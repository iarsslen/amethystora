#!/usr/bin/env bash
#
# Take away what the Electron windows of an earlier image left in the account's ~/.config.
#
# Each of Amethystora's apps kept the profile of the Chromium inside it in a folder named after the app:
# its caches, and its page's local storage, which held nothing but how the window was last left. The
# apps are GTK windows now (apps/), which keep that in ~/.local/state/amethystora and never read these
# folders. Notes keeps the notes themselves in ~/.local/share/amethystora-notes, which stays.
#
# Only those seven folders go, and only one that is a Chromium profile, with Chromium's Local State in
# it: a folder of that name that is anything else stays.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script retire-electron-profiles user 1 || exit 0

CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}"

for app in manual security update notes logs backups control; do
    profile="${CONFIG}/amethystora-${app}"
    if [[ -d ${profile} && ! -L ${profile} && -f "${profile}/Local State" ]]; then
        rm -rf -- "${profile}"
    fi
done

exit 0
