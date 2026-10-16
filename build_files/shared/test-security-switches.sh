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
# The profiles that look for new threats are what they say they are, and none turns on, or touches, what sends
# something to somebody else
"${CONFIG}" profile default
for profile in light balanced thorough; do
    "${CONFIG}" profile "${profile}"
    [[ "$("${CONFIG}" --profile)" == "${profile}" ]] || fail "profile ${profile} reads as $("${CONFIG}" --profile)"
    "${CONFIG}" --list --json | jq -e 'all(.settings[] | select(.sends | IN("none", "downloads") | not); .value == "off")' >/dev/null ||
        fail "profile ${profile} turned on something that sends away"
    [[ "$("${CONFIG}" WATCHER)" == on && "$("${CONFIG}" VIRUS_SCAN)" == weekly ]] || fail "profile ${profile} changed an existing key"
done
[[ "$("${CONFIG}" BEHAVIOUR)" == record && "$("${CONFIG}" NETWORK_FEEDS)" == hourly ]] || fail "thorough"
"${CONFIG}" set TRIAGE on
"${CONFIG}" profile light
[[ "$("${CONFIG}" TRIAGE)" == on && "$("${CONFIG}" --profile)" == light ]] || fail "a profile touched what sends away"
"${CONFIG}" profile default
[[ "$("${CONFIG}" TRIAGE)" == off ]] || fail "back to the defaults left what sends away on"
# Every setting is in the file, said or as a comment, where somebody editing it by hand finds it
for key in $("${CONFIG}" --list --json | jq -r '.settings[].key'); do
    grep -qE "^#?${key}=" /etc/amethystora/security.conf || fail "${key} is not in security.conf"
done
# Every setting is described, grouped, and says how it applies and what it sends
"${CONFIG}" --list --json | jq -e '.settings | length > 20 and all(.[];
    (.title | length > 0) and (.text | length > 0) and (.group | length > 0) and (.applies | length > 0)
    and ((.sends | IN("none", "downloads")) or (.explain | length > 0)) and (.value as $value | .allowed | index($value) != null))' >/dev/null ||
    fail "a setting with no description, group, applies or sends, or sending away with no explanation"

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
grep -qE -- '-k exec-watch$' "${SYSTEM_RULES}" "${HOME_RULES}" && fail "what is off as the image ships it got rules"
# Turned on, a rule for each writable folder there is, and none for one that is not there, which would stop
# auditctl at that line
mkdir -m 0700 "${R}/var/home/alice/.cache" "${R}/var/home/alice/Downloads"
chown 4300:4300 "${R}/var/home/alice/.cache" "${R}/var/home/alice/Downloads"
printf 'EXEC_WATCH=on\n' >"${T}/keys.conf"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
for dir in /tmp /var/tmp "${R}/var/home/alice/.cache" "${R}/var/home/alice/Downloads"; do
    grep -qxF -- "-a always,exit -F arch=b64 -S execve,execveat -F dir=${dir} -F auid>=1000 -F auid!=unset -k exec-watch" \
        "${SYSTEM_RULES}" "${HOME_RULES}" || fail "no rule on what runs from ${dir}"
done
grep -E '^-a .* -F (dir|path)=' "${SYSTEM_RULES}" "${HOME_RULES}" | grep -oE ' -F (dir|path)=[^ ]+' | cut -d= -f2 |
    while read -r path; do [[ -e "${path}" ]] || fail "a rule on ${path}, which is not there"; done
# An agent's runs are watched where its command leads, once for each folder, and never where a link takes it
# out of the home
A="${R}/var/home/alice"
mkdir -p "${A}/.local/bin" "${A}/.local/share/claude/versions" "${A}/.opencode/bin"
touch "${A}/.local/share/claude/versions/2.1.0" "${A}/.opencode/bin/opencode" "${A}/.local/bin/copilot"
ln -s "${A}/.local/share/claude/versions/2.1.0" "${A}/.local/bin/claude"
ln -s /usr/bin/true "${A}/.local/bin/codex"
chown -R -h 4300:4300 "${A}/.local" "${A}/.opencode"
printf 'AGENT_CLIS=on\n' >"${T}/keys.conf"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
AGENT_RULES="$(grep -- '-k agent-clis$' "${HOME_RULES}" | grep -oE 'dir=[^ ]+' | cut -d= -f2 | sort)"
[[ "${AGENT_RULES}" == "$(printf '%s\n' "${A}/.local/bin" "${A}/.local/share/claude/versions" "${A}/.opencode/bin" | sort)" ]] ||
    fail "the folders agents run from: ${AGENT_RULES}"
