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
    # Ransomware protection's snapshots of /var/home (ame security ransomware)
    btrfs-progs
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
    # fido2-token, fido2-cred and fido2-assert, through which the Notes app speaks to a security key
    # for its passkeys; libfido2 itself is already in the base image
    fido2-tools
    # The browser, in the image so that a machine has one before it is online. It ships as Fedora
    # builds it, but for Fedora's start page, taken out below: Mozilla lets Firefox be redistributed
    # only unaltered, so nothing here or in system_files adds a policy, an extension, a preference
    # or a home page to it
    firefox
    firefox-langpacks
    firewall-config
    fish
    foo2zjs
    fuse-encfs
    # gamemoded, which a game asks through the GameMode portal for the CPU's performance mode while it
    # runs: Steam and the rest from Flathub reach it from their sandbox (ame apps gaming)
    gamemode
    gcc
    gcc-c++
    # gettext and gettext.sh, through which the security report and the app permissions speak the
    # session's language (po/amethystora)
    gettext-runtime
    git-credential-libsecret
    glow
    gnome-tweaks
    # One-time codes for password logins over SSH, off until `ame security ssh-codes on`
    google-authenticator
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
    # Parental Controls' allowed hours at the text consoles and over SSH (08-hardening.sh)
    malcontent-pam
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
    # SSSD's back ends: Active Directory's, which a join through realmd needs (Settings' Enterprise Login,
    # `realm join`), FreeIPA's, and LDAP and Kerberos for directories set up by hand. /etc/realmd.conf keeps
    # the image's authselect features.
    sssd
    sssd-nfs-idmap
    # Network protection (amethystora-ips.service), off until `ame security settings network`
    suricata
    switcheroo-control
    tmux
    tpm2-tools
    usbguard
    usbip
    usbmuxd
    # Android apps in a container (ame apps android): off until set up, as its container service ships
    # disabled (17-cleanup.sh). Binder is built into Fedora's kernel, and the package brings its own
    # SELinux policy. The Android images are downloaded on the machine that asks for them.
    waydroid
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

# Suricata's account, made here before its package makes it. The package would take the next free ID
# from the top of the system range, and every account created after it in this build (clamscan,
# setroubleshoot, docker, libvirt, wireshark and more) would move down by one, leaving the files each
# owns on a machine that updates to the wrong account. 850 is far below where those are handed out.
systemd-sysusers --inline 'u suricata 850 "Suricata IDS" / -'

# Install all Fedora packages (bulk - safe from COPR injection)
echo "Installing ${#FEDORA_PACKAGES[@]} packages from Fedora repos..."
dnf -y install "${FEDORA_PACKAGES[@]}"

# Fedora's Firefox opens on start.fedoraproject.org and pins it on the new tab page. Those two lines of
# its preferences are deleted, which leaves Firefox's own home page; nothing is put in their place
sed -i '/start\.fedoraproject\.org/d' /usr/lib64/firefox/browser/defaults/preferences/firefox-redhat-default-prefs.js

# ClamAV daemon (clamd@scan.service): listen on its local socket so clamdscan and ClamUI can use it,
# and let SELinux allow it to read files anywhere on the system
sed -i 's|^#LocalSocket |LocalSocket |' /etc/clamd.d/scan.conf
grep -q "^LocalSocket /run/clamd.scan/clamd.sock$" /etc/clamd.d/scan.conf
semanage boolean -m --on antivirus_can_scan_system

# Kept out of the weekly scan (amethystora-clamav-scan.timer). clamdscan takes its exclusions from the
# daemon's own configuration rather than from the command line, so they have to be set here. These are
# the kernel's virtual filesystems, the two content-addressed stores whose files are verified by their
# checksums and replaced whole, and the caches, which are large, rewritten constantly and rebuilt on
# demand. Everything a user writes stays in the scan, Flatpak application data included. The snapshots
# of ransomware protection are read-only copies of what is scanned already, one for each of the last
# day's hours and the last two weeks' days.
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
ExcludePath ^/var/home/\.snapshots/

# Amethystora: real-time scanning, read by clamonacc (amethystora-clamav-onaccess.service), which runs
# only with REALTIME=on in /etc/amethystora/security.conf. Files closed in a home directory are scanned;
# root's own reads are not, or the weekly scan would have every file it opens scanned a second time.
OnAccessIncludePath /var/home
OnAccessExcludeRootUID yes
OnAccessExtraScanning yes
OnAccessPrevention no
CLAMD
grep -q "^ExcludePath \^/proc/$" /etc/clamd.d/scan.conf
grep -q "^OnAccessIncludePath /var/home$" /etc/clamd.d/scan.conf

# FIDO2 security keys (YubiKey, Thetis, and their fingerprint models) log in, unlock and approve sudo/polkit in
# place of the password, once registered with `ame security key`. Users without a key are not affected.
authselect enable-feature with-pam-u2f

dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf config-manager setopt tailscale-stable.enabled=0
dnf -y install --enablerepo='tailscale-stable' tailscale

# The AI agents amethystora-agent offers are deliberately not installed here. They release far more
# often than the image, so it installs them into each user's home with their makers' own installers,
# where they update on a schedule the user controls.

# From che/nerd-fonts
copr_install_isolated "che/nerd-fonts" "nerd-fonts"

# From ublue-os/packages
copr_install_isolated "ublue-os/packages" "uupd"
copr_install_isolated "ublue-os/packages" "gnome-rounded-blur"

# sched-ext CPU schedulers and their loader (ame system scheduler), from CachyOS's COPR, which Bazzite uses
# too: Fedora's own scx packages are two years older than the kernel interface they would load into.
# scx_loader.service ships disabled (17-cleanup.sh), so the kernel's own scheduler runs until somebody
# picks another. GPL-2.0, so source-manifest.sh fetches the source packages into the image.
copr_install_isolated "bieszczaders/kernel-cachyos-addons" "scx-scheds" "scx-tools"

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
