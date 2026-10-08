#!/usr/bin/env bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script virtual-input system 1 || exit 0

set -x

# /dev/uinput used to be given to whoever sits at the machine. It is root's now, and `ame apps gaming` and
# `ame apps opentabletdriver` give it back as they set up (ame security virtual-input off). A machine that
# set either up before keeps it, once, instead of finding its controllers or tablet dead after the update.
if flatpak info --system com.valvesoftware.Steam >/dev/null 2>&1 || [[ -e /etc/udev/rules.d/71-opentabletdriver.rules ]]; then
    /usr/libexec/amethystora-hardening set virtual-input off
fi