# Reading where secrets are kept: each file that is there, not a public key, the keyring's folder and the
# backup's password; and the decoy, made as the account, only ever its own, and taken back when off
mkdir -p "${A}/.ssh" "${A}/.local/share/keyrings" "${A}/.config/amethystora"
touch "${A}/.ssh/id_ed25519" "${A}/.ssh/id_ed25519.pub" "${A}/.npmrc" "${A}/.config/amethystora/backup-password"
echo 'RESTIC_PASSWORD_FILE="~/.config/amethystora/backup-password"' >"${A}/.config/amethystora/backup.env"
chown -R 4300:4300 "${A}/.ssh" "${A}/.local" "${A}/.config" "${A}/.npmrc"
printf 'CREDENTIALS=on\nDECOY=on\n' >"${T}/keys.conf"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
for rule in "path=${A}/.ssh/id_ed25519" "path=${A}/.npmrc" "dir=${A}/.local/share/keyrings" \
    "path=${A}/.config/amethystora/backup-password"; do
    grep -qxF -- "-a always,exit -F arch=b64 -F ${rule} -F perm=r -F auid>=1000 -F auid!=unset -k credentials" "${HOME_RULES}" ||
        fail "no rule on reading ${rule}"
done
grep -q 'id_ed25519.pub' "${HOME_RULES}" && fail "a rule on reading a public key"
# A browser's passwords, in a name no rule's path can hold: by inode and device
mkdir -p "${A}/.config/chromium/Default"
touch "${A}/.config/chromium/Default/Login Data"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
dev="$(findmnt -n -o MAJ:MIN --target "${A}/.config/chromium/Default/Login Data" | tr -d ' ')"
grep -qxF -- "-a always,exit -F arch=b64 -S open,openat,openat2 -F inode=$(stat -c %i "${A}/.config/chromium/Default/Login Data") -F devmajor=${dev%:*} -F devminor=${dev#*:} -F auid>=1000 -F auid!=unset -k credentials" "${HOME_RULES}" ||
    fail "no rule on opening Login Data: $(grep -F 'inode=' "${HOME_RULES}")"
[[ "$(stat -c '%u %a' "${A}/.ssh/id_backup")" == "4300 600" ]] || fail "the decoy is not the account's own, 0600"
grep -qxF -- "-a always,exit -F arch=b64 -F path=${A}/.ssh/id_backup -F perm=r -F auid>=1000 -F auid!=unset -k decoy" "${HOME_RULES}" ||
    fail "no rule on reading the decoy"
printf 'CREDENTIALS=on\n' >"${T}/keys.conf"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
[[ ! -e "${A}/.ssh/id_backup" ]] || fail "the decoy stayed with its switch off"
echo "a key of alice's own" >"${A}/.ssh/id_backup"
printf 'DECOY=on\n' >"${T}/keys.conf"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
grep -qx "a key of alice's own" "${A}/.ssh/id_backup" || fail "a key of the account's own was replaced by a decoy"
grep -q -- '-k decoy$' "${HOME_RULES}" && fail "a key of the account's own was taken for the decoy"
printf '' >"${T}/keys.conf"
AMETHYSTORA_SECURITY_CONF="${T}/keys.conf" AMETHYSTORA_AUDIT_ROOT="${R}" bash /usr/libexec/amethystora-audit-home-rules
[[ -e "${A}/.ssh/id_backup" ]] || fail "a key of the account's own was taken away"

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
"${HARDENING}" status --json | jq -e 'length >= 27 and all(.[]; (.title | length > 0) and (.text | length > 0) and
    (.state | IN("on", "off")) and (.default | IN("on", "off")))' >/dev/null || fail "the switches' status"
