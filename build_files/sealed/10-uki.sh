#!/usr/bin/bash
# Builds the sealed image's UKI (Containerfile.sealed): the kernel, the initramfs 00-sealed.sh built, and
# a kernel command line of the composefs digest of the rechunked tree (/run/target) followed by the
# arguments in its kargs.d, all signed with the Secure Boot key. `bootc container ukify` computes the
# digest with the image's own bootc, the one that checks it at every boot.

echo "::group:: ===$(basename "$0")==="

set -xeuo pipefail

readarray -t KERNELS < <(find /run/kernel -mindepth 1 -maxdepth 1 -printf '%f\n')
[[ ${#KERNELS[@]} -eq 1 ]]
KERNEL="${KERNELS[0]}"

mkdir -p /out
bootc container ukify --rootfs /run/target --kernel-dir "/run/kernel/${KERNEL}" -- \
    --signtool sbsign \
    --secureboot-private-key /run/secrets/SECUREBOOT_KEY \
    --secureboot-certificate /run/secrets/SECUREBOOT_CERT \
    --output "/out/${KERNEL}.efi"

echo "::endgroup::"
