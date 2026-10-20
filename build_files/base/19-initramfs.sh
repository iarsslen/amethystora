#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -oue pipefail

KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

# Modules built into the initramfs. tpm2-tss is what lets systemd-cryptsetup ask the TPM for the disk
# key during boot; without it `ame security disk-unlock` would enrol a key the boot never reaches and
# the machine would fall back to the passphrase every time. Added only when dracut has the module, so
# a dracut that drops or renames it fails the disk unlock rather than the whole build.
DRACUT_MODULES=(ostree)
if dracut --list-modules 2>/dev/null | grep -x tpm2-tss >/dev/null; then
    DRACUT_MODULES+=(tpm2-tss)
else
    echo "::warning::dracut has no tpm2-tss module, TPM disk unlock will not work"
fi

# The initramfs is the same, byte for byte, whenever what goes into it is: then an update that leaves it, the
# kernel and its arguments alone can be finished with a soft reboot (amethystora-soft-reboot), which bootc
# offers only then. Two things dracut would copy in change with every build without changing how the machine
# starts, so it is shown the image without them: os-release, which it copies as initrd-release, here without
# the build's version and commit; and the out-of-tree drivers modules-load.d loads at every start
# (v4l2loopback), which akmods builds anew for every image and which nothing needs before the system is
# mounted, where they still load. NVIDIA's driver stays: its own dracut configuration forces it in.
HIDDEN="$(mktemp -d)"
mv /etc/os-release "${HIDDEN}/os-release"
(
    # shellcheck source=/dev/null
    . /usr/lib/os-release
    grep -Ev '^(VERSION|PRETTY_NAME|OSTREE_VERSION|IMAGE_VERSION|BUILD_ID)=' /usr/lib/os-release
    echo "VERSION=\"${VERSION_ID}\""
    echo "PRETTY_NAME=\"${NAME} ${VERSION_ID}\""
) >/etc/os-release
for conf in /usr/lib/modules-load.d/*.conf; do
    while read -r module _; do
        [[ -n "${module}" && "${module}" != [\#\;]* ]] || continue
        if [[ "$(modinfo -k "$QUALIFIED_KERNEL" -F filename "${module}" 2>/dev/null)" =~ /lib/modules/[^/]+/(extra|updates)/ ]]; then
            mv "${conf}" "${HIDDEN}/"
            break
        fi
    done <"${conf}"
done

export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v \
    --add "${DRACUT_MODULES[*]}" -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

mv -f "${HIDDEN}/os-release" /etc/os-release
find "${HIDDEN}" -name '*.conf' -exec mv -t /usr/lib/modules-load.d/ {} +
rmdir "${HIDDEN}"

echo "::endgroup::"
