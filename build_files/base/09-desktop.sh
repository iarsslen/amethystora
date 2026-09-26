#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Wire the Amethystora desktop defaults that cannot be expressed as a plain gschema override.
#
# The keybinding entries themselves are in /etc/dconf/db/distro.d/06-amethystora-keybindings, but
# custom-keybindings is a list of paths that GNOME only reads bindings from. The base image already
# ships six of them, so the Amethystora paths are appended to that list instead of restating it,
# which would silently drop the base image's bindings whenever it changes them.

OVERRIDE=/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override
CUSTOM_PATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings

# Keep in step with 06-amethystora-keybindings
AMETHYSTORA_KEYBINDINGS=(20 21 22 23 24 25 26 27 28)

paths=""
for index in "${AMETHYSTORA_KEYBINDINGS[@]}"; do
    paths+=", '${CUSTOM_PATH}/custom${index}/'"
    grep -q "^\[${CUSTOM_PATH#/}/custom${index}\]$" /etc/dconf/db/distro.d/06-amethystora-keybindings
done

sed -i "/^custom-keybindings=/ s|\]|${paths}&|" "${OVERRIDE}"
grep -q "custom${AMETHYSTORA_KEYBINDINGS[0]}/'" "${OVERRIDE}"

# The dash: Brave takes Firefox's slot, since 04-packages.sh drops Firefox from the image. The rest of
# the base image's pinned apps are left alone, so its future changes to them still come through.
test -f /usr/share/applications/brave-browser.desktop
sed -i "/^favorite-apps *=/ s|'org\.mozilla\.firefox\.desktop'|'brave-browser.desktop'|" "${OVERRIDE}"
grep -q "^favorite-apps *=.*'brave-browser\.desktop'" "${OVERRIDE}"
grep -qi "firefox" "${OVERRIDE}" && false

# The Logo Menu's panel icon, second half of the change 06-branding.sh makes to the extension's
# dconf defaults: the coloured gem instead of the symbolic silhouette GNOME repaints panel-white.
# The dconf file is what the extension actually reads, since its schema lives in its own directory
# rather than here, but the base image states the same two keys in this override as well; they are
# kept in step so the two never contradict each other. Section-scoped, the keys are not unique.
LOGOMENU_SECTION='/^\[org\.gnome\.shell\.extensions\.Logo-menu\]$/,/^\[/'
sed -i \
    -e "${LOGOMENU_SECTION} s|^symbolic-icon=.*|symbolic-icon=false|" \
    -e "${LOGOMENU_SECTION} s|^menu-button-icon-image=.*|menu-button-icon-image=29|" \
    "${OVERRIDE}"
logomenu_override="$(sed -n "${LOGOMENU_SECTION}p" "${OVERRIDE}")"
grep -q "^symbolic-icon=false$" <<<"${logomenu_override}"
grep -q "^menu-button-icon-image=29$" <<<"${logomenu_override}"

# No panel command menu here: the entries the base image fills belong to the Custom Command List
# extension (dconf path org/gnome/shell/extensions/custom-command-list), which this image does not
# install. The pinned projectbluefin/common ships 04-bluefin-logomenu-extension, which only sets the
# Logo Menu's own fixed entries. Adding the menu back means installing that extension and writing the
# whole dconf file here, not appending to the base image's.

rm -f /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

echo "::endgroup::"
