#!/usr/bin/bash
# `ame setup` (/usr/libexec/amethystora-setup, or the copy named first) against stand-ins for flatpak,
# Homebrew, GNOME's settings, amethystora-pkg and the theme, for 20-tests.sh: a file `save` wrote is one
# `apply` finds nothing to do for, `diff` lists everything against a file that names nothing, `apply`
# installs what is missing and takes nothing away unless asked, the tiling's settings are kept as the schema
# types them, and a file that names a command, an address, a key the format does not know or a setting out
# of its range is refused before anything runs. `bake` writes the same file as an image's defaults, which GNOME
# reads back as the file has them, and refuses what the image cannot have.

set -euo pipefail

SETUP="${1:-/usr/libexec/amethystora-setup}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin" "${T}/home"
export HOME="${T}/home" XDG_CONFIG_HOME="${T}/home/.config" XDG_DATA_HOME="${T}/home/.local/share"
export XDG_STATE_HOME="${T}/home/.local/state"
export PATH="${T}/bin:${PATH}" LOG="${T}/log"
: >"${LOG}"

# The tiling has taken Super+N out of GNOME's focus-active-notification, which is the account's own and was
# not changed by it, and says so in its state file
mkdir -p "${XDG_STATE_HOME}/amethystora"
echo '{"taken": [{"schema": "org.gnome.shell.keybindings", "key": "focus-active-notification",
    "removed": [{"accelerator": "<Super>n", "index": 0}], "wrote": []}]}' >"${XDG_STATE_HOME}/amethystora/tiling.json"

# The tiling's settings a file may hold are amethystora-setup's fixed list, with the type and range of each: they
# are the schema's own (the tiling's on/off, window rules and pictures aside), and the manifest saves the same keys
TILING=org.gnome.shell.extensions.amethystora-ui.tiling
TABLE="$(sed -n "/^TILING_KEYS='{\$/,/^}'\$/{s/^TILING_KEYS='//; s/^}'\$/}/; p}" "${SETUP}")"
listed="$(jq -r 'keys[]' <<<"${TABLE}" | sort)"
schema="$(GSETTINGS_BACKEND=memory /usr/bin/gsettings list-keys "${TILING}" |
    grep -vxE 'enabled|winprops|workspace-backgrounds|default-background' | sort)"
[[ -n "${listed}" && "${listed}" == "${schema}" ]] ||
    { echo "the tiling's keys in TILING_KEYS and in its schema differ:"; diff <(echo "${listed}") <(echo "${schema}"); false; }
saved="$(sed -n '/^TILING_KEYS=(/,/)$/p' "$(dirname "${SETUP}")/amethystora-setup-manifest" |
    sed 's/^TILING_KEYS=(//; s/)$//' | tr -s ' ' '\n' | sed '/^$/d' | sort)"
[[ "${saved}" == "${listed}" ]] ||
    { echo "the manifest saves other tiling keys than amethystora-setup reads:"; diff <(echo "${saved}") <(echo "${listed}"); false; }
# A range as numbers, since GSettings prints 0.05 as 0.050000000000000003
while read -r key; do
    read -r _ type min max <<<"$(GSETTINGS_BACKEND=memory /usr/bin/gsettings range "${TILING}" "${key}")"
    jq -e --arg k "${key}" --arg t "${type}" --arg min "${min:-}" --arg max "${max:-}" '.[$k] as [$type, $a, $b]
        | $type == $t and if $min == "" then ($a | type) != "number" else [($a, $b) + 0] == [($min, $max) | tonumber + 0] end' \
        <<<"${TABLE}" >/dev/null || { echo "TILING_KEYS has ${key} as $(jq -c --arg k "${key}" '.[$k]' <<<"${TABLE}"), the schema as ${type} ${min:-} ${max:-}"; false; }
done <<<"${listed}"

# A machine with two apps, three things from Homebrew, a container, an extension and a theme, whose
# dock, close key, terminal key, tiling key, two tiling settings and window rules are not the image's. What
# would change it is only logged.
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
org.gnome.shell.keybindings focus-active-notification ['<Super>n']
org.gnome.shell.extensions.amethystora-ui.tiling.keybindings cycle-width ['<Super>r']
org.gnome.shell.extensions.amethystora-ui.tiling enabled true
org.gnome.shell.extensions.amethystora-ui.tiling window-gap 8
org.gnome.shell.extensions.amethystora-ui.tiling animation-time 0.25
org.gnome.shell.extensions.amethystora-ui.tiling cycle-width-steps [0.38195000000000001, 0.5, 0.61804000000000003]
org.gnome.shell.extensions.amethystora-ui.tiling winprops @as []"
        values="org.gnome.shell favorite-apps ['org.gnome.Nautilus.desktop', 'firefox.desktop']
