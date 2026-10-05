#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Rename everything the upstream layers (the ublue-os base image, ublue-os/brew and the ublue COPR
# packages) ship as Universal Blue to Amethystora: paths, commands, services, settings and text.
# Runs after 06-branding.sh, which needs the Logo Menu's upstream file names.
# Amethystora's own files in system_files already use the final names and win over upstream ones.
python3 /ctx/build_files/shared/debrand.py

# Rebuild the compiled settings and caches from the renamed sources
glib-compile-schemas /usr/share/glib-2.0/schemas
if command -v dconf >/dev/null; then
    dconf update
fi
if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor
fi

echo "::endgroup::"
