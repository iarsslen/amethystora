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

# Pick the icon pack (glass, glass-light, neon, neon-light, duotone, line, clay or muted), or theme to follow the theme's own
[positional-arguments]
icons PACK="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    # shellcheck source=/dev/null
    source /usr/lib/amethystora/theme/lib.sh
    # Read by amethystora-theme, which writes the icon theme at every switch and would otherwise put the
    # theme's own back
    flag="${CONFIG_DIR}/icons"
    current="$(sed -e 's/^amethystora-//' "${flag}" 2>/dev/null || echo theme)"
    pack="${1:-}"
    if [[ -z "${pack}" ]]; then
        echo "glass        $(gettext "Each icon in its own gradient, with a glass sheen")"
        echo "glass-light  $(gettext "Glass with its colours deepened to read on a light desktop")"
        echo "neon         $(gettext "Outlines lit in colours of their own, for a dark desktop")"
        echo "neon-light   $(gettext "Neon with its colours deepened to read on a light desktop")"
        echo "duotone      $(gettext "Each icon in a gradient, its details in a contrasting one")"
        echo "line         $(gettext "One even outline, in colours that read on every theme")"
        echo "clay         $(gettext "Soft matte volumes, a highlight above and a shade below")"
        echo "muted        $(gettext "Glass in quieter colours, for themes of low chroma")"
        echo "theme        $(gettext "Whatever the theme chooses")"
        pack="$(gum choose --header "$(eval_gettext "Icons (current: \${current})")" --selected "${current}" "${ICON_PACKS[@]}" theme)"
    fi
    if [[ "${pack}" == theme ]]; then
        rm -f "${flag}"
        # What the theme chooses, written on its own: applying the whole theme again would hold the screen for a
        # transition and put another wallpaper up
        gsettings set org.gnome.desktop.interface icon-theme "$(icon_theme)"
        echo "$(eval_gettext "Icons: \${pack}.")"
        exit 0
    elif ! is_icon_pack "${pack}"; then
        echo "usage: ame desktop icons $(IFS='|'; echo "${ICON_PACKS[*]}")|theme"
        exit 64
    fi
    mkdir -p "${CONFIG_DIR}"
    echo "amethystora-${pack}" >"${flag}"
    gsettings set org.gnome.desktop.interface icon-theme "amethystora-${pack}"
    echo "$(eval_gettext "Icons: \${pack}.")"

# Pick the desktop style: the shape of the top bar, menus, notifications, dialogs, buttons and windows
[positional-arguments]
style STYLE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    # shellcheck source=/dev/null
    source /usr/lib/amethystora/theme/lib.sh
    # Read by amethystora-theme, which writes the style at every switch and would otherwise put the theme's own back
    flag="${CONFIG_DIR}/style"
    current="$(head -n1 "${flag}" 2>/dev/null || echo theme)"
    style="${1:-}"
    if [[ -z "${style}" ]]; then
        echo "islands   $(gettext "A floating pill for each part of the top bar, soft corners everywhere")"
        echo "floating  $(gettext "One rounded top bar held off the edge of the screen")"
        echo "hairline  $(gettext "A thin, solid top bar, crisp corners and fine lines")"
        echo "capsule   $(gettext "The clock in a dark capsule, and everything else a pill")"
        echo "terminal  $(gettext "Monospace, square and lined, like a terminal")"
        echo "segments  $(gettext "The top bar in blocks of the theme's colours")"
        echo "neon      $(gettext "Dark glass outlined and glowing in the theme's accent")"
        echo "theme     $(gettext "Whatever the theme chooses")"
        style="$(gum choose --header "$(eval_gettext "Style (current: \${current})")" --selected "${current}" \
            islands floating hairline capsule terminal segments neon theme)"
    fi
    if [[ "${style}" == theme ]]; then
        rm -f "${flag}"
    elif is_style "${style}"; then
        mkdir -p "${CONFIG_DIR}"
        echo "${style}" >"${flag}"
    else
        echo "usage: ame desktop style islands|floating|hairline|capsule|terminal|segments|neon|theme"
        exit 64
    fi
    # The whole theme again, with its transition, for the applications' half of the style too; the wallpaper stays
    AMETHYSTORA_THEME_QUIET=1 amethystora-theme reload >/dev/null
    style="$(desktop_style)"
    echo "$(eval_gettext "Style: \${style}. Applications that are open take it when they next start.")"

# Pick the glass the top bar, the dock, menus and notifications stand on: frost, prism or clear
[positional-arguments]
glass MATERIAL="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    SCHEMA=org.gnome.shell.extensions.amethystora-ui.glass
    current="$(gsettings get "${SCHEMA}" material | tr -d "'")"
    material="${1:-}"
    if [[ -z "${material}" ]]; then
        echo "frost  $(gettext "Thick, milky glass with an even tint")"
        echo "prism  $(gettext "Less tint, more colour, a lit top edge and light along the bottom")"
        echo "clear  $(gettext "The thinnest glass and the brightest rim; it darkens by itself where text needs it")"
        material="$(gum choose --header "$(eval_gettext "Glass (current: \${current})")" --selected "${current}" \
            frost prism clear)"
    fi
    case "${material}" in
        frost | prism | clear) gsettings set "${SCHEMA}" material "${material}" ;;
        *)
            echo "usage: ame desktop glass frost|prism|clear"
            exit 64
            ;;
    esac
    case "${material}" in
        frost) echo "$(gettext "Frost: thick, milky glass with an even tint.")" ;;
        prism) echo "$(gettext "Prism: less tint, more colour, and light along the edges.")" ;;
        clear) echo "$(gettext "Clear: the thinnest glass. It darkens by itself where text needs it.")" ;;
    esac
    profile="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
        org.freedesktop.UPower.PowerProfiles ActiveProfile 2>/dev/null || true)"
    if [[ "$(gsettings get "${SCHEMA}" solid)" == true ]] ||
        [[ "$(gsettings get org.gnome.desktop.a11y.interface high-contrast)" == true ]] ||
        [[ "${profile}" == 's "power-saver"' ]]; then
        echo "$(gettext "The glass is drawn solid while Reduce transparency, High Contrast or the power saver is on.")"
    fi

