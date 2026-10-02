#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# candy-icons, the gradient icon theme the desktop starts with, from a pinned upstream commit.
#
# Fedora's candy-icon-theme package is not used: it hard-requires breeze-icon-theme, which nothing
# else on a GNOME image wants, and it installs the theme as "Candy" rather than under its own name.
#
# Five changes are made to the upstream tree, the first three because the pack is written for Plasma:
#
#   - Inherits drops breeze-dark. Upstream looks there first for everything it does not draw
#     itself, which on this image would mean a KDE glyph wherever candy-icons has a gap, instead
#     of the Adwaita one the rest of the desktop uses.
#
#   - the *-symbolic names outside places/ are symlinks to the full-colour gradient art, not
#     symbolic icons, so GTK's recolouring has nothing to act on: the panel would carry gradient
#     battery and network glyphs that ignore the foreground colour amethystora-theme sets. They
#     are dropped, so the shell falls back to Adwaita's real symbolics. The ones in places/ stay,
#     because the colourful folders in the Nautilus sidebar are the point of the pack.
#
#   - the apps this image ships that upstream has no icon for are aliased to the nearest one it
#     does have, so the dash does not mix two icon styles.
#
#   - where there is no near enough neighbour to alias to, the icon is drawn for this image in the
#     pack's own style and installed from build_files/shared/candy-icons.
#
#   - nobody else's logo is redrawn. The pack draws some 800 applications, most of them as their
#     maker's logo in its own gradients, and a logo is a trademark whose owner decides how it looks:
#     Mozilla, JetBrains, Anthropic and the rest allow theirs unaltered or not at all. So of the
#     application icons only the drawings named in build_files/shared/candy-icons/keep stay, the
#     pictograms of a job rather than of a product, and an application whose logo the pack redrew
#     shows the icon it brought with it, from hicolor. A name that links to a pictogram stays: that
#     is a generic icon, not anybody's mark. The logos the pack puts on folders, file types and
#     status icons go as well. Do not alias an application to another maker's logo, and do not draw
#     one for this image.

CANDY_REPO="https://github.com/EliverLara/candy-icons"
# master as of 2026-03-06; bump together with the alias targets below
CANDY_COMMIT="83512fbcadcb7e1015ebbe1729a1894946b021be"
CANDY_DIR="/usr/share/icons/candy-icons"

ghcurl "${CANDY_REPO}/archive/${CANDY_COMMIT}.tar.gz" --fail --retry 3 -o /tmp/candy-icons.tar.gz
mkdir -p "${CANDY_DIR}"
tar -xzf /tmp/candy-icons.tar.gz -C "${CANDY_DIR}" --strip-components=1
rm -f /tmp/candy-icons.tar.gz

# The tarball is not checksummed, so check it really is the icon theme before anything is deleted
test -f "${CANDY_DIR}/index.theme"
grep -qx "Name=candy-icons" "${CANDY_DIR}/index.theme"
(($(find "${CANDY_DIR}/apps/scalable" -name '*.svg' | wc -l) > 2000))

# GPL-3.0: the licence travels with the artwork
install -Dpm0644 "${CANDY_DIR}/LICENSE" /usr/share/licenses/candy-icons/LICENSE
rm -rf "${CANDY_DIR}/preview" "${CANDY_DIR}/.github" "${CANDY_DIR}/README.md" "${CANDY_DIR}/LICENSE"

sed -i 's|^Inherits=.*|Inherits=Adwaita,hicolor|' "${CANDY_DIR}/index.theme"
grep -qx "Inherits=Adwaita,hicolor" "${CANDY_DIR}/index.theme"

find "${CANDY_DIR}"/{apps,devices,mimetypes,preferences,status} \
    -type l -name '*-symbolic.svg' -delete
[[ -z "$(find "${CANDY_DIR}"/{apps,devices,mimetypes,preferences,status} -type l -name '*-symbolic.svg')" ]]

# Nobody else's logo: of the application icons, only the drawings on the keep list stay. A name on
# the list that upstream has dropped leaves the two counts apart, which fails the build here rather
# than leaving an application without its icon.
CANDY_KEEP=/ctx/build_files/shared/candy-icons/keep
(
    cd "${CANDY_DIR}/apps/scalable"
    find . -maxdepth 1 -type f -printf '%f\n' |
        grep -vxFf <(sed -e '/^#/d' -e '/^$/d' -e 's/$/.svg/' "${CANDY_KEEP}") |
        xargs -d '\n' rm --
)
(($(find "${CANDY_DIR}/apps/scalable" -type f | wc -l) == $(grep -cv -e '^#' -e '^$' "${CANDY_KEEP}")))

# The same for the logos the pack puts on folders, file types, settings and status icons: Android,
# Blender, Debian, Docker, Flatpak, Google Drive, GitHub, Godot, Java, Snap, Windows and KDE on the
# folders; Adobe's PDF, Anki, Deluge, Debian, Plasma and the languages' own marks on the file types;
# Bluetooth and Cloudflare on the status icons. A file of one of those types takes the pack's
# generic icon of its kind instead. One that upstream has dropped fails the build, to be taken off.
CANDY_LOGOS=(
    places/48/folder-{android,blender,deb,docker,flatpak,gdrive,git,godot,java,snap,windows}
    places/48/start-here-kde{,-plasma}
    places/16/folder-gdrive
    mimetypes/scalable/application-{pdf,x-anki,x-bittorrent,x-deb,x-plasma,x-ruby}
    mimetypes/scalable/text-{julia,r,x-csharp,x-css,x-emacs-lisp,x-go,x-java,x-julia,x-python,x-rust,x-sass}
    preferences/scalable/preferences-desktop-plasma{,-theme}
    status/scalable/network-bluetooth{,-activated,-activated-locked,-inactive-symbolic}
    status/scalable/network-wireless-bluetooth-symbolic
    status/scalable/zero-trust{,-connected,-disconnected,-error}
)
for logo in "${CANDY_LOGOS[@]}"; do
    rm "${CANDY_DIR}/${logo}.svg"
