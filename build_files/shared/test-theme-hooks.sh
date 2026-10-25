#!/usr/bin/bash
# The theme-set hooks that write into other programs' settings (usr/share/amethystora/theme-set.hooks.d), for 20-tests.sh:
# kdeglobals (30-qt-colors.sh) and VSCodium's settings (10-vscodium.sh). They change an account's own files, so each
# keeps what is the account's, can be run again and again without growing the file, and takes only what it should from
# a theme, which is data shared as files.

set -euo pipefail

T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
export HOME="${T}/home" XDG_CONFIG_HOME="${T}/home/.config"
mkdir -p "${XDG_CONFIG_HOME}"
# shellcheck source=/dev/null
source /usr/lib/amethystora/theme/lib.sh
fail() { echo "test-theme-hooks: $*" >&2; exit 1; }

HOOKS=/usr/share/amethystora/theme-set.hooks.d
mkdir -p "${T}/theme"
cp "${SYSTEM_THEMES_DIR}/catppuccin/colors.toml" "${T}/theme/"
render_templates "${T}/theme" "theme_name=catppuccin"
run() { AMETHYSTORA_THEME=catppuccin AMETHYSTORA_THEME_DIR="${T}/theme" "${HOOKS}/$1"; }

# --- kdeglobals --------------------------------------------------------------------------------------------------------
KDE="${XDG_CONFIG_HOME}/kdeglobals"
# A theme's file that holds more than colours: only the colour groups and the two keys are taken
{
    printf '\n[General]\nTerminalApplication=evil\n[Evil]\nx=1\n'
} >>"${T}/theme/kdeglobals"
printf '# mine\n[KFileDialog Settings]\nShow Preview=true\n\n[General]\nTerminalApplication=kitty\n' >"${KDE}"
run 30-qt-colors.sh
first="$(wc -l <"${KDE}")"
run 30-qt-colors.sh
run 30-qt-colors.sh
[[ "$(wc -l <"${KDE}")" == "${first}" ]] || fail "kdeglobals grew from ${first} lines to $(wc -l <"${KDE}") on a run again"
[[ "$(grep -c '^\[Colors:' "${KDE}")" == 7 ]] || fail "kdeglobals has not the seven colour groups, each once"
grep -q '^TerminalApplication=kitty$' "${KDE}" || fail "kdeglobals lost the account's own key"
grep -q '^Show Preview=true$' "${KDE}" || fail "kdeglobals lost the account's own group"
grep -q '^# mine$' "${KDE}" || fail "kdeglobals lost the account's own comment"
grep -q 'evil\|Evil' "${KDE}" && fail "a theme put a key of its own into kdeglobals"
grep -qx 'ColorScheme=Amethystora' "${KDE}" || fail "kdeglobals does not name the colour scheme"
grep -qx 'AmethystoraTheme=catppuccin' "${KDE}" || fail "kdeglobals does not say whose colours these are"
# Colours that are somebody else's are left alone
printf '[Colors:View]\nBackgroundNormal=1,2,3\n' >"${KDE}"
run 30-qt-colors.sh
[[ "$(cat "${KDE}")" == "$(printf '[Colors:View]\nBackgroundNormal=1,2,3')" ]] || fail "a kdeglobals with colours of the account's own was rewritten"

# --- VSCodium ----------------------------------------------------------------------------------------------------------
mkdir -p "${T}/bin" "${XDG_CONFIG_HOME}/VSCodium/User"
printf '#!/bin/sh\nexit 0\n' >"${T}/bin/codium"
chmod +x "${T}/bin/codium"
export PATH="${T}/bin:${PATH}"
SETTINGS="${XDG_CONFIG_HOME}/VSCodium/User/settings.json"
cat >"${SETTINGS}" <<'JSON'
{"editor.fontSize": 15,
 "workbench.colorCustomizations": {"editor.background": "#000000", "my.own": "#123456"},
 "editor.tokenColorCustomizations": {"textMateRules": [
    {"scope": "my.scope", "settings": {"foreground": "#abcdef"}},
    {"scope": ["comment", "punctuation.definition.comment"], "settings": {"foreground": "#111111"}}]}}
JSON
run 10-vscodium.sh
run 10-vscodium.sh
jq -e '.["workbench.colorTheme"] == "Default Dark Modern" and .["editor.fontSize"] == 15
    and .["workbench.colorCustomizations"]["my.own"] == "#123456"
    and .["workbench.colorCustomizations"]["editor.background"] != "#000000"
    and (.["editor.tokenColorCustomizations"].textMateRules | map(select(.scope == "my.scope")) | length) == 1
    and (.["editor.tokenColorCustomizations"].textMateRules | length) == 9' "${SETTINGS}" >/dev/null ||
    fail "VSCodium's settings are not the account's with the theme's colours merged in: $(cat "${SETTINGS}")"
# A theme that names a colour theme of its own selects it and takes its palette's colours back out
echo Nord >"${T}/theme/vscode.theme"
run 10-vscodium.sh
jq -e '.["workbench.colorTheme"] == "Nord" and .["workbench.colorCustomizations"]["my.own"] == "#123456"
    and (.["workbench.colorCustomizations"] | has("editor.background") | not)' "${SETTINGS}" >/dev/null ||
    fail "a theme with a colour theme of its own left its palette in VSCodium's settings: $(cat "${SETTINGS}")"
rm -f "${T}/theme/vscode.theme"
# Settings with comments are left alone, not mangled
printf '// mine\n{"editor.fontSize": 15}\n' >"${SETTINGS}"
run 10-vscodium.sh
[[ "$(head -n1 "${SETTINGS}")" == "// mine" ]] || fail "a settings file with comments was rewritten"

echo "test-theme-hooks: kdeglobals and VSCodium's settings keep the account's own, and are the same on a run again"
