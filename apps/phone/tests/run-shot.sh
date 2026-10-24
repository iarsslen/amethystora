#!/usr/bin/bash
# run-shot.sh SCENARIO THEME NAME [APP ARGUMENTS...]: inside the Rust container (tests/shoot.sh starts it). Sets up a
# desktop session in a virtual display (session.sh), the mock of amethystora-connect (mock-service.py) in the scenario,
# then the app with the arguments, runs the steps in /tests/steps/NAME.sh (clicks and typing through the accessibility
# tree), and saves /scratch/shots/NAME-THEME.png. THEME is a folder of /repo/usr/share/amethystora/themes.
#
#   SIZE=1120x780   the window's size       LANG=ar_EG.UTF-8   the language       NOMOCK=1   no program on the bus
set -u
scenario=$1 theme=$2 name=$3
shift 3
export MOCK_LOG=/scratch/shots/$name-$theme.calls.log
mkdir -p /scratch/shots
# shellcheck source=session.sh
source /tests/session.sh
session_up "$theme"
[[ -z ${NOMOCK:-} ]] && mock_up "$scenario"
if ! app_up "$@"; then
    echo "no window"
    cat /tmp/app.log
    exit 1
fi
sleep "${WAIT:-2}"
# shellcheck disable=SC1090
[[ -f /tests/steps/$name.sh ]] && source "/tests/steps/$name.sh"
sleep "${SETTLE:-1.5}"
import -window "$app_id" "/scratch/shots/$name-$theme.png"
echo "window $(xdotool getwindowgeometry "$app_id" | tr '\n' ' ')"
echo "PSS $(( $(awk '/^Pss:/{print $2}' "/proc/$app_pid/smaps_rollup") / 1024 )) MB"
grep -v -e Vulkan -e DRI3 -e "^$" -e MESA /tmp/app.log | head -20
app_down
