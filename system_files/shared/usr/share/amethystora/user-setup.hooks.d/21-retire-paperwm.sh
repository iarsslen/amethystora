#!/usr/bin/env bash
#
# Hand an account over from PaperWM to the tiling module of Amethystora UI, which took its place in the image
# (plans/PLAN-amethystora-ui.md).
#
# PaperWM kept an account's GNOME shortcuts for itself while it ran: it emptied each one that collided with its
# own and wrote what they were into restore-keybinds, to give back only when it was turned off, which an update
# that takes it away never does. It did the same with three settings of mutter (restore-edge-tiling,
# restore-workspaces-only-on-primary, restore-attach-modal-dialogs). So, once:
#   - a shortcut it emptied, and the account has not set since, is given back;
#   - mutter's three settings go back to what they were, so that the tiling's own record of them starts from
#     the account's own values;
#   - what the account set under PaperWM's keybindings is set under the tiling's, where it has a key of that name;
#   - an account on the classic layout (PaperWM off, in ~/.config/amethystora/layout or among the disabled
#     extensions) has the tiling turned off, since that file is not read any more.
# 22-retire-extensions.sh then resets PaperWM's own folder. Not while the account's own copy of PaperWM is
# installed, whose settings these still are.

source /usr/lib/amethystora/setup-services/libsetup.sh

[[ -e "${XDG_DATA_HOME:-${HOME}/.local/share}/gnome-shell/extensions/paperwm@paperwm.github.com" ]] && exit 0
command -v dconf >/dev/null && command -v gsettings >/dev/null && command -v jq >/dev/null || exit 0

version-script retire-paperwm user 1 || exit 0

OLD=/org/gnome/shell/extensions/paperwm/
NEW=/org/gnome/shell/extensions/amethystora-ui/tiling/
TILING=org.gnome.shell.extensions.amethystora-ui.tiling

# restore-keybinds is a string holding JSON: for each GNOME key, its schema and its binding list (JSON in a string)
kept="$(dconf read "${OLD}restore-keybinds" 2>/dev/null | sed -E -e "s/^'(.*)'\$/\\1/" -e 's/\\(.)/\1/g')"
if [[ -n ${kept} ]]; then
    jq -r 'to_entries[] | select(.value.schema_id != null and .value.bind != null)
        | [.value.schema_id, .key, (.value.bind | fromjson | map(@sh) | join(", "))] | @tsv' <<<"${kept}" 2>/dev/null |
        while IFS=$'\t' read -r schema key binds; do
            [[ -n ${binds} && "$(gsettings get "${schema}" "${key}" 2>/dev/null)" == "@as []" ]] || continue
            gsettings set "${schema}" "${key}" "[${binds}]" 2>/dev/null || true
        done
fi

for key in edge-tiling workspaces-only-on-primary attach-modal-dialogs; do
    value="$(dconf read "${OLD}restore-${key}" 2>/dev/null | tr -d "'\" \\\\")"
    case "${value}" in
        true | false) gsettings set org.gnome.mutter "${key}" "${value}" ;;
    esac
done

for key in $(gsettings list-keys "${TILING}.keybindings" 2>/dev/null); do
    value="$(dconf read "${OLD}keybindings/${key}" 2>/dev/null)"
    [[ -n ${value} && -z "$(dconf read "${NEW}keybindings/${key}" 2>/dev/null)" ]] || continue
    dconf write "${NEW}keybindings/${key}" "${value}"
done

layout="${XDG_CONFIG_HOME:-${HOME}/.config}/amethystora/layout"
if [[ "$(cat "${layout}" 2>/dev/null)" == classic ]] ||
    gsettings get org.gnome.shell disabled-extensions 2>/dev/null | grep -q "'paperwm@paperwm.github.com'"; then
    gsettings set "${TILING}" enabled false
fi
rm -f "${layout}"

exit 0
