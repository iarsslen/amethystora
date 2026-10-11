#!/usr/bin/bash
# setup.sh: builds the VM lab's image and starts its container, amevm, again. The disks and VMs are kept in
# the volume amevm-vm and the pulled images in amevm-storage; VMs that were running are stopped.
set -euo pipefail

# Relative paths, which Git Bash on Windows passes on as they are (with MSYS_NO_PATHCONV=1, for /dev below)
cd "$(dirname "$0")"
docker build -t amethystora-vm-lab -f Containerfile .
docker rm -f amevm >/dev/null 2>&1 || true
# The host's /dev, where the partitions of a loop device appear as bootc makes them
docker run -d --name amevm --init --privileged -v /dev:/dev -v amevm-vm:/vm -v amevm-storage:/var/lib/containers amethystora-vm-lab
docker exec amevm test -c /dev/kvm || echo "setup: no /dev/kvm in the container: the VMs will not start" >&2
