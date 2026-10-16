#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# What Amethystora Security (amethystora-security) reports on and in, beside its window, which 13-apps.sh
# installs with the other apps.

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
