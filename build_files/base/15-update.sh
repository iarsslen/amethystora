#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Amethystora Updates (amethystora-update): the system, the apps and the command-line tools brought up
# to date in a window of their own, in place of upstream's System Update launcher, which opened a
# terminal on `ujust update`. The app (main.js, its page, script and stylesheet) comes from system_files
# and is already in place; this adds what it runs on, as 14-security.sh does for Security.
#
#   - Electron: the release 13-manual.sh installed and checked for the Manual, hard-linked rather than
#     copied, so that the image carries one Electron for every window and Renovate bumps one pin.
#   - Quicksand, the face of the Amethystora wordmark, which the window draws its top bar in.

MANUAL_DIR=/usr/lib/amethystora-manual
UPDATE_DIR=/usr/lib/amethystora-update
LICENSE_DIR=/usr/share/licenses/amethystora-update

# Everything beside the Manual's executable but its resources, which hold each window's own app
for entry in "${MANUAL_DIR}"/*; do
    case "$(basename "${entry}")" in
        amethystora-manual | resources) ;;
        *) cp -al "${entry}" "${UPDATE_DIR}/" ;;
    esac
done
ln "${MANUAL_DIR}/amethystora-manual" "${UPDATE_DIR}/amethystora-update"

install -Dpm0644 /ctx/branding/fonts/QuicksandVariable.ttf "${UPDATE_DIR}/resources/app/fonts/QuicksandVariable.ttf"
install -Dpm0644 /ctx/branding/fonts/Quicksand-OFL.txt "${LICENSE_DIR}/Quicksand-OFL.txt"

echo "::endgroup::"
