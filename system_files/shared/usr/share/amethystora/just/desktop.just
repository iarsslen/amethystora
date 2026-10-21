# vim: set ft=make :

set default-list

# Pick the desktop theme: colours, terminal palette, prompt and wallpaper (Super+Ctrl+Shift+Space)
[positional-arguments]
theme THEME="":
    #!/usr/bin/bash
    set -euo pipefail
    if [[ -n "${1:-}" ]]; then
        amethystora-theme set "${1:-}"
        exit 0
    fi
    current="$(amethystora-theme current 2>/dev/null || true)"
    choice="$(amethystora-theme list | sed 's/^[*] /  /' | awk '{ print $1 }' |
        gum choose --header "Theme (current: ${current:-none})" --height 14 --selected "${current}")"
    amethystora-theme set "${choice}"

# Cycle the wallpaper of the current theme (Super+Ctrl+Space), or show IMAGE, one that amethystora-theme bg list names
[positional-arguments]
background IMAGE="":
    #!/usr/bin/bash
    if [[ -n "${1:-}" ]]; then
        exec amethystora-theme bg set "$1"
    fi
    exec amethystora-theme bg next

# Pick how a new theme or wallpaper is revealed: grow, outer, wipe, wave, fade, random or none (DURATION: how long, 200 to 5000 milliseconds)
[positional-arguments]
transition STYLE="" DURATION="":
    #!/usr/bin/bash
    set -euo pipefail
    schema=org.gnome.shell.extensions.amethystora-transitions
    style="${1:-}"
    duration="${2:-}"
    if [[ -n "${duration}" && ! "${duration}" =~ ^[0-9]+$ ]]; then
        echo "usage: ame desktop transition STYLE [DURATION in milliseconds]"
        exit 64
    fi
    if [[ -z "${style}" ]]; then
        current="$(gsettings get "${schema}" style | tr -d "'")"
        style="$(gum choose --header "Transition (current: ${current})" --selected "${current}" \
            grow outer wipe wave fade random none)"
    fi
    gsettings set "${schema}" style "${style}"
    # gsettings refuses a length outside the schema's range
    if [[ -n "${duration}" ]]; then
        gsettings set "${schema}" duration "${duration}"
    fi
    echo "Transition set to ${style}, taking $(gsettings get "${schema}" duration | sed 's/^uint32 //') ms."
    echo "Super+Ctrl+Space changes the wallpaper to show it."

# Pick how windows are arranged: tiling, side by side on a strip (PaperWM), or classic, floating as on Windows and macOS
[positional-arguments]
layout STYLE="":
    #!/usr/bin/bash
    set -euo pipefail
    # Read by user-setup.hooks.d/15-extensions.sh, which turns the image's extensions back on after every
    # update and leaves PaperWM off while this says classic
    flag="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/layout"
    current="$(cat "${flag}" 2>/dev/null || echo tiling)"
    style="${1:-}"
    if [[ -z "${style}" ]]; then
        echo "tiling   Windows open side by side on a strip that scrolls, arranged for you (PaperWM)"
        echo "classic  Windows float and overlap, and you move and size them, as on Windows and macOS"
        style="$(gum choose --header "Layout (current: ${current})" --selected "${current}" tiling classic)"
    fi
    case "${style}" in
        classic)
            mkdir -p "$(dirname "${flag}")"
            echo classic >"${flag}"
            gnome-extensions disable paperwm@paperwm.github.com
            echo "Classic: windows float. Drag one by its title bar, Super+Up maximises it, Super+Down"
            echo "restores it, and Super+Left or Super+Right puts it on that half of the screen."
            ;;
        tiling)
            rm -f "${flag}"
            gnome-extensions enable paperwm@paperwm.github.com
            echo "Tiling: new windows open beside the one you are on, and Super+Left and Super+Right move"
            echo "between them. The keys are in the manual: amethystora-manual desktop#tiling-windows"
            ;;
        *) exit 0 ;;
    esac

# Pick how long the clipboard history (Super+Shift+V) keeps what you copied, sealed: always, restart (until the computer restarts) or session (until you log out); pinned items are always kept
[positional-arguments]
clipboard KEEP="":
    #!/usr/bin/bash
    set -euo pipefail
    schema=org.gnome.shell.extensions.amethystora-clipboard
    keep="${1:-}"
    if [[ -z "${keep}" ]]; then
        current="$(gsettings get "${schema}" keep-history | tr -d "'")"
        echo "always   Everything you copied, until you clear it"
        echo "restart  Pinned items, and the rest until the computer restarts"
        echo "session  Pinned items, and the rest until you log out"
        keep="$(gum choose --header "Keep the clipboard history (current: ${current})" --selected "${current}" \
            always restart session)"
    fi
    case "${keep}" in
        always | restart | session) ;;
        *)
            echo "usage: ame desktop clipboard always|restart|session"
            exit 64
            ;;
    esac
    gsettings set "${schema}" keep-history "${keep}"
    case "${keep}" in
        always) echo "The clipboard history is kept until you clear it." ;;
        restart) echo "Pinned items are kept, and the rest of the clipboard history until the computer restarts." ;;
        session) echo "Pinned items are kept, and the rest of the clipboard history until you log out." ;;
    esac
    echo "It is sealed on disk, under a key in your login keyring."

