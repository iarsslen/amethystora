# Sourced by every suite (run.mjs runs each as root in the VM, beside this file). A suite says one line per
# check, as TAP does, and ends with `finish`:
#
#   ok - what held
#   not ok - what did not
#     indented lines after it say why
#   skip - what could not be checked here, and why
#
# `reboot_and_continue` asks run.mjs to reboot the VM and run the suite again with SUITE_PHASE one higher.

TEST_USER=tester
SUITE_PHASE="${SUITE_PHASE:-1}"
FAILED=0

ok() { echo "ok - $*"; }
not_ok() {
    echo "not ok - $1"
    shift
    [[ $# -eq 0 ]] || printf '%s\n' "$@" | head -n 40 | sed 's/^/  /'
    FAILED=1
}
skip() { echo "skip - $*"; }
finish() { exit "${FAILED}"; }
reboot_and_continue() { exit 100; }
# The next phase in this same boot, for what outlasts one phase's 30 minutes
continue_phase() { exit 101; }
# usb_next JSON: before that next phase, USB devices plugged out and then in, as a person would, by name
# (run.mjs's USB_DEVICES: stick, stick2, keyboard): {"unplug": ["stick"], "plug": ["stick", "keyboard"]}
usb_next() {
    install -d -m 0700 /var/lib/vmlab-tests
    printf '%s\n' "$1" >/var/lib/vmlab-tests/usb.json
}
# next_boot JSON: the restart reboot_and_continue asks for is a power cycle, the machine started again with what
# JSON says (run.mjs): {"absent": [N]} leaves SPARE-N unplugged, {"faulty": {"N": [sector, ...]}} gives SPARE-N
# sectors that fail every read, {"system_absent": true} leaves the VM's own disk unplugged, {"credentials":
# {"cryptsetup.passphrase": null}} leaves a credential out, {"menu_last": true} chooses the boot menu's last entry
# (End, Enter) as it shows, {"type_passphrase": true} has the disk's passphrase
# typed at its prompt, which the next phase finds counted in VMLAB_PROMPTS. A later plain restart keeps the
# machine as that start left it. {"itself": true} is no power cycle: run.mjs restarts nothing and waits for the
# restart the phase left to happen after it, a soft reboot too.
next_boot() {
    install -d -m 0700 /var/lib/vmlab-tests
    printf '%s\n' "$1" >/var/lib/vmlab-tests/next-boot.json
}

# check WHAT COMMAND...: ok when the command succeeds, not ok with the end of its output when it does not
check() {
    local what="$1" out
    shift
    if out="$("$@" 2>&1)"; then ok "${what}"; else not_ok "${what}" "$(tail -n 20 <<<"${out}")"; fi
}

# wait_for SECONDS COMMAND...: until the command succeeds, or false after SECONDS
wait_for() {
    local deadline=$((SECONDS + $1))
    shift
    until "$@" >/dev/null 2>&1; do
        ((SECONDS < deadline)) || return 1
        sleep 2
    done
}

# The test account's login shell, and its graphical session as its own terminal would be: the account on its
# user manager's bus (systemctl -M and systemd-run --machine lose their connection when a system service
# starts them)
as_user() { runuser -l "${TEST_USER}" -c "$*"; }
user_bus() {
    local uid
    uid="$(id -u "${TEST_USER}")"
    runuser -u "${TEST_USER}" -- env XDG_RUNTIME_DIR="/run/user/${uid}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" "$@"
}
user_systemctl() { user_bus systemctl --user "$@"; }
# in_terminal SECONDS [EXPECT SEND]... -- COMMAND...: COMMAND on a terminal of its own, for what asks a person;
# each EXPECT (a Python regular expression) waited for, then SEND typed (term.py)
in_terminal() { python3 "$(dirname "${BASH_SOURCE[0]}")/term.py" "$@"; }
in_session() { user_bus systemd-run --user --pipe --wait --quiet --collect -- /usr/bin/bash -lc "$*"; }
has_session() { [[ "$(loginctl show-user "${TEST_USER}" -p State --value 2>/dev/null)" == active ]]; }

# Whether the home folders are a btrfs subvolume of their own, as the installer makes them and the hourly
# snapshots need: the root of a subvolume is always inode 256
home_subvolume() { [[ "$(stat -f -c %T /var/home)" == btrfs && "$(stat -c %i /var/home)" == 256 ]]; }
# What `bootc install to-disk` leaves out: the subvolume "home" at the top of the system's btrfs, mounted on
# /var/home as Anaconda writes it, with what is there now copied in while nobody is signed in. It takes
# effect at the next boot (reboot_and_continue).
make_home_subvolume() {
    local device uuid
    device="$(findmnt -no SOURCE -T /var/home | sed 's/\[.*//')"
    uuid="$(blkid -s UUID -o value "${device}")"
    systemctl stop gdm
    loginctl terminate-user "${TEST_USER}" 2>/dev/null
    wait_for 60 sh -c "! pgrep -u ${TEST_USER} >/dev/null"
    mkdir -p /run/vmlab-top
    mount -o subvolid=5 "${device}" /run/vmlab-top
    [[ -d /run/vmlab-top/home ]] || btrfs subvolume create /run/vmlab-top/home >/dev/null
    chown --reference=/var/home /run/vmlab-top/home
    chmod --reference=/var/home /run/vmlab-top/home
    chcon --reference=/var/home /run/vmlab-top/home
    cp -a --reflink=auto /var/home/. /run/vmlab-top/home/
    umount /run/vmlab-top
    grep -qs ' /var/home btrfs ' /etc/fstab || echo "UUID=${uuid} /var/home btrfs subvol=home,compress=zstd:1 0 0" >>/etc/fstab
}

# The core dumps since a time `date '+%F %T'` gave, of what MATCHES says (COREDUMP_UID=1000), after giving
# systemd-coredump a moment to file them
crashes_since() {
    sleep 10
    coredumpctl list --since "$1" --no-legend --no-pager "${@:2}" 2>/dev/null
}
