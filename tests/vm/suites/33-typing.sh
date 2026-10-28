#!/usr/bin/bash
# vmlab-vm: typing
# Emoji and symbols (plans/beyond/spec-search.md, section 8, suite 33), in the test account's session, asked of GNOME
# Shell itself through Eval, which a lab-only extension of the test account opens (never in the image), and typed as a
# person types (keys.py):
#   - Super+. is the picker's, Smile keeps Ctrl+Alt+Space, the old key of the image is gone and the hook resets it;
#   - it opens under the cursor of a Text Editor document on Smileys, finds by name, and Enter types the pick;
#   - Recent, the arrow keys, a terminal, the skin tone, Escape, a broken state file, the data let go when closed;
#   - the motion (forced on: the lab draws without a GPU), the card's too, and ten disables and enables.
source "$(dirname "$0")/lib.sh"

UUID=amethystora-ui@iarsslen.github.io
HOME_DIR="/var/home/${TEST_USER}"
EMOJI=org.gnome.shell.extensions.amethystora-ui.emoji
A11Y=org.gnome.desktop.a11y.interface
HERE="$(dirname "$(readlink -f "$0")")"
RUN="$RANDOM"
STATE="${HOME_DIR}/.local/state/amethystora/emoji.json"
CUSTOM6=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/
ev() {
    user_bus gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval "$1" |
        sed -E -e "s/^\(true, '(.*)'\)\$/\1/" -e 's/^"(.*)"$/\1/'
}
gs() { in_session "gsettings $*" 2>/dev/null; }
same() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1" "expected: $3" "found: $2"; fi; }
keys() { python3 "${HERE}/keys.py" "$@" >/dev/null 2>&1; }
UI="Main.extensionManager.lookup('${UUID}').stateObj.modules"
E="${UI}.get('emoji')"
SNAP="/run/user/$(id -u "${TEST_USER}")/vmlab-33-snap.json"
snap() {
    ev "imports.gi.GLib.file_set_contents(${SNAP@Q}, ${E}.snapshot()); 'written'" >/dev/null
    cat "${SNAP}"
}
q() { snap | jq -r "$1" 2>/dev/null; }
is_open() { [[ "$(q .open)" == true ]]; }
is_closed() { [[ "$(q .open)" == false ]]; }
editor_text() { user_bus python3 "${HERE}/atspi.py" gnome-text-editor text 2>/dev/null; }
# soon SECONDS COMMAND...: wait_for, looking every tenth of a second
soon() {
    local tries=$(($1 * 10))
    shift
    until "$@" >/dev/null 2>&1; do
        ((tries-- > 0)) || return 1
        sleep 0.1
    done
}
open_picker() { keys super+period; soon 5 is_open; loaded_now() { [[ "$(q .loaded)" == true ]]; }; soon 5 loaded_now; }

if ! has_session; then
    bash "$(dirname "$0")/10-account.sh" >/dev/null
fi
if ! wait_for 300 has_session; then
    not_ok "no session for ${TEST_USER}"
    finish
fi
gs reset "${EMOJI}" skin-tone
rm -f "${STATE}" "${STATE}.bak"

install -d -o "${TEST_USER}" -g "${TEST_USER}" "${HOME_DIR}/.local/share/gnome-shell/extensions/vmlab-eval@lab"
cat >"${HOME_DIR}/.local/share/gnome-shell/extensions/vmlab-eval@lab/metadata.json" <<'EOF'
{"uuid": "vmlab-eval@lab", "name": "VM lab", "description": "The lab's Eval", "shell-version": ["49", "50", "51"]}
EOF
cat >"${HOME_DIR}/.local/share/gnome-shell/extensions/vmlab-eval@lab/extension.js" <<'EOF'
export default class { enable() { global.context.unsafe_mode = true; } disable() {} }
EOF
chown -R "${TEST_USER}:" "${HOME_DIR}/.local/share/gnome-shell"
enabled="$(user_bus gsettings get org.gnome.shell enabled-extensions)"
[[ ${enabled} == *vmlab-eval@lab* ]] || user_bus gsettings set org.gnome.shell enabled-extensions "${enabled%]*}, 'vmlab-eval@lab']"

