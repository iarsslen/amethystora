#!/usr/bin/bash
# An image of your own, the image's side: what the image template's build does with setup.json and branding/
# (amethystora-setup bake, amethystora-brand), done to the running system as that build would, and the machine
# started on the result. The derived image is the running one, checked out in hard links into the repository,
# baked and branded with --root, and committed with its SELinux labels from its own policy, as 39-old-audit-rules.sh
# makes its older image, deployed unstaged. On it: amethystora-image-check passes; About's name, the login screen's
# logo and the wallpaper are the owner's; an account new to the machine starts with the file's dock, layout,
# tiling gap, keybindings and theme, and its wallpaper is the image's; the extension's own compiled schemas carry the
# file's tiling settings too; the Brewfile hook installs the file's formula once. The machine is left with its
# deployments as they were.
source "$(dirname "$0")/lib.sh"

STATE=/var/lib/vmlab-tests/41-image-setup
REPO=/sysroot/ostree/repo
ACCOUNT=vmlab-baked
CUSTOM=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
TILING=org.gnome.shell.extensions.amethystora-ui.tiling
UI=/usr/share/gnome-shell/extensions/amethystora-ui@iarsslen.github.io
WALLPAPER="'file:///usr/share/amethystora/image-setup/backgrounds/wallpaper.svg'"
install -d -m 0700 "${STATE}"
systemctl stop uupd.timer 2>/dev/null

remember() { printf '%s\n' "$2" >"${STATE}/$1"; }
recall() { cat "${STATE}/$1" 2>/dev/null; }
same() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1" "expected: $3" "found: $2"; fi; }
rw() { unshare -m sh -c 'mount -o remount,rw /sysroot && "$@"' sh "$@"; }
booted() { rpm-ostree status --json | jq -r '.deployments[] | select(.booted) | .checksum'; }
count() { rpm-ostree status --json | jq '.deployments | length'; }
deploy() { timeout 1500 ostree admin deploy --origin-file="${STATE}/origin" "$1" 2>&1; }
# What an account new to the machine reads, before it has set anything
fresh() { runuser -u "${ACCOUNT}" -- env HOME="/var/home/${ACCOUNT}" dbus-run-session -- "$@" 2>&1; }

