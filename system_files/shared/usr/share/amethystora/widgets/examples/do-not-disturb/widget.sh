#!/usr/bin/bash
# Do Not Disturb, shown only while notifications are silenced, with a switch that brings them back.
# "interval" is 0 in widget.json, so this keeps running and prints a line whenever the setting changes,
# instead of being asked every few seconds. gsettings flushes each line it prints; a program that does
# not would need stdbuf -oL in front of it, or flush=True in Python.
set -euo pipefail

KEY=(org.gnome.desktop.notifications show-banners)

if [[ ${1:-} == toggle ]]; then
    if [[ "$(gsettings get "${KEY[@]}")" == true ]]; then
        gsettings set "${KEY[@]}" false
    else
        gsettings set "${KEY[@]}" true
    fi
    exit 0
fi

show() {
    if [[ "$(gsettings get "${KEY[@]}")" == true ]]; then
        echo '{"hidden": true}'
    else
        echo '{"icon": "notifications-disabled-symbolic", "class": "warning", "menu": [{"label": "Do Not Disturb", "toggle": true, "run": "./widget.sh toggle"}]}'
    fi
}

show
gsettings monitor "${KEY[@]}" | while read -r _; do show; done
