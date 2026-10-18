#!/usr/bin/bash
# Amethystora Control (plans/PLAN-control.md, step 7): every card tried as the window tries it, and the questions
# the plan's "Verify" list left open answered on a running machine. A card's command is the one the list the
# window reads gives it (amethystora-control-list --json), run as the window runs it: a direct one as its
# argument vector in the account's session, with no terminal; one the list opens in a terminal on a terminal of
# its own, its questions answered (term.py). Then the list is read again for the state it says. Five starts:
#   1. The list: its speed, its commands, what it reads without root (the boot menu, sched_ext); the hotkey
#      against every other key of GNOME and its extensions; custom29 in the setup file; every direct card
#      (theme, wallpaper, transition and its length, layout, widgets, greeting, terminal tools, phone pairing,
#      the agent and which one, the AUR off, web apps removed, also by names with spaces and a leading dash, the
#      setup file saved); the window: a switch clicked, a terminal opened and closed, the list read again.
#   2. The terminal cards that download little: the boot menu, the CPU scheduler, swapped-out memory, the AUR
#      on, a web app added, the firmware settings declined, freeing space, the default apps, the image and the
#      stream offered (declined at the last question), the developer groups on a developer image.
#   3. Android, enabled after on, still after stop and not after off (drawing in software on an NVIDIA image);
#      drawing tablets, and the daemon their unit runs.
#   4. Games: Steam and its layers, X11 for Steam alone, other stores offered, all taken away again.
#   5. The add-ons: the chosen agent installed, JetBrains Toolbox, the command-line tools, Bold Brew's lists.
# Switching to the developer image and starting over are 90-control-switch.sh's.
source "$(dirname "$0")/lib.sh"

LIST=/usr/libexec/amethystora-control-list
APP=amethystora-control
BINARY=/usr/lib/amethystora-control/amethystora-control
# What the account runs of the suite's own: its folder is root's
OWN=/run/vmlab-control
HOME_DIR="/var/home/${TEST_USER}"
CONFIG="${HOME_DIR}/.config/amethystora"
SUDOERS=/etc/sudoers.d/zz-vmlab-control
POLKIT=/etc/polkit-1/rules.d/00-vmlab-control.rules
IMAGE_INFO=/usr/share/amethystora/image-info.json
CUSTOM=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
CUSTOM29="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${CUSTOM}/custom29/"

# After a restart, the session comes back by itself (GDM signs the account in)
if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi
TUID="$(id -u "${TEST_USER}")"
mkdir -p "${OWN}"
cp "$(dirname "$0")/atspi.py" "${OWN}/"
chmod -R a+rX "${OWN}"

# --- The list, and the cards as the window runs them ------------------------------------------------------

# A command as Control runs one: an argument vector, in the account's user manager, in English, no terminal
as_window() {
    user_bus systemd-run --user --pipe --wait --quiet --collect --setenv=LC_ALL=C.UTF-8 --setenv=LANGUAGE= \
        -- "$@" </dev/null
}
LIST_JSON=""
read_list() { LIST_JSON="$(as_window "${LIST}" --json 2>/dev/null)"; }
item() { jq -c --arg id "$1" '.items[] | select(.id == $id)' <<<"${LIST_JSON}"; }
state() { item "$1" | jq -r '.state // ""'; }
# The argument vector the list gives ID's choice VALUE, or ID's own command without one, a word a line, and
# whether it opens in a terminal
argv_of() { item "$1" | jq -r --arg v "${2:-}" 'if $v == "" then .command[] else .choices[] | select(.value == $v) | .command[] end'; }
terminal_of() { item "$1" | jq -r --arg v "${2:-}" 'if $v == "" then .terminal else .choices[] | select(.value == $v) | .terminal end'; }
# One of the commands an entry keeps in .commands (widgets, web apps, the setup file), its {id}, {example} and
# {name} filled in as the window fills them
named_argv() {
    item "$1" | jq -r --arg c "$2" --arg id "${3:-}" --arg ex "${4:-}" \
        '.commands[$c].command[] | if . == "{id}" or . == "{name}" then $id elif . == "{example}" then $ex else . end'
}
# json_holds WHAT JSON FILTER: ok when FILTER is true of JSON
json_holds() {
    if jq -e "$3" <<<"$2" >/dev/null 2>&1; then ok "$1"; else not_ok "$1" "$(head -c 3000 <<<"$2")"; fi
}
ms() {
    local start
    start="$(date +%s%N)"
    "$@" >/dev/null 2>&1
    echo $((($(date +%s%N) - start) / 1000000))
}

