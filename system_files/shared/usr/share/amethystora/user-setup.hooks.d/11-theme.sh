#!/usr/bin/env bash
#
# Apply the default Amethystora theme once, at first login, so a new account starts with the
# terminal palette, prompt and wallpaper already matching the desktop. After that the theme is the
# user's: this never runs again unless the version below is raised.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script theme user 1 || exit 0

set -xeuo pipefail

/usr/bin/amethystora-theme set amethystora
