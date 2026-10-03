# vim: set ft=make :

set default-list

# Install JetBrains Toolbox | https://www.jetbrains.com/toolbox-app/
jetbrains-toolbox:
    #!/usr/bin/env bash
    brew tap amethystora/homebrew-tap
    brew install --cask jetbrains-toolbox-linux

# Install OpenTabletDriver, an open source, cross-platform, user-mode tablet driver
opentabletdriver:
    #!/usr/bin/bash
    gum confirm --affirmative="Install" --negative="Uninstall" "Installer for OpenTabletDriver"
    EXIT_CODE="$?"

    if [ "${EXIT_CODE}" == 0 ] ; then
      echo "Installing OpenTabletDriver..."

      OTD_TMPDIR="$(mktemp -d)"

      curl -s "https://api.github.com/repos/OpenTabletDriver/OpenTabletDriver/releases/latest" \
        | jq -r '.assets[] | select(.name | test("opentabletdriver.*tar.gz$")) | .browser_download_url' \
        | xargs curl -L -s \
        | tar --strip-components=1 -xvzf - -C "${OTD_TMPDIR}"

      # https://opentabletdriver.net/Wiki/Documentation/RequiredPermissions
      sudo cp "${OTD_TMPDIR}/etc/udev/rules.d/70-opentabletdriver.rules" /etc/udev/rules.d/71-opentabletdriver.rules
      echo -ne "blacklist hid_uclogic\nblacklist wacom\n" | sudo tee /etc/modprobe.d/blacklist-opentabletdriver.conf
      rm -rf "${OTD_TMPDIR}"

      flatpak --system install -y flathub net.opentabletdriver.OpenTabletDriver

      mkdir -p "$HOME/.config/systemd/user"
      curl -s "https://raw.githubusercontent.com/flathub/net.opentabletdriver.OpenTabletDriver/refs/heads/master/scripts/opentabletdriver.service" > "$HOME/.config/systemd/user/opentabletdriver.service"

      systemctl --user daemon-reload
      systemctl enable --user --now opentabletdriver.service
    elif [ "${EXIT_CODE}" == 1 ] ; then
      echo "Uninstalling OpenTabletDriver..."
      sudo rm -f /etc/modprobe.d/blacklist-opentabletdriver.rules /etc/udev/rules.d/71-opentabletdriver.rules
      flatpak --system remove -y flathub net.opentabletdriver.OpenTabletDriver
    fi

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

# Install system flatpaks for rebasers
flatpaks $confirm="1" $dx_only="0":
    #!/usr/bin/env bash
    if [[ "$(jq '."image-flavor"' /usr/share/amethystora/image-info.json)" =~ dx ]] ; then
        ADD_DEVMODE="${ADD_DEVMODE:-1}"
    fi
    if [ "${ADD_DEVMODE:-0}" == "1" ] ; then
        if [ "$confirm" != 0 ] ; then
            gum confirm "Install development flatpaks?" || exit 0
        fi
        brew bundle --file="${TARGET_FLATPAK_FILE:-/usr/share/amethystora/homebrew/system-dx-flatpaks.Brewfile}"
    fi
    [ "$dx_only" == 1 ] && exit 0
    if [ "$confirm" != 0 ] ; then
        gum confirm "Install system flatpaks?" || exit 0
    fi
    brew bundle --file="${TARGET_FLATPAK_FILE:-/usr/share/amethystora/homebrew/system-flatpaks.Brewfile}"

# Configure Amethystora-CLI Terminal Experience with Brew
[no-exit-message]
cli:
    @amethystora-bling
    brew bundle --file=/usr/share/amethystora/homebrew/cli.Brewfile

# Let amethystora-pkg build packages from the Arch User Repository, or stop it again (off by default)
aur:
    #!/usr/bin/bash
    set -euo pipefail
    # Read by amethystora-pkg, which shows its paru manager and arch-aur template only while it is there
    FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/aur"
    if [[ -e "${FLAG}" ]]; then
        rm -f "${FLAG}"
        echo "The AUR is off. Containers made with it keep what they have, and what came from Arch's"
        echo "own repositories in them is still upgraded every day. Nothing more is built from the AUR."
        exit 0
    fi
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
