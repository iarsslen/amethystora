#!/usr/bin/bash
# Amethystora Clipboard (plans/PLAN-clipboard.md): the clipboard history sealed under a key in the login keyring.
# Copied to as apps copy (wl-copy, and copy.py's own window), read back as the menu shows it (atspi.py) and as
# the disk holds it (opened with the keyring's key). The lab signs the account in by itself, which leaves its
# login keyring locked after a restart, as a fingerprint does: that stands in for one. Three phases:
#   1. At login no keyring, then one unlocked with the account's password, as a password login unlocks it:
#      Clipboard Indicator's plain history and a setting of it taken over; what is copied, pictures too, sealed
#      and nowhere in the clear; a password manager's copy and an excluded app's not recorded; the history
#      outlasts the screen lock; a hundred copies in a burst. keep-history set to restart, as Control does.
#   2. After a restart, the keyring locked: the menu offers to unlock, the earlier items stay sealed, a new copy
#      is in memory only; the row clicked and the password typed in GNOME's prompt: the two merged, and of the
#      earlier ones only the pinned item, under restart. keep-history set to always.
#   3. After another restart: everything kept, and nothing the extension threw in the three boots.
source "$(dirname "$0")/lib.sh"

UUID=amethystora-clipboard@iarsslen.github.io
SCHEMA=org.gnome.shell.extensions.amethystora-clipboard
HELPER=/usr/libexec/amethystora-clipboard-seal
HOME_DIR="/var/home/${TEST_USER}"
STORE="${HOME_DIR}/.local/state/amethystora/clipboard"
OLD="${HOME_DIR}/.cache/clipboard-indicator@tudmotu.com"
LOGIN=/org/freedesktop/secrets/collection/login
OWN=/run/vmlab-91
TESTS=/var/lib/vmlab-tests/91

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi

install -d -m 0700 "${TESTS}"
if [[ "${SUITE_PHASE}" == 1 ]]; then
    printf 'RUN=%s\nSTART=%s\n' "$(date +%s)${RANDOM}" "$(date +%s)" >"${TESTS}/markers"
fi
# shellcheck source=/dev/null
source "${TESTS}/markers"
COPIED="vmlab-copied-${RUN}"
PINNED="vmlab-pinned-${RUN}"
WINDOW="vmlab-window-${RUN}"
SECRET="vmlab-secret-${RUN}"
KEEPASS="vmlab-keepass-${RUN}"
LOCKED="vmlab-locked-${RUN}"
ALWAYS="vmlab-always-${RUN}"
mapfile -t PNG < <(find /usr/share/icons/hicolor/48x48/apps -name '*.png' -size +1k | sort | head -n 2)

mkdir -p "${OWN}"
install -m 0644 "$(dirname "$0")/atspi.py" "$(dirname "$0")/copy.py" "${OWN}/"
chmod -R a+rX "${OWN}"
keys() { python3 "$(dirname "$0")/keys.py" "$@"; }
shell() { user_bus python3 "${OWN}/atspi.py" gnome-shell "$@"; }
# wl_copy ARGS: wl-copy in the account's session, serving the clipboard until something else takes it
wl_copy() {
    user_bus systemd-run --user --quiet --collect -- wl-copy --foreground "$@"
    sleep 2
}
copy_picture() {
    user_bus systemd-run --user --quiet --collect -- bash -c 'exec wl-copy --foreground --type image/png <"$1"' _ "$1"
    sleep 2
}
# copy_window MODE TEXT: from copy.py's window, which gets the focus as an app's does
copy_window() { user_bus systemd-run --user --pipe --wait --quiet --collect -- python3 "${OWN}/copy.py" "$@"; }

ext_state() { user_bus gnome-extensions info "${UUID}" 2>/dev/null | sed -n 's/^ *State: *//p'; }
keyring_says() { user_bus busctl --user get-property org.freedesktop.secrets "${LOGIN}" org.freedesktop.Secret.Collection Locked 2>/dev/null; }
keyring_open() { [[ "$(keyring_says)" == "b false" ]]; }
keyring_locked() { [[ "$(keyring_says)" == "b true" ]]; }
# What pam_gnome_keyring does at a password login: the login keyring unlocked, or made, with the password
unlock_keyring() { printf '%s' "${TEST_USER}" | user_bus gnome-keyring-daemon --unlock >/dev/null 2>&1; }

