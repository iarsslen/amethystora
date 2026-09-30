#!/usr/bin/bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script vscodium user 1 || exit 1

set -x

# Setup VSCodium
if test ! -e "$HOME"/.config/VSCodium/User/settings.json; then
	mkdir -p "$HOME"/.config/VSCodium/User
	cp -f /etc/skel/.config/VSCodium/User/settings.json "$HOME"/.config/VSCodium/User/settings.json
fi

# From Open VSX, VSCodium's marketplace. Microsoft's Remote SSH and Dev Containers may only be used
# with Microsoft's builds: Open Remote SSH takes the place of the first, and dev containers are run
# with the devcontainer command line (developer.md)
codium --install-extension jeanp413.open-remote-ssh
codium --install-extension ms-azuretools.vscode-containers
