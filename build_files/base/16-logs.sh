#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Amethystora Logs (amethystora-logs): the journal searched, filtered, followed and read one app or
# service at a time, in a window of its own, in place of GNOME Logs, which 04-packages.sh takes off the
# upstream Flatpak list. The app (main.js, its page, script and stylesheet) comes from system_files and
# is already in place; this adds what it runs on, as 14-security.sh does for Security.
#
#   - Electron: the release 13-manual.sh installed and checked for the Manual, hard-linked rather than
#     copied, so that the image carries one Electron for every window and Renovate bumps one pin.
#   - Quicksand, the face of the Amethystora wordmark, which the window draws its sidebar in.

MANUAL_DIR=/usr/lib/amethystora-manual
LOGS_DIR=/usr/lib/amethystora-logs
LICENSE_DIR=/usr/share/licenses/amethystora-logs

# Everything beside the Manual's executable but its resources, which hold each window's own app
for entry in "${MANUAL_DIR}"/*; do
    case "$(basename "${entry}")" in
        amethystora-manual | resources) ;;
        *) cp -al "${entry}" "${LOGS_DIR}/" ;;
    esac
done
ln "${MANUAL_DIR}/amethystora-manual" "${LOGS_DIR}/amethystora-logs"
# The translations' runtime (i18n.js), the Manual's own file, as Electron is
ln "${MANUAL_DIR}/resources/app/i18n.js" "${LOGS_DIR}/resources/app/i18n.js"

install -Dpm0644 /ctx/branding/fonts/QuicksandVariable.ttf "${LOGS_DIR}/resources/app/fonts/QuicksandVariable.ttf"
install -Dpm0644 /ctx/branding/fonts/Quicksand-OFL.txt "${LICENSE_DIR}/Quicksand-OFL.txt"

echo "::endgroup::"
