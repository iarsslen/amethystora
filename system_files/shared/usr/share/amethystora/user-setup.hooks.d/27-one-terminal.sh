#!/usr/bin/env bash
#
# Terminal in the app grid was Ptyxis's launcher until kitty's took its name and Ptyxis's was hidden (17-cleanup.sh), so
# a Terminal pinned to the dock is that launcher: pin kitty's in its place, once.

source /usr/lib/amethystora/setup-services/libsetup.sh

command -v gsettings >/dev/null || exit 0

version-script one-terminal user 1 || exit 0

old="'org.gnome.Ptyxis.desktop'"
new="'kitty.desktop'"
pinned="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)" || exit 0
[[ "${pinned}" == *"${old}"* ]] || exit 0
if [[ "${pinned}" == *"${new}"* ]]; then
    pinned="$(sed -E "s/${old}(, )?//; s/, \]/]/" <<<"${pinned}")"
else
    pinned="${pinned/"${old}"/"${new}"}"
fi
gsettings set org.gnome.shell favorite-apps "${pinned}"

exit 0
