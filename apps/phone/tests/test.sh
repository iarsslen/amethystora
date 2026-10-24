#!/usr/bin/bash
# test.sh [CASE...]: on the host (Git Bash with Docker). Builds the app's debug binary (cargo.sh phone, set CARGO to its
# path), then runs tests/run-behaviour.sh in the amethystora-rust container against the mock of amethystora-connect.
# The exit status is the number of checks that failed. -n skips the build.
#
#   CARGO=.../scratchpad/cargo.sh bash apps/phone/tests/test.sh [pairing changes unpair send reply text messages state]
set -u
build=1
if [[ ${1:-} == -n ]]; then build=0; shift; fi
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -W)
: "${CARGO:?the path of cargo.sh}"
export PATH="$(cygpath -u "$LOCALAPPDATA")/Programs/DockerDesktop/resources/bin:$PATH"
if ((build)); then
    bash "$CARGO" phone build -p amethystora-phone 2>&1 | grep -E "^(error|warning: unused)|^\s+-->" | head -40
fi
MSYS_NO_PATHCONV=1 docker.exe run --rm --shm-size=1g \
    -v "$repo/system_files/shared:/repo:ro" \
    -v "$repo/branding:/branding:ro" \
    -v "$repo/apps/connect/dbus:/dbus:ro" \
    -v "$repo/apps/phone/tests:/tests:ro" \
    -v "$repo/tests/vm/suites/atspi.py:/atspi.py:ro" \
    -v "amethystora-target-phone:/target:ro" \
    -e DEBUG \
    --entrypoint /usr/bin/bash amethystora-rust /tests/run-behaviour.sh "$@" 2>&1 | grep -v -e Vulkan -e "^$"
