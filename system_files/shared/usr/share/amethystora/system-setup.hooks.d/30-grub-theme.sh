#!/usr/bin/env bash
#
# Keep an installed boot menu in step with the image.
#
# The theme lives on /boot, which an image update does not touch, so without this the artwork would
# stay at whatever version first put it there. This never turns the theme on: refresh does nothing
# at all unless /boot/grub2/themes/amethystora is already there, and it stops immediately when the
# copy already matches the image. Turning it on is `ujust setup-grub-theme`, and only that.
#
# There is no version-script here on purpose: this has to run after every image update, not once.

set -euo pipefail

/usr/bin/amethystora-grub-theme refresh