# Every switch the image ships a file for has that file, and a stricter switch is off until turned on
for rel in sysctl.d/61-amethystora-strict.conf modprobe.d/61-amethystora-strict.conf chrony.conf \
    modprobe.d/61-amethystora-no-bluetooth.conf modprobe.d/61-amethystora-no-webcam.conf \
    dconf/db/local.d/60-amethystora-automount dconf/db/local.d/locks/60-amethystora-user-extensions \
    systemd/user/org.gnome.Shell@.service.d/60-amethystora-no-x11.conf \
    polkit-1/rules.d/49-amethystora-flatpak-password.rules systemd/coredump.conf.d/60-amethystora-off.conf \
    environment.d/60-amethystora-cooldown.conf profile.d/amethystora-brew-attestations.sh; do
    [[ -n "$("${HARDENING}" expected "${rel}")" ]] || fail "nothing expected at /etc/${rel}"
done
for name in time firewall-away block-bluetooth flatpak-password package-cooldown boot-password; do
    "${HARDENING}" is-on "${name}" && fail "${name}, a stricter setting, is on by default"
done
"${HARDENING}" is-on kernel strict && fail "the kernel is strict by default"
"${HARDENING}" is-on kernel-args init_on_free=1 && fail "an extra kernel argument is on by default"
printf 'kernel strict\ntime\nkernel-args init_on_free=1\npackage-cooldown strict\n' >"${AMETHYSTORA_HARDENING_ROOT}/etc/amethystora/hardening-on"
# kernel is off from above: strict is kept for when it is on again
"${HARDENING}" is-on kernel strict || fail "kernel strict"
"${HARDENING}" is-on time || fail "a stricter setting turned on"
"${HARDENING}" is-on kernel-args init_on_free=1 || fail "an extra kernel argument turned on"
"${HARDENING}" is-on package-cooldown || fail "a level counts as on"
MANAGED="$("${HARDENING}" managed)"
grep -qxP 'sysctl.d/61-amethystora-strict.conf\tfile' <<<"${MANAGED}" || fail "managed: the strict kernel settings"
grep -qxP 'chrony.conf\tfile' <<<"${MANAGED}" || fail "managed: the time servers"
grep -qx 'server time.cloudflare.com iburst nts' <<<"$("${HARDENING}" expected chrony.conf)" || fail "the time servers use NTS"
COOLDOWN="$("${HARDENING}" expected environment.d/60-amethystora-cooldown.conf)"
grep -qx 'npm_config_min_release_age=7' <<<"${COOLDOWN}" && grep -qx 'npm_config_ignore_scripts=true' <<<"${COOLDOWN}" ||
    fail "the strict cooldown"
grep -qx 'export UV_EXCLUDE_NEWER="7 days"' <<<"$("${HARDENING}" expected profile.d/amethystora-cooldown.sh)" ||
    fail "the cooldown's shell form"
"${HARDENING}" status --json | jq -e 'any(.[]; .name == "package-cooldown" and .level == "strict") and any(.[]; .name == "kernel" and .level == "off") and
    any(.[]; .name == "kernel-args" and any(.arguments[]; .argument == "init_on_free=1" and .state == "on" and .default == "off"))' >/dev/null ||
    fail "levels and extra arguments in the status"
rm "${AMETHYSTORA_HARDENING_ROOT}/etc/amethystora/hardening-on"
REPORT="$(/usr/libexec/amethystora-security-status --json)"
for id in firewall kernel kernel-args; do
    jq -e --arg id "${id}" 'any(.checks[]; .id == $id and .state == "info" and .command != null and .switched_off)' <<<"${REPORT}" >/dev/null ||
        fail "${id} switched off is not shown as turned off"
