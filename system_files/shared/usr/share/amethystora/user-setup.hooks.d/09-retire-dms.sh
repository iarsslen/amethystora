#!/usr/bin/env bash
#
# Remove what DankMaterialShell left in the account.
#
# The Hyprland era (commits 44a4524a to 0e3e0cbf) shipped DankMaterialShell, which writes into the
# home directory on its own account: a config tree of its own, a colour file for every application
# it themes, whole configs for kitty and GTK, and a session environment. The image stopped shipping
# it on 2026-09-19. Nothing it left is read by anything the image runs, except where it gets in the
# way: its kitty.conf hides kitty's title bar, which on GNOME leaves a window with no close button;
# its gtk.css keeps the theme out of every libadwaita application; and its environment.d file still
# sets variables for the whole GNOME session.
#
# The list is taken from DankMaterialShell's own source - its matugen templates, config deployer,
# gtk.sh and qt.sh - not guessed at. This runs before 11-theme.sh, so the theme that re-applies lands
# on an account DMS no longer holds.
#
# Left alone, on purpose:
#   - the <config>.backup.<date> copies DMS made of a config it replaced. They are your own files
#     from before DMS, and whether you want one back is yours to say.
#   - a colour scheme an editor's config still asks for by name (Neovim, Zed, Emacs, WezTerm). A
#     scheme that has gone missing stops the editor at startup with an error, so it stays until the
#     config stops naming it; the journal says which, if any.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script retire-dms user 1 || exit 0

# Not -e: every step below stands on its own, and one that cannot run should not keep the rest from it
set -xuo pipefail

CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}"
DATA="${XDG_DATA_HOME:-${HOME}/.local/share}"
STATE="${XDG_STATE_HOME:-${HOME}/.local/state}"
CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}"

# DMS's own, and what only its stack used: Hyprland, Quickshell, matugen and dgop left the image with it
rm -rf "${CONFIG}/DankMaterialShell" "${DATA}/DankMaterialShell" "${STATE}/DankMaterialShell" \
    "${CACHE}/DankMaterialShell" "${CONFIG}/quickshell" "${CACHE}/quickshell" "${CONFIG}/matugen" \
    "${CONFIG}/dgop" "${CONFIG}/hypr" "${CONFIG}/niri/dms" "${CONFIG}/mango/dms" \
    "${DATA}/fcitx5/themes/dms"

# The session environment it set for every application: 90-dms.conf is its own file name
rm -f "${CONFIG}/environment.d/90-dms.conf"

# Enabled per account with `systemctl --user enable dms`, which leaves a link to a unit that is gone
find "${CONFIG}/systemd/user" -name 'dms.service' -type l -delete 2>/dev/null

# Every colour file it generated, each under a name of its own
rm -f "${CONFIG}"/gtk-3.0/dank-colors.css "${CONFIG}"/gtk-4.0/dank-colors.css \
    "${CONFIG}"/kitty/dank-tabs.conf "${CONFIG}"/kitty/dank-theme.conf \
    "${CONFIG}"/alacritty/dank-theme.toml "${CONFIG}"/foot/dank-colors.ini \
    "${CONFIG}"/ghostty/themes/dankcolors "${CONFIG}"/qt5ct/colors/matugen.conf \
    "${CONFIG}"/qt6ct/colors/matugen.conf "${CONFIG}"/Vencord/themes/dank-discord.css \
    "${CONFIG}"/equibop/themes/dank-discord.css "${CONFIG}"/vesktop/themes/dank-discord.css \
    "${DATA}"/color-schemes/DankMatugen.colors "${DATA}"/color-schemes/DankMatugenDark.colors \
    "${DATA}"/color-schemes/DankMatugenLight.colors "${CACHE}"/wal/dank-pywalfox.json

