#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Replace the GNOME Shell session of the silverblue base with Hyprland and DankMaterialShell (DMS).
# GTK/GNOME applications and libraries (Nautilus, portals, gnome-keyring) are kept: DMS integrates with them.

# shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# GNOME Shell, its login manager and session
GNOME_SHELL_PACKAGES=(
    gdm
    gnome-browser-connector
    gnome-classic-session
    gnome-initial-setup
    gnome-session-wayland-session
    gnome-shell
    gnome-shell-extension-apps-menu
    gnome-shell-extension-common
    gnome-shell-extension-launch-new-instance
    gnome-shell-extension-places-menu
    gnome-shell-extension-window-list
    gnome-tour
    ptyxis
)
readarray -t INSTALLED_GNOME < <(rpm -qa --queryformat='%{NAME}\n' "${GNOME_SHELL_PACKAGES[@]}" 2>/dev/null || true)
if [[ "${#INSTALLED_GNOME[@]}" -gt 0 ]]; then
    dnf -y remove "${INSTALLED_GNOME[@]}"
fi

# GNOME Shell extensions and their settings shipped by projectbluefin/common
rm -rf /usr/share/gnome-shell/extensions
rm -f /etc/dconf/db/distro.d/04-bluefin-custom-command-menu \
    /etc/dconf/db/distro.d/05-bluefin-searchlight-extension

# Desktop support from Fedora repos
dnf -y install \
    accountsservice \
    brightnessctl \
    cava \
    gnome-keyring \
    gnome-keyring-pam \
    greetd \
    kitty \
    nautilus \
    playerctl \
    qt6-qtmultimedia \
    wl-clipboard \
    xdg-desktop-portal-gtk

# Hyprland from sdegler/hyprland, the maintained Fedora packaging (solopasha/hyprland is abandoned)
copr_install_isolated "sdegler/hyprland" \
    hyprland \
    xdg-desktop-portal-hyprland

# DMS and its companions: dms needs dgop and quickshell from danklinux, so both COPRs are enabled together
for copr in avengemedia/dms avengemedia/danklinux; do
    dnf5 -y copr enable "${copr}"
    dnf5 -y copr disable "${copr}"
done
dnf_install_retry \
    --enablerepo="copr:copr.fedorainfracloud.org:avengemedia:dms" \
    --enablerepo="copr:copr.fedorainfracloud.org:avengemedia:danklinux" \
    cliphist \
    danksearch \
    dgop \
    dms \
    dms-greeter \
    material-symbols-fonts \
    matugen \
    quickshell-git

# Hyprland session: start through Amethyst's wrapper, which deploys the DMS config on first login
sed -i 's|^Exec=.*|Exec=/usr/libexec/amethyst-hyprland-session|' /usr/share/wayland-sessions/hyprland.desktop
rm -f /usr/share/wayland-sessions/hyprland-uwsm.desktop

# DMS shell starts with every graphical session (it only runs under graphical-session.target)
systemctl --global enable dms.service amethyst-dms-defaults.service

# Log in through the DMS greeter running on Hyprland
cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dms-greeter --command hyprland"
EOF
systemctl enable greetd.service
systemctl set-default graphical.target

echo "::endgroup::"
