#!/usr/bin/bash
# App integrity (APP_INTEGRITY, amethystora-integrity) on a real machine: a small app from Flathub for the machine
# and another for the test account, checked clean, then each kind of change made on its own and found (a file
# of an app replaced, an object written in place, a stray launcher, a file of the account's own app replaced and
# said to it, the system's own object and initramfs), and put back. What each check cost, with nothing new and
# after an update. Then the two reaches of the app permissions that load code into an app or change the others,
# and odd processes' library from a home and session environment.
source "$(dirname "$0")/lib.sh"

HOME_DIR="/var/home/${TEST_USER}"
STATE=/var/lib/amethystora/security/integrity
HISTORY=/var/log/amethystora-security-events.jsonl
config=/usr/libexec/amethystora-security-config

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi

# A terminal in the session, as Ptyxis opens one: in the account's user manager, which polkit takes for the seat's
# session (so the account starts the check as the person at the machine), on a pseudo-terminal of its own
session_terminal() {
    local uid steps=()
    uid="$(id -u "${TEST_USER}")"
    while [[ $# -gt 0 && "$1" != -- ]]; do steps+=("$1"); shift; done
    shift
    in_terminal "${steps[@]}" -- runuser -u "${TEST_USER}" -- env XDG_RUNTIME_DIR="/run/user/${uid}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
        systemd-run --user --pty --wait --quiet --collect -- /usr/bin/bash -lc "$*"
}

# The first boot's flatpak preinstall brings the runtimes the two apps are picked on, and holds Flatpak's lock
# while it does: on a new disk that can take most of a phase, so phase 1 waits for it and the rest is phase 2's
preinstall_done() { [[ "$(systemctl show flatpak-preinstall.service -p SubState --value)" == exited ]]; }
if [[ "${SUITE_PHASE}" == 1 ]] && ! preinstall_done; then
    wait_for 1650 preinstall_done ||
        echo "# flatpak-preinstall.service still $(systemctl show flatpak-preinstall.service -p SubState --value) after 27 min"
    continue_phase
fi

check "app integrity goes on" "${config}" set APP_INTEGRITY on

# Two small apps on a runtime the default apps brought already, one for the machine and one for the account
runtimes="$(flatpak list --system --runtime --columns=ref)"
APPS=()
for candidate in org.gnome.Sudoku org.gnome.Mahjongg org.gnome.Tetravex org.gnome.Mines org.gnome.design.Palette; do
    flatpak info --system "${candidate}" >/dev/null 2>&1 && continue
    runtime="$(LC_ALL=C flatpak remote-info --system flathub "${candidate}" 2>/dev/null | sed -n 's/^ *Runtime: //p')"
    [[ -n "${runtime}" ]] && grep -qxF "${runtime}" <<<"${runtimes}" && APPS+=("${candidate}")
    [[ ${#APPS[@]} -eq 2 ]] && break
done
if [[ ${#APPS[@]} -lt 2 ]]; then
    skip "no two small apps on a runtime this machine has (flatpak-preinstall.service $(systemctl show flatpak-preinstall.service -p SubState --value)): Flathub cannot be reached?"
    finish
fi
APP="${APPS[0]}" OWN="${APPS[1]}"
echo "# the machine's app: ${APP}; ${TEST_USER}'s own: ${OWN}"
check "${APP} installs for the machine" flatpak install --system -y --noninteractive flathub "${APP}"
as_user "flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" >/dev/null 2>&1
check "${OWN} installs for ${TEST_USER}" as_user "flatpak install --user -y --noninteractive flathub ${OWN}"

# A check, as the recipe runs one, and what it took, from systemd's own accounting
measure() {
    local start stop cpu io
    { read -r cpu; read -r io; read -r start; read -r stop; } < <(systemctl show amethystora-integrity.service \
        -p CPUUsageNSec -p IOReadBytes -p ExecMainStartTimestampMonotonic -p ExecMainExitTimestampMonotonic --value)
    # systemd says "[not set]" for what it did not account
    [[ "${cpu}" =~ ^[0-9]+$ ]] && cpu="$((cpu / 1000000)) ms of CPU" || cpu="CPU not accounted"
    [[ "${io}" =~ ^[0-9]+$ ]] && io="$((io / 1048576)) MB read" || io="reads not accounted"
    echo "# $1: $(((stop - start) / 1000000)) s, ${cpu}, ${io}"
}
run_check() {
    systemctl start amethystora-integrity.service || return 1
    systemctl start amethystora-security-watch.service
    FOUND="$(jq -r '"\(.id) \(.level) \(.account): \(.text)"' "${STATE}/findings.jsonl" 2>/dev/null)"
}
clean() {
    run_check
    [[ -z "${FOUND}" ]] && ok "$1: nothing changed outside an update" || not_ok "$1: something was found" "${FOUND}"
}
found() {
    run_check
    grep -qE -- "$2" <<<"${FOUND}" && ok "found: $1" || not_ok "not found: $1" "${FOUND:-nothing}"
}

# The first check reads everything once; the next only what changed; after an update, the new deploys
clean "the first check"
measure "the first check"
clean "a check with nothing new"
measure "a check with nothing new"
check "the apps update" flatpak update --system -y --noninteractive
clean "a check after an update"
measure "a check after an update"
check "ame security app-integrity says when it checked" sh -c "ame security app-integrity status | grep -q 'Last checked'"

# The deploy of the machine's app, its program and one of its objects
DEPLOY="$(flatpak info --system --show-location "${APP}")"
FILE="$(find "${DEPLOY}/files" -type f -size +1k -links +1 | head -n1)"
OBJECT="$(find /var/lib/flatpak/repo/objects -samefile "${FILE}" | head -n1)"
echo "# changed: ${FILE#"${DEPLOY}/"}, whose object is ${OBJECT}"

# 1. A deployed file replaced, and put back by the recipe, which fetches the app again
cp "${FILE}" /run/vmlab-file
{ cat /run/vmlab-file; printf 'x'; } >/run/vmlab-file.new
mv /run/vmlab-file.new "${FILE}"
found "a file of ${APP} replaced" "^file:-:app/${APP}/"
check "ame security app-integrity repair puts ${APP} back" in_terminal 900 'Put back' y -- ame security app-integrity repair "${APP}"
clean "after the repair"
DEPLOY="$(flatpak info --system --show-location "${APP}")"
FILE="$(find "${DEPLOY}/files" -type f -size +1k -links +1 | head -n1)"
OBJECT="$(find /var/lib/flatpak/repo/objects -samefile "${FILE}" | head -n1)"

# 2. An object written in place, which is the deployed file too
printf 'x' >>"${OBJECT}"
found "an object written in place" "^object:-:${OBJECT}"
truncate -s -1 "${OBJECT}"
clean "the object put back"

# 3. A stray launcher among the installation's exports
printf '[Desktop Entry]\nType=Application\nName=Stray\nExec=sh -c true\n' >/var/lib/flatpak/exports/share/applications/vmlab-stray.desktop
found "a stray launcher" "^stray:-:share/applications/vmlab-stray.desktop"
rm /var/lib/flatpak/exports/share/applications/vmlab-stray.desktop
clean "the stray launcher taken away"

# 4. A file of the account's own app replaced by the account itself: found, and said to it
OWN_DEPLOY="$(as_user "flatpak info --user --show-location ${OWN}")"
OWN_FILE="$(as_user "find '${OWN_DEPLOY}/files' -type f -size +1k | head -n1")"
as_user "cp '${OWN_FILE}' ~/.vmlab-own && { cat ~/.vmlab-own; printf x; } >'${OWN_FILE}.new' && mv '${OWN_FILE}.new' '${OWN_FILE}' && touch ~/.local/share/flatpak/.changed"
before="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"
found "a file of ${TEST_USER}'s own ${OWN} replaced" "^${TEST_USER}:file:account:app/${OWN}/.* critical ${TEST_USER}:"
tail -n +"$((before + 1))" "${HISTORY}" | jq -e -s --arg user "${TEST_USER}" \
    'any(.[]; .key == "app-integrity" and .tell == $user)' >/dev/null &&
    ok "said to ${TEST_USER}" || not_ok "not said to ${TEST_USER}" "$(tail -n 5 "${HISTORY}")"
check "${TEST_USER} puts the app back without a password" session_terminal 900 'Put back' y -- \
    "ame security app-integrity repair ${OWN}"
as_user "rm -f ~/.vmlab-own"
clean "after the account's repair"

# 5. An object of the system's own repository, written through a remount of /sysroot that only this process
# sees, and then put back byte for byte: found, then kept quietly once its content checks out again
BOOTED="$(rpm-ostree status --json | jq -r '[.deployments[] | select(.booted)][0].checksum')"
SYS_OBJECT="$(ostree --repo=/sysroot/ostree/repo ls -R -C "${BOOTED}" /usr/share/licenses 2>/dev/null |
    awk '$1 ~ /^-/ && $4 > 100 { print $5; exit }')"
SYS_PATH="/sysroot/ostree/repo/objects/${SYS_OBJECT:0:2}/${SYS_OBJECT:2}.file"
if [[ -n "${SYS_OBJECT}" && -f "${SYS_PATH}" ]]; then
    check "the system's object is written in place" unshare -m sh -c "mount -o remount,rw /sysroot && printf x >>'${SYS_PATH}'"
    found "an object of the system's own repository changed" "^system:${SYS_PATH} critical"
    grep -q "reinstall from the installer" <<<"${FOUND}" && ok "it says to reinstall" || not_ok "it does not say to reinstall" "${FOUND}"
    check "the system's object is put back" unshare -m sh -c "mount -o remount,rw /sysroot && truncate -s -1 '${SYS_PATH}'"
    clean "the system's object put back"
else
    not_ok "no object of the system's own repository to change" "${BOOTED} ${SYS_OBJECT}"
fi

# 6. The initramfs in /boot, one byte longer. Where /boot is on the system's own filesystem, as on this disk,
# ostree hardlinks it to its object in the repository, and the object is what is found changed; on a /boot of
# its own, as the installer makes it, the copy no longer matches the deployment's
INITRAMFS="$(find /boot/ostree -name 'initramfs-*.img' | head -n1)"
INITRAMFS_OBJECT="$(find /sysroot/ostree/repo/objects -samefile "${INITRAMFS}" 2>/dev/null | head -n1)"
echo "# the initramfs: ${INITRAMFS}${INITRAMFS_OBJECT:+, the object ${INITRAMFS_OBJECT}}"
check "the initramfs grows a byte" unshare -m sh -c "mount -o remount,rw /boot; printf x >>'${INITRAMFS}'"
found "the initramfs changed" "^system:${INITRAMFS_OBJECT:-${INITRAMFS}} critical"
check "the initramfs is put back" unshare -m sh -c "mount -o remount,rw /boot; truncate -s -1 '${INITRAMFS}'"
clean "the initramfs put back"

# The report says what the check found, and nothing when nothing changed
check "the report's app integrity is ok" sh -c "/usr/libexec/amethystora-security-status --json |
    jq -e 'any(.checks[]; .id == \"app-integrity\" and .state == \"ok\")'"

# --- App permissions: code loaded into an app, and the other apps changed --------------------------------------------

perms() { as_user "/usr/libexec/amethystora-app-permissions --json" | jq -r --arg app "$1" '.[] | select(.app == $app) | .reaches[] | "\(.id) \(.granted)"'; }
as_user "flatpak override --user --env=LD_PRELOAD=${HOME_DIR}/x.so ${APP}"
perms "${APP}" | grep -qx "code true" && ok "an override that preloads a library is the code reach, granted" ||
    not_ok "no code reach" "$(perms "${APP}")"
as_user "flatpak override --user --filesystem=~/.local/share/flatpak ${APP}"
perms "${APP}" | grep -qx "installations true" && ok "a grant on the account's own installation is the installations reach" ||
    not_ok "no installations reach" "$(perms "${APP}")"
# Any action but the recipe's own leaves it once the list is printed, with no question asked
as_user "ame security apps list" 2>&1 | grep -q "Change the other apps installed for you" &&
    ok "ame security apps says it" || not_ok "ame security apps does not say it"
as_user "flatpak override --user --reset ${APP}"

# --- Odd processes: a library from a home preloaded, and a session's own environment ----------------------------

check "odd processes goes on" "${config}" set PROCESSES on
systemctl start amethystora-security-watch.service
before="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"
user_bus systemd-run --user --unit=vmlab-preload -E "LD_PRELOAD=${HOME_DIR}/x.so" sleep 600 >/dev/null 2>&1
user_systemctl set-environment "LD_PRELOAD=${HOME_DIR}/y.so"
systemctl start amethystora-security-watch.service
echo "# odd processes in that run: $(jq -r '.timings.PROCESSES' /var/lib/amethystora/security/status.json) ms"
user_systemctl unset-environment LD_PRELOAD
user_systemctl stop vmlab-preload 2>/dev/null
new="$(tail -n +"$((before + 1))" "${HISTORY}" | jq -c 'select(.key == "processes")')"
grep -q "A library from outside the system is loaded into /usr/bin/sleep: ${HOME_DIR}/x.so" <<<"${new}" &&
    ok "a library from a home loaded into a program" || not_ok "the preloaded library was not found" "${new}"
grep -q "Every program started in ${TEST_USER}'s session now loads ${HOME_DIR}/y.so (LD_PRELOAD)" <<<"${new}" &&
    ok "a session whose environment preloads a library" || not_ok "the session's environment was not found" "${new}"
"${config}" set PROCESSES off

flatpak uninstall --system -y --noninteractive "${APP}" >/dev/null 2>&1
as_user "flatpak uninstall --user -y --noninteractive ${OWN}" >/dev/null 2>&1
"${config}" set APP_INTEGRITY off
finish
