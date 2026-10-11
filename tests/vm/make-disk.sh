#!/usr/bin/bash
# make-disk.sh IMAGE DISK [SIZE]: installs IMAGE with `bootc install to-disk` onto /vm/disks/DISK.qcow2, the
# disk the lab's VMs start from (each VM writes to an overlay of its own), and writes DISK.vars.json, the
# firmware variables its VMs start with: Secure Boot on with Microsoft's keys, and the image's own
# certificates (/usr/share/amethystora/secure-boot) in shim's MOK list, as on a machine whose owner enrolled
# them. Runs in the lab container. An image named localhost/... is one built there, and is not pulled.
set -euo pipefail

IMAGE="$1"
DISK="$2"
SIZE="${3:-64G}"
DISKS=/vm/disks
SHIM_GUID=605dab50-e046-4300-abb6-3dd810dd8b23
[[ "${DISK}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "make-disk: a disk's name is lowercase letters, digits, . _ -" >&2; exit 2; }

mkdir -p "${DISKS}"
[[ "${IMAGE}" == localhost/* ]] || podman pull "${IMAGE}"
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

certs="$(mktemp -d)"
trap 'rm -rf "${certs}"' EXIT
podman run --rm -v "${certs}:/out" --entrypoint sh "${IMAGE}" -c 'cp /usr/share/amethystora/secure-boot/*.der /out/ 2>/dev/null || true'
mok=()
for cert in "${certs}"/*.der; do
    [[ -e "${cert}" ]] && mok+=(--add-mok "${SHIM_GUID}" "${cert}")
done
virt-fw-vars --input /usr/share/edk2/ovmf/OVMF_VARS.secboot.fd "${mok[@]}" --output-json "${DISKS}/${DISK}.vars.json.new"

mv "${DISKS}/${DISK}.vars.json.new" "${DISKS}/${DISK}.vars.json"
mv "${DISKS}/${DISK}.qcow2.new" "${DISKS}/${DISK}.qcow2"
podman image inspect --format '{{.Digest}}' "${IMAGE}" >"${DISKS}/${DISK}.digest"
echo "make-disk: ${DISKS}/${DISK}.qcow2 from ${IMAGE}@$(cat "${DISKS}/${DISK}.digest"), $(( ${#mok[@]} / 3 )) certificate(s) in MokList"
