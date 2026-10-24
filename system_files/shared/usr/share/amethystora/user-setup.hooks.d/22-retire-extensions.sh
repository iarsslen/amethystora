#!/usr/bin/env bash
#
# Let an account go of the third-party extensions Amethystora UI replaced (plans/PLAN-amethystora-ui.md): each one
# is taken out of the account's enabled and disabled lists, and the settings it kept are reset, since Amethystora UI
# carries only what the image had switched on, and none of their keys. An account that installed the extension itself
# (in ~/.local/share/gnome-shell/extensions) keeps it as it is: those settings are its own.
#
# Each swap adds its extension below and raises the version, so the hook runs once more on every account.
#   1  Just Perfection (the tweaks module)
#   2  Space Bar and TopHat (the workspaces and meters modules)
#   3  AppIndicator (the tray module)
#   4  Caffeine (dropped: it was never switched on)
#   5  Search Light and GNOME Fuzzy App Search (the search and fuzzy modules)
#   6  Gradia's and Bazaar's integrations (the screenshot and bazaar modules)
#   7  PaperWM (the tiling module), after 21-retire-paperwm.sh has handed over what it kept
#   8  Dash to Dock and Blur my Shell (the dock and glass modules)

source /usr/lib/amethystora/setup-services/libsetup.sh

command -v gsettings >/dev/null || exit 0

version-script retire-extensions user 8 || exit 0

# uuid, then the dconf folder its settings were in, then any folder it left in ~/.cache
RETIRED=(
    "just-perfection-desktop@just-perfection /org/gnome/shell/extensions/just-perfection/"
    "space-bar@luchrioh /org/gnome/shell/extensions/space-bar/"
    "tophat@fflewddur.github.io /org/gnome/shell/extensions/tophat/"
    "appindicatorsupport@rgcjonas.gmail.com /org/gnome/shell/extensions/appindicator/"
    "caffeine@patapon.info /org/gnome/shell/extensions/caffeine/"
    "search-light@icedman.github.com /org/gnome/shell/extensions/search-light/"
    "gnome-fuzzy-app-search@gnome-shell-extensions.Czarlie.gitlab.com /org/gnome/shell/extensions/gnome-fuzzy-app-search/ gnome-fuzzy-app-search@gnome-shell-extensions.Czarlie.gitlab.com"
    "gradia-integration@alexandervanhee.github.io /org/gnome/shell/extensions/gradia-integration/"
    "bazaar-integration@kolunmi.github.io /org/gnome/shell/extensions/bazaar-integration/"
    "paperwm@paperwm.github.com /org/gnome/shell/extensions/paperwm/"
    "dash-to-dock@micxgx.gmail.com /org/gnome/shell/extensions/dash-to-dock/"
    "blur-my-shell@aunetx /org/gnome/shell/extensions/blur-my-shell/"
)

OWN="${XDG_DATA_HOME:-${HOME}/.local/share}/gnome-shell/extensions"
uuids() { gsettings get org.gnome.shell "$1" | grep -oE "'[^']+'" | tr -d "'" || true; }
variant() { (($#)) && printf "'%s'\n" "$@" | paste -sd, | sed 's/^/[/; s/$/]/' || echo '@as []'; }

for entry in "${RETIRED[@]}"; do
    read -r uuid folder cache <<<"${entry}"
    [[ -e "${OWN}/${uuid}" ]] && continue
    for list in enabled-extensions disabled-extensions; do
        mapfile -t current < <(uuids "${list}")
        mapfile -t kept < <(printf '%s\n' "${current[@]}" | grep -vxF -- "${uuid}" || true)
        [[ -z ${kept[0]:-} ]] && kept=()
        ((${#kept[@]} != ${#current[@]})) && gsettings set org.gnome.shell "${list}" "$(variant "${kept[@]}")"
    done
    command -v dconf >/dev/null && dconf reset -f "${folder}"
    [[ -n ${cache} ]] && rm -rf "${XDG_CACHE_HOME:-${HOME}/.cache}/${cache}"
done

exit 0
