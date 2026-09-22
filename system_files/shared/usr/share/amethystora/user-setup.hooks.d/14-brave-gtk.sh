#!/usr/bin/env bash
#
# Hand Brave's title bar to GTK in the profiles that already exist, once per profile.
#
# Brave draws its own window buttons unless its theme is set to GTK, and only a title bar GTK draws
# wears the theme's window buttons, the three lights of build_files/base/11-gtk-theme.sh. Profiles
# created from now on start that way, from /usr/lib/brave.com/brave/initial_preferences; this is
# the same setting for the ones made before it. There is no policy for it.
#
# The setting is extensions.theme.system_theme: 1 for GTK, 0 for Brave's own, 2 for Qt. Chromium
# does not guard it against outside edits, so it is not reverted as tampering.
#
# Brave rewrites the whole file when it exits, so a profile is only touched while Brave is closed;
# otherwise this waits for the next login, which is why there is no version-script here. Each
# profile is done once and then left alone, so switching it back in Brave's settings sticks.

set -uo pipefail

command -v jq >/dev/null || exit 0
pgrep -u "${UID}" -x brave >/dev/null && exit 0

STAMPS="${XDG_STATE_HOME:-${HOME}/.local/state}/amethystora/brave-gtk"

shopt -s nullglob
# The package, and the Flatpak for anyone who has installed that instead
for prefs in "${XDG_CONFIG_HOME:-${HOME}/.config}"/BraveSoftware/Brave-Browser/{Default,Profile\ *}/Preferences \
    "${HOME}"/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/{Default,Profile\ *}/Preferences; do
    [[ -f ${prefs} ]] || continue
    stamp="${STAMPS}/$(printf '%s' "${prefs}" | sha256sum | cut -c1-16)"
    [[ -e ${stamp} ]] && continue

    # Written beside the original and moved over it, with the original's permissions (0600, it
    # holds the profile's settings), so an interrupted run never leaves a half-written file
    if jq -c '.extensions.theme.system_theme = 1' "${prefs}" >"${prefs}.amethystora" &&
        chmod --reference="${prefs}" "${prefs}.amethystora" &&
        mv -f "${prefs}.amethystora" "${prefs}"; then
        mkdir -p "${STAMPS}" && : >"${stamp}"
        echo "Brave profile ${prefs%/Preferences} now takes its title bar from GTK"
    else
        rm -f "${prefs}.amethystora"
    fi
done

exit 0
