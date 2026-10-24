#!/usr/bin/bash
#
# Carry the theme into the applications that the gtk-theme setting does not reach on its own: the
# libadwaita ones, and everything running inside a Flatpak sandbox. And draw every application's
# window buttons as Amethystora's three lights, in the theme's own colours, whatever GTK theme is set.
#
# Two gaps, closed by the user stylesheets.
#
# libadwaita ignores gtk-theme. It always loads its own stylesheet, and the one opening left is the
# user stylesheet at ~/.config/gtk-4.0/gtk.css, which GTK reads last and so on top of everything
# else. Files, Settings, Text Editor and most of GNOME are libadwaita.
#
# A Flatpak is told the theme's name by the settings portal but cannot see the theme: /usr inside
# the sandbox belongs to the runtime, and Flatpak refuses to bind anything under the host's /usr
# over it. Left alone, every Flatpak - which on this image is most of the applications - falls back
# to the runtime's stock Adwaita, which is why their window buttons came out as GNOME's next to the
# three lights this theme draws in Files.
#
# So the theme is mirrored into ~/.themes, the one directory GTK searches by name on both sides of
# the sandbox and which /etc/flatpak/overrides/global grants every application read-only. GTK3
# applications find it there by the name the portal gives them; the user stylesheet below imports
# from the mirror rather than from /usr/share/themes, so the same one file resolves inside a sandbox
# and outside it, assets and all.
#
# This is the unsupported half of GTK theming: the user stylesheet overrides libadwaita's own, and a
# GNOME major release can change what it is overriding. Nothing here can break an application's
# behaviour, only how it is painted, and removing the two paths below puts everything back.
#
# Run by amethystora-theme with AMETHYSTORA_THEME and AMETHYSTORA_THEME_DIR set.

set -euo pipefail

MIRROR_ROOT="${HOME}/.themes"
# Marks a mirror as this hook's own, so a theme the user put in ~/.themes themselves is never
# rewritten or removed. It holds the stamp below, which is also how a stale mirror is recognised.
MARKER=".amethystora-mirror"
GTK4_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/gtk-4.0"
USER_STYLESHEET="${GTK4_DIR}/gtk.css"
# A CSS comment, because GTK parses this file and '#' starts a selector, not a comment
CSS_MARKER="/* written by amethystora-theme"

# The GTK theme apply_gnome has just set, read back from the setting rather than from the theme
# directory: the themes that name no GTK theme of their own fall back to adw-gtk3 there, and the
# Flatpaks need that mirrored too or they lose even the fallback.
THEME_NAME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'" || true)"
SOURCE="/usr/share/themes/${THEME_NAME}"

# --- Mirror -------------------------------------------------------------------------------------

# /usr is read-only and ostree zeroes every mtime in it, so a file date cannot say whether a mirror
# is still the theme that is installed. The image version can: the theme only ever changes with it.
image_version() {
    # shellcheck disable=SC1091
    (source /usr/lib/os-release 2>/dev/null || true; echo "${OSTREE_VERSION:-${VERSION_ID:-0}}")
}
STAMP="${THEME_NAME} $(image_version)"

shopt -s nullglob
for stale in "${MIRROR_ROOT}"/*; do
    [[ -f "${stale}/${MARKER}" ]] || continue
    [[ "${stale##*/}" == "${THEME_NAME}" ]] && continue
    rm -rf "${stale}"
done
shopt -u nullglob

MIRROR="${MIRROR_ROOT}/${THEME_NAME}"
if [[ -n ${THEME_NAME} && -d ${SOURCE} ]] &&
    [[ ! -e ${MIRROR} || -f "${MIRROR}/${MARKER}" ]] &&
    [[ "$(cat "${MIRROR}/${MARKER}" 2>/dev/null || true)" != "${STAMP}" ]]; then
    # Copied beside the old mirror and moved into place, so an interrupted copy leaves the previous
    # theme for the applications to keep using rather than half of the new one
    mkdir -p "${MIRROR_ROOT}"
    rm -rf "${MIRROR}.new"
    cp -rL "${SOURCE}" "${MIRROR}.new"
    echo "${STAMP}" >"${MIRROR}.new/${MARKER}"
    rm -rf "${MIRROR}"
    mv "${MIRROR}.new" "${MIRROR}"
fi

# --- User stylesheets ---------------------------------------------------------------------------

STYLESHEET="${MIRROR}/gtk-4.0/gtk.css"
[[ -f "${AMETHYSTORA_THEME_DIR}/light.mode" ]] ||
    STYLESHEET="${MIRROR}/gtk-4.0/gtk-dark.css"

# A theme that names no GTK theme, or names one without a GTK4 stylesheet (adw-gtk3 is GTK3 only),
# gets the libadwaita applications back the way GNOME ships them instead of keeping the last theme's
# colours: no import, only the window buttons
if [[ -z ${THEME_NAME} ]] || [[ ! -f ${STYLESHEET} ]]; then
    STYLESHEET=""
fi

# Write one user stylesheet: the import, when there is one, then the window buttons rendered from the
# theme's palette (themed/window-controls-gtk*.css.tpl). The buttons are copied in rather than
# imported, because a Flatpak sees no more of the home than ~/.themes and these two folders.
#
# A stylesheet of the user's own is theirs. Only the one this hook wrote is ever replaced or
# removed, which is what the marker is for.
write_stylesheet() {
    local file="$1" import="$2" controls="$3"

    if [[ -e ${file} ]] && ! grep -qF "${CSS_MARKER}" "${file}"; then
        return 0
    fi
    [[ -f ${controls} ]] || controls=""
    if [[ -z ${import} && -z ${controls} ]]; then
        rm -f "${file}"
        return 0
    fi

    mkdir -p "$(dirname "${file}")"
    {
        echo "${CSS_MARKER} for the ${AMETHYSTORA_THEME} theme, and rewritten on every theme switch."
        echo "   Delete this file to put the applications back to their own stylesheet. */"
        # A one-line import rather than a copy of the stylesheet, so that the relative
        # url(../assets/...) in it keeps resolving against the theme directory rather than against the
        # home directory, and so that the light and dark stylesheets are never allowed to drift apart
        [[ -n ${import} ]] && echo "@import url(\"file://${import}\");"
        [[ -n ${controls} ]] && cat "${controls}"
    } >"${file}.new"
    mv "${file}.new" "${file}"
}

write_stylesheet "${USER_STYLESHEET}" "${STYLESHEET}" "${AMETHYSTORA_THEME_DIR}/window-controls-gtk4.css"
write_stylesheet "${XDG_CONFIG_HOME:-${HOME}/.config}/gtk-3.0/gtk.css" "" \
    "${AMETHYSTORA_THEME_DIR}/window-controls-gtk3.css"
