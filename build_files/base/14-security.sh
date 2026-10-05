#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Amethystora Security (amethystora-security): the security report and a virus scanner, in a window of
# their own, in place of the report's terminal launcher and ClamUI. The app (main.js, its page, script
# and stylesheet) comes from system_files and is already in place; this adds what it runs on.
#
#   - Electron: the release 13-manual.sh installed and checked for the Manual, hard-linked rather than
#     copied, so that the image carries one Electron for both windows and Renovate bumps one pin.
#   - Quicksand, the face of the Amethystora wordmark, which the window draws its sidebar in. The image
#     has no system copy of it; the Containerfile brings branding/fonts into the build context.

MANUAL_DIR=/usr/lib/amethystora-manual
SECURITY_DIR=/usr/lib/amethystora-security
LICENSE_DIR=/usr/share/licenses/amethystora-security

# Everything beside the Manual's executable but its resources, which hold each window's own app
for entry in "${MANUAL_DIR}"/*; do
    case "$(basename "${entry}")" in
        amethystora-manual | resources) ;;
        *) cp -al "${entry}" "${SECURITY_DIR}/" ;;
    esac
done
ln "${MANUAL_DIR}/amethystora-manual" "${SECURITY_DIR}/amethystora-security"
# The translations' runtime (i18n.js), the Manual's own file, as Electron is
ln "${MANUAL_DIR}/resources/app/i18n.js" "${SECURITY_DIR}/resources/app/i18n.js"

install -Dpm0644 /ctx/branding/fonts/QuicksandVariable.ttf "${SECURITY_DIR}/resources/app/fonts/QuicksandVariable.ttf"
install -Dpm0644 /ctx/branding/fonts/Quicksand-OFL.txt "${LICENSE_DIR}/Quicksand-OFL.txt"

# Network protection (amethystora-ips.service, which the app reports on): Suricata's configuration,
# derived from the one this Suricata shipped with, so that it fits 7 and 8 alike. ips-config.py says
# what it changes. Its rules, which are ET Open, are downloaded on the machine, never built in.
python3 /ctx/build_files/shared/ips-config.py /etc/suricata/suricata.yaml /usr/share/amethystora/ips/suricata.yaml
chmod 0644 /usr/share/amethystora/ips/suricata.yaml

# What the report and the app permissions say (/usr/libexec/amethystora-security-status and
# amethystora-app-permissions), in the languages it has been translated into: po/<language>.po, compiled
# where gettext looks for the text domain amethystora. --check holds every translation to the values its
# English names. msgfmt is only needed here, so gettext's tools leave again unless something else in the
# image wanted them.
if ! command -v msgfmt >/dev/null; then
    dnf -y install gettext
    MSGFMT_INSTALLED=1
fi
for po in /ctx/po/*.po; do
    [[ -e "${po}" ]] || continue
    language="$(basename "${po}" .po)"
    install -d "/usr/share/locale/${language}/LC_MESSAGES"
    msgfmt --check --output-file="/usr/share/locale/${language}/LC_MESSAGES/amethystora.mo" "${po}"
done
if [[ -n "${MSGFMT_INSTALLED:-}" ]]; then
    dnf -y remove gettext
fi

echo "::endgroup::"
