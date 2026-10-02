#!/usr/bin/bash

set -eoux pipefail

echo "::group:: ===$(basename "$0")==="

# Install tooling
dnf5 -y install glib2-devel meson sassc cmake dbus-devel

# Each extension installed below is added to the enabled-extensions list in zz0-amethystora-modifications,
# so that installing one is enough to have it on. Adding one that is already in the list would enable
# it twice, so this only appends when it is absent - and fails if there is no list to append to,
# rather than leaving an extension built into the image but off.
BASE_OVERRIDE=/usr/share/glib-2.0/schemas/zz0-amethystora-modifications.gschema.override

enable_extension() {
    local uuid="$1"
    grep -q "'${uuid}'" "${BASE_OVERRIDE}" ||
        sed -i "/^enabled-extensions/ s/\]/, '${uuid}'&/" "${BASE_OVERRIDE}"
    grep -q "'${uuid}'" "${BASE_OVERRIDE}"
}

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

# Blur my Shell carries the whole Tahoe glass look (the defaults are in
# /etc/dconf/db/distro.d/05-blur-my-shell-extension), so it is on out of the box rather than
# something to go and find in Extension Manager
enable_extension "blur-my-shell@aunetx"

# Caffeine
# The Caffeine extension is built/packaged into a temporary subdirectory (tmp/caffeine/caffeine@patapon.info).
# Unlike other extensions, it must be moved to the standard extensions directory so GNOME Shell can detect it.
mv /usr/share/gnome-shell/extensions/tmp/caffeine/caffeine@patapon.info /usr/share/gnome-shell/extensions/caffeine@patapon.info
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/caffeine@patapon.info/schemas
# GPL-2.0: the licence sits at the root of the repository, which the cleanup below removes
install -Dpm0644 /usr/share/gnome-shell/extensions/tmp/caffeine/COPYING /usr/share/licenses/caffeine@patapon.info/COPYING

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
# These are not submodules. Space Bar is TypeScript, so building it from source would pull npm and
# the npm registry into the image build; TopHat and Just Perfection are not in Fedora's repositories
# at all (only in updates-testing, which this build does not enable). The reviewed builds from
# extensions.gnome.org are used instead, each pinned to one upload. PaperWM, Clipboard Indicator and
# Fuzzy App Search need no build step, but come from there too, pinned and checked the same way.
#
# To update one: read the new upload id for this GNOME out of
# https://extensions.gnome.org/extension-info/?uuid=<uuid> and change its version and tag below.

install_ego_extension() {
    local uuid="$1" version="$2" version_tag="$3"
    local directory="/usr/share/gnome-shell/extensions/${uuid}"
    local archive="/tmp/${uuid}.zip"

    curl --fail --retry 3 --location --output "${archive}" \
        "https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}"
    mkdir -p "${directory}"
    unzip -o "${archive}" -d "${directory}"
    rm -f "${archive}"

    # extensions.gnome.org rewrites metadata.json when it builds a download, and stores it in the
    # zip as 0600. unzip honours that, so it lands on the image readable by root only. Everything
    # here runs as root and sees a perfectly good extension, while the session does not: GNOME
    # Shell reads metadata.json as the logged-in user, finds nothing it may open, and the extension
    # is absent from the shell and from Extension Manager rather than listed as broken.
    chmod -R u=rwX,go=rX "${directory}"

    # The pin is an upload id, so check the upload really is this extension at this version, and
    # that it supports the GNOME in this image rather than failing silently at login
    jq -e --arg uuid "${uuid}" --argjson version "${version}" \
        '.uuid == $uuid and .version == $version' "${directory}/metadata.json"
    jq -e --arg shell "${GNOME_MAJOR}" '.["shell-version"] | index($shell)' "${directory}/metadata.json"

    # The Amethystora defaults for these live in zz1-amethystora-modifications.gschema.override,
    # and an override only applies to a schema installed system-wide. Fuzzy App Search has no
    # settings, so no schema.
    if [[ -d "${directory}/schemas" ]]; then
        install -Dpm0644 -t /usr/share/glib-2.0/schemas "${directory}"/schemas/*.gschema.xml
        glib-compile-schemas --strict "${directory}/schemas"
    fi

    enable_extension "${uuid}"
}

GNOME_MAJOR="$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)"

# PaperWM: scrollable tiling. Windows open side by side on a strip wider than the screen, and the
# keyboard moves along it. Its keymap is fitted around the image's in zz1-amethystora-modifications.
install_ego_extension "paperwm@paperwm.github.com" 148 70147

# Clipboard Indicator: the clipboard history in the panel, on Super+Shift+V
install_ego_extension "clipboard-indicator@tudmotu.com" 71 70694

# GNOME Fuzzy App Search: app search that forgives typos, in the overview and in Search Light
install_ego_extension "gnome-fuzzy-app-search@gnome-shell-extensions.Czarlie.gitlab.com" 28 70194

# TopHat: CPU, memory and network meters in the panel. Their colour follows the theme, set by
# amethystora-theme.
install_ego_extension "tophat@fflewddur.github.io" 24 69837

# Just Perfection: the panel and animation tweaks in zz1-amethystora-modifications
install_ego_extension "just-perfection-desktop@just-perfection" 37 74466

# Space Bar: the i3-style workspace indicator that makes the six fixed workspaces visible.
# The only one of these that needs a pin per GNOME: v34 is the last build for GNOME 49 and
# v39 the first for GNOME 50, so there is no single upload that covers both.
if ((GNOME_MAJOR >= 50)); then
    install_ego_extension "space-bar@luchrioh" 39 72977
else
    install_ego_extension "space-bar@luchrioh" 34 65181
fi
# Its upload carries no licence file. It began as a fork of Workspaces Bar by Francois Thirioux, whose
# source says "License GPL v3", so that is the licence it comes under, and the text goes with it
install -Dpm0644 /usr/share/licenses/gnome-fuzzy-app-search@gnome-shell-extensions.Czarlie.gitlab.com/LICENSE \
    /usr/share/licenses/space-bar@luchrioh/LICENSE

rm /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

# Cleanup
dnf5 -y remove glib2-devel meson sassc cmake dbus-devel
rm -rf /usr/share/gnome-shell/extensions/tmp

echo "::endgroup::"
