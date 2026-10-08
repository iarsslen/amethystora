#!/usr/bin/bash
# Signs the UKI 10-uki.sh built (Containerfile.sealed) with the Secure Boot key, in the stage made from
# Fedora's own image with sbsigntools and nothing else: the key is never mounted in a stage built from
# the image, whose packages come from third-party repositories too.

echo "::group:: ===$(basename "$0")==="

set -xeuo pipefail

readarray -t UKIS < <(find /run/unsigned -maxdepth 1 -name '*.efi')
[[ ${#UKIS[@]} -eq 1 ]]

mkdir -p /out
sbsign --key /run/secrets/SECUREBOOT_KEY --cert /run/secrets/SECUREBOOT_CERT \
    --output "/out/$(basename "${UKIS[0]}")" "${UKIS[0]}"

echo "::endgroup::"