# --- 15 first: an account that kept the image's old Super+. for Smile has it reset by the hook, once ----------------
user_bus dconf write "${CUSTOM6}binding" "'<Super>period'"
user_bus dconf write "${CUSTOM6}command" "'flatpak run it.mijorus.smile'"
# The hook runs once per account (its version in setup_versioning.json): forgotten, it runs as at the update
VERSIONS="${HOME_DIR}/.local/share/amethystora/setup_versioning.json"
if [[ -s "${VERSIONS}" ]]; then
    jq 'del(.version.user["emoji-key"])' "${VERSIONS}" >"${VERSIONS}.vmlab" && mv "${VERSIONS}.vmlab" "${VERSIONS}"
    chown "${TEST_USER}:" "${VERSIONS}"
fi
user_bus env HOME="${HOME_DIR}" bash /usr/share/amethystora/user-setup.hooks.d/23-emoji-key.sh >/dev/null 2>&1
same "15 the hook resets the old key" "$(user_bus dconf read "${CUSTOM6}binding")" ""

loginctl unlock-sessions
systemctl restart gdm
emoji_ready() { [[ "$(ev "typeof ${E}?.snapshot")" == function ]]; }
if ! wait_for 240 has_session || ! wait_for 120 emoji_ready; then
    not_ok "the emoji module did not start in the session"
    finish
fi
overview_hidden() { ev "Main.overview.hide(); 'hidden'" >/dev/null; [[ "$(ev "Main.overview.visible")" == false ]]; }
wait_for 20 overview_hidden
FORCED="$(ev "global.force_animations")"
# The lab's own language, read first, so that every path (the trap's too) puts it back: the account's language in
# AccountsService (GDM's LANG at the next login, as suite 42 sets it) and what the shell reads
USER_PATH="/org/freedesktop/Accounts/User$(id -u "${TEST_USER}")"
account_language() {
    busctl --system --json=short get-property org.freedesktop.Accounts "${USER_PATH}" org.freedesktop.Accounts.User Language |
        jq -r .data
}
set_language() {
    busctl --system call org.freedesktop.Accounts "${USER_PATH}" org.freedesktop.Accounts.User SetLanguage s "$1" >/dev/null
}
shell_locale() { ev "imports.gi.GLib.get_language_names_with_category('LC_MESSAGES')[0]"; }
LANGUAGE_LAB="$(account_language)"
LOCALE_LAB="$(shell_locale)"
LOCALE_CHANGED=""
# A new session: the old shell's mark gone (has_session is still "active" for the closing one), the module up again
new_shell() { [[ "$(ev "String(globalThis.vmlabOldShell)")" == undefined ]] && emoji_ready; }
relogin() {
    ev "globalThis.vmlabOldShell = true; 'marked'" >/dev/null
    loginctl unlock-sessions
    systemctl restart gdm
    wait_for 240 has_session && wait_for 120 new_shell || return 1
    wait_for 20 overview_hidden
}
# The lab's language back and a new session; false unless the shell reads the lab's own again
lab_locale() {
    set_language "${LANGUAGE_LAB}"
    relogin && [[ "$(shell_locale)" == "${LOCALE_LAB}" ]]
}
cleanup() {
    ev "global.force_animations = ${FORCED:-false}; 'restored'" >/dev/null 2>&1
    gs reset "${A11Y}" reduced-motion
    gs reset "${EMOJI}" skin-tone
    user_bus systemctl --user stop 'vmlab-33-*' >/dev/null 2>&1
    if [[ -n ${LOCALE_CHANGED} ]] && ! lab_locale; then
        not_ok "the lab's language is back after the suite" "expected: ${LOCALE_LAB}" "found: $(shell_locale)"
        exit 1
    fi
}
trap cleanup EXIT

# --- 1: the keys ----------------------------------------------------------------------------------------------------
same "1 the picker's key" "$(gs get "${EMOJI}" emoji-picker)" "['<Super>period']"
same "1 the image's old Smile key is gone" "$(user_bus dconf read "${CUSTOM6}binding")" ""
same "1 the skin tone" "$(gs get "${EMOJI}" skin-tone)" "'none'"
check "1 Smile keeps Ctrl+Alt+Space" grep -q "binding='<Control><Alt>space'" /etc/dconf/db/distro.d/02-amethystora-keybindings

