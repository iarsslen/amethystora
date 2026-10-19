#!/bin/sh
# dracut cmdline hook (amethystora-degraded), after the crypt module's parse-crypt.sh: with "Start with a disk
# missing" chosen, the kernel command line asks for the root degraded, and dracut's initqueue no longer waits for
# every rd.luks.uuid to open (90-crypt.sh), which it would do forever for the missing disk's. The disks that are
# there open as always, and the missing one's unit is nofail in that entry.
case ",$(getarg rootflags=)," in
    *,degraded,*) rm -f "${hookdir:-/var/lib/dracut/hooks}/initqueue/finished/90-crypt.sh" ;;
esac
