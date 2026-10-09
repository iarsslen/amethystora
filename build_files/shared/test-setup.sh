#!/usr/bin/bash
# `ame setup` (/usr/libexec/amethystora-setup, or the copy named first) against stand-ins for flatpak,
# Homebrew, GNOME's settings, amethystora-pkg and the theme, for 20-tests.sh: a file `save` wrote is one
# `apply` finds nothing to do for, `diff` lists everything against a file that names nothing, `apply`
# installs what is missing and takes nothing away unless asked, and a file that names a command, an
# address or a key the format does not know is refused before anything runs.

set -euo pipefail

SETUP="${1:-/usr/libexec/amethystora-setup}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin" "${T}/home"
export HOME="${T}/home" XDG_CONFIG_HOME="${T}/home/.config" XDG_DATA_HOME="${T}/home/.local/share"
export PATH="${T}/bin:${PATH}" LOG="${T}/log"
: >"${LOG}"

# A machine with two apps, three things from Homebrew, a container, an extension and a theme, whose
# dock, close key, terminal key and window gap are not the image's. What would change it is only logged.
cat >"${T}/bin/stub" <<'EOF'
#!/usr/bin/bash
CUSTOM=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
case "${0##*/}" in
    flatpak)
        case "$*" in
            "list --system --app --columns=application,origin") printf 'org.gnome.Calculator\tflathub\n' ;;
            "list --user --app --columns=application,origin") printf 'org.gimp.GIMP\tflathub\n' ;;
            "remotes --system --columns=name") echo flathub ;;
            remotes*) ;;
            *) echo "flatpak $*" >>"${LOG}" ;;
        esac
        ;;
    brew)
        if [[ "$*" == "bundle dump --file=-" ]]; then
            printf 'tap "homebrew/bundle"\ntap "someone/tools"\nbrew "ripgrep"\ncask "font-iosevka"\n'
        else
            echo "brew $*" >>"${LOG}"
        fi
        ;;
    gsettings)
        defaults="org.gnome.shell favorite-apps ['firefox.desktop']
org.gnome.shell enabled-extensions @as []
org.gnome.desktop.wm.keybindings close ['<Super>w']
org.gnome.desktop.wm.keybindings maximize ['<Super>Up']
org.gnome.shell.extensions.paperwm window-gap 8
org.gnome.shell.extensions.paperwm vertical-margin 8"
        values="org.gnome.shell favorite-apps ['org.gnome.Nautilus.desktop', 'firefox.desktop']
org.gnome.shell enabled-extensions ['dash-to-dock@micxgx.gmail.com']
org.gnome.desktop.wm.keybindings close ['<Super>q']
org.gnome.shell.extensions.paperwm window-gap 12"
        [[ "${GSETTINGS_BACKEND:-}" == memory ]] && values=""
        value() { grep "^$1 $2 " <<<"${values}" || grep "^$1 $2 " <<<"${defaults}"; }
        case "$1" in
            list-recursively)
                awk -v schema="$2" '$1 == schema { print $2 }' <<<"${defaults}" | while read -r key; do value "$2" "${key}"; done
                ;;
            get)
                if [[ "$2" == *custom-keybinding:* ]]; then echo "'<Super>t'"; else value "$2" "$3" | cut -d' ' -f3-; fi
                ;;
            range) [[ "$2" == *paperwm ]] && echo "type i" || echo "type as" ;;
            *) echo "gsettings $*" >>"${LOG}" ;;
        esac
        ;;
    dconf)
        case "$*" in
            "list ${CUSTOM}/") echo custom20/ ;;
            "read -d ${CUSTOM}/custom20/command") echo "'xdg-terminal-exec'" ;;
            "read -d ${CUSTOM}/custom20/binding") echo "'<Super>Return'" ;;
            "read ${CUSTOM}/custom20/binding") echo "'<Super>t'" ;;
        esac
        ;;
    amethystora-theme)
        case "$1" in
            current) echo nord ;;
            list) printf '  amethyst\n* nord\n' ;;
            *) echo "amethystora-theme $*" >>"${LOG}" ;;
        esac
        ;;
    amethystora-pkg)
        case "$*" in
            "containers list --json") echo '[{"name": "debian", "template": "debian", "init": false, "packages": ["htop"]}]' ;;
            "templates list --json") echo '[{"name": "debian"}, {"name": "fedora"}]' ;;
            "managers list --json") echo '[]' ;;
            *) echo "amethystora-pkg $*" >>"${LOG}" ;;
        esac
        ;;
    *) echo "${0##*/} $*" >>"${LOG}" ;;
esac
EOF
chmod +x "${T}/bin/stub"
for command in flatpak brew gsettings dconf gnome-extensions amethystora-theme amethystora-pkg ame; do
    ln -s stub "${T}/bin/${command}"