done
# A stricter setting that is on is named in the report, in case it is why something stopped working
printf 'block-webcam\n' >"${AMETHYSTORA_HARDENING_ROOT}/etc/amethystora/hardening-on"
/usr/libexec/amethystora-security-status --json | jq -e 'any(.checks[]; .id == "stricter" and .state == "info" and
    any(.details[]; . == "No webcam"))' >/dev/null || fail "the report does not name a stricter setting that is on"
unset AMETHYSTORA_HARDENING_ROOT

# --- Accepted checks -----------------------------------------------------------------------------------

ALLOW=/usr/libexec/amethystora-security-allow
export AMETHYSTORA_ALLOW_ROOT="${T}/allow"
for entry in "secure boot check" "secure-boot ok" "x;rm check" $'secure-boot check\nfirewall check'; do
    "${ALLOW}" add report "${entry}" 2>/dev/null && fail "the allowlist took \"${entry}\""
done
# A path, or a glob of them from every home, for what the audit log's keys find; never a line that is not one
"${ALLOW}" --features | grep -qx persistence || fail "persistence has no allowlist"
GLOB='~/.local/share/gnome-shell/extensions/*'
"${ALLOW}" add persistence "${GLOB}" || fail "the allowlist refused a glob of paths"
grep -qxF "${GLOB}" <<<"$("${ALLOW}" list persistence)" || fail "the allowlist did not keep a glob of paths"
for entry in "relative/path" $'/a\nb' $'/a\e[2J' ""; do
    "${ALLOW}" add persistence "${entry}" 2>/dev/null && fail "the allowlist took $(printf '%q' "${entry}")"
done
"${ALLOW}" remove persistence "${GLOB}"
grep -qxF "${GLOB}" <<<"$("${ALLOW}" list persistence)" && fail "removing a path from the allowlist"
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

# The networks named home, and only those, are in the home zone, the one zone open to phone pairing; one no
# longer named goes back to the default zone, and with none named there is no list
mkdir -p "${T}/stubs"
cat >"${T}/stubs/nmcli" <<'EOF'
#!/usr/bin/bash
case "$1 $2" in
    "-g connection.zone") sed -n "s/^$5 //p" "${NMCLI_ZONES}" ;;
    "connection modify") sed -i "/^$3 /d" "${NMCLI_ZONES}"; echo "$3 $5" >>"${NMCLI_ZONES}" ;;
esac
EOF
chmod 0755 "${T}/stubs/nmcli"
export NMCLI_ZONES="${T}/zones"
: >"${NMCLI_ZONES}"
export AMETHYSTORA_HARDENING_ROOT="${T}/hardening"
: >"${AMETHYSTORA_HARDENING_ROOT}/etc/amethystora/hardening-off"
HOMES="${AMETHYSTORA_HARDENING_ROOT}/etc/amethystora/firewall-home"
ONE=11111111-1111-1111-1111-111111111111 TWO=22222222-2222-2222-2222-222222222222
PATH="${T}/stubs:${PATH}" "${HARDENING}" home "${ONE}" "${TWO}" "x;rm" || fail "naming home networks"
grep -qx "${ONE} amethystora-home" "${NMCLI_ZONES}" && grep -qx "${TWO} amethystora-home" "${NMCLI_ZONES}" ||
    fail "the networks named home are not in the home zone: $(cat "${NMCLI_ZONES}")"
[[ "$(cat "${HOMES}")" == "${ONE}"$'\n'"${TWO}" ]] || fail "the list of home networks: $(cat "${HOMES}")"
PATH="${T}/stubs:${PATH}" "${HARDENING}" home "${TWO}" || fail "naming fewer home networks"
grep -qx "${ONE} " "${NMCLI_ZONES}" || fail "a network no longer home kept the home zone"
PATH="${T}/stubs:${PATH}" "${HARDENING}" home || fail "naming no home network"
[[ ! -e "${HOMES}" ]] || fail "with no home network named, a list is left"
firewall-offline-cmd --zone=amethystora --query-service=kdeconnect >/dev/null && fail "the default zone is open to phone pairing"
firewall-offline-cmd --zone=amethystora-home --query-service=kdeconnect >/dev/null || fail "the home zone is closed to phone pairing"

echo "test-security-switches: every switch, off and on"
