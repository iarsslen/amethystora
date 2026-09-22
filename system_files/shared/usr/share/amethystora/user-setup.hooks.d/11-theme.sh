#!/usr/bin/env bash
#
# Apply the Amethystora theme once, at first login, so a new account starts with the terminal
# palette, prompt and wallpaper already matching the desktop. After that the theme is the user's:
# this only runs again when the version below is raised, which is how an account picks up something
# the theme system has learnt to set since it was set up. Raising it re-applies the account's own
# theme rather than the default, so a theme the user chose is kept.
#
#   2  the candy-icons icon theme (build_files/base/10-icons.sh). Accounts set up before it existed
#      hold an explicit icon-theme in their dconf, which wins over the image's new default, so they
#      would stay on the desktop's plain icons until the theme is applied again.
#   3  the theme mirror in ~/.themes and the libadwaita user stylesheet that imports from it
#      (theme-set.hooks.d/20-gtk-apps.sh). Accounts set up before it existed have neither, so every
#      Flatpak application on them keeps the runtime's stock Adwaita until the theme is applied again.
#   4  the kitty palette (themed/kitty.conf.tpl), which /etc/xdg/kitty/kitty.conf includes. Accounts
#      set up before kitty became the terminal have no rendered copy, so kitty would open unthemed.
#   5  the account after user-setup.hooks.d/09-retire-dms.sh, which runs just before this and removes
#      what DankMaterialShell left from the Hyprland era. Its gtk.css carried no amethystora-theme
#      marker, so 20-gtk-apps.sh had taken it for the user's own and never written the theme's.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script theme user 5 || exit 0

set -xeuo pipefail

/usr/bin/amethystora-theme set "$(/usr/bin/amethystora-theme current 2>/dev/null || echo amethystora)"
