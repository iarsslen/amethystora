#!/usr/bin/bash
# Browsers' data collection off (plans/done/PLAN-browser-telemetry.md): `ame security browser privacy` as a person
# runs it, its policy read back from a running Firefox through Marionette (its enterprise policies, the
# preferences they lock, the studies feature) and not only as a file; browser protection turned on and off beside
# it without dropping it, then privacy off, and the policy folders as empty as the image ships them. The report's
# check and the security watcher see exactly what the switch wrote and say nothing louder than a note.
# vmlab-paths: @sf/usr/libexec/amethystora-browser-policy @sf/usr/share/amethystora/browser-policy/*
source "$(dirname "$0")/lib.sh"

HOME_DIR="/var/home/${TEST_USER}"
H=/usr/libexec/amethystora-browser-policy
FIREFOX=/etc/firefox/policies/policies.json
WATCH_STATUS=/var/lib/amethystora/security/status.json
STATE=/var/lib/vmlab-tests/99-browser-privacy
SUITES="$(dirname "$0")"
mkdir -p "${STATE}"
SERIAL=0

if ! getent passwd "${TEST_USER}" >/dev/null; then
    skip "no account ${TEST_USER} (10-account.sh)"
    finish
fi

# The watcher's drift that was not there before this suite
new_drift() {
    systemctl start amethystora-security-watch.service
    jq -r '.drift // [] | .[] | "\(.change) \(.path)"' "${WATCH_STATUS}" | grep -vxF -f "${STATE}/drift.base" || true
}
watcher_accepts() {
    local drift
    drift="$(new_drift)"
    if [[ -z "${drift}" ]]; then ok "the security watcher accepts what the switch wrote ($1)"; else
        not_ok "the security watcher sees drift ($1)" "${drift}"; fi
}
: >"${STATE}/drift.base"
new_drift >"${STATE}/drift.base"

report_state() { /usr/libexec/amethystora-security-status --json | jq -r --arg id "$1" '.checks[] | select(.id == $id) | .state'; }
states() { echo "$("${H}" status) $("${H}" status privacy)"; }

# What a Firefox that has just started on a new profile makes of its policies, as one JSON object
firefox_says() {
    local profile="${HOME_DIR}/vmlab-ff-privacy-$((++SERIAL))" out
    pkill -u "${TEST_USER}" -x firefox || true
    as_user "mkdir -p ${profile} && (MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1 nohup firefox --headless --no-remote --marionette --remote-allow-system-access \
        --profile ${profile} about:blank >${profile}/out.log 2>&1 &)"
    out="$(python3 "${SUITES}/marionette.py" 2828 2>&1)" || { echo "${out}" >&2; pkill -u "${TEST_USER}" -x firefox || true; return 1; }
    pkill -u "${TEST_USER}" -x firefox || true
    wait_for 30 bash -c "! pgrep -u ${TEST_USER} -x firefox"
    echo "${out}"
}

# --- As the image ships it ---------------------------------------------------------------------------------
check "data collection off is off as the image ships" test "$("${H}" status privacy)" == off
check "...and so is browser protection" test "$("${H}" status)" == off
check "the report says so" test "$(report_state browser-privacy)" == off
check "the image has no Firefox policy file" test ! -e "${FIREFOX}"
base="$(firefox_says)" || base=""
if [[ -n "${base}" ]]; then
    echo "# Firefox as Fedora builds it: ${base}"
    if jq -e '(.policies | index("DisableTelemetry") | not) and .uploadLocked == false and .shield != false' <<<"${base}" >/dev/null; then
        ok "Firefox as Fedora builds it holds no policy of data collection, and its settings are the person's"
    else
        not_ok "Firefox as Fedora builds it" "${base}"
    fi
else
    not_ok "Firefox answers over Marionette with no policy file" "$(tail -n 5 "${HOME_DIR}"/vmlab-ff-privacy-1/out.log 2>&1)"
fi

