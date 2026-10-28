#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The icon packs (ICON_PACKS in the theme library) are Amethystora's own: branding/icons.mjs draws them into system_files
# (usr/share/icons/amethystora-*), and every other maker's app keeps the icon it ships, so there is nothing to
# download, trim or alias here. What is left is each pack's cache.
#
# The cache only speeds icon lookups up, so a theme it will not build is a warning, not a failure.
if command -v gtk-update-icon-cache >/dev/null; then
    for pack in $(source /usr/lib/amethystora/theme/lib.sh && echo "${ICON_PACKS[*]}"); do
        pack_dir="/usr/share/icons/amethystora-${pack}"
        gtk-update-icon-cache --force --quiet "${pack_dir}" ||
            echo "::warning::could not build the icon cache for ${pack_dir}"
    done
fi

# The pointers (POINTER_SETS) are cursor themes, with no cache. branding/cursors.mjs writes one file per drawing and
# the set's `aliases` table, "name file" a line, of every other name a toolkit asks for: each becomes a link here,
# relative and in the same folder as cursor themes ship them, since a container layer would store a copy in full: in
# cursors/ (Xcursor files, for X11 and GTK 3) and in cursors_scalable/ (a folder of SVG frames, GNOME Shell 51's own).
# Some 560 links: not traced line by line, a count for each set instead, and a line for any that cannot be made.
set +x
for set in $(source /usr/lib/amethystora/theme/lib.sh && echo "${POINTER_SETS[*]}"); do
    set_dir="/usr/share/icons/amethystora-pointer-${set}"
    links=0
    while read -r alias target; do
        [[ -z "${alias}" || "${alias}" == \#* ]] && continue
        [[ -f "${set_dir}/cursors/${target}" && ! -L "${set_dir}/cursors/${target}" &&
            -f "${set_dir}/cursors_scalable/${target}/metadata.json" ]] ||
            { echo "${set_dir}/aliases: ${alias} names ${target}, which is not a drawing of the set"; exit 1; }
        ln -sfn "${target}" "${set_dir}/cursors/${alias}"
        ln -sfn "${target}" "${set_dir}/cursors_scalable/${alias}"
        links=$((links + 1))
    done <"${set_dir}/aliases"
    echo "amethystora-pointer-${set}: ${links} other names linked in cursors/ and cursors_scalable/"
done
set -x

echo "::endgroup::"
