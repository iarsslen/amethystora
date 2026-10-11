#!/usr/bin/bash
# make-disk.sh IMAGE DISK [SIZE]: installs IMAGE with `bootc install to-disk` onto /vm/disks/DISK.qcow2, the
# disk the lab's VMs start from (each VM writes to an overlay of its own). Runs in the lab container, which
# the MCP server's disk_build calls it in.
set -euo pipefail

IMAGE="$1"
DISK="$2"
SIZE="${3:-64G}"
DISKS=/vm/disks
[[ "${DISK}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "make-disk: a disk's name is lowercase letters, digits, . _ -" >&2; exit 2; }

mkdir -p "${DISKS}"
podman pull "${IMAGE}"
raw="${DISKS}/${DISK}.raw"
rm -f "${raw}"
truncate -s "${SIZE}" "${raw}"
# --generic-image: no firmware boot entry, and nothing of this machine's, as for a disk image to copy around.
# The image names no filesystem for bootc; the installer ISO's is btrfs.
podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
    -v /dev:/dev -v /run/udev:/run/udev -v /var/lib/containers:/var/lib/containers -v "${DISKS}:/output" \
    "${IMAGE}" bootc install to-disk --via-loopback --generic-image --filesystem btrfs --wipe "/output/${DISK}.raw"
qemu-img convert -O qcow2 "${raw}" "${DISKS}/${DISK}.qcow2.new"
rm -f "${raw}"
mv "${DISKS}/${DISK}.qcow2.new" "${DISKS}/${DISK}.qcow2"
podman image inspect --format '{{.Digest}}' "${IMAGE}" >"${DISKS}/${DISK}.digest"
echo "make-disk: ${DISKS}/${DISK}.qcow2 from ${IMAGE}@$(cat "${DISKS}/${DISK}.digest")"
