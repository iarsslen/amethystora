#!/bin/bash
# Runs in the container that plays the phone: Fedora's kdeconnectd on a session bus of its own, offscreen.
set -u
export HOME=/tmp/phone/home XDG_CONFIG_HOME=/tmp/phone/config XDG_RUNTIME_DIR=/tmp/phone/run QT_QPA_PLATFORM=offscreen
export QT_LOGGING_RULES="kdeconnect.*=true" QT_LOGGING_TO_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1
mkdir -p "$HOME/Downloads" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
ADDRESS=$(dbus-daemon --session --fork --print-address)
echo "$ADDRESS" > /tmp/bus-address
export DBUS_SESSION_BUS_ADDRESS="$ADDRESS"
python3 /interop/fake-notifications.py /tmp/notifications.jsonl > /tmp/fake-notifications.log 2>&1 &
sleep 1
kdeconnectd >> /tmp/kdeconnectd.log 2>&1 &
echo $! > /tmp/kdeconnectd.pid
echo ready > /tmp/ready
sleep infinity
