#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Amethystora Notes (amethystora-notes): notes and tasks, kept on the machine only and encrypted with a
# passphrase, in place of Joplin and Planify. The app (main.js, its page, script and stylesheet) comes
# from system_files and is already in place; this adds what it runs on, as 14-security.sh does for
# Security.
#
#   - Electron: the release 13-manual.sh installed and checked for the Manual, hard-linked rather than
#     copied, so that the image carries one Electron for every window and Renovate bumps one pin.
#   - marked, which renders the notes' Markdown: the Manual's copy, hard-linked for the same reason.
#   - Quicksand, the face of the Amethystora wordmark, which the window draws its sidebar in.
#
# The security key behind a passkey is spoken to through fido2-tools, which 04-packages.sh installs.

MANUAL_DIR=/usr/lib/amethystora-manual
NOTES_DIR=/usr/lib/amethystora-notes
LICENSE_DIR=/usr/share/licenses/amethystora-notes

# Everything beside the Manual's executable but its resources, which hold each window's own app
for entry in "${MANUAL_DIR}"/*; do
    case "$(basename "${entry}")" in
        amethystora-manual | resources) ;;
        *) cp -al "${entry}" "${NOTES_DIR}/" ;;
    esac
done
ln "${MANUAL_DIR}/amethystora-manual" "${NOTES_DIR}/amethystora-notes"
ln "${MANUAL_DIR}/resources/app/marked.umd.js" "${NOTES_DIR}/resources/app/marked.umd.js"
# The translations' runtime (i18n.js), the Manual's own file, as Electron is
ln "${MANUAL_DIR}/resources/app/i18n.js" "${NOTES_DIR}/resources/app/i18n.js"
install -Dpm0644 /usr/share/licenses/amethystora-manual/marked/LICENSE "${LICENSE_DIR}/marked/LICENSE"

install -Dpm0644 /ctx/branding/fonts/QuicksandVariable.ttf "${NOTES_DIR}/resources/app/fonts/QuicksandVariable.ttf"
install -Dpm0644 /ctx/branding/fonts/Quicksand-OFL.txt "${LICENSE_DIR}/Quicksand-OFL.txt"

echo "::endgroup::"
