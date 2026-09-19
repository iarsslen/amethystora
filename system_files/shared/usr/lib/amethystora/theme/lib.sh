# shellcheck shell=bash
# Shared helpers for amethystora-theme and amethystora-menu.
#
# A theme is a directory of small files, so that adding one needs no code:
#
#   colors.toml   the palette: accent, foreground, background, cursor, selection_*, color0..color15
#   accent.theme  the GNOME accent name to pair with it (blue teal green yellow orange red pink
#                 purple slate); without it the palette's accent is matched to the closest one
#   light.mode    present when the theme is light
#   pair.theme    the name of the light or dark theme this one flips to on Super+Ctrl+D
#   gtk.theme     a GTK theme name, when adw-gtk3 is not wanted
#   icons.theme, cursor.theme  likewise for icons and the cursor
#   vscode.theme  the VS Code colour theme to select
#   backgrounds/  wallpapers to cycle with Super+Ctrl+Space
#
# Themes ship read-only in /usr/share/amethystora/themes. A directory of the same name in
# ~/.config/amethystora/themes is copied over the top, so a theme can be tweaked file by file, and
# a directory that exists only there is a theme of the user's own.
#
# Applying a theme renders /usr/share/amethystora/themed/*.tpl against colors.toml and swaps the
# result into ~/.config/amethystora/current/theme. Everything downstream reads that one path, so
# nothing else has to know which theme is current.

SYSTEM_THEMES_DIR=/usr/share/amethystora/themes
SYSTEM_TEMPLATES_DIR=/usr/share/amethystora/themed
SYSTEM_HOOKS_DIR=/usr/share/amethystora/theme-set.hooks.d

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/amethystora"
USER_THEMES_DIR="${CONFIG_DIR}/themes"
USER_TEMPLATES_DIR="${CONFIG_DIR}/themed"
USER_HOOKS_DIR="${CONFIG_DIR}/hooks/theme-set.d"
USER_BACKGROUNDS_DIR="${CONFIG_DIR}/backgrounds"
CURRENT_DIR="${CONFIG_DIR}/current"
CURRENT_THEME_DIR="${CURRENT_DIR}/theme"
CURRENT_THEME_NAME="${CURRENT_DIR}/theme.name"
CURRENT_BACKGROUND="${CURRENT_DIR}/background"

DEFAULT_THEME=amethystora

# GNOME's accent colours, with a representative sRGB value for each, used to pick the closest one
# for a theme that does not name its own
GNOME_ACCENTS=(
    "blue #3584e4"
    "teal #2190a4"
    "green #3a944a"
    "yellow #c88800"
    "orange #ed5b00"
    "red #e62d42"
    "pink #d56199"
    "purple #9141ac"
    "slate #6f8396"
)

die() {
    echo "${0##*/}: $*" >&2
    exit 1
}

# A theme name as it is typed ("Tokyo Night") to the directory name (tokyo-night)
theme_slug() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9._-]\+/-/g' -e 's/^-//' -e 's/-$//'
}

theme_exists() {
    local slug="$1"
    [[ -d "${SYSTEM_THEMES_DIR}/${slug}" || -d "${USER_THEMES_DIR}/${slug}" ]]
}

# Every theme, shipped and user-made, one name per line
theme_list() {
    {
        [[ -d ${SYSTEM_THEMES_DIR} ]] && find "${SYSTEM_THEMES_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
        [[ -d ${USER_THEMES_DIR} ]] && find "${USER_THEMES_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
    } 2>/dev/null | sort -u
}

theme_current() {
    [[ -f ${CURRENT_THEME_NAME} ]] && cat "${CURRENT_THEME_NAME}"
}

# The value of a one-line file in the current theme, or nothing when the theme does not ship it.
# Missing is normal, not an error: every one of these files is optional.
theme_file() {
    local name="$1"
    if [[ -f "${CURRENT_THEME_DIR}/${name}" ]]; then
        head -n1 "${CURRENT_THEME_DIR}/${name}"
    fi
    return 0
}