# The sealed history opened with the key the keyring holds (only while it is open: asking a locked one would
# bring up GNOME's prompt), as JSON
history() {
    local key
    keyring_open && [[ -f "${STORE}/history" ]] || return 1
    key="$(user_bus secret-tool lookup purpose history-key 2>/dev/null)"
    [[ -n "${key}" ]] || return 1
    { printf '%s\n' "${key}"; cat "${STORE}/history"; } | "${HELPER}" open history
}
in_history() { history | jq -e --arg t "$1" '.entries | any(.contents == $t)' >/dev/null; }
not_in_history() { history >/dev/null && ! in_history "$1"; }
pinned() { history | jq -e --arg t "$1" '.entries | any(.contents == $t and .favorite)' >/dev/null; }
pictures() { history | jq '[.entries[] | select(.mimetype | startswith("image/"))] | length'; }
pictures_at_least() { [[ "$(pictures)" -ge "$1" ]]; }
all_kept() { in_history "${ALWAYS}" && in_history "${LOCKED}" && in_history "${PINNED}"; }
# Whether any file in the home holds TEXT as it was copied
in_the_clear() { grep -rlaF -- "$1" "${HOME_DIR}" 2>/dev/null | grep -q .; }
nowhere_in_the_clear() { ! in_the_clear "$1"; }
# Whether any file in the home is a copy of the picture FILE
picture_in_the_clear() {
    find "${HOME_DIR}" -type f -size "$(stat -c %s "$1")c" -exec cmp -s "$1" {} \; -print 2>/dev/null | grep -q .
}
# menu_shows TEXT: the history opened with its key, TEXT waited for in it, and closed again
menu_shows() {
    local found=1
    keys super+shift+v
    shell wait 15 "$1" >/dev/null && found=0
    keys esc
    return "${found}"
}
menu_lacks() {
    local lacks=1
    keys super+shift+v
    sleep 3
    shell has "$1" >/dev/null || lacks=0
    keys esc
    return "${lacks}"
}
session_id() { loginctl show-user "${TEST_USER}" -p Display --value; }
screen_locked() { [[ "$(loginctl show-session "$(session_id)" -p LockedHint --value 2>/dev/null)" == yes ]]; }
screen_unlocked() { ! screen_locked; }
keep() { user_bus gsettings get "${SCHEMA}" keep-history 2>/dev/null; }

# GNOME's overview, where a session starts, takes keys for its search: a click on its workspace leaves it
keys click:0.5,0.5

