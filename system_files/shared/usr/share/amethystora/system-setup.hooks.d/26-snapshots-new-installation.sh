#!/usr/bin/env bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script snapshots-new-installation system 1 || exit 0

set -x

# Hourly read-only snapshots of the home folders, on from the first boot of a machine installed from an
# Amethystora ISO, whose installer leaves this marker (iso/iso.toml, iso/live/installer.ks). A machine that
# was already running when this arrived has no marker, and keeps the snapshots as its owner left them.
# `ame security ransomware off` turns them off like any other switch.
MARKER=/var/lib/amethystora/new-installation
[[ -e "${MARKER}" ]] || exit 0
rm -f "${MARKER}"
if [[ "$(stat -f -c %T /var/home)" == btrfs && "$(stat -c %i /var/home)" == 256 ]]; then
    /usr/libexec/amethystora-security-config note ransomware-protection on
    systemctl enable --now amethystora-home-snapshot.timer
fi
