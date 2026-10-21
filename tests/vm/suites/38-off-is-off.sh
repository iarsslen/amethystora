#!/usr/bin/bash
# Off is off (PLAN-threat-detection, Measuring): after `ame security profile off` and a restart, no audit rule is
# loaded, auditd and every unit of a security feature end at their ExecCondition=, at boot and when started, and
# nothing is said; `profile default` and a restart bring back the machine as it was. Then the same with only
# security.conf written by hand, as from a text console. A decoy key left from before is taken back with the audit
# log off. Last, TRIGGER_UNIT reaches the weekly scan's ExecCondition=: with VIRUS_SCAN=manual, its timer's start
# is skipped and one by hand is not. The machine's own security.conf is put back at the end.
source "$(dirname "$0")/lib.sh"

CONFIG=/usr/libexec/amethystora-security-config
CONF=/etc/amethystora/security.conf
STATE=/var/lib/vmlab-tests/off-is-off
HISTORY=/var/log/amethystora-security-events.jsonl
HOME_DIR="/var/home/${TEST_USER}"
DECOY="${HOME_DIR}/.ssh/id_backup"
# Every unit a security feature runs, and the families the plan names
UNITS=(auditd.service audit-rules.service amethystora-audit-rules.service amethystora-sensor.service
    amethystora-security-watch.service amethystora-security-realtime.service amethystora-lynis-audit.service
    clamd@scan.service clamav-freshclam.service amethystora-clamd-idle.service amethystora-clamav-scan.service
    amethystora-clamav-onaccess.service amethystora-yara.service amethystora-ips.service amethystora-ips-rules.service
    amethystora-dns-names.service amethystora-behaviour.service amethystora-integrity.service)
PATTERNS=('amethystora-security-*.service' 'amethystora-clamav-*.service' 'amethystora-lynis-*.service')

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi
install -d -m 0700 "${STATE}"

running() { systemctl list-units --type=service --state="$1" --no-legend --plain "${UNITS[@]}" "${PATTERNS[@]}" | awk '{ print $1 }' | sort -u; }
faults() { jq -r '.checks[] | select(.state == "check" or .state == "off") | .id' <<<"$1" | sort -u; }
lines() { wc -l <"${HISTORY}" 2>/dev/null || echo 0; }
# The audit rules and the sensor's plan and watch list as they are loaded now
loaded() {
    auditctl -l 2>&1 | sort
    echo "## plan"
    cat /run/amethystora/sensor/plan 2>/dev/null
    echo "## watch list"
    sort /run/amethystora/sensor/watch.list 2>/dev/null
}
# The boot's own rules are in once the sensor, when it took the boot, has registered every watch
settled() {
    wait_for 120 sh -c '! systemctl is-active --quiet amethystora-sensor.service || test -f /run/amethystora/sensor/ready'
    wait_for 120 sh -c '! systemctl list-jobs --no-legend | grep -qE "auditd|audit-rules|amethystora-sensor"'
}
# The Notify calls from Amethystora that reached the session while COMMAND ran, and in the 10 s after
said_during() {
    local log="${STATE}/notify.log"
    user_bus dbus-monitor --session "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" >"${log}" 2>&1 &
    sleep 2
    "$@" >/dev/null 2>&1
    sleep 10
    pkill -f "dbus-monitor.*org.freedesktop.Notifications" 2>/dev/null
    wait 2>/dev/null
    grep -c 'string "Amethystora"' "${log}"
}
# Each unit started as its timer or a person would start it, one line each in starts, then the login's security
# alert, which says what the scans found while nobody was there
start_each() {
    local unit
    : >"${STATE}/starts"
    for unit in "${UNITS[@]}"; do
        [[ "${unit}" == "${SKIP_START:-}" ]] && continue
        timeout 120 systemctl start "${unit}" >/dev/null 2>&1
        # The YARA sets of a source turned off are taken away by one run, as its ExecCondition= allows
        if [[ "${unit}" == amethystora-yara.service && "$(systemctl show -P Result "${unit}")" == success ]]; then
            timeout 120 systemctl start "${unit}" >/dev/null 2>&1
        fi
        echo "${unit} $(systemctl show -P ActiveState "${unit}") $(systemctl show -P Result "${unit}")" >>"${STATE}/starts"
    done
    user_systemctl restart amethystora-security-alert.service
}