case "${SUITE_PHASE}" in
1)
    check "Clipboard Indicator is not in the image" test ! -e /usr/share/gnome-shell/extensions/clipboard-indicator@tudmotu.com
    state="$(ext_state)"
    [[ "${state}" =~ ^(ACTIVE|ENABLED)$ ]] && ok "Amethystora Clipboard is on in the session" ||
        not_ok "Amethystora Clipboard is not on in the session" "State: ${state}" "$(user_bus gnome-extensions info "${UUID}" 2>&1)"

    # Signed in by GDM, the account has no login keyring yet: nothing is kept, and the menu says so
    if [[ -z "$(keyring_says)" ]]; then
        check "with no keyring, the menu says nothing is saved" menu_shows "Not saved"
    else
        skip "the account already had a login keyring: $(keyring_says)"
    fi

    # What Clipboard Indicator left: its plain history with a pinned item and a picture, and a setting
    install -d -o "${TEST_USER}" -g "${TEST_USER}" "${HOME_DIR}/.cache" "${OLD}"
    install -o "${TEST_USER}" -g "${TEST_USER}" -m 0644 "${PNG[0]}" "${OLD}/0123abcd"
    printf '[{"favorite":true,"mimetype":"text/plain;charset=utf-8","contents":"%s"},{"favorite":false,"mimetype":"image/png","contents":"%s/0123abcd"}]' \
        "${PINNED}" "${OLD}" >"${OLD}/registry.txt"
    chown "${TEST_USER}:" "${OLD}/registry.txt"
    user_bus dconf write /org/gnome/shell/extensions/clipboard-indicator/history-size 30
    versions="${HOME_DIR}/.local/share/amethystora/setup_versioning.json"
    if [[ -f "${versions}" ]]; then
        jq 'del(.version.user."clipboard-indicator")' "${versions}" >"${versions}.vmlab" && cat "${versions}.vmlab" >"${versions}"
        rm -f "${versions}.vmlab"
    fi
    user_bus bash /usr/share/amethystora/user-setup.hooks.d/21-clipboard-indicator.sh >/dev/null 2>&1
    if [[ "$(user_bus gsettings get "${SCHEMA}" history-size)" == 30 &&
        -z "$(user_bus dconf dump /org/gnome/shell/extensions/clipboard-indicator/)" ]]; then
        ok "Clipboard Indicator's setting is carried over and its own taken away (21-clipboard-indicator.sh)"
    else
        not_ok "Clipboard Indicator's setting was not carried over" "history-size: $(user_bus gsettings get "${SCHEMA}" history-size)" \
            "left: $(user_bus dconf dump /org/gnome/shell/extensions/clipboard-indicator/)"
    fi
    user_bus gsettings reset "${SCHEMA}" history-size

    # The login keyring made and unlocked with the password, and the default one, as at a password login
    unlock_keyring
    user_bus busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service \
        ReadAlias s default 2>/dev/null | grep -qF "${LOGIN}" ||
        user_bus busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service \
            SetAlias so default "${LOGIN}" >/dev/null 2>&1
    check "the login keyring is unlocked with the account's password" wait_for 20 keyring_open

    # Asked again when the menu opens, the keyring now gives the key: Clipboard Indicator's history is taken over
    check "the menu shows Clipboard Indicator's pinned item, once the keyring is open" menu_shows "${PINNED}"
    check "the history is sealed under a key the keyring keeps" wait_for 30 in_history "${PINNED}"
    check "Clipboard Indicator's item stays pinned" pinned "${PINNED}"
    check "and its picture is kept, sealed" wait_for 20 pictures_at_least 1
    check "its plain history and pictures are gone" wait_for 30 test ! -e "${OLD}"

    wl_copy -- "${COPIED}"
    check "a text copied is in the sealed history" wait_for 20 in_history "${COPIED}"
    copy_picture "${PNG[1]}"
    check "a picture copied is in it too" wait_for 20 pictures_at_least 2
    check "the store is the account's alone (0700), its files 0600" sh -c \
        "[[ \$(stat -c %a '${STORE}') == 700 ]] && ! find '${STORE}' -type f ! -perm 0600 | grep -q ."
    for text in "${COPIED}" "${PINNED}"; do
        in_the_clear "${text}" && not_ok "${text} is in the clear in: $(grep -rlaF -- "${text}" "${HOME_DIR}" | head -n 3)" ||
            ok "${text%-*} is nowhere in the home in the clear"
    done
    for picture in "${PNG[@]}"; do
        picture_in_the_clear "${picture}" && not_ok "the picture ${picture##*/} is in the home as it was copied" ||
            ok "the picture ${picture##*/} is nowhere in the home as it was copied"
    done

    # A window's copy is recorded; a password manager's marked secret, and KeePassXC's own, are not
    copy_window text "${WINDOW}"
    if wait_for 20 in_history "${WINDOW}"; then
        ok "a window's copy is recorded (copy.py works here)"
        copy_window secret "${SECRET}"
        sleep 3
        check "a copy marked x-kde-passwordManagerHint: secret is not recorded" not_in_history "${SECRET}"
        check "nor written anywhere" nowhere_in_the_clear "${SECRET}"
        copy_window keepass "${KEEPASS}"
        sleep 3
        check "a copy made in KeePassXC's window is not recorded (excluded-apps)" not_in_history "${KEEPASS}"
    else
        not_ok "copy.py's window did not get its copy recorded, so the password manager checks cannot run" \
            "$(user_bus journalctl --user -b --since "-60s" --no-pager -o cat 2>/dev/null | tail -n 10)"
    fi

    # The screen lock disables the extension and unlocking enables it: the history is read back, sealed
    loginctl lock-session "$(session_id)"
    if wait_for 30 screen_locked; then
        sleep 3
        keys esc
        sleep 2
        keys "text:${TEST_USER}" return
        if wait_for 30 screen_unlocked; then
            keys click:0.5,0.5
            check "after the screen lock the menu still shows what was copied before it" menu_shows "${COPIED}"
        else
            not_ok "the screen did not unlock with the password"
            loginctl unlock-session "$(session_id)"
        fi
    else
        not_ok "the screen did not lock"
    fi

    # A hundred copies in a burst
    shell_pid="$(pgrep -u "${TEST_USER}" -x gnome-shell)"
    for i in $(seq 1 100); do
        user_bus systemd-run --user --quiet --collect -- wl-copy --foreground -- "vmlab-burst-${i}-${RUN}"
        sleep 0.2
    done
    sleep 5
    check "GNOME Shell outlives a hundred copies in a burst" [ "$(pgrep -u "${TEST_USER}" -x gnome-shell)" == "${shell_pid}" ]
    unpinned="$(history | jq '[.entries[] | select(.favorite | not)] | length')"
    [[ "${unpinned}" =~ ^[0-9]+$ && "${unpinned}" -le 15 ]] && ok "the sealed history holds ${unpinned} items not pinned, at most 15" ||
        not_ok "the sealed history holds ${unpinned:-?} items not pinned"

    # How long it is kept, as Control sets it
    user_bus bash -lc 'ame desktop clipboard restart' >/dev/null
    check "ame desktop clipboard restart sets keep-history" [ "$(keep)" == "'restart'" ]
    reboot_and_continue
    ;;
