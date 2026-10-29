#!/usr/bin/env bash
#
# Keep a computer an account had already paired with the phone link (a KDE desktop: the protocol pairs computers too)
# where it was. The switch for other computers (org.amethystora.Connect computers, plans/beyond/spec-r4-later.md part A)
# came off as shipped, and off it hides every paired computer: for an account whose pairings hold one, it is turned on
# once, as the account had it. Any type that is not a phone, tablet or television is a computer to the program.

source /usr/lib/amethystora/setup-services/libsetup.sh

command -v gsettings >/dev/null && command -v jq >/dev/null || exit 0

version-script phone-computers user 1 || exit 0

DEVICES="${XDG_CONFIG_HOME:-${HOME}/.config}/amethystora/connect/devices.json"
[[ -f "${DEVICES}" && ! -L "${DEVICES}" ]] || exit 0
jq -e '[.devices[]?.type] | any(. != "phone" and . != "tablet" and . != "tv")' "${DEVICES}" >/dev/null 2>&1 || exit 0

gsettings set org.amethystora.Connect computers true

exit 0