# Comfort: reduce transparency, reduce motion and increase contrast (WHAT: one of those, then on or off; without it, it flips)
[positional-arguments]
comfort *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    GLASS=org.gnome.shell.extensions.amethystora-ui.glass
    A11Y=org.gnome.desktop.a11y.interface
    usage() {
        echo "usage: ame desktop comfort reduce-transparency|reduce-motion|increase-contrast [on|off]"
        exit 64
    }
    # on or off for a word that may be missing, which flips the current state
    flip() { if [[ -n "$1" ]]; then echo "$1"; elif [[ "$2" == true ]]; then echo off; else echo on; fi; }
    # The words a person types back, so left as they are
    word() { if [[ "$1" == true ]]; then echo on; else echo off; fi; }
    solid() { gsettings get "${GLASS}" solid; }
    motion() { [[ "$(gsettings get "${A11Y}" reduced-motion)" == "'reduce'" ]] && echo true || echo false; }
    contrast() { gsettings get "${A11Y}" high-contrast; }
    # The power saver is the profile power-profiles-daemon's interface says is active (tuned-ppd answers it here);
    # one that cannot be read is off
    saver() {
        [[ "$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
            org.freedesktop.UPower.PowerProfiles ActiveProfile 2>/dev/null || true)" == 's "power-saver"' ]] &&
            echo true || echo false
    }
    if [[ $# -eq 0 ]]; then
        state="$(word "$(solid)")"
        echo "$(eval_gettext "Reduce transparency: \${state}")"
        state="$(word "$(motion)")"
        echo "$(eval_gettext "Reduce motion: \${state}")"
        state="$(word "$(contrast)")"
        echo "$(eval_gettext "Increase contrast: \${state}")"
        state="$(word "$(saver)")"
        echo "$(eval_gettext "Power saver: \${state} (the glass is solid and animations are shorter while it is on)")"
        exit 0
    fi
    [[ $# -le 2 ]] || usage
    case "$1" in
        reduce-transparency)
            case "$(flip "${2:-}" "$(solid)")" in
                on)
                    gsettings set "${GLASS}" solid true
                    echo "$(gettext "Reduce transparency is on: the glass is drawn in the theme's solid colours.")"
                    ;;
                off)
                    gsettings set "${GLASS}" solid false
                    echo "$(gettext "Reduce transparency is off.")"
                    ;;
                *) usage ;;
            esac
            ;;
        reduce-motion)
            case "$(flip "${2:-}" "$(motion)")" in
                on)
                    gsettings set "${A11Y}" reduced-motion reduce
                    echo "$(gettext "Reduce motion is on: animations fade in place instead of travelling.")"
                    ;;
                off)
                    gsettings set "${A11Y}" reduced-motion no-preference
                    echo "$(gettext "Reduce motion is off.")"
                    ;;
                *) usage ;;
            esac
            ;;
        increase-contrast)
            case "$(flip "${2:-}" "$(contrast)")" in
                on)
                    gsettings set "${A11Y}" high-contrast true
                    echo "$(gettext "Increase contrast is on: GNOME's High Contrast, with stronger outlines and plain text, in the apps too.")"
                    ;;
                off)
                    gsettings set "${A11Y}" high-contrast false
                    echo "$(gettext "Increase contrast is off.")"
                    ;;
                *) usage ;;
            esac
            ;;
        *) usage ;;
    esac

# Pick the interface font, or go back to the theme's
[positional-arguments]
font FAMILY="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    # shellcheck source=/dev/null
    source /usr/lib/amethystora/theme/lib.sh
    flag="${CONFIG_DIR}/font"
    current="$(head -n1 "${flag}" 2>/dev/null || echo theme)"
    family="${1:-}"
    if [[ -z "${family}" ]]; then
        family="$(gum choose --header "$(eval_gettext "Font (current: \${current})")" --selected "${current}" \
            theme "${UI_FONTS[@]}")"
    fi
    if [[ "${family}" == theme ]]; then
        rm -f "${flag}"
    elif font_installed "${family}"; then
        mkdir -p "${CONFIG_DIR}"
        echo "${family}" >"${flag}"
    else
        echo "$(eval_gettext "No font called \${family} is installed. The fonts offered: ame desktop font")" >&2
        echo "usage: ame desktop font FAMILY|theme"
        exit 64
    fi
    # Written on its own: the font needs no transition, and applying the whole theme again would hold the screen
    gsettings set org.gnome.desktop.interface font-name "$(ui_font) ${FONT_SIZE}"
    gsettings set org.gnome.desktop.interface document-font-name "$(ui_font) $((FONT_SIZE + 1))"
    family="$(ui_font)"
    echo "$(eval_gettext "Font: \${family}.")"

# Pick the monospace font of the terminal, code and Text Editor, or go back to the theme's
[positional-arguments]
mono-font FAMILY="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    # shellcheck source=/dev/null
    source /usr/lib/amethystora/theme/lib.sh
    flag="${CONFIG_DIR}/mono-font"
    current="$(head -n1 "${flag}" 2>/dev/null || echo theme)"
    family="${1:-}"
    if [[ -z "${family}" ]]; then
        family="$(gum choose --header "$(eval_gettext "Monospace font (current: \${current})")" --selected "${current}" \
            theme "${MONO_FONTS[@]}")"
    fi
    if [[ "${family}" == theme ]]; then
        rm -f "${flag}"
    elif font_installed "${family}"; then
        mkdir -p "${CONFIG_DIR}"
        echo "${family}" >"${flag}"
    else
        echo "$(eval_gettext "No font called \${family} is installed. The fonts offered: ame desktop mono-font")" >&2
        echo "usage: ame desktop mono-font FAMILY|theme"
        exit 64
    fi
    gsettings set org.gnome.desktop.interface monospace-font-name "$(mono_font) ${MONO_FONT_SIZE}"
    # kitty's is in the rendered theme, which the theme renders again (the wallpaper stays); a window that is open
    # takes it at once
    AMETHYSTORA_THEME_QUIET=1 amethystora-theme reload >/dev/null
    family="$(mono_font)"
    echo "$(eval_gettext "Monospace font: \${family}.")"

# Pick the pointer (halo, ink or facet), or theme to follow the theme's own
[positional-arguments]
pointer SET="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    # shellcheck source=/dev/null
    source /usr/lib/amethystora/theme/lib.sh
    # Read by amethystora-theme, which writes the pointer at every switch and would otherwise put the theme's own back
    flag="${CONFIG_DIR}/pointer"
    current="$(sed -e 's/^amethystora-pointer-//' "${flag}" 2>/dev/null || echo theme)"
    set="${1:-}"
    if [[ -z "${set}" ]]; then
        echo "halo   $(gettext "White, with an amethyst rim: for dark themes")"
        echo "ink    $(gettext "Dark, with a white rim: for light themes")"
        echo "facet  $(gettext "Cut like the gem, in two faces of amethyst")"
        echo "theme  $(gettext "Whatever the theme chooses")"
        set="$(gum choose --header "$(eval_gettext "Pointer (current: \${current})")" --selected "${current}" \
            "${POINTER_SETS[@]}" theme)"
    fi
    if [[ "${set}" == theme ]]; then
        rm -f "${flag}"
    elif is_pointer_set "${set}"; then
        mkdir -p "${CONFIG_DIR}"
        echo "amethystora-pointer-${set}" >"${flag}"
    else
        echo "usage: ame desktop pointer $(IFS='|'; echo "${POINTER_SETS[*]}")|theme"
        exit 64
    fi
    # Written on its own, over whatever the key held: this is the account's own choice
    gsettings set org.gnome.desktop.interface cursor-theme "$(pointer_theme)"
    echo "$(eval_gettext "Pointer: \${set}.")"

