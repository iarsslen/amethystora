#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# No Bluefin / Universal Blue names left in paths or text (07-debrand.sh)
python3 /ctx/build_files/shared/debrand.py --check

for i in bin/ujust share/amethystora/just/{00-entry.just,apps.just,default.just,system.just,update.just,60-custom.just} ; do
   stat /usr/$i
done

test -f /usr/share/amethystora/homebrew/fonts.Brewfile
test -x /usr/bin/amethystora-fastfetch
# Logo in the text console colours (amethystora-greeting)
test -f /usr/share/amethystora/logos/console/amethystora
test -x /usr/libexec/amethystora-greeting
test -f /usr/lib/amethystora/setup-services/libsetup.sh

# If this file is not on the image bazaar will automatically be removed from users systems :(
# See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall
test -f /usr/share/flatpak/preinstall.d/clamui.preinstall

# Brave replaces Firefox; it lives under /usr/lib and is linked into /var/opt at boot
test -x /usr/lib/brave.com/brave/brave
test -f /usr/lib/tmpfiles.d/brave-browser.conf
test -f /usr/share/applications/brave-browser.desktop
grep -q "^x-scheme-handler/https=brave-browser.desktop" /etc/xdg/mimeapps.list
grep -q "org.mozilla.firefox" /usr/share/amethystora/homebrew/system-flatpaks.Brewfile && false
rpm -q firefox >/dev/null && false
# Brave is pinned in the dash, where Firefox was
FAVORITES="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps)"
grep -q "'brave-browser.desktop'" <<<"${FAVORITES}"
grep -qi "firefox" <<<"${FAVORITES}" && false

# Animated boot splash: the script theme, the images it loads, and both in the initramfs, which shows the
# splash up to and including the LUKS password prompt
[[ "$(plymouth-set-default-theme)" == "amethystora" ]]
rpm -q plymouth-plugin-script >/dev/null
test -f /usr/share/plymouth/themes/amethystora/amethystora.script
for image in nebula halo dust gem light shard-0 wordmark credit field dot; do
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
test -f /usr/share/backgrounds/amethystora/amethystora-l.png
test -f /usr/share/backgrounds/amethystora/amethystora-d.png
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri-dark)" == "'file:///usr/share/backgrounds/amethystora/amethystora-d.png'" ]]

# Login screen background (12-login-screen.sh): the sky the boot splash ends on, blurred and with
# no gem in it. GNOME reads the login background from the shell's own stylesheet and nowhere else,
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

# Top bar: the Logo Menu button draws the coloured Amethystora gem, entry 30 of the extension's
# coloured list (index 29), whose artwork 06-branding.sh replaces. Symbolic icons are off, so the
# panel shows the gem's own purple instead of a white silhouette. The files keep their upstream
# names until 07-debrand.sh renames them.
LOGOMENU=/usr/share/gnome-shell/extensions/logomenu@aryan_k
LOGOMENU_DCONF=/etc/dconf/db/distro.d/04-amethystora-logomenu-extension
cmp -s "${LOGOMENU}/Resources/amethystora-logo-symbolic.svg" \
    /usr/share/icons/hicolor/scalable/actions/amethystora-logo-symbolic.svg
cmp -s "${LOGOMENU}/Resources/amethystora-logo.svg" \
    /usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg
grep -q "^symbolic-icon=false$" "${LOGOMENU_DCONF}"
grep -q "^menu-button-icon-image=29$" "${LOGOMENU_DCONF}"
[[ "$(sed -n '/ColouredDistroIcons/,/^\];/p' "${LOGOMENU}/constants.js" |
    grep -oE "/Resources/[^']+" | sed -n '30p')" == "/Resources/amethystora-logo.svg" ]]
# The symbolic entry stays branded too: the Framework and Thelio Astra hooks and anyone switching
# symbolic icons back on in Extension Manager land on entry 31 of the symbolic list.
[[ "$(sed -n '/SymbolicDistroIcons/,/^\];/p' "${LOGOMENU}/constants.js" |
    grep -oE "/Resources/[^']+" | sed -n '30p')" == "/Resources/amethystora-logo-symbolic.svg" ]]

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

# Tiling and top bar: each extension from extensions.gnome.org is installed, enabled, supports this
# GNOME, and has its schema readable system-wide so the defaults in zz1-amethystora-modifications apply
GNOME_MAJOR="$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)"
for extension in tactile@lundal.io tophat@fflewddur.github.io \
    just-perfection-desktop@just-perfection space-bar@luchrioh; do
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
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.tactile col-3)" == "1" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.tactile row-1)" == "1" ]]

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
# Application windows are on the glass too, every one of them rather than a named few
grep -q "^enable-all=true$" "${BMS_DCONF}"
[[ "$(sed -n '/^\[org\/gnome\/shell\/extensions\/blur-my-shell\/applications\]$/,/^$/p' "${BMS_DCONF}" |
    grep -c '^blur=true$')" == 1 ]]

# Six fixed workspaces on Super+N, which moves the dash to Alt+N
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.wm.preferences num-workspaces)" == "6" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.mutter dynamic-workspaces)" == "false" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.wm.keybindings switch-to-workspace-6)" == "['<Super>6']" ]]
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.keybindings switch-to-application-1)" == "['<Alt>1']" ]]
# The Amethystora keybindings are appended to the base image's list, not substituted for it (09-desktop.sh)
CUSTOM_KEYBINDINGS="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
grep -q "custom0/'" <<<"${CUSTOM_KEYBINDINGS}"
for index in 20 21 22 23 24 25 26; do
    grep -q "custom${index}/'" <<<"${CUSTOM_KEYBINDINGS}"
    grep -q "^\[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}\]$" \
        /etc/dconf/db/distro.d/06-amethystora-keybindings
