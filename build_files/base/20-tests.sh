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

# Animated boot splash: the script theme, the images it loads, and both in the initramfs, which shows the
# splash up to and including the LUKS password prompt
[[ "$(plymouth-set-default-theme)" == "amethystora" ]]
rpm -q plymouth-plugin-script >/dev/null
test -f /usr/share/plymouth/themes/amethystora/amethystora.script
for image in nebula halo dust gem light shard-0 wordmark credit field dot; do
    test -f "/usr/share/plymouth/themes/amethystora/${image}.png"
done
INITRAMFS_FILES="$(lsinitrd /lib/modules/*/initramfs.img)"
grep -q "plymouth/script.so" <<<"${INITRAMFS_FILES}"
grep -q "themes/amethystora/amethystora.script" <<<"${INITRAMFS_FILES}"
# Boot and login text in Inter: fc-match falls back to another family when it is missing
[[ "$(fc-match -f '%{family[0]}' 'Inter')" == "Inter" ]]
grep -q "^Font=Inter " /usr/share/plymouth/themes/amethystora/amethystora.plymouth

# Amethystora wallpapers are the GNOME default
test -f /usr/share/backgrounds/amethystora/amethystora-l.png
test -f /usr/share/backgrounds/amethystora/amethystora-d.png
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri-dark)" == "'file:///usr/share/backgrounds/amethystora/amethystora-d.png'" ]]

# GNOME Shell extensions built from the git submodules (build-gnome-extensions.sh)
for extension in appindicatorsupport@rgcjonas.gmail.com blur-my-shell@aunetx caffeine@patapon.info \
    dash-to-dock@micxgx.gmail.com logomenu@aryan_k search-light@icedman.github.com; do
    test -f "/usr/share/gnome-shell/extensions/${extension}/metadata.json"
done
test -d /usr/share/gnome-shell/extensions/tmp && false

# ClamAV daemon listens on its socket and keeps retrying until freshclam has fetched the signatures
grep -q "^LocalSocket /run/clamd.scan/clamd.sock$" /etc/clamd.d/scan.conf
test -f /usr/lib/systemd/system/clamd@.service.d/10-amethystora.conf

# Security keys: pam_u2f ahead of the password for sudo and polkit. pam_u2f ignores its config file (and so
# the fixed origin keys are registered with) before 1.4.0, or when it is not root-owned or is writable.
grep -qE "^auth\s+sufficient\s+pam_u2f\.so" /etc/pam.d/system-auth
grep -q "^origin = pam://amethystora$" /etc/security/pam_u2f.conf
[[ "$(stat -c '%U %a' /etc/security/pam_u2f.conf)" == "root 644" ]]
[[ "$(printf '%s\n' 1.4.0 "$(rpm -q --queryformat '%{VERSION}' pam-u2f)" | sort -V | head -n1)" == 1.4.0 ]]

# Hardening (08-hardening.sh and its files in system_files)
# Updates must carry a valid signature from the key CI signs with
test -s /etc/pki/containers/amethystora.pub
jq -e '.transports.docker["ghcr.io/iarsslen"][0] == {"type": "sigstoreSigned",
    "keyPath": "/etc/pki/containers/amethystora.pub", "signedIdentity": {"type": "matchRepository"}}' \
    /etc/containers/policy.json
grep -q "use-sigstore-attachments: true" /etc/containers/registries.d/amethystora.yaml
test -x /usr/share/amethystora/system-setup.hooks.d/20-signed-updates.sh
# Kernel settings, arguments and blocked modules
grep -q "^kernel.kptr_restrict = 2$" /usr/lib/sysctl.d/60-amethystora-hardening.conf
grep -q '"slab_nomerge"' /usr/lib/bootc/kargs.d/10-amethystora-hardening.toml
modprobe --showconfig | grep -q "^install dccp /usr/bin/false$"
modprobe --showconfig | grep -q "^install firewire-core /usr/bin/false$"
# No passwordless root for users who are not at the machine, and no user-writable directory in root's
# sudo PATH, and no world-writable USB devices
grep -q "<allow_any>no</allow_any>" /usr/share/polkit-1/actions/*privileged.user.setup.policy
grep -E "^Defaults[[:space:]]+secure_path" /etc/sudoers | grep -q linuxbrew && false
if [[ -f /usr/lib/udev/rules.d/50-zsa.rules ]]; then
    grep -q 'MODE:="0666"' /usr/lib/udev/rules.d/50-zsa.rules && false
    grep -q 'TAG+="uaccess"' /usr/lib/udev/rules.d/50-zsa.rules
fi
# Firewall: the Amethystora zone, without Fedora Workstation's open port range
[[ "$(firewall-offline-cmd --get-default-zone)" == "amethystora" ]]
[[ -z "$(firewall-offline-cmd --zone=amethystora --list-ports)" ]]
firewall-offline-cmd --zone=trusted --query-interface=tailscale0
# Account lockout, and the SSH server's settings for when it is turned on
grep -qE "^auth\s+required\s+pam_faillock\.so\s+preauth" /etc/pam.d/system-auth
grep -q "^deny = 10$" /etc/security/faillock.conf
grep -q "^PermitRootLogin no$" /etc/ssh/sshd_config.d/40-amethystora-hardening.conf
grep -q "^Include /etc/ssh/sshd_config.d/\*.conf$" /etc/ssh/sshd_config

# DisplayLink: evdi built for the image kernel, and no module signing key left behind by the build
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
modinfo "/usr/lib/modules/${KERNEL_VERSION}/extra/evdi/evdi.ko.xz" >/dev/null
test -f /usr/lib/udev/rules.d/99-displaylink.rules
systemctl is-enabled displaylink.service
grep -q "^d /var/log/displaylink " /usr/lib/tmpfiles.d/displaylink.conf
find /etc/pki/akmods/private -type f 2>/dev/null | grep -q . && false
# ujust enroll-secure-boot-key enrolls both: the one evdi is signed with and the kernel's
test -f /etc/pki/akmods/certs/amethystora-modules.der
test -f /etc/pki/akmods/certs/akmods-amethystora.der

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
    gdm
    gnome-shell
    mutter
    pam-u2f
    pamu2fcfg
    pipewire
    ptyxis
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
    gdm.service
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
