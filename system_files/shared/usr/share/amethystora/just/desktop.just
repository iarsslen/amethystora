# vim: set ft=make :

set default-list

# Pick the desktop theme: colours, terminal palette, prompt and wallpaper (Super+Ctrl+Shift+Space)
theme THEME="":
    #!/usr/bin/bash
    set -euo pipefail
    if [[ -n "{{ THEME }}" ]]; then
        amethystora-theme set "{{ THEME }}"
        exit 0
    fi
    current="$(amethystora-theme current 2>/dev/null || true)"
    choice="$(amethystora-theme list | sed 's/^[*] /  /' | awk '{ print $1 }' |
        gum choose --header "Theme (current: ${current:-none})" --height 14 --selected "${current}")"
    amethystora-theme set "${choice}"

# Cycle the wallpaper of the current theme (Super+Ctrl+Space)
background:
    @amethystora-theme bg next

# Show the tiling, workspace and launcher keybindings (Super+Alt+Space, then Keybindings)
keybindings:
    @glow --pager /usr/share/amethystora/keybindings.md

# Put the Amethystora artwork on the GRUB boot menu, or take it off again
boot-menu ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    action="{{ ACTION }}"
    amethystora-grub-theme status
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Boot menu" "Turn on" "Turn off" "Cancel")"
    fi
    case "${action}" in
        "Turn on" | install | on) sudo amethystora-grub-theme install ;;
        "Turn off" | remove | off) sudo amethystora-grub-theme remove ;;
        *) exit 0 ;;
    esac

# Toggle the logo and system summary shown in new terminals
greeting:
    #!/usr/bin/bash
    FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/no-greeting"
    if [ -e "${FLAG}" ]; then
        rm -f "${FLAG}"
        echo "Terminal greeting enabled"
    else
        mkdir -p "$(dirname "${FLAG}")"
        touch "${FLAG}"
        echo "Terminal greeting disabled"
    fi