done

# Theme switching: the CLI, its library, the templates every theme renders, and the themes themselves
test -x /usr/bin/amethystora-theme
test -x /usr/bin/amethystora-menu
test -f /usr/lib/amethystora/theme/lib.sh
test -f /usr/share/amethystora/keybindings.md
test -x /usr/share/amethystora/theme-set.hooks.d/10-vscode.sh
test -x /usr/share/amethystora/user-setup.hooks.d/11-theme.sh
for template in btop.theme ptyxis.palette starship.toml wallpaper.svg; do
    test -f "/usr/share/amethystora/themed/${template}.tpl"
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
rpm -q breeze-icon-theme >/dev/null && false
# Gaps fall through to Adwaita, not to Plasma's Breeze
grep -qx "Inherits=Adwaita,hicolor" "${CANDY_DIR}/index.theme"
# No symbolic name outside places/ may point at the full-colour art: GTK cannot recolour it, so the
# panel would carry gradient glyphs that ignore the colour amethystora-theme sets on the top bar
[[ -z "$(find "${CANDY_DIR}"/{apps,devices,mimetypes,preferences,status} -type l -name '*-symbolic.svg')" ]]
test -e "${CANDY_DIR}/places/16/folder-symbolic.svg"
# The apps this image ships that upstream has no icon of its own for, and Thunderbird, whose
# artwork upstream only files under the capitalised app id
for icon in org.gnome.Ptyxis io.github.kolunmi.Bazaar io.github.linx_systems.ClamUI \
    org.gnome.Papers com.mattjakeman.ExtensionManager org.mozilla.thunderbird \
    be.alexandervanhee.gradia org.freedesktop.MalcontentControl it.mijorus.smile \
    org.gnome.Decibels org.gnome.Tour io.github.flattool.Warehouse page.tesk.Refine \
    io.github.flattool.Ignition io.gitlab.adhami3310.Impression input-remapper nordvpn-gui \
    org.gnome.Sysprof \
    amethystora-docs amethystora-community amethystora-update amethystora-security-status; do
    test -e "${CANDY_DIR}/apps/scalable/${icon}.svg"
