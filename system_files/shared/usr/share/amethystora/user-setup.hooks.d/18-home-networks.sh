#!/usr/bin/env bash
#
# Phone pairing (GSConnect) was open on every network, and is now open only on the networks named home
# (`ame security home-networks`), of which there are none until somebody names one. Said once to an account
# that has a phone paired, so that a phone that stops reaching this machine has its reason.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script home-networks user 1 || exit 0

# A paired phone is a device in GSConnect's list, which is empty for an account that never paired one
[[ "$(gsettings get org.gnome.Shell.Extensions.GSConnect devices 2>/dev/null)" == *"'"* ]] || exit 0
# Named already, by whoever got there first: nothing to say
[[ -s /etc/amethystora/firewall-home ]] && exit 0

systemd-run --user --collect --quiet --on-active=60 -- /usr/libexec/amethystora-home-networks-notice
