# vim: set ft=make :

set default-list

# Install JetBrains Toolbox into your home, from JetBrains, checked against the checksum JetBrains publishes
jetbrains-toolbox:
    #!/usr/bin/bash
    set -euo pipefail
    DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
    # A folder of its own, which it updates itself in
    DEST="${DATA}/jetbrains-toolbox"
    if [[ -x "${DEST}/bin/jetbrains-toolbox" ]]; then
        echo "JetBrains Toolbox is installed in ${DEST}, and keeps itself up to date."
        gum confirm --default=false "Install it again?" || exit 0
    fi
    case "$(uname -m)" in
        x86_64) platform=linux ;;
        aarch64) platform=linuxARM64 ;;
        *) echo "JetBrains makes no Toolbox for $(uname -m)."; exit 1 ;;
    esac
    # JetBrains' release feed, the one its download page reads
    release="$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release")"
    link="$(jq -er --arg p "${platform}" '.TBA[0].downloads[$p].link' <<<"${release}")"
    checksum="$(curl -fsSL "$(jq -er --arg p "${platform}" '.TBA[0].downloads[$p].checksumLink' <<<"${release}")")"
    TMP="$(mktemp -d)"
    trap 'rm -rf "${TMP}"' EXIT
    echo "Downloading JetBrains Toolbox $(jq -r '.TBA[0].version' <<<"${release}") from JetBrains"
    curl -fL --progress-bar -o "${TMP}/toolbox.tar.gz" "${link}"
    if [[ "$(sha256sum "${TMP}/toolbox.tar.gz" | cut -d" " -f1)" != "${checksum%% *}" ]]; then
        echo "The download does not match the checksum JetBrains publishes for it. Nothing was installed."
        exit 1
    fi
    mkdir -p "${TMP}/toolbox"
    tar -xzf "${TMP}/toolbox.tar.gz" --strip-components=1 -C "${TMP}/toolbox"
    rm -rf "${DEST}"
    mv "${TMP}/toolbox" "${DEST}"
    mkdir -p "${HOME}/.local/bin" "${DATA}/applications"
    ln -sf "${DEST}/bin/jetbrains-toolbox" "${HOME}/.local/bin/jetbrains-toolbox"
    # Toolbox writes a launcher of its own when it first runs; this one shows it in the app grid until then
    if [[ -f "${DEST}/bin/jetbrains-toolbox.desktop" ]]; then
        sed -e "s|^Exec=.*|Exec=${DEST}/bin/jetbrains-toolbox %u|" -e "s|^Icon=.*|Icon=${DEST}/bin/toolbox-tray-color.png|" \
            "${DEST}/bin/jetbrains-toolbox.desktop" >"${DATA}/applications/jetbrains-toolbox.desktop"
    fi
    setsid -f "${DEST}/bin/jetbrains-toolbox" >/dev/null 2>&1
    echo "Installed in ${DEST}. It opens now, and is in the app grid as JetBrains Toolbox."

