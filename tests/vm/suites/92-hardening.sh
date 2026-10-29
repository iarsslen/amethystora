#!/usr/bin/bash
# vmlab-vm: installer
# The prevention switches (amethystora-hardening): what the image enforces turned off and on again, and the
# stricter settings turned on and off again, each with what it does at once and what it does at the next start,
# on the installer's layout, whose /boot keeps a staged deployment through a restart and is mounted read-only.
# Each change is checked as it works, not only as a file: the firewall's zones from another network namespace,
# account lockout through PAM, Bluetooth privacy through BlueZ on a virtual controller, nothing run from the
# temporary folders (and bootc, which copies itself there, still updating), no X11 at the next login, the boot
# menu asking for its password to edit an entry, a kernel argument switched on a machine with a layered package,
# and the machine powering itself off once its session has been locked for 18 hours. After every change the
# security watcher sees no drift but the switches' own files, and nothing it says is louder than a note.
# A phase has 30 minutes, so the work of one start is split over several (continue_phase):
#   Phases 1, 2:   as the image ships them; noexec-temp on and a package layered; the rest of the first half
#                  switched: what the image enforces off, the stricter settings on
#   Phases 3-6:    after a restart; a kernel argument off and another on, on the layered machine (each
#                  rpm-ostree kargs takes minutes there); the first half back; the second half on
#   Phases 7-10:   after a restart; the second half back; the kernel arguments back; the package taken away
#   Phase 11:      after a restart, all as it was; locked for 18 hours: the machine powers off
#   Phase 12:      started again; locked-poweroff off; nothing left over
# vmlab-paths: @sf/usr/libexec/amethystora-hardening @sf/usr/lib/sysctl.d/* @sf/usr/lib/modprobe.d/* @sf/usr/lib/firewalld/*
source "$(dirname "$0")/lib.sh"

STATE=/var/lib/vmlab-tests/92-hardening
mkdir -p "${STATE}"
H=/usr/libexec/amethystora-hardening
WATCH_STATUS=/var/lib/amethystora/security/status.json
HISTORY=/var/log/amethystora-security-events.jsonl
PHASE_START="$(date +%s)"
NS=vmlab-fw
LAYERED=figlet
KARG=init_on_alloc=1
EXTRA=init_on_free=1
GRUB_PASSWORD=vmlab-grub

# The account, as 10-account.sh signs one in on the other machine: this one has none until a suite makes it
if ! getent passwd "${TEST_USER}" >/dev/null; then
    useradd -m -G wheel -c "Test account" "${TEST_USER}"
    echo "${TEST_USER}:${TEST_USER}" | chpasswd
    printf '[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=%s\n' "${TEST_USER}" >/etc/gdm/custom.conf
    install -d -o "${TEST_USER}" -g "${TEST_USER}" "/var/home/${TEST_USER}/.config"
    install -o "${TEST_USER}" -g "${TEST_USER}" /dev/null "/var/home/${TEST_USER}/.config/gnome-initial-setup-done"
    systemctl restart gdm
fi
UID_TEST="$(id -u "${TEST_USER}")"
if ! wait_for 300 has_session; then
    not_ok "no session for ${TEST_USER}" "$(loginctl list-sessions --no-legend)"
    finish
fi
wait_for 120 pgrep -u "${TEST_USER}" -x gnome-shell
PASSWORD=('\[sudo\] password for' "${TEST_USER}"$'\r')
runuser -u "${TEST_USER}" -- sudo -n true 2>/dev/null && PASSWORD=()

