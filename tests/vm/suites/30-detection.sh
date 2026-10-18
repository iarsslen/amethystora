#!/usr/bin/bash
# What looks for new threats, switched on as the thorough profile has it, finds what it is there to find on a
# machine that boots with it: a secret read (SSH key, a Chromium browser's saved passwords), the decoy key read,
# and a program run from the downloads folder, each done in the test account's own session. Falco (BEHAVIOUR)
# runs, and stays under the memory its unit allows. The audit rules are written at boot, so the profile goes on,
# then the machine restarts.
source "$(dirname "$0")/lib.sh"

HOME_DIR="/var/home/${TEST_USER}"
HISTORY=/var/log/amethystora-security-events.jsonl
config=/usr/libexec/amethystora-security-config

# After the restart, the session comes back by itself (GDM signs the account in)
if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi

if [[ "${SUITE_PHASE}" == 1 ]]; then
    check "the security report answers" sh -c '/usr/libexec/amethystora-security-status --json | jq -e .checks >/dev/null'
    check "the thorough profile goes on" "${config}" profile thorough
    # Secrets where a stealer would look, there before the boot that writes the rules on them
    as_user "mkdir -p -m 0700 ~/.ssh && head -c 400 /dev/urandom | base64 >~/.ssh/id_ed25519 && chmod 0600 ~/.ssh/id_ed25519
        mkdir -p ~/.config/chromium/Default && head -c 4096 /dev/urandom >'${HOME_DIR}/.config/chromium/Default/Login Data'
        mkdir -p ~/Downloads"
    reboot_and_continue
fi

[[ "$(${config} --profile)" == thorough ]] && ok "the profile is still thorough after the restart" || not_ok "the profile is $(${config} --profile) after the restart"
# Each key is watched by an audit rule, or by the file-watch sensor (then its key is in the plan and the
# watch list, not in auditctl, which shows only -a never,task). Either source feeds the same findings below.
rules="$(auditctl -l 2>&1)"
plan=/run/amethystora/sensor/plan
watchlist=/run/amethystora/sensor/watch.list
watched() { grep -q -- "-k $1\$\|key=$1\$" <<<"${rules}" || grep -qx "$1 sensor" "${plan}" 2>/dev/null; }
for key in credentials decoy exec-watch; do
    watched "${key}" && ok "${key} is watched (audit rule or the sensor)" || not_ok "no watch for ${key}" "$(grep -c . <<<"${rules}") rules; plan: $(cat "${plan}" 2>/dev/null | tr '\n' ' ')"
done
# Login Data: an inode rule under audit, a read-file watch (its name, space and all) under the sensor
{ grep -q -- "-F inode=" <<<"${rules}" || grep -q "^read-file credentials .*Login Data\$" "${watchlist}" 2>/dev/null; } &&
    ok "Login Data is watched (inode rule or the sensor)" || not_ok "Login Data not watched"
check "the decoy key is there" test -s "${HOME_DIR}/.ssh/id_backup"

before="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"
in_session "python3 -c 'open(\"${HOME_DIR}/.ssh/id_ed25519\").read()'
    cp '${HOME_DIR}/.config/chromium/Default/Login Data' /tmp/stolen
    cat ~/.ssh/id_backup >/dev/null
    cp /usr/bin/true ~/Downloads/amethystora-test-program && ~/Downloads/amethystora-test-program"
# ausearch gives an event only once a later one is more than two seconds newer
sleep 4
in_session "cat ~/.ssh/id_ed25519 >/dev/null"
sleep 3
check "the security watcher runs" systemctl start amethystora-security-watch.service
found="$(tail -n +"$((before + 1))" "${HISTORY}" 2>/dev/null)"
expect() {
    local what="$1" filter="$2"
    if jq -e -s "any(.[]; ${filter})" <<<"${found}" >/dev/null 2>&1; then ok "found: ${what}"; else not_ok "not found: ${what}" "$(jq -r -s '.[] | "\(.key) \(.level): \(.text)"' <<<"${found}" | tail -n 15)"; fi
}
expect "the SSH key read" '.key == "credentials" and (.text | contains("id_ed25519"))'
expect "the browser's saved passwords read" '.key == "credentials" and (.text | contains("Login Data"))'
expect "the decoy read, as critical" '.key == "decoy" and .level == "critical"'
expect "the program run from Downloads" '.key == "exec-watch" and (.text | contains("amethystora-test-program"))'

