#!/usr/bin/bash
# Reaching into other programs' memory on a real machine. proc_mem.force_override=ptrace is on the command line,
# so a program cannot write over its own code through /proc/self/mem. With INJECTION on (its rules or the
# sensor's program come with the next boot), a program of the test account's own session that attaches to a
# program it did not start is refused, and said; one that attaches to its own child, reads and writes the child's
# memory and opens its /proc/PID/mem for writing is said each time; and the same between two processes of one
# Flatpak is recorded and not said. The session's programs are user services (in_session), as the sensor has to
# count them: their login uid is the account's.
source "$(dirname "$0")/lib.sh"

HISTORY=/var/log/amethystora-security-events.jsonl
config=/usr/libexec/amethystora-security-config
SCRIPT=/var/lib/vmlab-tests/inject.py

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi

if [[ "${SUITE_PHASE}" == 1 ]]; then
    # What the desktop did by itself since this boot, with INJECTION on as the thorough profile has it (30 turns it
    # on, and nothing before this suite turns it off): a restart, a login and every suite since, recorded, never said
    if [[ "$("${config}" INJECTION)" == on ]]; then
        systemctl start amethystora-security-watch.service
        said="$(jq -r --argjson boot "$(date -d "$(uptime -s)" +%s)" \
            'select(.key == "injection" and .level != "quiet" and .time >= $boot) | "\(.level): \(.text)"' "${HISTORY}" 2>/dev/null)"
        [[ -z "${said}" ]] && ok "with INJECTION on since this boot, nothing the desktop did by itself was said" ||
            not_ok "INJECTION said what the desktop did by itself" "$(head -n 10 <<<"${said}")"
    else
        skip "INJECTION was not on before this suite (30 turns the thorough profile on)"
    fi
    grep -qw "proc_mem.force_override=ptrace" /proc/cmdline && ok "proc_mem.force_override=ptrace is on the command line" ||
        not_ok "proc_mem.force_override=ptrace is not on the command line" "$(cat /proc/cmdline)"
    # A write over its own code, the same byte as is there: refused without a debugger attached (EIO)
    out="$(python3 - <<'PY'
start = next(int(line.split("-")[0], 16) for line in open("/proc/self/maps") if " r-xp " in line)
with open("/proc/self/mem", "r+b", buffering=0) as mem:
    mem.seek(start)
    byte = mem.read(1)
    mem.seek(start)
    try:
        mem.write(byte)
        print("written")
    except OSError as error:
        print("refused", error.errno)
PY
)"
    [[ "${out}" == "refused 5" ]] && ok "a program cannot write over its own code through /proc/self/mem" ||
        not_ok "a write over its own code through /proc/self/mem: ${out}"
    check "INJECTION goes on" "${config}" set INJECTION on
    reboot_and_continue
fi

plan=/run/amethystora/sensor/plan
if grep -qx "injection sensor" "${plan}" 2>/dev/null; then
    ok "the sensor watches injection"
    wait_for 120 test -f /run/amethystora/sensor/ready && ok "the sensor finished registering" ||
        not_ok "the sensor did not become ready within 120 s"
elif auditctl -l 2>/dev/null | grep -q -- "-k injection"; then
    ok "the audit rules watch injection (no sensor on this kernel)"
else
    not_ok "nothing watches injection" "plan: $(cat "${plan}" 2>/dev/null | tr '\n' ' ')"
fi

# The test program: someone else's process attached to (refused), then its own child attached to, its memory
# read and written back as it was, and its /proc/PID/mem opened for writing
install -d -m 0755 /var/lib/vmlab-tests
cat >"${SCRIPT}" <<'PY'
import ctypes, os, subprocess, sys, time

libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.argtypes = [ctypes.c_long, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]


class iovec(ctypes.Structure):
    _fields_ = [("base", ctypes.c_void_p), ("len", ctypes.c_size_t)]


for call in (libc.process_vm_readv, libc.process_vm_writev):
    call.argtypes = [ctypes.c_int, ctypes.POINTER(iovec), ctypes.c_ulong, ctypes.POINTER(iovec), ctypes.c_ulong,
                     ctypes.c_ulong]
    call.restype = ctypes.c_ssize_t
PTRACE_ATTACH, PTRACE_DETACH = 16, 17

if len(sys.argv) > 1:
    print("foreign attach", libc.ptrace(PTRACE_ATTACH, int(sys.argv[1]), None, None), ctypes.get_errno())
child = subprocess.Popen(["sleep", "60"])
time.sleep(0.5)
if len(sys.argv) > 1:
    print("attach", libc.ptrace(PTRACE_ATTACH, child.pid, None, None), ctypes.get_errno())
    os.waitpid(child.pid, 0)
    libc.ptrace(PTRACE_DETACH, child.pid, None, None)
start = next(int(line.split("-")[0], 16) for line in open(f"/proc/{child.pid}/maps") if line.rstrip().endswith("[stack]"))
buf = ctypes.create_string_buffer(8)
local, remote = iovec(ctypes.addressof(buf), 8), iovec(start, 8)
print("read", libc.process_vm_readv(child.pid, ctypes.byref(local), 1, ctypes.byref(remote), 1, 0))
print("write", libc.process_vm_writev(child.pid, ctypes.byref(local), 1, ctypes.byref(remote), 1, 0))
if len(sys.argv) > 1:
    with open(f"/proc/{child.pid}/mem", "r+b", buffering=0):
        print("mem opened")
child.kill()
PY
chmod 0644 "${SCRIPT}"

