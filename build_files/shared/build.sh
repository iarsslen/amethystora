#!/usr/bin/bash

set -eoux pipefail

echo "::group:: Copy Files"

# Speeds up local builds
dnf config-manager setopt keepcache=1

# The base image's ujust, setup, signing, udev and update packages. system_files carries the image's own
# versions of the same files, which a later `dnf remove` would take away with the packages
dnf remove -y ublue-os-luks ublue-os-just ublue-os-udev-rules ublue-os-signing ublue-os-update-services

# Keep *-logos in RPM DB for downstream package installations
# We are not allowed to ship an empty fedora-logos package
dnf -y swap fedora-logos generic-logos
rpm --erase --nodeps --nodb generic-logos
# httpd's test page logos too: Fedora's trademark guidelines keep its logos out of a remix, and
# generic-logos-httpd provides the same system-logos-httpd that httpd requires
if rpm -q fedora-logos-httpd >/dev/null; then
    dnf -y swap fedora-logos-httpd generic-logos-httpd
fi
# The release packages go the same way: the guidelines name fedora-release beside fedora-logos, and
# Fedora ships generic-release to stand in for it. Only the package database changes hands. The files
# stay where they are: os-release is rewritten for this image by 00-image-info.sh, which also takes
# Fedora's name out of the rest, and the presets, the dist macros and rpm-ostree's polkit rules that
# came with Fedora's packages are what the system is built on.
readarray -t FEDORA_RELEASE < <(rpm -qa --queryformat '%{NAME}\n' 'fedora-release*')
((${#FEDORA_RELEASE[@]}))
mkdir -p /tmp/generic-release
dnf -y download --destdir=/tmp/generic-release generic-release generic-release-common
rpm --erase --justdb --nodeps --noscripts --notriggers "${FEDORA_RELEASE[@]}"
rpm --install --justdb --nodeps --noscripts --notriggers /tmp/generic-release/generic-release-*.rpm
rm -rf /tmp/generic-release
# What needs a release package still finds one, and dnf still knows which Fedora this is built on
rpm -q --whatprovides system-release "system-release($(rpm -E %fedora))"

# Copy Files to Container
rsync -rvK /ctx/system_files/shared/ /

mkdir -p /tmp/scripts/helpers
install -Dm0755 /ctx/build_files/shared/utils/ghcurl /tmp/scripts/helpers/ghcurl
export PATH="/tmp/scripts/helpers:$PATH"

echo "::endgroup::"

# Generate image-info.json
/ctx/build_files/base/00-image-info.sh

# Install Kernel and Akmods
/ctx/build_files/base/03-install-kernel-akmods.sh

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