# What shaking the mouse does: grow, beacon or off
[positional-arguments]
pointer-shake MODE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.pointer
    current="$(gsettings get "${schema}" shake | tr -d "'")"
    mode="${1:-}"
    if [[ -z "${mode}" ]]; then
        echo "grow    $(gettext "The pointer swells to three and a half times its size while you shake it")"
        echo "beacon  $(gettext "The pointer grows a little and sends rings out from where it is")"
        echo "off     $(gettext "Shaking the mouse does nothing")"
        mode="$(gum choose --header "$(eval_gettext "Shake to find (current: \${current})")" --selected "${current}" \
            grow beacon off)"
    fi
    case "${mode}" in
        grow | beacon | off) gsettings set "${schema}" shake "${mode}" ;;
        *)
            echo "usage: ame desktop pointer-shake grow|beacon|off"
            exit 64
            ;;
    esac
    echo "$(eval_gettext "Shake to find: \${mode}.")"

# A pointer one size larger on a screen with small pixels shown at 100% (STATE: on or off; without it, it flips)
[positional-arguments]
pointer-dense STATE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.pointer
    state="${1:-}"
    if [[ -z "${state}" ]]; then
        if [[ "$(gsettings get "${schema}" dense)" == true ]]; then state=off; else state=on; fi
    fi
    case "${state}" in
        on)
            gsettings set "${schema}" dense true
            echo "$(gettext "The pointer is one size larger on a dense screen. A size chosen in Settings is kept.")"
            ;;
        off)
            gsettings set "${schema}" dense false
            echo "$(gettext "The pointer keeps its size on every screen.")"
            ;;
        *)
            echo "usage: ame desktop pointer-dense on|off"
            exit 64
            ;;
    esac

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

# How a window goes into the dock and comes back: droplet or shrink
[positional-arguments]
minimize STYLE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.motion
    current="$(gsettings get "${schema}" minimize | tr -d "'")"
    style="${1:-}"
    if [[ -z "${style}" ]]; then
        echo "droplet  $(gettext "The window gathers into a drop of glass and arcs into its icon")"
        echo "shrink   $(gettext "The window shrinks and fades into its icon, as GNOME does it")"
        style="$(gum choose --header "$(eval_gettext "Minimize (current: \${current})")" --selected "${current}" droplet shrink)"
    fi
    case "${style}" in
        droplet | shrink) gsettings set "${schema}" minimize "${style}" ;;
        *)
            echo "usage: ame desktop minimize droplet|shrink"
            exit 64
            ;;
    esac
    case "${style}" in
        droplet) echo "$(gettext "Droplet: a window gathers into a drop of glass and arcs into its icon in the dock.")" ;;
        shrink) echo "$(gettext "Shrink: a window shrinks and fades into its icon, as GNOME does it.")" ;;
    esac

# How workspaces change: depth or slide
[positional-arguments]
workspace-switch STYLE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.motion
    current="$(gsettings get "${schema}" workspace-switch | tr -d "'")"
    style="${1:-}"
    if [[ -z "${style}" ]]; then
        echo "depth  $(gettext "The wallpaper slides a third as far as the windows, which step back a little on the way")"
        echo "slide  $(gettext "Each workspace slides in whole, wallpaper and all")"
        style="$(gum choose --header "$(eval_gettext "Changing workspace (current: \${current})")" --selected "${current}" depth slide)"
    fi
    case "${style}" in
        depth | slide) gsettings set "${schema}" workspace-switch "${style}" ;;
        *)
            echo "usage: ame desktop workspace-switch depth|slide"
            exit 64
            ;;
    esac
    case "${style}" in
        depth) echo "$(gettext "Depth: the wallpaper slides a third as far as the windows, which step back a little on the way.")" ;;
        slide) echo "$(gettext "Slide: each workspace slides in whole, wallpaper and all.")" ;;
    esac

# Workspaces without a name of yours show their main app's name (VALUE: on or off; without it, it flips)
[positional-arguments]
space-names VALUE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.workspaces
    value="${1:-}"
    if [[ -z "${value}" ]]; then
        if [[ "$(gsettings get "${schema}" auto-names)" == true ]]; then value=off; else value=on; fi
    fi
    case "${value}" in
        on)
            gsettings set "${schema}" auto-names true
            echo "$(gettext "A workspace you have not named shows the name of the app with most windows on it.")"
            ;;
        off)
            gsettings set "${schema}" auto-names false
            echo "$(gettext "A workspace you have not named shows its number only.")"
            ;;
        *)
            echo "usage: ame desktop space-names on|off"
            exit 64
            ;;
    esac

# Open the tiling's settings: the gaps, the sizes windows step through, how the strip moves, every shortcut and the window rules
tiling-settings:
    #!/usr/bin/bash
    set -euo pipefail
    gnome-extensions prefs amethystora-ui@iarsslen.github.io

