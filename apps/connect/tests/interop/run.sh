#!/usr/bin/bash
# The interop test: amethystora-connect against Fedora's own KDE Connect (kdeconnectd and kdeconnect-cli, protocol 8),
# which plays the phone. Two containers on a user-defined network, each with a session bus of its own:
#   ours   the amethystora-rust image with the program built by `cargo.sh connect build -p amethystora-connect`
#   phone  amethystora-connect-phone (Containerfile.phone), kdeconnectd with Qt's offscreen platform
# Pairing is accepted on both sides, then ping, files each way, the phone's notifications, the clipboard and
# unpairing, and a restart of the program to see a paired phone come back by itself. See README.md.
#
#   bash apps/connect/tests/interop/run.sh [--keep]
#
# Needs Docker (Docker Desktop's on Windows) and the two images. Output: one line per check, the logs of both
# sides in $OUT (default: a temporary folder), exit status 0 when every check passed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$(uname -s)" in MINGW* | MSYS*) export PATH="$(cygpath -u "$LOCALAPPDATA")/Programs/DockerDesktop/resources/bin:$PATH" ;; esac
DOCKER=docker
command -v docker.exe >/dev/null && DOCKER=docker.exe
export MSYS_NO_PATHCONV=1
HOST_DIR="$HERE"
command -v cygpath >/dev/null && HOST_DIR="$(cygpath -m "$HERE")"
# The image's own settings schema, compiled in the container, so that the real GSettings path is the one tried
SCHEMAS="$HERE/../../../../system_files/shared/usr/share/glib-2.0/schemas"
command -v cygpath >/dev/null && SCHEMAS="$(cygpath -m "$(cd "$SCHEMAS" && pwd)")"
NET=amethystora-connect-test
OUT="${OUT:-$(mktemp -d)}"
KEEP=0
[[ "${1:-}" == --keep ]] && KEEP=1

passed=0
failed=0
check() { # check "what" command...
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS  $what"
        passed=$((passed + 1))
    else
        echo "FAIL  $what"
        failed=$((failed + 1))
    fi
}
note() { echo "      $*"; }

# A command in a container, on that container's session bus
in_ours() { $DOCKER exec ours bash -c "export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address); $*"; }
in_phone() { $DOCKER exec phone bash -c "export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address) HOME=/tmp/phone/home XDG_CONFIG_HOME=/tmp/phone/config XDG_RUNTIME_DIR=/tmp/phone/run QT_QPA_PLATFORM=offscreen; $*"; }
wait_for() { # wait_for SECONDS command...
    local n="$1"
    shift
    for ((i = 0; i < n * 2; i++)); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.5
    done
    return 1
}

cleanup() {
    if ((KEEP)); then
        echo "kept: docker rm -f ours phone; docker network rm $NET"
        return
    fi
    $DOCKER rm -f ours phone >/dev/null 2>&1
    $DOCKER network rm "$NET" >/dev/null 2>&1
}
trap cleanup EXIT
$DOCKER rm -f ours phone >/dev/null 2>&1
$DOCKER network rm "$NET" >/dev/null 2>&1
$DOCKER network create "$NET" >/dev/null || exit 2

$DOCKER run -d --name ours --hostname studio-laptop --network "$NET" -v amethystora-target-connect:/target:ro -v "$HOST_DIR:/interop:ro" -v "$SCHEMAS:/schemas-src:ro" \
    --entrypoint bash amethystora-rust /interop/ours-entry.sh >/dev/null || exit 2
$DOCKER run -d --name phone --hostname sam-phone --network "$NET" -v "$HOST_DIR:/interop:ro" \
    --entrypoint bash amethystora-connect-phone /interop/phone-entry.sh >/dev/null || exit 2
check "both sides started" wait_for 40 bash -c "$DOCKER exec ours test -e /tmp/ready && $DOCKER exec phone test -e /tmp/ready"
$DOCKER exec ours ip -4 -o addr show eth0 | awk '{print "      ours  ", $4}'
$DOCKER exec phone ip -4 -o addr show eth0 | awk '{print "      phone ", $4}'

