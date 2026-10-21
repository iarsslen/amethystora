#!/usr/bin/env bash

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script ip6-privacy-file system 1 || exit 0

set -x

# `ame security ipv6-privacy off` used to mask NetworkManager's file with a link to /dev/null, which
# NetworkManager refuses: it does not start, and the machine has no network. The switch now writes a file of
# the same name in its place; a machine turned off the old way gets that file, and NetworkManager is started
# again if this start already lost it.
CONF=/etc/NetworkManager/conf.d/30-amethystora-ip6-privacy.conf
[[ "$(readlink "${CONF}" 2>/dev/null)" == /dev/null ]] || exit 0
rm -f "${CONF}"
/usr/libexec/amethystora-hardening set ipv6-privacy off
systemctl is-active --quiet NetworkManager.service || { systemctl reset-failed NetworkManager.service; systemctl start NetworkManager.service; }
exit 0