# --- On, as a person types it ---------------------------------------------------------------------------------
check "ame security browser privacy on" in_terminal 120 "Turn browsers" y -- ame security browser privacy on
check "its state is on" test "$("${H}" status privacy)" == on
check "...and protection is not" test "$("${H}" status)" == off
check "the report says on" test "$(report_state browser-privacy)" == on
check "Firefox's policy holds the telemetry and studies off" jq -e '.policies.DisableTelemetry == true and .policies.DisableFirefoxStudies == true
    and (.policies | has("ExtensionSettings") | not)' "${FIREFOX}"
check "Chrome's, Chromium's, Brave's and Edge's folders hold their own file" bash -c \
    'for d in /etc/brave /etc/opt/chrome /etc/opt/edge /etc/chromium; do jq -e ".MetricsReportingEnabled == false" "$d/policies/managed/11-amethystora-privacy.json" || exit 1; done'
check "...and none of protection's" bash -c '! ls /etc/brave/policies/managed/10-amethystora.json /etc/chromium/policies/managed/10-amethystora.json 2>/dev/null'
on="$(firefox_says)" || on=""
echo "# Firefox with data collection off: ${on}"
if jq -e '(.policies | index("DisableTelemetry")) and (.policies | index("DisableFirefoxStudies")) and .upload == false
    and .uploadLocked == true and .usage != true and .shield == false and .sponsoredTopSites == false
    and .sponsoredStories == false and .sponsoredLocked == false' <<<"${on}" >/dev/null 2>&1; then
    ok "Firefox applies it: Telemetry and its usage ping off and locked, studies off, sponsored shortcuts and stories off and not locked"
else
    not_ok "Firefox does not apply the policy" "${on}"
fi
if jq -e '.online != true' <<<"${on}" >/dev/null 2>&1; then ok "...and suggestions fetched while typing are off (or Firefox has none here)"; else
    not_ok "online suggestions are still on" "${on}"; fi
watcher_accepts "privacy on"

# --- Protection beside it ----------------------------------------------------------------------------------
check "browser protection on" "${H}" on
check "both are on" test "$(states)" == "on on"
check "Firefox's one file holds both" jq -e '.policies | has("ExtensionSettings") and .DisableTelemetry == true' "${FIREFOX}"
check "...and Chromium's folder both files" ls /etc/chromium/policies/managed/10-amethystora.json /etc/chromium/policies/managed/11-amethystora-privacy.json
both="$(firefox_says)" || both=""
if jq -e '(.policies | index("DisableTelemetry")) and (.policies | index("ExtensionSettings")) and .upload == false' <<<"${both}" >/dev/null 2>&1; then
    ok "Firefox applies both"
else
    not_ok "Firefox does not apply both" "${both}"
fi
watcher_accepts "both on"
check "protection off keeps data collection off" "${H}" off
check "...privacy is still on" test "$(states)" == "off on"
check "...in Firefox's file, alone" jq -e '.policies.DisableTelemetry == true and (.policies | has("ExtensionSettings") | not)' "${FIREFOX}"
"${H}" on >/dev/null
check "privacy off beside protection" "${H}" privacy off
check "...keeps protection" test "$(states)" == "on off"
check "...in Firefox's file, alone" jq -e '.policies | has("ExtensionSettings") and (has("DisableTelemetry") | not)' "${FIREFOX}"
"${H}" off >/dev/null

# --- Off, as a person types it ---------------------------------------------------------------------------------
"${H}" privacy on >/dev/null
check "ame security browser privacy off" ame security browser privacy off
check "it is off" test "$("${H}" status privacy)" == off
check "the report says off" test "$(report_state browser-privacy)" == off
check "no policy file or folder is left" bash -c '! find /etc/firefox /etc/brave /etc/chromium /etc/opt/chrome /etc/opt/edge \( -name policies -o -name "*amethystora*" \) | grep -q .'
check "the marker is gone" test ! -e /etc/amethystora/browser-privacy
off="$(firefox_says)" || off=""
if jq -e '(.policies | index("DisableTelemetry") | not) and .uploadLocked == false' <<<"${off}" >/dev/null 2>&1; then
    ok "Firefox is as Fedora builds it again"
else
    not_ok "Firefox still holds the policy" "${off}"
fi
watcher_accepts "privacy off"
finish
