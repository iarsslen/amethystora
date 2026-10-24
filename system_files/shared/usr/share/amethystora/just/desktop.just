# vim: set ft=make :

set default-list

# Pick the desktop theme: colours, terminal palette, prompt and wallpaper (Super+Ctrl+Shift+Space)
[positional-arguments]
theme THEME="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    if [[ -n "${1:-}" ]]; then
        amethystora-theme set "${1:-}"
        exit 0
    fi
    current="$(amethystora-theme current 2>/dev/null || true)"
    shown="${current:-$(gettext "none")}"
    choice="$(amethystora-theme list | sed 's/^[*] /  /' | awk '{ print $1 }' |
        gum choose --header "$(eval_gettext "Theme (current: \${shown})")" --height 14 --selected "${current}")"
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
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-transitions
    style="${1:-}"
    duration="${2:-}"
    if [[ -n "${duration}" && ! "${duration}" =~ ^[0-9]+$ ]]; then
        echo "usage: ame desktop transition STYLE [DURATION in milliseconds]"
        exit 64
    fi
    if [[ -z "${style}" ]]; then
        current="$(gsettings get "${schema}" style | tr -d "'")"
        style="$(gum choose --header "$(eval_gettext "Transition (current: \${current})")" --selected "${current}" \
            grow outer wipe wave fade random none)"
    fi
    gsettings set "${schema}" style "${style}"
    # gsettings refuses a length outside the schema's range
    if [[ -n "${duration}" ]]; then
        gsettings set "${schema}" duration "${duration}"
    fi
    length="$(gsettings get "${schema}" duration | sed 's/^uint32 //')"
    echo "$(eval_gettext "Transition set to \${style}, taking \${length} ms.")"
    echo "$(gettext "Super+Ctrl+Space changes the wallpaper to show it.")"

# Pick the icon pack: glass, neon or duotone, or theme to follow the theme (Glass for a dark theme, Duotone for a light one)
[positional-arguments]
icons PACK="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    # Read by amethystora-theme, which writes the icon theme at every switch and would otherwise put the
    # theme's own back
    flag="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/icons"
    current="$(sed -e 's/^amethystora-//' "${flag}" 2>/dev/null || echo theme)"
    pack="${1:-}"
    if [[ -z "${pack}" ]]; then
        echo "glass    $(gettext "Each icon in its own gradient, with a glass sheen")"
        echo "neon     $(gettext "Outlines lit in colours of their own, for a dark desktop")"
        echo "duotone  $(gettext "Each icon in a gradient, its details in a contrasting one")"
        echo "theme    $(gettext "Whatever the theme chooses: Glass for a dark theme, Duotone for a light one")"
        pack="$(gum choose --header "$(eval_gettext "Icons (current: \${current})")" --selected "${current}" glass neon duotone theme)"
    fi
    case "${pack}" in
        glass | neon | duotone) name="amethystora-${pack}" ;;
        theme)
            rm -f "${flag}"
            # What the theme chooses, written on its own: applying the whole theme again would hold the screen for a
            # transition and put another wallpaper up
            # shellcheck source=/dev/null
            source /usr/lib/amethystora/theme/lib.sh
            gsettings set org.gnome.desktop.interface icon-theme "$(icon_theme)"
            echo "$(eval_gettext "Icons: \${pack}.")"
            exit 0
            ;;
        *)
            echo "usage: ame desktop icons glass|neon|duotone|theme"
            exit 64
            ;;
    esac
    mkdir -p "$(dirname "${flag}")"
    echo "${name}" >"${flag}"
    gsettings set org.gnome.desktop.interface icon-theme "${name}"
    echo "$(eval_gettext "Icons: \${pack}.")"

