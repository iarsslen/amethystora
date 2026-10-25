#!/usr/bin/bash
#
# Carry the theme's colours into the KDE and Qt applications, which take theirs from ~/.config/kdeglobals (a Flatpak KDE
# application is let at it by its own manifest). The groups themed/kdeglobals.tpl renders replace the colour groups of the
# file and set its ColorScheme; everything else the applications keep there (Dolphin's dialogs, a terminal's name) stays.
# Only the colour groups and the two [General] keys of the theme's file are taken, whatever else it holds, since a theme
# is shared as files. A kdeglobals whose colours were not written by this hook, that is one with a colour group and no
# AmethystoraTheme key, is somebody's own look and is left alone. Nothing here can break an application, only change its
# colours.
#
# Run by amethystora-theme with AMETHYSTORA_THEME and AMETHYSTORA_THEME_DIR set.

set -euo pipefail

FILE="${XDG_CONFIG_HOME:-${HOME}/.config}/kdeglobals"
OURS="${AMETHYSTORA_THEME_DIR}/kdeglobals"

[[ -f ${OURS} ]] || exit 0
if [[ -f ${FILE} ]] && grep -q '^\[Colors:' "${FILE}" && ! grep -q '^AmethystoraTheme=' "${FILE}"; then
    exit 0
fi

mkdir -p "$(dirname "${FILE}")"
# What is there without its colour groups, without our keys, and without a group they leave empty or the blank lines that
# followed it (a blank line goes before each header, so a run again writes the same file), then ours
{
    if [[ -f ${FILE} ]]; then
        awk '
            function flush() {
                if (kept) {
                    sub(/\n+$/, "\n", body)
                    if (header != "") printf "%s%s\n", printed ? "\n" : "", header
                    printf "%s", body
                    printed = 1
                }
                header = ""; body = ""; kept = 0
            }
            /^\[/ { flush(); header = $0; skip = ($0 ~ /^\[Colors:/); general = ($0 == "[General]"); next }
            skip { next }
            general && /^(ColorScheme|AmethystoraTheme)=/ { next }
            { body = body $0 "\n"; if ($0 !~ /^[[:space:]]*$/) kept = 1 }
            END { flush() }
        ' "${FILE}"
    fi
    awk '
        /^\[/ { keep = ($0 ~ /^\[Colors:/ || $0 == "[General]"); general = ($0 == "[General]"); if (keep) print "\n" $0; next }
        !keep || /^[[:space:]]*(#|$)/ { next }
        general && !/^(ColorScheme|AmethystoraTheme)=/ { next }
        { print }
    ' "${OURS}"
} >"${FILE}.new"
mv "${FILE}.new" "${FILE}"
