#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The icon packs, Glass, Neon and Duotone, are Amethystora's own: branding/icons.mjs draws them into system_files
# (usr/share/icons/amethystora-*), and every other maker's app keeps the icon it ships, so there is nothing to
# download, trim or alias here. What is left is each pack's cache.
#
# The cache only speeds icon lookups up, so a theme it will not build is a warning, not a failure.
if command -v gtk-update-icon-cache >/dev/null; then
    for pack_dir in /usr/share/icons/amethystora-{glass,neon,duotone}; do
        gtk-update-icon-cache --force --quiet "${pack_dir}" ||
            echo "::warning::could not build the icon cache for ${pack_dir}"
    done
fi

echo "::endgroup::"