# Windows in the classic layout: snap layouts, the switcher, the Super card, hot corners, show desktop, gestures,
# places and dimming: ame desktop windows [snap|switcher|show-desktop|places|dim on|off] [hold-super on|off|MS]
# [corner top-left|top-right|bottom-left|bottom-right ACTION] [gesture pinch|spread|down|today on|off] [places forget]
[positional-arguments]
windows *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.windows
    usage() {
        echo "usage: ame desktop windows [snap|switcher|show-desktop|places|dim on|off] [hold-super on|off|MS] [corner top-left|top-right|bottom-left|bottom-right none|overview|desktop|lock|note|notifications] [gesture pinch|spread|down|today on|off] [places forget]"
        exit 64
    }
    # The words a person types back, so left as they are
    word() { if [[ "$(gsettings get "${schema}" "$1")" == true ]]; then echo on; else echo off; fi; }
    # on or off as GSettings has it; anything else is refused before a setting is touched
    bool() { if [[ "$1" == on ]]; then echo true; else echo false; fi; }
    onoff() { [[ "$1" == on || "$1" == off ]] || usage; }
    if [[ $# -eq 0 ]]; then
        for key in snap switcher hold-super show-desktop places dim; do
            echo "${key} $(word "${key}")"
        done
        echo "hold-super-delay $(gsettings get "${schema}" hold-super-delay)"
        for where in top-left top-right bottom-left bottom-right; do
            echo "corner ${where} $(gsettings get "${schema}" "corner-${where}" | tr -d "'")"
        done
        for name in pinch spread down today; do
            echo "gesture ${name} $(word "gesture-${name}")"
        done
        exit 0
    fi
    case "$1" in
        snap | switcher | show-desktop | dim)
            [[ $# -eq 2 ]] || usage
            onoff "$2"
            gsettings set "${schema}" "$1" "$(bool "$2")"
            case "$1:$2" in
                snap:on) echo "$(gettext "Snap layouts are on: drag a window to the top of the screen, or press Super+Z.")" ;;
                snap:off) echo "$(gettext "Snap layouts are off.")" ;;
                switcher:on) echo "$(gettext "Super+Tab and Alt+Tab show every window in a grid you can type into.")" ;;
                switcher:off) echo "$(gettext "Super+Tab and Alt+Tab are GNOME's own switchers again.")" ;;
                show-desktop:on) echo "$(gettext "A click on empty wallpaper slides the windows to the edges; a click anywhere brings them back.")" ;;
                show-desktop:off) echo "$(gettext "A click on the wallpaper does nothing.")" ;;
                dim:on) echo "$(gettext "The windows behind the one you are using are drawn a little darker.")" ;;
                dim:off) echo "$(gettext "No window is dimmed.")" ;;
            esac
            ;;
        places)
            [[ $# -eq 2 ]] || usage
            if [[ "$2" == forget ]]; then
                was="$(gsettings get "${schema}" places)"
                # Off first, so that nothing is written while the files go
                gsettings set "${schema}" places false
                sleep 1
                rm -f "${XDG_STATE_HOME:-${HOME}/.local/state}/amethystora/places.json" \
                    "${XDG_STATE_HOME:-${HOME}/.local/state}/amethystora/places.json.bak"
                gsettings set "${schema}" places "${was}"
                echo "$(gettext "The places windows went back to are forgotten.")"
                exit 0
            fi
            onoff "$2"
            gsettings set "${schema}" places "$(bool "$2")"
            if [[ "$2" == on ]]; then
                echo "$(gettext "Windows go back to their places for each arrangement of screens.")"
            else
                echo "$(gettext "Windows open where GNOME puts them.")"
            fi
            ;;
        hold-super)
            [[ $# -eq 2 ]] || usage
            case "$2" in
                on | off)
                    gsettings set "${schema}" hold-super "$(bool "$2")"
                    if [[ "$2" == on ]]; then
                        echo "$(gettext "Holding Super shows the main shortcuts and the dock's numbers.")"
                    else
                        echo "$(gettext "Holding Super shows nothing.")"
                    fi
                    ;;
                *)
                    # Base 10, so that 0900 is nine hundred and not an octal number bash refuses
                    [[ "$2" =~ ^[0-9]{1,5}$ ]] && ((10#$2 >= 500 && 10#$2 <= 3000)) || usage
                    set -- "$1" "$((10#$2))"
                    gsettings set "${schema}" hold-super-delay "$2"
                    gsettings set "${schema}" hold-super true
                    ms="$2"
                    echo "$(eval_gettext "The shortcuts show after Super has been held for \${ms} milliseconds.")"
                    ;;
            esac
            ;;
        corner)
            [[ $# -eq 3 ]] || usage
            case "$2" in top-left | top-right | bottom-left | bottom-right) ;; *) usage ;; esac
            case "$3" in none | overview | desktop | lock | note | notifications) ;; *) usage ;; esac
            gsettings set "${schema}" "corner-$2" "$3"
            where="$2"
            action="$3"
            echo "$(eval_gettext "The \${where} corner now does: \${action}.")"
            ;;
        gesture)
            [[ $# -eq 3 ]] || usage
            case "$2" in pinch | spread | down | today) ;; *) usage ;; esac
            onoff "$3"
            gsettings set "${schema}" "gesture-$2" "$(bool "$3")"
            name="$2"
            state="$3"
            echo "$(eval_gettext "The \${name} gesture is \${state}.")"
            ;;
        *) usage ;;
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

# The live pill: the clock shows what is happening now (ame desktop pill [on|off]); the privacy dots and the
# recording glow beside it (ame desktop pill dots|glow [on|off]). Without on or off, it asks
[positional-arguments]
pill *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.pill
    usage() {
        echo "usage: ame desktop pill [dots|glow] [on|off]"
        exit 64
    }
    what=live
    case "${1:-}" in
        dots) what=privacy-dots; shift ;;
        glow) what=glow; shift ;;
    esac
    [[ $# -le 1 ]] || usage
    state="${1:-}"
    if [[ -z "${state}" ]]; then
        if [[ "$(gsettings get "${schema}" "${what}")" == true ]]; then current=on; else current=off; fi
        state="$(gum choose --header "$(eval_gettext "\${what} (current: \${current})")" --selected "${current}" on off)"
    fi
    case "${what}:${state}" in
        live:on) echo "$(gettext "The live pill is on: the clock shows what is happening now.")" ;;
        live:off) echo "$(gettext "The live pill is off: the clock is GNOME's own.")" ;;
        privacy-dots:on) echo "$(gettext "The privacy dots are on: a dot in the top bar while the microphone, the camera, the screen or the location is in use.")" ;;
        privacy-dots:off) echo "$(gettext "The privacy dots are off: GNOME's own icons show what is in use.")" ;;
        glow:on) echo "$(gettext "The recording glow is on: a red glow round the screen while it is recorded or shared. It shows in a recording of the whole screen.")" ;;
        glow:off) echo "$(gettext "The recording glow is off.")" ;;
        *) usage ;;
    esac
    if [[ "${state}" == on ]]; then gsettings set "${schema}" "${what}" true; else gsettings set "${schema}" "${what}" false; fi

