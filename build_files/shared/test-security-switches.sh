#!/usr/bin/bash
# Every security feature is a switch, and off costs nothing and is not a fault, for 20-tests.sh: the
# settings helper, the audit rules a key that is off leaves out, the conditions the units read, the report
# with everything off, the prevention switches and accepted checks, each against stand-ins in a temporary
# folder. Nothing here writes to /etc or /var: a build must not leave /var/lib behind.

set -euo pipefail

CONFIG=/usr/libexec/amethystora-security-config
T="$(realpath "$(mktemp -d)")"
trap 'rm -rf "${T}"' EXIT
# The stand-in account makes its folders as itself, through here
chmod 0755 "${T}"
export AMETHYSTORA_SECURITY_CONF="${T}/security.conf"
export AMETHYSTORA_SECURITY_NOTES="${T}/notes"
cp /etc/amethystora/security.conf "${AMETHYSTORA_SECURITY_CONF}"
fail() { echo "test-security-switches: $*" >&2; exit 1; }

# --- The settings helper ----------------------------------------------------------------------------

[[ "$("${CONFIG}" WATCHER)" == on && "$("${CONFIG}" VIRUS_SCAN)" == weekly ]] || fail "defaults"
[[ "$("${CONFIG}" --profile)" == default ]] || fail "the shipped file is not the default profile"
"${CONFIG}" --is VIRUS_SCAN manual weekly || fail "--is with two values"
"${CONFIG}" --is VIRUS_SCAN off && fail "--is matched a value it is not"
# A value it does not know is the default, and a key it does not know is refused
echo "VIRUS_SCAN=everything" >>"${AMETHYSTORA_SECURITY_CONF}"
[[ "$("${CONFIG}" VIRUS_SCAN)" == weekly ]] || fail "an unknown value is not the default"
"${CONFIG}" NOT_A_KEY >/dev/null 2>&1 && fail "an unknown key was read"
# The halves of REALTIME follow it until they are set themselves
"${CONFIG}" set REALTIME on
[[ "$("${CONFIG}" REALTIME_SCAN)" == on && "$("${CONFIG}" REALTIME_WATCH)" == on ]] || fail "the halves do not follow REALTIME"
"${CONFIG}" set REALTIME_SCAN off
[[ "$("${CONFIG}" REALTIME_SCAN)" == off && "$("${CONFIG}" REALTIME_WATCH)" == on ]] || fail "a half set alone"
"${CONFIG}" set REALTIME off
[[ "$("${CONFIG}" REALTIME_WATCH)" == off ]] || fail "setting REALTIME sets both halves"
grep -qP '\trealtime\toff\t' "${AMETHYSTORA_SECURITY_NOTES}" || fail "set left no note"
"${CONFIG}" set VIRUS_SCAN sometimes 2>/dev/null && fail "set took a value the key does not have"
# Off is every key that can be off, and default every key as shipped
"${CONFIG}" profile off
[[ "$("${CONFIG}" --profile)" == off ]] || fail "profile off"
while IFS='=' read -r key value; do
    [[ "${value}" == off ]] || ! "${CONFIG}" --list --json | jq -e --arg key "${key}" \
        '.settings[] | select(.key == $key) | .allowed | index("off")' >/dev/null ||
        fail "profile off left ${key}=${value}"
done < <("${CONFIG}" --all)
[[ "$("${CONFIG}" ON_DETECTION)" == report ]] || fail "profile off changed what scans do with a find"
# Every setting is described, grouped, and says how it applies and what it sends
"${CONFIG}" --list --json | jq -e '.settings | length > 20 and all(.[];
    (.title | length > 0) and (.text | length > 0) and (.group | length > 0) and (.applies | length > 0)
    and (.sends | IN("none", "downloads")) and (.value as $value | .allowed | index($value) != null))' >/dev/null ||
    fail "a setting with no description, group, applies or sends"

# --- The units read their keys ------------------------------------------------------------------------

AMETHYSTORA_SECURITY_CONF=/dev/null /usr/libexec/amethystora-clamav-scan --check || fail "the weekly scan is off by default"
echo "VIRUS_SCAN=manual" >"${T}/manual.conf"
AMETHYSTORA_SECURITY_CONF="${T}/manual.conf" /usr/libexec/amethystora-clamav-scan --check ||
    fail "a scan asked for while the scanner is manual"
AMETHYSTORA_SECURITY_CONF="${T}/manual.conf" TRIGGER_UNIT=amethystora-clamav-scan.timer \
    /usr/libexec/amethystora-clamav-scan --check && fail "the timer scanned while the scanner is manual"
echo "VIRUS_SCAN=off" >"${T}/off.conf"
AMETHYSTORA_SECURITY_CONF="${T}/off.conf" /usr/libexec/amethystora-clamav-scan --check && fail "scanned while off"
printf 'WATCHER=off\nNETWORK=watch\nREALTIME=on\n' >"${T}/watcher.conf"
AMETHYSTORA_SECURITY_CONF="${T}/watcher.conf" /usr/libexec/amethystora-security-realtime --check &&
    fail "real-time watching runs with the watcher off"

# --- The audit rules leave out a key that is off ------------------------------------------------------

