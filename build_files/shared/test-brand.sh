#!/usr/bin/bash
# amethystora-brand (/usr/libexec/amethystora-brand, or the copy named first) against a stand-in for the image made
# of its own os-release and schemas, for 20-tests.sh: the name reaches os-release with ID=amethystora kept, the
# wallpaper and the logo reach GNOME's defaults and the Fedora names GDM and About read, and a folder with anything
# else, a name with Fedora's or a quote in it, a picture that is not what its name says, a link, or a login picture
# outside a build is refused before anything is written.

set -euo pipefail

BRAND="${1:-/usr/libexec/amethystora-brand}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
ROOT="${T}/root"
DIR="${T}/branding"
PNG=iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
JPEG=/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=

stand_in() {
    rm -rf "${ROOT}" "${DIR}"
    mkdir -p "${ROOT}/usr/lib" "${ROOT}/usr/share/glib-2.0" "${ROOT}/usr/share/pixmaps" "${DIR}"
    cp /usr/lib/os-release "${ROOT}/usr/lib/"
    cp -r /usr/share/glib-2.0/schemas "${ROOT}/usr/share/glib-2.0/"
    echo "Acme OS" >"${DIR}/name"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>\n' >"${DIR}/wallpaper.svg"
    base64 -d <<<"${PNG}" >"${DIR}/logo.png"
    echo "# Your branding" >"${DIR}/README.md"
}
image() { GSETTINGS_SCHEMA_DIR="${ROOT}/usr/share/glib-2.0/schemas" GSETTINGS_BACKEND=memory /usr/bin/gsettings get "$@"; }

stand_in
"${BRAND}" "${DIR}" --root "${ROOT}" >/dev/null
OS="${ROOT}/usr/lib/os-release"
grep -qx "ID=amethystora" "${OS}"
grep -qE '^PRETTY_NAME="Acme OS, built on Amethystora( \(Version: [^)]+\))?"$' "${OS}"
grep -qx 'VARIANT="Acme OS"' "${OS}"
grep -qx "VARIANT_ID=acme-os" "${OS}"
[[ "$(grep -c '^VARIANT' "${OS}")" == 2 ]]
# ...everything else as it was
diff <(grep -vE '^(PRETTY_NAME|VARIANT|VARIANT_ID)=' /usr/lib/os-release) <(grep -vE '^(PRETTY_NAME|VARIANT|VARIANT_ID)=' "${OS}")
URI="'file:///usr/share/amethystora/image-setup/backgrounds/wallpaper.svg'"
[[ "$(image org.gnome.desktop.background picture-uri)" == "${URI}" ]]
[[ "$(image org.gnome.desktop.background picture-uri-dark)" == "${URI}" ]]
[[ "$(image org.gnome.desktop.screensaver picture-uri)" == "${URI}" ]]
cmp -s "${DIR}/wallpaper.svg" "${ROOT}/usr/share/amethystora/image-setup/backgrounds/wallpaper.svg"
[[ "$(image org.gnome.login-screen logo)" == "'/usr/share/amethystora/image-setup/branding/logo.png'" ]]
for logo in fedora-logo-icon fedora-gdm-logo; do
    cmp -s "${DIR}/logo.png" "${ROOT}/usr/share/pixmaps/${logo}.png"
done
cmp -s "${DIR}/logo.png" "${ROOT}/usr/share/amethystora/image-setup/branding/logo.png"
# Run again with the name alone, it leaves no wallpaper or logo setting behind
rm "${DIR}/wallpaper.svg" "${DIR}/logo.png"
"${BRAND}" "${DIR}" --root "${ROOT}" >/dev/null
[[ ! -e "${ROOT}/usr/share/glib-2.0/schemas/zz3-image-branding.gschema.override" ]]
[[ "$(image org.gnome.desktop.background picture-uri)" != "${URI}" ]]
[[ "$(grep -c '^PRETTY_NAME=' "${OS}")" == 1 ]]
# The theme opens every theme on the image's wallpaper
grep -q 'IMAGE_BACKGROUNDS_DIR' /usr/bin/amethystora-theme
grep -qx 'IMAGE_BACKGROUNDS_DIR=/usr/share/amethystora/image-setup/backgrounds' /usr/lib/amethystora/theme/lib.sh

refused() {
    local why="$1"
    if "${BRAND}" "${DIR}" --root "${ROOT}" >/dev/null 2>&1; then
        echo "amethystora-brand took ${why}"
        exit 1
    fi
    cmp -s /usr/lib/os-release "${OS}" || { echo "amethystora-brand changed os-release for ${why}"; exit 1; }
    [[ ! -e "${ROOT}/usr/share/amethystora/image-setup" ]] || { echo "amethystora-brand wrote for ${why}"; exit 1; }
}
stand_in; echo "Fedora Remix" >"${DIR}/name"; refused "Fedora's name"
stand_in; echo 'Acme "OS"' >"${DIR}/name"; refused "a quote"
stand_in; printf 'Acme\nOS\n' >"${DIR}/name"; refused "two lines"
stand_in; base64 -d <<<"${JPEG}" >"${DIR}/logo.png"; refused "a JPEG named logo.png"
stand_in; echo "<script>" >"${DIR}/wallpaper.png"; refused "text named wallpaper.png"
stand_in; base64 -d <<<"${PNG}" >"${DIR}/wallpaper.jpg"; cp "${DIR}/wallpaper.jpg" "${DIR}/wallpaper.png"; refused "two wallpapers"
stand_in; rm "${DIR}/logo.png"; ln -s /usr/share/pixmaps/amethystora-logo-512.png "${DIR}/logo.png"; refused "a link"
stand_in; echo x >"${DIR}/build.sh"; refused "a script"
stand_in; base64 -d <<<"${PNG}" >"${DIR}/login.png"; refused "a login picture outside a build"
echo "amethystora-brand: ok"
