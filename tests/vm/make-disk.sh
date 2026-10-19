#!/usr/bin/bash
# make-disk.sh IMAGE DISK [SIZE] [--installer[=PASSPHRASE]]: installs IMAGE onto /vm/disks/DISK.qcow2, the
# disk the lab's VMs start from (each VM writes to an overlay of its own), and writes DISK.vars.json, the
# firmware variables its VMs start with: Secure Boot on with Microsoft's keys, and the image's own
# certificates (/usr/share/amethystora/secure-boot) in shim's MOK list, as on a machine whose owner enrolled
# them. Runs in the lab container. An image named localhost/... is one built there, and is not pulled.
#
# Without --installer, `bootc install to-disk`: the root btrfs holds /boot. With it, the installer's own
# layout, which the system mirror (ame system raid mirror DISK) needs: an ESP, an ext4 /boot, and btrfs with
# the subvolumes root and home, on LUKS2 opened with PASSPHRASE when one is given, written with
# `bootc install to-filesystem` and the fstab and crypttab lines Anaconda writes. Its kernel arguments add
# the serial console, last so that it is /dev/console, and turn Plymouth off: systemd then asks for the
# passphrase there, where the lab sees the prompt and types the answer (serialWrite in lab.mjs).
set -euo pipefail

IMAGE="$1"
DISK="$2"
SIZE=64G
INSTALLER=false
PASSPHRASE=""
for arg in "${@:3}"; do
    case "${arg}" in
        --installer) INSTALLER=true ;;
        --installer=*) INSTALLER=true PASSPHRASE="${arg#--installer=}" ;;
        *) SIZE="${arg}" ;;
    esac
done
DISKS=/vm/disks
SHIM_GUID=605dab50-e046-4300-abb6-3dd810dd8b23
[[ "${DISK}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "make-disk: a disk's name is lowercase letters, digits, . _ -" >&2; exit 2; }

mkdir -p "${DISKS}"
[[ "${IMAGE}" == localhost/* ]] || podman pull "${IMAGE}"
raw="${DISKS}/${DISK}.raw"
rm -f "${raw}"
truncate -s "${SIZE}" "${raw}"
RUN=(podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t
    -v /dev:/dev -v /run/udev:/run/udev -v /var/lib/containers:/var/lib/containers -v "${DISKS}:/output")
if [[ "${INSTALLER}" == false ]]; then
    # --generic-image: no firmware boot entry, and nothing of this machine's, as for a disk image to copy
    # around. The image names no filesystem for bootc; the installer ISO's is btrfs.
    "${RUN[@]}" "${IMAGE}" bootc install to-disk --via-loopback --generic-image --filesystem btrfs --wipe "/output/${DISK}.raw"
else
    # Anaconda's partitions for this image (its Fedora profile): a 600 MiB ESP, a 2 GiB ext4 /boot, and the
    # rest btrfs, LUKS2 under it when encryption was chosen
    "${RUN[@]}" -i -e PASSPHRASE="${PASSPHRASE}" -e RAW="/output/${DISK}.raw" --entrypoint bash "${IMAGE}" -s <<'SCRIPT'
set -euo pipefail
# No udev in here answers device-mapper, which would wait for it forever: libdevmapper makes the nodes
export DM_DISABLE_UDEV=1
loop="$(losetup -fP --show "${RAW}")"
cleanup() {
    umount -R /target 2>/dev/null || true
    [[ -e /dev/mapper/vmlab-root ]] && cryptsetup close vmlab-root
    losetup -d "${loop}"
}
trap cleanup EXIT
# bootc install to-filesystem has bootupd install its BIOS component too, as on its own to-disk disks, and GRUB
# needs a BIOS boot partition for that on GPT: 1 MiB at the start, numbered 4 so that the ESP, /boot and the
# system are 1 to 3 as on a UEFI machine Anaconda installed (which installs no BIOS component)
sfdisk --quiet "${loop}" <<EOF
label: gpt
${loop}p4 : start=2048, size=2048, type=21686148-6449-6E6F-744E-656564454649, name="BIOS boot"
${loop}p1 : start=4096, size=600MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System Partition"
${loop}p2 : size=2GiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
${loop}p3 : type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
for i in 1 2 3 4; do
    for _ in $(seq 50); do [[ -b "${loop}p${i}" ]] && break; sleep 0.2; done
done
mkfs.vfat -F 32 -n EFI "${loop}p1" >/dev/null
mkfs.ext4 -q -F "${loop}p2"
root="${loop}p3"
kargs=()
if [[ -n "${PASSPHRASE}" ]]; then
    printf '%s' "${PASSPHRASE}" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - "${root}"
    luks="$(cryptsetup luksUUID "${root}")"
    printf '%s' "${PASSPHRASE}" | cryptsetup open --key-file - "${root}" vmlab-root
    root=/dev/mapper/vmlab-root
    kargs+=(--karg "rd.luks.uuid=luks-${luks}")
fi
mkfs.btrfs -q -f -L amethystora "${root}"
mkdir -p /top /target
mount "${root}" /top
btrfs subvolume create /top/root >/dev/null
btrfs subvolume create /top/home >/dev/null
umount /top
mount -o subvol=root,compress=zstd:1 "${root}" /target
mkdir -p /target/boot
mount "${loop}p2" /target/boot
mkdir -p /target/boot/efi
mount "${loop}p1" /target/boot/efi
bootc install to-filesystem --generic-image --karg rootflags=subvol=root \
    --karg console=tty0 --karg console=ttyS0,115200 --karg rd.plymouth=0 --karg plymouth.enable=0 "${kargs[@]}" /target
fs="$(blkid -s UUID -o value "${root}")"
esp="$(blkid -s UUID -o value "${loop}p1")"
# What Anaconda writes besides /boot, which bootc wrote; bootc's finalizing left the system read-only
mount -o remount,rw /target
deployment="$(ls -d /target/ostree/deploy/default/deploy/*.0)"
{
    grep -s . "${deployment}/etc/fstab" | grep -vE ' /(boot/efi|home)? ' || true
    echo "UUID=${fs} / btrfs subvol=root,compress=zstd:1,x-systemd.device-timeout=0 0 0"
    echo "UUID=${esp} /boot/efi vfat umask=0077,shortname=winnt 0 2"
    echo "UUID=${fs} /home btrfs subvol=home,compress=zstd:1,x-systemd.device-timeout=0 0 0"
} >"${deployment}/etc/fstab.new"
mv "${deployment}/etc/fstab.new" "${deployment}/etc/fstab"
[[ -z "${PASSPHRASE}" ]] || echo "luks-${luks} UUID=${luks} none discard" >"${deployment}/etc/crypttab"
echo "make-disk: fstab:"; cat "${deployment}/etc/fstab"
echo "make-disk: kernel arguments:"; grep -h '^options' /target/boot/loader/entries/*.conf
SCRIPT
fi
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
