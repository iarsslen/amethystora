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

# Blur My Shell
make -C /usr/share/gnome-shell/extensions/blur-my-shell@aunetx
unzip -o /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/build/blur-my-shell@aunetx.shell-extension.zip -d /usr/share/gnome-shell/extensions/blur-my-shell@aunetx
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas
rm -rf /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/build

# Blur my Shell carries the whole Tahoe glass look (the defaults are in
# /etc/dconf/db/distro.d/05-blur-my-shell-extension), so it is on out of the box rather than
# something to go and find in Extension Manager
enable_extension "blur-my-shell@aunetx"

# Dash to Dock
make -C /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/schemas
# Its defaults are the image's, in zz0-amethystora-modifications: installed system-wide too, as for the
# extensions below, so that gsettings and the tests read what the dock does
install -Dpm0644 -t /usr/share/glib-2.0/schemas \
    /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/schemas/*.gschema.xml

# GSConnect (commented out until G49 support)
meson setup --prefix=/usr /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/_build
meson install -C /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/_build --skip-subprojects
# GSConnect installs schemas to /usr/share/glib-2.0/schemas and meson compiles them automatically

# Amethystora Transitions: written for this image, so it is in system_files rather than a submodule,
# and under the image's own licence. Its schema is installed system-wide from there too, so that
# gsettings and ame desktop transition reach it; the compile at the end picks it up.
install -Dpm0644 /usr/share/licenses/amethystora/LICENSE /usr/share/licenses/amethystora-transitions@iarsslen.github.io/LICENSE
enable_extension "amethystora-transitions@iarsslen.github.io"

# Amethystora Widgets: the top bar's widgets from ~/.config/amethystora/widgets (amethystora-widgets).
# Written for this image too, in system_files and under the image's licence. It has no settings.
install -Dpm0644 /usr/share/licenses/amethystora/LICENSE /usr/share/licenses/amethystora-widgets@iarsslen.github.io/LICENSE
enable_extension "amethystora-widgets@iarsslen.github.io"

# Amethystora Clipboard: the clipboard history on Super+Shift+V. A copy of Clipboard Indicator v71 (MIT, by
# Yotam Bar-On and its contributors, https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator at
# c880c7fb88dc7232a61a5864d125989a4f375daa) that seals its history with /usr/libexec/amethystora-clipboard-seal
# (built in the apps stage) instead of writing it to ~/.cache in plain text. In system_files with upstream's
# LICENSE.rst; its schema is system-wide, and 14-security.sh compiles its translations (po/amethystora-clipboard).
enable_extension "amethystora-clipboard@iarsslen.github.io"

# Amethystora Logo Menu: the gem at the left of the top bar and its menu of the system's tools. Written for this
# image, in system_files and under the image's licence, with no settings; its labels are in po/ (domain amethystora).
install -Dpm0644 /usr/share/licenses/amethystora/LICENSE /usr/share/licenses/amethystora-logo-menu@iarsslen.github.io/LICENSE
enable_extension "amethystora-logo-menu@iarsslen.github.io"

# Amethystora UI: the desktop's own modules, each written for this image in place of a third-party extension
# (plans/PLAN-amethystora-ui.md), in system_files and under the image's licence. A module's keys are in its own
# schema in the extension's schemas folder, installed system-wide too so that gsettings, ame and the overrides reach
# them; the loop below compiles them with the overrides.
UI_EXTENSION=/usr/share/gnome-shell/extensions/amethystora-ui@iarsslen.github.io
install -Dpm0644 /usr/share/licenses/amethystora/LICENSE /usr/share/licenses/amethystora-ui@iarsslen.github.io/LICENSE
if compgen -G "${UI_EXTENSION}/schemas/*.gschema.xml" >/dev/null; then
    install -Dpm0644 -t /usr/share/glib-2.0/schemas "${UI_EXTENSION}"/schemas/*.gschema.xml
fi
enable_extension "amethystora-ui@iarsslen.github.io"

# --- Extensions installed from extensions.gnome.org --------------------------------------------
#
# Not a submodule: PaperWM needs no build step, and comes from there: the reviewed build from
# extensions.gnome.org, pinned to one upload and to the SHA-256 of its zip, which extensions.gnome.org
# does not sign.
#
# To update one: read the new upload id for this GNOME out of
# https://extensions.gnome.org/extension-info/?uuid=<uuid>, download that upload and change its
# version, tag and SHA-256 below.

install_ego_extension() {
    local uuid="$1" version="$2" version_tag="$3" sha256="$4"
    local directory="/usr/share/gnome-shell/extensions/${uuid}"
    local archive="/tmp/${uuid}.zip"

    curl --fail --retry 3 --location --output "${archive}" \
        "https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}"
    echo "${sha256}  ${archive}" | sha256sum -c -
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
    # and an override only applies to a schema installed system-wide (and to the extension's own
    # copy, below).
    if [[ -d "${directory}/schemas" ]]; then
        install -Dpm0644 -t /usr/share/glib-2.0/schemas "${directory}"/schemas/*.gschema.xml
        glib-compile-schemas --strict "${directory}/schemas"
    fi

    enable_extension "${uuid}"
}

GNOME_MAJOR="$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)"

# PaperWM: scrollable tiling. Windows open side by side on a strip wider than the screen, and the
# keyboard moves along it. Its keymap is fitted around the image's in zz1-amethystora-modifications.
install_ego_extension "paperwm@paperwm.github.com" 148 70147 \
    2cef72ed7e31df4962584b52dabda9246c0ae81973b05f8d1202d9dbe9a3f794


# GNOME Shell's getSettings() reads an extension's own compiled schemas before the system's, and the
# overrides in /usr/share/glib-2.0/schemas never reach those: without this, every extension above ran
# on its own defaults. So each one's schemas are compiled again with its sections of zz0- and
# zz1-amethystora-modifications, strictly, so that a key it no longer has fails the build rather than
# being dropped without a word.
for schemas in /usr/share/gnome-shell/extensions/*/schemas; do
    # Some schema files spread a tag over several lines
    ids="$(cat "${schemas}"/*.gschema.xml | tr -s '[:space:]' ' ' | grep -oE '<schema [^>]*id="[^"]+"' |
        sed -E 's/.*id="([^"]+)".*/\1/' | tr '\n' ' ')"
    awk -v ids="${ids}" 'BEGIN { n = split(ids, list, " "); for (i = 1; i <= n; i++) own["[" list[i] "]"] = 1 }
        /^\[/ { keep = ($0 in own) } keep' \
        /usr/share/glib-2.0/schemas/zz0-amethystora-modifications.gschema.override \
        /usr/share/glib-2.0/schemas/zz1-amethystora-modifications.gschema.override \
        >"${schemas}/zz-amethystora-modifications.gschema.override"
    glib-compile-schemas --strict "${schemas}"
    rm "${schemas}/zz-amethystora-modifications.gschema.override"
done

rm /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

# Cleanup
dnf5 -y remove glib2-devel meson sassc cmake dbus-devel
rm -rf /usr/share/gnome-shell/extensions/tmp

echo "::endgroup::"
