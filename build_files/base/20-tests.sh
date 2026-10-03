#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# No Bluefin / Universal Blue names left in paths or text (07-debrand.sh)
python3 /ctx/build_files/shared/debrand.py --check

# ame: the commands in /usr/share/amethystora/just, in groups. ujust runs the same ones, and also under
# the names they had before the groups.
for i in bin/ame bin/ujust share/amethystora/just/{00-entry,agent,apps,backup,changelog,desktop,security,system,update}.just \
    share/bash-completion/completions/ame share/fish/vendor_completions.d/ame.fish share/zsh/site-functions/_ame ; do
   stat /usr/$i
done
[[ "$(ame --summary)" == "$(ujust --summary)" ]]
ujust --show setup-backup | grep -qx "alias setup-backup := backup"
# Every command the image tells somebody to run is one: the report's, the notifications', the apps', the
# manual's and the agent skill's. A group named alone is one too.
grep -rhoIE --exclude-dir=node_modules '\bame [a-z][a-z0-9-]*( [a-z][a-z0-9-]*)?' /usr/bin/ame* \
    /usr/libexec/amethystora-* /usr/lib/amethystora-*/resources/app /usr/lib/systemd/{system,user}/amethystora-* \
    /usr/share/amethystora /etc/amethystora /etc/profile.d/amethystora-greeting.sh | sort -u |
    while read -r _ first second; do
        ame --show "${first}" >/dev/null 2>&1 || ame --show "${first}::${second}" >/dev/null 2>&1 ||
            { [[ -z "${second}" ]] && ame --list "${first}" >/dev/null 2>&1; } ||
            { echo "the image names \"ame ${first} ${second}\", which is no command"; false; }
    done

test -f /usr/share/amethystora/homebrew/fonts.Brewfile
test -x /usr/bin/amethystora-fastfetch
# The fetch new terminals show (amethystora-fetch): the glint's frames, each as tall as the still logo
# so that it covers the one before, and the last of them the still logo, which fastfetch prints over it
test -x /usr/bin/amethystora-fetch
GLINT=(/usr/share/amethystora/logos/glint/*)
((${#GLINT[@]} > 1))
cmp -s "${GLINT[-1]}" /usr/share/amethystora/logos/symbols/amethystora
for frame in "${GLINT[@]}"; do
    [[ "$(wc -l <"${frame}")" == "$(wc -l </usr/share/amethystora/logos/symbols/amethystora)" ]]
done
# Logo in the text console colours (amethystora-greeting)
test -f /usr/share/amethystora/logos/console/amethystora
test -x /usr/libexec/amethystora-greeting
# ...which also draws the banner, so the upstream glow banner is not shipped; its tips are
command -v glow jq >/dev/null
jq -e . /usr/share/amethystora/greeting/style.json >/dev/null
test -f /usr/share/amethystora/image-info.json
test ! -e /etc/profile.d/amethystora-motd.sh
test ! -e /usr/bin/amethystora-motd
compgen -G "/usr/share/amethystora/motd/tips/*.md" >/dev/null
test -f /usr/lib/amethystora/setup-services/libsetup.sh

# If this file is not on the image bazaar will automatically be removed from users systems :(
# See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall
# ...which is also how ClamUI leaves the machines that have it: the Security app scans in its place
test ! -e /usr/share/flatpak/preinstall.d/clamui.preinstall

# Firefox is the browser: Fedora's package, in the image, and so not on the Flatpak list as well
test -f /usr/share/applications/org.mozilla.firefox.desktop
grep -q "^x-scheme-handler/https=org.mozilla.firefox.desktop" /etc/xdg/mimeapps.list
grep -q "org.mozilla.firefox" /usr/share/amethystora/homebrew/system-flatpaks.Brewfile && false
# Mozilla lets Firefox be redistributed only unaltered, so the image adds no policy to it, and with
# no policy no extension
test ! -e /etc/firefox/policies/policies.json
# Brave, which used to be the browser, is gone with the policy written for it
rpm -q brave-browser >/dev/null && false
test ! -e /etc/brave
# Firefox is pinned in the dash
FAVORITES="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps)"
grep -q "'org.mozilla.firefox.desktop'" <<<"${FAVORITES}"
grep -qi "brave" <<<"${FAVORITES}" && false

# Multimedia (05-override-install.sh): FFmpeg is Fedora's with RPM Fusion's libavcodec-freeworld, and no
# FFmpeg library in the image is a build FFmpeg itself calls unredistributable. negativo17's LC3plus,
# which has no licence to redistribute it, is gone, and aptX comes from RPM Fusion
for package in ffmpeg-free libavcodec-free fdk-aac-free libavcodec-freeworld pipewire-codec-aptx; do
    rpm -q "${package}" >/dev/null
done
for package in libavcodec libfdk-aac liblc3plus pipewire-libs-extra mpeghdec; do
    rpm -q "${package}" >/dev/null && false
done
find /usr/lib64 -name 'libav*.so.*' -type f -exec grep -laF 'nonfree and unredistributable' {} + | grep -q . && false
[[ "$(rpm -q --queryformat '%{VENDOR}' libavcodec-freeworld)" == "RPM Fusion" ]]

# No Fedora logo package is left (build.sh swaps each for its generic one)
[[ -z "$(rpm -qa 'fedora-logos*')" ]]
# Nor a Fedora release package. generic-release holds their place in the package database, which is
# what dnf reads the Fedora version from, and the release line no longer calls the system Fedora
[[ -z "$(rpm -qa 'fedora-release*')" ]]
rpm -q generic-release generic-release-common >/dev/null
rpm -q --whatprovides system-release "system-release(${FEDORA_MAJOR_VERSION})" >/dev/null
[[ "$(rpm -E %fedora)" == "${FEDORA_MAJOR_VERSION}" ]]
grep -q "^Amethystora release ${FEDORA_MAJOR_VERSION} " /etc/system-release
grep -qi "fedora" /etc/system-release /etc/system-release-cpe && false
test ! -e /usr/lib/swidtag/fedoraproject.org

# NordVPN is proprietary, with no right to redistribute it, so the image does not carry it
rpm -q nordvpn >/dev/null && false
rpm -q nordvpn-gui >/dev/null && false

# Ptyxis is the terminal: first for xdg-terminal-exec (Super+Return), and kitty is gone
[[ "$(grep -v '^#' /etc/xdg/xdg-terminals.list | head -1)" == "org.gnome.Ptyxis.desktop" ]]
[[ "$(grep -v '^#' /etc/xdg/gnome-xdg-terminals.list | head -1)" == "org.gnome.Ptyxis.desktop" ]]
rpm -q kitty >/dev/null && false

# Animated boot splash: the script theme, the images it loads, and both in the initramfs, which shows the
# splash up to and including the LUKS password prompt
[[ "$(plymouth-set-default-theme)" == "amethystora" ]]
rpm -q plymouth-plugin-script >/dev/null
test -f /usr/share/plymouth/themes/amethystora/amethystora.script
for image in crown halo dust gem light side-0 stem wordmark credit field dot; do
    test -f "/usr/share/plymouth/themes/amethystora/${image}.png"
done
INITRAMFS_FILES="$(lsinitrd /lib/modules/*/initramfs.img)"
grep -q "plymouth/script.so" <<<"${INITRAMFS_FILES}"
grep -q "themes/amethystora/amethystora.script" <<<"${INITRAMFS_FILES}"
# Boot and login text in Inter: fc-match falls back to another family when it is missing
[[ "$(fc-match -f '%{family[0]}' 'Inter')" == "Inter" ]]
grep -q "^Font=Inter " /usr/share/plymouth/themes/amethystora/amethystora.plymouth

# Boot menu: the theme ships read-only in the image and is copied to /boot by amethystora-grub-theme,
# because /boot is not part of a bootc image
test -x /usr/bin/amethystora-grub-theme
test -x /usr/share/amethystora/system-setup.hooks.d/30-grub-theme.sh
for file in theme.txt background.png logo.png select_c.png select_e.png select_w.png icons/fedora.png; do
    test -s "/usr/share/grub/themes/amethystora/${file}"
done
# The font theme.txt asks for, built from Inter by 06-branding.sh: without it the menu falls back
# to GRUB's own and the layout no longer lines up
test -s /usr/share/grub/themes/amethystora/font16.pf2
grep -aq "Inter Regular 16" /usr/share/grub/themes/amethystora/font16.pf2
grep -qE '^[[:space:]]*item_font = "Inter Regular 16"$' /usr/share/grub/themes/amethystora/theme.txt
grep -q '^desktop-image: "background.png"$' /usr/share/grub/themes/amethystora/theme.txt
# The theme is off until someone asks for it, so nothing here may write to /boot at build time
test -e /boot/grub2/themes/amethystora && false

# Amethystora wallpapers are the GNOME default
test -f /usr/share/backgrounds/amethystora/amethystora-facets-l.png
test -f /usr/share/backgrounds/amethystora/amethystora-facets-d.png
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri-dark)" == "'file:///usr/share/backgrounds/amethystora/amethystora-facets-d.png'" ]]
# ...and every one a theme cycles through or GNOME's picker offers is on the image. The PNGs are
# drawn by branding/generate.mjs, so one named here and never rendered stops the build. Every
# shipped theme lists pictures of its own, or it would open on the palette glow drawn from
# wallpaper.svg.tpl, which looks like a plain colour.
for theme in /usr/share/amethystora/themes/*/; do
    grep -q '^/' "${theme}backgrounds.list"
done
for list in /usr/share/amethystora/themes/*/backgrounds.list; do
    grep -v '^[[:space:]]*\(#\|$\)' "${list}" | xargs -r -n1 test -f
