#!/usr/bin/env bash
#
# Put the boot menu's artwork on, and keep it in step with the image.
#
# The artwork is on by default, but it lives on /boot, which the image cannot carry: so it is put
# there once per machine, the first time this runs, and a machine whose owner turns it off with
# `ame desktop boot-menu off` keeps it off. A machine that does not start with GRUB (a sealed image)
# is left alone.
#
# The refresh has to run after every image update, not once: an image update does not touch /boot,
# so without it the artwork would stay at whatever version first put it there. It does nothing at
# all unless /boot/grub2/themes/amethystora is already there, and stops at once when the copy
# already matches the image.

source /usr/lib/amethystora/setup-services/libsetup.sh

set -euo pipefail

if version-script grub-theme-default system 1; then
    /usr/bin/amethystora-grub-theme install || echo "Left the boot menu as it was"
fi

/usr/bin/amethystora-grub-theme refresh
