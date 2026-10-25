#!/usr/bin/bash
#
# Follow the theme in VSCodium, when it is installed (the dx image). The colours are the theme's own: themed/vscodium.json
# (the editor, the sidebars, the status bar, the terminal and the syntax) is merged into the account's settings over
# VSCodium's own Default Dark Modern or Default Light Modern, so that no extension has to be installed: a colour of the
# account's that the theme does not name is kept, and so is a syntax rule of its own for a scope the theme does not name.
# A theme that names a colour theme of its own (vscode.theme) selects that one instead, and takes its palette's colours
# back out of the settings; the colour theme has to be installed in VSCodium for it to take, and when it is not, VSCodium
# keeps its current one.
#
# Run by amethystora-theme with AMETHYSTORA_THEME and AMETHYSTORA_THEME_DIR set.

set -euo pipefail

SETTINGS="${XDG_CONFIG_HOME:-${HOME}/.config}/VSCodium/User/settings.json"
COLOR_THEME_FILE="${AMETHYSTORA_THEME_DIR}/vscode.theme"
COLORS="${AMETHYSTORA_THEME_DIR}/vscodium.json"

command -v codium >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[[ -f ${SETTINGS} ]] || exit 0

# VSCodium writes JSON with comments; jq cannot read those, so leave the file alone rather than mangling it if it has any.
jq empty "${SETTINGS}" 2>/dev/null || exit 0

if [[ -f ${COLOR_THEME_FILE} ]]; then
    # The theme's own, with none of the previous palette's colours left over it
    if [[ -f ${COLORS} ]]; then
        jq --arg theme "$(head -n1 "${COLOR_THEME_FILE}")" --slurpfile ours "${COLORS}" '
            .["workbench.colorTheme"] = $theme
            | reduce ($ours[0]["workbench.colorCustomizations"] | keys[]) as $key (.; del(.["workbench.colorCustomizations"][$key]))' \
            "${SETTINGS}" >"${SETTINGS}.new"
    else
        jq --arg theme "$(head -n1 "${COLOR_THEME_FILE}")" '.["workbench.colorTheme"] = $theme' "${SETTINGS}" >"${SETTINGS}.new"
    fi
elif [[ -f ${COLORS} ]]; then
    BASE="Default Dark Modern"
    [[ -f "${AMETHYSTORA_THEME_DIR}/light.mode" ]] && BASE="Default Light Modern"
    # The theme's colours over the account's, and its syntax rules over the account's rules, which stay for a scope the
    # theme does not name
    jq --arg theme "${BASE}" --slurpfile ours "${COLORS}" '
        def rules($old; $new):
            (($old // []) | map(select(.scope as $scope | ($new | any(.scope == $scope)) | not))) + $new;
        $ours[0]["editor.tokenColorCustomizations"].textMateRules as $new
        | .["workbench.colorTheme"] = $theme
        | .["workbench.colorCustomizations"] = ((.["workbench.colorCustomizations"] // {}) + $ours[0]["workbench.colorCustomizations"])
        | .["editor.tokenColorCustomizations"] = ((.["editor.tokenColorCustomizations"] // {})
            + {textMateRules: rules(.["editor.tokenColorCustomizations"].textMateRules; $new)})' \
        "${SETTINGS}" >"${SETTINGS}.new"
else
    exit 0
fi
mv "${SETTINGS}.new" "${SETTINGS}"