case "${SUITE_PHASE}" in
    1)
        if [[ "$(count)" != 1 ]]; then
            skip "the machine has $(count) deployments, which this would change"
            finish
        fi
        remember original "$(booted)"
        cp "$(ostree admin --print-current-dir).origin" "${STATE}/origin"
        # The template's three places, as the editor writes them
        files="${STATE}/files"
        mkdir -p "${files}/branding"
        cat >"${files}/setup.json" <<'EOF'
{
  "version": 1,
  "flatpaks": {"system": [{"app": "org.gnome.Maps", "origin": "flathub"}]},
  "brew": {"taps": [], "formulae": ["hello"], "casks": []},
  "containers": [{"name": "left-out", "template": "debian", "init": false, "packages": []}],
  "theme": "nord",
  "settings": {
    "layout": "classic",
    "favorites": ["org.gnome.Nautilus.desktop", "org.mozilla.firefox.desktop"],
    "keybindings": {"org.gnome.desktop.wm.keybindings": {"close": ["<Super>q"]}, "custom": {"custom20": ["<Super>t"]}},
    "tiling": {"window-gap": 20}
  }
}
EOF
        echo "Vmlab OS" >"${files}/branding/name"
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="40"><rect width="64" height="40" fill="#0b6e4f"/></svg>\n' \
            >"${files}/branding/wallpaper.svg"
        base64 -d >"${files}/branding/logo.png" <<<"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

        dir="${REPO}/tmp/vmlab-image-setup"
        rw rm -rf "${dir}"
        # In the checkout /etc is usr/etc, as in a commit: the link lets both helpers find it where a build has it
        if out="$({ rw ostree checkout --repo="${REPO}" -H "$(recall original)" "${dir}" &&
            rw ln -s usr/etc "${dir}/etc" &&
            rw /usr/libexec/amethystora-setup bake "${files}/setup.json" --root "${dir}" &&
            rw /usr/libexec/amethystora-brand "${files}/branding" --root "${dir}" &&
            rw rm "${dir}/etc" &&
            rw ostree commit --repo="${REPO}" --parent="$(recall original)" -b vmlab/image-setup -I --consume --bootable \
                --selinux-policy="${dir}" --add-metadata-string=version=vmlab-image-setup "${dir}" >/dev/null &&
            deploy vmlab/image-setup; } 2>&1)"; then
            grep -q "Left out: the containers" <<<"${out}" && ok "bake leaves the containers out, and says so" ||
                not_ok "bake did not say it left the containers out" "${out}"
            ok "the running system baked and branded as the template's build would, and deployed"
            reboot_and_continue
        else
            not_ok "could not make the image" "$(tail -n 15 <<<"${out}")"
            rw rm -rf "${dir}"
        fi
        ;;
    2)
        if [[ "$(booted)" == "$(recall original)" ]]; then
            not_ok "the machine did not start the baked image"
            finish
        fi
        out="$(/usr/libexec/amethystora-image-check 2>&1)" && ok "amethystora-image-check passes on it, the owner's logo included" ||
            not_ok "amethystora-image-check fails on it" "${out}"
        # shellcheck source=/dev/null
        same "About's name is the owner's, built on Amethystora" "$(. /usr/lib/os-release && echo "${PRETTY_NAME%% (*}|${ID}|${VARIANT}")" \
            "Vmlab OS, built on Amethystora|amethystora|Vmlab OS"
        same "the login screen shows the owner's logo" "$(GSETTINGS_BACKEND=memory gsettings get org.gnome.login-screen logo)" \
            "'/usr/share/amethystora/image-setup/branding/logo.png'"
        check "About's picture is the owner's logo" cmp -s /usr/share/pixmaps/fedora-logo-icon.png /usr/share/amethystora/image-setup/branding/logo.png
        check "the file's app is preinstalled" grep -qxF "[Flatpak Preinstall org.gnome.Maps]" /usr/share/flatpak/preinstall.d/image-setup.preinstall

        # An account new to the machine
        userdel -r "${ACCOUNT}" >/dev/null 2>&1
        useradd -m "${ACCOUNT}"
        same "its dock is the file's" "$(fresh gsettings get org.gnome.shell favorite-apps)" "['org.gnome.Nautilus.desktop', 'org.mozilla.firefox.desktop']"
        same "its close key is the file's" "$(fresh gsettings get org.gnome.desktop.wm.keybindings close)" "['<Super>q']"
        same "its terminal key, one of the image's custom keybindings, is the file's" \
            "$(fresh gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${CUSTOM}/custom20/" binding)" "'<Super>t'"
        same "...whose command stays the image's" \
            "$(fresh gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${CUSTOM}/custom20/" command)" "'xdg-terminal-exec'"
        same "its windows are classic" "$(fresh gsettings get "${TILING}" enabled)" false
        same "the tiling's gap is the file's" "$(fresh gsettings get "${TILING}" window-gap)" 20
        # GNOME Shell reads the extension's own compiled schemas before the system's
        same "...in the schemas GNOME Shell gives the extension too" \
            "$(GSETTINGS_SCHEMA_DIR="${UI}/schemas" GSETTINGS_BACKEND=memory gsettings get "${TILING}" window-gap)" 20
        extensions="$(fresh gsettings get org.gnome.shell enabled-extensions)"
        grep -qF "'amethystora-ui@iarsslen.github.io'" <<<"${extensions}" && ok "the image's own extensions stay on" ||
            not_ok "the image's extensions are not on" "${extensions}"
        # Its first login applies the theme: the file's, and every theme opens on the image's wallpaper
        out="$(fresh /usr/share/amethystora/user-setup.hooks.d/11-theme.sh)"
        same "its theme is the file's" "$(cat "/var/home/${ACCOUNT}/.config/amethystora/current/theme.name" 2>/dev/null)" nord

        same "its wallpaper is the image's" "$(fresh gsettings get org.gnome.desktop.background picture-uri)" "${WALLPAPER}"
        same "...and its lock screen's" "$(fresh gsettings get org.gnome.desktop.screensaver picture-uri)" "${WALLPAPER}"
        [[ "${FAILED}" == 0 ]] || echo "# the theme hook said: $(tail -n 5 <<<"${out}")"

        # The Brewfile, installed once for an account that logs in
        stamp="$(realpath "$(getent passwd "${TEST_USER}" | cut -d: -f6)")/.local/state/amethystora/image-brewfile"
        rm -f "${stamp}"
        if ! has_session && ! wait_for 300 has_session; then
            skip "the Brewfile: no session for ${TEST_USER}"
        else
            in_session /usr/share/amethystora/user-setup.hooks.d/18-image-brewfile.sh >/dev/null 2>&1
            stamped() { [[ -s "${stamp}" ]]; }
            if wait_for 900 stamped; then
                same "the Brewfile is installed and stamped with its sum" "$(cat "${stamp}")" \
                    "$(sha256sum /usr/share/amethystora/image-setup/Brewfile | cut -d' ' -f1)"
                check "hello is installed" as_user "/home/linuxbrew/.linuxbrew/bin/brew list --versions hello"
            else
                not_ok "the Brewfile was not installed" "$(user_bus journalctl --user -u amethystora-image-brewfile -o cat --no-pager | tail -n 10)"
            fi
        fi

        userdel -r "${ACCOUNT}" >/dev/null 2>&1
        out="$(deploy "$(recall original)")" || not_ok "could not deploy the machine's own image" "$(tail -n 15 <<<"${out}")"
        reboot_and_continue
        ;;
    *)
        [[ "$(booted)" == "$(recall original)" ]] && ok "the machine's own image runs again" || not_ok "the machine runs $(booted)"
        same "...named as Amethystora names it" "$(. /usr/lib/os-release && echo "${PRETTY_NAME%% (*}")" Amethystora
        ostree admin undeploy 1 >/dev/null 2>&1
        rw ostree refs --repo="${REPO}" --delete vmlab/image-setup >/dev/null 2>&1
        rw ostree prune --repo="${REPO}" --refs-only >/dev/null 2>&1
        [[ "$(count)" == 1 && -z "$(ostree refs --repo="${REPO}" vmlab/image-setup 2>/dev/null)" ]] &&
            ok "the machine is left with its one deployment" || not_ok "the machine has $(count) deployments" "$(ostree admin status 2>&1)"
        rm -rf "${STATE}"
        ;;
esac
finish