done
# Every picture in a theme's folder is accounted for, with its licence, in CREDITS.md
for picture in /usr/share/backgrounds/amethystora/*/*; do
    grep -qF "\`${picture#/usr/share/backgrounds/amethystora/}\`" /usr/share/backgrounds/amethystora/CREDITS.md
done
sed -n 's:.*<filename\(-dark\)\?>\(.*\)</filename\(-dark\)\?>.*:\2:p' /usr/share/gnome-background-properties/amethystora.xml |
    xargs -r -n1 test -f

# Login screen background (12-login-screen.sh): the crown the boot splash ends on, with no gem in
# it. GNOME reads the login background from the shell's own stylesheet and nowhere else,
# so both the picture and the rule naming it live inside the theme's gresource.
#
# The bundle itself is checked in 12-login-screen.sh, at the point it is rebuilt, and not here:
# gresource comes from glib2-devel, which that script takes back out of the image when it is done,
# so reading the bundle at this point would mean installing a toolchain again to re-check something
# nothing since has touched.
test -s /usr/share/backgrounds/amethystora/amethystora-login.png

# Logos (06-branding.sh). The upstream layers overwrite Fedora's logo files with their own pictures,
# under names that say nothing about Bluefin or Universal Blue for 07-debrand.sh to catch, so each
# one is checked here against the Amethystora artwork it has to be. These are what the login screen,
# the Settings About page and Fedora's fallback splash draw.
FEDORA_NAMED_LOGOS=(
    "/usr/share/pixmaps/fedora-gdm-logo.png:/usr/share/pixmaps/amethystora-wordmark-glow.png"
    "/usr/share/pixmaps/fedora-logo-small.png:/usr/share/pixmaps/amethystora-wordmark-small.png"
    "/usr/share/pixmaps/fedora-logo.png:/usr/share/pixmaps/amethystora-wordmark.png"
    "/usr/share/pixmaps/fedora_logo_med.png:/usr/share/pixmaps/amethystora-wordmark-medium.png"
    "/usr/share/pixmaps/fedora_whitelogo_med.png:/usr/share/pixmaps/amethystora-wordmark-white.png"
    "/usr/share/pixmaps/fedora-logo-icon.png:/usr/share/pixmaps/amethystora-logo-512.png"
    "/usr/share/pixmaps/fedora-logo-sprite.png:/usr/share/pixmaps/amethystora-logo-400.png"
    "/usr/share/pixmaps/system-logo-white.png:/usr/share/pixmaps/amethystora-logo-white.png"
    "/usr/share/icons/hicolor/scalable/places/fedora-logo-sprite.svg:/usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg"
    "/usr/share/icons/hicolor/scalable/places/fedora_white_logo.svg:/usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg"
    "/usr/share/icons/hicolor/scalable/places/fedora_whitelogo.svg:/usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg"
    "/usr/share/plymouth/themes/spinner/silverblue-watermark.png:/usr/share/plymouth/themes/spinner/watermark.png"
)
for entry in "${FEDORA_NAMED_LOGOS[@]}"; do
    cmp -s "${entry%%:*}" "${entry#*:}"
done
# GDM's own setting names the Amethystora file, for the case where it is read instead of the path
# above. The wordmark in white, because the greeter's background is dark, and the variant whose
# stone is lit, so the logo carries on from the splash rather than restating it cold.
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.login-screen logo)" == "'/usr/share/pixmaps/amethystora-wordmark-glow.png'" ]]

# Top bar: the Logo Menu button draws the coloured Amethystora gem, the one entry 06-branding.sh
# leaves in the extension's coloured list (index 0). Symbolic icons are off, so the panel shows the
# gem's own purple instead of a white silhouette. The files keep their upstream names until
# 07-debrand.sh renames them.
LOGOMENU=/usr/share/gnome-shell/extensions/logomenu@aryan_k
LOGOMENU_DCONF=/etc/dconf/db/distro.d/04-amethystora-logomenu-extension
cmp -s "${LOGOMENU}/Resources/amethystora-logo-symbolic.svg" \
    /usr/share/icons/hicolor/scalable/actions/amethystora-logo-symbolic.svg
cmp -s "${LOGOMENU}/Resources/amethystora-logo.svg" \
    /usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg
grep -q "^symbolic-icon=false$" "${LOGOMENU_DCONF}"
grep -q "^menu-button-icon-image=0$" "${LOGOMENU_DCONF}"
[[ "$(sed -n '/ColouredDistroIcons/,/^\];/p' "${LOGOMENU}/constants.js" |
    grep -oE "PATH: '[^']+'")" == "PATH: '/Resources/amethystora-logo.svg'" ]]
# The symbolic list is as short: an account switching symbolic icons back on in Extension Manager, or
# one whose setting names an entry that has gone, lands on the Amethystora silhouette.
[[ "$(sed -n '/SymbolicDistroIcons/,/^\];/p' "${LOGOMENU}/constants.js" |
    grep -oE "PATH: '[^']+'")" == "PATH: '/Resources/amethystora-logo-symbolic.svg'" ]]
# Nobody else's logo comes with the extension: a logo is a trademark, and Fedora's guidelines keep
# Fedora's out of a system built this way. What is left is the two above and the extension's own
# picture for its About page.
[[ -z "$(find "${LOGOMENU}/Resources" -type f ! -name 'amethystora-logo.svg' \
    ! -name 'amethystora-logo-symbolic.svg' ! -name 'settings-logo-menu-logo.svg')" ]]
test ! -e "${LOGOMENU}/screenshots"
grep -q "menu-button-icon-image" /usr/share/amethystora/user-setup.hooks.d/10-theming.sh && false

# GNOME Shell extensions built from the git submodules (build-gnome-extensions.sh)
for extension in appindicatorsupport@rgcjonas.gmail.com blur-my-shell@aunetx caffeine@patapon.info \
    dash-to-dock@micxgx.gmail.com logomenu@aryan_k search-light@icedman.github.com; do
    test -f "/usr/share/gnome-shell/extensions/${extension}/metadata.json"
done
test -d /usr/share/gnome-shell/extensions/tmp && false

# Every extension has to be readable by the account that logs in, not just by the root this build
# runs as. GNOME Shell reads metadata.json as the user; one it cannot open is not a broken
# extension, it is no extension at all, missing from the shell and from Extension Manager. The
# extensions.gnome.org downloads carry metadata.json as 0600, which build-gnome-extensions.sh
# undoes right after unpacking them.
for extension in /usr/share/gnome-shell/extensions/*/; do
    [[ -z "$(find "${extension}" -type f ! -perm -o=r)" ]]
    [[ -z "$(find "${extension}" -type d ! -perm -o=rx)" ]]
done