# The top bar's widgets, which the AI agent can make: list, make, new, run, fix, on, off, remove (amethystora-widgets)
[no-cd]
[no-exit-message]
[positional-arguments]
widgets *ARGS:
    @amethystora-widgets "$@"

# Show the tiling, workspace and launcher keybindings (Super+Alt+Space, then Keybindings)
keybindings:
    #!/usr/bin/bash
    # In the session's language when the manual has the page translated (manual/<language>/), as the
    # Manual itself shows it
    file=/usr/share/amethystora/keybindings.md
    locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    locale="${locale%%[.@]*}"
    for language in "${locale/_/-}" "${locale%%_*}"; do
        if [[ -n "${language}" && -f "/usr/share/amethystora/manual/${language}/keybindings.md" ]]; then
            file="/usr/share/amethystora/manual/${language}/keybindings.md"
            break
        fi
    done
    glow --pager "${file}"

# Put the Amethystora artwork on the GRUB boot menu, or take it off again
[positional-arguments]
boot-menu ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    action="${1:-}"
    amethystora-grub-theme status
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Boot menu" "Turn on" "Turn off" "Cancel")"
    fi
    case "${action}" in
        "Turn on" | install | on) sudo amethystora-grub-theme install ;;
        "Turn off" | remove | off) sudo amethystora-grub-theme remove ;;
        *) exit 0 ;;
    esac

# The logo and system summary shown in new terminals (ACTION: on or off; without it, it flips)
[positional-arguments]
greeting ACTION="":
    #!/usr/bin/bash
    FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/no-greeting"
    action="${1:-}"
    if [[ -z "${action}" ]]; then
        if [ -e "${FLAG}" ]; then action=on; else action=off; fi
    fi
    case "${action}" in
        on)
            rm -f "${FLAG}"
            echo "Terminal greeting enabled"
            ;;
        off)
            mkdir -p "$(dirname "${FLAG}")"
            touch "${FLAG}"
            echo "Terminal greeting disabled"
            ;;
        *)
            echo "usage: ame desktop greeting [on|off]"
            exit 64
            ;;
    esac

# Your Android phone through GSConnect: notifications, files, clipboard and texts (ACTION: on or off; without
# it, it flips). Off until turned on, since its service keeps some 30 MB in every session
[positional-arguments]
phone ACTION="":
    #!/usr/bin/bash
    UUID=gsconnect@andyholmes.github.io
    # One uuid a line, and back to a list, as user-setup.hooks.d/15-extensions.sh does: outside a session,
    # where gnome-extensions cannot reach GNOME Shell, the setting is changed directly
    uuids() { gsettings get org.gnome.shell enabled-extensions | grep -oE "'[^']+'" | tr -d "'" || true; }
    variant() { if (($#)); then printf "'%s'\n" "$@" | paste -sd, | sed 's/^/[/; s/$/]/'; else echo '[]'; fi; }
    on() { uuids | grep -qxF "${UUID}"; }
    action="${1:-}"
    if [[ -z "${action}" ]]; then
        if on; then action=off; else action=on; fi
    fi
    case "${action}" in
        on)
            if ! gnome-extensions enable "${UUID}" 2>/dev/null && ! on; then
                mapfile -t list < <(uuids)
                gsettings set org.gnome.shell enabled-extensions "$(variant "${list[@]}" "${UUID}")"
            fi
            echo "Phone pairing is on: install KDE Connect on the phone, and pair them on a network you named home."
            ;;
        off)
            if ! gnome-extensions disable "${UUID}" 2>/dev/null; then
                mapfile -t list < <(uuids | grep -vxF "${UUID}")
                gsettings set org.gnome.shell enabled-extensions "$(variant "${list[@]}")"
            fi
            echo "Phone pairing is off"
            ;;
        *)
            echo "usage: ame desktop phone [on|off]"
            exit 64
            ;;
    esac

# The terminal's own tools in place of the usual ones: eza for ls, bat for cat, ugrep for grep, with zoxide, direnv and mise (ACTION: on or off)
[positional-arguments]
bling ACTION="":
    @amethystora-bling ${1:+"$1"}
