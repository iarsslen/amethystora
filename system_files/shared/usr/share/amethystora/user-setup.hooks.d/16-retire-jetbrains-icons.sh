#!/usr/bin/env bash
#
# Take back the candy-icons an earlier image gave the IDEs JetBrains Toolbox installs.
#
# Toolbox names each IDE's icon after an id it makes up per install (jetbrains-idea-8b6042f6-...), so
# that image answered each name with a link, in the account's own layer of candy-icons, to the
# theme's drawing of the IDE. The theme no longer redraws anybody's logo (build_files/base/10-icons.sh):
# JetBrains allows its logos unaltered only. The drawings are gone and the links point at nothing,
# and a name the theme lists but cannot load leaves the launcher blank instead of falling back to
# the artwork Toolbox put in hicolor. With the links gone, that artwork is what shows.
#
# Only those links go: a dangling jetbrains-* link in that one directory. An icon put there by hand
# is a file or a link that still leads somewhere, and stays.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script retire-jetbrains-icons user 1 || exit 0

OWN="${XDG_DATA_HOME:-${HOME}/.local/share}/icons/candy-icons/apps/scalable"

if [[ -d ${OWN} ]]; then
    find "${OWN}" -maxdepth 1 -xtype l -name 'jetbrains-*.svg' -delete
    # The directories were made for those links alone; one that holds anything else stays
    rmdir "${OWN}" "${OWN%/*}" "${OWN%/*/*}" 2>/dev/null
fi

exit 0
