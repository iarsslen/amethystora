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

# The core dumps since a time `date '+%F %T'` gave, of what MATCHES says (COREDUMP_UID=1000), after giving
# systemd-coredump a moment to file them
crashes_since() {
    sleep 10
    coredumpctl list --since "$1" --no-legend --no-pager "${@:2}" 2>/dev/null
}
