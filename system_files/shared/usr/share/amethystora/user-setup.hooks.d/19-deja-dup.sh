#!/usr/bin/env bash
#
# Déjà Dup left the apps every machine comes with (amethystora.preinstall), and Flatpak uninstalls an app
# taken off that list from the machines that got it from there. An account whose Déjà Dup backed it up on a
# schedule would then stop being backed up without a word, so it is told, once, a minute into the first login
# after Déjà Dup is gone. Its backups stay where they are, and Déjà Dup from Bazaar still restores them.
#
# Not a version-script: Flatpak may uninstall it after this login, and the account is told at the next one.

STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/amethystora/deja-dup-notice"
[[ -e "${STATE}" ]] && exit 0

# The Flatpak's settings: it has no dconf access, so GLib keeps them in a keyfile in the app's own folder,
# where they stay after it is uninstalled. periodic is false unless the account turned the schedule on.
KEYFILE="${HOME}/.var/app/org.gnome.DejaDup/config/glib-2.0/settings/keyfile"
[[ -f "${KEYFILE}" && ! -L "${KEYFILE}" ]] || exit 0
awk '/^\[/ { group = $0 } group == "[org/gnome/deja-dup]" && /^periodic=true$/ { found = 1 } END { exit !found }' \
    "${KEYFILE}" || exit 0
# Still installed, from here or by hand: it goes on backing up
flatpak info org.gnome.DejaDup >/dev/null 2>&1 && exit 0

mkdir -p "${STATE%/*}"
: >"${STATE}"
systemd-run --user --collect --quiet --on-active=60 -- /usr/libexec/amethystora-deja-dup-notice
exit 0