session_terminal() {
    local steps=()
    while [[ $# -gt 0 && "$1" != -- ]]; do steps+=("$1"); shift; done
    shift
    in_terminal "${steps[@]}" -- runuser -u "${TEST_USER}" -- env XDG_RUNTIME_DIR="/run/user/${UID_TEST}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_TEST}/bus" \
        systemd-run --user --pty --wait --quiet --collect -- /usr/bin/bash -lc "$*"
}
same() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1" "expected: $3" "found: $2"; fi; }
# The report, read once for the checks that follow (report_now), and one check of it
report_now() { REPORT="$(/usr/libexec/amethystora-security-status --json 2>/dev/null)"; }
record() { jq -c --arg id "$1" '[.. | objects | select(.id? == $id)][0]' <<<"${REPORT}"; }
state_of() { "${H}" is-on "$@" && echo on || echo off; }
set_to() {
    local out
    if out="$("${H}" set "$@" 2>&1)"; then ok "amethystora-hardening set $*"; else not_ok "amethystora-hardening set $*" "${out}"; fi
}
# What the report says of a switch the owner turned off: off, not a fault, with the command that turns it on
turned_off() {
    same "the report says ${1} is turned off, with ${3}" "$(record "$2" | jq -c '[.state, .switched_off, .command]')" \
        "[\"info\",true,\"${3}\"]"
}
SWITCHES="$("${H}" status --json)"
title() { jq -r --arg name "$1" '.[] | select(.name == $name) | .title' <<<"${SWITCHES}"; }
stricter_listed() { record stricter | jq -r '.details // [] | .[]'; }
# How long the phase took, said as a measurement: a phase has 30 minutes
SUITE_START="$(date +%s)"
took() { echo "# phase ${SUITE_PHASE} took $(($(date +%s) - SUITE_START)) s"; }
# The watcher's drift that was not there before this suite, after a run started now
new_drift() {
    systemctl start amethystora-security-watch.service
    jq -r '.drift // [] | .[] | "\(.change) \(.path)"' "${WATCH_STATUS}" | grep -vxF -f "${STATE}/drift.base"
}
# What the watcher said louder than a note since this phase began, of the switches and the image's settings
loud() {
    jq -c --argjson since "${PHASE_START}" 'select(.time >= $since and .level != "quiet"
        and (.key == "settings" or .key == "hardening" or (.key == "report" and (.text | test("differ|fail2ban|[Ff]irewall")))))
        | [.level, .key, .text]' "${HISTORY}" 2>/dev/null
}
watcher_quiet() {
    local drift said
    drift="$(new_drift)"
    if [[ -z "${drift}" ]]; then ok "the security watcher accepts exactly what the switches wrote ($1)"; else
        not_ok "the security watcher sees drift ($1)" "${drift}"; fi
    said="$(loud)"
    if [[ -z "${said}" ]]; then ok "and says nothing of it louder than a note"; else not_ok "the watcher spoke up ($1)" "${said}"; fi
}
new_failed() { comm -13 "${STATE}/failed.base" <(systemctl --failed --no-legend --plain | awk '{ print $1 }' | sort); }
no_new_failed() {
    local failed
    failed="$(new_failed)"
    if [[ -z "${failed}" ]]; then ok "no unit failed in this start that had not before"; else
        not_ok "units failed in this start" "${failed}" "$(for u in ${failed}; do journalctl -b -u "${u}" --no-pager -o cat | tail -n 4; done)"; fi
}

# --- Tools the checks use, kept beside the suite's state ----------------------------------------------------------
# A Bluetooth Low Energy controller as far as the kernel and BlueZ ask of one: /dev/vhci, every command answered as
# done, so that bluetoothd manages an adapter with the settings in its main.conf
cat >"${STATE}/vhci.py" <<'EOF'
import os, struct
fd = os.open('/dev/vhci', os.O_RDWR)
os.write(fd, bytes([0xff, 0x00]))
answers = {
    0x0c03: b'',  # reset
    0x1001: bytes([0x09, 0, 0, 0x09, 0xf1, 0x05, 0, 0]),  # version 5.0, the Linux Foundation's company id
    0x1002: bytes(64),  # no optional commands
    0x1003: bytes([0, 0, 0, 0, 0x60, 0, 0, 0]),  # LE, and no BR/EDR
    0x1009: bytes([0x56, 0x34, 0x12, 0xa0, 0x5a, 0x00]),  # a public address
    0x2002: struct.pack('<HB', 27, 15),  # LE buffers
    0x2003: bytes(8),
    0x201c: bytes(8),
}
while True:
    data = os.read(fd, 1100)
    if not data or data[0] != 0x01:
        continue
    op = struct.unpack('<H', data[1:3])[0]
    event = bytes([1]) + struct.pack('<H', op) + bytes([0]) + answers.get(op, bytes(250))
    os.write(fd, bytes([0x04, 0x0e, len(event)]) + event)
EOF
# listen ADDRESS FILE: TCP and UDP listeners on the ports the zones differ in, each datagram written to FILE.
# probe ADDRESS FILE: from another machine, each port as it answers: tcp/N open or closed, udp/N open when the
# listener wrote it down within a second
cat >"${STATE}/ports.py" <<'EOF'
import os, select, socket, sys, time
TCP, UDP = [4000, 1716], [138, 1716]
mode, address, seen = sys.argv[1:4]
if mode == 'listen':
    socks = []
    for port in TCP:
        s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((address, port)); s.listen(); socks.append(s)
    for port in UDP:
        s = socket.socket(type=socket.SOCK_DGRAM); s.bind((address, port)); socks.append(s)
    while True:
        for s in select.select(socks, [], [])[0]:
            if s.type == socket.SOCK_STREAM:
                s.accept()[0].close()
            else:
                with open(seen, 'a') as f:
                    f.write(s.recv(100).decode() + '\n')
else:
    words = []
    for port in TCP:
        s = socket.socket(); s.settimeout(3)
        try:
            s.connect((address, port)); words.append(f'tcp/{port} open')
        except OSError:
            words.append(f'tcp/{port} closed')
        s.close()
    for port in UDP:
        mark = f'{port}-{time.time()}'
        s = socket.socket(type=socket.SOCK_DGRAM); s.sendto(mark.encode(), (address, port)); s.close()
        time.sleep(1)
        got = os.path.exists(seen) and mark in open(seen).read().split()
        words.append(f'udp/{port} {"open" if got else "closed"}')
    print(' '.join(words))
EOF
# SERVICE USER PASSWORD: PAM asked to let USER in through SERVICE's stack, as a login asks: exit 0 when it does
cat >"${STATE}/pam.py" <<'EOF'
import ctypes, ctypes.util, sys
pam = ctypes.CDLL(ctypes.util.find_library('pam'))
libc = ctypes.CDLL(ctypes.util.find_library('c'))
libc.calloc.restype = ctypes.c_void_p
libc.strdup.restype = ctypes.c_void_p
libc.strdup.argtypes = [ctypes.c_char_p]
class Message(ctypes.Structure):
    _fields_ = [('style', ctypes.c_int), ('text', ctypes.c_char_p)]
class Response(ctypes.Structure):
    _fields_ = [('resp', ctypes.c_void_p), ('retcode', ctypes.c_int)]
CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(Message)),
                        ctypes.POINTER(ctypes.POINTER(Response)), ctypes.c_void_p)
class Conv(ctypes.Structure):
    _fields_ = [('conv', CONV), ('data', ctypes.c_void_p)]
password = sys.argv[3].encode()
def answer(count, messages, responses, data):
    replies = ctypes.cast(libc.calloc(count, ctypes.sizeof(Response)), ctypes.POINTER(Response))
    for i in range(count):
        if messages[i].contents.style in (1, 2):
            replies[i].resp = libc.strdup(password)
    responses[0] = replies
    return 0
conv = Conv(CONV(answer), None)
handle = ctypes.c_void_p()
pam.pam_start.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(Conv), ctypes.POINTER(ctypes.c_void_p)]
pam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
if pam.pam_start(sys.argv[1].encode(), sys.argv[2].encode(), ctypes.byref(conv), ctypes.byref(handle)) != 0:
    sys.exit(2)
result = pam.pam_authenticate(handle, 0)
pam.pam_end(handle, result)
sys.exit(0 if result == 0 else 1)
EOF
[[ -e "${STATE}/hostkey" ]] || ssh-keygen -q -t ed25519 -N '' -f "${STATE}/hostkey"

