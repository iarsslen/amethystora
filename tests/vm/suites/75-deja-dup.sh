#!/usr/bin/bash
# Déjà Dup left the apps every machine comes with (amethystora.preinstall). What that does on a running machine,
# with Déjà Dup from Flathub: where its Flatpak keeps the settings that user-setup.hooks.d/19-deja-dup.sh reads;
# what `flatpak preinstall`, as flatpak-preinstall.service runs it, does with an app taken off its list, when the
# list installed it and when it was installed by hand (as `ame apps flatpaks` did from the old Brewfile); and that
# an account whose Déjà Dup backed it up on a schedule is told once, at its next login, when Déjà Dup is gone,
# and not while it is still there.
# vmlab-paths: @sf/usr/share/flatpak/* @sf/usr/share/amethystora/user-setup.hooks.d/19-deja-dup.sh
source "$(dirname "$0")/lib.sh"
cd /

APP=org.gnome.DejaDup
HOME_DIR="/var/home/${TEST_USER}"
LIST=/etc/flatpak/preinstall.d/vmlab-deja-dup.preinstall
KEYFILE="${HOME_DIR}/.var/app/${APP}/config/glib-2.0/settings/keyfile"
STATE="${HOME_DIR}/.local/state/amethystora/deja-dup-notice"
NOTIFY_LOG=/run/vmlab-notify.log

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi
# The first boot's preinstall done (or given up on), so that the two do not race
wait_for 1200 sh -c '[ "$(systemctl show -p SubState --value flatpak-preinstall.service)" != running ]'
if ! out="$(flatpak remote-info --system flathub "${APP}" 2>&1)"; then
    skip "Flathub cannot be reached from the VM: ${out}"
    finish
fi

installed() { flatpak info --system "${APP}" >/dev/null 2>&1; }
# The list read as the service reads it at every boot
preinstall() { flatpak preinstall -y </dev/null; }
# Déjà Dup's own gsettings, in its sandbox, in the account's session
dejadup_gsettings() { in_session "flatpak run --command=gsettings ${APP} $*"; }
# The next login's per-account setup, every hook in user-setup.hooks.d
login_setup() { user_systemctl start --wait amethystora-user-setup.service; }
# The notifications with Déjà Dup's icon that reached the Shell. GNOME's notification service owns
# org.freedesktop.Notifications and passes each Notify call on to the Shell with x-shell-sender added, so
# dbus-monitor sees every notification twice, both times addressed by unique name: the second one counts.
notices() {
    awk '/^method call/ { n += icon && shell; icon = shell = 0 } /string "deja-dup"/ { icon = 1 }
        /string "x-shell-sender"/ { shell = 1 } END { print n + (icon && shell) }' "${NOTIFY_LOG}" 2>/dev/null
}

cleanup() {
    pkill -f "dbus-monitor.*org.freedesktop.Notifications" 2>/dev/null
    rm -f "${LIST}" "${STATE}" "${NOTIFY_LOG}"
    installed && flatpak uninstall --system -y --noninteractive "${APP}" >/dev/null 2>&1
    rm -rf "${HOME_DIR}/.var/app/${APP}"
}
trap cleanup EXIT

if [[ "$(systemctl show -p SubState --value flatpak-preinstall.service)" == exited ]]; then
    if installed; then
        not_ok "Déjà Dup came with this machine" "$(grep -rl "${APP}" /usr/share/flatpak/preinstall.d)"
    else
        ok "Déjà Dup is not among the apps this machine came with"
    fi
fi
# Fresh: not installed, no settings, never told
installed && flatpak uninstall --system -y --noninteractive "${APP}" >/dev/null 2>&1
rm -rf "${HOME_DIR}/.var/app/${APP}" "${STATE}"

# --- Installed by hand, as on a machine set up before the list moved to preinstall.d ----------------------

check "Déjà Dup installs from Flathub" flatpak install --system -y --noninteractive flathub "${APP}"
check "its schedule turns on in its own settings" dejadup_gsettings set org.gnome.DejaDup periodic true
keys="$(dejadup_gsettings list-keys org.gnome.DejaDup 2>&1)"
if grep -qx periodic <<<"${keys}" && grep -qx last-backup <<<"${keys}" && grep -qx last-run <<<"${keys}"; then
    ok "its schema has periodic, last-backup and last-run"
else
    not_ok "its schema lacks a key the hook or the plan names" "${keys}"
fi
if [[ -f "${KEYFILE}" ]] && awk '/^\[/ { group = $0 } group == "[org/gnome/deja-dup]" && /^periodic=true$/ { found = 1 } END { exit !found }' "${KEYFILE}"; then
    ok "the schedule is periodic=true in [org/gnome/deja-dup] of ~/.var/app/${APP}/config/glib-2.0/settings/keyfile"
else
    not_ok "the schedule is not where 19-deja-dup.sh reads it" "$(find "${HOME_DIR}/.var/app/${APP}" -type f 2>&1 | head)" "$(cat "${KEYFILE}" 2>&1 | head -n 20)"
fi

check "flatpak preinstall runs" preinstall
if installed; then
    ok "an app installed by hand is left alone by flatpak preinstall"
else
    not_ok "flatpak preinstall uninstalled an app that was installed by hand"
fi
login_setup
if [[ ! -e "${STATE}" ]]; then
    ok "while Déjà Dup is installed, the login's setup says nothing"
else
    not_ok "the login's setup told the account although Déjà Dup is still installed"
fi
flatpak uninstall --system -y --noninteractive "${APP}" >/dev/null 2>&1

# --- Installed from the list, as on a machine set up from 2026-10-03 to the release that took it off -------

printf '%s\n' "[Flatpak Preinstall ${APP}]" 'Branch=stable' 'IsRuntime=false' >"${LIST}"
check "flatpak preinstall installs what its list names" sh -c "flatpak preinstall -y </dev/null && flatpak info --system ${APP} >/dev/null"
rm -f "${LIST}"
check "flatpak preinstall runs with it off the list" preinstall
if installed; then
    not_ok "flatpak preinstall kept an app its list installed and no longer names"
else
    ok "an app taken off the list is uninstalled from a machine that got it from there"
fi
check "its settings stay in the account's folder" test -f "${KEYFILE}"

# The next login: told, a minute in, once
user_bus dbus-monitor --session "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" >"${NOTIFY_LOG}" 2>&1 &
sleep 2
login_setup
check "the login's setup marks the account told" test -e "${STATE}"
told() { [[ "$(notices)" -ge 1 ]]; }
if wait_for 150 told; then
    ok "a minute later, the account is told Déjà Dup no longer backs it up"
    grep -q 'ame backup setup' "${NOTIFY_LOG}" && ok "the notice names ame backup setup" ||
        not_ok "the notice does not name ame backup setup" "$(grep -A6 '^method call' "${NOTIFY_LOG}" | tail -n 12)"
else
    not_ok "no notice within 150 s" "$(user_systemctl list-timers --all --no-pager 2>&1 | tail -n 8)" "$(tail -n 20 "${NOTIFY_LOG}")"
fi
login_setup
sleep 75
if [[ "$(notices)" == 1 ]]; then
    ok "the next login says nothing again"
else
    not_ok "told $(notices) times" "$(grep '^method call' "${NOTIFY_LOG}")"
fi
finish