R="${T}/root"
mkdir -p "${R}/etc/audit/rules.d" "${R}/var/home"
: >"${R}/etc/passwd"
mkdir -m 0700 "${R}/var/home/alice"
chown 4300:4300 "${R}/var/home/alice"
echo "alice:x:4300:4300::${R}/var/home/alice:/bin/bash" >>"${R}/etc/passwd"
printf 'INPUT_CAPTURE=off\nPERSISTENCE=off\n' >"${T}/keys.conf"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
SYSTEM_RULES="${R}/etc/audit/rules.d/60-amethystora.rules"
HOME_RULES="${R}/etc/audit/rules.d/61-amethystora-home.rules"
grep -qE -- '-k (input-capture|persistence)$' "${SYSTEM_RULES}" "${HOME_RULES}" && fail "a key that is off got rules"
grep -qE -- '-k identity$' "${SYSTEM_RULES}" || fail "a key that is on got none"
grep -qE -- '-k user-programs$' "${HOME_RULES}" || fail "the home's own key that is on got none"
grep -qvE '^-(w|a) ' <<<"$(grep -vE '^[[:space:]]*(#|$)' "${SYSTEM_RULES}")" && fail "a line auditctl cannot read"
[[ -e "${R}/var/home/alice/.config/autostart" ]] && fail "a folder made for a key that is off"

# --- The report: off is not a fault ------------------------------------------------------------------

"${CONFIG}" profile off
REPORT="$(/usr/libexec/amethystora-security-status --json)"
jq -e '[.checks[] | select(.id | IN("security-watcher", "audit-log", "audit-rules", "virus-scan",
    "virus-scan-schedule", "signatures", "settings-audit", "listeners", "image-settings", "setuid-sweep",
    "realtime-running")) | select(.state == "check" or .state == "off")] | length == 0' <<<"${REPORT}" >/dev/null ||
    fail "the report warns about a feature that was switched off"
for id in security-watcher audit-log virus-scan settings-audit listeners image-settings setuid-sweep; do
    jq -e --arg id "${id}" 'any(.checks[]; .id == $id and .state == "info" and .command != null and .switched_off)' <<<"${REPORT}" >/dev/null ||
        fail "${id} does not say it is turned off, with the command that turns it on"
done
jq -e '.settings.profile == "off" and .settings.virus_scan == "off"' <<<"${REPORT}" >/dev/null || fail "the report's settings"

# --- The prevention switches ----------------------------------------------------------------------------

HARDENING=/usr/libexec/amethystora-hardening
export AMETHYSTORA_HARDENING_ROOT="${T}/hardening"
mkdir -p "${AMETHYSTORA_HARDENING_ROOT}/etc/amethystora"
"${HARDENING}" is-on firewall || fail "a prevention switch is off by default"
[[ -z "$("${HARDENING}" managed)" ]] || fail "a switch that is on manages a file"
printf 'kernel\nfirewall\nkernel-args init_on_alloc=1\n' >"${AMETHYSTORA_HARDENING_ROOT}/etc/amethystora/hardening-off"
"${HARDENING}" is-on firewall && fail "firewall is off"
"${HARDENING}" is-on kernel-args init_on_alloc=1 && fail "one kernel argument is off"
"${HARDENING}" is-on kernel-args slab_nomerge || fail "the other kernel arguments are on"
# Read whole before matching: grep -q stops reading at the first match, and pipefail would count the
# writer's broken pipe as a failure
MANAGED="$("${HARDENING}" managed)"
grep -qxP 'sysctl.d/60-amethystora-hardening.conf\tmask' <<<"${MANAGED}" || fail "managed: the kernel's mask"
grep -qxP 'firewalld/firewalld.conf\tfile' <<<"${MANAGED}" || fail "managed: the firewall's file"
grep -qx 'deny = 0' <<<"$("${HARDENING}" expected security/faillock.conf)" || fail "lockout off is deny = 0"
grep -qx 'DefaultZone=FedoraWorkstation' <<<"$("${HARDENING}" expected firewalld/firewalld.conf)" || fail "the zone off"
grep -qE '^(sockets|devices)=' <<<"$("${HARDENING}" expected flatpak/overrides/global)" && fail "the sandbox off keeps a denial"
"${HARDENING}" status --json | jq -e 'length == 10 and all(.[]; (.title | length > 0) and (.state | IN("on", "off")))' >/dev/null ||
    fail "the switches' status"
REPORT="$(/usr/libexec/amethystora-security-status --json)"
for id in firewall kernel kernel-args; do
    jq -e --arg id "${id}" 'any(.checks[]; .id == $id and .state == "info" and .command != null and .switched_off)' <<<"${REPORT}" >/dev/null ||
        fail "${id} switched off is not shown as turned off"
done
unset AMETHYSTORA_HARDENING_ROOT

# --- Accepted checks -----------------------------------------------------------------------------------

ALLOW=/usr/libexec/amethystora-security-allow
export AMETHYSTORA_ALLOW_ROOT="${T}/allow"
for entry in "secure boot check" "secure-boot ok" "x;rm check" $'secure-boot check\nfirewall check'; do
    "${ALLOW}" add report "${entry}" 2>/dev/null && fail "the allowlist took \"${entry}\""
done
"${CONFIG}" profile default
OPEN="$(/usr/libexec/amethystora-security-status --json |
    jq -r 'first(.checks[] | select(.group != "optional" and (.state == "check" or .state == "off")) | "\(.id) \(.state)")')"
if [[ -n "${OPEN}" ]]; then
    "${ALLOW}" add report "${OPEN}"
    grep -qxF "${OPEN}" <<<"$("${ALLOW}" list report)" || fail "the allowlist did not keep ${OPEN}"
    /usr/libexec/amethystora-security-status --json | jq -e --arg id "${OPEN% *}" --arg was "${OPEN#* }" \
        'any(.checks[]; .id == $id and .state == "info" and .accepted == $was)' >/dev/null ||
        fail "an accepted check is still a warning"
    "${ALLOW}" remove report "${OPEN}"
    [[ -z "$("${ALLOW}" list report)" ]] || fail "removing from the allowlist"
fi

echo "test-security-switches: every switch, off and on"
