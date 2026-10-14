#!/usr/bin/env bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script console-query system 1 || exit 0

set -x

# systemd asks the console for its size at boot and waits for an answer that never comes while Plymouth
# holds it, which hung about 1 boot in 10 to 50 (/usr/lib/bootc/kargs.d/12-amethystora-console.toml).
# kargs.d only reaches a machine that bootc updates: one with layered packages is updated by rpm-ostree,
# which ignores it, so this adds the argument there, once, for the next restart. A sealed image has it in
# its signed UKI. When that file is dropped, version 2 has to take it off again (--delete-if-present).
# AMETHYSTORA_CMDLINE and AMETHYSTORA_SEALED are for 20-tests.sh, which runs this against stand-ins.
ARG=systemd.tty.term.console=dumb
CMDLINE="${AMETHYSTORA_CMDLINE:-/proc/cmdline}"
SEALED="${AMETHYSTORA_SEALED:-/usr/share/amethystora/sealed}"
[[ -e "${SEALED}" || " $(<"${CMDLINE}") " == *" ${ARG} "* ]] && exit 0
echo "Adding ${ARG} to the kernel arguments, for the next restart"
rpm-ostree kargs --append-if-missing="${ARG}"
