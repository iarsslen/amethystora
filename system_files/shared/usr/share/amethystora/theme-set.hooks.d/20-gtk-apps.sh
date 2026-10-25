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
# else. Files, Settings, Text Editor and most of GNOME are libadwaita. What that stylesheet holds is
# the theme's palette as libadwaita's own colour variables (themed/palette-gtk4.css.tpl), so that every
# surface, accent and status colour of such an application is the theme's, at the contrast WCAG asks
# for. GTK 4 leaves the palette out while High Contrast is on, which has its own colours, as the media query round it
# says; GTK 3 has no such query, so its palette is left out here, and applying the theme again puts it back.
#
# A Flatpak is told the theme's name by the settings portal but cannot see the theme: /usr inside
# the sandbox belongs to the runtime, and Flatpak refuses to bind anything under the host's /usr
# over it. Left alone, every Flatpak - which on this image is most of the applications - falls back
# to the runtime's stock Adwaita, which is why their window buttons came out as GNOME's next to the
# three lights this theme draws in Files.
#
# So the theme is mirrored into ~/.themes, the one directory GTK searches by name on both sides of
# the sandbox and which /etc/flatpak/overrides/global grants every application read-only. GTK3
# applications find it there by the name the portal gives them, and the GTK 3 stylesheet carries the
# palette in the named colours adw-gtk3 shares with libadwaita.
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

# Write one user stylesheet: the palette, then the window buttons rendered from the theme's palette
# (themed/window-controls-gtk*.css.tpl), then the desktop style. They are copied in rather than imported, because a
# Flatpak sees no more of the home than ~/.themes and these two folders. The palette comes first so that what follows
# can use its variables.
#
# A stylesheet of the user's own is theirs. Only the one this hook wrote is ever replaced or
# removed, which is what the marker is for.
write_stylesheet() {
    local file="$1" palette="$2" controls="$3" part

    if [[ -e ${file} ]] && ! grep -qF "${CSS_MARKER}" "${file}"; then
        return 0
    fi
    [[ -f ${palette} ]] || palette=""
    [[ -f ${controls} ]] || controls=""
    [[ -f ${STYLE_SHEET} ]] || STYLE_SHEET=""
    if [[ -z ${palette} && -z ${controls} && -z ${STYLE_SHEET} ]]; then
        rm -f "${file}"
        return 0
    fi

    mkdir -p "$(dirname "${file}")"
    {
        echo "${CSS_MARKER} for the ${AMETHYSTORA_THEME} theme, and rewritten on every theme switch."
        echo "   Delete this file to put the applications back to their own stylesheet. */"
        for part in "${palette}" "${controls}" "${STYLE_SHEET}"; do
            [[ -z ${part} ]] || cat "${part}"
        done
    } >"${file}.new"
    mv "${file}.new" "${file}"
}

# The desktop style's half in the applications (themed/style-<style>.gtk.css.tpl), after the window buttons: the
# style apply_gnome has just written, read back as the GTK theme is. GTK 3 and 4 share it; a selector one of them
# does not have matches nothing there.
STYLE="$(gsettings get org.gnome.shell.extensions.amethystora-ui.style style 2>/dev/null | tr -d "'" || true)"
STYLE_SHEET="${AMETHYSTORA_THEME_DIR}/style-${STYLE:-floating}.gtk.css"
HIGH_CONTRAST="$(gsettings get org.gnome.desktop.a11y.interface high-contrast 2>/dev/null || true)"

write_stylesheet "${USER_STYLESHEET}" "${AMETHYSTORA_THEME_DIR}/palette-gtk4.css" "${AMETHYSTORA_THEME_DIR}/window-controls-gtk4.css"
# With High Contrast on, GTK 3 draws what adw-gtk3 draws for it, and a palette over that would undo it
GTK3_PALETTE="${AMETHYSTORA_THEME_DIR}/palette-gtk3.css"
[[ ${HIGH_CONTRAST} != true ]] || GTK3_PALETTE=""
write_stylesheet "${XDG_CONFIG_HOME:-${HOME}/.config}/gtk-3.0/gtk.css" "${GTK3_PALETTE}" \
    "${AMETHYSTORA_THEME_DIR}/window-controls-gtk3.css"