org.gnome.shell enabled-extensions ['clipboard-indicator@tudmotu.com']
org.gnome.desktop.wm.keybindings close ['<Super>q']
org.gnome.shell.keybindings focus-active-notification @as []
org.gnome.shell.extensions.amethystora-ui.tiling.keybindings cycle-width ['<Super>e']
org.gnome.shell.extensions.amethystora-ui.tiling window-gap 12
org.gnome.shell.extensions.amethystora-ui.tiling cycle-width-steps [0.29999999999999999, 0.5]
org.gnome.shell.extensions.amethystora-ui.tiling winprops ['{\"wm_class\": \"Firefox\", \"scratch_layer\": true}']"
        [[ "${GSETTINGS_BACKEND:-}" == memory ]] && values=""
        value() { grep "^$1 $2 " <<<"${values}" || grep "^$1 $2 " <<<"${defaults}"; }
        case "$1" in
            list-recursively)
                awk -v schema="$2" '$1 == schema { print $2 }' <<<"${defaults}" | while read -r key; do value "$2" "${key}"; done
                ;;
            get)
                if [[ "$2" == *custom-keybinding:* ]]; then echo "'<Super>t'"; else value "$2" "$3" | cut -d' ' -f3-; fi
                ;;
            range) echo "type as" ;;
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
    and .extensions == ["clipboard-indicator@tudmotu.com"]
    and .settings == {"layout": "tiling", "favorites": ["org.gnome.Nautilus.desktop", "firefox.desktop"],
        "keybindings": {"org.gnome.desktop.wm.keybindings": {"close": ["<Super>q"]}, "custom": {"custom20": ["<Super>t"]},
            "org.gnome.shell.extensions.amethystora-ui.tiling.keybindings": {"cycle-width": ["<Super>e"]}},
        "tiling": {"window-gap": 12, "cycle-width-steps": [0.3, 0.5]}}
    and (keys - ["version", "image", "flatpaks", "brew", "containers", "extensions", "theme", "settings"] == [])' \
    "${FILE}" >/dev/null
# ...the tiling's settings as JSON writes them, and not its window rules, which the file never holds
[[ "$(jq -c .settings.tiling "${FILE}")" == '{"cycle-width-steps":[0.3,0.5],"window-gap":12}' ]]
"${SETUP}" save - | cmp -s - "${FILE}"

# Applying what save just wrote does nothing, and says so
grep -q "^Nothing to do" <<<"$("${SETUP}" apply --yes)"
grep -q "^This machine is as " <<<"$("${SETUP}" diff)"
[[ ! -s "${LOG}" ]]

# A file from before the tiling replaced PaperWM still holds its gaps, which are ignored beside the tiling's own
jq '.settings.paperwm = {"window-gap": 20}' "${FILE}" >"${T}/old.json"
grep -q "^Nothing to do" <<<"$("${SETUP}" apply --yes "${T}/old.json")"
[[ ! -s "${LOG}" ]]
# ...and read as the tiling's where the file has none, less a gap the tiling cannot take (PaperWM took up to 1000)
jq 'del(.settings.tiling) | .settings.paperwm = {"window-gap": 20, "horizontal-margin": 1000}' "${FILE}" >"${T}/old-gaps.json"
"${SETUP}" apply --yes "${T}/old-gaps.json" >/dev/null
grep -qx "gsettings set ${TILING} window-gap 20" "${LOG}"
grep -q "horizontal-margin" "${LOG}" && false
: >"${LOG}"
# ...and its keybindings, which this machine has no such keys for: the file is not refused for them, and what it
# holds besides still applies
jq '.settings.keybindings["org.gnome.shell.extensions.paperwm.keybindings"] = {"switch-left": ["<Super>h"]}
    | .flatpaks.user += [{"app": "org.gnome.Maps", "origin": "flathub"}]' "${FILE}" >"${T}/old-keys.json"
