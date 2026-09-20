#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The login screen's background.
#
# GNOME takes it from exactly one place: the #lockDialogGroup rule in GNOME Shell's own stylesheet,
# which ships compiled into gnome-shell-theme.gresource. There is no setting for it and no drop-in
# directory, so the bundle is unpacked, the rule appended, and the bundle built again.
#
# The usual objection to doing this is that the next gnome-shell update overwrites it. That is an
# objection to doing it on a running system: here the image is rebuilt from scratch, so an update to
# gnome-shell means this script runs again on the new stylesheet rather than being undone by it.
#
# The picture itself is the sky the boot splash ends on, blurred and without the gem, so the
# handover from Plymouth to GDM is one picture carried across. branding/generate.mjs draws it.

GRESOURCE=/usr/share/gnome-shell/gnome-shell-theme.gresource
BACKGROUND=/usr/share/backgrounds/amethystora/amethystora-login.png
PREFIX=/org/gnome/shell/theme
WORK=/tmp/shell-theme

test -s "${BACKGROUND}"
test -s "${GRESOURCE}"

# glib-compile-resources and gresource both come from glib2-devel, which build-gnome-extensions.sh
# takes back out when it has finished with it. Neither is in glib2 itself, so both have to be
# brought back before the bundle can be read or written.
GLIB_DEVEL_ADDED=false
if ! command -v glib-compile-resources >/dev/null || ! command -v gresource >/dev/null; then
    dnf5 -y install glib2-devel
    GLIB_DEVEL_ADDED=true
fi

rm -rf "${WORK}"
mkdir -p "${WORK}"
mapfile -t RESOURCES < <(gresource list "${GRESOURCE}")
# The stock bundle holds the three stylesheets and a handful of images. Far fewer than that means
# gresource read something other than the theme, and the rebuilt bundle would drop what it missed.
((${#RESOURCES[@]} >= 4))
for resource in "${RESOURCES[@]}"; do
    file="${WORK}/${resource#"${PREFIX}/"}"
    mkdir -p "$(dirname "${file}")"
    gresource extract "${GRESOURCE}" "${resource}" >"${file}"
done

# The background travels inside the bundle, so the stylesheet can name it the way the shell names
# its own artwork: a relative URL, which St resolves against the stylesheet's place in the bundle.
install -Dpm0644 "${BACKGROUND}" "${WORK}/amethystora-login.png"

# Both stylesheets, because the greeter follows the colour scheme and either can be the one in use.
# The rule is appended rather than substituted for the upstream one: the last rule of the same
# specificity is the one that applies, and leaving theirs in place keeps the change to one block at
# the end of the file, where a diff against stock gnome-shell shows it whole.
for stylesheet in "${WORK}/gnome-shell-dark.css" "${WORK}/gnome-shell-light.css"; do
    test -s "${stylesheet}"
    # If the selector has gone, the rule below would be styling nothing at all
    grep -q "lockDialogGroup" "${stylesheet}"
    cat >>"${stylesheet}" <<'EOF'

/* Amethystora: the login screen background (build_files/base/12-login-screen.sh) */
#lockDialogGroup {
  background-image: url("amethystora-login.png");
  background-size: cover;
}
EOF
done

# Rebuilt from what was unpacked plus the one file added, so anything the bundle held that this
# script has no opinion about is carried over untouched
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<gresources>'
    echo "  <gresource prefix=\"${PREFIX}\">"
    (cd "${WORK}" && find . -type f ! -name '*.gresource.xml' -printf '%P\n' | sort) |
        while read -r file; do echo "    <file>${file}</file>"; done
    echo '  </gresource>'
    echo '</gresources>'
} >"${WORK}/gnome-shell-theme.gresource.xml"

glib-compile-resources --sourcedir="${WORK}" --target="${GRESOURCE}" \
    "${WORK}/gnome-shell-theme.gresource.xml"

# The bundle has to still hold everything it held before, plus the background, and the stylesheets
# have to have come through with the rule in them
gresource list "${GRESOURCE}" | grep -qx "${PREFIX}/amethystora-login.png"
for resource in "${RESOURCES[@]}"; do
    gresource list "${GRESOURCE}" | grep -qx "${resource}"
done
for variant in dark light; do
    gresource extract "${GRESOURCE}" "${PREFIX}/gnome-shell-${variant}.css" |
        grep -q 'background-image: url("amethystora-login.png")'
done

rm -rf "${WORK}"
if [[ "${GLIB_DEVEL_ADDED}" == true ]]; then
    dnf5 -y remove glib2-devel
fi

echo "::endgroup::"
