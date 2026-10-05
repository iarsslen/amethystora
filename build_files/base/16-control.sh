#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Amethystora Control (amethystora-control): Amethystora's own settings outside security in a window of
# their own, each with the `ame` command that changes it, from the list /usr/libexec/amethystora-control-list
# gives. The app (main.js, its page, script and stylesheet) comes from system_files and is already in
# place; this adds what it runs on, as 14-security.sh does for Security.
#
#   - Electron: the release 13-manual.sh installed and checked for the Manual, hard-linked rather than
#     copied, so that the image carries one Electron for every window and Renovate bumps one pin.
#   - Quicksand, the face of the Amethystora wordmark, which the window draws its sidebar in.

MANUAL_DIR=/usr/lib/amethystora-manual
CONTROL_DIR=/usr/lib/amethystora-control
LICENSE_DIR=/usr/share/licenses/amethystora-control

# Everything beside the Manual's executable but its resources, which hold each window's own app
for entry in "${MANUAL_DIR}"/*; do
    case "$(basename "${entry}")" in
        amethystora-manual | resources) ;;
        *) cp -al "${entry}" "${CONTROL_DIR}/" ;;
    esac
done
ln "${MANUAL_DIR}/amethystora-manual" "${CONTROL_DIR}/amethystora-control"
# The translations' runtime (i18n.js), the Manual's own file, as Electron is
ln "${MANUAL_DIR}/resources/app/i18n.js" "${CONTROL_DIR}/resources/app/i18n.js"

install -Dpm0644 /ctx/branding/fonts/QuicksandVariable.ttf "${CONTROL_DIR}/resources/app/fonts/QuicksandVariable.ttf"
install -Dpm0644 /ctx/branding/fonts/Quicksand-OFL.txt "${LICENSE_DIR}/Quicksand-OFL.txt"

echo "::endgroup::"
