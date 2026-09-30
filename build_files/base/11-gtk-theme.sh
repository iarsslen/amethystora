#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The Amethystora GTK theme: EliverLara's Sweet, recoloured onto the amethyst palette.
#
# Sweet is by the author of candy-icons (10-icons.sh), which is why the two sit together without
# looking assembled. It ships its stylesheets already built, so nothing here needs sass, npm or the
# gulp pipeline the upstream repository uses.
#
# It is installed under Amethystora's own name rather than Sweet's, because what is installed is not
# Sweet: recolor.py rotates every cool colour in it onto the amethyst, which is most of the theme.
# Leaving the upstream name on a theme whose palette has been replaced would misattribute it.
#
# Only the amethystora and amethystora-light themes name this in their gtk.theme file. The others
# (nord, gruvbox, catppuccin and the rest) stay on adw-gtk3, which follows the GNOME accent colour
# and so goes on matching whatever palette they set, where a purple theme would fight them.

SWEET_REPO="https://github.com/EliverLara/Sweet"
# master as of 2026-08-13
SWEET_COMMIT="c405a6a73878ce3beb4323d26bc6fa674a485f36"
THEME_DIR=/usr/share/themes/Amethystora
WORK=/tmp/sweet

ghcurl "${SWEET_REPO}/archive/${SWEET_COMMIT}.tar.gz" --fail --retry 3 -o /tmp/sweet.tar.gz
mkdir -p "${WORK}"
tar -xzf /tmp/sweet.tar.gz -C "${WORK}" --strip-components=1
rm -f /tmp/sweet.tar.gz

# The tarball is not checksummed, so check it really is the theme before anything is installed
test -f "${WORK}/index.theme"
grep -qx "Name=Sweet" "${WORK}/index.theme"
test -s "${WORK}/gtk-4.0/gtk-dark.css"

# GPL-3.0: the licence travels with the stylesheets
install -Dpm0644 "${WORK}/LICENSE" /usr/share/licenses/amethystora-gtk-theme/LICENSE

# The stylesheets reference ../assets, so the three have to stay siblings. Everything else in the
# repository is for other desktops (Cinnamon, Xfwm, Metacity), the GNOME Shell theme, which needs
# the User Themes extension this image does not install, or the sources the CSS was built from.
mkdir -p "${THEME_DIR}"
cp -r "${WORK}/gtk-3.0" "${WORK}/gtk-4.0" "${WORK}/assets" "${THEME_DIR}/"
rm -rf "${THEME_DIR}"/gtk-[34].0/*.scss "${THEME_DIR}"/gtk-[34].0/widgets "${THEME_DIR}"/gtk-[34].0/apps
rm -rf "${WORK}"

cat >"${THEME_DIR}/index.theme" <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Amethystora
Comment=Sweet by EliverLara, recoloured onto the Amethystora amethyst palette
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Amethystora
IconTheme=candy-icons
ButtonLayout=:minimize,maximize,close
EOF

# Recolour. The window buttons are left out on purpose: Sweet draws them as the three coloured
# lights, and red, amber and green are the convention that says which one closes the window without
# reading the glyph. The green one is inside the band, so without this it would come out amethyst
# and leave the row with two lights that mean stop and one that means nothing.
mapfile -t STYLESHEETS < <(find "${THEME_DIR}" \( -name '*.css' -o -name '*.svg' \) \
    ! -name 'close*' ! -name 'min*' ! -name 'maximize*')
((${#STYLESHEETS[@]} >= 4))
python3 /ctx/build_files/shared/recolor.py "${STYLESHEETS[@]}"
python3 /ctx/build_files/shared/recolor.py --check "${THEME_DIR}"/gtk-3.0/*.css "${THEME_DIR}"/gtk-4.0/*.css

# The filled half of a switch is the one place Sweet puts an accent in the warm colours the default
# band spares, so it needs its own pass over the amber and yellow it is drawn in. Sparing those is
# right everywhere else - they are the warning and the caution light there, not branding - which is
# why this is two narrow files and a band of its own rather than a wider band for the whole theme.
SWITCHES=("${THEME_DIR}/assets/switch-on.svg" "${THEME_DIR}/assets/switch-on-insensitive.svg")
for switch in "${SWITCHES[@]}"; do
    test -s "${switch}"
done
python3 /ctx/build_files/shared/recolor.py --band 30:56 "${SWITCHES[@]}"
python3 /ctx/build_files/shared/recolor.py --band 30:56 --check "${SWITCHES[@]}"

# Sweet's teal is baked into the widget bitmaps as well - the tick in a checked checkbox, the filled
# half of a switch - so they need the same rotation the stylesheets just had. These carry the accent
# on top of neutral grey and nothing else, and grey has no hue to rotate, so turning the whole file
# is the same thing as turning only the accent in it.
#
# The hue is given in ImageMagick's own units, where 100 is no rotation and the scale runs over two
# turns, so a degree is 1/1.8 of a unit. 95 degrees is teal to amethyst, the same arc as above.
ACCENT_ROTATION=152.7
IMAGEMAGICK_ADDED=false
if ! command -v magick >/dev/null; then
    dnf5 -y install ImageMagick
    IMAGEMAGICK_ADDED=true
fi
ACCENT_ASSETS=(checkbox-checked radio-checked radio-selected selected- menuitem- calendar-selected
    grid-selection-checked qcheckbox-checked switch-slider-on switch-on scale-slider)
for prefix in "${ACCENT_ASSETS[@]}"; do
    for asset in "${THEME_DIR}/assets/${prefix}"*.png; do
        [[ -f "${asset}" ]] || continue
        magick "${asset}" -modulate 100,100,"${ACCENT_ROTATION}" "${asset}"
    done
done
# Only taken back out if this brought it in: removing something the image wanted would be worse
# than leaving a build tool behind
if [[ "${IMAGEMAGICK_ADDED}" == true ]]; then
    dnf5 -y remove ImageMagick
fi

test -s "${THEME_DIR}/gtk-4.0/gtk-dark.css"
test -s "${THEME_DIR}/gtk-3.0/gtk-dark.css"

echo "::endgroup::"