check "the security watcher primes" systemctl start amethystora-security-watch.service
before="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"
user_bus systemd-run --user --unit=vmlab-target sleep 600 >/dev/null 2>&1
TARGET="$(user_systemctl show -p MainPID --value vmlab-target)"
out="$(in_session "python3 ${SCRIPT} ${TARGET}" 2>&1)"
echo "${out}" | sed 's/^/# /'
grep -q "^foreign attach -1 1$" <<<"${out}" && ok "an attach to a process the account did not start is refused" ||
    not_ok "the attach to someone else's process" "${out}"
grep -q "^attach 0 " <<<"${out}" && grep -q "^write 8$" <<<"${out}" && grep -q "^mem opened$" <<<"${out}" &&
    ok "its own child: attached to, written into, its memory opened" || not_ok "its own child" "${out}"
user_systemctl stop vmlab-target 2>/dev/null

# Two processes of one Flatpak, each the other's own business: the sandbox's own python and its child
APP="$(flatpak list --system --app --columns=application,runtime | awk '$2 ~ /^org\.gnome\.Platform\// { print $1; exit }')"
if [[ -n "${APP}" ]]; then
    out="$(in_session "flatpak run --command=python3 ${APP} -c \"\$(cat ${SCRIPT})\"" 2>&1)"
    echo "${out}" | sed 's/^/# in the Flatpak: /'
    grep -q "^write 8$" <<<"${out}" && ok "in ${APP}'s sandbox, a process wrote into its child's memory" ||
        not_ok "in ${APP}'s sandbox" "${out}"
else
    skip "no app on the GNOME runtime to run python3 in"
fi

sleep 4
check "the security watcher runs" systemctl start amethystora-security-watch.service
found="$(tail -n +"$((before + 1))" "${HISTORY}" 2>/dev/null | jq -c 'select(.key == "injection")')"
expect() {
    if jq -e -s "any(.[]; $2)" <<<"${found}" >/dev/null 2>&1; then ok "$1"; else not_ok "$1" "$(jq -r -s '.[] | "\(.level) \(.tactic): \(.text)"' <<<"${found}")"; fi
}
expect "the refused attach is said" '.level == "normal" and (.text | test("tried to reach into .* and the kernel refused it"))'
expect "the attach to its own child is said" '.level == "normal" and (.text | test("attached to /usr/bin/sleep"))'
expect "the write into the child's memory is said" '.level == "normal" and .tactic == "Defense Evasion" and (.text | test("wrote into the memory of /usr/bin/sleep"))'
expect "the read of the child's memory is said" '.level == "normal" and .tactic == "Credential Access" and (.text | test("read the memory of /usr/bin/sleep"))'
if grep -qx "injection sensor" "${plan}" 2>/dev/null; then
    expect "the child's /proc/PID/mem opened for writing is said" '.level == "normal" and (.text | test("opened for writing the memory of /usr/bin/sleep"))'
    [[ -n "${APP}" ]] && expect "the sandbox's own business is recorded and not said" '.level == "quiet" and (.text | test("wrote into the memory of"))'
fi
echo "# INJECTION's part of that run: $(jq -r '.timings.INJECTION' /var/lib/amethystora/security/status.json) ms"

# What the sensor's program costs everything else: every read of /proc/PID/stat asks the same hook, and the
# program returns at once unless the mode attaches. INJECTION off and on in turn, the sensor started again on a
# plan without or with it (it reads the plan as it starts), medians of four rounds: /proc/PID/stat read as root,
# who reaches the hook for every process, and find /usr, which 37 measures
if grep -qx "injection sensor" "${plan}" 2>/dev/null; then
    cp "${plan}" /run/vmlab-plan
    restart_sensor() {
        systemctl kill -s KILL amethystora-sensor.service
        rm -f /run/amethystora/sensor/ready
        wait_for 60 test -f /run/amethystora/sensor/ready
    }
    proc_read() {
        python3 -I -c '
import os, time
pids = [p for p in os.listdir("/proc") if p.isdigit()]
n, start = 0, time.perf_counter()
for _ in range(200):
    for p in pids:
        try:
            with open(f"/proc/{p}/stat", "rb") as f:
                f.read()
            n += 1
        except OSError:
            pass
print(f"{(time.perf_counter() - start) / max(n, 1) * 1e6:.2f}")'
    }
    : >/run/vmlab-cost
    for round in 1 2 3 4; do
        for state in off on; do
            if [[ "${state}" == on ]]; then cp /run/vmlab-plan "${plan}"; else grep -vx "injection sensor" /run/vmlab-plan >"${plan}"; fi
            restart_sensor || not_ok "the sensor did not come back with injection ${state}"
            echo "${state} $(proc_read) $( { /usr/bin/time -f '%e' find /usr -xdev >/dev/null; } 2>&1 | tail -n1)" >>/run/vmlab-cost
        done
    done
    median() { awk -v s="$1" -v c="$2" '$1 == s { print $c }' /run/vmlab-cost | sort -n | awk '{ a[NR] = $1 } END { print (a[2] + a[3]) / 2 }'; }
    echo "# /proc/PID/stat read, INJECTION off / on: $(median off 2) / $(median on 2) µs"
    echo "# find /usr, INJECTION off / on: $(median off 3) / $(median on 3) s"
    cp /run/vmlab-plan "${plan}"
    restart_sensor && ok "the sensor is back with its own plan" || not_ok "the sensor did not come back with its own plan"
fi

"${config}" set INJECTION off
rm -f "${SCRIPT}"
finish
