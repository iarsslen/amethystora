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
    audit
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
    kitty
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
    tpm2-tools
    usbguard
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

# Kept out of the weekly scan (amethystora-clamav-scan.timer). clamdscan takes its exclusions from the
# daemon's own configuration rather than from the command line, so they have to be set here. These are
# the kernel's virtual filesystems, the two content-addressed stores whose files are verified by their
# checksums and replaced whole, and the caches, which are large, rewritten constantly and rebuilt on
# demand. Everything a user writes stays in the scan, Flatpak application data included.
tee -a /etc/clamd.d/scan.conf >/dev/null <<'CLAMD'

# Amethystora: directories left out of the weekly scan (/usr/libexec/amethystora-clamav-scan)
ExcludePath ^/proc/
ExcludePath ^/sys/
ExcludePath ^/dev/
ExcludePath ^/run/
ExcludePath ^/var/lib/flatpak/
ExcludePath ^/var/lib/containers/
ExcludePath ^/var/home/[^/]+/\.cache/
ExcludePath ^/var/home/[^/]+/\.var/app/[^/]+/cache/
ExcludePath ^/var/home/[^/]+/\.local/share/containers/
CLAMD
grep -q "^ExcludePath \^/proc/$" /etc/clamd.d/scan.conf

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

# The AI agents amethystora-agent opens, in every image. Whether they are offered is the user's choice
# (ujust toggle-agentic); the CLIs themselves do nothing until someone runs them and signs in.
#
# Claude Code. Anthropic publishes a signed dnf repository for Fedora, and that is the install method
# that suits an image: the native installer and the npm package both leave a binary in the user's home
# that updates itself in the background, which on a machine where the whole system is replaced at once
# means one tool quietly drifting away from the image it came with. From the rpm it moves when the
# image does, like everything else here, and a package install does not auto-update itself.
#
# The stable channel is a release about a week old with the ones that turned out badly skipped. That
# is the right trade here, where a regression reaches every machine at the next reboot rather than
# only the person who chose to run an update.
#
# Signed with the Claude Code release key, fingerprint
# 31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE, which is what gpgcheck below verifies against.
tee /etc/yum.repos.d/claude-code.repo <<'EOF'
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://downloads.claude.ai/keys/claude-code.asc
EOF
sed -i "s/enabled=.*/enabled=0/g" /etc/yum.repos.d/claude-code.repo
dnf -y install --enablerepo=claude-code \
    claude-code

# opencode. There is no rpm of the CLI, so the release binary goes into /usr/bin, pinned by version
# and checksum for the same reason as Claude Code above: it moves when the image does. Renovate bumps
# both (.github/renovate.json5). Its self-update has nowhere to write under a read-only /usr.
OPENCODE_VERSION="v1.18.31"
OPENCODE_SHA256="e9312be75ed803b7415fc2aeabda1f4fe938912a39673762dc0c38c0e11ebde4"
ghcurl "https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
    --fail --retry 3 -o /tmp/opencode.tar.gz
echo "${OPENCODE_SHA256}  /tmp/opencode.tar.gz" | sha256sum -c -
tar -xzf /tmp/opencode.tar.gz -C /tmp opencode
install -Dm0755 /tmp/opencode /usr/bin/opencode
rm -f /tmp/opencode /tmp/opencode.tar.gz

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