# Every extension ships its licence, in its own folder or in /usr/share/licenses/<uuid>: the GPL asks
# for the text to travel with the program. One installed from a Fedora package carries it in the package's
# licence folder, or, like those of gnome-shell-extensions, in that of a sibling from the same source
# package (gnome-shell-extension-common). Space Bar's upload has none, so build-gnome-extensions.sh adds
# the GPL its origin puts it under (NOTICE)
for extension in /usr/share/gnome-shell/extensions/*/; do
    uuid="$(basename "${extension}")"
    srpm="$(rpm -qf --qf '%{SOURCERPM}' "${extension%/}" 2>/dev/null)" || srpm=""
    compgen -G "${extension}[Ll][Ii][Cc][Ee][Nn][Ss][Ee]*" >/dev/null ||
        compgen -G "${extension}COPYING*" >/dev/null ||
        compgen -G "/usr/share/licenses/${uuid}/*" >/dev/null ||
        { [[ -n ${srpm} ]] && [[ -n "$(rpm -qa --qf '%{SOURCERPM} %{NAME}\n' |
            awk -v s="${srpm}" '$1 == s { print $2 }' | xargs -r rpm -qL | grep '^/')" ]]; } ||
        { echo "No licence shipped for the extension ${uuid}"; exit 1; }
done

# Tiling and top bar: each extension from extensions.gnome.org is installed, enabled, supports this
# GNOME, and has its schema readable system-wide so the defaults in zz1-amethystora-modifications apply
GNOME_MAJOR="$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)"
for extension in paperwm@paperwm.github.com tophat@fflewddur.github.io \
    just-perfection-desktop@just-perfection space-bar@luchrioh clipboard-indicator@tudmotu.com \
    gnome-fuzzy-app-search@gnome-shell-extensions.Czarlie.gitlab.com; do
    test -f "/usr/share/gnome-shell/extensions/${extension}/metadata.json"
    jq -e --arg shell "${GNOME_MAJOR}" '.["shell-version"] | index($shell)' \
        "/usr/share/gnome-shell/extensions/${extension}/metadata.json"
    grep -q "'${extension}'" /usr/share/glib-2.0/schemas/zz0-amethystora-modifications.gschema.override
done
# Space Bar's own menu shortcut defaults to Super+W, which closes a window here, so it has to be cleared
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.space-bar.shortcuts open-menu)" == "@as []" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.space-bar.shortcuts enable-activate-workspace-shortcuts)" == "false" ]]
# TopHat's colour comes from the palette, not from GNOME's nine accents
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.tophat use-system-accent)" == "false" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.just-perfection workspace-popup)" == "false" ]]
test ! -e /usr/share/gnome-shell/extensions/tactile@lundal.io
# The Activities button stays hidden with PaperWM on, which shows it again after Space Bar hid it
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.just-perfection activities-button)" == "false" ]]
# PaperWM leaves the top bar to the theme and the workspaces to Space Bar
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.paperwm disable-topbar-styling)" == "true" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.paperwm show-workspace-indicator)" == "false" ]]
# Clipboard history stays in memory, and none of its shortcuts take the Ctrl+F keys from applications
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.clipboard-indicator cache-only-favorites)" == "true" ]]
grep -qi "<Control>F" <<<"$(GSETTINGS_BACKEND=memory gsettings list-recursively org.gnome.shell.extensions.clipboard-indicator)" && false
# PaperWM takes a colliding GNOME binding for itself while it is on. It cannot see custom keybindings
# or other extensions' shortcuts, and the GNOME ones listed here are kept on purpose, so no PaperWM
# binding may share a key with any of them. Modifiers are sorted and lower-cased before comparing.
keycombos() {
    grep -oE "'[^']+'" | tr -d "'" | tr '[:upper:]' '[:lower:]' | sed 's/<ctrl>/<control>/g; s/<primary>/<control>/g' |
        while read -r combo; do
            echo "$(grep -o '<[a-z]*>' <<<"${combo}" | LC_ALL=C sort | tr -d '\n')${combo##*>}"
        done | LC_ALL=C sort -u
}
PAPERWM_COMBOS="$(GSETTINGS_BACKEND=memory gsettings list-recursively org.gnome.shell.extensions.paperwm.keybindings | keycombos)"
grep -qx "<super>left" <<<"${PAPERWM_COMBOS}"
KEPT_COMBOS="$(
    {
        grep -h -d skip -e "^binding=" -e "^shortcut-search=" /etc/dconf/db/distro.d/*
        GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.clipboard-indicator toggle-menu
        for key in close begin-resize switch-applications switch-windows switch-group switch-panels; do
            GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.wm.keybindings "${key}"
        done
        GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.keybindings toggle-message-tray
        GSETTINGS_BACKEND=memory gsettings get org.gnome.mutter.wayland.keybindings restore-shortcuts
        GSETTINGS_BACKEND=memory gsettings get org.gnome.mutter.keybindings cancel-input-capture
    } | keycombos
)"
grep -qx "<super>return" <<<"${KEPT_COMBOS}"
[[ -z "$(LC_ALL=C comm -12 <(echo "${PAPERWM_COMBOS}") <(echo "${KEPT_COMBOS}"))" ]]

# Blur my Shell: the Tahoe-style glass in 05-blur-my-shell-extension. Its schema lives in the
# extension's own directory rather than system-wide, so these are dconf defaults and not a gschema
# override -- and a dconf default for a key the extension does not have is dropped without a word,
# which is how a submodule bump would quietly undo the whole file. So every key in it is looked up
# in the schema it belongs to.
BMS=/usr/share/gnome-shell/extensions/blur-my-shell@aunetx
BMS_DCONF=/etc/dconf/db/distro.d/05-blur-my-shell-extension
bms_schema=""
while read -r line; do
    case "${line}" in
    '#'* | '') continue ;;
    '['*)
        bms_schema="${line//\//.}"
        bms_schema="${bms_schema:1:-1}"
        continue
        ;;
    esac
    gsettings --schemadir "${BMS}/schemas" list-keys "${bms_schema}" | grep -qx "${line%%=*}"
done <"${BMS_DCONF}"
# A component that names a pipeline the pipelines dict does not define falls back to the stock blur
# without a word, so every pipeline the file selects has to be one the file also defines
while read -r bms_pipeline; do
    grep -q "'${bms_pipeline}': {" "${BMS_DCONF}"
done < <(sed -n "s/^pipeline='\([^']*\)'$/\1/p" "${BMS_DCONF}" | sort -u)
# The glass is the refraction effect ("Liquid Glass" in the preferences) and it only runs on the
# static blur path, so the effect has to be packed into the extension and the popups set to static
test -f "${BMS}/effects/refraction.glsl"
grep -q "'refraction'" "${BMS_DCONF}"
grep -q "^static-blur=true$" "${BMS_DCONF}"
# The whole look is off if the extension is not enabled, and nothing else in the image would say so:
# every key above would be a perfectly valid default for an extension nobody is running
grep -q "'blur-my-shell@aunetx'" /usr/share/glib-2.0/schemas/zz0-amethystora-modifications.gschema.override
# An account that holds a list of its own never sees that default, so the user-setup hook puts it
# back after every update; the default it reads has to be the one the image compiled
test -x /usr/share/amethystora/user-setup.hooks.d/15-extensions.sh
GSETTINGS_BACKEND=memory gsettings get org.gnome.shell enabled-extensions | grep -q "'blur-my-shell@aunetx'"
# Application windows are on the glass too, every one of them rather than a named few
grep -q "^enable-all=true$" "${BMS_DCONF}"
[[ "$(sed -n '/^\[org\/gnome\/shell\/extensions\/blur-my-shell\/applications\]$/,/^$/p' "${BMS_DCONF}" |
    grep -c '^blur=true$')" == 1 ]]

# Six fixed workspaces on Super+N, which moves the dash to Alt+N
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.wm.preferences num-workspaces)" == "6" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.mutter dynamic-workspaces)" == "false" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.wm.keybindings switch-to-workspace-6)" == "['<Super>6']" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.keybindings switch-to-application-1)" == "['<Alt>1']" ]]
# custom-keybindings in zz0-amethystora-modifications lists every custom keybinding GNOME reads, the
# Amethystora ones in 06-amethystora-keybindings included
CUSTOM_KEYBINDINGS="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
grep -q "custom0/'" <<<"${CUSTOM_KEYBINDINGS}"
for index in 20 21 22 23 24 25 26 27 28; do
    grep -q "custom${index}/'" <<<"${CUSTOM_KEYBINDINGS}"
    grep -q "^\[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}\]$" \
        /etc/dconf/db/distro.d/06-amethystora-keybindings
done

# Theme switching: the CLI, its library, the templates every theme renders, and the themes themselves
test -x /usr/bin/amethystora-theme
test -x /usr/bin/amethystora-menu

# Web apps: a launcher that reopens the site through amethystora-webapp, in Firefox by default, with
# the window class GNOME needs to show it under its own name; anything but http(s) is refused. Firefox
# has no app window, so the launcher opens the site in a profile of its own and takes that window's
# class, and removing the web app removes the profile. With a Chromium-based default browser the
# launcher opens the browser's app window instead and takes that one's class
test -x /usr/bin/amethystora-webapp
WEBAPP_HOME="$(mktemp -d)"
WEBAPP_CLASS=amethystora-webapp-example.com_app
HOME="${WEBAPP_HOME}" amethystora-webapp install "Test App" example.com/app web-browser
WEBAPP_DESKTOP="${WEBAPP_HOME}/.local/share/applications/amethystora-webapp-test-app.desktop"
grep -qx 'Exec=amethystora-webapp "https://example.com/app"' "${WEBAPP_DESKTOP}"
grep -qx "StartupWMClass=${WEBAPP_CLASS}" "${WEBAPP_DESKTOP}"
HOME="${WEBAPP_HOME}" amethystora-webapp install Bad "javascript:alert(1)" web-browser 2>/dev/null && false
mkdir "${WEBAPP_HOME}/bin"
# Opens the web app from its launcher with the browser named as the default one, a stand-in that
# prints what it was started with. GLib names the launcher and the process it started; exec keeps the
# shell's PID for the script
webapp_open() {
    printf '#!/usr/bin/bash\necho %s.desktop\n' "$1" >"${WEBAPP_HOME}/bin/xdg-settings"
    chmod +x "${WEBAPP_HOME}/bin/xdg-settings"
    printf '[Desktop Entry]\nExec=echo %%u\n' >"${WEBAPP_HOME}/.local/share/applications/$1.desktop"
    HOME="${WEBAPP_HOME}" PATH="${WEBAPP_HOME}/bin:${PATH}" GIO_LAUNCHED_DESKTOP_FILE="${WEBAPP_DESKTOP}" \
        bash -c 'export GIO_LAUNCHED_DESKTOP_FILE_PID=$$; exec amethystora-webapp example.com/app'
}
test "$(webapp_open chromium-browser)" = "--app=https://example.com/app"
grep -qx 'StartupWMClass=chrome-example.com__app-Default' "${WEBAPP_DESKTOP}"
WEBAPP_PROFILE="${WEBAPP_HOME}/.local/share/amethystora-webapp/${WEBAPP_CLASS}"
test "$(webapp_open firefox)" = \
    "--name ${WEBAPP_CLASS} --class ${WEBAPP_CLASS} --profile ${WEBAPP_PROFILE} https://example.com/app"
grep -qx "StartupWMClass=${WEBAPP_CLASS}" "${WEBAPP_DESKTOP}"
grep -q legacyUserProfileCustomizations "${WEBAPP_PROFILE}/user.js"
test -s "${WEBAPP_PROFILE}/chrome/userChrome.css"
HOME="${WEBAPP_HOME}" amethystora-webapp remove "Test App" >/dev/null
test ! -e "${WEBAPP_DESKTOP}"
test ! -e "${WEBAPP_PROFILE}"
rm -rf "${WEBAPP_HOME}"

# Packages from other distributions (amethystora-pkg): the command and its short name, which answers to
# the name it was typed as, and `ame pkg`
test -x /usr/bin/amethystora-pkg
[[ "$(readlink /usr/bin/amepkg)" == amethystora-pkg ]]
amepkg --help | grep -q "^Usage: amepkg "
ame pkg --help | grep -q "^Usage: amethystora-pkg "
for completion in bash-completion/completions/amethystora-pkg bash-completion/completions/amepkg \
    fish/vendor_completions.d/amethystora-pkg.fish fish/vendor_completions.d/amepkg.fish zsh/site-functions/_amethystora-pkg; do
    test -s "/usr/share/${completion}"
done
grep -q "^#compdef amethystora-pkg amepkg$" /usr/share/zsh/site-functions/_amethystora-pkg
# Every list --json parses, the containers one through a stand-in for podman with one container in it
PKG_HOME="$(mktemp -d)"
mkdir -p "${PKG_HOME}/bin" "${PKG_HOME}/.local/state/amethystora/pkg/containers"
cat >"${PKG_HOME}/bin/podman" <<'EOF'
#!/usr/bin/bash
echo '[{"Names": ["pkg-test"], "State": "exited", "Labels": {"manager": "distrobox",
    "amethystora.pkg.manager": "amethystora-pkg", "amethystora.pkg.name": "test", "amethystora.pkg.template": "debian",
    "amethystora.pkg.pkgmanager": "apt", "amethystora.pkg.image": "quay.io/x/y:1", "amethystora.pkg.init": "0"}}]'
EOF
chmod +x "${PKG_HOME}/bin/podman"
HOME="${PKG_HOME}" PATH="${PKG_HOME}/bin:${PATH}" amethystora-pkg containers list --json |
    jq -e 'length == 1 and (.[0] | .name == "test" and .manager == "apt" and .status == "exited"
        and has("home") and has("init") and has("exported_apps") and has("last_upgrade"))' >/dev/null
HOME="${PKG_HOME}" amethystora-pkg templates list --json |
    jq -e 'length >= 7 and all(has("name") and has("base") and has("manager") and has("packages") and .built_in and .verified)' >/dev/null
HOME="${PKG_HOME}" amethystora-pkg managers list --json |
    jq -e 'length >= 5 and all(.built_in and (.install | length > 0) and (.clean | length > 0) and has("need_sudo"))' >/dev/null
# The AUR's manager and template are there only while ame apps aur has turned it on
HOME="${PKG_HOME}" amethystora-pkg managers show paru >/dev/null 2>&1 && false
mkdir -p "${PKG_HOME}/.config/amethystora" && touch "${PKG_HOME}/.config/amethystora/aur"
HOME="${PKG_HOME}" amethystora-pkg templates show arch-aur | jq -e '.manager == "paru" and .own_home' >/dev/null
rm -rf "${PKG_HOME}"
grep -q "^aur:" /usr/share/amethystora/just/apps.just
# Every built-in template's image is pinned by digest, and the pins ship in the signed image, which is
# what makes a container made from one start from exactly that image. Each names a built-in manager.
for template in /usr/share/amethystora/pkg/templates/*.json /usr/share/amethystora/pkg/aur/templates/*.json; do
    jq -e '.base | test("^[a-z0-9.-]+/[^@ ]+@sha256:[0-9a-f]{64}$")' "${template}" >/dev/null
    manager="$(jq -r .manager "${template}")"
    test -f "/usr/share/amethystora/pkg/managers/${manager}.json" -o -f "/usr/share/amethystora/pkg/aur/managers/${manager}.json"
done
# A .deb or an .rpm opens in it, in a terminal, scanned and explained first
PKG_DESKTOP=/usr/share/applications/amethystora-pkg-install.desktop
command -v desktop-file-validate >/dev/null && desktop-file-validate "${PKG_DESKTOP}"
grep -qx "MimeType=application/vnd.debian.binary-package;application/x-rpm;" "${PKG_DESKTOP}"
grep -q "^Exec=/usr/libexec/amethystora-in-terminal amethystora-pkg install %f$" "${PKG_DESKTOP}"
for type in application/vnd.debian.binary-package application/x-rpm; do
    grep -qx "${type}=amethystora-pkg-install.desktop" /etc/xdg/mimeapps.list
done
# DistroShelf, the window onto the containers, comes with every machine, as Bazaar and Flatseal do
for preinstall in bazaar flatseal distroshelf; do
    test -f "/usr/share/flatpak/preinstall.d/${preinstall}.preinstall"
done
grep -q "^\[Flatpak Preinstall com.ranfdev.DistroShelf\]$" /usr/share/flatpak/preinstall.d/distroshelf.preinstall
grep -q '"com.ranfdev.DistroShelf"' /usr/share/amethystora/homebrew/system-flatpaks.Brewfile && false
# Its containers are upgraded by a timer of each account's own. uupd's module for containers stays off:
# it upgraded every container of everyone, and made manual updates slow.
test -L /etc/systemd/user/timers.target.wants/amethystora-pkg-upgrade.timer
grep -q "^ExecStart=/usr/bin/amethystora-pkg upgrade-all$" /usr/lib/systemd/user/amethystora-pkg-upgrade.service
jq -e '.modules.distrobox.disable == true' /etc/uupd/config.json >/dev/null
# Nothing this adds is named after the tools it does the work of. The manual alone may say, once, that
# importing reads their file format.
PKG_NAMES='\b(vanilla[ -]?os|apx|vso|sideload)\b'
grep -rliE "${PKG_NAMES}" /usr/bin/amethystora-pkg /usr/share/amethystora/pkg /usr/share/bash-completion/completions/amepkg \
    /usr/share/bash-completion/completions/amethystora-pkg /usr/share/fish/vendor_completions.d/amepkg.fish \
    /usr/share/fish/vendor_completions.d/amethystora-pkg.fish /usr/share/zsh/site-functions/_amethystora-pkg "${PKG_DESKTOP}" \
    /usr/lib/systemd/user/amethystora-pkg-upgrade.service /usr/lib/systemd/user/amethystora-pkg-upgrade.timer \
    /usr/libexec/amethystora-gpu-check /usr/libexec/amethystora-update-alert /usr/libexec/amethystora-setup-manifest \
    /usr/libexec/amethystora-restore-setup /usr/share/amethystora/agents /usr/share/amethystora/just \
    /usr/share/amethystora/user-setup.hooks.d && false
[[ -z "$(grep -rliE "${PKG_NAMES}" /usr/share/amethystora/manual | grep -vx /usr/share/amethystora/manual/software.md)" ]]
[[ "$(grep -ciE "${PKG_NAMES}" /usr/share/amethystora/manual/software.md)" -le 1 ]]

# A setup to make again on a new machine: every backup stores one beside the files, and `ame
# restore-setup` reads it back. Neither may delete anything from the repository.
test -x /usr/libexec/amethystora-setup-manifest
test -x /usr/libexec/amethystora-restore-setup
grep -q "/usr/libexec/amethystora-setup-manifest" /usr/libexec/amethystora-backup
grep -q "^restore-setup SNAPSHOT=" /usr/share/amethystora/just/backup.just
grep -vE "^[[:space:]]*#" /usr/libexec/amethystora-restore-setup | grep -qE "restic +(forget|prune)" && false
# The image switch it makes goes through the rebase helper, which takes signed images only and offers the
# image without NVIDIA's driver too
grep -q "^rebase IMAGE=\"\" STREAM=\"\":" /usr/share/amethystora/just/system.just
grep -q "^  IMAGES=(amethystora amethystora-dx amethystora-nvidia-open amethystora-dx-nvidia-open)$" /usr/bin/amethystora-rollback-helper

# The NVIDIA check, once per machine, through the rebase helper, never switching by itself
test -x /usr/libexec/amethystora-gpu-check
grep -q "^ExecCondition=/usr/libexec/amethystora-gpu-check pending$" /usr/lib/systemd/system/amethystora-gpu-check.service
grep -q "ame system rebase" /usr/libexec/amethystora-gpu-check
grep -q "kernel lockdown" /usr/libexec/amethystora-gpu-check
grep -q -- "--action" /usr/libexec/amethystora-notify-users
# A machine started from an older version than its default one is told so at login, and System Updates
# offers to keep it or to restart into the newest
test -x /usr/libexec/amethystora-update-alert
test -L /etc/systemd/user/graphical-session.target.wants/amethystora-update-alert.service
grep -q "'/usr/bin/bootc', 'rollback'" /usr/lib/amethystora-update/resources/app/main.js
# The manual's welcome page, once, at an account's first login
test -x /usr/share/amethystora/user-setup.hooks.d/17-welcome.sh
grep -q "^version-script welcome user " /usr/share/amethystora/user-setup.hooks.d/17-welcome.sh
grep -q "amethystora-manual welcome$" /usr/share/amethystora/user-setup.hooks.d/17-welcome.sh

# The manual (13-manual.sh): Electron starts, which also proves every library it links against is on
# the image, the app, its renderer and its wordmark's font and stone are in place, and every page in
# pages.json exists and every link between pages lands on a page and a heading that exist
MANUAL_ELECTRON=/usr/lib/amethystora-manual/amethystora-manual
test -x /usr/bin/amethystora-manual
test -x "${MANUAL_ELECTRON}"
test ! -e /usr/lib/amethystora-manual/chrome-sandbox
for file in main.js preload.js manual.js index.html manual.css marked.umd.js gem.svg fonts/QuicksandVariable.ttf; do
    test -s "/usr/lib/amethystora-manual/resources/app/${file}"
done
ELECTRON_RUN_AS_NODE=1 "${MANUAL_ELECTRON}" -e 'process.exit(0)'
ELECTRON_RUN_AS_NODE=1 "${MANUAL_ELECTRON}" /ctx/build_files/shared/check-manual.js
test -f /usr/share/licenses/amethystora-manual/LICENSES.chromium.html
test -f /usr/share/licenses/amethystora-manual/marked/LICENSE
test -f /usr/share/licenses/amethystora-manual/Quicksand-OFL.txt
cmp -s <(sed 1d /usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg) \
    <(sed 1d /usr/lib/amethystora-manual/resources/app/gem.svg)
# It replaces upstream's Documentation launcher, and Super+F1 opens it
MANUAL_DESKTOP=/usr/share/applications/amethystora-manual.desktop
test ! -e /usr/share/applications/documentation.desktop
command -v desktop-file-validate >/dev/null && desktop-file-validate "${MANUAL_DESKTOP}"
grep -q "^command='amethystora-manual'$" /etc/dconf/db/distro.d/06-amethystora-keybindings

# The Security app (14-security.sh): the Manual's Electron under a name of its own, the same files rather
# than a copy of them, and the app, its renderer and its wordmark's font and stone in place. Its scripts
# at least compile, which is as much as a build can ask of a window it cannot open.
SECURITY_ELECTRON=/usr/lib/amethystora-security/amethystora-security
test -x /usr/bin/amethystora-security
test -x "${SECURITY_ELECTRON}"
[[ "$(stat -c '%i' "${SECURITY_ELECTRON}")" == "$(stat -c '%i' "${MANUAL_ELECTRON}")" ]]
test ! -e /usr/lib/amethystora-security/chrome-sandbox
for file in main.js preload.js security.js index.html security.css gem.svg fonts/QuicksandVariable.ttf; do
    test -s "/usr/lib/amethystora-security/resources/app/${file}"
done
for file in main.js preload.js security.js; do
    ELECTRON_RUN_AS_NODE=1 "${SECURITY_ELECTRON}" -e \
        'new (require("node:vm").Script)(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
        "/usr/lib/amethystora-security/resources/app/${file}"
done
test -f /usr/share/licenses/amethystora-security/Quicksand-OFL.txt
# The stone in its wordmark is the logo's own, cropped the way branding/generate.mjs crops it
cmp -s <(sed 1d /usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg) \
    <(sed 1d /usr/lib/amethystora-security/resources/app/gem.svg)
test -x /usr/libexec/amethystora-in-terminal

# The Updates app (15-update.sh), put together as the Security app is
UPDATE_ELECTRON=/usr/lib/amethystora-update/amethystora-update
test -x /usr/bin/amethystora-update
test -x "${UPDATE_ELECTRON}"
[[ "$(stat -c '%i' "${UPDATE_ELECTRON}")" == "$(stat -c '%i' "${MANUAL_ELECTRON}")" ]]
test ! -e /usr/lib/amethystora-update/chrome-sandbox
for file in main.js preload.js update.js index.html update.css gem.svg fonts/QuicksandVariable.ttf; do
    test -s "/usr/lib/amethystora-update/resources/app/${file}"
done
for file in main.js preload.js update.js; do
    ELECTRON_RUN_AS_NODE=1 "${UPDATE_ELECTRON}" -e \
        'new (require("node:vm").Script)(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
        "/usr/lib/amethystora-update/resources/app/${file}"
done
test -f /usr/share/licenses/amethystora-update/Quicksand-OFL.txt
cmp -s <(sed 1d /usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg) \
    <(sed 1d /usr/lib/amethystora-update/resources/app/gem.svg)
# It replaces upstream's System Update launcher, while `ame update` stays for the terminal
UPDATE_DESKTOP=/usr/share/applications/amethystora-update.desktop
test ! -e /usr/share/applications/system-update.desktop
command -v desktop-file-validate >/dev/null && desktop-file-validate "${UPDATE_DESKTOP}"
grep -rqx "update:" /usr/share/amethystora/just/
# "Update now" starts uupd's manual unit, which the rule the uupd package ships lets anyone start
# without a password. Without the rule it would still start, after asking for one. The ublue-os/packages
# build this image installs puts the rule in /etc, uupd's own spec in /usr/share: either will do.
test -f /usr/lib/systemd/system/uupd-manual.service
grep -qs '"uupd-manual.service"' /etc/polkit-1/rules.d/uupd.rules /usr/share/polkit-1/rules.d/uupd.rules

# The Notes app (16-notes.sh), put together as the Security app is, with the Manual's marked as well
NOTES_ELECTRON=/usr/lib/amethystora-notes/amethystora-notes
test -x /usr/bin/amethystora-notes
test -x "${NOTES_ELECTRON}"
[[ "$(stat -c '%i' "${NOTES_ELECTRON}")" == "$(stat -c '%i' "${MANUAL_ELECTRON}")" ]]
[[ "$(stat -c '%i' /usr/lib/amethystora-notes/resources/app/marked.umd.js)" == "$(stat -c '%i' /usr/lib/amethystora-manual/resources/app/marked.umd.js)" ]]
test ! -e /usr/lib/amethystora-notes/chrome-sandbox
for file in main.js preload.js notes.js index.html notes.css gem.svg gem-bowl.svg gem-stem.svg fonts/QuicksandVariable.ttf; do
    test -s "/usr/lib/amethystora-notes/resources/app/${file}"
done
for file in main.js preload.js notes.js; do
    ELECTRON_RUN_AS_NODE=1 "${NOTES_ELECTRON}" -e \
        'new (require("node:vm").Script)(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
        "/usr/lib/amethystora-notes/resources/app/${file}"
done
# The notes are sealed with AES-256-GCM under a key from scrypt: both have to be in this Electron's crypto
ELECTRON_RUN_AS_NODE=1 "${NOTES_ELECTRON}" -e '
    const crypto = require("node:crypto");
    const key = crypto.scryptSync("test", "salt", 32, { N: 2 ** 17, r: 8, p: 1, maxmem: 512 * 1024 * 1024 });
    crypto.createCipheriv("aes-256-gcm", key, crypto.randomBytes(12));'
# A passkey is asked of the security key through libfido2's tools (fido2-tools)
for tool in fido2-token fido2-cred fido2-assert; do
    command -v "${tool}"
done
test -f /usr/share/licenses/amethystora-notes/Quicksand-OFL.txt
test -f /usr/share/licenses/amethystora-notes/marked/LICENSE
cmp -s <(sed 1d /usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg) \
    <(sed 1d /usr/lib/amethystora-notes/resources/app/gem.svg)
test -s /usr/share/icons/hicolor/scalable/apps/amethystora-notes.svg
command -v desktop-file-validate >/dev/null && desktop-file-validate /usr/share/applications/amethystora-notes.desktop
# It takes the place of Joplin and Planify, so no Flatpak list the image carries may bring them back
grep -rqsE '"(net\.cozic\.joplin_desktop|io\.github\.alainm23\.planify)"' /usr/share/amethystora/homebrew /usr/share/flatpak/preinstall.d && false

# The Logs app (16-logs.sh), put together as the Security app is
LOGS_ELECTRON=/usr/lib/amethystora-logs/amethystora-logs
test -x /usr/bin/amethystora-logs
test -x "${LOGS_ELECTRON}"
[[ "$(stat -c '%i' "${LOGS_ELECTRON}")" == "$(stat -c '%i' "${MANUAL_ELECTRON}")" ]]
test ! -e /usr/lib/amethystora-logs/chrome-sandbox
for file in main.js preload.js logs.js index.html logs.css gem.svg gem-bowl.svg gem-stem.svg fonts/QuicksandVariable.ttf; do
    test -s "/usr/lib/amethystora-logs/resources/app/${file}"
done
for file in main.js preload.js logs.js; do
    ELECTRON_RUN_AS_NODE=1 "${LOGS_ELECTRON}" -e \
        'new (require("node:vm").Script)(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
        "/usr/lib/amethystora-logs/resources/app/${file}"
done
test -f /usr/share/licenses/amethystora-logs/Quicksand-OFL.txt
cmp -s <(sed 1d /usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg) \
    <(sed 1d /usr/lib/amethystora-logs/resources/app/gem.svg)
command -v desktop-file-validate >/dev/null && desktop-file-validate /usr/share/applications/amethystora-logs.desktop
# It replaces GNOME Logs, which the upstream Flatpak list installed. The options it hands journalctl
# have to be ones this journalctl knows.
grep -q '"org.gnome.Logs"' /usr/share/amethystora/homebrew/system-flatpaks.Brewfile && false
# ...and a machine that already had it loses it, once, by 21-retire-gnome-logs.sh
grep -q "flatpak uninstall --system .*org.gnome.Logs" /usr/share/amethystora/system-setup.hooks.d/21-retire-gnome-logs.sh
JOURNALCTL_HELP="$(journalctl --help --no-pager)"
for option in --case-sensitive --output-fields --after-cursor --identifier --user-unit; do
    grep -q -- "${option}" <<<"${JOURNALCTL_HELP}"
done

test -f /usr/lib/amethystora/theme/lib.sh
test -f /usr/share/amethystora/keybindings.md
test -x /usr/share/amethystora/theme-set.hooks.d/10-vscodium.sh
test -x /usr/share/amethystora/user-setup.hooks.d/11-theme.sh
for template in btop.theme ptyxis.palette starship.toml wallpaper.svg wallpaper-contours.svg wallpaper-ridges.svg wallpaper-waves.svg; do
    test -f "/usr/share/amethystora/themed/${template}.tpl"
done
# A wallpaper template draws with colours from the palette, and one a theme lacks would be left in
# the SVG as "{{ key }}", which librsvg cannot draw
for key in $(grep -oh '{{ [a-z0-9_]* }}' /usr/share/amethystora/themed/wallpaper*.svg.tpl | tr -d '{} ' | sort -u); do
    for theme in /usr/share/amethystora/themes/*/; do
        grep -q "^${key} = \"#" "${theme}colors.toml"
    done