# Games: Steam from Flathub with ProtonPlus, the MangoHud overlay and gamescope, and X11 granted back to Steam alone
gaming ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    STEAM=com.valvesoftware.Steam
    # Launchers for other stores, offered beside Steam. Each draws through X11 too.
    declare -A LAUNCHERS=(
        ["Heroic (Epic, GOG and Amazon games)"]=com.heroicgameslauncher.hgl
        ["Lutris (games from anywhere else)"]=net.lutris.Lutris
    )
    action="{{ ACTION }}"
    if flatpak info "${STEAM}" >/dev/null 2>&1; then
        echo "Gaming is set up: Steam is installed."
        [[ -n "${action}" ]] || action="$(gum choose --header "Games" "Add another launcher" "Take it all away" "Cancel")"
    else
        [[ -n "${action}" ]] || action="$(gum choose --header "Games" "Set up" "Cancel")"
    fi
    case "${action}" in
        "Set up" | on)
            echo "This installs from Flathub Steam, ProtonPlus, which adds other versions of Proton, and the"
            echo "MangoHud overlay and gamescope compositor that Steam's games can use."
            echo
            echo "The image takes X11 from every app, because an app on X11 can read what you type into other"
            echo "X11 apps. Steam and the Windows games it runs through Proton draw on nothing else, so X11 is"
            echo "granted back to Steam alone, for your account. The Security app's Apps page lists it, and"
            echo "\`ame apps gaming off\` takes it back with the rest."
            echo
            echo "Steam Input, which lets every controller work in every game, makes a virtual controller"
            echo "through /dev/uinput, which the image keeps from apps: a virtual keyboard can type into any"
            echo "window. This gives it back to whoever sits at the machine (ame security virtual-input), and"
            echo "so to every app that may reach all of /dev, the Chromium browsers among them."
            gum confirm "Set up gaming?" || exit 0
            sudo /usr/libexec/amethystora-hardening set virtual-input off
            flatpak install --system -y flathub "${STEAM}" com.vysp3r.ProtonPlus
            # The overlay and the compositor are Vulkan layers of Steam's runtime, so of its branch
            branch="$(flatpak info --show-runtime "${STEAM}" | cut -d/ -f3)"
            flatpak install --system -y flathub "org.freedesktop.Platform.VulkanLayer.MangoHud//${branch}" \
                "org.freedesktop.Platform.VulkanLayer.gamescope//${branch}"
            flatpak override --user --socket=x11 "${STEAM}"
            mapfile -t chosen < <(printf '%s\n' "${!LAUNCHERS[@]}" | sort |
                gum choose --no-limit --header "Also install? (space to pick, enter when done)" || true)
            for name in "${chosen[@]}"; do
                [[ -n "${name}" ]] || continue
                flatpak install --system -y flathub "${LAUNCHERS[${name}]}"
                flatpak override --user --socket=x11 "${LAUNCHERS[${name}]}"
            done
            echo
            echo "Ready. Open Steam from the app grid. In a game's Properties, under Launch Options:"
            echo "  mangohud %command%                the overlay with frame rate and temperatures"
            echo "  gamemoderun %command%             the CPU's performance mode while the game runs"
            echo "  gamescope -f -- %command%         the game in gamescope, full screen"
            ;;
        "Add another launcher" | launchers)
            mapfile -t chosen < <(printf '%s\n' "${!LAUNCHERS[@]}" | sort | gum choose --no-limit --header "Install which?" || true)
            for name in "${chosen[@]}"; do
                [[ -n "${name}" ]] || continue
                flatpak install --system -y flathub "${LAUNCHERS[${name}]}"
                flatpak override --user --socket=x11 "${LAUNCHERS[${name}]}"
            done
            ;;
        "Take it all away" | off)
            gum confirm --default=false "Uninstall Steam, ProtonPlus and the launchers added with them, with their games?" || exit 0
            for app in "${STEAM}" com.vysp3r.ProtonPlus "${LAUNCHERS[@]}"; do
                flatpak override --user --reset "${app}" 2>/dev/null || true
                if flatpak info "${app}" >/dev/null 2>&1; then
                    flatpak uninstall --system -y --delete-data "${app}"
                fi
            done
            # The Vulkan layers are left to flatpak's own clean-up of what nothing uses
            flatpak uninstall --system -y --unused
            # Virtual keyboards go back to root's, unless the tablet driver still needs them
            if [[ ! -e /etc/udev/rules.d/71-opentabletdriver.rules ]]; then
                sudo /usr/libexec/amethystora-hardening set virtual-input on
            fi
            echo "Done. X11 is taken back from them with their overrides, and /dev/uinput at the next restart."
            ;;
        *) exit 0 ;;
    esac