# --- 2-4: a document, the picker under its cursor, a pick typed in --------------------------------------------------
user_bus systemd-run --user --collect --unit=vmlab-33-editor flatpak run org.gnome.TextEditor --new-document >/dev/null
editor_up() { user_bus python3 "${HERE}/atspi.py" gnome-text-editor has "Untitled" >/dev/null 2>&1; }
editor_focused() { [[ "$(ev "global.display.focus_window?.get_wm_class()")" == *TextEditor* ]]; }
if ! wait_for 60 editor_up || ! soon 10 editor_focused; then
    not_ok "2 Text Editor did not open"
    finish
fi
open_picker
check "2 Super+. opens the picker" is_open
# 15: and Smile does not start on it any more
smile() { pgrep -f it.mijorus.smile >/dev/null; }
if soon 3 smile; then not_ok "15 Super+. started Smile"; else ok "15 Super+. starts no Smile"; fi
scale="$(ev "St.ThemeContext.get_for_stage(global.stage).scale_factor")"
same "2 its width" "$(q .width)" "$((400 * scale))"
placed="$(ev "(() => { const r = Main.inputMethod._cursorRect; const p = ${E}._picker.actor; const f = global.display.focus_window?.get_frame_rect(); if (r && p.y >= r.y + r.height) return 'below the cursor'; if (r && p.y + p.height <= r.y) return 'above the cursor'; return f && Math.abs(p.y - (f.y + f.height / 3)) < 40 ? 'a third down the window' : 'elsewhere ' + p.y; })()")"
if [[ "${placed}" != elsewhere* ]]; then ok "2 placed ${placed}"; else not_ok "2 placed ${placed}"; fi
same "3 it opens on Smileys" "$(q .tab)" smileys
same "3 ...with 😀 first" "$(q '.cells[0]')" "😀"
keys text:grinning
query_is() { [[ "$(q .query)" == "$1" ]]; }
soon 3 query_is grinning
same "4 grinning" "$(q '.query + " " + .cells[0]')" "grinning 😀"
keys return
check "4 Return closes it" soon 2 is_closed
typed() { editor_text | grep -q "$1"; }
check "4 the document holds 😀 within 2 s" wait_for 2 typed "😀"
same "4 Recent keeps it" "$(jq -c .recent "${STATE}")" '["😀"]'
clip_known() { [[ "$(ev "String(globalThis.vmlabClip)")" != undefined ]]; }
ev "globalThis.vmlabClip = undefined; St.Clipboard.get_default().get_text(St.ClipboardType.CLIPBOARD, (c, t) => (globalThis.vmlabClip = t)); 'asked'" >/dev/null
soon 3 clip_known
if [[ "$(ev "String(globalThis.vmlabClip)")" != "😀" ]]; then ok "4 typed through the input method: the clipboard is untouched"; else not_ok "4 the pick went through the clipboard" "the window took no text from the input method"; fi

# --- 5-6: Recent, a search, the arrow keys --------------------------------------------------------------------------
open_picker
same "5 it opens on Recent" "$(q '.tab + " " + .cells[0]')" "recent 😀"
keys text:euro
soon 3 query_is euro
same "5 euro" "$(q '.cells[0]')" "€"
keys return
check "5 the document ends with 😀€" wait_for 2 typed "😀€"
open_picker
keys ctrl+pagedown
tab_is() { [[ "$(q .tab)" == "$1" ]]; }
soon 3 tab_is smileys
third="$(q '.cells[2]')"
keys down right right return
check "6 Down, Right, Right, Return types the third character (${third})" wait_for 2 typed "${third}"

# --- 7: a terminal --------------------------------------------------------------------------------------------------
user_bus systemd-run --user --collect --unit=vmlab-33-kitty kitty --title vmlab-33 sh -c "cat > /tmp/vmlab-33-${RUN}" >/dev/null
kitty_up() { [[ "$(ev "global.display.focus_window?.get_title()")" == vmlab-33 ]]; }
if wait_for 20 kitty_up; then
    open_picker
    keys text:euro
    soon 3 query_is euro
    keys return
    check "7 Return closes it" soon 2 is_closed
    in_file() { [[ -s "/tmp/vmlab-33-${RUN}" ]] || { keys return ctrl+d; [[ -s "/tmp/vmlab-33-${RUN}" ]]; }; }
    wait_for 10 in_file
    same "7 the terminal took €" "$(cat "/tmp/vmlab-33-${RUN}" 2>/dev/null)" "€"