done
# Every theme needs a palette; the default one is what 11-theme.sh applies at first login
test -f /usr/share/amethystora/themes/amethystora/colors.toml
for theme in /usr/share/amethystora/themes/*/; do
    test -f "${theme}colors.toml"
    grep -q "^background = \"#" "${theme}colors.toml"
    grep -q "^color15 = \"#" "${theme}colors.toml"
    # accent.theme has to name an accent GNOME knows, or setting it silently does nothing
    if [[ -f "${theme}accent.theme" ]]; then
        grep -qE "^(blue|teal|green|yellow|orange|red|pink|purple|slate)$" "${theme}accent.theme"
    fi
    # pair.theme has to name a theme that exists, or Super+Ctrl+D dead-ends
    if [[ -f "${theme}pair.theme" ]]; then
        test -d "/usr/share/amethystora/themes/$(cat "${theme}pair.theme")"
    fi
done

# GTK theme (11-gtk-theme.sh): Sweet, rotated onto the amethyst palette and installed under
# Amethystora's own name, because a theme whose colours have been replaced is no longer Sweet
GTK_THEME_DIR=/usr/share/themes/Amethystora
test -f /usr/share/licenses/amethystora-gtk-theme/LICENSE
grep -qx "Name=Amethystora" "${GTK_THEME_DIR}/index.theme"
for stylesheet in gtk-3.0/gtk.css gtk-3.0/gtk-dark.css gtk-4.0/gtk.css gtk-4.0/gtk-dark.css; do
    test -s "${GTK_THEME_DIR}/${stylesheet}"
done
# The stylesheets reach their bitmaps through ../assets, so the two have to stay siblings
test -s "${GTK_THEME_DIR}/assets/checkbox-checked-dark.png"
grep -q '\.\./assets/' "${GTK_THEME_DIR}/gtk-4.0/gtk-dark.css"
# Nothing Sweet coloured may be left: its teal accent by name, and anything else the rotation
# should have moved and did not
grep -qi "00d3a7" "${GTK_THEME_DIR}/gtk-4.0/gtk-dark.css" && false
python3 /ctx/build_files/shared/recolor.py --check "${GTK_THEME_DIR}"/gtk-[34].0/*.css
# The filled half of a switch is the one accent Sweet draws in the warm colours the default band
# spares, and it gets a pass of its own. Amber left here would be the only thing in the theme still
# wearing Sweet's colours, next to a purple everything else.
for switch in switch-on switch-on-insensitive; do
    grep -qiE "ff9200|fadd00" "${GTK_THEME_DIR}/assets/${switch}.svg" && false
done
python3 /ctx/build_files/shared/recolor.py --band 30:56 --check \
    "${GTK_THEME_DIR}"/assets/switch-on.svg "${GTK_THEME_DIR}"/assets/switch-on-insensitive.svg
# Only the two Amethystora palettes ask for it. The rest stay on adw-gtk3, which follows the GNOME
# accent colour, where this one would hold its purple against whatever palette they set.
for theme in amethystora amethystora-light; do
    grep -qx "Amethystora" "/usr/share/amethystora/themes/${theme}/gtk.theme"
done
[[ -z "$(find /usr/share/amethystora/themes -name gtk.theme ! -path '*/amethystora/*' ! -path '*/amethystora-light/*')" ]]
# libadwaita ignores gtk-theme, and a Flatpak cannot see /usr/share/themes at all, so both are
# reached by the theme-set hook: it mirrors the theme into ~/.themes and writes the user stylesheet
# that imports from the mirror. Without it the theme stops at the native GTK3 applications.
THEME_HOOK=/usr/share/amethystora/theme-set.hooks.d/20-gtk-apps.sh
test -x "${THEME_HOOK}"
grep -q 'MIRROR_ROOT="${HOME}/.themes"' "${THEME_HOOK}"
grep -q "gtk-4.0" "${THEME_HOOK}"
# The mirror and the stylesheet are only any use to a Flatpak if the sandbox is let at them
grep -q "^filesystems=~/\.themes:ro;xdg-config/gtk-4\.0:ro;$" /etc/flatpak/overrides/global
# Window buttons on the right, where the theme draws its three lights
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.wm.preferences button-layout)" == "':minimize,maximize,close'" ]]

# Icon theme (10-icons.sh): candy-icons, installed from upstream rather than from Fedora's
# candy-icon-theme, which would pull breeze-icon-theme onto a GNOME image
CANDY_DIR=/usr/share/icons/candy-icons
test -f "${CANDY_DIR}/index.theme"
test -f /usr/share/licenses/candy-icons/LICENSE

# The source of every package is listed (source-manifest.sh), and the written offer it points to ships
diff <(rpm -qa --queryformat '%{NAME}\n' | grep -vx gpg-pubkey | sort) \
    <(awk -F'\t' 'NF == 4 && $1 != "PACKAGE" { print $1 }' /usr/share/licenses/amethystora/SOURCES | sort)
grep -q "^Written offer" /usr/share/licenses/amethystora/NOTICE
# What is not installed from a package has no package to carry its licence: Starship is one binary
# from its release (05-override-install.sh), and the *-gdu.rules are game-devices-udev's
test -x /usr/bin/starship
test -s /usr/share/licenses/starship/LICENSE
compgen -G "/usr/lib/udev/rules.d/71-*-gdu.rules" >/dev/null
test -s /usr/share/licenses/game-devices-udev/LICENSE
# The same for what came with the desktop layer and is somebody else's work under another licence
# (NOTICE names each): Prezto's and zimfw's for the zsh configuration, the GPL of Realtek's driver for
# its udev rules, fish's own for the prompt taken from it, and the GPL for Space Bar
for licence in prezto/LICENSE zimfw/LICENSE realtek-r8152/LICENSE fish/COPYING space-bar@luchrioh/LICENSE; do
    test -s "/usr/share/licenses/${licence}"
done
# The licences Fedora's packages keep among their documentation outlive the documentation
# (05-override-install.sh): zsh and libX11 have theirs nowhere else
test -s /usr/share/licenses/zsh/LICENCE
test -s /usr/share/licenses/libX11-common/COPYING
# The credits in the udev rules taken from Universal Blue still say where the work was done
# (debrand.py leaves them alone)
grep -q "https://github.com/ublue-os/config/pull/45$" /usr/lib/udev/rules.d/70-wooting.rules
# The source packages SOURCES says the image carries are in it. FFmpeg's is one: RPM Fusion's
# libavcodec-freeworld is built from it, and RPM Fusion keeps only its current build
awk -F'\t' '$4 ~ "^/usr/src/amethystora/" { print $4 }' /usr/share/licenses/amethystora/SOURCES |
    sort -u | xargs -r -n1 test -s
compgen -G "/usr/src/amethystora/ffmpeg-*.src.rpm" >/dev/null
rpm -q breeze-icon-theme >/dev/null && false
# Gaps fall through to Adwaita, not to Plasma's Breeze
grep -qx "Inherits=Adwaita,hicolor" "${CANDY_DIR}/index.theme"
# No symbolic name outside places/ may point at the full-colour art: GTK cannot recolour it, so the
# panel would carry gradient glyphs that ignore the colour amethystora-theme sets on the top bar
[[ -z "$(find "${CANDY_DIR}"/{apps,devices,mimetypes,preferences,status} -type l -name '*-symbolic.svg')" ]]
test -e "${CANDY_DIR}/places/16/folder-symbolic.svg"
# The apps this image ships that upstream has no icon of its own for, each under the pack's
# pictogram for the job it does or under an icon drawn here
for icon in org.gnome.Ptyxis io.github.kolunmi.Bazaar \
    org.gnome.Papers com.mattjakeman.ExtensionManager \
    be.alexandervanhee.gradia org.freedesktop.MalcontentControl it.mijorus.smile \
    org.gnome.Decibels org.gnome.Tour io.github.flattool.Warehouse page.tesk.Refine org.gnome.tweaks \
    io.github.flattool.Ignition io.gitlab.adhami3310.Impression input-remapper \
    com.ranfdev.DistroShelf org.gnome.Sysprof \
    amethystora-docs amethystora-community amethystora-update amethystora-security-status amethystora-logs; do
    test -e "${CANDY_DIR}/apps/scalable/${icon}.svg"
done
# Icons drawn for this image, in the pack's style, for what upstream has no artwork for and nothing
# near enough to alias to. A real file, not the dangling symlink a missing source would leave.
for icon in /ctx/build_files/shared/candy-icons/*.svg; do
    test -s "${CANDY_DIR}/apps/scalable/$(basename "${icon}")"
    cmp -s "${icon}" "${CANDY_DIR}/apps/scalable/$(basename "${icon}")"
    # glycin decides an icon is SVG from its first 256 bytes alone; a comment ahead of <svg> that
    # pushes the tag past them leaves the launcher with a blank icon
    head -c 256 "${icon}" | grep -q "<svg"
    # Each is named in NOTICE, with where its outline comes from and the licence that came with it
    grep -qF "$(basename "${icon}")" /usr/share/licenses/amethystora/NOTICE
done
# Nobody else's logo is redrawn: a logo is a trademark, and its owner decides how it looks. The only
# application drawings in the theme are the pictograms on the keep list and the icons drawn for this
# image, so one that upstream adds, or that is added here, fails the build until somebody has looked
# at it and put it on the list.
[[ -z "$(find "${CANDY_DIR}/apps/scalable" -type f -printf '%f\n' |
    grep -vxFf <(sed -e '/^#/d' -e '/^$/d' -e 's/$/.svg/' /ctx/build_files/shared/candy-icons/keep) |
    grep -vxFf <(find /ctx/build_files/shared/candy-icons -name '*.svg' -printf '%f\n'))" ]]
# None of the names that answered for a logo is left, as a drawing or as a link to one, so each of
# these shows its maker's icon: Firefox's is in its package, and a Flatpak exports its own
for icon in firefox org.mozilla.firefox thunderbird org.mozilla.Thunderbird jetbrains-toolbox \
    com.jetbrains.IntelliJ-IDEA-Ultimate code com.visualstudio.code google-chrome com.brave.Browser \
    claude opencode org.onlyoffice.desktopeditors io.podman_desktop.PodmanDesktop fedora-logo-icon; do
    [[ ! -e "${CANDY_DIR}/apps/scalable/${icon}.svg" && ! -L "${CANDY_DIR}/apps/scalable/${icon}.svg" ]]
done
[[ -z "$(find "${CANDY_DIR}" -xtype l)" ]]
compgen -G "/usr/share/icons/hicolor/*/apps/firefox.*" >/dev/null
# The logos on folders, file types and status icons went the same way, and a file of one of those
# types falls to the pack's generic icon of its kind
for logo in places/48/folder-git mimetypes/scalable/{application-pdf,text-x-python} status/scalable/network-bluetooth; do
    [[ ! -e "${CANDY_DIR}/${logo}.svg" ]]
