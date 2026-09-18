#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# No Bluefin / Universal Blue names left in paths or text (07-debrand.sh)
python3 /ctx/build_files/shared/debrand.py --check

for i in bin/ujust share/amethyst/just/{00-entry.just,apps.just,default.just,system.just,update.just,60-custom.just} ; do
   stat /usr/$i
done

test -f /usr/share/amethyst/homebrew/fonts.Brewfile
test -x /usr/bin/amethyst-fastfetch
test -x /usr/libexec/amethyst-greeting
test -f /usr/lib/amethyst/setup-services/libsetup.sh

# If this file is not on the image bazaar will automatically be removed from users systems :(
# See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall
test -f /usr/share/flatpak/preinstall.d/clamui.preinstall

# Brave replaces Firefox; it lives under /usr/lib and is linked into /var/opt at boot
test -x /usr/lib/brave.com/brave/brave
test -f /usr/lib/tmpfiles.d/brave-browser.conf
grep -q "^x-scheme-handler/https=brave-browser.desktop" /etc/xdg/mimeapps.list
grep -q "org.mozilla.firefox" /usr/share/amethyst/homebrew/system-flatpaks.Brewfile && false

# Hyprland + DankMaterialShell session
test -x /usr/libexec/amethyst-hyprland-session
grep -q "^Exec=/usr/libexec/amethyst-hyprland-session$" /usr/share/wayland-sessions/hyprland.desktop
grep -q "dms-greeter --command hyprland" /etc/greetd/config.toml
test -L /etc/systemd/user/graphical-session.target.wants/dms.service
# Without these SELinux labels the greeter cannot start and boot ends on a black screen
grep -qF '/var/cache/dms-greeter(/.*)?' /etc/selinux/targeted/contexts/files/file_contexts.local
grep -qF '/var/lib/greeter(/.*)?' /etc/selinux/targeted/contexts/files/file_contexts.local
test -f /usr/lib/systemd/system/greetd.service.d/10-amethyst-selinux.conf

# Animated boot splash
[[ "$(plymouth-set-default-theme)" == "amethyst" ]]
test -f /usr/share/plymouth/themes/amethyst/throbber-0001.png
test -f /usr/share/plymouth/themes/amethyst/entry.png

# Make sure this garbage never makes it to an image
test -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service && false

IMPORTANT_PACKAGES=(
    brave-browser
    clamav
    clamav-freshclam
    distrobox
    dotnet-sdk-10.0
    fish
    flatpak
    hyprland
    pipewire
    dms
    dms-greeter
    greetd
    systemd
    tailscale
    uupd
    wireplumber
    zsh
)

for package in "${IMPORTANT_PACKAGES[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1 ; }
done

# these packages are supposed to be removed
# and are considered footguns
UNWANTED_PACKAGES=(
    fedora-logos
    firefox
    gdm
    gnome-shell
    gnome-software
    gnome-software-rpm-ostree
    podman-docker
)

for package in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        echo "Unwanted package found: ${package}... Exiting"; exit 1
    fi
done

if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
  NV_PACKAGES=(
      libnvidia-container-tools
      kmod-nvidia
      nvidia-driver-cuda
)
  for package in "${NV_PACKAGES[@]}"; do
      rpm -q "${package}" >/dev/null || { echo "Missing NVIDIA package: ${package}... Exiting"; exit 1 ; }
  done
fi

IMPORTANT_UNITS=(
    clamav-freshclam.service
    greetd.service
    rpm-ostree-countme.timer
    tailscaled.service
    amethyst-system-setup.service
    uupd.timer
  )

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
