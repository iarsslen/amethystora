#!/usr/bin/env bash
#
# Remove GNOME Logs from a machine that got it from the default Flatpak list.
#
# The list installed org.gnome.Logs until Amethystora Logs (amethystora-logs) took its place. Taking
# an app off the list keeps it off new machines only: nothing uninstalls a Flatpak that is already
# there, so those machines were left with two apps called Logs in the app grid.
#
# The list installs system-wide, so only that copy goes, and only once per machine: GNOME Logs
# installed from Bazaar after this has run is the user's own choice, and stays.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script retire-gnome-logs system 1 || exit 0

set -x

if flatpak info --system org.gnome.Logs >/dev/null 2>&1; then
    flatpak uninstall --system --noninteractive -y org.gnome.Logs
fi

exit 0