# Android apps, in Waydroid: set it up, start it, stop it, or take it all away again
android ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    action="{{ ACTION }}"
    # Written by `waydroid init`, so there whenever Android has been set up
    if sudo test -e /var/lib/waydroid/waydroid.cfg; then
        echo "Android is set up. Its container is $(systemctl is-active waydroid-container.service || true)."
        [[ -n "${action}" ]] || action="$(gum choose --header "Android apps (Waydroid)" "Start" "Stop" "Take it all away" "Cancel")"
    else
        [[ -n "${action}" ]] || action="$(gum choose --header "Android apps (Waydroid)" "Set up" "Cancel")"
    fi
    case "${action}" in
        "Set up" | on)
            echo "Waydroid runs Android, LineageOS 20, in a container beside your desktop, and the Android apps"
            echo "you install appear in the app grid. Setting it up downloads Android from Waydroid's servers,"
            echo "about a gigabyte, without Google's apps: get apps from F-Droid, or install an .apk with"
            echo "waydroid app install <file>. Its container service runs as root while it is on."
            nvidia=false
            if [[ "$(jq -r '."image-flavor" // ""' /usr/share/amethystora/image-info.json 2>/dev/null)" == nvidia* ]]; then
                nvidia=true
                echo
                echo "Waydroid cannot draw with NVIDIA's driver, so on this image Android draws in software:"
                echo "fine for most apps, slow for games."
            fi
            gum confirm "Set up Android apps?" || exit 0
            sudo systemctl enable --now waydroid-container.service
            # Fedora's package leaves the download channels empty, so they are named here
            sudo waydroid init -c https://ota.waydro.id/system -v https://ota.waydro.id/vendor
            # What waydroid init writes has to carry the labels its own SELinux policy expects
            sudo restorecon -R /var/lib/waydroid
            if [[ "${nvidia}" == true ]]; then
                sudo sed -i '/^\[properties\]/a ro.hardware.gralloc=default\nro.hardware.egl=swiftshader' /var/lib/waydroid/waydroid.cfg
                sudo waydroid upgrade -o
            fi
            echo
            echo "Ready. Open Waydroid from the app grid; the first start takes a minute."
            ;;
        "Start" | start)
            sudo systemctl start waydroid-container.service
            setsid -f waydroid show-full-ui >/dev/null 2>&1
            ;;
        "Stop" | stop)
            waydroid session stop 2>/dev/null || true
            sudo systemctl stop waydroid-container.service
            echo "Stopped. It starts again with ame apps android start."
            ;;
        "Take it all away" | off)
            gum confirm --default=false "Remove Android, with every app and everything saved in it?" || exit 0
            waydroid session stop 2>/dev/null || true
            sudo systemctl disable --now waydroid-container.service
            sudo rm -rf /var/lib/waydroid
            rm -rf "${XDG_DATA_HOME:-${HOME}/.local/share}/waydroid"
            rm -f "${XDG_DATA_HOME:-${HOME}/.local/share}"/applications/waydroid.*.desktop
            echo "Removed. Waydroid itself stays in the image, set up only when you ask."
            ;;
        *) exit 0 ;;
    esac

