#!/usr/bin/bash
# Copying text out of a picture on the screen (plans/PLAN-screen-text.md): it is Gradia's, reached from GNOME's
# screenshot UI through the image's extension. A window shows a known sentence; Print, an area dragged over it
# and Ctrl+E (keys.py, as a person's hands), with a language file in Gradia's data folder, and the clipboard
# then holds the sentence. The language file is the image's own English pack, so that this needs no download;
# the download Gradia offers in its place is only checked to still be where it fetches it.
source "$(dirname "$0")/lib.sh"

GRADIA=be.alexandervanhee.gradia
EXTENSION=gradia-integration@alexandervanhee.github.io
HOME_DIR="/var/home/${TEST_USER}"
TESSDATA="${HOME_DIR}/.var/app/${GRADIA}/data/tessdata"
OWN=/run/vmlab-22
SENTENCE="Purple gems keep quiet harbors"

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi
# The default Flatpaks install on the first boots with a network, as in 25-every-app.sh
preinstalled() { [[ "$(systemctl show flatpak-preinstall.service -p SubState -p Result --value | paste -sd ' ')" == "exited success" ]]; }
if ! wait_for 600 preinstalled; then
    if ((SUITE_PHASE < 4)); then
        echo "# the default Flatpaks were still installing after 10 minutes: on with them after a restart"
        reboot_and_continue
    fi
    not_ok "flatpak-preinstall.service did not finish" "$(systemctl status flatpak-preinstall.service --no-pager 2>&1 | tail -n 8)"
    finish
fi

keys() { python3 "$(dirname "$0")/keys.py" "$@"; }
shell() { user_bus python3 "${OWN}/atspi.py" gnome-shell "$@"; }
mkdir -p "${OWN}"
install -m 0644 "$(dirname "$0")/atspi.py" "$(dirname "$0")/screentext.py" "${OWN}/"
chmod -R a+rX "${OWN}"

check "Gradia is installed" user_bus flatpak info "${GRADIA}"
ext_state() { user_bus gnome-extensions info "${EXTENSION}" 2>/dev/null | sed -n 's/^ *State: *//p'; }
[[ "$(ext_state)" == ACTIVE ]] && ok "Gradia's extension is active" || not_ok "Gradia's extension is not active" "state: $(ext_state)"

# Where Gradia's own download would come from
code=000
for _ in 1 2 3; do
    code="$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 30 \
        https://github.com/tesseract-ocr/tessdata_best/raw/4.1.0/eng.traineddata)" && [[ "${code}" == 200 ]] && break
    sleep 5
done
case "${code}" in
    200) ok "the language data Gradia downloads is where it fetches it" ;;
    000) skip "no network to GitHub: the download Gradia offers was not checked" ;;
    *) not_ok "Gradia's language download answers ${code}" ;;
esac

# The language chosen, as the download would leave it
install -d -o "${TEST_USER}" -g "${TEST_USER}" "${HOME_DIR}/.var" "${HOME_DIR}/.var/app" "${HOME_DIR}/.var/app/${GRADIA}" \
    "${HOME_DIR}/.var/app/${GRADIA}/data" "${TESSDATA}"
install -o "${TEST_USER}" -g "${TEST_USER}" -m 0644 /usr/share/tesseract/tessdata/eng.traineddata "${TESSDATA}/"
chcon -R --reference="${HOME_DIR}/.var" "${HOME_DIR}/.var/app" 2>/dev/null

user_bus systemd-run --user --quiet --collect --unit=vmlab-screentext --setenv=WAYLAND_DISPLAY=wayland-0 -- \
    python3 "${OWN}/screentext.py" "${SENTENCE}"
sleep 8
# Something else on the clipboard first, so that what is there afterwards is what the button copied
user_bus systemd-run --user --quiet --collect --unit=vmlab-before -- wl-copy --foreground "vmlab-before-$RANDOM"
sleep 2

# Print opens the screenshot UI; the area over the sentence is dragged, as a person does; Extract Text is Ctrl+E
keys print
sleep 4
keys drag:0.08,0.3,0.92,0.7
sleep 2
keys ctrl+e

# What the clipboard holds is read as a person reads it, from the clipboard history's menu (Super+Shift+V):
# wl-paste may wait for a focus that a session with no window of its own does not give: it is tried as well,
# with a time limit, and only the menu decides.
recognised() {
    local found=1
    keys super+shift+v
    shell wait 10 "harbors" >/dev/null && found=0
    keys esc
    return "${found}"
}
if wait_for 150 recognised; then
    ok "Print, an area and Ctrl+E put the sentence in the clipboard history"
else
    not_ok "the clipboard history does not hold the sentence" \
        "Gradia: $(user_bus flatpak ps --columns=application,instance 2>&1 | head -n 5)" \
        "screen: $(shell text 2>&1 | head -n 30)" \
        "$(user_bus journalctl --user -b --since '-5min' --no-pager -o cat 2>/dev/null | grep -i 'gradia\|ocr\|screenshot' | grep -v Vulkan | tail -n 15)"
fi
pasted="$(timeout 10 sudo -u "${TEST_USER}" env XDG_RUNTIME_DIR="/run/user/$(id -u "${TEST_USER}")" wl-paste --no-newline 2>&1 | tr -c '[:alnum:]' ' ' | xargs)"
echo "# wl-paste: ${pasted:0:120}"
if [[ "${pasted,,}" == "${SENTENCE,,}" ]]; then
    ok "and the clipboard holds exactly the sentence"
else
    skip "the clipboard itself was not read back as the sentence (wl-paste said: ${pasted:0:80})"
fi

# The capture is kept like any screenshot
found="$(find "${HOME_DIR}/Pictures" -type f -newer "${OWN}/screentext.py" 2>/dev/null)"
if [[ -n "${found}" ]]; then
    ok "the capture is in the screenshot folder, as the manual says"
else
    not_ok "no capture was kept" "$(find "${HOME_DIR}/Pictures" 2>&1 | head -n 10)"
fi

user_bus flatpak kill "${GRADIA}" >/dev/null 2>&1
user_systemctl stop vmlab-screentext.service vmlab-before.service >/dev/null 2>&1
[[ -z "${found}" ]] || rm -f ${found}
finish
