#!/usr/bin/bash
# The file-watch sensor (amethystora-sensor, plans/security/PLAN-audit-cost.md) covers the always-on keys:
# a write to a watched file or folder is recorded by the sensor, read back by the security watcher, and said,
# exactly as the audit rules would have. Only meaningful on a boot the sensor took over (auditctl shows the
# -a never,task filter and nothing else); on a fallback boot the audit rules do it and 30-detection covers
# that path, so this suite skips.
source "$(dirname "$0")/lib.sh"

HISTORY=/var/log/amethystora-security-events.jsonl
plan=/run/amethystora/sensor/plan

if ! grep -qx 'identity sensor' "${plan}" 2>/dev/null; then
    skip "the sensor did not take this boot (fallback to the audit rules); 30-detection covers that"
    finish
fi

check "the sensor service is running" systemctl is-active --quiet amethystora-sensor.service
# It is watching only once it has registered every folder, which waits on a ten-second BPF load; wait for it
# to say so before making the changes below, so they are not missed in that window.
wait_for 120 test -f /run/amethystora/sensor/ready &&
    ok "the sensor finished registering" || not_ok "the sensor did not become ready within 120 s"
# With the sensor active the kernel audits no system call: auditctl is just the task filter
check "no per-syscall audit rule is loaded" sh -c 'auditctl -l | grep -qE -- "(never,task|task,never)" && ! auditctl -l | grep -qE -- "^-[wa] .*(-k |key=)"'
check "the sensor is writing its log" test -f /var/log/amethystora-sensor/audit.log

# Prime the watcher so it has a point to read on from, then make the changes, so they fall after it.
check "the security watcher primes" systemctl start amethystora-security-watch.service
before="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"

# A write to each always-on key's watched place, as root (these keys record any actor): a write-open of an
# account file, and a file made then removed in each watched folder. Nothing's content changes.
bash -c ': >>/etc/passwd'
touch /etc/sudoers.d/amethystora-sensor-test && rm -f /etc/sudoers.d/amethystora-sensor-test
touch /etc/systemd/system/amethystora-sensor-test.service && rm -f /etc/systemd/system/amethystora-sensor-test.service
touch /etc/amethystora/amethystora-sensor-test && rm -f /etc/amethystora/amethystora-sensor-test
# A later write, so ausearch releases the ones above (it holds an event until a newer one), then settle
sleep 4
: >>/etc/passwd
sleep 3

check "the security watcher runs" systemctl start amethystora-security-watch.service
found="$(tail -n +"$((before + 1))" "${HISTORY}" 2>/dev/null)"
expect() {
    local what="$1" filter="$2"
    if jq -e -s "any(.[]; ${filter})" <<<"${found}" >/dev/null 2>&1; then
        ok "the sensor recorded: ${what}"
    else
        not_ok "the sensor did not record: ${what}" "$(jq -r -s '.[] | "\(.key) \(.level): \(.text)"' <<<"${found}" | tail -n 20)"
    fi
}
expect "a write to an account file (identity)" '.key == "identity" and (.text | contains("/etc/passwd"))'
expect "a change to the sudoers folder (privilege)" '.key == "privilege" and (.text | contains("amethystora-sensor-test"))'
expect "a change to what starts by itself (persistence)" '.key == "persistence" and (.text | contains("amethystora-sensor-test.service"))'
expect "a change to a security setting (hardening)" '.key == "hardening" and (.text | contains("amethystora-sensor-test"))'

# How much the sensor's maps and ring buffer cost, for the record
rss="$(systemctl show -p MemoryCurrent --value amethystora-sensor.service 2>/dev/null)"
[[ "${rss}" =~ ^[0-9]+$ ]] && echo "# sensor memory: $((rss / 1024 / 1024)) MB"

finish
