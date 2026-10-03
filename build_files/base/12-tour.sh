#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The picture on the first page of GNOME Tour.
#
# Fedora builds gnome-tour with a picture of its own in place of GNOME's, a backpack with Fedora's
# logo on it, compiled into the resource bundle the Tour reads all of its pictures from. An image
# built from Fedora carries none of Fedora's logos, so the bundle is unpacked, the picture swapped for
# Amethystora's, and the bundle built again, as 12-login-screen.sh does with GNOME Shell's theme.
# branding/generate.mjs draws the picture: the boot splash at the top of its glow.

GRESOURCE=/usr/share/gnome-tour/resources.gresource
WELCOME=/usr/share/amethystora/tour/welcome.svg
PREFIX=/org/gnome/Tour
WORK=/tmp/gnome-tour

test -s "${WELCOME}"
test -s "${GRESOURCE}"

# glib-compile-resources and gresource come from glib2-devel, which 12-login-screen.sh takes back
# out when it has finished with it
GLIB_DEVEL_ADDED=false
if ! command -v glib-compile-resources >/dev/null || ! command -v gresource >/dev/null; then
    dnf5 -y install glib2-devel
    GLIB_DEVEL_ADDED=true
fi

rm -rf "${WORK}"
mkdir -p "${WORK}"
mapfile -t RESOURCES < <(gresource list "${GRESOURCE}")
# The first page has to still ask for the picture by this name, or the one put here is never shown
printf '%s\n' "${RESOURCES[@]}" | grep -x "${PREFIX}/welcome.svg" >/dev/null
for resource in "${RESOURCES[@]}"; do
    file="${WORK}/${resource#"${PREFIX}/"}"
    mkdir -p "$(dirname "${file}")"
    gresource extract "${GRESOURCE}" "${resource}" >"${file}"
done
install -pm0644 "${WELCOME}" "${WORK}/welcome.svg"

# Rebuilt from what was unpacked, so the rest of the Tour's pictures and its interface come through
# untouched. The interface files were stripped of blanks when Fedora built the bundle, and come out so.
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<gresources>'
    echo "  <gresource prefix=\"${PREFIX}\">"
    (cd "${WORK}" && find . -type f ! -name '*.gresource.xml' -printf '%P\n' | sort) |
        while read -r file; do echo "    <file compressed=\"true\">${file}</file>"; done
    echo '  </gresource>'
    echo '</gresources>'
} >"${WORK}/gnome-tour.gresource.xml"

glib-compile-resources --sourcedir="${WORK}" --target="${GRESOURCE}" "${WORK}/gnome-tour.gresource.xml"

# The bundle has to still hold everything it held before, and the first page's picture has to be
# Amethystora's. Not grep -q: under pipefail the SIGPIPE it leaves gresource with fails the build.
for resource in "${RESOURCES[@]}"; do
    gresource list "${GRESOURCE}" | grep -x "${resource}" >/dev/null
done
gresource extract "${GRESOURCE}" "${PREFIX}/welcome.svg" | cmp -s - "${WELCOME}"

rm -rf "${WORK}"
if [[ "${GLIB_DEVEL_ADDED}" == true ]]; then
    dnf5 -y remove glib2-devel
fi

echo "::endgroup::"