done
# Icons drawn for this image, in the pack's style, for what upstream has no artwork for and nothing
# near enough to alias to. A real file, not the dangling symlink a missing source would leave.
for icon in /ctx/build_files/shared/candy-icons/*.svg; do
    test -s "${CANDY_DIR}/apps/scalable/$(basename "${icon}")"
    cmp -s "${icon}" "${CANDY_DIR}/apps/scalable/$(basename "${icon}")"
done
# NordVPN's mark is filled with one gradient, the way the pack draws every other VPN client
grep -q 'fill="url(#_lgradient_nordvpn)"' "${CANDY_DIR}/apps/scalable/nordvpn.svg"
# Claude's mark the same way. Nothing in the image looks it up yet - the claude-code rpm ships no
# desktop entry - so this line is all that stands between a drawing mistake and nobody noticing.
grep -q 'fill="url(#_lgradient_claude)"' "${CANDY_DIR}/apps/scalable/claude.svg"
# The Security Report shield: the pack's own shield, from preferences-system-privacy, with report bars
# instead of that icon's keyhole. Both elements draw from one gradient placed in user space, because a
# second gradient, or either element left on its own bounding box, would break the diagonal across them.
SECURITY_ICON="${CANDY_DIR}/apps/scalable/amethystora-security-status.svg"
grep -q 'fill="url(#_lgradient_security_status)"' "${SECURITY_ICON}"
grep -q 'stroke="url(#_lgradient_security_status)"' "${SECURITY_ICON}"
[[ "$(grep -c "<linearGradient" "${SECURITY_ICON}")" == 1 ]]
grep -q 'gradientUnits="userSpaceOnUse"' "${SECURITY_ICON}"
# The theme is the default before an account applies a theme of its own, and the value
# amethystora-theme falls back to afterwards; the two have to name the same theme
[[ "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.interface icon-theme)" == "'candy-icons'" ]]
grep -q "^DEFAULT_ICON_THEME=candy-icons$" /usr/lib/amethystora/theme/lib.sh
# An account set up before candy-icons holds an explicit icon-theme that beats the default above,
# so the theme hook has to be past the version that only wrote the desktop's own icons
[[ "$(sed -n 's/^version-script theme user \([0-9]\+\).*/\1/p' \
    /usr/share/amethystora/user-setup.hooks.d/11-theme.sh)" -ge 2 ]]
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
test -x /usr/share/amethystora/system-setup.hooks.d/20-signed-updates.sh
# Verification is re-checked at every boot rather than pinned once: a later `bootc switch` turns it off
# again, and a machine in that state looks no different from one that is still checking. The hook says
# so in a comment of its own, the way 30-grub-theme.sh does, so this has to look for the directive at
# the start of a line and not for the word.
grep -qE "^[[:space:]]*version-script" /usr/share/amethystora/system-setup.hooks.d/20-signed-updates.sh && false
# Everything the image claims to do, in one place, without a password, with nothing to dismiss. This is
# what makes Secure Boot and the rest surfaceable without interrupting anybody more than once.
grep -q "^security-status:$" /usr/share/amethystora/just/60-custom.just
grep -q "secure-boot-notified" /usr/libexec/amethystora-security-alert
# ...and in the app grid too, so it is not only behind a recipe name somebody has to already know.
SECURITY_DESKTOP=/usr/share/applications/amethystora-security-status.desktop
test -s "${SECURITY_DESKTOP}"
command -v desktop-file-validate >/dev/null && desktop-file-validate "${SECURITY_DESKTOP}"
# Terminal=true is what gives the launcher something to draw the report in
grep -q "^Terminal=true$" "${SECURITY_DESKTOP}"
# An Exec or an Icon that resolves to nothing is a tile in the grid that does nothing, or a blank one
test -x "$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "${SECURITY_DESKTOP}")"
test -e "/usr/share/icons/candy-icons/apps/scalable/$(sed -n 's/^Icon=//p' "${SECURITY_DESKTOP}").svg"
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
# Lynis audits the machine against the image's profile (ujust security-audit); it reads every
# .prf in /etc/lynis, so the image's settings only apply while Lynis finds this one
test -f /etc/lynis/default.prf
grep -q "^machine-role=workstation$" /etc/lynis/custom.prf
lynis show profiles | grep -q "/etc/lynis/custom.prf"

# Flatpak: X11, the whole of /dev and the Flatpak service are taken away from every application,
# whatever its own manifest asks for. Flatseal is how they are granted back, one application at a time.
FLATPAK_OVERRIDES=/etc/flatpak/overrides/global
grep -q "^sockets=!x11;!fallback-x11;$" "${FLATPAK_OVERRIDES}"
grep -q "^devices=!all;!input;$" "${FLATPAK_OVERRIDES}"
grep -q "^org.freedesktop.Flatpak=none$" "${FLATPAK_OVERRIDES}"
test -f /usr/share/flatpak/preinstall.d/flatseal.preinstall

# Browser policy. 08-hardening.sh puts it in whichever directory the Brave binary actually reads, so
# this looks for where it ended up rather than assuming: a policy nothing reads is the failure here.
BRAVE_POLICY="$(find /etc -path '*/policies/managed/10-amethystora.json' -print -quit)"
test -s "${BRAVE_POLICY}"
jq -e '.ExtensionInstallBlocklist == ["*"]' "${BRAVE_POLICY}" >/dev/null
jq -e '.ExtensionInstallAllowlist | length > 0' "${BRAVE_POLICY}" >/dev/null
# Osprey ships installed but removable. A "*" entry in ExtensionSettings would replace the blanket
# blocklist above rather than sit beside it, so there must not be one.
OSPREY=jmnpibhfpmpfjhhkmpadlbgjnbhpjgnd
jq -e --arg id "${OSPREY}" '.ExtensionSettings[$id].installation_mode == "normal_installed"' "${BRAVE_POLICY}" >/dev/null
jq -e --arg id "${OSPREY}" '.ExtensionSettings[$id].update_url | startswith("https://")' "${BRAVE_POLICY}" >/dev/null
jq -e '.ExtensionSettings | has("*")' "${BRAVE_POLICY}" >/dev/null && false
jq -e --arg id "${OSPREY}" '.["3rdparty"].extensions[$id].DisableUninstallSurvey == true' "${BRAVE_POLICY}" >/dev/null
# A web page may not reach a keyboard through WebHID, or the hardware behind WebUSB and WebSerial
for guard in DefaultWebHidGuardSetting DefaultWebUsbGuardSetting DefaultSerialGuardSetting; do
    jq -e ".${guard} == 2" "${BRAVE_POLICY}" >/dev/null
