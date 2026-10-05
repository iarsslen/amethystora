#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

IMPORTANT_PACKAGES_DX=(
    bpftool
    codium
    containerd.io
    docker-ce
    docker-buildx-plugin
    docker-compose-plugin
    flatpak-builder
    gdb
    libvirt
    ltrace
    perf
    qemu
    strace
    valgrind
    wireshark
)

for package in "${IMPORTANT_PACKAGES_DX[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1 ; }
done

# genisoimage is Fedora's, not negativo17's CDDL mkisofs (00-dx.sh)
[[ "$(rpm -q --queryformat '%{VENDOR}' genisoimage)" == "Fedora Project" ]]
rpm -q mkisofs >/dev/null && false

# The development apps are installed on the first boot, beside the ones every image comes with
grep -q "^\[Flatpak Preinstall org.gnome.Builder\]$" /usr/share/flatpak/preinstall.d/amethystora-dx.preinstall

IMPORTANT_UNITS=(
    docker.socket
    podman.socket
)

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