done

# save writes the setup, and nothing that is an address or a script: no remote, Brewfile or template
"${SETUP}" save >/dev/null
FILE="${XDG_CONFIG_HOME}/amethystora/setup.json"
jq -e '.version == 1 and .theme == "nord" and .flatpaks.user == [{"app": "org.gimp.GIMP", "origin": "flathub"}]
    and .brew == {"taps": ["someone/tools"], "formulae": ["ripgrep"], "casks": ["font-iosevka"]}
    and .containers == [{"name": "debian", "template": "debian", "init": false, "packages": ["htop"]}]
    and .extensions == ["dash-to-dock@micxgx.gmail.com"]
    and .settings == {"layout": "tiling", "favorites": ["org.gnome.Nautilus.desktop", "firefox.desktop"],
        "keybindings": {"org.gnome.desktop.wm.keybindings": {"close": ["<Super>q"]}, "custom": {"custom20": ["<Super>t"]}},
        "paperwm": {"window-gap": 12}}
    and (keys - ["version", "image", "flatpaks", "brew", "containers", "extensions", "theme", "settings"] == [])' \
    "${FILE}" >/dev/null
"${SETUP}" save - | cmp -s - "${FILE}"

# Applying what save just wrote does nothing, and says so
grep -q "^Nothing to do" <<<"$("${SETUP}" apply --yes)"
grep -q "^This machine is as " <<<"$("${SETUP}" diff)"
[[ ! -s "${LOG}" ]]

# Against a file that names nothing, diff lists everything here, as what apply --remove would take away
echo '{"version": 1}' >"${T}/empty.json"
"${SETUP}" diff --json "${T}/empty.json" | jq -e 'length == 11 and all(.action == "remove")' >/dev/null

# apply installs what is missing, and without --remove takes nothing away
jq '.flatpaks.system += [{"app": "org.gnome.Maps", "origin": "flathub"}] | .brew.formulae = ["fd", "someone/tools/lint"]
    | .settings.keybindings["org.gnome.desktop.wm.keybindings"].close = ["<Super>c"]' "${FILE}" >"${T}/more.json"
"${SETUP}" apply --yes "${T}/more.json" >/dev/null
grep -qx "flatpak install --system --noninteractive flathub org.gnome.Maps" "${LOG}"
grep -qx "brew install --formula fd someone/tools/lint" "${LOG}"
grep -qx "gsettings set org.gnome.desktop.wm.keybindings close \['<Super>c'\]" "${LOG}"
grep -qE "uninstall|untap|reset|rm " "${LOG}" && false
# --remove asks first, which takes a terminal: without one, nothing is taken away
: >"${LOG}"
"${SETUP}" apply --yes --remove "${T}/more.json" </dev/null >/dev/null 2>&1 && false
grep -qE "uninstall|untap|reset|rm " "${LOG}" && false

# A file somebody shared must not run anything: a key the format does not know, a custom keybinding's
# command or the list of them, an app id that would be read as an option, an address for a tap, a formula
# from a tap the file does not list (Homebrew would tap it unannounced)
: >"${LOG}"
for bad in '{"version": 1, "token": "x"}' '{"version": 2}' \
    '{"version": 1, "settings": {"keybindings": {"custom": {"custom20": {"command": "rm -rf ~"}}}}}' \
    '{"version": 1, "settings": {"keybindings": {"org.gnome.settings-daemon.plugins.media-keys": {"custom-keybindings": ["/x/"]}}}}' \
    '{"version": 1, "settings": {"org.gnome.desktop.background": {"picture-uri": "x"}}}' \
    '{"version": 1, "flatpaks": {"system": [{"app": "--from=https://example.com/x.flatpakref", "origin": "flathub"}]}}' \
    '{"version": 1, "brew": {"taps": ["https://example.com/tap.git"]}}' \
    '{"version": 1, "brew": {"formulae": ["someone/tools/thing"]}}' \
    '{"version": 1, "brew": {"taps": ["someone/other"], "casks": ["someone/tools/thing"]}}' \
    '{"version": 1, "containers": [{"name": "x", "template": "debian", "packages": ["-o APT::Update::Pre-Invoke::=x"]}]}'; do
    printf '%s\n' "${bad}" >"${T}/bad.json"
    "${SETUP}" diff "${T}/bad.json" >/dev/null 2>&1 && { echo "accepted: ${bad}"; false; }
    "${SETUP}" apply --yes "${T}/bad.json" >/dev/null 2>&1 && { echo "applied: ${bad}"; false; }
done
[[ ! -s "${LOG}" ]]
echo "ame setup: ok"
