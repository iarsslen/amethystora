#!/usr/bin/bash
#
# Follow the theme in VS Code, when it is installed (the dx image) and the theme names one in
# vscode.theme. The colour theme has to be installed in VS Code for it to take; when it is not,
# VS Code keeps its current one and nothing breaks.
#
# Run by amethystora-theme with AMETHYSTORA_THEME and AMETHYSTORA_THEME_DIR set.

set -euo pipefail

SETTINGS="${XDG_CONFIG_HOME:-${HOME}/.config}/Code/User/settings.json"
COLOR_THEME_FILE="${AMETHYSTORA_THEME_DIR}/vscode.theme"

command -v code >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[[ -f ${COLOR_THEME_FILE} ]] || exit 0
[[ -f ${SETTINGS} ]] || exit 0

COLOR_THEME="$(head -n1 "${COLOR_THEME_FILE}")"

# VS Code writes JSON with comments; jq cannot read those, so leave the file alone rather than
# mangling it if it has any.
jq empty "${SETTINGS}" 2>/dev/null || exit 0

jq --arg theme "${COLOR_THEME}" '.["workbench.colorTheme"] = $theme' "${SETTINGS}" >"${SETTINGS}.new"
mv "${SETTINGS}.new" "${SETTINGS}"
