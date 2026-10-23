#!/usr/bin/env bash
#
# Let an account go of the third-party extensions Amethystora UI replaced (plans/PLAN-amethystora-ui.md): each one
# is taken out of the account's enabled and disabled lists, and the settings it kept are reset, since Amethystora UI
# carries only what the image had switched on, and none of their keys. An account that installed the extension itself
# (in ~/.local/share/gnome-shell/extensions) keeps it as it is: those settings are its own.
#
# Each swap adds its extension below and raises the version, so the hook runs once more on every account.
#   1  Just Perfection (the tweaks module)

source /usr/lib/amethystora/setup-services/libsetup.sh

command -v gsettings >/dev/null || exit 0

version-script retire-extensions user 1 || exit 0

# uuid, then the dconf folder its settings were in
RETIRED=(
    "just-perfection-desktop@just-perfection /org/gnome/shell/extensions/just-perfection/"
)

OWN="${XDG_DATA_HOME:-${HOME}/.local/share}/gnome-shell/extensions"
uuids() { gsettings get org.gnome.shell "$1" | grep -oE "'[^']+'" | tr -d "'" || true; }
variant() { (($#)) && printf "'%s'\n" "$@" | paste -sd, | sed 's/^/[/; s/$/]/' || echo '@as []'; }

for entry in "${RETIRED[@]}"; do
    read -r uuid folder <<<"${entry}"
    [[ -e "${OWN}/${uuid}" ]] && continue
    for list in enabled-extensions disabled-extensions; do
        mapfile -t current < <(uuids "${list}")
        mapfile -t kept < <(printf '%s\n' "${current[@]}" | grep -vxF -- "${uuid}" || true)
        [[ -z ${kept[0]:-} ]] && kept=()
        ((${#kept[@]} != ${#current[@]})) && gsettings set org.gnome.shell "${list}" "$(variant "${kept[@]}")"
    done
    command -v dconf >/dev/null && dconf reset -f "${folder}"
done

exit 0
