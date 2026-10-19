#!/usr/bin/env bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script proc-mem system 1 || exit 0

set -x

# proc_mem.force_override=ptrace lets only a program's own debugger write through /proc/PID/mem over memory
# it may not write itself, such as its code (/usr/lib/bootc/kargs.d/10-amethystora-hardening.toml). It was
# one of the extra arguments, off until turned on, and is now the image's own, on until turned off. kargs.d
# only reaches a machine that bootc updates: one with layered packages is updated by rpm-ostree, which
# ignores it, so this adds the argument there, once, for the next restart. A sealed image has it in its
# signed UKI. A machine whose owner had turned the extra on loses the line that said so, which now says
# nothing. AMETHYSTORA_CMDLINE, AMETHYSTORA_SEALED and AMETHYSTORA_HARDENING_ROOT are for 20-tests.sh,
# which runs this against stand-ins.
ARG=proc_mem.force_override=ptrace
CMDLINE="${AMETHYSTORA_CMDLINE:-/proc/cmdline}"
SEALED="${AMETHYSTORA_SEALED:-/usr/share/amethystora/sealed}"
ON="${AMETHYSTORA_HARDENING_ROOT:-}/etc/amethystora/hardening-on"
OFF="${AMETHYSTORA_HARDENING_ROOT:-}/etc/amethystora/hardening-off"
if grep -qxF "kernel-args ${ARG}" "${ON}" 2>/dev/null; then
    grep -vxF "kernel-args ${ARG}" "${ON}" >"${ON}.new"
    if [[ -s "${ON}.new" ]]; then
        chmod 0644 "${ON}.new"
        mv "${ON}.new" "${ON}"
    else
        rm -f "${ON}.new" "${ON}"
    fi
fi
[[ -e "${SEALED}" || " $(<"${CMDLINE}") " == *" proc_mem.force_override="* ]] && exit 0
grep -qxF "kernel-args ${ARG}" "${OFF}" 2>/dev/null && exit 0
echo "Adding ${ARG} to the kernel arguments, for the next restart"
rpm-ostree kargs --append-if-missing="${ARG}"
