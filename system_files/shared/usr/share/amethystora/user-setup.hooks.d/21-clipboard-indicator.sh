#!/usr/bin/env bash
#
# Carry what an account set in Clipboard Indicator over to Amethystora Clipboard, the copy of it that seals
# the history, which took its place in the image.
#
# What the account changed under Clipboard Indicator's path is loaded under the copy's, less
# cache-only-favorites, which the copy replaced with keep-history (Control's Clipboard history), and the old
# path is reset. The history Clipboard Indicator left in plain text in ~/.cache is the extension's to take
# over: it seals it the next time it starts with the keyring unlocked, and only then deletes it.
#
# Once, and not while the account's own Clipboard Indicator is installed, whose settings these still are.

source /usr/lib/amethystora/setup-services/libsetup.sh

[[ -e "${XDG_DATA_HOME:-${HOME}/.local/share}/gnome-shell/extensions/clipboard-indicator@tudmotu.com" ]] && exit 0
command -v dconf >/dev/null || exit 0

version-script clipboard-indicator user 1 || exit 0

OLD=/org/gnome/shell/extensions/clipboard-indicator/
NEW=/org/gnome/shell/extensions/amethystora-clipboard/

settings="$(dconf dump "${OLD}" | grep -v '^cache-only-favorites=')"
if grep -q '=' <<<"${settings}"; then
    dconf load "${NEW}" <<<"${settings}"
fi
dconf reset -f "${OLD}"

exit 0