# Pick how windows are arranged: tiling, side by side on a strip, or classic, floating as on Windows and macOS
[positional-arguments]
layout STYLE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    # The tiling is a module of Amethystora UI with one switch, which an update leaves as the account has it
    schema=org.gnome.shell.extensions.amethystora-ui.tiling
    if [[ "$(gsettings get "${schema}" enabled)" == false ]]; then current=classic; else current=tiling; fi
    style="${1:-}"
    if [[ -z "${style}" ]]; then
        echo "tiling   $(gettext "Windows open side by side on a strip that scrolls, arranged for you")"
        echo "classic  $(gettext "Windows float and overlap, and you move and size them, as on Windows and macOS")"
        style="$(gum choose --header "$(eval_gettext "Layout (current: \${current})")" --selected "${current}" tiling classic)"
    fi
    case "${style}" in
        classic)
            gsettings set "${schema}" enabled false
            echo "$(gettext "Classic: windows float. Drag one by its title bar, Super+Up maximises it, Super+Down restores it, and Super+Left or Super+Right puts it on that half of the screen.")"
            ;;
        tiling)
            gsettings set "${schema}" enabled true
            echo "$(gettext "Tiling: new windows open beside the one you are on, and Super+Left and Super+Right move between them. The keys are in the manual: amethystora-manual desktop#tiling-windows")"
            ;;
        *) exit 0 ;;
    esac

# Pick how long the clipboard history (Super+Shift+V) keeps what you copied, sealed: always, restart (until the computer restarts) or session (until you log out); pinned items are always kept
[positional-arguments]
clipboard KEEP="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-clipboard
    keep="${1:-}"
    if [[ -z "${keep}" ]]; then
        current="$(gsettings get "${schema}" keep-history | tr -d "'")"
        echo "always   $(gettext "Everything you copied, until you clear it")"
        echo "restart  $(gettext "Pinned items, and the rest until the computer restarts")"
        echo "session  $(gettext "Pinned items, and the rest until you log out")"
        keep="$(gum choose --header "$(eval_gettext "Keep the clipboard history (current: \${current})")" --selected "${current}" \
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
        always) echo "$(gettext "The clipboard history is kept until you clear it.")" ;;
        restart) echo "$(gettext "Pinned items are kept, and the rest of the clipboard history until the computer restarts.")" ;;
        session) echo "$(gettext "Pinned items are kept, and the rest of the clipboard history until you log out.")" ;;
    esac
    echo "$(gettext "It is sealed on disk, under a key in your login keyring.")"

# Empty the trash of what was deleted more than DAYS days ago (1 to 3650), checked every hour while you are logged in, or never (off): ame desktop privacy trash DAYS|off
[positional-arguments]
privacy WHAT="" VALUE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.desktop.privacy
    usage() {
        echo "usage: ame desktop privacy trash DAYS|off"
        exit 64
    }
    [[ "${1:-trash}" == trash ]] || usage
    value="${2:-}"
    if [[ -z "${value}" ]]; then
        current=off
        if [[ "$(gsettings get "${schema}" remove-old-trash-files)" == true ]]; then
            current="$(gsettings get "${schema}" old-files-age | sed 's/^uint32 //')"
        fi
        value="$(gum choose --header "$(eval_gettext "Empty the trash of what was deleted more than this many days ago (current: \${current})")" \
            --selected "${current}" 7 14 30 60 off)"
    fi
    if [[ "${value}" == off ]]; then
        gsettings set "${schema}" remove-old-trash-files false
        gsettings set "${schema}" remove-old-temp-files false
    elif [[ "${value}" =~ ^[0-9]+$ ]] && ((10#${value} >= 1 && 10#${value} <= 3650)); then
        gsettings set "${schema}" old-files-age "$((10#${value}))"
        gsettings set "${schema}" remove-old-trash-files true
        gsettings set "${schema}" remove-old-temp-files true
    else
        usage
    fi
    # GNOME's housekeeping reads these keys when it starts and when a key of its own schema changes, never
    # when they do (gnome-settings-daemon 50, gsd-disk-space.c): one of its own keys changed and put back
    # makes the running session take them now
    housekeeping=org.gnome.settings-daemon.plugins.housekeeping
    was="$(dconf read /org/gnome/settings-daemon/plugins/housekeeping/min-notify-period)"
    period="$(gsettings get "${housekeeping}" min-notify-period | sed 's/^[a-z0-9]* //')"
    gsettings set "${housekeeping}" min-notify-period "$((period > 1 ? period - 1 : period + 1))"
    if [[ -n "${was}" ]]; then
        gsettings set "${housekeeping}" min-notify-period "${was}"
    else
        gsettings reset "${housekeeping}" min-notify-period
    fi
    if [[ "${value}" == off ]]; then
        echo "$(gettext "The trash is never emptied by itself.")"
    else
        days=$((10#${value}))
        echo "$(eval_gettext "The trash is emptied of what was deleted more than \${days} days ago, checked every hour while you are logged in.")"
        echo "$(gettext "What it empties stays in the snapshots and the backup, where they are on.")"
    fi

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
    # shellcheck source=/dev/null
    source gettext.sh
    # The choices are shown in the session's language, and what gum prints back is matched against the same words
    # Translators: a choice in a menu: to put the artwork on the boot menu
    turn_on="$(gettext "Turn on")"
    # Translators: a choice in a menu: to take the artwork off the boot menu
    turn_off="$(gettext "Turn off")"

    action="${1:-}"
    amethystora-grub-theme status
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "$(gettext "Boot menu")" "${turn_on}" "${turn_off}" "$(gettext "Cancel")")"
    fi
    case "${action}" in
        "${turn_on}" | "Turn on" | install | on) sudo amethystora-grub-theme install ;;
        "${turn_off}" | "Turn off" | remove | off) sudo amethystora-grub-theme remove ;;
        *) exit 0 ;;
    esac