done

# Every name that linked to a drawing that has gone goes with it, and so do upstream's links into
# breeze-dark, which this image does not have
find "${CANDY_DIR}" -xtype l -delete
[[ -z "$(find "${CANDY_DIR}" -xtype l)" ]]

# Icons drawn for this image, for applications the pack has no artwork for and nothing near enough to
# alias to. They go in before the aliases below, so the loop's check that a target exists covers these
# too, and so an icon upstream adds later simply replaces the file of the same name.
for icon in /ctx/build_files/shared/candy-icons/*.svg; do
    install -Dpm0644 "${icon}" "${CANDY_DIR}/apps/scalable/$(basename "${icon}")"
done

# The Security and Notes apps' launchers are the drawn icons that a launcher of this image names.
# Unlike the three that 06-branding.sh points at, they have no Amethystora artwork in hicolor to fall
# back to, so without this they would exist only under candy-icons and the launchers would go blank
# under any other icon theme, an account set up before candy-icons that still holds its old theme
# included. hicolor's cache is rebuilt by 07-debrand.sh, which runs after this.
for icon in amethystora-security-status amethystora-notes; do
    install -Dpm0644 "/ctx/build_files/shared/candy-icons/${icon}.svg" "/usr/share/icons/hicolor/scalable/apps/${icon}.svg"
done

# alias:icon, where the icon is one upstream ships or one installed just above. An alias whose icon
# upstream has since added is left alone, and a target that has gone away fails the build rather
# than silently leaving the app without an icon.
CANDY_ALIASES=(
    # Ptyxis, kept as the fallback terminal
    "org.gnome.Ptyxis:org.gnome.Terminal.svg"
    # Papers is Evince's successor
    "org.gnome.Papers:org.gnome.Evince.svg"
    # Extension Manager does the job of GNOME's own Extensions app
    "com.mattjakeman.ExtensionManager:org.gnome.Extensions.svg"
    # Gradia annotates screenshots
    "be.alexandervanhee.gradia:org.gnome.Screenshot.svg"
    # Parental Controls (malcontent) restricts what an account may run
    "org.freedesktop.MalcontentControl:preferences-desktop-user-password.svg"
    # Smile picks emoji, as the character map does
    "it.mijorus.smile:org.gnome.Characters.svg"
    # Decibels is the audio player
    "org.gnome.Decibels:audio-player.svg"
    # Tour is the welcome walkthrough
    "org.gnome.Tour:applications-education.svg"
    # Warehouse manages the installed Flatpaks
    "io.github.flattool.Warehouse:software-manager.svg"
    # Refine tweaks GNOME's settings, as GNOME Tweaks does. The pack's icon for both is the Nintendo
    # Switch logo, which is not on the keep list, so they take its sliders from the settings icons.
    "page.tesk.Refine:../../preferences/scalable/preferences.svg"
    "org.gnome.tweaks:../../preferences/scalable/preferences.svg"
    # Ignition edits what starts at login
    "io.github.flattool.Ignition:preferences-system.svg"
    # Impression writes disk images to USB sticks
    "io.gitlab.adhami3310.Impression:usb-creator-gtk.svg"
    # Input Remapper remaps keys and buttons
    "input-remapper:preferences-desktop-keyboard.svg"
    # DistroShelf installs a distribution into a Distrobox container
    "com.ranfdev.DistroShelf:system-software-install.svg"
    # Sysprof is the one application the dx image adds that the pack has no icon for. VSCodium,
    # virt-manager and Remote Viewer (Icon=virt-viewer) are all drawn upstream, and the rest of dx
    # is command line tools and daemons with no launcher to put an icon on. A profiler is a system
    # monitor that keeps the recording, so it takes the generic monitor rather than GNOME's own,
    # which System Monitor is already using.
    "org.gnome.Sysprof:utilities-system-monitor.svg"
    # The three launchers 06-branding.sh points at the Amethystora artwork. The branded icons stay
    # in hicolor and come back with any other icon theme, but under candy-icons the dash would
    # otherwise carry three flat tiles among the gradients.
    "amethystora-docs:accessories-ebook-reader.svg"
    "amethystora-community:irc-chat.svg"
    "amethystora-update:system-software-update.svg"
    # Amethystora Logs, in place of GNOME Logs, under GNOME Logs' own artwork
    "amethystora-logs:org.gnome.Logs.svg"
)

for entry in "${CANDY_ALIASES[@]}"; do
    alias_name="${entry%%:*}"
    target="${entry#*:}"
    test -e "${CANDY_DIR}/apps/scalable/${target}"
    if [[ ! -e "${CANDY_DIR}/apps/scalable/${alias_name}.svg" ]]; then
        ln -s "${target}" "${CANDY_DIR}/apps/scalable/${alias_name}.svg"
    fi
done

# The cache only speeds icon lookups up, so a theme it will not build is a warning, not a failure
if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache --force --quiet "${CANDY_DIR}" ||
        echo "::warning::could not build the icon cache for ${CANDY_DIR}"
fi

echo "::endgroup::"