"${SETUP}" diff --json "${T}/old-keys.json" | jq -e 'any(.area == "keybinding" and .ok == false)
    and any(.area == "flatpak" and .action == "add")' >/dev/null

# Against a file that names nothing, diff lists everything here, as what apply --remove would take away
echo '{"version": 1}' >"${T}/empty.json"
"${SETUP}" diff --json "${T}/empty.json" | jq -e 'length == 13 and all(.action == "remove")
    and ([.[] | select(.area == "tiling") | .key] | sort == ["cycle-width-steps", "window-gap"])' >/dev/null

# apply installs what is missing, and without --remove takes nothing away. A tiling setting this machine does
# not have is listed and left out.
jq '.flatpaks.system += [{"app": "org.gnome.Maps", "origin": "flathub"}] | .brew.formulae = ["fd", "someone/tools/lint"]
    | .settings.keybindings["org.gnome.desktop.wm.keybindings"].close = ["<Super>c"]
    | .settings.tiling += {"window-gap": 20, "animation-time": 0.5, "workspace-colors": ["", "#314e6c"]}' "${FILE}" >"${T}/more.json"
out="$("${SETUP}" diff "${T}/more.json")"
grep -qxF "  ~ the tiling's window-gap: 20, in place of 12" <<<"${out}"
grep -qxF "  ~ the tiling's animation-time: 0.5, in place of 0.25" <<<"${out}"
grep -qxF "  ! the tiling's workspace-colors: [\"\",\"#314e6c\"]: this machine's tiling has no such setting" <<<"${out}"
"${SETUP}" apply --yes "${T}/more.json" >/dev/null
grep -qx "flatpak install --system --noninteractive flathub org.gnome.Maps" "${LOG}"
grep -qx "brew install --formula fd someone/tools/lint" "${LOG}"
grep -qx "gsettings set org.gnome.desktop.wm.keybindings close \['<Super>c'\]" "${LOG}"
grep -qx "gsettings set ${TILING} window-gap 20" "${LOG}"
grep -qx "gsettings set ${TILING} animation-time 0.5" "${LOG}"
grep -qE "workspace-colors|cycle-width-steps" "${LOG}" && false
grep -qE "uninstall|untap|reset|rm " "${LOG}" && false
# --remove asks first, which takes a terminal: without one, nothing is taken away
: >"${LOG}"
"${SETUP}" apply --yes --remove "${T}/more.json" </dev/null >/dev/null 2>&1 && false
grep -qE "uninstall|untap|reset|rm " "${LOG}" && false

# A file somebody shared must not run anything: a key the format does not know, a custom keybinding's
# command or the list of them, an app id that would be read as an option, an address for a tap, a formula
# from a tap the file does not list (Homebrew would tap it unannounced); and of the tiling's, a key it does not
# keep (its on/off, which is the layout; its window rules; one it does not have), a value of the wrong type, a
# fraction for a whole number, a number outside the schema's range, a step of 0, a colour that is not #rrggbb
: >"${LOG}"
for bad in '{"version": 1, "token": "x"}' '{"version": 2}' \
    '{"version": 1, "settings": {"keybindings": {"custom": {"custom20": {"command": "rm -rf ~"}}}}}' \
    '{"version": 1, "settings": {"keybindings": {"org.gnome.settings-daemon.plugins.media-keys": {"custom-keybindings": ["/x/"]}}}}' \
    '{"version": 1, "settings": {"org.gnome.desktop.background": {"picture-uri": "x"}}}' \
    '{"version": 1, "flatpaks": {"system": [{"app": "--from=https://example.com/x.flatpakref", "origin": "flathub"}]}}' \
    '{"version": 1, "brew": {"taps": ["https://example.com/tap.git"]}}' \
    '{"version": 1, "brew": {"formulae": ["someone/tools/thing"]}}' \
    '{"version": 1, "brew": {"taps": ["someone/other"], "casks": ["someone/tools/thing"]}}' \
    '{"version": 1, "containers": [{"name": "x", "template": "debian", "packages": ["-o APT::Update::Pre-Invoke::=x"]}]}' \
    '{"version": 1, "settings": {"tiling": {"enabled": false}}}' \
    '{"version": 1, "settings": {"tiling": {"winprops": ["{\"wm_class\": \"x\"}"]}}}' \
    '{"version": 1, "settings": {"tiling": {"workspace-backgrounds": ["/tmp/x.png"]}}}' \
    '{"version": 1, "settings": {"tiling": {"no-such-setting": 1}}}' \
    '{"version": 1, "settings": {"tiling": [{"window-gap": 12}]}}' \
    '{"version": 1, "settings": {"tiling": {"window-gap": "12"}}}' \
    '{"version": 1, "settings": {"tiling": {"maximize-within-tiling": 1}}}' \
    '{"version": 1, "settings": {"tiling": {"window-gap": 12.5}}}' \
    '{"version": 1, "settings": {"tiling": {"window-gap": 201}}}' \
    '{"version": 1, "settings": {"tiling": {"maximize-width-percent": 0.4}}}' \
    '{"version": 1, "settings": {"tiling": {"cycle-width-steps": [0.5, 0]}}}' \
    '{"version": 1, "settings": {"tiling": {"swipe-friction": ["0.3"]}}}' \
    '{"version": 1, "settings": {"tiling": {"workspace-colors": ["red"]}}}'; do
    printf '%s\n' "${bad}" >"${T}/bad.json"
    "${SETUP}" diff "${T}/bad.json" >/dev/null 2>&1 && { echo "accepted: ${bad}"; false; }
    "${SETUP}" apply --yes "${T}/bad.json" >/dev/null 2>&1 && { echo "applied: ${bad}"; false; }
