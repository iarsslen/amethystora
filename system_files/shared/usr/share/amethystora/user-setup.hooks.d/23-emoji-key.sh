#!/usr/bin/env bash
#
# Super+. is the emoji and symbols picker of Amethystora UI now, which types where the text cursor is; Smile, the emoji
# app, keeps Ctrl+Alt+Space. The image's second key for Smile (custom6) went with the update, from the system's
# keybindings. An account that wrote that entry into its own settings, with the image's own key and command, would
# still take Super+. from the picker: its key is reset, so that the picker answers. A key the account chose itself
# for that entry, or another command, is its own and is left as it is.
#
# Once.

source /usr/lib/amethystora/setup-services/libsetup.sh

command -v dconf >/dev/null || exit 0

version-script emoji-key user 1 || exit 0

ENTRY=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/
if [[ "$(dconf read "${ENTRY}binding")" == "'<Super>period'" &&
    "$(dconf read "${ENTRY}command")" == "'flatpak run it.mijorus.smile'" ]]; then
    dconf reset "${ENTRY}binding"
fi

exit 0