theme_is_light() {
    [[ -f "${CURRENT_THEME_DIR}/light.mode" ]]
}

# A colour from a theme's colors.toml, e.g. colors_get <dir> accent -> #7c3aed
colors_get() {
    local dir="$1" key="$2"
    sed -nE "s/^[[:space:]]*['\"]?${key}['\"]?[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" \
        "${dir}/colors.toml" 2>/dev/null | head -n1
}

hex_to_rgb() {
    local hex="${1#\#}"
    printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# 0.0-1.0 components, the form GNOME extensions store colours in
hex_to_float() {
    local hex="${1#\#}"
    awk -v r="$((16#${hex:0:2}))" -v g="$((16#${hex:2:2}))" -v b="$((16#${hex:4:2}))" \
        'BEGIN { printf "%.3f, %.3f, %.3f", r/255, g/255, b/255 }'
}

# The GNOME accent whose colour is nearest the theme's, so a ported theme still tints the shell
closest_gnome_accent() {
    local hex="${1#\#}" best=purple best_distance=-1 entry name candidate distance
    [[ ${#hex} -eq 6 ]] || { echo "${best}"; return; }
    for entry in "${GNOME_ACCENTS[@]}"; do
        name="${entry%% *}"
        candidate="${entry##* }"
        candidate="${candidate#\#}"
        distance=$(awk -v a="$((16#${hex:0:2}))" -v b="$((16#${hex:2:2}))" -v c="$((16#${hex:4:2}))" \
            -v x="$((16#${candidate:0:2}))" -v y="$((16#${candidate:2:2}))" -v z="$((16#${candidate:4:2}))" \
            'BEGIN { print (a-x)^2 + (b-y)^2 + (c-z)^2 }')
        if [[ ${best_distance} -lt 0 ]] || ((distance < best_distance)); then
            best_distance=${distance}
            best="${name}"
        fi
    done
    echo "${best}"
}

# Render every *.tpl into dest, substituting {{ key }}, {{ key_strip }} (no leading #) and
# {{ key_rgb }} (decimal r,g,b) from colors.toml. A file the theme ships itself is left alone, so a
# theme can hand-write any config a template would otherwise generate. Any further key=value pairs
# given as arguments are substituted too, for things a palette cannot hold, such as the theme name.
render_templates() {
    local dest="$1" script key value rgb template output
    shift

    [[ -f "${dest}/colors.toml" ]] || return 0
    script="$(mktemp)"

    for value in "$@"; do
        printf 's|{{ %s }}|%s|g\n' "${value%%=*}" "${value#*=}"
    done >"${script}"

    while IFS='=' read -r key value || [[ -n ${key} ]]; do
        key="${key//[\"\' ]/}"
        [[ -n ${key} && ${key} != \#* ]] || continue
        value="${value#*[\"\']}"
        value="${value%%[\"\']*}"
        printf 's|{{ %s }}|%s|g\n' "${key}" "${value}"
        printf 's|{{ %s_strip }}|%s|g\n' "${key}" "${value#\#}"
        if [[ ${value} =~ ^#[0-9a-fA-F]{6}$ ]]; then
            rgb="$(hex_to_rgb "${value}")"
            printf 's|{{ %s_rgb }}|%s|g\n' "${key}" "${rgb}"
        fi
    done <"${dest}/colors.toml" >>"${script}"

    shopt -s nullglob
    for template in "${USER_TEMPLATES_DIR}"/*.tpl "${SYSTEM_TEMPLATES_DIR}"/*.tpl; do
        output="${dest}/$(basename "${template}" .tpl)"
        [[ -f ${output} ]] || sed -f "${script}" "${template}" >"${output}"
    done
    shopt -u nullglob

    rm -f "${script}"
}

# Settings are written with dconf rather than gsettings: it needs no schema, so it also reaches the
# relocatable ones (Ptyxis profiles) and extensions that keep their schema out of the system path.
dconf_write_string() {
    dconf write "$1" "'$2'"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

notify() {
    have notify-send && notify-send --app-name=Amethystora --expire-time=2000 "$@" || true
}
