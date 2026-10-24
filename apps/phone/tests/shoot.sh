#!/usr/bin/bash
# shoot.sh [-n] SCENARIO THEME NAME [APP ARGUMENTS...]: on the host (Git Bash with Docker). Builds the app's debug
# binary in the amethystora-rust container (cargo.sh phone, set CARGO to its path), then runs tests/run-shot.sh in that
# container with the repository mounted, and leaves SCRATCH/shots/NAME-THEME.png. -n skips the build.
#
#   CARGO=.../scratchpad/cargo.sh SCRATCH=.../scratchpad/phone-shots bash apps/phone/tests/shoot.sh default amethystora phones
set -u
build=1
if [[ ${1:-} == -n ]]; then build=0; shift; fi
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -W)
: "${CARGO:?the path of cargo.sh}" "${SCRATCH:?a folder for the screenshots}"
mkdir -p "$SCRATCH/shots"
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
    -v "$(cygpath -w "$SCRATCH"):/scratch" \
    -v "amethystora-target-phone:/target:ro" \
    -e LANG -e SIZE -e NOMOCK -e WAIT -e SETTLE -e RTL -e DEBUG -e AMETHYSTORA_CONNECT_EXE \
    --entrypoint /usr/bin/bash amethystora-rust /tests/run-shot.sh "$@" 2>&1 | grep -v -e Vulkan -e "^$"