# Drawing tablets: OpenTabletDriver from Flathub, with the udev rules of its pinned release (ACTION: on or off)
opentabletdriver ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    APP=net.opentabletdriver.OpenTabletDriver
    RULES=/etc/udev/rules.d/71-opentabletdriver.rules
    BLACKLIST=/etc/modprobe.d/blacklist-opentabletdriver.conf
    # The image's own copy of the daemon's user unit (/usr/lib/systemd/user), off until this turns it on
    UNIT=amethystora-opentabletdriver.service
    # The release the udev rules come from, and the SHA-256 of its tarball, both bumped by Renovate
    # (.github/renovate.json5): nothing is copied into /etc from a download that does not match
    OTD_TAG="v0.6.7"
    OTD_SHA256="38b6953ef67579d0afbc99c28522e54182f28838920102566bb5619f152f7b2d"
    action="{{ ACTION }}"
    if flatpak info "${APP}" >/dev/null 2>&1 || [[ -e "${RULES}" ]]; then
        echo "OpenTabletDriver is set up."
        [[ -n "${action}" ]] || action="$(gum choose --header "Drawing tablets (OpenTabletDriver)" "Take it away" "Cancel")"
    else
        [[ -n "${action}" ]] || action="$(gum choose --header "Drawing tablets (OpenTabletDriver)" "Set up" "Cancel")"
    fi
    case "${action}" in
        "Set up" | on)
            echo "OpenTabletDriver drives most drawing tablets, Wacom, Huion, XP-Pen, Gaomon and many more, the"
            echo "same way on every one: pressure, the pen's buttons, and which part of the screen the tablet"
            echo "covers. This installs it from Flathub, and copies its udev rules from its ${OTD_TAG} release"
            echo "into /etc so that it can reach the tablet. It turns off the kernel's own tablet drivers"
            echo "(wacom, hid_uclogic), which would take the tablet first: if one already has, restart."
            echo
            echo "It moves the pointer through /dev/uinput, which the image keeps from apps: a virtual keyboard"
            echo "can type into any window. This gives it back to whoever sits at the machine (ame security"
            echo "virtual-input), and so to every app that may reach all of /dev, the Chromium browsers among them."
            gum confirm "Set up OpenTabletDriver?" || exit 0
            sudo /usr/libexec/amethystora-hardening set virtual-input off
            TMP="$(mktemp -d)"
            trap 'rm -rf "${TMP}"' EXIT
            url="https://github.com/OpenTabletDriver/OpenTabletDriver/releases/download/${OTD_TAG}/opentabletdriver-${OTD_TAG#v}_linux-x64_binary.tar.gz"
            curl -fL --progress-bar -o "${TMP}/otd.tar.gz" "${url}"
            if [[ "$(sha256sum "${TMP}/otd.tar.gz" | cut -d" " -f1)" != "${OTD_SHA256}" ]]; then
                echo "The download does not match the checksum pinned for ${OTD_TAG}. Nothing was installed."
                exit 1
            fi
            tar -xzf "${TMP}/otd.tar.gz" -C "${TMP}" --strip-components=1 \
                opentabletdriver/etc/udev/rules.d/70-opentabletdriver.rules
            # https://opentabletdriver.net/Wiki/Documentation/RequiredPermissions
            sudo install -m 0644 "${TMP}/etc/udev/rules.d/70-opentabletdriver.rules" "${RULES}"
            printf 'blacklist hid_uclogic\nblacklist wacom\n' | sudo tee "${BLACKLIST}" >/dev/null
            sudo udevadm control --reload-rules
            flatpak install --system -y flathub "${APP}"
            # An earlier recipe downloaded a unit of its own into the account; the image's takes its place
            if [[ -e "${HOME}/.config/systemd/user/opentabletdriver.service" ]]; then
                systemctl --user disable --now opentabletdriver.service 2>/dev/null || true
                rm -f "${HOME}/.config/systemd/user/opentabletdriver.service"
            fi
            systemctl --user daemon-reload
            systemctl --user enable --now "${UNIT}"
            echo
            echo "Ready. Plug the tablet in, and set it up in OpenTabletDriver, in the app grid."
            ;;
        "Take it away" | off)
            gum confirm --default=false "Uninstall OpenTabletDriver, with its settings and its udev rules?" || exit 0
            # With the blacklist left behind, the kernel's own tablet drivers would stay off
            sudo rm -f "${BLACKLIST}" "${RULES}"
            sudo udevadm control --reload-rules
            # Virtual keyboards go back to root's, unless Steam Input still needs them
            if ! flatpak info --system com.valvesoftware.Steam >/dev/null 2>&1; then
                sudo /usr/libexec/amethystora-hardening set virtual-input on
            fi
            systemctl --user disable --now "${UNIT}" 2>/dev/null || true
            systemctl --user disable --now opentabletdriver.service 2>/dev/null || true
            rm -f "${HOME}/.config/systemd/user/opentabletdriver.service"
            systemctl --user daemon-reload
            if flatpak info "${APP}" >/dev/null 2>&1; then
                flatpak uninstall --system -y --delete-data "${APP}"
            fi
            echo "Uninstalled. Restart to let the kernel's own tablet drivers load again."
            ;;
        *) exit 0 ;;
    esac

