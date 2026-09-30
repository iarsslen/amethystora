#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# We do not need anything here at all
rm -rf /usr/src
rm -rf /usr/share/doc
# Remove kernel-devel from rpmdb because all package files are removed from /usr/src
rpm --erase --nodeps kernel-devel

# Starship Shell Prompt
ghcurl "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz" --retry 3 -o /tmp/starship.tar.gz
tar -xzf /tmp/starship.tar.gz -C /tmp
install -c -m 0755 /tmp/starship /usr/bin

# Remove desktop entries
if [[ -f /usr/share/applications/gnome-system-monitor.desktop ]]; then
    sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/gnome-system-monitor.desktop
fi
if [[ -f /usr/share/applications/org.gnome.SystemMonitor.desktop ]]; then
    sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/org.gnome.SystemMonitor.desktop
fi

# Add Mutter experimental-features
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    sed -i "/experimental-features/ s/\]/, 'kms-modifiers'&/" /usr/share/glib-2.0/schemas/zz0-amethystora-modifications.gschema.override
    echo "Compiling gschema to include the kms-modifiers override"
    glib-compile-schemas /usr/share/glib-2.0/schemas
fi

echo "::endgroup::"
