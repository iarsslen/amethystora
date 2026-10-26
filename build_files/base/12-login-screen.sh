#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The login screen's background: the crown the boot splash ends on, without the gem, so the handover from
# Plymouth to GDM is one picture carried across. branding/generate.mjs draws it. GNOME reads it from inside
# GNOME Shell's own theme bundle and nowhere else, which the helper rebuilds with it; an image of one's own
# built on this one puts its picture there with the same helper (amethystora-brand).
/usr/libexec/amethystora-login-background /usr/share/backgrounds/amethystora/amethystora-login.png

echo "::endgroup::"
