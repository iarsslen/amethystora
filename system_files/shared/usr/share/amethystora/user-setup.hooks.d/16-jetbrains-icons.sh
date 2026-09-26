#!/usr/bin/env bash
#
# Give the IDEs JetBrains Toolbox installs their candy-icons.
#
# Toolbox names each IDE's icon after the IDE's window class and an id it makes up per install
# (Icon=jetbrains-idea-8b6042f6-...), copies JetBrains' artwork into hicolor under that name, and
# writes its desktop entries back the way they were every time it starts. Neither the entry nor the
# name can be changed, and the theme cannot know the ids, so each name is answered here from the
# user's own layer of candy-icons, with the icon for its window class (the aliases in 10-icons.sh).
# Nothing of Toolbox's is touched: under any other icon theme the IDE keeps JetBrains' artwork.
# Flatpaks need none of this, being named by app id, which candy-icons draws.
#
# There is no version-script here on purpose: an IDE installed since the last login gets its icon
# at the next one.

set -uo pipefail

DATA="${XDG_DATA_HOME:-${HOME}/.local/share}"
CANDY=/usr/share/icons/candy-icons/apps/scalable
OWN="${DATA}/icons/candy-icons/apps/scalable"

shopt -s nullglob
for entry in "${DATA}"/applications/jetbrains-*.desktop; do
    icon="$(sed -n 's/^Icon=//p' "${entry}" | head -n1)"
    class="$(sed -n 's/^StartupWMClass=//p' "${entry}" | head -n1)"
    # Toolbox's own entry is named plainly (Icon=jetbrains-toolbox), which the theme already draws
    [[ -n ${class} && ${icon} == "${class}-"* && -e "${CANDY}/${class}.svg" ]] || continue
    [[ -e "${OWN}/${icon}.svg" ]] && continue
    mkdir -p "${OWN}" && ln -sf "${CANDY}/${class}.svg" "${OWN}/${icon}.svg"
done

exit 0