# A refused read of a path nothing watches must not be reported as a secret. A desktop reads other
# processes' /proc files and probes paths it may not read all day; the sensor's refused-open hook carries
# every read key with the raw path and leaves the matching to the daemon, so a regression there would flood
# the report with false "a secret was read" findings (and bury the real ones). auditd's rules watch only the
# named files, so this holds on a fallback boot too.
noise_before="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"
in_session "cat /proc/1/io /proc/1/smaps_rollup /etc/shadow >/dev/null 2>&1; true"
sleep 4
in_session "cat /proc/1/io >/dev/null 2>&1; true"
sleep 3
systemctl start amethystora-security-watch.service
noise="$(tail -n +"$((noise_before + 1))" "${HISTORY}" 2>/dev/null)"
if jq -e -s 'any(.[]; (.key == "credentials" or .key == "decoy") and (.text | test("/proc/|/etc/shadow")))' <<<"${noise}" >/dev/null 2>&1; then
    not_ok "a refused read of an unwatched path was reported as a secret" \
        "$(jq -r -s '.[] | select(.key == "credentials" or .key == "decoy") | "\(.key): \(.text)"' <<<"${noise}" | grep -E '/proc/|/etc/shadow' | head)"
else
    ok "a refused read of an unwatched path is not reported as a secret"
fi

# Falco: running, and its memory against the unit's MemoryHigh
if wait_for 120 systemctl is-active --quiet amethystora-behaviour.service; then
    ok "Falco runs"
    sleep 60
fi
# Still running a minute later, or there is no memory to measure
if ! systemctl is-active --quiet amethystora-behaviour.service; then
    not_ok "Falco is not running" "$(journalctl -b -u amethystora-behaviour.service --no-pager -o cat | tail -n 15)"
else
    peak="$(systemctl show amethystora-behaviour.service -p MemoryPeak --value)"
    now="$(systemctl show amethystora-behaviour.service -p MemoryCurrent --value)"
    high="$(($(systemctl show amethystora-behaviour.service -p MemoryHigh --value) / 1048576))"
    echo "# Falco memory: $((now / 1048576)) MiB now, $((peak / 1048576)) MiB at most"
    # What the peak is made of, its own memory or a cache the kernel takes back at MemoryHigh, and how often it did
    cg="/sys/fs/cgroup$(systemctl show amethystora-behaviour.service -p ControlGroup --value)"
    echo "# Falco memory now: $(awk '$1 ~ /^(anon|file|kernel|sock|shmem)$/ { printf "%s %d MiB, ", $1, $2 / 1048576 }' "${cg}/memory.stat")events: $(paste -sd ' ' "${cg}/memory.events")"
    # The peak is not what is checked: it counts the page cache of the events file Falco writes, which grows until
    # MemoryHigh takes it back, so it reaches any limit. Falco's own memory is anon + kernel.
    own="$(awk '$1 == "anon" || $1 == "kernel" { sum += $2 } END { printf "%d", sum / 1048576 }' "${cg}/memory.stat")"
    [[ -n "${own}" ]] && ((own < high)) && ok "Falco's own memory stays under ${high} MiB" || not_ok "Falco's own memory is ${own:-unreadable} MiB, over its ${high} MiB"
    grep -qx 'oom_kill 0' "${cg}/memory.events" && ok "Falco was never killed for memory" || not_ok "Falco was killed for memory" "$(paste -sd ' ' "${cg}/memory.events")"
fi
finish
