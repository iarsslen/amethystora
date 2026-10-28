#!/usr/bin/bash
# The palette layer (palette.awk, through derive_palette in /usr/lib/amethystora/theme/lib.sh), for 20-tests.sh: every
# colour an interface takes from a theme reads at the contrast WCAG asks, measured here by an implementation of its own.
# Text, and a label on a fill, 4.5:1; the line a control is drawn with, 3:1; a dimmed label at its own strength 4.5:1;
# each on every surface the interface draws on. Checked for every shipped theme as it is, for every shipped theme with
# each of the twelve accents (ame desktop accent), and for every shipped theme with the colours
# /usr/libexec/amethystora-wallpaper-colours works out of every picture a theme opens on, cycles through or shows by the
# time of day, in each of its three ways (ame desktop colours), merged over the theme's as amethystora-theme merges them;
# there the text also has to read at 7:1 on the ground.

set -euo pipefail

# shellcheck source=/dev/null
source /usr/lib/amethystora/theme/lib.sh
fail() { echo "test-theme-palette: $*" >&2; exit 1; }
PALETTE_AWK=/usr/lib/amethystora/theme/palette.awk
KEYS=(background foreground accent color1 color2 color3 color4 color5 color6 success warning error)
declare -A THEME_COLOURS=()
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Every palette checked in one pass: a block per palette, `== NAME FOREGROUND BACKGROUND TEXT_RATIO` and then the lines
# palette.awk printed for it (TEXT_RATIO 0 when the text's own ratio on the ground is not checked)
check_palettes() {
    awk -F= '
        function hex(s,   i, n) { s = tolower(s); n = 0; for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return n }
        function chan(h, i,   v) { v = hex(substr(h, 2 * i, 2)) / 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(h) { return 0.2126 * chan(h, 1) + 0.7152 * chan(h, 2) + 0.0722 * chan(h, 3) }
        function ratio(a, b,   x, y) { x = lum(a); y = lum(b); return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05) }
        function blend(a, b, t,   i, s) { s = "#"; for (i = 1; i <= 3; i++) s = s sprintf("%02x", hex(substr(a, 2 * i, 2)) * (1 - t) + hex(substr(b, 2 * i, 2)) * t + 0.5); return s }
        function need(what, got, want) { if (got < want) { printf "%s: %s is %.2f:1, under %s:1\n", name, what, got, want; bad = 1 } }
        function check(   n, m, f, k, i) {
            if (name == "") return
            n = split("window_bg view_bg headerbar_bg sidebar_bg card_bg popover_bg dialog_bg", G, " ")
            m = split("accent_text destructive_text success_text warning_text error_text", T, " ")
            if (P["unmet"] != "") { printf "%s: %s could not be brought to its ratio\n", name, P["unmet"]; bad = 1 }
            if (text > 0) need("the text on the ground", ratio(fg, bg), text)
            for (k = 1; k <= n; k++) {
                if (P[G[k]] !~ /^#[0-9a-f]{6}$/) { printf "%s: %s is not a colour\n", name, G[k]; bad = 1; continue }
                for (i = 1; i <= m; i++) need(T[i] " on " G[k], ratio(P[T[i]], P[G[k]]), 4.5)
                need("the text on " G[k], ratio(fg, P[G[k]]), 4.5)
                need("outline on " G[k], ratio(P["outline"], P[G[k]]), 3)
                need("dimmed text on " G[k], ratio(blend(P[G[k]], fg, P["dim_alpha"]), P[G[k]]), 4.5)
            }
            f = split("accent destructive success warning error segment1 segment2 segment3 segment4 segment5 segment6", F, " ")
            for (i = 1; i <= f; i++) {
                if (P[F[i] "_bg"] !~ /^#[0-9a-f]{6}$/ || P[F[i] "_fg"] !~ /^#[0-9a-f]{6}$/) { printf "%s: %s has no fill and label\n", name, F[i]; bad = 1; continue }
                need("the label on " F[i], ratio(P[F[i] "_fg"], P[F[i] "_bg"]), 4.5)
            }
            count++
        }
        /^== / { check(); split(substr($0, 4), H, " "); name = H[1]; fg = H[2]; bg = H[3]; text = H[4] + 0; delete P; next }
        { P[$1] = $2 }
        END { check(); printf "test-theme-palette: %d palettes checked\n", count; exit bad }'
}

# A block: its head, then what palette.awk makes of the theme's colours with any KEY=VALUE given put over them
palette() {
    local name="$1" dir="$2" text="$3" key
    shift 3
    local -A colours=()
    for key in "${KEYS[@]}"; do
        # Each theme's colours read once: a sed for every key of every palette took most of the time
        [[ -v "THEME_COLOURS[${dir}:${key}]" ]] || THEME_COLOURS["${dir}:${key}"]="$(colors_get "${dir}" "${key}")"
        colours["${key}"]="${THEME_COLOURS[${dir}:${key}]}"
    done
    for key in "$@"; do
        colours["${key%%=*}"]="${key#*=}"
    done
    echo "== ${name} ${colours[foreground]} ${colours[background]} ${text}"
    {
        for key in "${KEYS[@]}"; do
            echo "${key}=${colours[${key}]}"
        done
        if [[ -f "${dir}/light.mode" ]]; then
            echo "light=1"
        fi
    } | awk -f "${PALETTE_AWK}"
}

# The pictures a shipped theme opens on, cycles through or shows by the time of day
pictures() {
    local theme
    for theme in "${SYSTEM_THEMES_DIR}"/*/; do
        grep -v '^[[:space:]]*\(#\|$\)' "${theme}backgrounds.list" 2>/dev/null || true
        if [[ -f "${theme}daylight.list" ]]; then
            cut -d' ' -f2- "${theme}daylight.list"
        fi
    done | sort -u | while read -r picture; do
        if [[ -f ${picture} ]]; then echo "${picture}"; fi
    done
}

mapfile -t PICTURES < <(pictures)
[[ ${#PICTURES[@]} -gt 0 ]] || fail "no picture to work colours out of"
# The helper's blocks, `== PICTURE THEME WAY` and then key=value lines. It runs as an account, never as root, which the
# build is: there it runs as nobody.
AS_ACCOUNT=()
if [[ ${EUID} == 0 ]]; then
    AS_ACCOUNT=(setpriv --reuid=nobody --regid=nobody --clear-groups env -i HOME=/ PATH=/usr/bin:/usr/sbin)
fi
"${AS_ACCOUNT[@]}" /usr/libexec/amethystora-wallpaper-colours --fixtures "${SYSTEM_THEMES_DIR}" "${PICTURES[@]}" >"${WORK}/fixtures" 2>"${WORK}/fixtures.err" ||
    fail "the wallpaper's colours could not be worked out: $(cat "${WORK}/fixtures.err")"

{
    for theme in "${SYSTEM_THEMES_DIR}"/*/; do
        slug="$(basename "${theme}")"
        palette "${slug}" "${theme}" 0
        for entry in "${ACCENTS[@]}"; do
            palette "${slug}+${entry%% *}" "${theme}" 0 "accent=${entry##* }"
        done
    done
    block=""
    over=()
    while IFS= read -r line; do
        if [[ ${line} == "== "* ]]; then
            if [[ -n ${block} ]]; then palette "${block}" "${SYSTEM_THEMES_DIR}/${theme}" 7 "${over[@]}"; fi
            read -r _ picture theme way <<<"${line}"
            block="${picture##*/}:${theme}:${way}"
            over=()
        elif [[ ${line} =~ ^(background|foreground|accent|selection_background)=#[0-9a-f]{6}$ ]]; then
            over+=("${line}")
        else
            echo "== the-wallpapers-colours #000000 #000000 0"
            echo "unmet=a line that is not one of its colours: ${line}"
        fi
    done <"${WORK}/fixtures"
    if [[ -n ${block} ]]; then palette "${block}" "${SYSTEM_THEMES_DIR}/${theme}" 7 "${over[@]}"; fi
} >"${WORK}/palettes"

check_palettes <"${WORK}/palettes" || fail "a colour of the palette layer does not read"
grep -q '^== [^ ]*:mono ' "${WORK}/palettes" || fail "the wallpaper's colours gave no palette"

echo "test-theme-palette: every colour of every shipped theme, with every accent and with the wallpapers' colours, reads at the ratio WCAG asks"
