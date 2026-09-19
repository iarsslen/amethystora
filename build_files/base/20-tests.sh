#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# No Bluefin / Universal Blue names left in paths or text (07-debrand.sh)
python3 /ctx/build_files/shared/debrand.py --check

for i in bin/ujust share/amethystora/just/{00-entry.just,apps.just,default.just,system.just,update.just,60-custom.just} ; do
   stat /usr/$i
done

test -f /usr/share/amethystora/homebrew/fonts.Brewfile
test -x /usr/bin/amethystora-fastfetch
# Logo in the text console colours (amethystora-greeting)
test -f /usr/share/amethystora/logos/console/amethystora
test -x /usr/libexec/amethystora-greeting
test -f /usr/lib/amethystora/setup-services/libsetup.sh

# If this file is not on the image bazaar will automatically be removed from users systems :(
# See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall
test -f /usr/share/flatpak/preinstall.d/clamui.preinstall

# Brave replaces Firefox; it lives under /usr/lib and is linked into /var/opt at boot
test -x /usr/lib/brave.com/brave/brave
test -f /usr/lib/tmpfiles.d/brave-browser.conf
grep -q "^x-scheme-handler/https=brave-browser.desktop" /etc/xdg/mimeapps.list
grep -q "org.mozilla.firefox" /usr/share/amethystora/homebrew/system-flatpaks.Brewfile && false

# Hyprland + DankMaterialShell session
test -x /usr/libexec/amethystora-hyprland-session
grep -q "^Exec=/usr/libexec/amethystora-hyprland-session$" /usr/share/wayland-sessions/hyprland.desktop
grep -q "^command = \"/usr/libexec/amethystora-greeter --command hyprland\"$" /etc/greetd/config.toml
test -x /usr/libexec/amethystora-greeter
test -f /usr/lib/amethystora/graphics.sh
test -L /etc/systemd/user/graphical-session.target.wants/dms.service
# Without these SELinux labels the greeter cannot start and boot ends on a black screen
grep -qF '/var/cache/dms-greeter(/.*)?' /etc/selinux/targeted/contexts/files/file_contexts.local
grep -qF '/var/lib/greeter(/.*)?' /etc/selinux/targeted/contexts/files/file_contexts.local
test -f /usr/lib/systemd/system/greetd.service.d/10-amethystora-selinux.conf
# Window title bars
test -f /usr/lib64/hyprland/libhyprbars.so
test -f /usr/share/amethystora/hypr/hyprbars.lua
rpm -q hyprland-devel >/dev/null && false

# Animated boot splash: the script theme, the images it loads, and both in the initramfs, which shows the
# splash up to and including the LUKS password prompt
[[ "$(plymouth-set-default-theme)" == "amethystora" ]]
rpm -q plymouth-plugin-script >/dev/null
test -f /usr/share/plymouth/themes/amethystora/amethystora.script
for image in nebula halo dust gem light shard-0 wordmark credit bullet entry lock; do
    test -f "/usr/share/plymouth/themes/amethystora/${image}.png"
done
INITRAMFS_FILES="$(lsinitrd /lib/modules/*/initramfs.img)"
grep -q "plymouth/script.so" <<<"${INITRAMFS_FILES}"
grep -q "themes/amethystora/amethystora.script" <<<"${INITRAMFS_FILES}"
# Boot and login text in Inter: fc-match falls back to another family when it is missing
[[ "$(fc-match -f '%{family[0]}' 'Inter')" == "Inter" ]]
grep -q "^Font=Inter " /usr/share/plymouth/themes/amethystora/amethystora.plymouth

# Login screen: Amethystora wallpaper and font until a user syncs their own
test -f /usr/share/backgrounds/amethystora/amethystora-d.png
jq -e '.wallpaperPath == "/usr/share/backgrounds/amethystora/amethystora-d.png"' /usr/share/amethystora/greeter/session.json
jq -e '.fontFamily == "Inter"' /usr/share/amethystora/greeter/settings.json
grep -q "^C /var/cache/dms-greeter/session.json " /usr/lib/tmpfiles.d/amethystora-greeter.conf
grep -q "^Z /var/cache/dms-greeter - greeter greeter -$" /usr/lib/tmpfiles.d/amethystora-greeter.conf

# ClamAV daemon listens on its socket and keeps retrying until freshclam has fetched the signatures
grep -q "^LocalSocket /run/clamd.scan/clamd.sock$" /etc/clamd.d/scan.conf
test -f /usr/lib/systemd/system/clamd@.service.d/10-amethystora.conf

# Security keys: pam_u2f ahead of the password for login (greetd), sudo and polkit. The DMS greeter only
# offers the key when it finds pam_u2f through /etc/pam.d/greetd. pam_u2f ignores its config file (and so
# the fixed origin keys are registered with) before 1.4.0, or when it is not root-owned or is writable.
grep -qE "^auth\s+sufficient\s+pam_u2f\.so" /etc/pam.d/system-auth
grep -qE "^auth\s+substack\s+system-auth" /etc/pam.d/greetd
grep -q "^origin = pam://amethystora$" /etc/security/pam_u2f.conf
[[ "$(stat -c '%U %a' /etc/security/pam_u2f.conf)" == "root 644" ]]
[[ "$(printf '%s\n' 1.4.0 "$(rpm -q --queryformat '%{VERSION}' pam-u2f)" | sort -V | head -n1)" == 1.4.0 ]]

# DisplayLink: evdi built for the image kernel, and no module signing key left behind by the build
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
modinfo "/usr/lib/modules/${KERNEL_VERSION}/extra/evdi/evdi.ko.xz" >/dev/null
test -f /usr/lib/udev/rules.d/99-displaylink.rules
find /etc/pki/akmods/private -type f 2>/dev/null | grep -q . && false

# Make sure this garbage never makes it to an image
test -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service && false

IMPORTANT_PACKAGES=(
    brave-browser
    clamav
    clamav-freshclam
    clamd
    displaylink
    distrobox
    dotnet-sdk-10.0
    fish
    flatpak
    hyprland
    pam-u2f
    pamu2fcfg
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
    akmod-evdi
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
    clamd@scan.service
    greetd.service
    rpm-ostree-countme.timer
    tailscaled.service
    amethystora-system-setup.service
    uupd.timer
  )

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
