#!/usr/bin/bash
# /usr/libexec/amethystora-browser-policy (or the copy named first) against a stand-in root, for 20-tests.sh:
# browser protection and data collection off, each on and off in either order, never dropping the other's
# policy, never touching a Firefox file that is not ours, and writing nothing a browser would take as an
# extension to install or a page to open. It needs root, as the helper does. The shipped policies are read
# from the folder named second.

set -euo pipefail

POLICY="${1:-/usr/libexec/amethystora-browser-policy}"
SHARE="${2:-/usr/share/amethystora/browser-policy}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
export AMETHYSTORA_BROWSER_ROOT="${T}" AMETHYSTORA_BROWSER_SHARE="${SHARE}"
export AMETHYSTORA_SECURITY_CONF="${T}/security.conf"
: >"${AMETHYSTORA_SECURITY_CONF}"
ARCH="$(uname -m)"
EXT="${T}/var/lib/flatpak/extension"
FIREFOX="${T}/etc/firefox/policies/policies.json"
FLATPAK="${EXT}/org.mozilla.firefox.systemconfig/${ARCH}/stable/policies/policies.json"
CHROMIUM_FILES=("${T}/etc/brave" "${T}/etc/opt/chrome" "${T}/etc/opt/edge" "${T}/etc/chromium")

fail() {
    echo "test-browser-policy: $*" >&2
    exit 1
}
# A state is "protection privacy": what both statuses say
state() { echo "$("${POLICY}" status) $("${POLICY}" status privacy)"; }
expect() {
    local got
    got="$(state)"
    [[ "${got}" == "$1" ]] || fail "$2: status says '${got}', not '$1'"
}
has() { [[ -e "$1" ]] || fail "$2: $1 is missing"; }
lacks() { [[ ! -e "$1" ]] || fail "$2: $1 is there"; }
# The jq filter $2 holds for the file $1
holds() { jq -e "$2" "$1" >/dev/null || fail "$3: $1 does not hold $2"; }
# What is written below the root, as the browsers would read it
check() {
    local protection="$1" privacy="$2" label="$3" dir file
    for dir in "${CHROMIUM_FILES[@]}"; do
        file="${dir}/policies/managed"
        if [[ "${protection}" == true ]]; then has "${file}/10-amethystora.json" "${label}"; else lacks "${file}/10-amethystora.json" "${label}"; fi
        if [[ "${privacy}" == true ]]; then
            has "${file}/11-amethystora-privacy.json" "${label}"
            holds "${file}/11-amethystora-privacy.json" '.MetricsReportingEnabled == false and .BraveP3AEnabled == false
                and (has("ExtensionInstallForcelist") | not) and (has("ExtensionInstallAllowlist") | not)' "${label}"
        else
            lacks "${file}/11-amethystora-privacy.json" "${label}"
        fi
    done
    for file in "${FIREFOX}" "${FLATPAK}"; do
        if [[ "${protection}" == false && "${privacy}" == false ]]; then lacks "${file}" "${label}"; continue; fi
        has "${file}" "${label}"
        holds "${file}" 'has("amethystora")' "${label}"
        if [[ "${protection}" == true ]]; then
            holds "${file}" '.policies | has("ExtensionSettings") and has("Preferences")' "${label}"
        else
            holds "${file}" '.policies | (has("ExtensionSettings") or has("Preferences")) | not' "${label}"
        fi
        if [[ "${privacy}" == true ]]; then
            holds "${file}" '.policies | .DisableTelemetry == true and .DisableFirefoxStudies == true
                and .FirefoxHome.Locked == false and .FirefoxSuggest.OnlineEnabled == false' "${label}"
        else
            holds "${file}" '.policies | (has("DisableTelemetry") or has("FirefoxHome") or has("FirefoxSuggest")) | not' "${label}"
        fi
        # Neither part installs an extension or touches a page the person sees first
        holds "${file}" '.policies | (has("Extensions") or has("Homepage") or has("NewTabPage") or has("OverrideFirstRunPage")) | not' "${label}"
    done
    # Firefox in a Flatpak does not update itself there, whichever part wrote the file
    if [[ "${protection}" == true || "${privacy}" == true ]]; then
        holds "${FLATPAK}" '.policies.DisableAppUpdate == true' "${label}"
        holds "${FIREFOX}" '.policies | has("DisableAppUpdate") | not' "${label}"
    fi
}

expect "off off" "to begin with"
check false false "to begin with"

