#!/usr/bin/bash
# Starting the system with one of its disks missing, from the boot menu's "Start with a disk missing"
# (amethystora-raid boot writes it on a machine whose system spans several disks): the udev rule that lets
# the root btrfs mount degraded when the kernel command line asks for it, and the hook that keeps dracut from
# waiting for the missing disk's LUKS then. In the initramfs only, so that a pool of disks is never mounted
# around a missing disk by itself.

check() {
    return 0
}

depends() {
    echo btrfs
}

install() {
    inst_simple "${moddir}/65-amethystora-btrfs-degraded.rules" /usr/lib/udev/rules.d/65-amethystora-btrfs-degraded.rules
    # After the crypt module's parse-crypt.sh (cmdline 30)
    inst_hook cmdline 99 "${moddir}/amethystora-degraded-crypt.sh"
}
