#!/usr/bin/bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script tailscale privileged 1 || exit 0

set -xeuo pipefail

# Tailscale's operator manages the tailnet connection without sudo: an administrator's to have, so only
# one of those is made it, whatever let this run
user="$(getent passwd "${PKEXEC_UID:?}" | cut -d: -f1)"
[[ " $(id -nG "${user}") " == *" wheel "* ]] || exit 0
tailscale set --operator="${user}"
