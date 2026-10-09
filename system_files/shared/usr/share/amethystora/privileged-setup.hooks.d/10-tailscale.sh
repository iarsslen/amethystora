#!/usr/bin/bash

source /usr/lib/amethystora/setup-services/libsetup.sh

# Version 1 made the administrator who logged in first Tailscale's operator, without a password. The
# operator reconfigures tailscaled, which runs as root, without one either: any program of that account
# could join the machine to a tailnet somebody else runs and turn on Tailscale SSH, which that tailnet's
# policy can open to root. This takes it back, once, where tailscaled can be asked: administering
# Tailscale takes sudo, as every other root service does, and `sudo tailscale set --operator=$USER` gives
# it back to whoever wants it at that cost (software.md says so).
systemctl is-active --quiet tailscaled.service || exit 0

version-script tailscale privileged 2 || exit 0

set -xeuo pipefail

tailscale set --operator=
