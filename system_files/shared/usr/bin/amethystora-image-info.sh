#!/usr/bin/bash

# shellcheck disable=2046
echo -n "$(jq -r '"\(.["image-name"]):\(.["image-tag"])"' < /usr/share/amethystora/image-info.json)"

if [[ "$(rpm-ostree status --booted)" =~ "signed" ]]; then
	echo -n " 🔐"
else
	echo -n -e " \033[5m🔓\033[0m"
fi
