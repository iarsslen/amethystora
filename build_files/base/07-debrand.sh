#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Rename everything the upstream layers ship as Bluefin / Universal Blue to Amethystora: paths, commands,
# services, settings and text. Runs after 06-branding.sh, which needs the upstream paths.
# Amethystora's own files in system_files already use the final names and win over upstream ones.

# Terminal banner and message-of-the-day (uwelcome, umotd): their Bluefin messages are compiled in.
# New terminals show the Amethystora fastfetch instead (/etc/profile.d/amethystora-greeting.sh).
rm -f /usr/bin/uwelcome /usr/bin/umotd /etc/profile.d/uwelcome.sh /etc/ublue-os/tags.json
rm -rf /etc/uwelcome
# The older glow banner (ublue-os-just's user-motd.sh running ublue-motd). Its image, commands, tip
# and links are in the greeting now, drawn in a style that reads on a dark terminal, which this one's
# glow fell back from; its tips stay, and the greeting picks one of them.
rm -f /etc/profile.d/user-motd.sh /usr/libexec/ublue-motd /etc/user-motd

# Bazaar: the curated page with the Bluefin banners and the hooks that redirect IDE installs to the
# Universal Blue Homebrew tap. Amethystora's bazaar.yaml uses neither.
rm -f /etc/bazaar/curated.yaml /etc/bazaar/hooks.py /etc/bazaar/*.png /etc/bazaar/*.jxl /usr/libexec/bazaar-hook

# Bluefin's administrator guide
rm -rf /usr/share/doc/bluefin

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