# The logo and system summary shown in new terminals (ACTION: on or off; without it, it flips)
[positional-arguments]
greeting ACTION="":
    #!/usr/bin/bash
    # shellcheck source=/dev/null
    source gettext.sh
    FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/no-greeting"
    action="${1:-}"
    if [[ -z "${action}" ]]; then
        if [ -e "${FLAG}" ]; then action=on; else action=off; fi
    fi
    case "${action}" in
        on)
            rm -f "${FLAG}"
            echo "$(gettext "Terminal greeting enabled")"
            ;;
        off)
            mkdir -p "$(dirname "${FLAG}")"
            touch "${FLAG}"
            echo "$(gettext "Terminal greeting disabled")"
            ;;
        *)
            echo "usage: ame desktop greeting [on|off]"
            exit 64
            ;;
    esac

# Your Android phone through Amethystora Connect, which speaks KDE Connect's protocol: notifications, files, texts and
# calls (ACTION: on or off; without it, it flips). Off until turned on: the program listens only while its user
# service is enabled. `phone clipboard send|receive [on|off]` shares the clipboard one way or the other, both off
[positional-arguments]
phone *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    UNIT=amethystora-connect.service
    on() { [[ "$(systemctl --user is-enabled "${UNIT}" 2>/dev/null)" == enabled ]]; }
    # on or off for a word that may be missing, which flips the current state
    flip() { if [[ -n "$1" ]]; then echo "$1"; elif [[ "$2" == true ]]; then echo off; else echo on; fi; }
    if [[ "${1:-}" == clipboard ]]; then
        case "${2:-}" in
            send | receive) key="clipboard-$2" ;;
            *)
                echo "usage: ame desktop phone clipboard send|receive [on|off]"
                exit 64
                ;;
        esac
        case "$(flip "${3:-}" "$(gsettings get org.amethystora.Connect "${key}")")" in
            on)
                gsettings set org.amethystora.Connect "${key}" true
                if [[ "$2" == send ]]; then
                    echo "$(gettext "What you copy here is sent to the phones you paired.")"
                else
                    echo "$(gettext "What a paired phone copies is put on this computer's clipboard, where any program can paste it.")"
                fi
                ;;
            off)
                gsettings set org.amethystora.Connect "${key}" false
                echo "$(gettext "The clipboard is not shared that way")"
                ;;
            *)
                echo "usage: ame desktop phone clipboard send|receive [on|off]"
                exit 64
                ;;
        esac
        exit 0
    fi
    case "$(flip "${1:-}" "$(on && echo true)")" in
        on)
            if ! systemctl --user enable --now "${UNIT}" 2>/dev/null; then
                # Outside a session there is no manager to start it: the next login does
                systemctl --user enable "${UNIT}"
            fi
            echo "$(gettext "Phone pairing is on: install KDE Connect on the phone, and pair them on a network you named home.")"
            ;;
        off)
            if ! systemctl --user disable --now "${UNIT}" 2>/dev/null; then
                systemctl --user disable "${UNIT}"
            fi
            echo "$(gettext "Phone pairing is off")"
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