# Everything off, as HOW turned it off
check_off() {
    local how="$1" decoy_left="$2" active report out
    settled
    [[ "$("${CONFIG}" --profile)" == off ]] && ok "${how}: the switches read off" || not_ok "${how}: the switches read $("${CONFIG}" --profile)"
    out="$(auditctl -l 2>&1)"
    [[ "${out}" == "No rules" ]] && ok "${how}: auditctl lists no rules" || not_ok "${how}: audit rules are loaded" "$(head -n 10 <<<"${out}")"
    echo "# ${how}: kernel audit $(auditctl -s 2>/dev/null | grep -E '^(enabled|lost|backlog) ' | paste -sd ' ')"
    [[ "$(systemctl show -P Result auditd.service)" == exec-condition && "$(systemctl show -P ActiveState auditd.service)" == inactive ]] &&
        ok "${how}: auditd was skipped at boot by its ExecCondition=" ||
        not_ok "${how}: auditd was not skipped at boot" "$(systemctl status auditd.service --no-pager 2>&1 | tail -n 12)"
    if grep -qs . /run/amethystora/sensor/plan; then
        not_ok "${how}: the sensor's plan names keys" "$(cat /run/amethystora/sensor/plan)"
    else
        ok "${how}: the sensor's plan names no key"
    fi
    # The decoy goes with the audit log, at the restart that turns it off; the generator ran for nothing else
    if [[ "${decoy_left}" == true ]]; then
        [[ ! -e "${DECOY}" ]] && ok "${how}: the decoy key left from before was taken back" ||
            not_ok "${how}: the decoy key is still in the home" "$(ls -l "${DECOY}")"
    fi
    active="$(running active,activating,reloading,deactivating)"
    [[ "${decoy_left}" == true ]] && active="$(grep -vx amethystora-audit-rules.service <<<"${active}")"
    [[ -z "${active}" ]] && ok "${how}: no unit of a security feature runs" || not_ok "${how}: units of security features run" "${active}"
    # A timer's run ends at its condition: the watcher's, five minutes after boot
    wait_for 480 sh -c '[ "$(systemctl show -P InactiveExitTimestampMonotonic amethystora-security-watch.service)" != 0 ] && [ "$(systemctl show -P ActiveState amethystora-security-watch.service)" = inactive ]'
    [[ "$(systemctl show -P Result amethystora-security-watch.service)" == exec-condition ]] &&
        ok "${how}: the watcher's timer run ended at its condition" ||
        not_ok "${how}: the watcher's timer run did not end at its condition" "$(systemctl status amethystora-security-watch.service --no-pager 2>&1 | tail -n 8)"
    # Each unit, started as its timer or a person would start it, ends at its condition, and says nothing
    SKIP_START=""
    [[ "${decoy_left}" == true ]] && SKIP_START=amethystora-audit-rules.service
    since="$(date +%s)"
    said="$(said_during start_each)"
    # What the kernel still records goes to the journal while auditd is not there to take it: with its audit
    # on, systemd's record of each unit just started; with it off, nothing but SELinux's denials
    out="$(( $(journalctl -q --since "@${since}" _TRANSPORT=audit -o cat 2>/dev/null | wc -l) +
        $(journalctl -q -k --since "@${since}" -o cat 2>/dev/null | grep -c '^audit: type=') ))"
    if [[ "$(auditctl -s 2>/dev/null | awk '$1 == "enabled" { print $2 }')" == 0 ]]; then
        echo "# ${how}: the kernel's audit is off, so it records no system call and no unit: ${out} records since"
    elif ((out > 0)); then
        ok "${how}: the kernel's audit records reach the journal (${out} as the units started)"
    else
        not_ok "${how}: the kernel's audit is on, and none of its records reached the journal"
    fi
    out="$(awk '$2 != "inactive" || $3 != "exec-condition"' "${STATE}/starts")"
    [[ -n "$(cat "${STATE}/starts")" && -z "${out}" ]] && ok "${how}: each unit, started by hand, ends at its condition" ||
        not_ok "${how}: units ran when started" "${out}"
    # clamd's socket stays, at no cost: a connection to it is refused, and starts nothing and fails nothing
    python3 -c 'import socket; s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect("/run/clamd.scan/clamd.sock"); s.send(b"zPING\0"); s.recv(64)' 2>/dev/null
    sleep 3
    [[ "$(systemctl show -P ActiveState clamd@scan.socket) $(systemctl show -P ActiveState clamd@scan.service)" == "active inactive" ]] &&
        ok "${how}: a connection to clamd's socket starts nothing and fails nothing" ||
        not_ok "${how}: a connection to clamd's socket left it $(systemctl show -P ActiveState clamd@scan.socket) ($(systemctl show -P Result clamd@scan.socket))" \
            "$(journalctl -b -u clamd@scan.socket -o cat --no-pager | tail -n 4)"
    [[ "${said}" == 0 ]] && ok "${how}: nothing is said, the login's security alert included" ||
        not_ok "${how}: ${said} notifications from Amethystora" "$(grep -A8 'string "Amethystora"' "${STATE}/notify.log" | head -n 20)"
    [[ "$(lines)" == "$(cat "${STATE}/history")" ]] && ok "${how}: nothing was added to the security history" ||
        not_ok "${how}: the security history grew" "$(tail -n +"$(($(cat "${STATE}/history") + 1))" "${HISTORY}" | tail -n 5)"
    # Off is not a fault: what was switched off is information, and nothing warns that did not before
    report="$(/usr/libexec/amethystora-security-status --json 2>/dev/null)"
    out="$(comm -13 "${STATE}/faults" <(faults "${report}"))"
    [[ -z "${out}" ]] && ok "${how}: the report warns of nothing new" || not_ok "${how}: the report warns of what was switched off" "${out}"
    out="$(jq -r '.checks[] | select(.id | IN("security-watcher", "audit-log", "virus-scan", "settings-audit")) |
        select(.state != "info" or (.switched_off | not)) | "\(.id) \(.state)"' <<<"${report}")"
    [[ -z "${out}" ]] && ok "${how}: the report shows the watcher, the audit log, the scanner and the audit as turned off" ||
        not_ok "${how}: the report does not show them turned off" "${out}"
}

