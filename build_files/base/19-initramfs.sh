#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -oue pipefail

KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

# Modules built into the initramfs. tpm2-tss is what lets systemd-cryptsetup ask the TPM for the disk
# key during boot; without it `ujust setup-disk-unlock` would enrol a key the boot never reaches and
# the machine would fall back to the passphrase every time. Added only when dracut has the module, so
# a dracut that drops or renames it fails the disk unlock rather than the whole build.
DRACUT_MODULES=(ostree)
if dracut --list-modules 2>/dev/null | grep -qx tpm2-tss; then
    DRACUT_MODULES+=(tpm2-tss)
else
    echo "::warning::dracut has no tpm2-tss module, TPM disk unlock will not work"
fi

export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v \
    --add "${DRACUT_MODULES[*]}" -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

echo "::endgroup::"
