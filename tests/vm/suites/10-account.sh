#!/usr/bin/bash
# An account for the suites after this one, logged in on the screen as a person would be: an administrator
# (wheel), signed in by GDM, past GNOME's first-run setup. Its first login runs the per-account setup.
source "$(dirname "$0")/lib.sh"

if ! getent passwd "${TEST_USER}" >/dev/null; then
    useradd -m -G wheel -c "Test account" "${TEST_USER}"
    echo "${TEST_USER}:${TEST_USER}" | chpasswd
fi
printf '[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=%s\n' "${TEST_USER}" >/etc/gdm/custom.conf
install -d -o "${TEST_USER}" -g "${TEST_USER}" "/var/home/${TEST_USER}/.config"
install -o "${TEST_USER}" -g "${TEST_USER}" /dev/null "/var/home/${TEST_USER}/.config/gnome-initial-setup-done"
systemctl restart gdm

if wait_for 240 has_session; then
    ok "${TEST_USER} is signed in"
else
    not_ok "${TEST_USER} did not get a session" "$(loginctl list-sessions --no-legend)" "$(journalctl -b -u gdm --no-pager -o cat | tail -n 10)"
    finish
fi
check "the session is Wayland" sh -c "loginctl show-session \$(loginctl show-user ${TEST_USER} -p Display --value) -p Type --value | grep -qx wayland"
check "GNOME Shell runs in it" wait_for 120 pgrep -u "${TEST_USER}" -x gnome-shell
# GNOME's welcome dialog of a first login, left with the keyboard alone (keys.py): Just Perfection once took the
# keyboard from it, and without a mouse there was no way past it
shows_welcome() { user_bus python3 "$(dirname "$0")/atspi.py" gnome-shell has "Welcome to"; }
welcome_gone() { ! shows_welcome; }
if wait_for 120 shows_welcome; then
    # Pressed once the dialog has had time to take the keyboard at the end of its opening, and once more when the
    # first came before it had (as in one round): a keyboard taken from it fails both
    sleep 2
    python3 "$(dirname "$0")/keys.py" esc
    wait_for 10 welcome_gone || python3 "$(dirname "$0")/keys.py" esc
    check "Escape closes GNOME's welcome dialog" wait_for 20 welcome_gone
else
    skip "GNOME's welcome dialog did not show"
fi
# The per-account setup, then the session settled
setup_state() { user_systemctl show amethystora-user-setup.service -p ActiveState -p Result --value | paste -sd ' '; }
setup_done() { [[ "$(setup_state)" == inactive* ]]; }
if wait_for 300 setup_done; then
    state="$(setup_state)"
    if [[ "${state}" == "inactive success" ]]; then
        ok "the per-account setup ran"
    else
        not_ok "the per-account setup ended as ${state}" "$(journalctl -b _SYSTEMD_USER_UNIT=amethystora-user-setup.service --no-pager -o cat | tail -n 15)"
    fi
else
    not_ok "the per-account setup did not finish within 5 minutes: $(setup_state)"
fi
check "the Manual's welcome page opened once" wait_for 120 pgrep -u "${TEST_USER}" -f "amethystora-manual welcome"
failed="$(user_systemctl --failed --no-legend --plain | awk '{print $1}')"
if [[ -z "${failed}" ]]; then ok "no user unit failed"; else not_ok "user units failed: $(paste -sd ' ' <<<"${failed}")"; fi
finish