else
    not_ok "7 kitty did not open"
fi
user_bus systemctl --user stop vmlab-33-kitty >/dev/null 2>&1
rm -f "/tmp/vmlab-33-${RUN}"
ev "global.display.get_tab_list(0, null).find(w => w.get_title()?.includes('Untitled'))?.activate(global.get_current_time()); 'back'" >/dev/null
soon 5 editor_focused

# --- 8: the skin tone -----------------------------------------------------------------------------------------------
in_session "ame desktop emoji tone medium" >/dev/null
same "8 ame desktop emoji tone medium" "$(gs get "${EMOJI}" skin-tone)" "'medium'"
open_picker
keys "text:waving hand"
soon 3 query_is "waving hand"
same "8 waving hand in the medium tone" "$(q '.cells[0]')" "👋🏽"
keys esc
soon 2 is_closed
in_session "ame desktop emoji tone none" >/dev/null
open_picker
keys "text:waving hand"
soon 3 query_is "waving hand"
same "8 ...and back to none" "$(q '.cells[0]')" "👋"

# --- 9: closing without typing --------------------------------------------------------------------------------------
before="$(editor_text | md5sum)"
keys esc
check "9 Escape closes it" soon 2 is_closed
open_picker
keys super+period
check "9 the same key closes it" soon 2 is_closed
open_picker
keys "click:0.95,0.5"
check "9 a click elsewhere closes it" soon 3 is_closed
same "9 nothing was typed" "$(editor_text | md5sum)" "${before}"

# --- 10: a broken state file ----------------------------------------------------------------------------------------
printf '{"version":1,"recent":' >"${STATE}"
chown "${TEST_USER}:" "${STATE}"
rm -f "${STATE}.bak"
ev "global.display.get_tab_list(0, null).find(w => w.get_title()?.includes('Untitled'))?.activate(global.get_current_time()); 'back'" >/dev/null
soon 5 editor_focused
open_picker
same "10 a broken file: it opens on Smileys" "$(q .tab)" smileys
keys return
rewritten() { jq -e '.recent | length == 1' "${STATE}" && test -s "${STATE}.bak"; }
check "10 after a pick the file is JSON again, with its copy beside it" soon 3 rewritten

# --- 13: the data is let go -----------------------------------------------------------------------------------------
same "13 closed, nothing of the data is held" "$(q .loaded)" false

# --- 14: the motion, forced on --------------------------------------------------------------------------------------
ev "global.force_animations = true; 'forced'" >/dev/null
gs set "${A11Y}" reduced-motion no-preference
motion_on() { [[ "$(ev "${UI}.get('comfort').reduceMotion")" == false ]]; }
soon 3 motion_on
scale_x="$(ev "(() => { ${E}.show(); return ${E}._picker.actor.scale_x.toFixed(3); })()")"
if [[ ${scale_x} =~ ^0[.][0-9]+$ ]]; then ok "14 the picker grows from ${scale_x}"; else not_ok "14 no scale while it opens" "${scale_x}"; fi
grown() { [[ "$(ev "${E}._picker.actor.scale_x")" == 1 ]]; }
check "14 ...to 1" soon 2 grown
ev "${E}.close(); 'closed'" >/dev/null
gs set "${A11Y}" reduced-motion reduce
motion_off() { [[ "$(ev "${UI}.get('comfort').reduceMotion")" == true ]]; }
soon 3 motion_off
same "14 reduce motion: no scale, the opacity still fades" \
    "$(ev "(() => { ${E}.show(); const a = ${E}._picker.actor; return a.scale_x + ' ' + (a.opacity < 255); })()")" "1 true"
