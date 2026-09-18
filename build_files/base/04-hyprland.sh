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

# hyprbars window title bars. The COPR's hyprland-plugin-hyprbars lags behind its hyprland and requires an
# older release, so build the plugin against the installed Hyprland headers. The commit must be the one
# hyprpm pins for the installed Hyprland: https://github.com/hyprwm/hyprland-plugins/blob/main/hyprpm.toml
HYPRLAND_PLUGINS_COMMIT=7644cecdb947060682891a0db2a0cdc5c0b9e704 # v0.56.0
rpm -qa --queryformat='%{NAME}\n' | sort -u >/tmp/packages-before-hyprbars
dnf_install_retry --enablerepo="copr:copr.fedorainfracloud.org:sdegler:hyprland" hyprland-devel meson
mkdir -p /tmp/hyprland-plugins
ghcurl "https://github.com/hyprwm/hyprland-plugins/archive/${HYPRLAND_PLUGINS_COMMIT}.tar.gz" --retry 3 |
    tar -xz --strip-components=1 -C /tmp/hyprland-plugins
meson setup /tmp/hyprland-plugins/hyprbars/build /tmp/hyprland-plugins/hyprbars --buildtype=release
meson compile -C /tmp/hyprland-plugins/hyprbars/build
install -Dm0755 /tmp/hyprland-plugins/hyprbars/build/libhyprbars.so /usr/lib64/hyprland/libhyprbars.so
# Drop the build dependencies again
comm -13 /tmp/packages-before-hyprbars <(rpm -qa --queryformat='%{NAME}\n' | sort -u) | xargs -r dnf -y remove
rm -rf /tmp/hyprland-plugins /tmp/packages-before-hyprbars

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

# SELinux: greetd runs the greeter as xdm_t, which can only write to the greeter's home and cache (where it
# unpacks its UI and Hyprland config) once they are labelled as home directories. Without this the greeter
# dies at boot and the screen stays black. dms-greeter's %post sets these rules but ignores failures, so set
# them here where a failure stops the build. greetd.service relabels existing installs on start.
for fcontext in "cache_home_t /var/cache/dms-greeter(/.*)?" "user_home_dir_t /var/lib/greeter(/.*)?"; do
    read -r setype pattern <<<"${fcontext}"
    semanage fcontext -a -t "${setype}" "${pattern}" || semanage fcontext -m -t "${setype}" "${pattern}"
done

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
command = "/usr/libexec/amethyst-greeter --command hyprland"
EOF
systemctl enable greetd.service
systemctl set-default graphical.target

echo "::endgroup::"