done
test -e "${CANDY_DIR}/mimetypes/scalable/x-office-document.svg"
test -e "${CANDY_DIR}/mimetypes/scalable/text-x-script.svg"
# The links an earlier image made in each account to the IDE drawings, which now point at nothing,
# are taken back at login (user-setup.hooks.d/16-retire-jetbrains-icons.sh)
grep -q -- "-xtype l -name 'jetbrains-\*.svg' -delete" /usr/share/amethystora/user-setup.hooks.d/16-retire-jetbrains-icons.sh
# The Security app's shield: the pack's own shield, from preferences-system-privacy, with report bars
# instead of that icon's keyhole. Both elements draw from one gradient placed in user space, because a
# second gradient, or either element left on its own bounding box, would break the diagonal across them.
SECURITY_ICON="${CANDY_DIR}/apps/scalable/amethystora-security-status.svg"
grep -q 'fill="url(#_lgradient_security_status)"' "${SECURITY_ICON}"
grep -q 'stroke="url(#_lgradient_security_status)"' "${SECURITY_ICON}"
[[ "$(grep -c "<linearGradient" "${SECURITY_ICON}")" == 1 ]]
grep -q 'gradientUnits="userSpaceOnUse"' "${SECURITY_ICON}"
# The same drawing in hicolor, so the launcher keeps its icon under any icon theme, not only candy-icons
cmp -s /ctx/build_files/shared/candy-icons/amethystora-security-status.svg \
    /usr/share/icons/hicolor/scalable/apps/amethystora-security-status.svg
# The theme is the default before an account applies a theme of its own, and the value
# amethystora-theme falls back to afterwards; the two have to name the same theme
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.interface icon-theme)" == "'candy-icons'" ]]
grep -q "^DEFAULT_ICON_THEME=candy-icons$" /usr/lib/amethystora/theme/lib.sh
# An account set up before candy-icons holds an explicit icon-theme that beats the default above,
# so the theme hook has to be past the version that only wrote the desktop's own icons
[[ "$(sed -n 's/^version-script theme user \([0-9]\+\).*/\1/p' \
    /usr/share/amethystora/user-setup.hooks.d/11-theme.sh)" -ge 2 ]]