# run_argv WHAT CHECK... -- ARGV...: ARGV run as the window runs a direct command, then the list read again;
# ok when it ended well and every CHECK (a command) holds
run_argv() {
    local what="$1" checks=() out status failed=""
    shift
    while [[ "$1" != -- ]]; do checks+=("$1"); shift; done
    shift
    out="$(as_window "$@" 2>&1)"
    status=$?
    read_list
    for c in "${checks[@]}"; do
        eval "${c}" >/dev/null 2>&1 || failed+="does not hold: ${c}"$'\n'
    done
    if [[ ${status} == 0 && -z "${failed}" ]]; then
        ok "${what}"
    else
        not_ok "${what}" "${*}: exit status ${status}" "${failed}" "$(tail -n 15 <<<"${out}")"
    fi
}
# set_direct ID VALUE [CHECK...]: ID set to VALUE with the command the list gives it, which must not open a
# terminal; then the list says VALUE
set_direct() {
    local id="$1" value="$2" argv=()
    shift 2
    mapfile -t argv < <(argv_of "${id}" "${value}")
    if [[ ${#argv[@]} == 0 || "$(terminal_of "${id}" "${value}")" != false ]]; then
        not_ok "${id}: the list gives ${value} a command run without a terminal" "$(item "${id}" | head -c 2000)"
        return
    fi
    run_argv "${id} set to ${value}: ${argv[*]}" "[[ \"\$(state ${id})\" == '${value}' ]]" "$@" -- "${argv[@]}"
}

# The account at a terminal in its session, as Ptyxis opens one: in its user manager, on a pseudo-terminal of
# its own, each EXPECT waited for and SEND typed (term.py). OUT and STATUS say how it went.
at_terminal() {
    local steps=()
    while [[ "$1" != -- ]]; do steps+=("$1"); shift; done
    shift
    OUT="$(in_terminal "${steps[@]}" -- runuser -u "${TEST_USER}" -- env XDG_RUNTIME_DIR="/run/user/${TUID}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TUID}/bus" \
        systemd-run --user --pty --wait --quiet --collect --setenv=LC_ALL=C.UTF-8 --setenv=LANGUAGE= -- "$@" 2>&1)"
    STATUS=$?
    read_list
}
# in_card SECONDS [EXPECT SEND]... -- ID [VALUE]: ID's command for VALUE (or its own) on a terminal, as the
# window opens it there; the list must say it opens in one
in_card() {
    local steps=() argv=()
    while [[ "$1" != -- ]]; do steps+=("$1"); shift; done
    shift
    CARD="$1 ${2:-}"
    mapfile -t argv < <(argv_of "$1" "${2:-}")
    if [[ ${#argv[@]} == 0 || "$(terminal_of "$1" "${2:-}")" != true ]]; then
        OUT="the list has no command for $1 ${2:-} that opens in a terminal: $(item "$1" | head -c 1500)"
        STATUS=1
        return
    fi
    CARD="${argv[*]}"
    at_terminal "${steps[@]}" -- "${argv[@]}"
}
# card_ok WHAT [CHECK...]: ok when the card's command ended well and every CHECK (a command) holds
card_ok() {
    local what="$1" failed=""
    shift
    for c in "$@"; do
        eval "${c}" >/dev/null 2>&1 || failed+="does not hold: ${c}"$'\n'
    done
    if [[ ${STATUS} == 0 && -z "${failed}" ]]; then
        ok "${what}"
    else
        not_ok "${what}" "${CARD:-}: exit status ${STATUS}" "${failed}" "$(tail -n 25 <<<"${OUT}")"
    fi
}

# The cards that need root ask sudo or pkexec, which a person answers with a password. While this suite runs
# the account's sudo asks none, and polkit lets it do what it asks; the last phase takes both away.
allow_root() {
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${TEST_USER}" >"${SUDOERS}"
    chmod 0440 "${SUDOERS}"
    printf 'polkit.addRule(function (action, subject) {\n    if (subject.user == "%s") { return polkit.Result.YES; }\n});\n' \
        "${TEST_USER}" >"${POLKIT}"
    sleep 2
}
take_root_away() { rm -f "${SUDOERS}" "${POLKIT}"; }

read_list
if [[ -z "${LIST_JSON}" ]]; then
    not_ok "amethystora-control-list --json says nothing" "$(as_window "${LIST}" --json 2>&1 | tail -n 15)"
    finish
fi

# --- Phase 1: the list, the direct cards, the window --------------------------------------------------------
if [[ "${SUITE_PHASE}" == 1 ]]; then
    apps="$(as_window flatpak list --app --columns=application | wc -l)"
    times=()
    for _ in 1 2 3; do times+=("$(ms user_bus env LC_ALL=C.UTF-8 "${LIST}" --json)"); done
    best="$(printf '%s\n' "${times[@]}" | sort -n | head -n 1)"
    echo "# amethystora-control-list --json: ${times[*]} ms, with ${apps} Flatpak apps"
    if ((best < 1000)); then
        ok "the list is read in under a second (${best} ms) with ${apps} Flatpak apps"
    else
        not_ok "the list takes ${best} ms with ${apps} Flatpak apps, more than a second" "${times[*]} ms"
    fi
    json_holds "every id is listed once, and every command is an ame command, none under ame security" "${LIST_JSON}" '
        (.items | map(.id) | length == (unique | length))
        and ([.items[] | (.command // empty), ((.choices // [])[] | .command), ((.commands // {})[] | .command),
              ((.disks // [])[] | .actions[] | .command)] | length > 30 and all(.[0] == "ame" and .[1] != "security"))'

    # Verify: amethystora-grub-theme status without root, and the boot menu's card from it
    said="$(as_user amethystora-grub-theme status 2>&1)"
    status=$?
    echo "# amethystora-grub-theme status, as ${TEST_USER}: exit ${status}: ${said//$'\n'/ | }"
    if [[ ${status} == 0 && "${said}" == "$(amethystora-grub-theme status 2>&1)" ]]; then
        ok "amethystora-grub-theme status says without root what it says as root"
    else
        not_ok "amethystora-grub-theme status says another thing without root" "as ${TEST_USER}: ${said}" \
            "as root: $(amethystora-grub-theme status 2>&1)" "$(ls -ld /boot/grub2 /boot/grub2/user.cfg 2>&1)"
    fi
    json_holds "the boot menu's card says off, as amethystora-grub-theme does" "$(item boot-menu)" \
        '.available and .state == "off"'
    # Verify: sched_ext's state, which the scheduler's card reads as the account (root/ops in phase 2)
    if [[ -d /sys/kernel/sched_ext ]]; then
        check "an account reads the kernel's sched_ext state" as_user "cat /sys/kernel/sched_ext/state"
        json_holds "the scheduler's card says the kernel's own" "$(item scheduler)" '.available and .state == "kernel"'
    else
        skip "this kernel has no sched_ext"
    fi

    # Verify: Super+Ctrl+Shift+C is Control's alone, among every key of GNOME and of each enabled extension
    cat >"${OWN}/bindings.sh" <<'EOF'
# Every setting of GNOME's and of each enabled extension's, "schema key value" a line, and each custom keybinding
gsettings list-recursively
for uuid in $(gsettings get org.gnome.shell enabled-extensions | grep -oE "[A-Za-z0-9._-]+@[A-Za-z0-9._-]+"); do
    dir="$(gnome-extensions info "${uuid}" 2>/dev/null | sed -n 's/^ *Path: //p')/schemas"
    [[ -d "${dir}" ]] || continue
    for schema in $(grep -ohE '<schema [^>]*id="[^"]+"' "${dir}"/*.gschema.xml 2>/dev/null | sed -E 's/.*id="([^"]+)".*/\1/'); do
        gsettings --schemadir "${dir}" list-recursively "${schema}" 2>/dev/null | sed "s|^|${uuid}: |"
    done
done
base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
for path in $(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | grep -oE "${base}/[a-z0-9]+/"); do
    echo "custom ${path} $(gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${path}" binding)"
done
EOF
    cat >"${OWN}/accel.py" <<'EOF'
# The lines of standard input that hold Super+Ctrl+Shift+C, its modifiers in any order and spelling
import re
import sys

names = {"primary": "control", "ctrl": "control", "control": "control", "shift": "shift", "super": "super"}
for line in sys.stdin:
    for mods, key in re.findall(r"((?:<[A-Za-z]+>)+)([A-Za-z0-9]+)", line):
        if {names.get(m.lower(), m.lower()) for m in re.findall(r"<([A-Za-z]+)>", mods)} == {"super", "control", "shift"} \
                and key.lower() == "c":
            print(line.strip())
            break
EOF
    bindings="$(in_session "bash ${OWN}/bindings.sh" 2>/dev/null)"
    holders="$(python3 "${OWN}/accel.py" <<<"${bindings}")"
    others="$(grep -v "^custom ${CUSTOM}/custom29/ " <<<"${holders}")"
    echo "# keys read: $(wc -l <<<"${bindings}") settings of GNOME and $(grep -c '@' <<<"$(grep -oE '^[^ ]+@[^ :]+:' <<<"${bindings}" | sort -u)") extensions"
    if grep -q "^custom ${CUSTOM}/custom29/ " <<<"${holders}" && [[ -z "${others}" ]]; then
        ok "Super+Ctrl+Shift+C is custom29's alone, in GNOME and every extension it has on"
    else
        not_ok "Super+Ctrl+Shift+C is not custom29's alone" "${holders}"
    fi
    check "custom29 runs amethystora-control" sh -c \
        "[[ \"\$(runuser -u ${TEST_USER} -- gsettings get ${CUSTOM29} command)\" == \"'amethystora-control'\" ]]"

    # Verify: ame setup save keeps custom29 once the account changed it, by its id, and only then
    setup="${HOME_DIR}/vmlab-setup.json"
    in_session "gsettings set ${CUSTOM29} binding \"'<Super><Control><Shift>x'\" && ame setup save ${setup}" >/dev/null 2>&1
    if jq -e '.settings.keybindings.custom.custom29 == ["<Super><Control><Shift>x"]' "${setup}" >/dev/null 2>&1; then
        ok "ame setup save keeps custom29 by its id once its key is changed"
    else
        not_ok "ame setup save did not keep custom29's new key" "$(jq -c '.settings // .' "${setup}" 2>&1 | head -c 2000)"
    fi
    in_session "gsettings reset ${CUSTOM29} binding && ame setup save ${setup}" >/dev/null 2>&1
    if jq -e '.settings.keybindings.custom.custom29 == null' "${setup}" >/dev/null 2>&1; then
        ok "and leaves it out once it is the image's again"
    else
        not_ok "ame setup save keeps custom29 at the image's own key" "$(jq -c '.settings' "${setup}" 2>&1 | head -c 2000)"
    fi
    rm -f "${setup}"

    # --- The direct cards: each changed and put back as it was
    theme="$(state theme)"
    other="$(item theme | jq -r --arg t "${theme}" '[.choices[].value | select(. != $t)][0] // ""')"
    if [[ -n "${theme}" && -n "${other}" ]]; then
        set_direct theme "${other}" "[[ \"\$(as_user amethystora-theme current)\" == '${other}' ]]"
        set_direct theme "${theme}"
    else
        not_ok "the theme card lists no theme to change to" "$(item theme | head -c 2000)"
    fi
    picture="$(state wallpaper)"
    other="$(item wallpaper | jq -r --arg p "${picture}" '[.choices[].value | select(. != $p)][0] // ""')"
    if [[ -n "${other}" ]]; then
        set_direct wallpaper "${other}"
        [[ -z "${picture}" ]] || set_direct wallpaper "${picture}"
    else
        skip "the theme ${theme} has one wallpaper only"
    fi
    style="$(state transition)"
    set_direct transition wipe \
        "[[ \"\$(runuser -u ${TEST_USER} -- gsettings get org.gnome.shell.extensions.amethystora-transitions style)\" == \"'wipe'\" ]]"
    set_direct transition "${style:-grow}"
    length="$(state transition-length)"
    mapfile -t argv < <(item transition-length | jq -r '.command[] | if . == "{value}" then "1200" else . end')
    run_argv "the transition's length set to 1200 ms: ${argv[*]}" "[[ \"\$(state transition-length)\" == 1200 ]]" -- "${argv[@]}"
    mapfile -t argv < <(item transition-length | jq -r --arg v "${length:-1000}" '.command[] | if . == "{value}" then $v else . end')
    run_argv "and back to ${length} ms" "[[ \"\$(state transition-length)\" == '${length}' ]]" -- "${argv[@]}"

    paperwm_on() { runuser -u "${TEST_USER}" -- gsettings get org.gnome.shell enabled-extensions | grep -qF "'paperwm@paperwm.github.com'"; }
    set_direct layout classic "! paperwm_on" "[[ \$(cat ${CONFIG}/layout) == classic ]]"
    set_direct layout tiling "paperwm_on" "[[ ! -e ${CONFIG}/layout ]]"
    set_direct greeting off "[[ -e ${CONFIG}/no-greeting ]]"
    set_direct greeting on "[[ ! -e ${CONFIG}/no-greeting ]]"
    bling="$(state bling)"
    set_direct bling on "grep -q 'source /usr/share/amethystora/bling/' ${HOME_DIR}/.bashrc"
    set_direct bling off "! grep -q 'source /usr/share/amethystora/bling/' ${HOME_DIR}/.bashrc"
    [[ "${bling}" != on ]] || set_direct bling on
    phone="$(state phone)"
    set_direct phone on
    set_direct phone off
    [[ "${phone}" != on ]] || set_direct phone on
    set_direct agent off "[[ -e ${CONFIG}/no-agentic ]]" "! item agent-choice | jq -e .available"
    set_direct agent on "[[ ! -e ${CONFIG}/no-agentic ]]" "item agent-choice | jq -e .available"
    chosen="$(state agent-choice)"
    other="$(item agent-choice | jq -r --arg c "${chosen}" '[.choices[].value | select(. != $c)][0] // ""')"
    set_direct agent-choice "${other}"
    set_direct agent-choice "${chosen:-claude}"
    set_direct aur off "[[ ! -e ${CONFIG}/aur ]]"

    # Widgets: one made from an example, turned off and on, and moved to the trash, by the list's commands
    widget() { jq -c --arg id vmlab-clock '.widgets[] | select(.id == $id)' <<<"$(item widgets)"; }
    mapfile -t argv < <(named_argv widgets new vmlab-clock hello)
    run_argv "a widget made from the hello example: ${argv[*]}" "widget | jq -e .on" -- "${argv[@]}"
    mapfile -t argv < <(named_argv widgets off vmlab-clock)
    run_argv "and turned off: ${argv[*]}" "widget | jq -e '.on | not'" -- "${argv[@]}"
    mapfile -t argv < <(named_argv widgets on vmlab-clock)
    run_argv "and on again: ${argv[*]}" "widget | jq -e .on" -- "${argv[@]}"
    mapfile -t argv < <(named_argv widgets remove vmlab-clock)
    run_argv "and removed: ${argv[*]}" "[[ -z \"\$(widget)\" ]]" "[[ ! -e ${CONFIG}/widgets/vmlab-clock ]]" -- "${argv[@]}"

    # Verify: web apps removed by the names the list gives, a name with spaces and one starting with - among them
    for name in "Vmlab Notes" "Vmlab  Two  Spaces" "-vmlab dash"; do
        as_window amethystora-webapp install "${name}" https://example.org/vmlab web-browser >/dev/null 2>&1
    done
    read_list
    json_holds "the web apps card lists the three" "$(item webapps)" \
        '[.webapps[].name] | contains(["Vmlab Notes", "Vmlab  Two  Spaces", "-vmlab dash"])'
    for name in "Vmlab Notes" "Vmlab  Two  Spaces" "-vmlab dash"; do
        mapfile -t argv < <(named_argv webapps remove "${name}")
        run_argv "the web app \"${name}\" removed: ${argv[*]}" \
            "! item webapps | jq -e --arg n '${name}' 'any(.webapps[]; .name == \$n)'" -- "${argv[@]}"
    done

    mapfile -t argv < <(named_argv setup-file save)
    run_argv "the setup file saved: ${argv[*]}" "[[ \"\$(state setup-file)\" == saved ]]" "[[ -s ${CONFIG}/setup.json ]]" -- "${argv[@]}"

    # Verify: a terminal opened with xdg-terminal-exec, as amethystora-in-terminal opens one, gives the
    # launcher back before its command ends; Control reads the list again once it has the focus back
    started="$(date +%s)"
    in_session "xdg-terminal-exec sleep 30" >/dev/null 2>&1
    echo "# xdg-terminal-exec returned after $(($(date +%s) - started)) s, its command running for 30"
    pkill -u "${TEST_USER}" -f '^sleep 30$'

    # --- The window, through its accessibility tree
    atspi() { user_bus python3 "${OWN}/atspi.py" "${APP}" "$@"; }
    has() { atspi has "$1"; }
    # The first widget named TEXT, of ROLE, is in STATE (checked, active...)
    atspi_state() {
        user_bus python3 - "${OWN}" "${APP}" "$1" "$2" "$3" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import atspi
from gi.repository import Atspi
app = atspi.application(sys.argv[2])
node = atspi.find(app, sys.argv[3], sys.argv[4] or None) if app else None
sys.exit(0 if node and node.get_state_set().contains(getattr(Atspi.StateType, sys.argv[5].upper())) else 1)
EOF
    }
    # The window itself, the frame, has the focus
    window_active() {
        user_bus python3 - "${OWN}" "${APP}" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import atspi
from gi.repository import Atspi
app = atspi.application(sys.argv[2])
frames = [app.get_child_at_index(i) for i in range(app.get_child_count())] if app else []
sys.exit(0 if any(f and f.get_state_set().contains(Atspi.StateType.ACTIVE) for f in frames) else 1)
EOF
    }
    SWITCH="toggle button"
    WINDOW_UNIT="vmlab-control-${RANDOM}"
    user_bus systemd-run --user --unit="${WINDOW_UNIT}" --collect --quiet --setenv=LC_ALL=en_US.UTF-8 \
        --setenv=LANGUAGE=en -- /usr/bin/amethystora-control desktop
    if atspi wait 120 "Terminal greeting" >/dev/null 2>&1; then
        ok "Control opens on the page asked for (desktop)"
        rm -f "${CONFIG}/no-greeting"
        # A switch clicked runs its command, and the page reads the list again
        atspi click "Terminal greeting" "${SWITCH}" >/dev/null 2>&1
        greeting_shown_off() { ! atspi_state "Terminal greeting" "${SWITCH}" checked; }
        if wait_for 30 test -e "${CONFIG}/no-greeting" && wait_for 30 greeting_shown_off; then
            ok "clicking the greeting's switch turns it off, and the switch shows it"
        else
            not_ok "clicking the greeting's switch did not turn it off" "$(ls -la "${CONFIG}")" "$(atspi tree 2>&1 | grep -iA2 greeting | head -n 12)"
        fi
        # A terminal card: its terminal opens, the window says so; changed behind its back meanwhile, the
        # switch shows the change once the terminal has closed and the window has the focus back
        atspi click "System" >/dev/null 2>&1
        atspi wait 30 "Free space" >/dev/null 2>&1
        atspi click "Free space" >/dev/null 2>&1
        if wait_for 60 pgrep -u "${TEST_USER}" -f "amethystora-in-terminal ame system clean"; then
            ok "Free space… opens ame system clean in a terminal"
        else
            not_ok "Free space… opened no terminal" "$(pgrep -a -u "${TEST_USER}" | tail -n 15)"
        fi
        check "the window says it opened in a terminal" atspi wait 20 "It opened in a terminal"
        atspi click "Desktop" >/dev/null 2>&1
        rm -f "${CONFIG}/no-greeting"
        pkill -u "${TEST_USER}" -f "amethystora-in-terminal ame system clean"
        sleep 3
        pkill -u "${TEST_USER}" -f "amethystora-in-terminal ame system clean"
        if wait_for 30 window_active; then
            ok "the window has the focus back once the terminal closes"
        else
            not_ok "the window did not get the focus back after the terminal closed"
        fi
        if wait_for 30 atspi_state "Terminal greeting" "${SWITCH}" checked; then
            ok "and has read the list again: the greeting's switch shows it on"
        else
            not_ok "the window did not read the list again after the terminal" "$(atspi tree 2>&1 | grep -iA2 greeting | head -n 12)"
        fi
        # The keybindings link opens the Manual on its page
        atspi click "Keybindings" >/dev/null 2>&1
        check "the Keybindings card opens the Manual on the keybindings" wait_for 60 pgrep -u "${TEST_USER}" -f "amethystora-manual.* keybindings"
        pkill -u "${TEST_USER}" -f "^/usr/lib/amethystora-manual/amethystora-manual" || true
    else
        not_ok "Control did not show its Desktop page" "$(journalctl -b _SYSTEMD_USER_UNIT="${WINDOW_UNIT}.service" --no-pager -o cat | tail -n 15)"
    fi
    user_systemctl kill --kill-whom=main --signal=SIGTERM "${WINDOW_UNIT}" >/dev/null 2>&1
    reboot_and_continue
fi

# --- Phase 2: the terminal cards that download little -------------------------------------------------------
if [[ "${SUITE_PHASE}" == 2 ]]; then
    allow_root
    in_card 300 -- boot-menu on
    card_ok "the boot menu artwork turned on in a terminal: ${CARD}" \
        "amethystora-grub-theme status | grep -q '^on:'" "[[ \"\$(state boot-menu)\" == on ]]"
    in_card 300 -- boot-menu off
    card_ok "and off: ${CARD}" "amethystora-grub-theme status | grep -q '^off:'" "[[ \"\$(state boot-menu)\" == off ]]"

    if [[ -d /sys/kernel/sched_ext ]]; then
        in_card 120 -- scheduler lavd
        card_ok "the CPU scheduler set to lavd: ${CARD}" "[[ \"\$(state scheduler)\" == lavd ]]" \
            "systemctl is-enabled --quiet scx_loader.service"
        # Verify: what the card reads, as the account
        check "an account reads which sched-ext scheduler runs (root/ops)" as_user "grep -q '^lavd' /sys/kernel/sched_ext/root/ops"
        in_card 120 -- scheduler kernel
        card_ok "and back to the kernel's own: ${CARD}" "[[ \"\$(state scheduler)\" == kernel ]]" \
            "! systemctl is-enabled --quiet scx_loader.service" "[[ ! -e /etc/scx_loader/config.toml ]]"
    fi

    in_card 60 -- zram fast
    card_ok "swapped-out memory set to quick: ${CARD}" "[[ \"\$(state zram)\" == fast ]]" \
        "grep -q lzo-rle /etc/systemd/zram-generator.conf.d/90-amethystora-choice.conf"
    in_card 60 -- zram default
    card_ok "and back to the default: ${CARD}" "[[ \"\$(state zram)\" == default ]]" \
        "[[ ! -e /etc/systemd/zram-generator.conf.d/90-amethystora-choice.conf ]]"

    in_card 60 'Turn the AUR on\?' y -- aur on
    card_ok "the AUR turned on after its warning: ${CARD}" "[[ \"\$(state aur)\" == on ]]" "[[ -e ${CONFIG}/aur ]]" \
        "grep -q 'nobody' <<<\"\${OUT}\""
    set_direct aur off

    mapfile -t argv < <(named_argv webapps install)
    CARD="${argv[*]}"
    at_terminal 120 'Name>' $'Vmlab Typed\r' 'URL>' $'example.net/vmlab\r' 'Icon>' $'web-browser\r' -- "${argv[@]}"
    card_ok "a web app added in a terminal, its name and address typed: ${CARD}" \
        "item webapps | jq -e 'any(.webapps[]; .name == \"Vmlab Typed\" and .address == \"https://example.net/vmlab\")'"
    mapfile -t argv < <(named_argv webapps remove "Vmlab Typed")
    as_window "${argv[@]}" >/dev/null 2>&1

    boot="$(cat /proc/sys/kernel/random/boot_id)"
    in_card 60 'Reboot into BIOS\?' n -- bios
    card_ok "the firmware settings declined at the question, and nothing restarts: ${CARD}" \
        "sleep 5" "[[ \"\$(cat /proc/sys/kernel/random/boot_id)\" == '${boot}' ]]"

    in_card 600 'Prune all Podman images and volumes\?' y '?Docker images and volumes\?' y \
        '?Proceed with these changes' y -- clean
    card_ok "free disk space, every question answered yes: ${CARD}"

    in_card 900 '?Proceed with these changes' y -- flatpaks
    card_ok "the apps this image comes with, installed now: ${CARD}"

    # The image and the stream: the helper starts on the choice made, and asks before switching; declined there
    image="$(jq -r '."image-name"' "${IMAGE_INFO}")"
    stream="$(jq -r '."image-tag"' "${IMAGE_INFO}")"
    other="$(item image | jq -r --arg i "${image}" '[.choices[].value | select(. != $i)][0]')"
    in_card 120 'Select your image' $'\r' 'for testers' $'\r' 'Confirm rebase to' n -- image "${other}"
    if grep -q "Confirm rebase to ghcr.io/iarsslen/${other}:${stream}?" <<<"${OUT}" &&
        [[ "$(bootc status --json | jq -r '.status.staged')" == null ]]; then
        ok "the image card offers ${other} on the stream followed, and switches nothing when declined"
    else
        not_ok "the image card did not offer ${other}:${stream}" "$(tail -n 20 <<<"${OUT}")"
    fi
    in_card 120 'Select your image' $'\r' 'for testers' $'\r' 'Confirm rebase to' n -- stream stable
    if grep -q "Confirm rebase to ghcr.io/iarsslen/${image}:stable?" <<<"${OUT}"; then
        ok "the stream card offers ${image} on stable"
    else
        not_ok "the stream card did not offer ${image}:stable" "$(tail -n 20 <<<"${OUT}")"
    fi

    # On a developer image, the developer groups: dialout joined at the terminal's list, then left
    if grep -qE -e '-dx(-|$)' <<<"${image}"; then
        json_holds "developer mode's card says on, on ${image}" "$(item devmode)" '.state == "on"'
        dialout="$(grep -v '^#' /usr/share/amethystora/developer-groups | awk 'NF { print $1 }' |
            while read -r g; do getent group "${g}" >/dev/null && echo "${g}"; done | grep -nx dialout | cut -d: -f1)"
        downs="$(printf '\e[B%.0s' $(seq 2 "${dialout:-1}"))"
        in_card 120 'Which groups should' "${downs} "$'\r' -- dx-group
        card_ok "the developer groups card joins dialout: ${CARD}" "id -nG ${TEST_USER} | grep -qw dialout"
        as_user "ame system dx-group none" >/dev/null 2>&1
    else
        json_holds "developer mode's card says off, on ${image}, and there is no developer groups card" "${LIST_JSON}" \
            '(.items[] | select(.id == "devmode") | .state == "off") and all(.items[]; .id != "dx-group")'
    fi
    reboot_and_continue
fi

# --- Phase 3: Android, drawing tablets ---------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 3 ]]; then
    allow_root
    nvidia=false
    [[ "$(jq -r '."image-flavor" // ""' "${IMAGE_INFO}")" == nvidia* ]] && nvidia=true
    # Verify: waydroid-container.service enabled after on, still after stop, not after off
    in_card 1500 'Set up Android apps\?' y -- android on
    card_ok "Android set up in a terminal: ${CARD}" "[[ \"\$(state android)\" == on ]]" \
        "systemctl is-enabled --quiet waydroid-container.service" "[[ -e /var/lib/waydroid/waydroid.cfg ]]"
    if [[ "${nvidia}" == true ]]; then
        card_ok "on this NVIDIA image it says Android draws in software, and sets it so" \
            "grep -q 'draws in software' <<<\"\${OUT}\"" "grep -qx 'ro.hardware.egl=swiftshader' /var/lib/waydroid/waydroid.cfg" \
            "grep -qx 'ro.hardware.gralloc=default' /var/lib/waydroid/waydroid.cfg"
    else
        card_ok "and draws with the machine's own driver here" "! grep -q 'draws in software' <<<\"\${OUT}\"" \
            "! grep -q swiftshader /var/lib/waydroid/waydroid.cfg"
    fi
    in_card 120 -- android-run
    card_ok "Android started: ${CARD}" "systemctl is-active --quiet waydroid-container.service" \
        "item android-run | jq -e '.title == \"Stop Android\"'"
    in_card 120 -- android-run
    card_ok "and stopped, still set up: ${CARD}" "! systemctl is-active --quiet waydroid-container.service" \
        "systemctl is-enabled --quiet waydroid-container.service" "[[ \"\$(state android)\" == on ]]"
    in_card 300 'Remove Android, with every app' y -- android off
    card_ok "and taken away: ${CARD}" "[[ \"\$(state android)\" == off ]]" \
        "! systemctl is-enabled --quiet waydroid-container.service" "[[ ! -e /var/lib/waydroid ]]"

    # Verify: the daemon the image's unit starts, from the Flatpak
    in_card 1200 'Set up OpenTabletDriver\?' y -- opentabletdriver on
    card_ok "drawing tablets set up: ${CARD}" "[[ \"\$(state opentabletdriver)\" == on ]]" \
        "[[ -e /etc/udev/rules.d/71-opentabletdriver.rules ]]" "user_systemctl is-enabled --quiet amethystora-opentabletdriver.service"
    sleep 20
    restarts="$(user_systemctl show amethystora-opentabletdriver.service -p NRestarts --value)"
    if user_systemctl is-active --quiet amethystora-opentabletdriver.service && ((restarts == 0)) &&
        pgrep -u "${TEST_USER}" -f 'OpenTabletDriver.Daemon' >/dev/null; then
        ok "its unit runs OpenTabletDriver's daemon, and keeps it running"
    else
        not_ok "the unit does not keep OpenTabletDriver's daemon running" "restarts: ${restarts}" \
            "$(user_systemctl status amethystora-opentabletdriver.service --no-pager 2>&1 | tail -n 12)" \
            "commands in the Flatpak: $(user_bus flatpak run --command=ls net.opentabletdriver.OpenTabletDriver /app/bin 2>&1 | paste -sd ' ')"
    fi
    echo "# the OpenTabletDriver Flatpak's commands: $(user_bus flatpak run --command=ls net.opentabletdriver.OpenTabletDriver /app/bin 2>&1 | paste -sd ' ')"
    in_card 600 'Uninstall OpenTabletDriver' y -- opentabletdriver off
    card_ok "and taken away: ${CARD}" "[[ \"\$(state opentabletdriver)\" == off ]]" \
        "[[ ! -e /etc/udev/rules.d/71-opentabletdriver.rules ]]" "! flatpak info net.opentabletdriver.OpenTabletDriver" \
        "! user_systemctl is-enabled --quiet amethystora-opentabletdriver.service"
    reboot_and_continue
fi

# --- Phase 4: games ----------------------------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 4 ]]; then
    allow_root
    in_card 1500 'Set up gaming\?' y 'Also install\?' $'\x03' -- gaming on
    card_ok "games set up: ${CARD}" "[[ \"\$(state gaming)\" == on ]]" "flatpak info com.vysp3r.ProtonPlus" \
        "as_user 'flatpak override --user --show com.valvesoftware.Steam' | grep -q 'sockets=.*x11'" \
        "item gaming-launchers | jq -e '.available'"
    in_card 120 'Install which\?' $'\x03' -- gaming-launchers
    card_ok "other stores offered, none chosen: ${CARD}" "! flatpak info com.heroicgameslauncher.hgl" "! flatpak info net.lutris.Lutris"
    in_card 900 'Uninstall Steam' y -- gaming off
    card_ok "and taken away: ${CARD}" "[[ \"\$(state gaming)\" == off ]]" "! flatpak info com.valvesoftware.Steam" \
        "! as_user 'flatpak override --user --show com.valvesoftware.Steam' | grep -q x11"
    reboot_and_continue
fi

# --- Phase 5: the add-ons and the agent --------------------------------------------------------------------
if [[ "${SUITE_PHASE}" == 5 ]]; then
    allow_root
    chosen="$(state agent-choice)"
    if [[ -n "$(item agent-install)" ]]; then
        in_card 900 -- agent-install
        card_ok "the chosen agent installed with its maker's installer: ${CARD}" "[[ -z \"\$(item agent-install)\" ]]" \
            "item agent-choice | jq -e --arg c '${chosen}' 'any(.choices[]; .value == \$c and .text == \"Installed\")'"
    else
        skip "the chosen agent (${chosen}) is installed already"
    fi
    in_card 900 -- jetbrains-toolbox
    card_ok "JetBrains Toolbox installed: ${CARD}" "[[ -x ${HOME_DIR}/.local/share/jetbrains-toolbox/bin/jetbrains-toolbox ]]" \
        "item jetbrains-toolbox | jq -e '.state == \"installed\"'"
    pkill -u "${TEST_USER}" -f jetbrains-toolbox || true
    in_card 1500 -- cli
    card_ok "the command-line tools installed from Homebrew, the terminal tools on: ${CARD}" "[[ \"\$(state bling)\" == on ]]" \
        "as_user 'brew list eza'"
    in_card 600 'would you like to install it\?' y 'Some of these take a while' '' '?(?i)brewfile|search|filter|package' $'\x03' -- bbrew
    card_ok "Bold Brew installed, its lists offered: ${CARD}" "as_user 'command -v bbrew'"
    in_card 300 '(?i)brewfile|search|filter|package|cncf' $'\x03' -- cncf
    card_ok "the cloud native tools' list opens in Bold Brew: ${CARD}"
    take_root_away
fi
finish