# Everything as it was before
check_back() {
    local how="$1" report out
    settled
    [[ "$("${CONFIG}" --profile)" == default ]] && ok "${how}: the switches read default" || not_ok "${how}: the switches read $("${CONFIG}" --profile)"
    out="$(diff "${STATE}/units" <(running active))"
    [[ -z "${out}" ]] && ok "${how}: the same units run as before ($(wc -l <"${STATE}/units"))" || not_ok "${how}: other units run than before" "${out}"
    out="$(diff "${STATE}/loaded" <(loaded))"
    [[ -z "${out}" ]] && ok "${how}: the same audit rules and sensor watches are loaded" || not_ok "${how}: other rules are loaded than before" "${out}"
    report="$(/usr/libexec/amethystora-security-status --json 2>/dev/null)"
    out="$(comm -13 "${STATE}/faults" <(faults "${report}"))"
    [[ -z "${out}" ]] && ok "${how}: the report warns of nothing it did not before" || not_ok "${how}: the report warns of more than before" "${out}"
}

case "${SUITE_PHASE}" in
    1)
        # The machine's own file, put back at the end; a folder for the decoy, there from the baseline's boot on,
        # so that its watch is in the rules compared
        if [[ -e "${CONF}" ]]; then cp -a "${CONF}" "${STATE}/original.conf"; else rm -f "${STATE}/original.conf"; fi
        "${CONFIG}" --profile >"${STATE}/original.profile"
        as_user "mkdir -p -m 0700 ~/.ssh"
        check "ame security profile default" in_terminal 300 -- ame security profile default
        cp -a "${CONF}" "${STATE}/default.conf"
        reboot_and_continue
        ;;
    2)
        # The machine as the image ships it, to come back to
        settled
        running active >"${STATE}/units"
        loaded >"${STATE}/loaded"
        faults "$(/usr/libexec/amethystora-security-status --json 2>/dev/null)" >"${STATE}/faults"
        echo "# default: $(wc -l <"${STATE}/units") units run, $(auditctl -l 2>/dev/null | grep -c '^-') audit rules, plan: $(paste -sd ' ' /run/amethystora/sensor/plan 2>/dev/null)"
        # A decoy key as the generator makes it, its mark on its second line, as a machine on the thorough profile has
        if [[ -e "${DECOY}" ]]; then
            echo "# ${DECOY} is there already" && rm -f "${STATE}/decoy"
        else
            as_user "umask 077; { echo '-----BEGIN OPENSSH PRIVATE KEY-----'; { printf 'amethystora-decoy:'; head -c 381 /dev/urandom; } | base64 -w 68
                echo '-----END OPENSSH PRIVATE KEY-----'; } >~/.ssh/id_backup" && touch "${STATE}/decoy"
        fi
        check "ame security profile off" in_terminal 300 'Turn every detection switch off' y -- ame security profile off
        cp -a "${CONF}" "${STATE}/off.conf"
        sleep 5
        lines >"${STATE}/history"
        reboot_and_continue
        ;;
    3)
        if [[ -e "${STATE}/decoy" ]]; then check_off "profile off" true; else skip "the decoy: the account had an id_backup of its own"; check_off "profile off" false; fi
        check "ame security profile default" in_terminal 300 -- ame security profile default
        reboot_and_continue
        ;;
    4)
        check_back "profile default"
        # From a text console: the file alone, written as the profile left it, without the helper or a note
        cat "${STATE}/off.conf" >"${CONF}"
        lines >"${STATE}/history"
        reboot_and_continue
        ;;
    5)
        check_off "security.conf written by hand" false
        cat "${STATE}/default.conf" >"${CONF}"
        reboot_and_continue
        ;;
    6)
        check_back "security.conf written back by hand"
        # TRIGGER_UNIT: with VIRUS_SCAN=manual, the scan its timer starts is skipped, one started by hand is not
        "${CONFIG}" set VIRUS_SCAN manual
        dropin=/run/systemd/system/amethystora-clamav-scan.timer.d
        mkdir -p "${dropin}"
        printf '[Timer]\nOnActiveSec=5s\nAccuracySec=1s\nRandomizedDelaySec=0\n' >"${dropin}/vmlab.conf"
        before="$(systemctl show -P InactiveExitTimestampMonotonic amethystora-clamav-scan.service)"
        systemctl daemon-reload
        systemctl restart amethystora-clamav-scan.timer
        started() { [[ "$(systemctl show -P InactiveExitTimestampMonotonic amethystora-clamav-scan.service)" != "${before}" &&
            "$(systemctl show -P ActiveState amethystora-clamav-scan.service)" == inactive ]]; }
        if wait_for 90 started && [[ "$(systemctl show -P Result amethystora-clamav-scan.service)" == exec-condition ]]; then
            ok "the weekly scan its timer starts is skipped while VIRUS_SCAN=manual: TRIGGER_UNIT reaches its ExecCondition="
        else
            not_ok "the timer's scan was not skipped while VIRUS_SCAN=manual" "$(journalctl -b -u amethystora-clamav-scan.service --no-pager -o cat | tail -n 8)"
        fi
        rm -rf "${dropin}"
        systemctl daemon-reload
        systemctl restart amethystora-clamav-scan.timer
        before="$(systemctl show -P ExecMainStartTimestampMonotonic amethystora-clamav-scan.service)"
        systemctl start --no-block amethystora-clamav-scan.service
        ran() { [[ "$(systemctl show -P ExecMainStartTimestampMonotonic amethystora-clamav-scan.service)" != "${before}" ]]; }
        if wait_for 90 ran; then ok "a scan started by hand runs while VIRUS_SCAN=manual"; else not_ok "a scan started by hand did not run" "$(systemctl status amethystora-clamav-scan.service --no-pager 2>&1 | tail -n 8)"; fi
        systemctl stop amethystora-clamav-scan.service clamd@scan.service
        # The machine's own settings, at the next boot
        if [[ -e "${STATE}/original.conf" ]]; then cp -a "${STATE}/original.conf" "${CONF}"; else rm -f "${CONF}"; fi
        reboot_and_continue
        ;;
    *)
        [[ "$("${CONFIG}" --profile)" == "$(cat "${STATE}/original.profile")" ]] && ok "the machine's own settings are back ($(cat "${STATE}/original.profile"))" ||
            not_ok "the settings read $("${CONFIG}" --profile), not $(cat "${STATE}/original.profile")"
        rm -rf "${STATE}"
        ;;
esac
finish
