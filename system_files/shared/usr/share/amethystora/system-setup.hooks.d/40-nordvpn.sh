#!/usr/bin/env bash
#
# Let the machine's administrators use NordVPN.
#
# nordvpnd answers only root and members of the nordvpn group. NordVPN's installer adds the user who
# ran it; an image has nobody to add when it is built, so every member of wheel is added here. They
# could run the client as root with sudo anyway, so this grants nothing they did not have. Anyone else
# is added with `sudo usermod -aG nordvpn <name>`. Membership counts from the next login.
#
# There is no version-script here on purpose: an administrator created later is added at the next
# boot. /etc/group is written only when someone is missing, because every write to it is audited.

set -euo pipefail

members=",$(getent group nordvpn | cut -d: -f4),"
for user in $(getent group wheel | cut -d: -f4 | tr ',' ' '); do
    [[ ${members} == *",${user},"* ]] || usermod -aG nordvpn "${user}"
done