ev "${E}.close(); 'closed'" >/dev/null
S="${UI}.get('search')"
same "14 the card under reduce motion: no scale" "$(ev "(() => { ${S}._show(); return ${S}._box.scale_x; })()")" 1
ev "${S}._close('now'); 'closed'" >/dev/null
gs set "${A11Y}" reduced-motion no-preference
soon 3 motion_on
card_scale="$(ev "(() => { ${S}._show(); return ${S}._box.scale_x.toFixed(3); })()")"
if [[ ${card_scale} =~ ^0[.][0-9]+$ ]]; then ok "14 the card grows from ${card_scale}"; else not_ok "14 the card does not grow" "${card_scale}"; fi
ev "${S}._close('now'); 'closed'" >/dev/null
ev "global.force_animations = ${FORCED:-false}; 'restored'" >/dev/null
gs reset "${A11Y}" reduced-motion

# --- 12: ten disables and enables -----------------------------------------------------------------------------------
since="$(date '+%Y-%m-%d %H:%M:%S')"
ev "globalThis.vmlabCycles = 'running'; (async () => { for (let i = 0; i < 10; i++) { await Main.extensionManager.disableExtension('${UUID}'); await Main.extensionManager.enableExtension('${UUID}'); } globalThis.vmlabCycles = 'done'; })(); 'started'" >/dev/null
cycles() { [[ "$(ev "String(globalThis.vmlabCycles)")" == "$1" ]]; }
check "12 ten cycles end" wait_for 120 cycles done
same "12 the key is bound once, after the cycles" "$(ev "(Main.wm._allowedKeybindings['emoji-picker'] ?? 0) !== 0")" true
ev "(async () => { await Main.extensionManager.disableExtension('${UUID}'); globalThis.vmlabCycles = 'disabled'; })(); 'off'" >/dev/null
soon 20 cycles disabled
same "12 ...and not while it is off" "$(ev "(Main.wm._allowedKeybindings['emoji-picker'] ?? 0) === 0")" true
ev "(async () => { await Main.extensionManager.enableExtension('${UUID}'); })(); 'on'" >/dev/null
check "12 enabled again" wait_for 20 emoji_ready
gs set "${EMOJI}" emoji-picker "[]"
unbound() { [[ "$(ev "(Main.wm._allowedKeybindings['emoji-picker'] ?? 0) === 0")" == true ]]; }
check "12 an empty key turns the picker off" soon 3 unbound
gs reset "${EMOJI}" emoji-picker
bound() { ! unbound; }
check "12 ...and its key back on again" soon 3 bound
if journalctl --since "${since}" -o cat _UID="$(id -u "${TEST_USER}")" | grep -q "JS ERROR\|Gjs-CRITICAL"; then
    not_ok "12 JS ERROR in the cycles" "$(journalctl --since "${since}" -o cat _UID="$(id -u "${TEST_USER}")" | grep -A3 "JS ERROR\|Gjs-CRITICAL" | head -12)"
else
    ok "12 no JS ERROR in ten cycles"
fi

# --- 11: an Arabic session: يورو finds €, and the tabs run right to left ------------------------------------------
LOCALE_CHANGED=1
set_language ar_EG.UTF-8
if relogin && [[ "$(shell_locale)" == ar_EG* ]]; then
    ok "11 the shell reads Arabic"
    ev "${E}.show(); 'shown'" >/dev/null
    soon 5 is_open
    loaded() { [[ "$(q .loaded)" == true ]]; }
    soon 5 loaded
    ev "${E}._picker.entry.set_text('يورو'); 'typed'" >/dev/null
    soon 3 query_is "يورو"
    same "11 يورو finds €" "$(q '.cells[0]')" "€"
    rtl="$(ev "(() => { const b = ${E}._picker._tabsBox.get_children().filter(c => c.visible); const [x0] = b[0].get_transformed_position(); const [x1] = b[1].get_transformed_position(); return x0 > x1; })()")"
    same "11 the tabs run right to left" "${rtl}" true
    ev "${E}.close(); 'closed'" >/dev/null
else
    not_ok "11 the shell reads Arabic" "expected: ar_EG.UTF-8 (LC_MESSAGES)" "found: $(shell_locale)"
fi
if lab_locale; then
    ok "the lab's language is back: ${LOCALE_LAB}"
else
    not_ok "the lab's language is back" "expected: ${LOCALE_LAB}" "found: $(shell_locale)"
fi
LOCALE_CHANGED=""

user_bus systemctl --user stop vmlab-33-editor >/dev/null 2>&1
finish