# ...and past the one that re-applies it after 09-retire-dms.sh, which runs first
[[ "$(sed -n 's/^version-script theme user \([0-9]\+\).*/\1/p' \
    /usr/share/amethystora/user-setup.hooks.d/11-theme.sh)" -ge 5 ]]

# What the Hyprland era left behind is removed: per account by 09-retire-dms.sh, before 11-theme.sh
# re-applies the theme, and per machine by 20-retire-dms.sh. The account side keys on the names and
# signatures in DankMaterialShell's own source: its kitty.conf hides kitty's title bar (no close
# button on GNOME), its gtk.css kept the theme out of libadwaita, and its environment.d file still
# set variables for the whole session.
USER_RETIRE=/usr/share/amethystora/user-setup.hooks.d/09-retire-dms.sh
SYSTEM_RETIRE=/usr/share/amethystora/system-setup.hooks.d/20-retire-dms.sh
test -x "${USER_RETIRE}"
test -x "${SYSTEM_RETIRE}"
[[ "$(printf '%s\n' "${USER_RETIRE##*/}" 11-theme.sh | LC_ALL=C sort | head -n1)" == "${USER_RETIRE##*/}" ]]
grep -q "dank-colors" "${USER_RETIRE}"
grep -q "90-dms.conf" "${USER_RETIRE}"
# The machine side never touches a machine that has layered any of it back on, and removes the greeter
# account only by the home dms-greeter gave it
grep -q 'rpm -q "${package}"' "${SYSTEM_RETIRE}"
grep -q "== /var/lib/greeter" "${SYSTEM_RETIRE}"
# ...and nothing of that stack is in the image any more
for package in greetd dms dms-greeter quickshell hyprland; do
    rpm -q "${package}" >/dev/null 2>&1 && false
done
# Files opens on the grid, where candy-icons' folders are drawn as artwork rather than as a 16px row
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.nautilus.preferences default-folder-viewer)" == "'icon-view'" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.nautilus.icon-view default-zoom-level)" == "'large'" ]]

# ClamAV daemon listens on its socket and keeps retrying until freshclam has fetched the signatures
grep -q "^LocalSocket /run/clamd.scan/clamd.sock$" /etc/clamd.d/scan.conf
test -f /usr/lib/systemd/system/clamd@.service.d/10-amethystora.conf

# Security keys: pam_u2f ahead of the password for sudo and polkit. pam_u2f ignores its config file (and so
# the fixed origin keys are registered with) before 1.4.0, or when it is not root-owned or is writable.
grep -qE "^auth\s+sufficient\s+pam_u2f\.so" /etc/pam.d/system-auth
grep -q "^origin = pam://amethystora$" /etc/security/pam_u2f.conf
[[ "$(stat -c '%U %a' /etc/security/pam_u2f.conf)" == "root 644" ]]
[[ "$(printf '%s\n' 1.4.0 "$(rpm -q --queryformat '%{VERSION}' pam-u2f)" | sort -V | head -n1)" == 1.4.0 ]]

# Hardening (08-hardening.sh and its files in system_files)
# Updates must carry a valid signature from the key CI signs with
test -s /etc/pki/containers/amethystora.pub
jq -e '.transports.docker["ghcr.io/iarsslen"][0] == {"type": "sigstoreSigned",
    "keyPath": "/etc/pki/containers/amethystora.pub", "signedIdentity": {"type": "matchRepository"}}' \
    /etc/containers/policy.json
grep -q "use-sigstore-attachments: true" /etc/containers/registries.d/amethystora.yaml
# openSUSE Leap's images are checked against openSUSE's container keys, from its openSUSE-build-key
# package: the one that signs them today and its 2023 successor, so that a rotation keeps them pulling.
# Leap only: the rest of openSUSE's namespace there holds build projects that sign with keys of their own.
jq -e '.transports.docker["registry.opensuse.org/opensuse/leap"][0] | .type == "sigstoreSigned"
    and (.keyPaths | length == 2) and .signedIdentity.type == "matchRepository"' /etc/containers/policy.json >/dev/null
jq -r '.transports.docker["registry.opensuse.org/opensuse/leap"][0].keyPaths[]' /etc/containers/policy.json |
    xargs -r -n1 openssl pkey -pubin -noout -in
jq -e '.transports.docker | has("registry.opensuse.org") or has("registry.opensuse.org/opensuse") | not' \
    /etc/containers/policy.json >/dev/null
grep -q "use-sigstore-attachments: true" /etc/containers/registries.d/registry.opensuse.org-opensuse-leap.yaml
# The policy is the one every update is verified against, so it has to be one this containers/image
# accepts, unknown keys and all: loading it is the first thing a copy does, before it opens anything
command -v skopeo >/dev/null
POLICY_CHECK="$(skopeo copy dir:/nonexistent "dir:$(mktemp -d)" 2>&1 || true)"
grep -qi "policy" <<<"${POLICY_CHECK}" && { echo "${POLICY_CHECK}"; false; }
# Signature checking is kept on by a unit of its own, at every boot, once the network is up. It used to
# be a first-boot setup hook, whose runner reports success whatever a hook does, and the in-place switch
# that hook ran cannot work on a booted system, where /sysroot is read-only: it failed on every ISO
# install, once, without a word. The script explains all of that in comments that name the flag, so
# the check for the flag itself has to skip them.
test -x /usr/libexec/amethystora-signed-updates
grep -q "enforce-container-sigpolicy" /usr/libexec/amethystora-signed-updates
grep -vE "^[[:space:]]*#" /usr/libexec/amethystora-signed-updates | grep -q -- "--mutate-in-place" && false
grep -q "^After=network-online.target$" /usr/lib/systemd/system/amethystora-signed-updates.service
test -e /usr/share/amethystora/system-setup.hooks.d/20-signed-updates.sh && false
# bootc builds the next deployment from the image alone, so switching with it on a machine that has
# layered packages drops them at the next boot without a word. This unit runs at every boot, so it
# has to read the flag bootc sets for such a deployment and rebase with rpm-ostree instead.
grep -q '\.status\.booted\.incompatible' /usr/libexec/amethystora-signed-updates
grep -q "rpm-ostree rebase" /usr/libexec/amethystora-signed-updates
# The same command is offered to anyone following a dated tag back onto a stream
grep -q "rpm-ostree rebase ostree-image-signed" /usr/libexec/amethystora-security-status
# Everything the image claims to do, in one place, without a password, with nothing to dismiss. This is
# what makes Secure Boot and the rest surfaceable without interrupting anybody more than once. The
# recipe and the Security app read the one script, so the terminal and the window cannot tell two stories.
grep -q "^status:$" /usr/share/amethystora/just/security.just
grep -qx "    @/usr/libexec/amethystora-security-status" /usr/share/amethystora/just/security.just
/usr/libexec/amethystora-security-status >/dev/null
/usr/libexec/amethystora-security-status --json |
    jq -e '.checks | length > 0 and all(.group and .id and .state and .title and .text)' >/dev/null
grep -q "secure-boot-notified" /usr/libexec/amethystora-security-alert
# The recipe that enrolls the signing keys and the report that says whether they are enrolled ask the one
# helper. They used to check on their own and disagreed, because one of them counted a certificate it
# could not find as enrolled.
test -x /usr/libexec/amethystora-mok-status
grep -q "/usr/libexec/amethystora-mok-status" /usr/share/amethystora/just/security.just
grep -q "/usr/libexec/amethystora-mok-status" /usr/libexec/amethystora-security-status
grep -q "mokutil --test-key" /usr/share/amethystora/just/security.just && false
grep -q "mokutil --test-key" /usr/libexec/amethystora-security-status && false
# ...and what it checks has to be readable by the user asking. /etc/pki/akmods/certs is 0750
# root:akmods, so run without sudo every check there concluded the certificates did not exist.
SB_CERT=/usr/share/amethystora/secure-boot/amethystora-modules.der
[[ "$(stat -c '%a' "${SB_CERT}")" == 644 ]]
cmp -s /etc/pki/akmods/certs/amethystora-modules.der "${SB_CERT}"
# ...and in the app grid too, so it is not only behind a recipe name somebody has to already know. The
# Security app shows it in a window, where the terminal launcher it replaces used to print it.
SECURITY_DESKTOP=/usr/share/applications/amethystora-security.desktop
test ! -e /usr/share/applications/amethystora-security-status.desktop
test -s "${SECURITY_DESKTOP}"
command -v desktop-file-validate >/dev/null && desktop-file-validate "${SECURITY_DESKTOP}"
# An Exec or an Icon that resolves to nothing is a tile in the grid that does nothing, or a blank one
test -x "$(command -v "$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "${SECURITY_DESKTOP}" | head -n1)")"
test -e "/usr/share/icons/candy-icons/apps/scalable/$(sed -n 's/^Icon=//p' "${SECURITY_DESKTOP}").svg"
# Starting the whole-machine scan is the one thing its polkit rule lets through without a password, and
# only for the person at the machine
SCAN_RULE=/usr/share/polkit-1/rules.d/50-amethystora-virus-scan.rules
grep -q 'action.lookup("unit") == "amethystora-clamav-scan.service"' "${SCAN_RULE}"
grep -q 'action.lookup("verb") == "start"' "${SCAN_RULE}"
grep -q "subject.local && subject.active" "${SCAN_RULE}"
# Kernel settings, arguments and blocked modules
grep -q "^kernel.kptr_restrict = 2$" /usr/lib/sysctl.d/60-amethystora-hardening.conf
grep -q '"slab_nomerge"' /usr/lib/bootc/kargs.d/10-amethystora-hardening.toml
# modprobe reports module names with underscores, whichever spelling the config file uses
MODPROBE_CONFIG="$(modprobe --showconfig)"
for module in dccp sctp rds tipc n_hdlc firewire_core firewire_sbp2 cramfs hfs vivid; do
    grep -q "^install ${module} /usr/bin/false$" <<<"${MODPROBE_CONFIG}"