2)
    # Signed in by GDM again, with no password: the login keyring is locked, as after a fingerprint
    check "the login keyring is locked after a login without the password" wait_for 30 keyring_locked
    check "the menu offers to unlock the earlier items" menu_shows "Unlock to see earlier items"
    check "and does not show them while locked" menu_lacks "${PINNED}"
    written="$(stat -c %Y "${STORE}/history")"
    wl_copy -- "${LOCKED}"
    check "a copy made while locked is in the menu" menu_shows "${LOCKED}"
    check "and on no disk: the sealed history is untouched" [ "$(stat -c %Y "${STORE}/history")" == "${written}" ]
    in_the_clear "${LOCKED}" && not_ok "the copy made while locked is in the clear" || ok "the copy made while locked is nowhere in the clear"

    # The row clicked, GNOME's own prompt for the keyring answered with the password
    keys super+shift+v
    shell click "Unlock to see earlier items" >/dev/null
    sleep 4
    keys "text:${TEST_USER}" return
    check "the row's prompt unlocks the keyring" wait_for 30 keyring_open
    check "the history is written again, with the copy made while locked" wait_for 30 in_history "${LOCKED}"
    check "and the pinned item from before" pinned "${PINNED}"
    check "keep-history restart dropped what was not pinned before the restart" not_in_history "${COPIED}"
    check "the menu shows the pinned item from before" menu_shows "${PINNED}"

    user_bus bash -lc 'ame desktop clipboard always' >/dev/null
    check "ame desktop clipboard always sets keep-history" [ "$(keep)" == "'always'" ]
    wl_copy -- "${ALWAYS}"
    check "a copy is sealed at once with the keyring open" wait_for 20 in_history "${ALWAYS}"
    reboot_and_continue
    ;;
3)
    # As a password login unlocks it; the menu asks the keyring again when it opens
    unlock_keyring
    check "the keyring is unlocked" wait_for 20 keyring_open
    check "under always, what was copied before the restart is in the menu" menu_shows "${ALWAYS}"
    check "and in the sealed history: both copies and the pinned item" all_kept

    uid="$(id -u "${TEST_USER}")"
    errors="$(journalctl _UID="${uid}" --since "@${START}" --no-pager -o cat 2>/dev/null |
        grep -E "JS ERROR|had error|Error:" | grep -iF -e "${UUID}" -e "Amethystora Clipboard" | sort -u | head -n 20)"
    [[ -z "${errors}" ]] && ok "the extension threw nothing in three boots" || not_ok "the extension threw" "${errors}"
    crashes="$(coredumpctl list --since "@${START}" --no-legend --no-pager 2>/dev/null | grep -w gnome-shell)"
    [[ -z "${crashes}" ]] && ok "GNOME Shell did not crash" || not_ok "GNOME Shell crashed" "${crashes}"

    user_bus gsettings reset "${SCHEMA}" keep-history
    ;;
esac
finish
