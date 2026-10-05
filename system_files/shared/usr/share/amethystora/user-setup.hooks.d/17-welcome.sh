#!/usr/bin/bash
#
# The manual's welcome page, once, at an account's first login, the way 11-theme.sh applies the theme
# once. The manual opens in a unit of its own: the setup service this hook runs in takes whatever is
# left of it when it ends, and the systemd user manager is what has the session's display by now.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script welcome user 1 || exit 0

systemd-run --user --collect --quiet -- /usr/bin/amethystora-manual welcome
# ...and, once the welcome page has had a minute to itself, the offer of classic windows for someone
# who does not want them tiled. With the welcome page, so that it too comes once per account.
systemd-run --user --collect --quiet --on-active=90 -- /usr/libexec/amethystora-layout-offer