# --- What each switch does, as it works -------------------------------------------------------------------------
blocked() { modprobe -n -v "$1" 2>&1 | tail -n 1 | grep -q '^install /usr/bin/false'; }
sshd_says() { sshd -T -h "${STATE}/hostkey" 2>/dev/null | awk '{ $1 = tolower($1) } 1' | grep -E '^(maxauthtries|permitrootlogin|x11forwarding) ' | paste -sd' '; }
uinput_acl() { getfacl -cp /dev/uinput 2>/dev/null | grep -c "^user:${TEST_USER}:"; }
# NetworkManager's own reading of its configuration, which it refuses whole for one file it cannot read
ip6_privacy() {
    local config
    config="$(NetworkManager --print-config 2>&1)" || { echo "unreadable: ${config}"; return; }
    grep -c '^ipv6.ip6-privacy=2$' <<<"${config}"
}
sandbox() { flatpak override --show 2>/dev/null | grep -c 'sockets=!x11'; }
sysctls() { sysctl -n kernel.io_uring_disabled kernel.yama.ptrace_scope vm.mmap_rnd_bits kernel.kexec_load_disabled | paste -sd' '; }
noexec_mounts() {
    local folder
    for folder in /tmp /var/tmp /dev/shm; do
        findmnt -rn -o OPTIONS --mountpoint "${folder}" | tr ',' '\n' | grep -qx noexec && echo "${folder}"
    done | paste -sd' '
}
# The temporary folders a program copied there and started runs from
runs_from() {
    local folder
    for folder in /tmp /var/tmp /dev/shm; do
        printf '#!/bin/sh\necho ran\n' >"${folder}/vmlab-run" && chmod 0755 "${folder}/vmlab-run"
        [[ "$("${folder}/vmlab-run" 2>/dev/null)" == ran ]] && echo "${folder}"
        rm -f "${folder}/vmlab-run"
    done | paste -sd' '
}
shell_args() { tr '\0' ' ' <"/proc/$(pgrep -u "${TEST_USER}" -x gnome-shell | head -n 1)/cmdline"; }
display() { user_systemctl show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p'; }
x11_answers() { if in_session 'xset q >/dev/null 2>&1'; then echo yes; else echo no; fi; }
gsetting() { echo "$(user_bus gsettings get "$1" "$2") $(user_bus gsettings writable "$1" "$2")"; }
daemons() {
    local unit
    for unit in avahi-daemon.socket avahi-daemon.service ModemManager.service passim.service; do
        printf '%s=%s/%s ' "${unit}" "$(systemctl is-enabled "${unit}" 2>/dev/null)" "$(systemctl is-active "${unit}")"
    done
}
# Flathub's subset as flatpak lists it, "-" for none
subset() { flatpak remotes --system --columns=name,subset 2>/dev/null | awk '$1 == "flathub" { print ($2 == "" || $2 == "-" ? "none" : $2) }'; }
# pkcheck's answer for the account's session installing a Flatpak for the machine: 0 allowed, 2 a password first
flatpak_install() { pkcheck --action-id org.freedesktop.Flatpak.app-install --process "$(pgrep -u "${TEST_USER}" -x gnome-shell | head -n 1)" >/dev/null 2>&1; echo $?; }
# Where systemd-coredump kept the core of a program of the account's that crashed now
core_kept() {
    local since
    since="$(date '+%F %T')"
    runuser -u "${TEST_USER}" -- bash -c 'sleep 30 & sleep 1; kill -SEGV $!; wait' >/dev/null 2>&1
    sleep 8
    coredumpctl info --since "${since}" --no-pager 2>/dev/null | sed -n 's/^ *Storage: \([^ ]*\).*/\1/p' | head -n 1 |
        sed 's#^/var/lib/systemd/coredump/.*#on disk#'
}
cooldown() {
    # shellcheck disable=SC2016 # expanded by the account's login shell
    as_user 'echo "${npm_config_min_release_age}|${pnpm_config_minimum_release_age}|${UV_EXCLUDE_NEWER}|${npm_config_ignore_scripts}|${HOMEBREW_VERIFY_ATTESTATIONS}"'
}
# What environment.d gives every program of the account's session from its next login
session_env() {
    runuser -u "${TEST_USER}" -- /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator 2>/dev/null |
        grep -cE '^(npm_config_min_release_age|HOMEBREW_VERIFY_ATTESTATIONS)='
}
nts() { chronyc -c authdata 2>/dev/null | grep -c ',NTS,'; }
has_nts() { [[ "$(nts)" -gt 0 ]]; }
# Ten wrong passwords for the account through system-auth, then the right one: let in or refused
lockout_try() {
    local i said
    faillock --user "${TEST_USER}" --reset
    for i in $(seq 10); do python3 "${STATE}/pam.py" system-auth "${TEST_USER}" wrong; done
    if python3 "${STATE}/pam.py" system-auth "${TEST_USER}" "${TEST_USER}"; then said="let in"; else said=refused; fi
    faillock --user "${TEST_USER}" --reset
    echo "${said}"
}
# The virtual controller, bluetoothd's adapter on it, and what bluetoothd set it to: its timeouts and privacy
adapter_powered() { [[ "$(busctl get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Powered 2>/dev/null)" == "b true" ]]; }
vhci_up() {
    systemctl is-active --quiet vmlab-vhci.service ||
        systemd-run --quiet --unit=vmlab-vhci --collect python3 "${STATE}/vhci.py"
    wait_for 60 adapter_powered
}
adapter() { busctl get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 "$1" 2>/dev/null | cut -d' ' -f2; }
bt_privacy() { if btmgmt --index 0 info 2>/dev/null | grep 'current settings' | grep -qw privacy; then echo privacy; else echo fixed; fi; }
bluetooth() { echo "discoverable for $(adapter DiscoverableTimeout) s, pairable for $(adapter PairableTimeout) s, $(bt_privacy) address"; }
# Visible, and still visible 35 seconds later or not
discoverable_after() {
    bluetoothctl discoverable on >/dev/null 2>&1
    wait_for 10 sh -c '[ "$(busctl get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Discoverable)" = "b true" ]'
    sleep 35
    adapter Discoverable
    bluetoothctl discoverable off >/dev/null 2>&1
}
# A network of its own in a namespace, which NetworkManager manages as a saved connection, and what it reaches here
net_up() {
    ip netns add "${NS}" 2>/dev/null
    if ! ip link show vmlab-fw0 >/dev/null 2>&1; then
        ip link add vmlab-fw0 type veth peer name vmlab-fw1 netns "${NS}"
        ip -n "${NS}" link set lo up
        ip -n "${NS}" addr add 10.77.0.2/24 dev vmlab-fw1
        ip -n "${NS}" link set vmlab-fw1 up
    fi
    wait_for 30 nmcli -t device show vmlab-fw0
    nmcli device set vmlab-fw0 managed yes
    nmcli device set vmlab-fw0 autoconnect no
    nmcli -g connection.uuid connection show vmlab-fw >/dev/null 2>&1 ||
        nmcli connection add type ethernet ifname vmlab-fw0 con-name vmlab-fw autoconnect no \
            ipv4.method manual ipv4.addresses 10.77.0.1/24 ipv6.method disabled >/dev/null
    nmcli connection up vmlab-fw >/dev/null
    systemctl is-active --quiet vmlab-ports.service ||
        systemd-run --quiet --unit=vmlab-ports --collect python3 "${STATE}/ports.py" listen 10.77.0.1 /run/vmlab-ports.seen
    wait_for 20 sh -c 'ss -ltn | grep -q "10.77.0.1:4000 "'
}
probe() { ip netns exec "${NS}" python3 "${STATE}/ports.py" probe 10.77.0.1 /run/vmlab-ports.seen; }
zone() { firewall-cmd --get-zone-of-interface="$1" 2>/dev/null; }
CLOSED="tcp/4000 closed tcp/1716 closed udp/138 open udp/1716 closed"
WORKSTATION="tcp/4000 open tcp/1716 open udp/138 open udp/1716 open"
AWAY="tcp/4000 closed tcp/1716 closed udp/138 closed udp/1716 closed"
HOMEZONE="tcp/4000 closed tcp/1716 open udp/138 open udp/1716 open"
has_arg() { [[ " $(cat /proc/cmdline) " == *" $1 "* ]]; }
next_has() { [[ " $(rpm-ostree kargs 2>/dev/null) " == *" $1 "* ]]; }
layered() { rpm-ostree status --booted --json | jq -r '.deployments[0]["requested-packages"] // [] | join(" ")'; }
staged_layered() { rpm-ostree status --json | jq -r '.deployments[] | select(.staged) | .["requested-packages"] // [] | join(" ")'; }
graphical() { loginctl show-user "${TEST_USER}" -p Display --value; }
sensor_watches() { grep -qx 'identity sensor' /run/amethystora/sensor/plan 2>/dev/null && echo sensor || echo audit; }
# How amethystora-signed-updates ended, at this start or since SECONDS since the epoch: success, a failure, or skipped
signed_updates_ran() {
    local result since=(-b)
    [[ -n "${1:-}" ]] && since=(--since "@$1")
    wait_for 900 sh -c '[ "$(systemctl show -P ActiveState amethystora-signed-updates.service)" != activating ]'
    result="$(systemctl show -P Result amethystora-signed-updates.service)"
    if journalctl "${since[@]}" -u amethystora-signed-updates.service --no-pager -o cat | grep -q "Skipped due to 'exec-condition'"; then
        echo skipped
    else
        echo "${result}"
    fi
}

# --- Phase 1: the first half on, a package layered ---------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 1 ]]; then
    # What the earlier suites left: no staged deployment, no switch away from the image's default
    rpm-ostree cleanup --pending >/dev/null 2>&1
    off_default="$("${H}" status --json | jq -c '[.[] | select(.state != .default) | .name] + [.[] | .arguments // [] | .[] | select(.state != .default) | .argument]')"
    same "every switch starts as the image ships it" "${off_default}" "[]"
    systemctl --failed --no-legend --plain | awk '{ print $1 }' | sort >"${STATE}/failed.base"
    : >"${STATE}/drift.base"
    new_drift >"${STATE}/drift.base"
    "${H}" status --json >"${STATE}/status.base"
    /usr/libexec/amethystora-security-status --json | jq -c '[.. | objects | select(.switched_off? == true) | .id]' >"${STATE}/off.base"
    # What the watcher says from here on is this suite's doing
    PHASE_START="$(date +%s)"
    [[ -s "${STATE}/drift.base" ]] && echo "# drift before this suite, left out of its checks: $(paste -sd';' "${STATE}/drift.base")"

    # --- As the image ships them
    vhci_up || not_ok "bluetoothd has no adapter on the virtual controller" "$(journalctl -u bluetooth -b --no-pager -o cat | tail -n 5)"
    same "Bluetooth: visible and pairable for 30 seconds, a random address" "$(bluetooth)" \
        "discoverable for 30 s, pairable for 30 s, privacy address"
    same "made visible, Bluetooth hides again after 30 seconds" "$(discoverable_after)" false
    same "ten wrong passwords lock the account: the right one is then refused" "$(lockout_try)" refused
    net_up
    same "another network reaches only what the Amethystora zone lets in" "$(zone vmlab-fw0) $(probe)" "amethystora ${CLOSED}"
    same "the SSH server's settings" "$(sshd_says)" "maxauthtries 3 permitrootlogin no x11forwarding no"
    BASE_DAEMONS="$(daemons)"
    echo "${BASE_DAEMONS}" >"${STATE}/daemons.base"

    # --- Nothing run from the temporary folders, through its recipe, as a person turns it on
    out="$(session_terminal 300 'Turn Nothing runs from temporary folders on\?' y "${PASSWORD[@]}" -- "ame security noexec-temp on")"
    if [[ $? == 0 ]]; then ok "ame security noexec-temp on"; else not_ok "ame security noexec-temp on" "$(tail -n 10 <<<"${out}")"; fi
    same "/tmp, /var/tmp and /dev/shm are noexec at once" "$(noexec_mounts)" "/tmp /var/tmp /dev/shm"
    same "a program copied into any of them does not start" "$(runs_from)" ""
    same "a script run through its interpreter still does" "$(printf 'echo ran\n' >/tmp/vmlab-script; sh /tmp/vmlab-script; rm -f /tmp/vmlab-script)" ran
    # bootc copies itself into /tmp to re-execute in install_t when its caller does not get it there; a system
    # service of the image's that runs it gets there by itself
    started="$(date +%s)"
    systemctl reset-failed amethystora-signed-updates.service 2>/dev/null
    systemctl start amethystora-signed-updates.service 2>/dev/null
    same "amethystora-signed-updates, which runs bootc, still works" "$(signed_updates_ran "${started}")" success
    out="$(session_terminal 120 "${PASSWORD[@]}" -- "sudo bootc status --format=json >/dev/null && echo bootc-answers")"
    if [[ "${out}" == *bootc-answers* ]]; then ok "and so does sudo bootc in a terminal"; else
        not_ok "sudo bootc status with /tmp noexec" "$(tail -n 5 <<<"${out}")"; fi
    # A package layered meanwhile, which also has rpm-ostree work with /tmp noexec: the kernel arguments are
    # switched on this machine in the next phase, which then updates through rpm-ostree, not bootc
    out="$(timeout 1200 rpm-ostree install --idempotent "${LAYERED}" 2>&1)"
    if [[ "$(staged_layered)" == "${LAYERED}" ]]; then ok "rpm-ostree layers ${LAYERED}, for the next start"; else
        not_ok "rpm-ostree install ${LAYERED}" "$(tail -n 10 <<<"${out}")"; fi
    took
    continue_phase
fi

# --- Phase 2: the rest of the first half: what the image enforces off, the stricter settings on -------------------------
if [[ "${SUITE_PHASE}" == 2 ]]; then

    # --- What the image enforces, turned off
    set_to kernel off
    same "the kernel settings are masked" "$(readlink /etc/sysctl.d/60-amethystora-hardening.conf)" /dev/null
    module="$(for m in sctp rds tipc; do modinfo "${m}" >/dev/null 2>&1 && { echo "${m}"; break; }; done)"
    echo "${module}" >"${STATE}/module"
    set_to blocked-modules off
    if blocked "${module}"; then not_ok "${module} is still blocked"; else ok "${module}, a blocked module this kernel has, can load"; fi
    set_to failed-logins off
    same "fail2ban is disabled" "$(systemctl is-enabled fail2ban.service)" disabled
    out="$(session_terminal 300 'Turn Account lockout off\?' y "${PASSWORD[@]}" -- "ame security lockout off")"
    if [[ $? == 0 ]]; then ok "ame security lockout off"; else not_ok "ame security lockout off" "$(tail -n 10 <<<"${out}")"; fi
    same "ten wrong passwords then lock nothing: the right one lets the account in" "$(lockout_try)" "let in"
    set_to app-sandbox off
    same "apps keep their own X11 and input devices" "$(sandbox)" 0
    set_to virtual-input off
    wait_for 10 sh -c "getfacl -cp /dev/uinput | grep -q '^user:${TEST_USER}:'"
    same "/dev/uinput is the account's at the seat at once" "$(uinput_acl)" 1
    set_to ssh-settings off
    same "OpenSSH's own settings" "$(sshd_says)" "maxauthtries 6 permitrootlogin prohibit-password x11forwarding yes"
    same "and systemd's SSH over vsock is no longer masked" "$(readlink /etc/systemd/system-generators/systemd-ssh-generator || echo none)" none
    set_to ipv6-privacy off
    same "NetworkManager no longer asks for temporary IPv6 addresses" "$(ip6_privacy)" 0
    set_to bluetooth-privacy off
    vhci_up
    same "BlueZ's own settings: visible for 3 minutes, pairable without end, a fixed address" "$(bluetooth)" \
        "discoverable for 180 s, pairable for 0 s, fixed address"
    same "made visible, Bluetooth stays visible past 30 seconds" "$(discoverable_after)" true
    set_to firewall off
    same "another network reaches every port from 1025 up" "$(zone vmlab-fw0) $(probe)" "FedoraWorkstation ${WORKSTATION}"
    same "fail2ban bans in that zone" "$(cmp -s /etc/fail2ban/jail.d/20-amethystora-zone.conf <("${H}" expected fail2ban/jail.d/20-amethystora-zone.conf) && echo yes)" yes

    # --- Stricter settings, turned on
    set_to time on
    if wait_for 90 has_nts; then ok "the clock is set from NTS servers only ($(nts) authenticated)"; else
        not_ok "chrony has no NTS source" "$(chronyc -n sources 2>&1 | tail -n 5)"; fi
    set_to network-daemons on
    same "Avahi, ModemManager and passim are stopped and masked" "$(daemons)" \
        "avahi-daemon.socket=masked/inactive avahi-daemon.service=masked/inactive ModemManager.service=masked/inactive passim.service=masked/inactive "
    set_to block-webcam on
    if modprobe uvcvideo 2>/dev/null; then modprobe -r uvcvideo; not_ok "uvcvideo still loads"; else ok "the webcam driver cannot load"; fi
    set_to block-automount on
    same "automatic mounting is off and locked for the account" "$(gsetting org.gnome.desktop.media-handling automount)" "false false"
    set_to block-user-extensions on
    same "installing GNOME extensions is off and locked" "$(gsetting org.gnome.shell allow-extension-installation)" "false false"
    set_to block-xwayland on
    if [[ -n "$(subset)" ]]; then
        set_to flathub-verified on
        same "Flathub offers its verified apps only" "$(subset)" verified
    else
        skip "verified Flathub apps: this machine has no Flathub remote"
    fi
    same "installing a Flatpak for the machine needs no password from an administrator's session" "$(flatpak_install)" 0
    set_to flatpak-password on
    same "now it asks for one" "$(flatpak_install)" 2
    set_to no-coredumps on
    same "a program that crashes leaves no core on disk" "$(core_kept)" none
    set_to package-cooldown on
    same "npm, pnpm and uv wait 3 days in a new login shell" "$(cooldown)" "3|4320|3 days||"
    set_to package-cooldown strict
    same "strict waits 7 days and runs no install scripts" "$(cooldown)" "7|10080|7 days|true|"
    set_to brew-attestations on
    same "Homebrew checks attestations" "$(cooldown | cut -d'|' -f5)" 1
    same "and both reach every program of the account's next login" "$(session_env)" 2
    if [[ -x /usr/bin/codium ]]; then
        set_to vscodium-extensions on
        same "VSCodium updates no extension by itself" "$(jq -c .ExtensionsAutoUpdate /etc/vscodium/policy.json)" false
    else
        skip "VSCodium's extensions: VSCodium is in the dx images only"
    fi
    # The boot menu's password, through its recipe, on /boot, which bootc mounts read-only
    out="$(session_terminal 300 'Set a boot menu password now\?' y "${PASSWORD[@]}" 'Enter password:' "${GRUB_PASSWORD}"$'\r' \
        'Confirm password:' "${GRUB_PASSWORD}"$'\r' -- "ame security boot-password on")"
    if [[ $? == 0 && "$(state_of boot-password)" == on ]]; then ok "ame security boot-password on sets a password"; else
        not_ok "ame security boot-password on" "$(tail -n 10 <<<"${out}")"; fi
    if grep -q '^GRUB2_PASSWORD=grub.pbkdf2.' /boot/grub2/user.cfg 2>/dev/null; then ok "GRUB has it in user.cfg"; else
        not_ok "no password in /boot/grub2/user.cfg"; fi
    findmnt -rn -o OPTIONS --mountpoint /boot | tr ',' '\n' | grep -qx ro &&
        same "/boot stays read-only for everything else" "$(touch /boot/vmlab 2>&1 | grep -c 'Read-only')" 1

    # --- What the report and the watcher make of all of it
    report_now
    turned_off kernel kernel "ame security kernel on"
    turned_off blocked-modules blocked-modules "ame security blocked-modules on"
    turned_off failed-logins fail2ban "ame security failed-logins on"
    turned_off lockout lockout "ame security lockout on"
    turned_off app-sandbox app-sandbox "ame security app-sandbox on"
    turned_off virtual-input virtual-input "ame security virtual-input on"
    turned_off ssh-settings ssh-settings "ame security ssh-settings on"
    turned_off ipv6-privacy ipv6-privacy "ame security ipv6-privacy on"
    turned_off bluetooth-privacy bluetooth-privacy "ame security bluetooth-privacy on"
    turned_off firewall firewall "ame security firewall on"
    listed="$(stricter_listed)"
    missing=()
    for name in time network-daemons block-webcam block-automount block-user-extensions block-xwayland flatpak-password \
        noexec-temp no-coredumps package-cooldown brew-attestations boot-password; do
        grep -qxF -- "$(title "${name}")" <<<"${listed}" || missing+=("${name}")
    done
    same "the report names every stricter setting that is on" "${missing[*]}" ""
    watcher_quiet "the first half switched"
    took
    next_boot '{"menu_edit": true}'
    reboot_and_continue
fi

# --- Phase 3: after a restart; kernel arguments on the layered machine --------------------------------------------------
if [[ "${SUITE_PHASE}" == 3 ]]; then
    same "editing a boot entry asks for the boot menu's password, and the machine starts without it" "${VMLAB_MENU_EDIT}" asked
    no_new_failed
    same "amethystora-signed-updates ran at this start, with /tmp noexec" "$(signed_updates_ran)" success
    same "the session came up with every temporary folder noexec" "$(noexec_mounts) $(has_session && echo session)" \
        "/tmp /var/tmp /dev/shm session"
    same "and nothing copied into them starts" "$(runs_from)" ""
    if [[ "$(shell_args)" == *--no-x11* && -z "$(display)" ]]; then ok "GNOME Shell started without Xwayland: no DISPLAY"; else
        not_ok "the login after block-xwayland on" "$(shell_args)" "DISPLAY=$(display)"; fi
    same "no X11 app can connect" "$(x11_answers)" no
    same "the kernel settings are the kernel's own from this start (kexec_load_disabled)" "$(sysctl -n kernel.kexec_load_disabled)" 0
    same "/dev/uinput is still the account's" "$(uinput_acl)" 1
    net_up
    same "another network still reaches every port from 1025 up" "$(zone vmlab-fw0) $(probe)" "FedoraWorkstation ${WORKSTATION}"
    same "${LAYERED} is layered on the system this machine started" "$(layered)" "${LAYERED}"

    # --- Kernel arguments, on a machine that updates through rpm-ostree
    set_to kernel-args off "${KARG}"
    if next_has "${KARG}"; then not_ok "the next start still has ${KARG}" "$(rpm-ostree kargs)"; else
        ok "the next start has no ${KARG}"; fi
    took
    continue_phase
fi

# --- Phase 4: an extra kernel argument on, on the layered machine -------------------------------------------------------
if [[ "${SUITE_PHASE}" == 4 ]]; then
    set_to kernel-args on "${EXTRA}"
    if ! next_has "${KARG}" && next_has "${EXTRA}"; then ok "the next start has ${EXTRA} and not ${KARG}"; else
        not_ok "the next start's arguments" "$(rpm-ostree kargs)"; fi
    same "and keeps ${LAYERED}" "$(staged_layered)" "${LAYERED}"
    report_now
    same "the report says ${KARG} is turned off" "$(record kernel-args | jq -c '[.state, .switched_off, .text]')" \
        "[\"info\",true,\"Turned off, from the next restart: ${KARG}\"]"
    if stricter_listed | grep -qxF "${EXTRA}"; then ok "and names ${EXTRA} among the stricter settings"; else
        not_ok "${EXTRA} is not among the stricter settings" "$(stricter_listed)"; fi

    took
    continue_phase
fi

# --- Phase 5: the first half back as the image ships it -----------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 5 ]]; then
    set_to noexec-temp off
    same "the temporary folders run programs again at once" "$(runs_from)" "/tmp /var/tmp /dev/shm"
    same "and /etc/fstab has none of its lines" "$(grep -c x-amethystora-noexec /etc/fstab)" 0
    set_to kernel on
    same "kernel settings unmasked" "$(test -e /etc/sysctl.d/60-amethystora-hardening.conf && echo there)" ""
    same "and applied at once (kexec_load_disabled)" "$(sysctl -n kernel.kexec_load_disabled)" 1
    set_to blocked-modules on
    if blocked "$(cat "${STATE}/module")"; then ok "$(cat "${STATE}/module") is blocked again"; else not_ok "$(cat "${STATE}/module") still loads"; fi
    set_to failed-logins on
    same "fail2ban is enabled" "$(systemctl is-enabled fail2ban.service)" enabled
    set_to lockout on
    same "ten wrong passwords lock the account again" "$(lockout_try)" refused
    set_to app-sandbox on
    same "apps lose X11 and input devices again" "$(sandbox)" 1
    set_to virtual-input on
    same "the rule is gone" "$(ls /etc/udev/rules.d | grep -c uinput)" 0
    set_to ssh-settings on
    same "the SSH server's settings again" "$(sshd_says)" "maxauthtries 3 permitrootlogin no x11forwarding no"
    set_to ipv6-privacy on
    same "temporary IPv6 addresses again" "$(ip6_privacy)" 1
    set_to bluetooth-privacy on
    vhci_up
    same "Bluetooth's privacy settings again" "$(bluetooth)" "discoverable for 30 s, pairable for 30 s, privacy address"
    systemctl stop vmlab-vhci.service
    set_to firewall on
    same "another network reaches only what the Amethystora zone lets in again" "$(zone vmlab-fw0) $(probe)" "amethystora ${CLOSED}"
    same "fail2ban's zone file is gone" "$(ls /etc/fail2ban/jail.d | grep -c 20-amethystora-zone)" 0
    set_to time off
    same "chrony.conf is the image's again" "$(cmp -s /etc/chrony.conf /usr/etc/chrony.conf && echo same)" same
    set_to network-daemons off
    same "Avahi, ModemManager and passim as before" "$(daemons)" "$(cat "${STATE}/daemons.base")"
    set_to block-webcam off
    if modprobe uvcvideo; then modprobe -r uvcvideo; ok "the webcam driver loads again"; else not_ok "uvcvideo still cannot load"; fi
    set_to block-automount off
    same "automatic mounting is on and the account's again" "$(gsetting org.gnome.desktop.media-handling automount)" "true true"
    set_to block-user-extensions off
    same "extensions can be installed again" "$(gsetting org.gnome.shell allow-extension-installation)" "true true"
    set_to block-xwayland off
    if [[ "$(state_of flathub-verified)" == on ]]; then
        set_to flathub-verified off
        same "Flathub offers every app again" "$(subset)" none
    fi
    set_to flatpak-password off
    same "installing a Flatpak for the machine needs no password again" "$(flatpak_install)" 0
    set_to no-coredumps off
    same "a crash leaves its core on disk again" "$(core_kept)" "on disk"
    set_to package-cooldown off
    set_to brew-attestations off
    same "no cooldown and no attestations in a new login shell" "$(cooldown)" "||||"
    same "nor from the next login" "$(session_env)" 0
    [[ -x /usr/bin/codium ]] && { set_to vscodium-extensions off; same "VSCodium's policy is gone" "$(test -e /etc/vscodium/policy.json && echo there)" ""; }
    set_to boot-password off
    same "the boot menu's password is gone, from read-only /boot" "$(test -e /boot/grub2/user.cfg && echo there)" ""
    same "the switches have nothing left in /etc" "$("${H}" managed)" ""
    watcher_quiet "the first half back"

    took
    continue_phase
fi

# --- Phase 6: the second half switched ----------------------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 6 ]]; then
    set_to kernel strict
    same "strict: io_uring off, only root attaches a debugger, more address randomisation, at once" \
        "$(sysctls | cut -d' ' -f1-3)" "2 2 32"
    if blocked esp4; then ok "and IPsec's esp4 cannot load"; else not_ok "esp4 still loads"; fi
    set_to firewall-away on
    same "the default zone is the away zone" "$(firewall-cmd --get-default-zone)" amethystora-away
    same "a network not named home answers nothing, not even Windows shares" "$(zone vmlab-fw0) $(probe)" "amethystora-away ${AWAY}"
    UUID="$(nmcli -g connection.uuid connection show vmlab-fw)"
    echo "${UUID}" >"${STATE}/uuid"
    if out="$("${H}" home "${UUID}" 2>&1)"; then ok "amethystora-hardening home names it home"; else not_ok "amethystora-hardening home" "${out}"; fi
    same "named home, it reaches phone pairing and shares" "$(zone vmlab-fw0) $(probe)" "amethystora-home ${HOMEZONE}"
    report_now
    same "the report says so" "$(record firewall | jq -r .state) $(record home-networks | jq -r .state)" "ok info"
    set_to block-bluetooth on
    same "Bluetooth's service is off" "$(systemctl is-enabled bluetooth.service)/$(systemctl is-active bluetooth.service)" "disabled/inactive"
    if blocked btusb; then ok "btusb cannot load"; else not_ok "btusb still loads"; fi
    set_to audit-locked on
    set_to signed-updates off
    started="$(date +%s)"
    systemctl reset-failed amethystora-signed-updates.service 2>/dev/null
    systemctl start amethystora-signed-updates.service 2>/dev/null
    same "amethystora-signed-updates now switches nothing" "$(signed_updates_ran "${started}")" skipped
    report_now
    turned_off signed-updates signed-updates "ame security signed-updates on"
    listed="$(stricter_listed)"
    missing=()
    for name in firewall-away block-bluetooth audit-locked; do
        grep -qxF -- "$(title "${name}")" <<<"${listed}" || missing+=("${name}")
    done
    grep -qxF -- "$(title kernel) (strict)" <<<"${listed}" || missing+=("kernel strict")
    same "the report names every stricter setting that is on" "${missing[*]}" ""
    watcher_quiet "the second half switched"
    took
    next_boot '{"menu_edit": true}'
    reboot_and_continue
fi

# --- Phase 7: after a restart; the second half back ---------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 7 ]]; then
    same "with the password gone, e opens the boot menu's editor" "${VMLAB_MENU_EDIT}" editor
    no_new_failed
    same "the temporary folders are as before" "$(noexec_mounts)" ""
    if [[ "$(shell_args)" != *--no-x11* && -n "$(display)" ]]; then ok "GNOME Shell starts Xwayland again"; else
        not_ok "the login after block-xwayland off" "$(shell_args)" "DISPLAY=$(display)"; fi
    same "an X11 app connects" "$(x11_answers)" yes
    same "/dev/uinput is root's alone from this start" "$(uinput_acl)" 0
    if ! has_arg "${KARG}" && has_arg "${EXTRA}"; then ok "the machine started with ${EXTRA} and without ${KARG}"; else
        not_ok "the arguments it started with" "$(cat /proc/cmdline)"; fi
    same "still with ${LAYERED} layered" "$(layered)" "${LAYERED}"
    same "kernel strict holds from the start" "$(sysctls | cut -d' ' -f1-3)" "2 2 32"
    net_up
    same "the away zone is still the default, the network named home keeps its zone" \
        "$(firewall-cmd --get-default-zone) $(zone vmlab-fw0) $(probe)" "amethystora-away amethystora-home ${HOMEZONE}"
    if lsmod | grep -q '^bluetooth '; then not_ok "Bluetooth loaded at this start"; else ok "Bluetooth did not load at this start"; fi
    if modprobe hci_vhci 2>/dev/null; then not_ok "a Bluetooth driver still loads"; else ok "and no Bluetooth driver can"; fi
    same "the audit rules, locked, record in the sensor's place" "$(sensor_watches) $(systemctl is-active amethystora-sensor.service) $(auditctl -s | awk '$1 == "enabled" { print $2 }')" \
        "audit inactive 2"
    if auditctl -l | grep -qE -- '-k identity$|key=identity'; then ok "the identity audit rules are loaded"; else not_ok "no identity audit rule" "$(auditctl -l | head -n 5)"; fi
    same "amethystora-signed-updates switched nothing at this start" "$(signed_updates_ran)" skipped

    # --- The second half back
    set_to kernel standard
    same "kernel standard leaves no file of strict's" "$(ls /etc/sysctl.d /etc/modprobe.d | grep -c 61-amethystora-strict)" 0
    set_to firewall-away off
    same "the default zone is the Amethystora zone again, the network named home keeps its own" \
        "$(firewall-cmd --get-default-zone) $(zone vmlab-fw0) $(probe)" "amethystora amethystora-home ${HOMEZONE}"
    if out="$("${H}" home 2>&1)"; then ok "no network named home any more"; else not_ok "amethystora-hardening home" "${out}"; fi
    same "it goes back to the default zone" "$(zone vmlab-fw0) $(probe)" "amethystora ${CLOSED}"
    same "and the list is gone" "$(test -e /etc/amethystora/firewall-home && echo listed)" ""
    set_to block-bluetooth off
    same "Bluetooth's service is back" "$(systemctl is-enabled bluetooth.service)/$(systemctl is-active bluetooth.service)" "enabled/active"
    if vhci_up; then ok "and bluetoothd has an adapter again"; else not_ok "no adapter after block-bluetooth off"; fi
    systemctl stop vmlab-vhci.service
    set_to audit-locked off
    started="$(date +%s)"
    set_to signed-updates on
    same "amethystora-signed-updates runs again" "$(signed_updates_ran "${started}")" success
    took
    continue_phase
fi

# --- Phase 8: the kernel argument back --------------------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 8 ]]; then
    set_to kernel-args on "${KARG}"
    if next_has "${KARG}"; then ok "the next start has ${KARG} again"; else not_ok "the next start's arguments" "$(rpm-ostree kargs)"; fi
    took
    continue_phase
fi

# --- Phase 9: the extra kernel argument off -----------------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 9 ]]; then
    set_to kernel-args off "${EXTRA}"
    if next_has "${KARG}" && ! next_has "${EXTRA}"; then ok "the next start has ${KARG} again and not ${EXTRA}"; else
        not_ok "the next start's arguments" "$(rpm-ostree kargs)"; fi
    report_now
    same "the report no longer says a kernel argument is off" "$(record kernel-args)" null
    took
    continue_phase
fi

# --- Phase 10: the package taken away -----------------------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 10 ]]; then
    out="$(timeout 1200 rpm-ostree uninstall "${LAYERED}" 2>&1)"
    if rpm-ostree status --json | jq -e '.deployments[] | select(.staged) | .["requested-packages"] == []' >/dev/null; then
        ok "${LAYERED} goes from the next start"; else not_ok "rpm-ostree uninstall ${LAYERED}" "$(tail -n 10 <<<"${out}")"; fi
    if next_has "${KARG}" && ! next_has "${EXTRA}"; then ok "which keeps the kernel arguments as switched back"; else
        not_ok "the next start's arguments after the uninstall" "$(rpm-ostree kargs)"; fi
    same "the switches have nothing left in /etc" "$("${H}" managed)" ""
    watcher_quiet "everything back"
    took
    reboot_and_continue
fi

# --- Phase 11: all as it was after a restart; locked for 18 hours --------------------------------------------------------
if [[ "${SUITE_PHASE}" == 11 ]]; then
    no_new_failed
    same "the kernel's own io_uring and ptrace from this start" "$(sysctls | cut -d' ' -f1-2)" "0 1"
    same "the sensor records in the audit rules' place again" "$(sensor_watches) $(systemctl is-active amethystora-sensor.service)" "sensor active"
    if has_arg "${KARG}" && ! has_arg "${EXTRA}"; then ok "the machine started with the image's kernel arguments"; else
        not_ok "the arguments it started with" "$(cat /proc/cmdline)"; fi
    same "and nothing layered" "$(layered)" ""
    same "every switch is as the image ships it" \
        "$("${H}" status --json | jq -c '[.[] | select(.state != .default) | .name] + [.[] | .arguments // [] | .[] | select(.state != .default) | .argument]')" "[]"
    report_now
    same "and the report has no stricter setting to name" "$(record stricter)" null
    same "nothing of what the suite turned off is still said to be off" \
        "$(jq -c '[.. | objects | select(.switched_off? == true) | .id]' <<<"${REPORT}")" \
        "$(cat "${STATE}/off.base")"

    # --- Power off once every desktop session has stayed locked for 18 hours
    set_to locked-poweroff on
    same "its timer runs" "$(systemctl is-enabled amethystora-locked-poweroff.timer)/$(systemctl is-active amethystora-locked-poweroff.timer)" "enabled/active"
    systemctl start amethystora-locked-poweroff.service
    same "with the session unlocked it counts nothing" "$(test -e /run/amethystora/locked-since && echo counting)" ""
    loginctl lock-session "$(graphical)"
    locked() { [[ "$(loginctl show-session "$(graphical)" -p LockedHint --value)" == yes ]]; }
    if wait_for 60 locked; then ok "the session is locked, which GNOME tells logind"; else not_ok "the session did not lock"; fi
    systemctl start amethystora-locked-poweroff.service
    since="$(cat /run/amethystora/locked-since 2>/dev/null)"
    if [[ "${since}" =~ ^[0-9]+$ ]] && ((since >= PHASE_START)); then ok "locked, it counts from now"; else not_ok "nothing counted" "${since}"; fi
    # 18 hours and a minute ago, as the timer's next run would find it
    echo "$(($(date +%s) - 18 * 3600 - 60))" >/run/amethystora/locked-since
    systemd-run --quiet --unit=vmlab-locked-poweroff --on-active=40s systemctl start amethystora-locked-poweroff.service
    took
    next_boot '{"powers_off": true}'
    reboot_and_continue
fi

# --- Phase 12: started again ---------------------------------------------------------------------------------------
said="$(journalctl -b -1 -u amethystora-locked-poweroff.service --no-pager -o cat | grep 'powering off')"
if [[ -n "${said}" ]]; then ok "the machine powered itself off: ${said}"; else
    not_ok "locked-poweroff did not power the machine off" "$(journalctl -b -1 -u amethystora-locked-poweroff.service --no-pager -o cat | tail -n 5)"; fi
no_new_failed
set_to locked-poweroff off
same "its timer no longer runs" "$(systemctl is-enabled amethystora-locked-poweroff.timer)/$(systemctl is-active amethystora-locked-poweroff.timer)" "disabled/inactive"
same "every switch is as the image ships it" "$("${H}" status --json | jq -c '[.[] | select(.state != .default) | .name]')" "[]"
nmcli connection delete vmlab-fw >/dev/null 2>&1
systemctl stop vmlab-ports.service 2>/dev/null
ip netns delete "${NS}" 2>/dev/null
watcher_quiet "after the power off"
took
finish
