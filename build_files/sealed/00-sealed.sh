#!/usr/bin/bash
# Makes a built image ready to be sealed (Containerfile.sealed): what only an ostree deployment uses
# goes, systemd-boot comes in, and the initramfs is rebuilt to mount the composefs image the UKI's
# kernel command line names. After Fedora's sealed test images
# (https://github.com/travier/fedora-atomic-desktops-sealed, CC0-1.0).

echo "::group:: ===$(basename "$0")==="

set -xeuo pipefail

# The install configuration (systemd-boot, btrfs), the kernel arguments the UKI carries, the initramfs's
# modules, the polkit rule for amethystora-deployments, and /usr/share/amethystora/sealed, which the
# scripts that act differently on a sealed machine test for
rsync -rvK /ctx/system_files/sealed/ /

# rpm-ostree reads ostree deployments only, and a sealed machine has none, so its status, kargs and
# rebase would all fail there: bootc does each of them instead. Its units are disabled first, so that no
# enabled unit is left naming a file that is gone.
for unit in rpm-ostree-countme.service rpm-ostree-countme.timer rpm-ostreed-automatic.timer; do
    systemctl disable "${unit}" 2>/dev/null || true
done
REMOVE=()
for package in rpm-ostree rpm-ostree-libs gnome-software-rpm-ostree; do
    rpm -q "${package}" >/dev/null && REMOVE+=("${package}")
done
if ((${#REMOVE[@]})); then
    dnf -y remove --setopt=clean_requirements_on_remove=False "${REMOVE[@]}"
fi
rm -f /etc/rpm-ostreed.conf

# bootupd installs GRUB and shim only, and bootc installs systemd-boot only when bootupd is absent.
# GRUB goes with it: the boot loader is systemd-boot, loaded by shim, which stays for the installer to
# put on the ESP (/usr/lib/efi/shim)
if rpm -q bootupd >/dev/null; then
    rpm -e bootupd
fi
rm -rf /usr/lib/bootupd /usr/lib/ostree-boot
readarray -t GRUB < <(rpm -qa --queryformat '%{NAME}\n' 'grub2*')
if ((${#GRUB[@]})); then
    rpm -e --nodeps "${GRUB[@]}"
fi
dnf -y install systemd-boot-unsigned

# The stream this image follows is the sealed one: `ame system rebase`, the GPU check and the setup
# manifest read it here
IMAGE_INFO=/usr/share/amethystora/image-info.json
TAG="$(jq -r '."image-tag"' "${IMAGE_INFO}")"
jq --arg tag "${TAG%-sealed}-sealed" '."image-tag" = $tag' "${IMAGE_INFO}" >/tmp/image-info.json
cat /tmp/image-info.json >"${IMAGE_INFO}"
rm /tmp/image-info.json

# The certificate the UKI and systemd-boot are signed with, where `ame security secure-boot` and the
# security report find the image's Secure Boot keys, and where the installer reads it to enrol it
install -d -m0755 /usr/share/amethystora/secure-boot
openssl x509 -in /run/secrets/SECUREBOOT_CERT -outform DER -out /usr/share/amethystora/secure-boot/amethystora-uki.der
chmod 0644 /usr/share/amethystora/secure-boot/amethystora-uki.der

# The initramfs, with bootc's module, which mounts the composefs image the kernel command line names and
# refuses one whose digest differs, and with tpm2-tss, as 19-initramfs.sh has it, for `ame security
# disk-unlock`. /etc/passwd and /etc/group go in as Fedora's sealed images put them.
readarray -t KERNELS < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n')
if [[ ${#KERNELS[@]} -ne 1 ]]; then
    echo "::error::A sealed image carries one kernel, and this one has ${#KERNELS[@]}: ${KERNELS[*]}"
    exit 1
fi
KERNEL="${KERNELS[0]}"
DRACUT_MODULES=(bootc)
if dracut --list-modules 2>/dev/null | grep -x tpm2-tss >/dev/null; then
    DRACUT_MODULES+=(tpm2-tss)
else
    echo "::warning::dracut has no tpm2-tss module, TPM disk unlock will not work"
fi
export DRACUT_NO_XATTR=1
dracut --no-hostonly --kver "${KERNEL}" --reproducible -v --add "${DRACUT_MODULES[*]}" \
    --install "/etc/passwd /etc/group" -f "/usr/lib/modules/${KERNEL}/initramfs.img"

# The packages changed, so the list of where their source is is written again (20-tests.sh checks it
# against the image's packages, and 20-tests-sealed.sh against this one's)
/ctx/build_files/shared/source-manifest.sh

dnf clean all
rm -rf /var/log/dnf5* /tmp/*
# bootc's lint wants /boot empty, as clean-stage.sh leaves it
rm -rf /boot && mkdir -p /boot

echo "::endgroup::"
