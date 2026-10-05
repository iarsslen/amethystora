#!/usr/bin/bash
# A starting point: how long the computer has been on, and a menu. The bar runs this every "interval"
# seconds (widget.json) and shows the last line it prints: one JSON object, built by jq -c so that any
# text in it is escaped properly.
set -euo pipefail

up="$(uptime -p | sed -e 's/^up //' -e 's/ days\?/d/' -e 's/ hours\?/h/' -e 's/ minutes\?/m/' -e 's/,//g')"

jq -cn --arg up "${up}" '{
    text: $up,
    icon: "computer-symbolic",
    menu: [
        {label: "On for \($up)"},
        {separator: true},
        {label: "Edit this widget", icon: "document-edit-symbolic", open: "widget.sh"},
        {label: "Open its folder", icon: "folder-symbolic", open: env.WIDGET_DIR}
    ]
}'
