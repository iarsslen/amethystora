#!/usr/bin/env bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script signed-updates system 1 || exit 0

set -x

# Installs made from an ISO or with a plain `bootc switch` track the image without checking its signature.
# Switch them, in place and without downloading anything, to updates that /etc/containers/policy.json must
# accept: only images signed with /etc/pki/containers/amethystora.pub.
booted="$(bootc status --format=json | jq -r '.status.booted.image.image.image // empty')"
signature="$(bootc status --format=json | jq -r '.status.booted.image.image.signature // "none" | tostring')"

if [[ "${booted}" != ghcr.io/iarsslen/* ]]; then
	echo "Not an Amethystora image (${booted:-unknown}), leaving update verification alone"
	exit 0
fi
if [[ "${signature}" == "containerPolicy" ]]; then
	echo "Updates of ${booted} are already verified"
	exit 0
fi

bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry "${booted}"