done
# No passwordless root for users who are not at the machine, and no user-writable directory in root's
# sudo PATH, and no world-writable USB devices
grep -q "<allow_any>no</allow_any>" /usr/share/polkit-1/actions/*privileged.user.setup.policy
grep -q "polkit.Result.NO" /usr/share/polkit-1/rules.d/10-amethystora-privileged-setup.rules
test -x /usr/bin/amethystora-privileged-setup
grep -E "^Defaults[[:space:]]+secure_path" /etc/sudoers | grep -q linuxbrew && false
if [[ -f /usr/lib/udev/rules.d/50-zsa.rules ]]; then
    grep -q 'MODE:="0666"' /usr/lib/udev/rules.d/50-zsa.rules && false
    grep -q 'TAG+="uaccess"' /usr/lib/udev/rules.d/50-zsa.rules
fi
# Firewall: the Amethystora zone, without Fedora Workstation's open port range
[[ "$(firewall-offline-cmd --get-default-zone)" == "amethystora" ]]
[[ -z "$(firewall-offline-cmd --zone=amethystora --list-ports)" ]]
firewall-offline-cmd --zone=trusted --query-interface=tailscale0
# Account lockout, and the SSH server's settings for when it is turned on
grep -q "pam_faillock.so" /etc/pam.d/system-auth
grep -q "^deny = 10$" /etc/security/faillock.conf
# ...and fingerprint login last, where the installer puts it (08-hardening.sh)
[[ "$(tail -n1 /etc/authselect/authselect.conf)" == "with-fingerprint" ]]
grep -q "^PermitRootLogin no$" /etc/ssh/sshd_config.d/40-amethystora-hardening.conf
grep -qE "^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf" /etc/ssh/sshd_config

# fail2ban: only the sshd jail is on, it reads the journal, and it bans through firewalld.
# `fail2ban-client -d` is the dump Lynis (TOOL-5104) reads the jails from, so what it shows here is
# what Lynis sees on the installed system. 08-hardening.sh checks the ban zone is the default zone.
test -f /etc/fail2ban/jail.d/10-amethystora.conf
F2B_DUMP="$(fail2ban-client -d)"
grep -q "'sshd'" <<<"${F2B_DUMP}"
grep -q "'systemd'" <<<"${F2B_DUMP}"
grep -q "firewallcmd-rich-rules" <<<"${F2B_DUMP}"
# The ban database's directory is created at every boot, not only shipped in the image: /var reaches a
# machine once, when it is installed, so on a machine installed before fail2ban was in the image it
# never existed, and fail2ban exited with 255 straight after "Server ready". The path created has to
# be the one fail2ban.conf actually names.
grep -q "^d /var/lib/fail2ban " /usr/lib/tmpfiles.d/fail2ban-var.conf
grep -qE "^dbfile = /var/lib/fail2ban/" /etc/fail2ban/fail2ban.conf
# Lynis audits the machine against the image's profile (ame security audit); it reads every
# .prf in /etc/lynis, so the image's settings only apply while Lynis finds this one
test -f /etc/lynis/default.prf
grep -q "^machine-role=workstation$" /etc/lynis/custom.prf
lynis show profiles | grep -F "/etc/lynis/custom.prf" >/dev/null

# Flatpak: X11, the whole of /dev and the Flatpak service are taken away from every application,
# whatever its own manifest asks for. Flatseal is how they are granted back, one application at a time.
FLATPAK_OVERRIDES=/etc/flatpak/overrides/global
grep -q "^sockets=!x11;!fallback-x11;$" "${FLATPAK_OVERRIDES}"
grep -q "^devices=!all;!input;$" "${FLATPAK_OVERRIDES}"
grep -q "^org.freedesktop.Flatpak=none$" "${FLATPAK_OVERRIDES}"
test -f /usr/share/flatpak/preinstall.d/flatseal.preinstall

# Kernel lockdown: on everywhere except the NVIDIA images, whose driver is a machine-owner-key module
# that a machine with Secure Boot turned off would no longer be able to load
LOCKDOWN_KARGS=/usr/lib/bootc/kargs.d/11-amethystora-lockdown.toml
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    test -e "${LOCKDOWN_KARGS}" && false
else
    grep -q '"lockdown=integrity"' "${LOCKDOWN_KARGS}"
fi

# Key remapping runs as root and reads every input device, so it ships installed and switched off.
# `ame security input-remapper` is how someone who remaps keys turns it on.
rpm -q input-remapper >/dev/null
[[ "$(systemctl is-enabled input-remapper.service 2>/dev/null)" == "enabled" ]] && false
# Same for USB protection, which blocks every device that was not present when it was set up: useless
# as a default, because the first boot would block the keyboard nobody had allowed yet
[[ "$(systemctl is-enabled usbguard.service 2>/dev/null)" == "enabled" ]] && false
# And for browser protection, the extension list and the block on web pages reaching hardware. The
# image ships Firefox unaltered, so the policy is only data here, and `ame security browser`
# writes it on the machine that asks: for Chromium-based browsers and for Firefox, each in its own
# form. Neither installs an extension, it only allows some
BROWSER_POLICY=/usr/libexec/amethystora-browser-policy
test -x "${BROWSER_POLICY}"
[[ "$("${BROWSER_POLICY}" status)" == off ]]
grep -q "^browser " /usr/share/amethystora/just/security.just
/usr/libexec/amethystora-security-status --json |
    jq -e 'any(.checks[]; .id == "browser-protection" and .state == "off")' >/dev/null
"${BROWSER_POLICY}" show chromium |
    jq -e '.ExtensionInstallBlocklist == ["*"] and (.ExtensionInstallAllowlist | length > 0)
        and (has("ExtensionSettings") or has("ExtensionInstallForcelist") | not)' >/dev/null
for guard in DefaultWebHidGuardSetting DefaultWebUsbGuardSetting DefaultSerialGuardSetting DefaultWebBluetoothGuardSetting; do
    "${BROWSER_POLICY}" show chromium | jq -e ".${guard} == 2" >/dev/null
done
"${BROWSER_POLICY}" show firefox |
    jq -e 'has("amethystora") and (.policies.ExtensionSettings["*"].allowed_types | index("extension") | not)
        and ([.policies.ExtensionSettings[] | .installation_mode // "allowed"] | all(. == "allowed"))' >/dev/null

# Audit rules: the watches that ship with the image, and the generator for the per-user ones, which
# can only be written on a machine that already has home directories
AUDIT_RULES=/etc/audit/rules.d/60-amethystora.rules
grep -q "^-w /etc/flatpak/overrides/ -p wa -k hardening$" "${AUDIT_RULES}"
grep -q "^-w /etc/containers/policy.json -p wa -k hardening$" "${AUDIT_RULES}"
# A watch needs its path to be there when the rules load, and this one is the Firefox package's
grep -q "^-w /etc/firefox/ -p wa -k hardening$" "${AUDIT_RULES}"
test -d /etc/firefox
grep -q "dir=/dev/input" "${AUDIT_RULES}"
test -x /usr/libexec/amethystora-audit-home-rules
# One line augenrules cannot parse stops every rule in the directory from loading, which would leave
# the machine silently unaudited. auditctl cannot be asked about it during a container build, where
# there is no audit netlink socket to talk to, so the shape of each rule is what gets checked.
grep -vE '^[[:space:]]*(#|$)' "${AUDIT_RULES}" | grep -qvE '^-(w|a) ' && false

# The key the update policy names, not only the policy file that names it: a watch on policy.json
# alone watches the lock and not the key.
for path in /etc/pki/containers/ /etc/containers/registries.d/ /etc/pki/akmods/certs/; do
    grep -q "^-w ${path} -p wa -k hardening$" "${AUDIT_RULES}"
done

# How the rule set ends. augenrules concatenates every .rules file in this directory in name order and
# loads the result, so this reproduces that concatenation and checks it, rather than checking the files
# one at a time: a -D ("delete every rule loaded so far") in a file that sorts after ours would erase
# the whole lot, which is why 08-hardening.sh renames the file the audit package ships.
AUDIT_CONCAT="$(find /etc/audit/rules.d -name '*.rules' -printf '%p\n' | LC_ALL=C sort |
    while read -r rules; do cat "${rules}"; done)"
AUDIT_DIRECTIVES="$(grep -vE '^[[:space:]]*(#|$)' <<<"${AUDIT_CONCAT}" || true)"
# Immutable, and it is the last word
[[ "$(tail -n1 <<<"${AUDIT_DIRECTIVES}")" == "-e 2" ]]
# The audit backlog may never make a process wait: a watch on /dev/input would stop the session
grep -q -- "--backlog_wait_time 0" <<<"${AUDIT_DIRECTIVES}"
LAST_DELETE="$(grep -n '^-D$' <<<"${AUDIT_DIRECTIVES}" | tail -n1 | cut -d: -f1 || true)"
FIRST_WATCH="$(grep -n '^-w ' <<<"${AUDIT_DIRECTIVES}" | head -n1 | cut -d: -f1 || true)"
[[ -n "${FIRST_WATCH}" ]]
[[ -z "${LAST_DELETE}" || "${LAST_DELETE}" -lt "${FIRST_WATCH}" ]]

# A full disk may never halt or suspend somebody's laptop. A gap in the audit log is the lesser loss,
# so the actions that stop the machine are the ones this asserts are absent.
grep -q "^max_log_file = 32$" /etc/audit/auditd.conf
grep -qiE "^(space_left_action|admin_space_left_action|disk_full_action|disk_error_action) = (halt|single|suspend)$" \
    /etc/audit/auditd.conf && false

# The per-home watches reach the kernel through the load auditd does as it starts, because once -e 2 is
# in the rule set a second `augenrules --load` is refused.
grep -qE "^Before=auditd.service( |$)" /usr/lib/systemd/system/amethystora-audit-rules.service
grep -qE "^After=auditd.service" /usr/lib/systemd/system/amethystora-audit-rules.service && false
# auditd starts before sysinit.target, so a unit ordered before it has to as well: with the default
# dependencies it sits after sysinit.target, and systemd breaks the cycle by not starting auditd
grep -q "^DefaultDependencies=no$" /usr/lib/systemd/system/amethystora-audit-rules.service
grep -q "^Before=.*sysinit.target" /usr/lib/systemd/system/amethystora-audit-rules.service
grep -q "^Before=.*sysinit.target" /usr/lib/systemd/system/auditd.service

# Weekly virus scan and monthly Lynis audit. What is done with a found file is ON_DETECTION's to say,
# through the one helper, never a clamdscan flag in a script. It ships as report: a false positive that
# takes away a file the user wanted is worse than most of what it would be removing.
test -x /usr/libexec/amethystora-clamav-scan
grep -vE "^[[:space:]]*#" /usr/libexec/amethystora-clamav-scan | grep -qE "(--remove|--move=)" && false
test -x /usr/libexec/amethystora-security-config
test -x /usr/libexec/amethystora-quarantine
[[ "$(/usr/libexec/amethystora-security-config ON_DETECTION)" == report ]]
[[ "$(/usr/libexec/amethystora-security-config REALTIME)" == off ]]
grep -q "^ON_DETECTION=report$" /etc/amethystora/security.conf
for script in amethystora-clamav-scan amethystora-clamav-onaccess; do
    grep -q "/usr/libexec/amethystora-quarantine act" "/usr/libexec/${script}"
done
# The helper scans each file again itself before it acts, whoever called it
grep -q "clamdscan --fdpass" /usr/libexec/amethystora-quarantine
grep -q "^d /var/lib/amethystora/quarantine 0700 root root" /usr/lib/tmpfiles.d/amethystora-security.conf
grep -q "^settings " /usr/share/amethystora/just/security.just
grep -q '"Put a file back" | restore)' /usr/share/amethystora/just/security.just

# Real-time watching and scanning: enabled, but each unit skips itself unless REALTIME=on, the way the
# setting is meant to switch it rather than a unit somebody has to know about. The watcher's trigger also
# runs while network protection is on, to follow Suricata's alerts, and asks its script whether to.
grep -q "^ExecCondition=/usr/libexec/amethystora-security-config --is REALTIME on$" \
    /usr/lib/systemd/system/amethystora-clamav-onaccess.service
grep -q "^ExecCondition=/usr/libexec/amethystora-security-realtime --check$" \
    /usr/lib/systemd/system/amethystora-security-realtime.service
/usr/libexec/amethystora-security-realtime --check && false
command -v clamonacc >/dev/null
grep -q "^OnAccessIncludePath /var/home$" /etc/clamd.d/scan.conf
# Without this, every file the weekly scan opens as root would be scanned a second time
grep -q "^OnAccessExcludeRootUID yes$" /etc/clamd.d/scan.conf

# The security watcher reads what the audit rules record: every key the rules write has to be one the
# watcher reads and the real-time trigger follows, or those events are recorded for nobody. The rules in
# home folders are written at boot by amethystora-audit-home-rules, and its keys count too.
test -x /usr/libexec/amethystora-security-watch
test -x /usr/libexec/amethystora-security-realtime
grep -q "^OnFailure=amethystora-scan-alert@%n.service$" /usr/lib/systemd/system/amethystora-security-watch.service
grep -q -- "-k user-programs" /usr/libexec/amethystora-audit-home-rules
for key in $( { grep -ohE -- '-k [a-z-]+$' /etc/audit/rules.d/60-amethystora.rules | cut -d' ' -f2
    grep -ohE -- '(-k |key=)[a-z-]+' /usr/libexec/amethystora-audit-home-rules | sed -E 's/^(-k |key=)//'; } | sort -u); do
    grep -E "^AUDIT_KEYS=\(" /usr/libexec/amethystora-security-watch | grep -qw -- "${key}"
    grep -E "^KEYS=" /usr/libexec/amethystora-security-realtime | grep -qw -- "${key}"
done
# ...and a watch on a path that is not there stops every rule after it from loading
for path in $(grep -oE '^-w [^ ]+' /etc/audit/rules.d/60-amethystora.rules | cut -d' ' -f2); do
    test -e "${path}"
done
# Its checks are the report's: the watcher runs the report rather than keeping checks of its own
grep -q "/usr/libexec/amethystora-security-status --json" /usr/libexec/amethystora-security-watch
grep -q "^events " /usr/share/amethystora/just/security.just
/usr/libexec/amethystora-security-status --json |
    jq -e '.settings.on_detection == "report" and .settings.realtime == "off" and .settings.network == "off"' >/dev/null

# Network protection (amethystora-ips): Suricata inline, enabled but skipped while NETWORK=off, which is
# how the image ships. Whatever goes wrong with it has to cost inspection and never the network: the
# table lets traffic through while nothing reads the queue, and the configuration 14-security.sh derives
# fails open, logs only alerts, and bypasses with the mark the table tests. That configuration has to be
# one this Suricata loads; its rules are downloaded on the machine, so one rule stands in for them.
command -v suricata-update >/dev/null
test -x /usr/libexec/amethystora-ips
# Its account has the fixed ID 04-packages.sh gives it, not one taken from the other accounts' range
[[ "$(id -u suricata):$(id -g suricata)" == "850:850" ]]
[[ "$(/usr/libexec/amethystora-security-config NETWORK)" == off ]]
grep -q "^NETWORK=off$" /etc/amethystora/security.conf
/usr/libexec/amethystora-ips enabled && false
[[ "$(systemctl is-enabled suricata.service 2>/dev/null)" == "enabled" ]] && false
for unit in amethystora-ips amethystora-ips-rules; do
    grep -q "^ExecCondition=/usr/libexec/amethystora-ips enabled$" "/usr/lib/systemd/system/${unit}.service"
done
grep -q "^OnFailure=amethystora-scan-alert@%n.service$" /usr/lib/systemd/system/amethystora-ips.service
IPS_TABLE=/usr/share/amethystora/ips/amethystora-ips.nft
grep -qE "^ +queue " "${IPS_TABLE}"
grep -E "^ +queue " "${IPS_TABLE}" | grep -v " flags bypass " && false
grep -q "ct mark 0x10000000 accept" "${IPS_TABLE}"
IPS_CONFIG=/usr/share/amethystora/ips/suricata.yaml
IPS_DUMP="$(suricata --dump-config -c "${IPS_CONFIG}")"
for setting in "nfq.fail-open = yes" "nfq.bypass-mark = 268435456" "exception-policy = ignore" \
    "stream.drop-invalid = no" "outputs.0.eve-log.types.0.alert.payload = no"; do
    grep -qxF "${setting}" <<<"${IPS_DUMP}"
done
grep -q "^outputs\.1\." <<<"${IPS_DUMP}" && false
IPS_TEST="$(mktemp -d)"
echo 'drop tcp any any -> any 9 (msg:"amethystora-ips build test"; sid:1; rev:1;)' >"${IPS_TEST}/test.rules"
# Everything it writes goes to the temporary directory. Suricata 8 caches what it compiles in
# /var/lib/suricata/cache/sgh by default, and making that here remade the /var/lib clean-stage.sh had
# removed, as 0750: see the check on /var/lib at the end of this file for what that did.
suricata -T -c "${IPS_CONFIG}" -S "${IPS_TEST}/test.rules" -l "${IPS_TEST}" \
    --set detect.sgh-mpm-caching-path="${IPS_TEST}"
rm -rf "${IPS_TEST}"
for dir in "lib/suricata 2770" "log/suricata 0750"; do
    grep -q "^d /var/${dir} suricata suricata " /usr/lib/tmpfiles.d/amethystora-security.conf
done
grep -q "^connections " /usr/share/amethystora/just/security.just
grep -q "amethystora-ips.service" /usr/libexec/amethystora-scan-alert
/usr/libexec/amethystora-security-status --json |
    jq -e 'any(.checks[]; .id == "network-protection" and .state == "off")' >/dev/null
grep -q "^ExcludePath \^/proc/$" /etc/clamd.d/scan.conf
grep -q "^ExcludePath \^/var/lib/flatpak/$" /etc/clamd.d/scan.conf
# The caches left out of the scan are under /var/home, where this system keeps home directories
grep -qF 'ExcludePath ^/var/home/[^/]+/\.cache/' /etc/clamd.d/scan.conf

# A finding nobody is told about is not a finding. Every way either scan can end badly fails its unit,
# and the failure reaches the person at the machine: OnFailure while they are logged in, and the login
# check for what happened while they were not.
test -x /usr/libexec/amethystora-notify-users
test -x /usr/libexec/amethystora-scan-alert
test -x /usr/libexec/amethystora-security-alert
test -x /usr/libexec/amethystora-lynis-audit
test -f /usr/lib/systemd/system/amethystora-scan-alert@.service
for unit in amethystora-clamav-scan amethystora-lynis-audit; do
    grep -q "^OnFailure=amethystora-scan-alert@%n.service$" "/usr/lib/systemd/system/${unit}.service"
done
grep -q "^ExecStart=/usr/libexec/amethystora-lynis-audit$" \
    /usr/lib/systemd/system/amethystora-lynis-audit.service
test -L /etc/systemd/user/graphical-session.target.wants/amethystora-security-alert.service
# clamd not starting is the likeliest reason a machine is not being scanned, and a Requires= on it would
# cancel this job rather than fail it, which runs no OnFailure at all. The scan has to reach the script.
grep -q "^Wants=clamd@scan.service$" /usr/lib/systemd/system/amethystora-clamav-scan.service
grep -qE "^Requires=" /usr/lib/systemd/system/amethystora-clamav-scan.service && false

# Signature age is what says whether a clean scan means anything; `systemctl is-active` of the freshclam
# daemon does not, because it stays active whether or not a download ever succeeded. The image ships no
# signatures, so the helper reports exactly that here rather than a number.
test -x /usr/libexec/amethystora-clamav-signature-age
SIGNATURE_AGE_RC=0
/usr/libexec/amethystora-clamav-signature-age || SIGNATURE_AGE_RC=$?
[[ "${SIGNATURE_AGE_RC}" -eq 1 ]]
grep -q "amethystora-clamav-signature-age" /usr/libexec/amethystora-clamav-scan
grep -q "amethystora-clamav-signature-age" /usr/share/amethystora/just/security.just

# Backups. The helper never removes anything from the repository: an append-only repository is the
# whole of the defence against ransomware, and a client able to delete from one gives that away.
test -x /usr/libexec/amethystora-backup
test -s /usr/share/amethystora/backup-excludes
test -f /usr/lib/systemd/user/amethystora-backup.service
test -f /usr/lib/systemd/user/amethystora-backup.timer
grep -vE "^[[:space:]]*#" /usr/libexec/amethystora-backup | grep -qE "restic +(forget|prune)" && false

# Ransomware protection: hourly read-only snapshots of /var/home, off until `ame
# security ransomware` because they cost disk space. Both virus scans leave the snapshots out,
# or they would read every home folder once for each snapshot kept.
test -x /usr/libexec/amethystora-home-snapshot
test -f /usr/lib/systemd/system/amethystora-home-snapshot.service
test -f /usr/lib/systemd/system/amethystora-home-snapshot.timer
[[ "$(systemctl is-enabled amethystora-home-snapshot.timer 2>/dev/null)" == "enabled" ]] && false
command -v btrfs >/dev/null
grep -qF 'ExcludePath ^/var/home/\.snapshots/' /etc/clamd.d/scan.conf
grep -qF 'echo /var/home/.snapshots' /usr/libexec/amethystora-clamav-onaccess

# TPM disk unlock (ame security disk-unlock) only works if the initramfs can talk to the TPM at all.
# 19-initramfs.sh adds dracut's tpm2-tss module where dracut has it, and warns where it does not.
grep -q "tss2" <<<"${INITRAMFS_FILES}" ||
    echo "::warning::no TPM2 libraries in the initramfs, ame security disk-unlock will not work"

# DisplayLink: evdi built for the image kernel, and no module signing key left behind by the build
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
modinfo "/usr/lib/modules/${KERNEL_VERSION}/extra/evdi/evdi.ko.xz" >/dev/null
test -f /usr/lib/udev/rules.d/99-displaylink.rules
systemctl is-enabled displaylink.service
grep -q "^d /var/log/displaylink " /usr/lib/tmpfiles.d/displaylink.conf
# DisplayLinkManager is proprietary. Its licence lets it be redistributed unmodified, and only with
# the licence itself beside it
test -s /usr/share/licenses/displaylink/LICENSE
find /etc/pki/akmods/private -type f 2>/dev/null | grep -q . && false
# ame security secure-boot enrolls both: the one evdi is signed with and the kernel's
test -f /etc/pki/akmods/certs/amethystora-modules.der
test -f /etc/pki/akmods/certs/akmods-amethystora.der

# Make sure this garbage never makes it to an image
test -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service && false

IMPORTANT_PACKAGES=(
    audit
    clamav
    clamav-freshclam
    clamd
    displaylink
    distrobox
    dotnet-sdk-10.0
    fail2ban-firewalld
    fail2ban-server
    firefox
    fish
    flatpak
    gdm
    gnome-shell
    lynis
    mutter
    pam-u2f
    pamu2fcfg
    pipewire
    ptyxis
    restic
    suricata
    systemd
    tailscale
    tpm2-tools
    usbguard
    uupd
    wireplumber
    zsh
)

for package in "${IMPORTANT_PACKAGES[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1 ; }
done

# The agentic features. The agents themselves install into each user's home (amethystora-agent
# install); a copy in /usr/bin would be one the user cannot update. A skill's name has to match its
# directory, or Claude Code and opencode skip it.
test -e /usr/bin/claude && false
test -e /usr/bin/opencode && false
test -x /usr/bin/amethystora-agent
test -x /usr/share/amethystora/user-setup.hooks.d/13-agentic.sh
for skill in amethystora amethystora-diagnose; do
    grep -qx "name: ${skill}" "/usr/share/amethystora/agents/skills/${skill}/SKILL.md"
done
grep -q "^toggle:" /usr/share/amethystora/just/agent.just
grep -q "^install " /usr/share/amethystora/just/agent.just

# these packages are supposed to be removed
# and are considered footguns
UNWANTED_PACKAGES=(
    akmod-evdi
    fedora-logos
    gnome-software
    gnome-software-rpm-ostree
    podman-docker
)

for package in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        echo "Unwanted package found: ${package}... Exiting"; exit 1
    fi
done

if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
  NV_PACKAGES=(
      libnvidia-container-tools
      kmod-nvidia
      nvidia-driver-cuda
)
  for package in "${NV_PACKAGES[@]}"; do
      rpm -q "${package}" >/dev/null || { echo "Missing NVIDIA package: ${package}... Exiting"; exit 1 ; }
  done
fi

IMPORTANT_UNITS=(
    clamav-freshclam.service
    clamd@scan.service
    fail2ban.service
    gdm.service
    rpm-ostree-countme.timer
    tailscaled.service
    uupd.timer
    auditd.service
    amethystora-audit-rules.service
    amethystora-clamav-scan.timer
    amethystora-lynis-audit.timer
    amethystora-security-watch.timer
    amethystora-security-realtime.service
    amethystora-clamav-onaccess.service
    amethystora-ips.service
    amethystora-ips-rules.timer
    amethystora-system-setup.service
    amethystora-signed-updates.service
    amethystora-gpu-check.timer
  )

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

# Last, after everything above has run: the rechunker copies /var/lib onto /usr/lib with
# `rsync ./var/lib/ ./usr/lib/`, which gives /usr/lib the mode of /var/lib. clean-stage.sh removes
# /var/lib, so one here was made by something in this build since, with whatever mode that chose. A
# /usr/lib that is not 0755 locks every service that does not run as root out of its own program
# (polkit, systemd-resolved, the login screen's user manager), and the machine boots to a black screen.
if [[ -e /var/lib ]]; then
    [[ "$(stat -c '%a %U %G' /var/lib)" == "755 root root" ]] ||
        { echo "/var/lib is $(stat -c '%a %U %G' /var/lib); the rechunker would give /usr/lib that mode"; exit 1; }
fi
[[ "$(stat -c '%a %U %G' /usr/lib)" == "755 root root" ]]

echo "::endgroup::"
