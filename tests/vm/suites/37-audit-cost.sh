#!/usr/bin/bash
# The point of the sensor: once it covers every watched key, the kernel audits no system call, so stat- and
# open-heavy work pays nothing for the watching (plans/done/PLAN-audit-cost.md section 7). This records
# find /usr and a stat loop for the run report; the rigorous A/B against the base image is the perf lab's.
# Only meaningful on a boot the sensor took over.
source "$(dirname "$0")/lib.sh"

if ! grep -qx 'identity sensor' /run/amethystora/sensor/plan 2>/dev/null; then
    skip "the sensor did not take this boot; cost is the audit rules' as before"
    finish
fi

# No per-syscall audit rule is loaded: the kernel's audit filter is the task filter and nothing else, which
# is what makes every system call cost nothing extra.
loaded="$(auditctl -l 2>/dev/null)"
if grep -qE -- '(never,task|task,never)' <<<"${loaded}" && ! grep -qE -- '^-[wa] .*(-k |key=|-S )' <<<"${loaded}"; then
    ok "the kernel audits no system call (only -a never,task is loaded)"
else
    not_ok "a per-syscall audit rule is loaded with the sensor active" "$(echo "${loaded}" | head -n 8)"
fi

# find /usr: the stat-heavy workload the study measures. Recorded, not gated here (VM speed varies).
find_ms="$( { /usr/bin/time -f '%e' find /usr -xdev >/dev/null; } 2>&1 | tail -n1 )"
echo "# find /usr (sensor active): ${find_ms} s"
check "find /usr completes with the sensor active" test -n "${find_ms}"

finish
