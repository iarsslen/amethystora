#!/usr/bin/env bash
#
# Keep this machine's updates signature-checked.
#
# Installs made from an ISO or with a plain `bootc switch` track the image without checking its
# signature. Switch them, in place and without downloading anything, to updates that
# /etc/containers/policy.json must accept: only images signed with /etc/pki/containers/amethystora.pub.
#
# There is no version-script here on purpose: this has to run at every boot, not once. A later
# `bootc switch` turns verification off again without --enforce-container-sigpolicy, and a machine in
# that state looks exactly like one that is still checking, so the question is worth asking again. On a
# machine that is already verified this costs one `bootc status` and stops.
#
# An image that is not one of ours is left alone. Somebody tracking their own build is not asking for
# this image's signing key, and forcing it on them would stop their updates altogether.

set -euo pipefail
set -x

STATUS="$(bootc status --format=json 2>/dev/null || true)"
if [[ -z "${STATUS}" ]]; then
	echo "bootc cannot report this machine's image, leaving update verification alone"
	exit 0
fi
booted="$(jq -r '.status.booted.image.image.image // empty' <<<"${STATUS}")"
signature="$(jq -r '.status.booted.image.image.signature // "none" | tostring' <<<"${STATUS}")"

if [[ "${booted}" != ghcr.io/iarsslen/* ]]; then
	echo "Not an Amethystora image (${booted:-unknown}), leaving update verification alone"
	exit 0
fi
if [[ "${signature}" == "containerPolicy" ]]; then
	echo "Updates of ${booted} are already verified"
	exit 0
fi

echo "Updates of ${booted} are not signature-checked. Turning verification back on."
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry "${booted}"
