#!/usr/bin/bash
# A 25-minute focus timer: click it to start, and its menu stops it. "./widget.sh start" and
# "./widget.sh stop" are what the click and the menu run. What it remembers, the time the timer ends,
# is a file in $WIDGET_STATE and never in its own folder: the bar loads a widget again whenever its
# folder changes.
set -euo pipefail

MINUTES=25
END="${WIDGET_STATE}/end"

case "${1:-}" in
    start) echo $(($(date +%s) + MINUTES * 60)) >"${END}" ;;
    stop) rm -f "${END}" ;;
esac
[[ -z ${1:-} ]] || exit 0

left=0
[[ -s ${END} ]] && left=$(($(<"${END}") - $(date +%s)))
if ((left <= 0)); then
    if [[ -e ${END} ]]; then
        rm -f "${END}"
        notify-send --app-name=Pomodoro --icon=alarm-symbolic "Time for a break" "That was ${MINUTES} minutes of focus."
    fi
    echo '{"icon": "alarm-symbolic", "click": "./widget.sh start"}'
    exit 0
fi

printf '{"text": "%02d:%02d", "icon": "alarm-symbolic", "class": "accent", "menu": [{"label": "Stop the timer", "run": "./widget.sh stop"}]}\n' \
    $((left / 60)) $((left % 60))
