#!/usr/bin/bash
# Turns Amethystora into the live system of the live ISO (iso/live/Containerfile). The live session
# runs from the squashed image in memory; the system it installs is the published image itself, a copy
# of which this puts in the live system so that installing needs no network, and which the installed
# machine then follows from the registry.
#
# What it adds is Fedora's: the live boot (dracut-live), the live session (livesys-scripts), and the
# installer (anaconda-live with its web interface). Nothing from anywhere else, but the sealed images'
# own installer (amethystora-install-sealed), which downloads what it installs.

set -xeuo pipefail

: "${BASE_IMAGE:?the image the ISO installs}"
LIVE=/src/live

mkdir -p "$(realpath /root)"

# --- The system to install ----------------------------------------------------------------------------

# Into the read-only image store that containers-common lists for root (additionalimagestores), where
# the installer's ostreecontainer finds it by name. The storage settings are only for this pull.
cat >/etc/containers/storage.conf <<'EOF'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/usr/lib/containers/storage"
EOF
podman pull "${BASE_IMAGE}"
rm -f /etc/containers/storage.conf

# --- The live boot and the installer ------------------------------------------------------------------

dnf -y install dracut-live livesys-scripts anaconda-live anaconda-webui \
    libblockdev-btrfs libblockdev-lvm libblockdev-dm grub2-efi-x64-cdboot \
    cryptsetup dosfstools efibootmgr mokutil

# An initramfs that can find the squashed system on the stick and lay a writable layer over it
kernel="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -n 1)"
DRACUT_NO_XATTR=1 dracut --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

# Fedora's GNOME live session: logged in as liveuser, with the installer in the dash
sed -i 's/^livesys_session=.*/livesys_session=gnome/' /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

# The ISO boots through the image's own shim and GRUB, signed by Fedora, so Secure Boot can stay on
mkdir -p /boot/efi
cp -a /usr/lib/efi/*/*/EFI /boot/efi/
cp /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi

rm -f /etc/localtime
systemd-firstboot --timezone UTC

# The live session writes to memory, and what the installer unpacks goes through /var/tmp first
install -Dpm0644 "${LIVE}/var-tmp.mount" /usr/lib/systemd/system/var-tmp.mount
systemctl enable var-tmp.mount

# --- The installer's look and what it installs -------------------------------------------------------

# The same look as the installer ISO's (iso/product), laid over Anaconda as that ISO's product.img is
cp -a /src/product/. /
# ...and a profile for this os-release, whose ID is the image's own rather than the installer ISO's
install -Dpm0644 "${LIVE}/amethystora-live.conf" /etc/anaconda/profile.d/amethystora-live.conf
# What Anaconda installs, and where it points the installed machine
sed "s|@IMAGE@|${BASE_IMAGE}|g" "${LIVE}/installer.ks" >/usr/share/anaconda/interactive-defaults.ks
# ...which takes its updates signature-checked from the first one
grep -q -- "--enforce-container-sigpolicy" /usr/share/anaconda/interactive-defaults.ks
if grep "bootc switch" /usr/share/anaconda/interactive-defaults.ks | grep -v -- "--enforce-container-sigpolicy"; then
    echo "installer.ks switches the installed machine without signature checking" >&2
    exit 1
fi

# The sealed images (:stable-sealed), which Anaconda cannot install yet, have an installer of their own:
# a whole disk, the image downloaded from the registry, shim placed in front of systemd-boot
install -Dpm0755 "${LIVE}/amethystora-install-sealed" /usr/bin/amethystora-install-sealed
install -Dpm0644 "${LIVE}/amethystora-install-sealed.desktop" \
    /usr/share/applications/amethystora-install-sealed.desktop

# Anaconda's welcome window for the live session names Fedora, as its desktop entries do: this is a
# system built on Fedora, not Fedora, and its trademark guidelines ask for its name to stay off it
{ grep -rlI --null 'Fedora' /usr/share/anaconda/gnome /usr/share/applications/liveinst.desktop 2>/dev/null || true; } |
    xargs -0 -r sed -i 's/\bFedora\b/Amethystora/g'

# --- The live session --------------------------------------------------------------------------------

# Nothing that would download, scan or set up a machine for good runs in a session that ends at
# shutdown: the apps come with the first boot of the installed system
systemctl disable uupd.timer flatpak-preinstall.service fwupd-refresh.timer amethystora-gpu-check.timer \
    amethystora-signed-updates.service amethystora-clamav-scan.timer amethystora-lynis-audit.timer \
    amethystora-security-watch.timer clamav-freshclam.service clamd@scan.service rpm-ostree-countme.service \
    brew-setup.service
systemctl --global disable amethystora-pkg-upgrade.timer amethystora-update-alert.service \
    amethystora-security-alert.service

# What Titanoboa makes the ISO from (the container-native ISO contract): its label and boot menu
install -Dpm0644 "${LIVE}/iso.yaml" /usr/lib/bootc-image-builder/iso.yaml

dnf clean all
