#!/usr/bin/bash

set -eoux pipefail

# The rest of the build, after prepare.sh and the kernel (03-install-kernel-akmods.sh), each a step of
# its own in the Containerfile

mkdir -p /tmp/scripts/helpers
install -Dm0755 /ctx/build_files/shared/utils/ghcurl /tmp/scripts/helpers/ghcurl
export PATH="/tmp/scripts/helpers:$PATH"

# Install Additional Packages
/ctx/build_files/base/04-packages.sh

# Install Overrides and Fetch Install
/ctx/build_files/base/05-override-install.sh

# Amethystora Branding
/ctx/build_files/base/06-branding.sh

# Build GNOME Extensions from Git Submodules
/ctx/build_files/shared/build-gnome-extensions.sh

# The candy-icons icon theme
/ctx/build_files/base/10-icons.sh

# The Amethystora GTK theme, recoloured from Sweet by the same author as candy-icons
/ctx/build_files/base/11-gtk-theme.sh

# The login screen background, patched into GNOME Shell's own theme
/ctx/build_files/base/12-login-screen.sh

# GNOME Tour's first page, which Fedora builds with Fedora's logo on it
/ctx/build_files/base/12-tour.sh

# The Amethystora Manual: the runtime its window needs
/ctx/build_files/base/13-manual.sh

# Amethystora Security: the Manual's runtime, and the wordmark's font
/ctx/build_files/base/14-security.sh

# Amethystora Updates: the same
/ctx/build_files/base/15-update.sh

# Amethystora Notes: the same, and the Manual's Markdown renderer
/ctx/build_files/base/16-notes.sh

# Amethystora Logs: the same
/ctx/build_files/base/16-logs.sh

# Amethystora Backups: the same
/ctx/build_files/base/16-backups.sh

# Amethystora Control: the same
/ctx/build_files/base/16-control.sh

# Rename the remaining Universal Blue files, commands and services to Amethystora
/ctx/build_files/base/07-debrand.sh

# Signed updates, account lockout, firewall
/ctx/build_files/base/08-hardening.sh


## late stage changes

# Systemd and Remove Items
/ctx/build_files/base/17-cleanup.sh

# Run workarounds for lf (Likely not needed)
/ctx/build_files/base/18-workarounds.sh

# Regenerate initramfs
/ctx/build_files/base/19-initramfs.sh

if [ "${IMAGE_FLAVOR}" == "dx" ] ; then
  # Now we build DX!
  /ctx/build_files/shared/build-dx.sh
fi

# Where the source of every package in the image is published, for the GPL
/ctx/build_files/shared/source-manifest.sh

# Validate all repos are disabled before committing
/ctx/build_files/shared/validate-repos.sh

# Clean Up
echo "::group:: Cleanup"
/ctx/build_files/shared/clean-stage.sh

echo "::endgroup::"

# Simple Tests
/ctx/build_files/base/20-tests.sh