# Quick settings: put every tile back where it was and show them all (reset), or show or hide the theme block (theme on|off)
[positional-arguments]
quick-settings ACTION="" VALUE="":
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.quick
    usage() {
        echo "usage: ame desktop quick-settings reset|theme [on|off]"
        exit 64
    }
    # The tiles put away, one id a line (an id is lower-case letters, digits and hyphens)
    hidden() {
        gsettings get "${schema}" tile-hidden | sed -e 's/^@as //' -e "s/[][',]/ /g" | tr ' ' '\n' |
            grep -E '^[a-z0-9-]{1,40}$' || true
    }
    theme_state() { if hidden | grep -qx theme; then echo off; else echo on; fi; }
    action="${1:-}"
    if [[ -z "${action}" ]]; then
        [[ -t 0 && -t 1 ]] || usage
        current="$(theme_state)"
        echo "reset  $(gettext "Every tile back in its first order, and every tile shown")"
        echo "theme  $(eval_gettext "Show or hide the theme block (now \${current})")"
        action="$(gum choose reset theme)"
    fi
    case "${action}" in
        reset)
            [[ -z "${2:-}" ]] || usage
            gsettings reset "${schema}" tile-order
            gsettings reset "${schema}" tile-hidden
            echo "$(gettext "Quick settings have every tile again, in their first order.")"
            ;;
        theme)
            value="${2:-}"
            if [[ -z "${value}" ]]; then
                [[ -t 0 && -t 1 ]] || usage
                current="$(theme_state)"
                value="$(gum choose --header "$(eval_gettext "The theme block (current: \${current})")" --selected "${current}" on off)"
            fi
            # The other tiles put away stay so
            others="$(hidden | grep -vx theme || true)"
            case "${value}" in
                on) list="${others}" ;;
                off) list="${others}"$'\n'theme ;;
                *) usage ;;
            esac
            gsettings set "${schema}" tile-hidden "[$(grep -v '^$' <<<"${list}" | sed "s/.*/'&'/" | paste -sd, -)]"
            if [[ "${value}" == on ]]; then
                echo "$(gettext "The theme block is in quick settings.")"
            else
                echo "$(gettext "The theme block is hidden from quick settings.")"
            fi
            ;;
        *) usage ;;
    esac

# Quiet: banners wait in the list while a window is fullscreen or the screen is shared or recorded (ame desktop quiet
# [on|off]), and between Night Light's times (ame desktop quiet night [on|off]). Without on or off, it asks
[positional-arguments]
quiet *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.pill
    color=org.gnome.settings-daemon.plugins.color
    usage() {
        echo "usage: ame desktop quiet [night] [on|off]"
        exit 64
    }
    what=quiet
    if [[ "${1:-}" == night ]]; then what=quiet-night; shift; fi
    [[ $# -le 1 ]] || usage
    state="${1:-}"
    if [[ -z "${state}" ]]; then
        if [[ "$(gsettings get "${schema}" "${what}")" == true ]]; then current=on; else current=off; fi
        state="$(gum choose --header "$(eval_gettext "\${what} (current: \${current})")" --selected "${current}" on off)"
    fi
    # Night Light's times as HH:MM, from its decimal hours
    hhmm() { awk -v h="$1" 'BEGIN { m = int(h * 60 + 0.5) % 1440; printf "%02d:%02d", int(m / 60), m % 60 }'; }
    case "${what}:${state}" in
        quiet:on)
            gsettings set "${schema}" quiet true
            echo "$(gettext "Quiet is on: banners wait in the list while a window is fullscreen or the screen is shared or recorded. Calls, alarms and urgent ones still come through.")"
            ;;
        quiet:off)
            gsettings set "${schema}" quiet false
            echo "$(gettext "Quiet while fullscreen or sharing is off.")"
            ;;
        quiet-night:on)
            gsettings set "${schema}" quiet-night true
            if [[ "$(gsettings get "${color}" night-light-schedule-automatic)" == true ]]; then
                echo "$(gettext "Quiet at night is on, from sunset to sunrise.")"
            else
                from="$(hhmm "$(gsettings get "${color}" night-light-schedule-from)")"
                to="$(hhmm "$(gsettings get "${color}" night-light-schedule-to)")"
                echo "$(eval_gettext "Quiet at night is on, between Night Light's times: \${from} to \${to}.")"
            fi
            ;;
        quiet-night:off)
            gsettings set "${schema}" quiet-night false
            echo "$(gettext "Quiet at night is off.")"
            ;;
        *) usage ;;
    esac

# The digest: banners that are not urgent wait and come together at the digest times (ame desktop digest [on|off];
# ame desktop digest times HH:MM [HH:MM]..., one to six of them). Without on or off, it asks
[positional-arguments]
digest *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.pill
    # The times as the key has them, sorted, each once
    times() { gsettings get "${schema}" digest-times | tr -d "[]',@as" | xargs | sed 's/ /, /g'; }
    if [[ "${1:-}" == times ]]; then
        shift
        if [[ $# -lt 1 || $# -gt 6 ]]; then
            echo "usage: ame desktop digest times HH:MM [HH:MM]..."
            exit 64
        fi
        for t in "$@"; do
            if [[ ! "${t}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                echo "usage: ame desktop digest times HH:MM [HH:MM]..."
                exit 64
            fi
        done
        list="$(printf '%s\n' "$@" | sort -u | sed "s/.*/'&'/" | paste -sd, -)"
        gsettings set "${schema}" digest-times "[${list}]"
        shown="$(times)"
        echo "$(eval_gettext "The digest comes at \${shown}.")"
        exit 0
    fi
    [[ $# -le 1 ]] || { echo "usage: ame desktop digest [on|off]"; exit 64; }
    state="${1:-}"
    if [[ -z "${state}" ]]; then
        if [[ "$(gsettings get "${schema}" digest)" == true ]]; then current=on; else current=off; fi
        state="$(gum choose --header "$(eval_gettext "Digest (current: \${current})")" --selected "${current}" on off)"
    fi
    case "${state}" in
        on)
            gsettings set "${schema}" digest true
            shown="$(times)"
            echo "$(eval_gettext "The digest is on: banners that are not urgent wait and come together at \${shown}.")"
            ;;
        off)
            gsettings set "${schema}" digest false
            echo "$(gettext "The digest is off: banners show as they come.")"
            ;;
        *)
            echo "usage: ame desktop digest [on|off]"
            exit 64
            ;;
    esac

# The top bar on every screen (ame desktop top-bar screens [on|off]), and over a fullscreen window when you push the
# pointer against the top edge (ame desktop top-bar peek [on|off]). Without on or off, it asks
[positional-arguments]
top-bar *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.bars
    usage() {
        echo "usage: ame desktop top-bar screens|peek [on|off]"
        exit 64
    }
    [[ $# -ge 1 && $# -le 2 ]] || usage
    case "$1" in
        screens) key=every-screen ;;
        peek) key=peek ;;
        *) usage ;;
    esac
    state="${2:-}"
    if [[ -z "${state}" ]]; then
        if [[ "$(gsettings get "${schema}" "${key}")" == true ]]; then current=on; else current=off; fi
        what="$1"
        state="$(gum choose --header "$(eval_gettext "Top bar \${what} (current: \${current})")" --selected "${current}" on off)"
    fi
    case "$1:${state}" in
        screens:on) echo "$(gettext "Every screen has a top bar with the workspace it shows.")" ;;
        screens:off) echo "$(gettext "Only the main screen has a top bar.")" ;;
        peek:on) echo "$(gettext "Push the pointer against the top edge to see the top bar over a fullscreen window.")" ;;
        peek:off) echo "$(gettext "A fullscreen window keeps the whole screen.")" ;;
        *) usage ;;
    esac
    if [[ "${state}" == on ]]; then gsettings set "${schema}" "${key}" true; else gsettings set "${schema}" "${key}" false; fi

