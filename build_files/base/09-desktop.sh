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
AMETHYSTORA_KEYBINDINGS=(20 21 22 23 24 25 26)

paths=""
for index in "${AMETHYSTORA_KEYBINDINGS[@]}"; do
    paths+=", '${CUSTOM_PATH}/custom${index}/'"
    grep -q "^\[${CUSTOM_PATH#/}/custom${index}\]$" /etc/dconf/db/distro.d/06-amethystora-keybindings
done

sed -i "/^custom-keybindings=/ s|\]|${paths}&|" "${OVERRIDE}"
grep -q "custom${AMETHYSTORA_KEYBINDINGS[0]}/'" "${OVERRIDE}"

# The panel's command menu is the mouse way to the same things the keys reach. Its entries are
# appended to the base image's, for the same reason as above; the numbers start at 20 to leave
# room for it to add its own.
COMMAND_MENU=/etc/dconf/db/distro.d/04-bluefin-custom-command-menu
if [[ -f ${COMMAND_MENU} ]]; then
    cat >>"${COMMAND_MENU}" <<'EOF'

command20=('---Amethystora', '', '', true)
command21=('Theme', 'amethystora-menu theme', '', true)
command22=('Next background', 'amethystora-theme bg next', '', true)
command23=('Keybindings', 'amethystora-menu keys', '', true)
EOF
    sed -i "/^command-order=/ s|\]|, 20, 21, 22, 23]|" "${COMMAND_MENU}"
    grep -q "^command-order=.*, 23\]$" "${COMMAND_MENU}"
else
    echo "::warning::${COMMAND_MENU} not found, skipping the Amethystora panel menu entries"
fi

rm -f /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

echo "::endgroup::"
