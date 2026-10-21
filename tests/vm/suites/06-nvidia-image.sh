#!/usr/bin/bash
# The NVIDIA images on the lab's machine, which has no NVIDIA card: they start, carry the driver their flavor names
# (NVIDIA's closed driver of its 580 branch on -nvidia-lts, its open one on -nvidia-open), signed with the key the
# image enrolls, and the GPU check offers the image without the driver. Skipped on any other image.
source "$(dirname "$0")/lib.sh"

same() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1" "expected: $3" "found: $2"; fi; }
INFO=/usr/share/amethystora/image-info.json
FLAVOR="$(jq -r '."image-flavor"' "${INFO}")"
IMAGE="$(jq -r '."image-name"' "${INFO}")"
if [[ "${FLAVOR}" != nvidia-* ]]; then
    skip "not an NVIDIA image (${IMAGE}, flavor ${FLAVOR})"
    finish
fi

same "the image's flavor is the end of its name" "${IMAGE##*-nvidia-}" "${FLAVOR#nvidia-}"
case "${FLAVOR}" in
    nvidia-lts)
        same "NVIDIA's closed driver" "$(modinfo -F license nvidia)" NVIDIA
        same "of the 580 branch" "$(rpm -q --queryformat '%{VERSION}' kmod-nvidia | cut -d. -f1)" 580
        ;;
    nvidia-open) same "NVIDIA's open driver" "$(modinfo -F license nvidia)" "Dual MIT/GPL" ;;
esac
serial() { tr -d ':' | sed 's/^0*//' | tr a-f A-F; }
same "it is signed with the key ame security secure-boot enrolls" "$(modinfo -F sig_key nvidia | serial)" \
    "$(openssl x509 -inform DER -in /usr/share/amethystora/secure-boot/akmods-amethystora.der -noout -serial | cut -d= -f2 | serial)"
same "Secure Boot trusts it here, where the lab enrolled the image's keys" \
    "$(/usr/libexec/amethystora-mok-status | grep -c '^enrolled .*/akmods-amethystora\.der$')" 1
if grep -qw 'modprobe.blacklist=nouveau' /proc/cmdline; then ok "nouveau is kept out, as on every NVIDIA image"; else
    not_ok "the NVIDIA image's arguments" "$(cat /proc/cmdline)"; fi
same "with no NVIDIA card, the GPU check offers the image without the driver" \
    "$(/usr/libexec/amethystora-gpu-check offer)" "no-nvidia-card ${IMAGE%-"${FLAVOR}"}"
same "the driver check finds nothing missing" "$(/usr/libexec/amethystora-driver-status --json | jq -c .findings)" "[]"
# NVIDIA's own units, on a machine without the card they are for: none may fail (the lab's machine is degraded for
# reasons of its own, which the main image's runs show too)
failed="$(systemctl --failed --plain --no-legend | awk '{print $1}' | grep -i nvidia | paste -sd ' ')"
if [[ -z "${failed}" ]]; then ok "none of NVIDIA's units failed without a card"; else
    not_ok "NVIDIA's units failed" "${failed}" "$(journalctl -b -u "${failed%% *}" --no-pager -o cat | tail -n 5)"; fi
finish