done
[[ ! -s "${LOG}" ]]

# bake: the same file as an image's defaults, into a stand-in for the image made of its own schemas, extensions'
# schemas and dconf files, with the real tools (no stand-ins on the PATH). What it writes is read back as GNOME
# reads it: the system's schemas, the tiling's own compiled copy, which GNOME Shell reads first, and dconf's database.
ROOT="${T}/root"
UI=usr/share/gnome-shell/extensions/amethystora-ui@iarsslen.github.io
bake_root() {
    rm -rf "${ROOT}"
    mkdir -p "${ROOT}/usr/share/glib-2.0" "${ROOT}/${UI}" "${ROOT}/etc/dconf/db" "${ROOT}/usr/share/amethystora/themes/nord" \
        "${ROOT}/usr/share/gnome-shell/extensions/amethystora-clipboard@iarsslen.github.io"
    cp -r /usr/share/glib-2.0/schemas "${ROOT}/usr/share/glib-2.0/"
    cp -r "/${UI}/schemas" "${ROOT}/${UI}/"
    cp -r /etc/dconf/db/distro.d "${ROOT}/etc/dconf/db/"
}
# ...and without HOME, which a build need not set
bake() { env -u HOME PATH=/usr/bin:/usr/sbin "${SETUP}" bake "$@" --root "${ROOT}"; }
image() { GSETTINGS_SCHEMA_DIR="${ROOT}/usr/share/glib-2.0/schemas" GSETTINGS_BACKEND=memory /usr/bin/gsettings get "$@"; }
bake_root
jq '.image = {"name": "amethystora", "stream": "stable"}
    | .flatpaks.system += [{"app": "org.gnome.Maps", "origin": "flathub"}] | .extensions = ["amethystora-clipboard@iarsslen.github.io"]
    | .settings.layout = "classic" | .brew.taps = ["someone/tools"] | .brew.formulae = ["fd", "someone/tools/lint"]' \
    "${FILE}" >"${T}/image.json"