# The kitty.conf and gtk.css DMS deployed whole, recognised the way DMS recognises them: its kitty.conf
# carries both of its include lines, and gtk.sh's own test for a gtk.css it manages. Also any copy
# 11-theme.sh set aside as <name>.dms before this hook existed.
if [[ -f "${CONFIG}/kitty/kitty.conf" ]] &&
    grep -qE '^include[[:space:]]+dank-tabs\.conf' "${CONFIG}/kitty/kitty.conf" &&
    grep -qE '^include[[:space:]]+dank-theme\.conf' "${CONFIG}/kitty/kitty.conf"; then
    rm -f "${CONFIG}/kitty/kitty.conf"
fi
for gtk_css in "${CONFIG}"/gtk-3.0/gtk.css "${CONFIG}"/gtk-4.0/gtk.css; do
    if { [[ -L ${gtk_css} ]] && [[ "$(readlink "${gtk_css}")" == *dank-colors.css* ]]; } ||
        { [[ -f ${gtk_css} && ! -L ${gtk_css} ]] && grep -qE '^@import url.*dank-colors\.css.*\);$' "${gtk_css}"; }; then
        rm -f "${gtk_css}"
    fi
done
rm -f "${CONFIG}"/kitty/kitty.conf.dms "${CONFIG}"/gtk-3.0/gtk.css.dms "${CONFIG}"/gtk-4.0/gtk.css.dms

# A config you keep that pulls in a DMS file keeps everything else in it; only that line goes. The
# patterns are the lines DMS writes, and one that matches nothing leaves the file untouched.
drop_lines() {
    [[ -f $1 ]] && grep -qE "$2" "$1" && sed -i -E "\#$2#d" "$1"
}
drop_lines "${CONFIG}/kitty/kitty.conf" '^[[:space:]]*include[[:space:]]+dank-(tabs|theme)\.conf'
drop_lines "${CONFIG}/ghostty/config" '^[[:space:]]*theme[[:space:]]*=[[:space:]]*dankcolors[[:space:]]*$'
drop_lines "${CONFIG}/foot/foot.ini" '^[[:space:]]*include[[:space:]]*=.*dank-colors\.ini'
# Alacritty names its includes in a list, so DMS's entry comes out of the list and whatever else it
# names stays. A list that held only DMS's file is left empty, which alacritty reads as no imports.
[[ -f "${CONFIG}/alacritty/alacritty.toml" ]] &&
    sed -i -E '/^[[:space:]]*import[[:space:]]*=/ s#"[^"]*dank-theme\.toml"[[:space:]]*,?[[:space:]]*##' \
        "${CONFIG}/alacritty/alacritty.toml"
drop_lines "${CONFIG}/qt5ct/qt5ct.conf" '^color_scheme_path=.*(DankMatugen|matugen)'
drop_lines "${CONFIG}/qt6ct/qt6ct.conf" '^color_scheme_path=.*(DankMatugen|matugen)'

# Editor colour schemes, gone only once nothing in that editor's config names them
drop_unless_named() { # file, directory its config lives in, the name a config would use
    [[ -e $1 ]] || return 0
    if grep -rqsF --exclude="$(basename "$1")" -- "$3" "$2"; then
        echo "Kept $1: something in $2 still names $3"
    else
        rm -f "$1"
    fi
}
drop_unless_named "${CONFIG}/nvim/colors/dms.lua" "${CONFIG}/nvim" dms
drop_unless_named "${CONFIG}/nvim/lua/lualine/themes/dms.lua" "${CONFIG}/nvim" dms
drop_unless_named "${CONFIG}/zed/themes/dank-zed-theme.json" "${CONFIG}/zed" Dank
drop_unless_named "${CONFIG}/wezterm/colors/dank-theme.toml" "${CONFIG}/wezterm" dank-theme
for emacs in "${HOME}/.emacs.d" "${CONFIG}/emacs"; do
    drop_unless_named "${emacs}/themes/dank-emacs-theme.el" "${emacs}" dank-emacs
done

exit 0
