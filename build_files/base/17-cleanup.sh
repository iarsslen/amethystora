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
# Upgrades every account's amethystora-pkg containers once a day. It holds back the way uupd's automatic
# updates do, and does nothing for an account that has never made one.
systemctl --global enable amethystora-pkg-upgrade.timer
# Says at login when the machine started an older version than its default one, and opens System Updates
systemctl --global enable amethystora-update-alert.service
# With encrypted DNS on (ame security dns), offers to pause it on a network that wants a login first.
# It does not start while encrypted DNS is off.
systemctl --global enable amethystora-dns-portal.service
# Offers the image with NVIDIA's driver on a machine with an NVIDIA card, or the one without it on a
# machine without one, once, to whoever logs in first
systemctl enable amethystora-gpu-check.timer
# The pools of disks (ame system raid): an hourly health check that tells whoever is logged in, and a
# monthly scrub that repairs a damaged copy from a good one. Both are skipped on a machine with no pool
# and no btrfs over several disks; `ame system raid scrub off` turns the scrub off.
systemctl enable amethystora-raid-check.timer
systemctl enable amethystora-raid-scrub.timer
# amepkg is amethystora-pkg under a shorter name. Made here, because a link in system_files is one the
# build's rsync would skip.
ln -sf amethystora-pkg /usr/bin/amepkg
systemctl enable brew-setup.service
systemctl enable clamav-freshclam.service
systemctl enable clamd@scan.service
systemctl enable dconf-update.service
# Blocks addresses that fail to log in too often (08-hardening.sh, /etc/fail2ban/jail.d/10-amethystora.conf)
systemctl enable fail2ban.service
systemctl enable amethystora-flatpak-remotes.service
# input-remapper is installed but not enabled: it runs as root and reads every key pressed on every
# input device, which is a keylogger by any other name and is wanted only by people who remap keys.
# `ame security input-remapper` turns it on for them.
systemctl disable input-remapper.service
# The same for Android apps, whose container runs as root (ame apps android), and for the sched-ext CPU
# schedulers, which replace the kernel's own (ame system scheduler)
systemctl disable waydroid-container.service
systemctl disable scx_loader.service
systemctl enable rpm-ostree-countme.service
systemctl enable tailscaled.service
systemctl enable amethystora-system-setup.service
# Keeps updates signature-checked (/usr/libexec/amethystora-signed-updates)
systemctl enable amethystora-signed-updates.service

# Audit watches on the paths that would have to change for something to survive a reboot, which this
# service writes at every boot from /usr/share/amethystora/audit and for each home, for every key not
# switched off in /etc/amethystora/security.conf (AUDIT_LOG=off skips both units)
systemctl enable auditd.service
systemctl enable amethystora-audit-rules.service

# Weekly ClamAV scan of the home and temporary directories, monthly Lynis audit of the settings. What
# the scan finds is only reported unless ON_DETECTION in /etc/amethystora/security.conf says otherwise.
systemctl enable amethystora-clamav-scan.timer
systemctl enable amethystora-lynis-audit.timer
# The security watcher reads the audit log and the journal every 15 minutes (amethystora-security-watch)
systemctl enable amethystora-security-watch.timer
# Real-time watching and scanning. Enabled, but each checks REALTIME in /etc/amethystora/security.conf as
# it starts and is skipped while that is off, which is the default
systemctl enable amethystora-security-realtime.service
systemctl enable amethystora-clamav-onaccess.service
# Network protection and its daily rules, the same way: enabled, and skipped while NETWORK=off. The
# package's own unit sniffs one named interface and never blocks, so it stays off.
systemctl enable amethystora-ips.service
systemctl enable amethystora-ips-rules.timer
systemctl disable suricata.service

systemctl enable flatpak-preinstall.service

# Updater
systemctl enable uupd.timer

# Firmware: fwupd's daily look at LVFS for new firmware, which Fedora leaves to GNOME Software on its
# desktops. This image has no GNOME Software, so without it the Updates app and `fwupdmgr get-updates`
# would only ever know of the firmware there was when somebody last ran `fwupdmgr refresh`.
systemctl enable fwupd-refresh.timer

#disable the old rpm-ostreed-automatic.timer
systemctl disable rpm-ostreed-automatic.timer

# Hide Desktop Files. Hidden removes mime associations
for file in fish htop nvtop; do
    if [[ -f "/usr/share/applications/$file.desktop" ]]; then
        sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/"$file".desktop
    fi
done

#Add the Flathub Flatpak remote and remove the Fedora Flatpak remote. It is added from the .flatpakrepo
# the base image carries, which machines add it from too (flatpak-add-flathub-repos.service), once the
# key inside has been checked against Flathub's fingerprint, rather than from Flathub's server unchecked
# shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh
FLATHUB_REPO=/etc/flatpak/remotes.d/flathub.flatpakrepo
sed -n 's/^GPGKey=//p' "${FLATHUB_REPO}" | base64 -d >/tmp/flathub.gpg
[[ "$(key_fingerprints /tmp/flathub.gpg)" == 6E5C05D979C76DAF93C081354184DD4D907A7CAE ]]
flatpak remote-add --system --if-not-exists flathub "${FLATHUB_REPO}"
systemctl disable flatpak-add-fedora-repos.service

# NOTE: With isolated COPR installation, most repos are never enabled globally.
# We only need to clean up repos that were enabled during the build process.

# Disable third-party repos. fedora-multimedia is negativo17's, under the name the base image gives it;
# left on, it outranks Fedora's repositories for anything installed after this, here or by the user
for repo in fedora-multimedia negativo17-fedora-multimedia tailscale fedora-cisco-openh264; do
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