# Privacy alone
"${POLICY}" privacy on >/dev/null
expect "off on" "privacy on"
check false true "privacy on"
# ...then protection beside it, and the extension list changes
"${POLICY}" on >/dev/null
expect "on on" "protection on"
check true true "both on"
"${POLICY}" allow keepassxc-browser@keepassxc.org >/dev/null
"${POLICY}" allow aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null
check true true "an extension allowed"
holds "${FIREFOX}" '.policies.ExtensionSettings["keepassxc-browser@keepassxc.org"].installation_mode == "allowed"' "allowed"
holds "${CHROMIUM_FILES[0]}/policies/managed/10-amethystora.json" '.ExtensionInstallAllowlist | index("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")' "allowed"
"${POLICY}" disallow aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null
holds "${CHROMIUM_FILES[0]}/policies/managed/10-amethystora.json" '.ExtensionInstallAllowlist | index("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") | not' "disallowed"
"${POLICY}" refresh >/dev/null
check true true "refreshed"
# Protection off leaves privacy's policies
"${POLICY}" off >/dev/null
expect "off on" "protection off"
check false true "protection off"
# Privacy off removes the last of it, and the folders made for it
"${POLICY}" privacy off >/dev/null
expect "off off" "privacy off"
check false false "privacy off"
[[ -z "$(find "${T}/etc/firefox" "${T}/etc/brave" "${T}/etc/chromium" "${T}/etc/opt" "${EXT}" -mindepth 1 2>/dev/null)" ]] ||
    fail "folders left behind: $(find "${T}/etc/firefox" "${T}/etc/brave" "${T}/etc/chromium" "${T}/etc/opt" "${EXT}" -mindepth 1)"

# The other order: protection first, then privacy on and off with protection on
"${POLICY}" on >/dev/null
check true false "protection alone"
"${POLICY}" privacy on >/dev/null
check true true "privacy after protection"
"${POLICY}" privacy off >/dev/null
expect "on off" "privacy off beside protection"
check true false "privacy off beside protection"
"${POLICY}" off >/dev/null
check false false "all off"

# What `show` prints is what is written: protection alone, privacy's part alone, the two together
"${POLICY}" show chromium | jq -e 'has("MetricsReportingEnabled") | not' >/dev/null || fail "show chromium holds privacy"
"${POLICY}" show chromium-privacy | jq -e '.DiagnosticData == 1 and .PersonalizationReportingEnabled == false' >/dev/null ||
    fail "show chromium-privacy"
"${POLICY}" show firefox-privacy |
    jq -e 'has("amethystora") and (.policies.DisableTelemetry == true) and (.policies | has("ExtensionSettings") | not)' >/dev/null ||
    fail "show firefox-privacy"
"${POLICY}" show firefox | jq -e '.policies | has("ExtensionSettings") and (has("DisableTelemetry") | not)' >/dev/null ||
    fail "show firefox holds privacy while it is off"
AMETHYSTORA_BROWSER_PRIVACY=/dev/null "${POLICY}" show firefox |
    jq -e '.policies | has("ExtensionSettings") and .DisableTelemetry == true' >/dev/null ||
    fail "show firefox leaves privacy out while it is on"

# A Firefox policy that is not ours is left alone, by either part, and the Chromium ones are written all the same
mkdir -p "${FIREFOX%/*}"
echo '{"policies":{"DisableTelemetry":false}}' >"${FIREFOX}"
"${POLICY}" privacy on >/dev/null 2>&1
has "${CHROMIUM_FILES[0]}/policies/managed/11-amethystora-privacy.json" "beside a Firefox policy that is not ours"
"${POLICY}" on >/dev/null 2>&1
"${POLICY}" privacy off >/dev/null 2>&1
"${POLICY}" off >/dev/null 2>&1
[[ "$(cat "${FIREFOX}")" == '{"policies":{"DisableTelemetry":false}}' ]] || fail "a Firefox policy that is not ours was changed"
lacks "${CHROMIUM_FILES[0]}/policies/managed/10-amethystora.json" "beside a Firefox policy that is not ours"
rm -f "${FIREFOX}"

# The two parts must never share a key in Firefox's policy: the merge fails rather than choose
BAD="${T}/share"
mkdir -p "${BAD}"
cp "${SHARE}"/*.json "${BAD}/"
jq '.policies.ExtensionSettings = {}' "${SHARE}/firefox-privacy.json" >"${BAD}/firefox-privacy.json"
if AMETHYSTORA_BROWSER_SHARE="${BAD}" AMETHYSTORA_BROWSER_PRIVACY=/dev/null "${POLICY}" show firefox >/dev/null 2>&1; then
    fail "the merge went on with a key both parts set"
fi

echo "test-browser-policy: ok"
