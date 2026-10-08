#!/usr/bin/bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script vscodium user 1 || exit 1

set -x

# Setup VSCodium
if test ! -e "$HOME"/.config/VSCodium/User/settings.json; then
	mkdir -p "$HOME"/.config/VSCodium/User
	cp -f /etc/skel/.config/VSCodium/User/settings.json "$HOME"/.config/VSCodium/User/settings.json
fi

# From Open VSX, VSCodium's marketplace, and only as published there by its own maker. Microsoft's Remote
# SSH and Dev Containers may only be used with Microsoft's builds: Open Remote SSH takes the place of the
# first, and dev containers are run with the devcontainer command line (developer.md). Container Tools is
# not installed: Open VSX carries a copy its bot republished, not one from Microsoft.
codium --install-extension jeanp413.open-remote-ssh