out="$(bake "${T}/image.json")"
grep -qF "Left out: the containers" <<<"${out}"
grep -qF "Left out: image" <<<"${out}"
PRE="${ROOT}/usr/share/flatpak/preinstall.d/image-setup.preinstall"
[[ "$(grep -c '^\[Flatpak Preinstall ' "${PRE}")" == 3 && "$(grep -c '^Branch=stable$' "${PRE}")" == 3 ]]
grep -qxF "[Flatpak Preinstall org.gimp.GIMP]" "${PRE}"
[[ "$(image org.gnome.shell favorite-apps)" == "['org.gnome.Nautilus.desktop', 'firefox.desktop']" ]]
# ...the image's extensions kept, the file's added
extensions="$(image org.gnome.shell enabled-extensions)"
grep -qF "'amethystora-ui@iarsslen.github.io'" <<<"${extensions}"
grep -qF "'amethystora-clipboard@iarsslen.github.io'" <<<"${extensions}"
[[ "$(image org.gnome.desktop.wm.keybindings close)" == "['<Super>q']" ]]
[[ "$(image "${TILING}.keybindings" cycle-width)" == "['<Super>e']" ]]
[[ "$(image "${TILING}" enabled)" == false && "$(image "${TILING}" window-gap)" == 12 ]]
[[ "$(GSETTINGS_SCHEMA_DIR="${ROOT}/${UI}/schemas" GSETTINGS_BACKEND=memory /usr/bin/gsettings get "${TILING}" window-gap)" == 12 ]]
[[ "$(GSETTINGS_SCHEMA_DIR="${ROOT}/${UI}/schemas" GSETTINGS_BACKEND=memory /usr/bin/gsettings get "${TILING}" enabled)" == false ]]
printf 'file-db:%s\n' "${ROOT}/etc/dconf/db/distro" >"${T}/dconf-profile"
[[ "$(DCONF_PROFILE="${T}/dconf-profile" /usr/bin/dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom20/binding)" == "'<Super>t'" ]]
# ...the image's command for it left as it was
[[ -n "$(DCONF_PROFILE="${T}/dconf-profile" /usr/bin/dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom20/command)" ]]
[[ "$(cat "${ROOT}/usr/share/amethystora/image-setup/theme")" == nord ]]
diff <(printf '%s\n' 'tap "someone/tools"' 'brew "fd"' 'brew "someone/tools/lint"' 'cask "font-iosevka"') \
    "${ROOT}/usr/share/amethystora/image-setup/Brewfile"
cmp -s "${T}/image.json" "${ROOT}/usr/share/amethystora/image-setup/setup.json"
# An app from a remote the image declares (amethystora-image-policy --only flatpak-remotes, before bake) is baked in
bake_root
mkdir -p "${ROOT}/etc/flatpak/remotes.d"
printf '[Flatpak Repo]\nUrl=https://flatpak.acme.example/repo/\n' >"${ROOT}/etc/flatpak/remotes.d/acme.flatpakrepo"
echo '{"version": 1, "flatpaks": {"system": [{"app": "com.acme.Tool", "origin": "acme"}]}}' >"${T}/acme.json"
bake "${T}/acme.json" >/dev/null
grep -qxF "[Flatpak Preinstall com.acme.Tool]" "${ROOT}/usr/share/flatpak/preinstall.d/image-setup.preinstall"
bake_root

# The theme hook falls back on the baked theme, and the Brewfile hook installs once per version of the file
grep -qF /usr/share/amethystora/image-setup/theme /usr/share/amethystora/user-setup.hooks.d/11-theme.sh
grep -qF /usr/share/amethystora/image-setup/Brewfile /usr/share/amethystora/user-setup.hooks.d/18-image-brewfile.sh

# ...and refuses, writing nothing, what the image cannot have: an app from another remote, an extension or a theme
# it does not ship, a custom keybinding or a keybinding it does not have, PaperWM's, and all that the format refuses
for bad in '{"version": 1, "flatpaks": {"user": [{"app": "org.gimp.GIMP", "origin": "gnome-nightly"}]}}' \
    '{"version": 1, "extensions": ["someone@example.com"]}' \
    '{"version": 1, "theme": "no-such-theme"}' \
    '{"version": 1, "settings": {"keybindings": {"custom": {"custom99": ["<Super>t"]}}}}' \
    '{"version": 1, "settings": {"keybindings": {"org.gnome.desktop.wm.keybindings": {"no-such-key": ["<Super>t"]}}}}' \
    '{"version": 1, "settings": {"keybindings": {"org.gnome.shell.extensions.paperwm.keybindings": {"switch-left": ["<Super>h"]}}}}' \
    '{"version": 1, "settings": {"tiling": {"winprops": ["{\"wm_class\": \"x\"}"]}}}' \
    '{"version": 1, "brew": {"taps": ["https://example.com/tap.git"]}}'; do
    bake_root
    printf '%s\n' "${bad}" >"${T}/bad.json"
    bake "${T}/bad.json" >/dev/null 2>&1 && { echo "baked: ${bad}"; false; }
    [[ ! -e "${ROOT}/usr/share/amethystora/image-setup" && ! -e "${ROOT}/usr/share/glib-2.0/schemas/zz2-image-setup.gschema.override" ]]
done
echo "ame setup: ok"