# Today's tasks from Notes in the calendar menu, while Notes is open and unlocked (ame desktop today tasks [on|off]).
# Without on or off, it asks
[positional-arguments]
today *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.today
    usage() {
        echo "usage: ame desktop today tasks [on|off]"
        exit 64
    }
    [[ $# -ge 1 && $# -le 2 && "$1" == tasks ]] || usage
    state="${2:-}"
    if [[ -z "${state}" ]]; then
        if [[ "$(gsettings get "${schema}" tasks)" == true ]]; then current=on; else current=off; fi
        state="$(gum choose --header "$(eval_gettext "Today's tasks (current: \${current})")" --selected "${current}" on off)"
    fi
    case "${state}" in
        on) echo "$(gettext "The calendar menu lists today's tasks while Notes is open and unlocked.")" ;;
        off) echo "$(gettext "The calendar menu shows no tasks.")" ;;
        *) usage ;;
    esac
    if [[ "${state}" == on ]]; then gsettings set "${schema}" tasks true; else gsettings set "${schema}" tasks false; fi

# The weather beside the clock and in the calendar menu, for the place you chose in Weather. It sends that place to a
# weather service, so it is off until you turn it on (ame desktop weather [on|off]). Without on or off, it asks
[positional-arguments]
weather *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.shell.extensions.amethystora-ui.today
    usage() {
        echo "usage: ame desktop weather [on|off]"
        exit 64
    }
    [[ $# -le 1 ]] || usage
    state="${1:-}"
    # What it sends, said once before it can be turned on: before the question, or before turning it on straight away
    if [[ -z "${state}" || "${state}" == on ]]; then
        echo "$(gettext "The place you chose in Weather goes to the weather services GNOME uses, each time the weather is shown.")"
    fi
    if [[ -z "${state}" ]]; then
        if [[ "$(gsettings get "${schema}" weather)" == true ]]; then current=on; else current=off; fi
        state="$(gum choose --header "$(eval_gettext "Weather (current: \${current})")" --selected "${current}" on off)"
    fi
    case "${state}" in
        on)
            gsettings set "${schema}" weather true
            echo "$(gettext "The weather is on.")"
            if [[ "$(gsettings get org.gnome.shell.weather locations 2>/dev/null)" == "@av []" ]]; then
                echo "$(gettext "Choose a place in Weather: it opens with gnome-weather.")"
            fi
            ;;
        off)
            gsettings set "${schema}" weather false
            echo "$(gettext "The weather is off: nothing is sent for it.")"
            ;;
        *) usage ;;
    esac

# Rest reminders, GNOME's own: look away (on or eyesight), stand up (movement), both, or off. The times are in
# Settings, Wellbeing (ame desktop breaks [on|eyesight|movement|both|off]). Without a value, it asks
[positional-arguments]
breaks *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    schema=org.gnome.desktop.break-reminders
    usage() {
        echo "usage: ame desktop breaks on|eyesight|movement|both|off"
        exit 64
    }
    [[ $# -le 1 ]] || usage
    state="${1:-}"
    if [[ -z "${state}" ]]; then
        case "$(gsettings get "${schema}" selected-breaks)" in
            *eyesight*movement* | *movement*eyesight*) current=both ;;
            *eyesight*) current=eyesight ;;
            *movement*) current=movement ;;
            *) current=off ;;
        esac
        state="$(gum choose --header "$(eval_gettext "Rest reminders (current: \${current})")" --selected "${current}" eyesight movement both off)"
    fi
    # GNOME's times for one kind of break, as the account has them, in seconds: between breaks, and a break's length
    seconds_of() { gsettings get "${schema}.$1" "$2" | awk '{print $NF}'; }
    # How long a break lasts, in whole minutes where it is some, else in seconds: a sentence of its own
    lasts() {
        local seconds="$1" minutes=$(($1 / 60))
        if ((seconds >= 60 && seconds % 60 == 0)); then
            echo "$(eval_ngettext "Each break lasts \${minutes} minute." "Each break lasts \${minutes} minutes." "${minutes}")"
        else
            echo "$(eval_ngettext "Each break lasts \${seconds} second." "Each break lasts \${seconds} seconds." "${seconds}")"
        fi
    }
    case "${state}" in
        on | eyesight)
            gsettings set "${schema}" selected-breaks "['eyesight']"
            minutes=$(($(seconds_of eyesight interval-seconds) / 60))
            echo "$(eval_ngettext "A reminder to look away from the screen comes every \${minutes} minute." "A reminder to look away from the screen comes every \${minutes} minutes." "${minutes}")"
            lasts "$(seconds_of eyesight duration-seconds)"
            echo "$(gettext "Change the times in Settings, Wellbeing.")"
            ;;
        movement)
            gsettings set "${schema}" selected-breaks "['movement']"
            minutes=$(($(seconds_of movement interval-seconds) / 60))
            echo "$(eval_ngettext "A reminder to stand up and move comes every \${minutes} minute." "A reminder to stand up and move comes every \${minutes} minutes." "${minutes}")"
            lasts "$(seconds_of movement duration-seconds)"
            echo "$(gettext "Change the times in Settings, Wellbeing.")"
            ;;
        both)
            gsettings set "${schema}" selected-breaks "['eyesight', 'movement']"
            echo "$(gettext "Both reminders are on. Change the times in Settings, Wellbeing.")"
            ;;
        off)
            gsettings set "${schema}" selected-breaks "[]"
            echo "$(gettext "Rest reminders are off.")"
            ;;
        *) usage ;;
    esac

