#!/usr/bin/env bash

set -euo pipefail

# The privileged hooks are an administrator's: polkit lets one sitting at the machine run them without a
# password (20-privileged-user-setup.rules), and would ask anyone else for an administrator's at login
[[ " $(id -nG) " == *" wheel "* ]] || exit 0

echo "Running all privileged units"

pkexec /usr/bin/amethystora-privileged-setup
