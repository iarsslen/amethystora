#!/usr/bin/bash

# shellcheck disable=2046
echo -n "$(jq -r '"\(.["image-name"]):\(.["image-tag"])"' < /usr/share/amethystora/image-info.json)"

# The running image's origin, as amethystora-deployments lists it on an ostree image and a sealed one
REFERENCE="$(/usr/libexec/amethystora-deployments 2>/dev/null |
	jq -r '[.deployments[] | select(.booted)][0]["container-image-reference"] // ""' 2>/dev/null)"
if [[ "${REFERENCE}" == ostree-image-signed:* ]]; then
	echo -n " 🔐"
else
	echo -n -e " \033[5m🔓\033[0m"
fi
