#!/usr/bin/bash

set -eoux pipefail

echo "::group:: ===$(basename "$0")==="

# Install tooling
dnf5 -y install glib2-devel meson sassc cmake dbus-devel

# Build Extensions

# AppIndicator Support
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/appindicatorsupport@rgcjonas.gmail.com/schemas

# Bazaar Companion
mv /usr/share/gnome-shell/extensions/tmp/bazaar-integration@kolunmi.github.io/src/ /usr/share/gnome-shell/extensions/bazaar-integration@kolunmi.github.io/

# Blur My Shell
make -C /usr/share/gnome-shell/extensions/blur-my-shell@aunetx
unzip -o /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/build/blur-my-shell@aunetx.shell-extension.zip -d /usr/share/gnome-shell/extensions/blur-my-shell@aunetx
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas
rm -rf /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/build

# Caffeine
# The Caffeine extension is built/packaged into a temporary subdirectory (tmp/caffeine/caffeine@patapon.info).
# Unlike other extensions, it must be moved to the standard extensions directory so GNOME Shell can detect it.
mv /usr/share/gnome-shell/extensions/tmp/caffeine/caffeine@patapon.info /usr/share/gnome-shell/extensions/caffeine@patapon.info
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/caffeine@patapon.info/schemas

# Dash to Dock
make -C /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/schemas

# Gradia Capture
bash /usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/build.sh
unzip -o /usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/gradia-integration@alexandervanhee.github.io.shell-extension.zip -d /usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io
rm -f /usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/gradia-integration@alexandervanhee.github.io.shell-extension.zip
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/schemas

# GSConnect (commented out until G49 support)
meson setup --prefix=/usr /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/_build
meson install -C /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/_build --skip-subprojects
# GSConnect installs schemas to /usr/share/glib-2.0/schemas and meson compiles them automatically

# Logo Menu
# xdg-terminal-exec is required for this extension as it opens up terminals using that script
install -Dpm0755 -t /usr/bin /usr/share/gnome-shell/extensions/logomenu@aryan_k/distroshelf-helper
install -Dpm0755 -t /usr/bin /usr/share/gnome-shell/extensions/logomenu@aryan_k/missioncenter-helper
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/logomenu@aryan_k/schemas

# Search Light
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/search-light@icedman.github.com/schemas

# --- Extensions installed from extensions.gnome.org --------------------------------------------
#
# These four are not submodules. Tactile and Space Bar are TypeScript, so building them from source
# would pull npm and the npm registry into the image build; TopHat and Just Perfection are not in
# Fedora's repositories at all (only in updates-testing, which this build does not enable). The
# reviewed builds from extensions.gnome.org are used instead, each pinned to one upload.
#
# To update one: read the new upload id for this GNOME out of
# https://extensions.gnome.org/extension-info/?uuid=<uuid> and change its version and tag below.

BASE_OVERRIDE=/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override

install_ego_extension() {
    local uuid="$1" version="$2" version_tag="$3"
    local directory="/usr/share/gnome-shell/extensions/${uuid}"
    local archive="/tmp/${uuid}.zip"

    curl --fail --retry 3 --location --output "${archive}" \
        "https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}"
    mkdir -p "${directory}"
    unzip -o "${archive}" -d "${directory}"
    rm -f "${archive}"

    # The pin is an upload id, so check the upload really is this extension at this version, and
    # that it supports the GNOME in this image rather than failing silently at login
    jq -e --arg uuid "${uuid}" --argjson version "${version}" \
        '.uuid == $uuid and .version == $version' "${directory}/metadata.json"
    jq -e --arg shell "${GNOME_MAJOR}" '.["shell-version"] | index($shell)' "${directory}/metadata.json"

    # The Amethystora defaults for these live in zz1-amethystora-modifications.gschema.override,
    # and an override only applies to a schema installed system-wide
    install -Dpm0644 -t /usr/share/glib-2.0/schemas "${directory}"/schemas/*.gschema.xml
    glib-compile-schemas --strict "${directory}/schemas"

    # Enable it on top of whatever the base image enables, instead of restating that list and
    # going stale the next time the base image changes it
    sed -i "/^enabled-extensions/ s/\]/, '${uuid}'&/" "${BASE_OVERRIDE}"
    grep -q "'${uuid}'" "${BASE_OVERRIDE}"
}

GNOME_MAJOR="$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)"

# Tactile: keyboard-driven window tiling on a grid
install_ego_extension "tactile@lundal.io" 38 75027

# TopHat: CPU, memory and network meters in the panel. Their colour follows the theme, set by
# amethystora-theme.
install_ego_extension "tophat@fflewddur.github.io" 24 69837

# Just Perfection: the panel and animation tweaks in zz1-amethystora-modifications
install_ego_extension "just-perfection-desktop@just-perfection" 37 74466

# Space Bar: the i3-style workspace indicator that makes the six fixed workspaces visible.
# The only one of the four that needs a pin per GNOME: v34 is the last build for GNOME 49 and
# v39 the first for GNOME 50, so there is no single upload that covers both.
if ((GNOME_MAJOR >= 50)); then
    install_ego_extension "space-bar@luchrioh" 39 72977
else
    install_ego_extension "space-bar@luchrioh" 34 65181
fi

rm /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

# Cleanup
dnf5 -y remove glib2-devel meson sassc cmake dbus-devel
rm -rf /usr/share/gnome-shell/extensions/tmp

echo "::endgroup::"
