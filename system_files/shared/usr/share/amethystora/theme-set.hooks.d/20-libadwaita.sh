#!/usr/bin/bash
#
# Carry the theme's GTK stylesheet into the libadwaita applications, which will not take it any
# other way.
#
# Setting gtk-theme is enough for GTK3, and for the GTK4 applications that use the toolkit's own
# stylesheet. libadwaita ignores it: it always loads its own, and the one opening left is the user
# stylesheet at ~/.config/gtk-4.0/gtk.css, which GTK reads last and so on top of everything else.
# Files, Settings, Text Editor and most of GNOME are libadwaita, so without this the theme stops at
# the edge of the applications it is most visible in.
#
# The file written is a one-line import rather than a copy, so a rebuilt theme is picked up without
# reapplying, and so the relative url(../assets/...) in the stylesheet keeps resolving against the
# theme directory rather than against the home directory.
#
# This is the unsupported half of GTK theming: the user stylesheet overrides libadwaita's own, and a
# GNOME major release can change what it is overriding. Nothing here can break an application's
# behaviour, only how it is painted, and removing the file below puts everything back.
#
# Run by amethystora-theme with AMETHYSTORA_THEME and AMETHYSTORA_THEME_DIR set.

set -euo pipefail

GTK4_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/gtk-4.0"
USER_STYLESHEET="${GTK4_DIR}/gtk.css"
# A CSS comment, because GTK parses this file and '#' starts a selector, not a comment
MARKER="/* written by amethystora-theme"

THEME_NAME="$(head -n1 "${AMETHYSTORA_THEME_DIR}/gtk.theme" 2>/dev/null || true)"
STYLESHEET="/usr/share/themes/${THEME_NAME}/gtk-4.0/gtk.css"
[[ -f "${AMETHYSTORA_THEME_DIR}/light.mode" ]] ||
    STYLESHEET="/usr/share/themes/${THEME_NAME}/gtk-4.0/gtk-dark.css"

# A stylesheet of the user's own is theirs. Only the one this hook wrote is ever replaced or
# removed, which is what the marker is for.
if [[ -e ${USER_STYLESHEET} ]] && ! grep -qF "${MARKER}" "${USER_STYLESHEET}"; then
    exit 0
fi

# A theme that names no GTK theme, or names one without a GTK4 stylesheet, gets the applications
# back the way GNOME ships them instead of keeping the last theme's colours
if [[ -z ${THEME_NAME} ]] || [[ ! -f ${STYLESHEET} ]]; then
    rm -f "${USER_STYLESHEET}"
    exit 0
fi

mkdir -p "${GTK4_DIR}"
cat >"${USER_STYLESHEET}" <<EOF
${MARKER} for the ${AMETHYSTORA_THEME} theme, and rewritten on every theme switch.
   Delete this file to put the libadwaita applications back to the GNOME stylesheet. */
@import url("file://${STYLESHEET}");
EOF
