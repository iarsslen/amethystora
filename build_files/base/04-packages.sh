#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# All DNF-related operations should be done here whenever possible

# shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# NOTE:
# Packages are split into FEDORA_PACKAGES and COPR_PACKAGES to prevent
# malicious COPRs from injecting fake versions of Fedora packages.
# Fedora packages are installed first in bulk (safe).
# COPR packages are installed individually with isolated enablement.

# Base packages from Fedora repos - common to all versions
FEDORA_PACKAGES=(
    adcli
    adw-gtk3-theme
    adwaita-fonts-all
    autofs
    bash-color-prompt
    bcache-tools
    bootc
    borgbackup
    clamav
    clamav-freshclam
    clamd
    containerd
    cryfs
    davfs2
    ddcutil
    dotnet-sdk-10.0
    evtest
    fail2ban-firewalld
    fail2ban-selinux
    fail2ban-server
    fastfetch
    firewall-config
    fish
    foo2zjs
    fuse-encfs
    gcc
    gcc-c++
    git-credential-libsecret
    glow
    gnome-tweaks
    # grub2-mkfont, which 06-branding.sh uses to build the boot menu font
    grub2-tools-extra
    gum
    hplip
    ibus-mozc
    ifuse
    igt-gpu-tools
    input-remapper
    iwd
    jetbrains-mono-fonts-all
    just
    krb5-workstation
    libappindicator-gtk3
    libayatana-appindicator-gtk3
    libgda
    libgda-sqlite
    libimobiledevice
    libratbag-ratbagd
    libxcrypt-compat
    lm_sensors
    lynis
    make
    mesa-libGLU
    mozc
    nautilus-gsconnect
    oddjob-mkhomedir
    opendyslexic-fonts
    openssh-askpass
    pam-u2f
    pamu2fcfg
    plymouth-plugin-label
    plymouth-plugin-script
    powerstat
    powertop
    printer-driver-brlaser
    pulseaudio-utils
    python3-pip
    python3-pygit2
    rclone
    restic
    rsms-inter-fonts
    samba
    samba-dcerpc
    samba-ldb-ldap-modules
    samba-winbind-clients
    samba-winbind-modules
    setools-console
    sssd-nfs-idmap
    switcheroo-control
    tmux
    usbip
    usbmuxd
    waypipe
    wireguard-tools
    wl-clipboard
    xdg-terminal-exec
    xprop
    zenity
    zsh
)
# Version-specific Fedora package additions
case "$FEDORA_MAJOR_VERSION" in
    42)
        FEDORA_PACKAGES+=(
            evolution-ews-core
            uld
        )
        ;;
    43)
        FEDORA_PACKAGES+=(
            evolution-ews-core
            gnupg2-scdaemon
        )
        ;;
    44)
        FEDORA_PACKAGES+=(
            gnupg2-scdaemon
        )
        ;;
esac

# Install all Fedora packages (bulk - safe from COPR injection)
echo "Installing ${#FEDORA_PACKAGES[@]} packages from Fedora repos..."
dnf -y install "${FEDORA_PACKAGES[@]}"

# ClamAV daemon (clamd@scan.service): listen on its local socket so clamdscan and ClamUI can use it,
# and let SELinux allow it to read files anywhere on the system
sed -i 's|^#LocalSocket |LocalSocket |' /etc/clamd.d/scan.conf
grep -q "^LocalSocket /run/clamd.scan/clamd.sock$" /etc/clamd.d/scan.conf
semanage boolean -m --on antivirus_can_scan_system

# FIDO2 security keys (YubiKey, Thetis, and their fingerprint models) log in, unlock and approve sudo/polkit in
# place of the password, once registered with `ujust setup-security-key`. Users without a key are not affected.
authselect enable-feature with-pam-u2f

dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf config-manager setopt tailscale-stable.enabled=0
dnf -y install --enablerepo='tailscale-stable' tailscale

# Brave is the browser, in place of Firefox.
# Its RPM installs to /opt, which is /var/opt on a booted system: outside the image, so never updated.
# Move it under /usr/lib; /usr/lib/tmpfiles.d/brave-browser.conf links it back into /var/opt at boot.
dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
dnf config-manager setopt brave-browser.enabled=0
mkdir -p /var/opt
dnf -y install --enablerepo='brave-browser' brave-browser
mv /opt/brave.com /usr/lib/brave.com
# Its daily cron job re-adds and re-enables the repo, which the image does not use
rm -f /etc/cron.daily/brave-browser

# Firefox: drop the Flatpak from the default app list and its now unused settings
sed -i '/^flatpak "org\.mozilla\.firefox"/d' /usr/share/ublue-os/homebrew/system-flatpaks.Brewfile
rm -rf /usr/share/ublue-os/firefox-config
sed -i '$a\' /etc/xdg/mimeapps.list
cat >>/etc/xdg/mimeapps.list <<'EOF'
application/xhtml+xml=brave-browser.desktop;com.brave.Browser.desktop;
text/html=brave-browser.desktop;com.brave.Browser.desktop;
x-scheme-handler/about=brave-browser.desktop;com.brave.Browser.desktop;
x-scheme-handler/http=brave-browser.desktop;com.brave.Browser.desktop;
x-scheme-handler/https=brave-browser.desktop;com.brave.Browser.desktop;
x-scheme-handler/unknown=brave-browser.desktop;com.brave.Browser.desktop;
EOF

# From che/nerd-fonts
copr_install_isolated "che/nerd-fonts" "nerd-fonts"

# From ublue-os/packages
copr_install_isolated "ublue-os/packages" "uupd"
copr_install_isolated "ublue-os/packages" "gnome-rounded-blur"

# Version-specific COPR packages
# case "$FEDORA_MAJOR_VERSION" in
#    42)
        # bazaar and uupd from ublue-os/packages
        # copr_install_isolated "ublue-os/packages" "bazaar" "uupd"
        # ;;
    # 43)
        # bazaar from ublue-os/packages
        # copr_install_isolated "ublue-os/packages" "bazaar"
        # ;;
# esac

# Packages to exclude - common to all versions
EXCLUDED_PACKAGES=(
    cosign
    fedora-bookmarks
    fedora-chromium-config
    fedora-chromium-config-gnome
    firefox
    firefox-langpacks
    gnome-extensions-app
    gnome-shell-extension-background-logo
    gnome-software
    gnome-software-rpm-ostree
    gnome-terminal-nautilus
    podman-docker
    yelp
)

# Remove excluded packages if they are installed
if [[ "${#EXCLUDED_PACKAGES[@]}" -gt 0 ]]; then
    readarray -t INSTALLED_EXCLUDED < <(rpm -qa --queryformat='%{NAME}\n' "${EXCLUDED_PACKAGES[@]}" 2>/dev/null || true)
    if [[ "${#INSTALLED_EXCLUDED[@]}" -gt 0 ]]; then
        dnf -y remove "${INSTALLED_EXCLUDED[@]}"
    else
        echo "No excluded packages found to remove."
    fi
fi

## Pins and Overrides
## Use this section to pin packages in order to avoid regressions
# Remember to leave a note with rationale/link to issue for each pin!
#
# Example:
#if [ "$FEDORA_MAJOR_VERSION" -eq "41" ]; then
#    Workaround pkcs11-provider regression, see issue #1943
#    rpm-ostree override replace https://bodhi.fedoraproject.org/updates/FEDORA-2024-dd2e9fb225
#fi

echo "::endgroup::"