# Install applications from curated Brewfiles (includes full-desktop.Brewfile with GNOME Circle apps)
bbrew:
    #!/usr/bin/env bash
    if ! command -v bbrew &>/dev/null ; then
        if gum confirm "Bold Brew is not installed, would you like to install it?" ; then
            set -e
            brew install Valkyrie00/homebrew-bbrew/bbrew
            set +e
        else
            exit 0
        fi
    fi
    echo "Note: Some of these take a while to load, we'll keep working on it."
    bbrew -f "/usr/share/amethystora/homebrew/$(gum choose $(find "/usr/share/amethystora/homebrew"/*.Brewfile -exec basename '{}' '.Brewfile' ';')).Brewfile"

# Install CNCF projects from a curated Brewfile
cncf:
    #!/usr/bin/env bash
    if ! command -v bbrew &>/dev/null ; then
        if gum confirm "Bold Brew is not installed, would you like to install it?" ; then
            brew install Valkyrie00/homebrew-bbrew/bbrew
        else
            exit 0
        fi
    fi
    bbrew -f "/usr/share/amethystora/homebrew/cncf.Brewfile"

# Install the apps this image comes with now, instead of waiting for flatpak-preinstall.service
flatpaks:
    flatpak preinstall

# Configure Amethystora-CLI Terminal Experience with Brew
[no-exit-message]
cli:
    @amethystora-bling on
    brew bundle --file=/usr/share/amethystora/homebrew/cli.Brewfile

# Sites in windows of their own, with a launcher in the app grid: list, install, remove (amethystora-webapp)
[no-cd]
[no-exit-message]
[positional-arguments]
webapps *ARGS:
    @amethystora-webapp "$@"

# Let amethystora-pkg build packages from the Arch User Repository, or stop it again (ACTION: on or off; off by default, and without it, it flips)
aur ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    # Read by amethystora-pkg, which shows its paru manager and arch-aur template only while it is there
    FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/aur"
    action="{{ ACTION }}"
    if [[ -z "${action}" ]]; then
        if [[ -e "${FLAG}" ]]; then action=off; else action=on; fi
    fi
    case "${action}" in
        on)
            if [[ -e "${FLAG}" ]]; then
                echo "The AUR is already on."
                exit 0
            fi
            ;;
        off)
            rm -f "${FLAG}"
            echo "The AUR is off. Containers made with it keep what they have, and what came from Arch's"
            echo "own repositories in them is still upgraded every day. Nothing more is built from the AUR."
            exit 0
            ;;
        *)
            echo "usage: ame apps aur [on|off]"
            exit 64
            ;;
    esac
    echo "The Arch User Repository (AUR) is build scripts, PKGBUILDs, that anyone can upload and nobody"
    echo "reviews, and malware has been found in it more than once. What you build from it runs as you,"
    echo "with your files, your display and your session, as anything in a container does."
    echo
    echo "Turned on, amethystora-pkg offers the arch-aur template, whose containers keep their settings in"
    echo "a home folder of their own, and the paru manager. Before anything is built it shows what the"
    echo "AUR knows of it: who maintains it, how many vote for it, how old it is, whether it is flagged"
    echo "out of date. paru then shows you the PKGBUILD itself: read it. Packages from the AUR are never"
    echo "upgraded unattended."
    gum confirm --default=false "Turn the AUR on?" || exit 0
    mkdir -p "$(dirname "${FLAG}")"
    touch "${FLAG}"
    echo "On. Make a container for it with: amepkg containers new --template arch-aur"
