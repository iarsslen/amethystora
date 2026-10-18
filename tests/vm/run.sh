#!/usr/bin/bash
# run.sh [all | build | disk | test] [--keep]: a test run of this checkout's last commit in the VM lab
# (README.md). Starts the lab when it is not running, sends HEAD into it as a git bundle, which holds what is
# committed whatever the checkout's line endings, and runs tests/vm/run.mjs from it there. The run's files
# stay in the lab, in /vm/runs/last. With VMLAB_NAME set, the run has a source tree, image tag, disks and VMs of
# that name, and its files are in /vm/runs/last-NAME, so that it leaves another session's run alone.
set -euo pipefail

export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/../.."
NAME="${VMLAB_NAME:-test}"
SRC=/build/src
[[ "${NAME}" == test ]] || SRC="/build/src-${NAME}"
if ! command -v docker >/dev/null && command -v cygpath >/dev/null; then
    PATH="$(cygpath -u "${LOCALAPPDATA}")/Programs/DockerDesktop/resources/bin:${PATH}"
fi
if [[ "$(docker inspect -f '{{.State.Running}}' amevm 2>/dev/null)" != true ]]; then
    docker start amevm >/dev/null 2>&1 || bash tests/vm/setup.sh
fi
# Only the test stage needs KVM: a build or a disk goes on without it
if ! docker exec amevm test -c /dev/kvm; then
    docker run --rm --privileged --pid=host alpine nsenter -t 1 -m -- sh -c \
        'grep -q AuthenticAMD /proc/cpuinfo && modprobe kvm_amd || modprobe kvm_intel' ||
        echo "run.sh: no /dev/kvm, so no VM can start (the host lost hardware virtualization; restart it)" >&2
fi
git bundle create - HEAD 2>/dev/null | docker exec -i amevm sh -c "cat >/vm/head-${NAME}.bundle"
docker exec amevm sh -c "rm -rf ${SRC} && git clone -q /vm/head-${NAME}.bundle ${SRC}"
exec docker exec -e "VMLAB_NAME=${NAME}" amevm node "${SRC}/tests/vm/run.mjs" "$@"
