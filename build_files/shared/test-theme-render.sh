#!/usr/bin/bash
# The theme templates (render_templates in /usr/lib/amethystora/theme/lib.sh), for 20-tests.sh. A theme is
# data shared as dotfiles, so a colour that is not a colour must refuse the theme and run nothing, every
# shipped theme must render every template completely, and a value is put in as text.

set -euo pipefail

T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
export HOME="${T}/home" XDG_CONFIG_HOME="${T}/home/.config"
mkdir -p "${XDG_CONFIG_HOME}"
# shellcheck source=/dev/null
source /usr/lib/amethystora/theme/lib.sh
fail() { echo "test-theme-render: $*" >&2; exit 1; }

# A planted theme: its accent ends the old sed command and runs one of its own
mkdir -p "${T}/evil"
cat >"${T}/evil/colors.toml" <<EOF
accent = "#9148f0"
background = "x|g;e touch ${T}/pwned;s|x|"
EOF
if render_templates "${T}/evil" "theme_name=evil" 2>"${T}/evil.err"; then
    fail "a theme whose colour is not a colour was rendered"
fi
[[ ! -e "${T}/pwned" ]] || fail "a theme's colour ran a command"
grep -q "refused" "${T}/evil.err" || fail "the refusal does not say so"
compgen -G "${T}/evil/*" | grep -vx "${T}/evil/colors.toml" && fail "a refused theme left rendered files"

# Every shipped theme renders every template, with nothing left to fill
for theme in "${SYSTEM_THEMES_DIR}"/*/; do
    slug="$(basename "${theme}")"
    rm -rf "${T}/stage"
    cp -r "${theme}" "${T}/stage"
    render_templates "${T}/stage" "theme_name=${slug}" "ptyxis_palette_name=Amethystora ${slug} & co" ||
        fail "${slug} does not render"
    for template in "${SYSTEM_TEMPLATES_DIR}"/*.tpl; do
        output="${T}/stage/$(basename "${template}" .tpl)"
        [[ -f "${output}" ]] || fail "${slug}: $(basename "${template}") was not rendered"
        grep -q '{{ [A-Za-z0-9_]* }}' "${output}" && fail "${slug}: $(basename "${output}") has a value left unfilled"
        # The last newline is kept, as sed kept it
        [[ "$(tail -c1 "${template}" | od -An -tx1 | tr -d ' ')" == "$(tail -c1 "${output}" | od -An -tx1 | tr -d ' ')" ]] ||
            fail "${slug}: $(basename "${output}") lost its last newline"
    done
done
# A value is text: & is not the matched pattern, \ is not an escape
grep -rqF "Amethystora ${slug} & co" "${T}/stage" 2>/dev/null ||
    ! grep -rqF '{{ ptyxis_palette_name }}' "${SYSTEM_TEMPLATES_DIR}" || fail "a value with & was not put in as text"

# dconf strings are escaped for GVariant
dconf() { printf '%s\n' "$3" >"${T}/dconf.value"; }
dconf_write_string /test "it's a \\ test"
[[ "$(cat "${T}/dconf.value")" == "'it\\'s a \\\\ test'" ]] || fail "dconf string not escaped: $(cat "${T}/dconf.value")"

echo "test-theme-render: every shipped theme renders, and a planted one runs nothing"