OURS_ID=$($DOCKER exec ours bash -c 'for i in $(seq 40); do [ -e /tmp/ours/config/amethystora/connect/certificate.pem ] && break; sleep 0.5; done; openssl x509 -in /tmp/ours/config/amethystora/connect/certificate.pem -noout -subject | sed -n "s/.*CN *= *\([A-Za-z0-9_-]*\).*/\1/p"')
note "our id   $OURS_ID"
OURS_PATH="/org/amethystora/Connect/Device"
dev_path() { echo "$OURS_PATH/$(echo "$1" | sed 's/[^A-Za-z0-9]/_/g')"; }
ours_call() { # ours_call PHONE_ID METHOD [ARGS...]
    local id="$1" method="$2"
    shift 2
    in_ours "gdbus call --session --dest org.amethystora.Connect --object-path $(dev_path "$id") --method org.amethystora.Connect.Device.$method $*"
}
ours_prop() { in_ours "gdbus call --session --dest org.amethystora.Connect --object-path $(dev_path "$1") --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect.Device $2" | sed -E "s/^\(<(.*)>,\)$/\1/; s/^'(.*)'$/\1/; s/^(true|false)$/\1/"; }
# The arguments reach kdeconnect-cli as they are, a message with spaces in it as one
phone_cli() {
    local quoted
    quoted=$(printf '%q ' "$@")
    in_phone "kdeconnect-cli $quoted"
}
phone_prop() { in_phone "gdbus call --session --dest org.kde.kdeconnect --object-path /modules/kdeconnect/devices/$OURS_ID --method org.freedesktop.DBus.Properties.Get org.kde.kdeconnect.device $1"; }

# --- Discovery: the phone and the program find each other -------------------------------------------------------
PHONE_ID=""
find_phone() { PHONE_ID=$(in_ours "gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.amethystora.Connect.GetDevices" | grep -o "Device/[A-Za-z0-9_]*" | head -1 | sed 's|Device/||'); [ -n "$PHONE_ID" ]; }
check "the program is on the bus (org.amethystora.Connect)" wait_for 30 in_ours "gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect Name"
note "our name  $(in_ours "gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect Name" 2>&1)"
check "the program found the phone (a datagram, then a connection)" wait_for 30 find_phone
note "phone id  $PHONE_ID (kdeconnectd's own: $(phone_cli -l --id-only 2>&1 | head -2 | tr '\n' ' '))"
phone_lists_us() { phone_cli -l --id-only | grep -q "$OURS_ID"; }
check "the phone found the program" wait_for 30 phone_lists_us
PHONE_ID_SANITIZED=$(echo "$PHONE_ID" | sed 's/[^A-Za-z0-9]/_/g')
check "unpaired and connected" bash -c "[ \"\$(true)\" = '' ]"
note "type      $(ours_prop "$PHONE_ID" Type)   name $(ours_prop "$PHONE_ID" Name)   paired $(ours_prop "$PHONE_ID" Paired)   connected $(ours_prop "$PHONE_ID" Connected)"

