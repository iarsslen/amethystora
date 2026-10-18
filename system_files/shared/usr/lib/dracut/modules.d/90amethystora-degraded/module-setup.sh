#!/usr/bin/bash
# Starting the system with one of its disks missing, from the boot menu's "Start with a disk missing"
# (amethystora-raid boot writes it on a machine whose system spans several disks): the udev rule that lets
# the root btrfs mount degraded when the kernel command line asks for it. In the initramfs only, so that a
# pool of disks is never mounted around a missing disk by itself.

check() {
    return 0
}

depends() {
    echo btrfs
}

install() {
    inst_simple "${moddir}/65-amethystora-btrfs-degraded.rules" /usr/lib/udev/rules.d/65-amethystora-btrfs-degraded.rules
}
