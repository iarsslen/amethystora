#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Setup Systemd
# systemctl --global enable bazaar.service
systemctl --global enable podman-auto-update.timer
systemctl --global enable amethystora-user-setup.service
# Says at login what the scheduled scans found while nobody was logged in, which would otherwise sit
# in a log file until somebody thought to look
systemctl --global enable amethystora-security-alert.service
systemctl enable brew-setup.service
systemctl enable clamav-freshclam.service
systemctl enable clamd@scan.service
systemctl enable dconf-update.service
# Blocks addresses that fail to log in too often (08-hardening.sh, /etc/fail2ban/jail.d/10-amethystora.conf)
systemctl enable fail2ban.service
systemctl enable amethystora-flatpak-remotes.service
# input-remapper is installed but not enabled: it runs as root and reads every key pressed on every
# input device, which is a keylogger by any other name and is wanted only by people who remap keys.
# `ujust setup-input-remapper` turns it on for them.
systemctl disable input-remapper.service
systemctl enable rpm-ostree-countme.service
systemctl enable tailscaled.service
# NordVPN starts at boot, as its installer sets it up, so that auto-connect and the kill switch hold
# before anyone logs in. nordvpnd.service pulls in nordvpnd-killswitch.service itself.
systemctl enable nordvpnd.socket
systemctl enable nordvpnd.service
systemctl enable amethystora-system-setup.service
# Keeps updates signature-checked (/usr/libexec/amethystora-signed-updates)
systemctl enable amethystora-signed-updates.service

# Audit watches on the paths that would have to change for something to survive a reboot
# (/etc/audit/rules.d/60-amethystora.rules, plus the per-home ones this service generates)
systemctl enable auditd.service
systemctl enable amethystora-audit-rules.service

# Weekly ClamAV scan of the home and temporary directories, monthly Lynis audit of the settings.
# Both only report; neither deletes, quarantines or changes anything.
systemctl enable amethystora-clamav-scan.timer
systemctl enable amethystora-lynis-audit.timer

systemctl enable flatpak-preinstall.service

# Updater
systemctl enable uupd.timer

#disable the old rpm-ostreed-automatic.timer
systemctl disable rpm-ostreed-automatic.timer

# Hide Desktop Files. Hidden removes mime associations
for file in fish htop nvtop; do
    if [[ -f "/usr/share/applications/$file.desktop" ]]; then
        sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/"$file".desktop
    fi
done

#Add the Flathub Flatpak remote and remove the Fedora Flatpak remote
flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
systemctl disable flatpak-add-fedora-repos.service

# NOTE: With isolated COPR installation, most repos are never enabled globally.
# We only need to clean up repos that were enabled during the build process.

# Disable third-party repos
for repo in negativo17-fedora-multimedia tailscale brave-browser nordvpn fedora-cisco-openh264; do
    if [[ -f "/etc/yum.repos.d/${repo}.repo" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "/etc/yum.repos.d/${repo}.repo"
    fi
done

# Disable all COPR repos (should already be disabled by helpers, but ensure)
for i in /etc/yum.repos.d/_copr:*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Disable RPM Fusion repos
for i in /etc/yum.repos.d/rpmfusion-*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Disable fedora-coreos-pool if it exists
if [ -f /etc/yum.repos.d/fedora-coreos-pool.repo ]; then
    sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/fedora-coreos-pool.repo
fi

echo "::endgroup::"