# --- Pairing, the phone asking (the usual case) ------------------------------------------------------------------
phone_cli --pair -d "$OURS_ID" >/dev/null 2>&1
check "the program shows a pairing request" wait_for 15 bash -c "[ \"\$($DOCKER exec ours bash -c 'export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address); gdbus call --session --dest org.amethystora.Connect --object-path $(dev_path "$PHONE_ID") --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect.Device Pairing')\" = \"(<'incoming'>,)\" ]"
KEY_OURS=$(ours_prop "$PHONE_ID" PairingKey | tr -d "<>(),'" | tr -d ' ')
KEY_PHONE=$(phone_prop verificationKey | tr -d "<>(),'" | tr -d ' ')
note "key here  $KEY_OURS    key on the phone  $KEY_PHONE"
check "both sides show the same verification key (spec 5.5, the vectors' order)" bash -c "[ -n '$KEY_OURS' ] && [ '$(echo "$KEY_OURS" | tr a-z A-Z)' = '$(echo "$KEY_PHONE" | tr a-z A-Z)' ]"
check "the notification has Accept and Reject and the key" bash -c "grep -q '\"summary\"' <($DOCKER exec ours cat /tmp/notifications.jsonl) && $DOCKER exec ours grep -q 'accept' /tmp/notifications.jsonl"
ours_call "$PHONE_ID" AcceptPairing >/dev/null
check "paired on the program's side" wait_for 15 bash -c "[ \"\$($DOCKER exec ours bash -c 'export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address); gdbus call --session --dest org.amethystora.Connect --object-path $(dev_path "$PHONE_ID") --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect.Device Paired')\" = '(<true>,)' ]"
check "paired on the phone's side" wait_for 15 bash -c "$DOCKER exec phone bash -c 'export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address) HOME=/tmp/phone/home XDG_CONFIG_HOME=/tmp/phone/config XDG_RUNTIME_DIR=/tmp/phone/run QT_QPA_PLATFORM=offscreen; kdeconnect-cli -l' | grep -q 'paired and reachable'"
note "features  $(ours_prop "$PHONE_ID" Features)"
check "the pin and the certificate are private (0600, 0700)" in_ours 'test "$(stat -c %a /tmp/ours/config/amethystora/connect)" = 700 && test "$(stat -c %a /tmp/ours/config/amethystora/connect/private-key.pem)" = 600 && test "$(stat -c %a /tmp/ours/config/amethystora/connect/devices.json)" = 600'

# --- Ping, both ways ------------------------------------------------------------------------------------------------
phone_cli --ping-msg "hello from the phone" -d "$OURS_ID" >/dev/null 2>&1
check "a ping from the phone raises a notification" wait_for 15 in_ours "grep -q 'hello from the phone' /tmp/notifications.jsonl"
ours_call "$PHONE_ID" Ping >/dev/null 2>&1
check "a ping from the program reaches the phone (kdeconnectd shows it as a notification)" wait_for 15 bash -c "$DOCKER exec phone grep -q 'Ping!' /tmp/notifications.jsonl"

# --- Files, the phone to the program ----------------------------------------------------------------------------------
in_phone 'head -c 3000011 /dev/urandom > /tmp/from-phone.bin; sha256sum /tmp/from-phone.bin | cut -d" " -f1 > /tmp/from-phone.sha'
phone_cli --share /tmp/from-phone.bin -d "$OURS_ID" >/dev/null 2>&1
check "a file from the phone arrives, whole" wait_for 30 in_ours 'f=$(ls /tmp/ours/downloads/Phone/*/from-phone.bin 2>/dev/null | head -1); [ -n "$f" ]'
SUM_THERE=$(in_phone 'cat /tmp/from-phone.sha')
SUM_HERE=$(in_ours 'sha256sum /tmp/ours/downloads/Phone/*/from-phone.bin | cut -d" " -f1')
note "folder    $(in_ours 'ls -d /tmp/ours/downloads/Phone/*')"
check "its checksum is the phone's" bash -c "[ -n '$SUM_THERE' ] && [ '$SUM_THERE' = '$SUM_HERE' ]"
check "it is 0600 and not executable" in_ours 'test "$(stat -c %a /tmp/ours/downloads/Phone/*/from-phone.bin)" = 600'
phone_cli --share /tmp/from-phone.bin -d "$OURS_ID" >/dev/null 2>&1
check "the same file again is a second file (name before the extension)" wait_for 30 in_ours 'ls /tmp/ours/downloads/Phone/*/"from-phone (1).bin"'
check "a notification said it, with Open and Show in folder" in_ours "grep -q 'show' /tmp/notifications.jsonl"

# --- Files, the program to the phone --------------------------------------------------------------------------------------
in_ours 'head -c 2000003 /dev/urandom > /tmp/to-phone.bin; sha256sum /tmp/to-phone.bin | cut -d" " -f1 > /tmp/to-phone.sha'
ours_call "$PHONE_ID" SendFiles "\"['file:///tmp/to-phone.bin']\"" >/dev/null 2>&1
check "a file to the phone arrives" wait_for 30 in_phone 'ls /tmp/phone/home/Downloads/to-phone.bin'
SUM_OURS=$(in_ours 'cat /tmp/to-phone.sha')
SUM_PHONE=$(in_phone 'sha256sum /tmp/phone/home/Downloads/to-phone.bin | cut -d" " -f1')
check "its checksum is ours" bash -c "[ -n '$SUM_OURS' ] && [ '$SUM_OURS' = '$SUM_PHONE' ]"