done

# Kernel lockdown: on everywhere except the NVIDIA images, whose driver is a machine-owner-key module
# that a machine with Secure Boot turned off would no longer be able to load
LOCKDOWN_KARGS=/usr/lib/bootc/kargs.d/11-amethystora-lockdown.toml
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    test -e "${LOCKDOWN_KARGS}" && false
else
    grep -q '"lockdown=integrity"' "${LOCKDOWN_KARGS}"
fi

# Key remapping runs as root and reads every input device, so it ships installed and switched off.
# `ujust setup-input-remapper` is how someone who remaps keys turns it on.
rpm -q input-remapper >/dev/null
[[ "$(systemctl is-enabled input-remapper.service 2>/dev/null)" == "enabled" ]] && false
# Same for USB protection, which blocks every device that was not present when it was set up: useless
# as a default, because the first boot would block the keyboard nobody had allowed yet
[[ "$(systemctl is-enabled usbguard.service 2>/dev/null)" == "enabled" ]] && false

# Audit rules: the watches that ship with the image, and the generator for the per-user ones, which
# can only be written on a machine that already has home directories
AUDIT_RULES=/etc/audit/rules.d/60-amethystora.rules
grep -q "^-w /etc/flatpak/overrides/ -p wa -k hardening$" "${AUDIT_RULES}"
grep -q "^-w /etc/containers/policy.json -p wa -k hardening$" "${AUDIT_RULES}"
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
grep -q "^Before=auditd.service$" /usr/lib/systemd/system/amethystora-audit-rules.service
grep -qE "^After=auditd.service" /usr/lib/systemd/system/amethystora-audit-rules.service && false

# Weekly virus scan and monthly Lynis audit. Neither may delete, quarantine or move anything: a false
# positive that takes away a file the user wanted is worse than most of what it would be removing.
test -x /usr/libexec/amethystora-clamav-scan
grep -vE "^[[:space:]]*#" /usr/libexec/amethystora-clamav-scan | grep -qE "(--remove|--move=)" && false
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
grep -q "amethystora-clamav-signature-age" /usr/share/amethystora/just/60-custom.just

# Backups. The helper never removes anything from the repository: an append-only repository is the
# whole of the defence against ransomware, and a client able to delete from one gives that away.
test -x /usr/libexec/amethystora-backup
test -s /usr/share/amethystora/backup-excludes
test -f /usr/lib/systemd/user/amethystora-backup.service
test -f /usr/lib/systemd/user/amethystora-backup.timer
grep -vE "^[[:space:]]*#" /usr/libexec/amethystora-backup | grep -qE "restic +(forget|prune)" && false

# TPM disk unlock (ujust setup-disk-unlock) only works if the initramfs can talk to the TPM at all.
# 19-initramfs.sh adds dracut's tpm2-tss module where dracut has it, and warns where it does not.
grep -q "tss2" <<<"${INITRAMFS_FILES}" ||
    echo "::warning::no TPM2 libraries in the initramfs, ujust setup-disk-unlock will not work"

# DisplayLink: evdi built for the image kernel, and no module signing key left behind by the build
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
modinfo "/usr/lib/modules/${KERNEL_VERSION}/extra/evdi/evdi.ko.xz" >/dev/null
test -f /usr/lib/udev/rules.d/99-displaylink.rules
systemctl is-enabled displaylink.service
grep -q "^d /var/log/displaylink " /usr/lib/tmpfiles.d/displaylink.conf
find /etc/pki/akmods/private -type f 2>/dev/null | grep -q . && false
# ujust enroll-secure-boot-key enrolls both: the one evdi is signed with and the kernel's
test -f /etc/pki/akmods/certs/amethystora-modules.der
test -f /etc/pki/akmods/certs/akmods-amethystora.der

# Make sure this garbage never makes it to an image
test -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service && false

IMPORTANT_PACKAGES=(
    audit
    brave-browser
    clamav
    clamav-freshclam
    clamd
    displaylink
    distrobox
    dotnet-sdk-10.0
    fail2ban-firewalld
    fail2ban-server
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

# these packages are supposed to be removed
# and are considered footguns
UNWANTED_PACKAGES=(
    akmod-evdi
    fedora-logos
    firefox
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
    amethystora-system-setup.service
  )

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
