#!/usr/bin/env bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script theming user 1 || exit 0

set -xeuo pipefail

VEN_ID="$(cat /sys/devices/virtual/dmi/id/chassis_vendor)"
SYS_ID="$(cat /sys/devices/virtual/dmi/id/product_name)"

# The panel button keeps the Amethystora gem on every machine. This hook used to put the maker's logo
# there on a Framework laptop and on a Thelio Astra, and the image no longer carries anybody else's
# logo (build_files/base/06-branding.sh).
if [[ ":Framework:" =~ :$VEN_ID: ]]; then
	echo 'Setting touch scroll type'
	dconf write /org/gnome/desktop/peripherals/mouse/natural-scroll true
	if [[ $SYS_ID == "Laptop ("* ]]; then
		echo 'Applying font fix for Framework 13'
		dconf write /org/gnome/desktop/interface/text-scaling-factor 1.25
	fi
fi