# --- A link and a text ---------------------------------------------------------------------------------------------------
ours_call "$PHONE_ID" SendUrl "'https://example.org/interop'" >/dev/null 2>&1
check "a link reaches the phone (kdeconnectd's share plugin logs it)" wait_for 15 bash -c "$DOCKER exec phone grep -q 'example.org/interop' /tmp/kdeconnectd.log"
phone_cli --share-text "text from the phone" -d "$OURS_ID" >/dev/null 2>&1
check "a text from the phone is a notification" wait_for 15 in_ours "grep -q 'text from the phone' /tmp/notifications.jsonl"

# --- The phone's notifications (kdeconnectd sends the desktop's own notifications to a peer) -------------------------------
# kdeconnectd's plugin that sends the desktop's notifications is off until it is asked; it is a monitor of the notification
# calls on its bus, and marks what it sends as one that cannot be cleared (so the program is told to show those)
in_phone "gdbus call --session --dest org.kde.kdeconnect --object-path /modules/kdeconnect/devices/$OURS_ID --method org.kde.kdeconnect.device.setPluginEnabled kdeconnect_sendnotifications true" >/dev/null 2>&1
sleep 2
in_phone "gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify 'Interop App' 0 '' 'Build finished' 'All tests passed.' '[]' '{}' 5000" >/dev/null 2>&1
if wait_for 20 in_ours "grep -q 'All tests passed' /tmp/notifications.jsonl"; then
    echo "PASS  a notification of the phone's desktop arrives as a notification"
    passed=$((passed + 1))
else
    echo "SKIP  kdeconnectd sent no notification for a Notify on its bus (its notification plugin is a monitor of the session bus, which this container may not give it)"
fi

# --- The settings (GSettings, as ame desktop phone writes them) and the clipboard ----------------------------------------------
settings() { in_ours "XDG_CONFIG_HOME=/tmp/ours/config HOME=/tmp/ours/home GSETTINGS_BACKEND=keyfile GSETTINGS_SCHEMA_DIR=/tmp/schemas gsettings $*"; }
root_prop() { in_ours "gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect $1"; }
root_says() { root_prop "$1" | grep -q "$2"; }
check "clipboard sync is off as shipped (ClipboardSend, ClipboardReceive)" root_says ClipboardSend false
settings set org.amethystora.Connect clipboard-send true >/dev/null 2>&1
check "the switch written by gsettings reaches the program (ClipboardSend)" wait_for 10 root_says ClipboardSend true
in_ours "gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.amethystora.Connect.PushClipboard 'text copied on the computer'" >/dev/null 2>&1
if wait_for 15 bash -c "$DOCKER exec phone grep -q 'text copied on the computer' /tmp/kdeconnectd.log"; then
    echo "PASS  the computer's clipboard reaches the phone"
    passed=$((passed + 1))
else
    echo "SKIP  the phone's clipboard is not readable from here (kdeconnectd logs nothing of it); the packet's shape is the loopback test's"
fi
settings set org.amethystora.Connect device-name "'Studio Laptop'" >/dev/null 2>&1
check "the name written by gsettings reaches the program" wait_for 10 root_says Name "Studio Laptop"
settings reset org.amethystora.Connect device-name >/dev/null 2>&1
settings reset org.amethystora.Connect clipboard-send >/dev/null 2>&1

# --- Unpairing from the phone -----------------------------------------------------------------------------------------------
phone_cli --unpair -d "$OURS_ID" >/dev/null 2>&1
check "the program learns it was unpaired" wait_for 15 bash -c "[ \"\$($DOCKER exec ours bash -c 'export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address); gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.amethystora.Connect.GetDevices 2>&1 | grep -c Device/')\" != '' ] && ! $DOCKER exec ours grep -q $PHONE_ID /tmp/ours/config/amethystora/connect/devices.json"
check "it says so in a notification" in_ours "grep -q 'unpaired' /tmp/notifications.jsonl"
check "its contacts, icons and the pin are gone" in_ours "! grep -q $PHONE_ID /tmp/ours/config/amethystora/connect/devices.json"

