#!/usr/bin/bash
# The palette layer (palette.awk, through derive_palette in /usr/lib/amethystora/theme/lib.sh), for 20-tests.sh: for every
# shipped theme, every colour an interface takes from it reads at the contrast WCAG asks, measured here by an
# implementation of its own. Text, and a label on a fill, 4.5:1; the line a control is drawn with, 3:1; a dimmed label
# at its own strength 4.5:1; each on every surface the interface draws on.

set -euo pipefail

# shellcheck source=/dev/null
source /usr/lib/amethystora/theme/lib.sh
fail() { echo "test-theme-palette: $*" >&2; exit 1; }

for theme in "${SYSTEM_THEMES_DIR}"/*/; do
    slug="$(basename "${theme}")"
    palette="$(derive_palette "${theme}")"
    [[ -n ${palette} ]] || fail "${slug}: no palette"
    awk -F= -v slug="${slug}" -v fg="$(colors_get "${theme}" foreground)" '
        function hex(s,   i, n) { s = tolower(s); n = 0; for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return n }
        function chan(h, i) { v = hex(substr(h, 2 * i, 2)) / 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(h) { return 0.2126 * chan(h, 1) + 0.7152 * chan(h, 2) + 0.0722 * chan(h, 3) }
        function ratio(a, b,   x, y) { x = lum(a); y = lum(b); return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05) }
        function blend(a, b, t,   i, s) { s = "#"; for (i = 1; i <= 3; i++) s = s sprintf("%02x", hex(substr(a, 2 * i, 2)) * (1 - t) + hex(substr(b, 2 * i, 2)) * t + 0.5); return s }
        function need(what, got, want) { if (got < want) { printf "%s: %s is %.2f:1, under %s:1\n", slug, what, got, want; bad = 1 } }
        { P[$1] = $2 }
        END {
            n = split("window_bg view_bg headerbar_bg sidebar_bg card_bg popover_bg dialog_bg", G, " ")
            m = split("accent_text destructive_text success_text warning_text error_text", T, " ")
            if (P["unmet"] != "") { printf "%s: %s could not be brought to its ratio\n", slug, P["unmet"]; bad = 1 }
            for (k = 1; k <= n; k++) {
                if (P[G[k]] !~ /^#[0-9a-f]{6}$/) { printf "%s: %s is not a colour\n", slug, G[k]; bad = 1; continue }
                for (i = 1; i <= m; i++) need(T[i] " on " G[k], ratio(P[T[i]], P[G[k]]), 4.5)
                need("the text on " G[k], ratio(fg, P[G[k]]), 4.5)
                need("outline on " G[k], ratio(P["outline"], P[G[k]]), 3)
                need("dimmed text on " G[k], ratio(blend(P[G[k]], fg, P["dim_alpha"]), P[G[k]]), 4.5)
            }
            f = split("accent destructive success warning error segment1 segment2 segment3 segment4 segment5 segment6", F, " ")
            for (i = 1; i <= f; i++) {
                if (P[F[i] "_bg"] !~ /^#[0-9a-f]{6}$/ || P[F[i] "_fg"] !~ /^#[0-9a-f]{6}$/) { printf "%s: %s has no fill and label\n", slug, F[i]; bad = 1; continue }
                need("the label on " F[i], ratio(P[F[i] "_fg"], P[F[i] "_bg"]), 4.5)
            }
            exit bad
        }' <<<"${palette}" || fail "${slug}: a colour of the palette layer does not read"
done

echo "test-theme-palette: every colour of every shipped theme reads at the ratio WCAG asks"