# The dock: how it grows and starts apps, what marks a running app, what it holds and where it lives
# (ame desktop dock SETTING VALUE; without a value it asks; without anything it shows them all)
[positional-arguments]
dock *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    # shellcheck source=/dev/null
    source gettext.sh
    SCHEMA=org.gnome.shell.extensions.amethystora-ui.dock
    get() { gsettings get "${SCHEMA}" "$1" | tr -d "'"; }
    onoff() { if [[ "$(get "$1")" == true ]]; then echo on; else echo off; fi; }
    percent() { awk -v a="$(get magnify-amount)" 'BEGIN { printf "%.0f", a * 100 }'; }
    # on or off for a word that may be missing, which flips the current state
    flip() { if [[ -n "$1" ]]; then echo "$1"; elif [[ "$2" == on ]]; then echo off; else echo on; fi; }
    # A value from a fixed list: the one given, or one chosen; anything else is refused with the setting's usage
    pick() {
        local setting="$1" current="$2" value="$3"
        shift 3
        if [[ -z "${value}" ]]; then
            value="$(gum choose --header "$(eval_gettext "\${setting} (current: \${current})")" --selected "${current}" "$@")"
        fi
        local IFS='|'
        if [[ "|$*|" != *"|${value}|"* ]]; then
            echo "usage: ame desktop dock ${setting} $*" >&2
            exit 64
        fi
        echo "${value}"
    }
    # The folders and stacks are lists, read and written in python, which answers with one word
    lists() {
        python3 -I - "$@" <<'PY'
    import ast, json, os, re, subprocess, sys, unicodedata
    SCHEMA = 'org.gnome.shell.extensions.amethystora-ui.dock'
    XDG = ['DESKTOP', 'DOCUMENTS', 'DOWNLOAD', 'MUSIC', 'PICTURES', 'PUBLICSHARE', 'TEMPLATES', 'VIDEOS']
    APP = re.compile(r'^[A-Za-z0-9._+-]+\.desktop$')
    # A name as the dock takes one: some text, at most 40 characters, no control or format character
    def good_name(name):
        return bool(name.strip()) and len(name) <= 40 and not any(unicodedata.category(c) in ("Cc", "Cf") for c in name)
    def read(schema, key):
        text = subprocess.run(['gsettings', 'get', schema, key], capture_output=True, text=True, check=True).stdout
        return ast.literal_eval(re.sub(r'^@[a-z{}]+ ', '', text.strip()))
    def write(key, value, kind):
        empty = '{}' if kind == 'a{sas}' else '[]'
        text = json.dumps(value, ensure_ascii=True) if value else f'@{kind} {empty}'
        subprocess.run(['gsettings', 'set', SCHEMA, key, text], check=True)
    def special(name):
        out = subprocess.run(['xdg-user-dir', name], capture_output=True, text=True).stdout.strip()
        return out if out and out != os.path.expanduser('~') else None
    def resolve(value):
        if value.startswith('xdg:'):
            return special(value[4:]) if value[4:] in XDG else None
        if value.startswith('~/'):
            return None if '..' in value.split('/') else os.path.join(os.path.expanduser('~'), value[2:])
        return value if value.startswith('/') else None
    def launchers():
        home = os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share')
        dirs = [home] + (os.environ.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share').split(':')
        return [os.path.join(d, 'applications') for d in dirs if d]
    what, *rest = sys.argv[1:]
    if what == 'stack-list':
        for value in read(SCHEMA, 'stacks'):
            print(value)
    elif what in ('stack-add', 'stack-remove'):
        path = os.path.realpath(os.path.expanduser(rest[0]))
        try:
            path.encode("utf-8")
        except UnicodeEncodeError:
            print("not-text")
            sys.exit(0)
        if what == 'stack-add' and not os.path.isdir(path):
            print('not-a-folder')
            sys.exit(0)
        home = os.path.expanduser('~')
        value = next((f'xdg:{name}' for name in XDG if special(name) == path), None)
        if value is None:
            value = '~/' + os.path.relpath(path, home) if path.startswith(home + '/') else path
        stacks = [v for v in read(SCHEMA, 'stacks') if resolve(v) != path]
        if what == 'stack-add':
            if len(stacks) >= 12:
                print('full')
                sys.exit(0)
            stacks.append(value)
        write('stacks', stacks, 'as')
        print('ok')
    elif what == 'folder-list':
        for name, ids in read(SCHEMA, 'folders').items():
            print(name + ': ' + ' '.join(ids))
    elif what == 'folder':
        name, ids = rest[0], rest[1:]
        folders = read(SCHEMA, 'folders')
        if not good_name(name):
            print('bad-name')
            sys.exit(0)
        if not ids:
            folders.pop(name, None)
            write('folders', folders, 'a{sas}')
            print('apart')
            sys.exit(0)
        if name in folders:
            print('taken')
            sys.exit(0)
        pinned = read('org.gnome.shell', 'favorite-apps')
        dirs = launchers()
        for app in ids:
            if not APP.match(app) or app not in pinned or not any(os.path.isfile(os.path.join(d, app)) for d in dirs):
                print('bad-app ' + app)
                sys.exit(0)
        ids = list(dict.fromkeys(ids))
        if len(ids) < 2:
            print('too-few')
            sys.exit(0)
        # An app is in one folder at most; a folder left with one app is taken apart
        others = {n: [a for a in v if a not in ids] for n, v in folders.items() if n != name}
        folders = {n: v for n, v in others.items() if len(v) >= 2}
        folders[name] = ids
        write('folders', folders, 'a{sas}')
        print('ok')
    PY
    }
    say() {
        case "$1" in
            magnify)
                case "$(get magnify)" in
                    swell)
                        amount="$(percent)%"
                        echo "$(eval_gettext "The dock swells under the pointer, up to \${amount}.")" ;;
                    lift) echo "$(gettext "The dock lifts the icon under the pointer.")" ;;
                    *) echo "$(gettext "The dock stays still.")" ;;
                esac ;;
            launch)
                case "$(get launch)" in
                    halo) echo "$(gettext "Apps starting show a ring.")" ;;
                    hop) echo "$(gettext "Apps starting hop.")" ;;
                    breathe) echo "$(gettext "Apps starting breathe.")" ;;
                    *) echo "$(gettext "Apps start without a sign.")" ;;
                esac ;;
            indicator)
                case "$(get indicator)" in
                    bar) echo "$(gettext "A running app is marked with a bar.")" ;;
                    dot) echo "$(gettext "A running app is marked with a dot for each window.")" ;;
                    *) echo "$(gettext "A running app is marked with a glow.")" ;;
                esac ;;
            recent)
                if [[ "$(onoff recent)" == on ]]; then
                    echo "$(gettext "Recent apps are shown after the running ones.")"
                else
                    echo "$(gettext "Recent apps are not shown.")"
                fi ;;
            previews)
                if [[ "$(onoff previews)" == on ]]; then
                    echo "$(gettext "Resting on an app shows its windows.")"
                else
                    echo "$(gettext "Resting on an app shows its name only.")"
                fi ;;
            edge)
                case "$(get edge)" in
                    left) edge="$(gettext "left")" ;;
                    right) edge="$(gettext "right")" ;;
                    *) edge="$(gettext "bottom")" ;;
                esac
                echo "$(eval_gettext "The dock is at the \${edge} of the screen.")" ;;
            screens)
                if [[ "$(get screens)" == every ]]; then
                    echo "$(gettext "There is a dock on every screen.")"
                else
                    echo "$(gettext "There is a dock on the main screen only.")"
                fi ;;
            autohide)
                if [[ "$(get autohide)" == touch ]]; then
                    echo "$(gettext "The dock hides while a window touches it; push the pointer against the edge to bring it back.")"
                else
                    echo "$(gettext "The dock is always shown.")"
                fi ;;
            workspace-apps)
                if [[ "$(onoff workspace-apps)" == on ]]; then
                    echo "$(gettext "The dock shows only the apps of the workspace you are on, and the pinned ones.")"
                else
                    echo "$(gettext "The dock shows every running app.")"
                fi ;;
        esac
    }
    setting="${1:-}"
    value="${2:-}"
    case "${setting}" in
        "")
            echo "magnify $(get magnify)"
            echo "amount $(percent)"
            echo "launch $(get launch)"
            echo "indicator $(get indicator)"
            echo "recent $(onoff recent)"
            echo "previews $(onoff previews)"
            echo "edge $(get edge)"
            echo "screens $(get screens)"
            echo "autohide $(get autohide)"
            echo "workspace-apps $(onoff workspace-apps)"
            echo "folders $(gsettings get "${SCHEMA}" folders)"
            echo "stacks $(gsettings get "${SCHEMA}" stacks)"
            ;;
        magnify | launch | indicator | edge | screens | autohide)
            case "${setting}" in
                magnify) values=(swell lift off) ;;
                launch) values=(halo hop breathe off) ;;
                indicator) values=(bar dot glow) ;;
                edge) values=(bottom left right) ;;
                screens) values=(every primary) ;;
                autohide) values=(off touch) ;;
            esac
            value="$(pick "${setting}" "$(get "${setting}")" "${value}" "${values[@]}")"
            gsettings set "${SCHEMA}" "${setting}" "${value}"
            say "${setting}"
            ;;
        amount)
            if [[ -z "${value}" ]]; then
                value="$(gum input --header "$(gettext "How far Swell grows, 120 to 220 per cent")" --value "$(percent)")"
            fi
            # Per cent (120 to 220), or the multiple itself (1.2 to 2.2)
            amount="$(awk -v v="${value}" 'BEGIN {
                if (v ~ /^[0-9]+$/ && v + 0 >= 120 && v + 0 <= 220) printf "%.2f", v / 100
                else if (v ~ /^[12]\.[0-9]+$/ && v + 0 >= 1.2 && v + 0 <= 2.2) printf "%.2f", v
            }')"
            if [[ -z "${amount}" ]]; then
                echo "usage: ame desktop dock amount 120..220" >&2
                exit 64
            fi
            gsettings set "${SCHEMA}" magnify-amount "${amount}"
            say magnify
            ;;
        recent | previews | workspace-apps)
            case "$(flip "${value}" "$(onoff "${setting}")")" in
                on) gsettings set "${SCHEMA}" "${setting}" true ;;
                off) gsettings set "${SCHEMA}" "${setting}" false ;;
                *)
                    echo "usage: ame desktop dock ${setting} on|off" >&2
                    exit 64
                    ;;
            esac
            say "${setting}"
            ;;
        stack)
            path="${3:-}"
            case "${value}" in
                list) lists stack-list ;;
                add | remove)
                    if [[ -z "${path}" ]]; then
                        echo "usage: ame desktop dock stack add|remove PATH" >&2
                        exit 64
                    fi
                    case "$(lists "stack-${value}" "${path}")" in
                        ok)
                            if [[ "${value}" == add ]]; then
                                echo "$(eval_gettext "\${path} is in the dock.")"
                            else
                                echo "$(eval_gettext "\${path} is no longer in the dock.")"
                            fi ;;
                        not-text)
                            echo "$(eval_gettext "\${path} cannot be kept in the dock: its name is not text.")" >&2
                            exit 1 ;;
                        not-a-folder)
                            echo "$(eval_gettext "\${path} is not a folder.")" >&2
                            exit 1 ;;
                        full)
                            echo "$(gettext "The dock holds twelve stacks at most.")" >&2
                            exit 1 ;;
                    esac
                    ;;
                *)
                    echo "usage: ame desktop dock stack add|remove|list [PATH]" >&2
                    exit 64
                    ;;
            esac
            ;;
        folder)
            name="${value}"
            if [[ -z "${name}" ]]; then
                echo "usage: ame desktop dock folder NAME [APP.desktop APP.desktop...] | folder list" >&2
                exit 64
            fi
            if [[ "${name}" == list && $# -eq 2 ]]; then
                lists folder-list
                exit 0
            fi
            shift 2
            result="$(lists folder "${name}" "$@")"
            case "${result}" in
                ok)
                    apps="$*"
                    echo "$(eval_gettext "The folder \${name} holds \${apps}.")" ;;
                apart) echo "$(eval_gettext "The folder \${name} is taken apart.")" ;;
                taken)
                    echo "$(eval_gettext "There is a folder called \${name} already.")" >&2
                    exit 64 ;;
                bad-name)
                    echo "$(gettext "A folder's name is 1 to 40 characters, without control characters.")" >&2
                    exit 64 ;;
                too-few)
                    echo "$(gettext "A folder holds two pinned apps or more.")" >&2
                    exit 64 ;;
                bad-app*)
                    app="${result#bad-app }"
                    echo "$(eval_gettext "\${app} is not a pinned app.")" >&2
                    exit 64 ;;
            esac
            ;;
        *)
            echo "usage: ame desktop dock [magnify|amount|launch|indicator|recent|previews|edge|screens|autohide|workspace-apps|stack|folder] [VALUE]" >&2
            exit 64
            ;;
    esac

# The terminal's own tools in place of the usual ones: eza for ls, bat for cat, ugrep for grep, with zoxide, direnv and mise (ACTION: on or off)
[positional-arguments]
bling ACTION="":
    @amethystora-bling ${1:+"$1"}