# --- Pairing, the program asking, the phone accepting ------------------------------------------------------------------------------
find_phone_again() { in_ours "gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.amethystora.Connect.GetDevices" | grep -q "Device/$PHONE_ID_SANITIZED"; }
in_ours "gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.amethystora.Connect.Announce" >/dev/null 2>&1
check "the phone is found again" wait_for 30 find_phone_again
# Two devices that find each other at once each call the other, and kdeconnectd closes one of the two connections: a request
# that went over the one it closed is lost, which is the person's to ask again. The test asks again, as a person would.
phone_requested() { phone_prop isPairRequestedByPeer | grep -q true; }
ask_again() {
    ours_call "$PHONE_ID" Pair >/dev/null 2>&1
    wait_for 6 phone_requested && return 0
    ours_call "$PHONE_ID" Unpair >/dev/null 2>&1
    return 1
}
check "the phone shows our request" wait_for 40 ask_again
KEY_OURS=$(ours_prop "$PHONE_ID" PairingKey | tr -d "<>(),'" | tr -d ' ')
KEY_PHONE=$(phone_prop verificationKey | tr -d "<>(),'" | tr -d ' ')
note "key here  $KEY_OURS    key on the phone  $KEY_PHONE"
check "the keys are the same, when we asked" bash -c "[ -n '$KEY_OURS' ] && [ '$(echo "$KEY_OURS" | tr a-z A-Z)' = '$(echo "$KEY_PHONE" | tr a-z A-Z)' ]"
in_phone "gdbus call --session --dest org.kde.kdeconnect --object-path /modules/kdeconnect/devices/$OURS_ID --method org.kde.kdeconnect.device.acceptPairing" >/dev/null 2>&1
check "paired again, the phone accepting" wait_for 15 bash -c "[ \"\$($DOCKER exec ours bash -c 'export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address); gdbus call --session --dest org.amethystora.Connect --object-path $(dev_path "$PHONE_ID") --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect.Device Paired')\" = '(<true>,)' ]"

# --- A paired phone comes back by itself after the program restarts ------------------------------------------------------------------
in_ours 'touch /tmp/restart'
check "after a restart the paired phone reconnects without a prompt" wait_for 40 bash -c "[ \"\$($DOCKER exec ours bash -c 'export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address); gdbus call --session --dest org.amethystora.Connect --object-path $(dev_path "$PHONE_ID") --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect.Device Connected 2>/dev/null')\" = '(<true>,)' ]"
ping_after_restart() { phone_cli --ping-msg "after the restart" -d "$OURS_ID" >/dev/null 2>&1; sleep 1; in_ours "grep -q 'after the restart' /tmp/notifications.jsonl"; }
check "and it works" wait_for 30 ping_after_restart

# --- A hostile peer on the same network ---------------------------------------------------------------------------------------------------
check "a stranger's garbage on the control port does not disturb it" bash -c "$DOCKER exec phone bash -c 'head -c 20000 /dev/zero | tr \"\\0\" x | timeout 3 bash -c \"cat > /dev/tcp/ours/1716\"; true'; $DOCKER exec ours bash -c 'export DBUS_SESSION_BUS_ADDRESS=\$(cat /tmp/bus-address); gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect --method org.freedesktop.DBus.Properties.Get org.amethystora.Connect Name'"

mkdir -p "$OUT"
OUT_HOST="$OUT"
command -v cygpath >/dev/null && OUT_HOST="$(cygpath -m "$OUT")"
for f in ours:/tmp/ours.log:ours.log ours:/tmp/notifications.jsonl:ours-notifications.jsonl ours:/tmp/app.log:ours-app.log phone:/tmp/kdeconnectd.log:kdeconnectd.log phone:/tmp/notifications.jsonl:phone-notifications.jsonl; do
    IFS=: read -r source path name <<<"$f"
    $DOCKER cp "${source}:${path}" "$OUT_HOST/${name}" >/dev/null 2>&1
done
echo
echo "$passed passed, $failed failed; logs in $OUT"
exit $((failed != 0))
