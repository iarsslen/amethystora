#!/usr/bin/bash
# run-behaviour.sh [CASE...]: inside the Rust container (tests/test.sh starts it). Uses the window as a person would,
# through the accessibility tree and the keyboard, against the mock of amethystora-connect (mock-service.py), and
# checks what the window asked the program to do from the mock's log: that a pairing is answered only by a click, that
# nothing is sent before it is asked for, that a text goes to the right thread, that what a phone wrote stays text.
# Prints one line a check, ok or FAIL; the exit status is the number that failed.
set -u
export MOCK_LOG=/tmp/calls.log
SIZE=1120x780
# shellcheck source=session.sh
source /tests/session.sh
session_up amethystora

ok=0
failed=0
check() {
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok   $what"
        ok=$((ok + 1))
    else
        echo "FAIL $what"
        failed=$((failed + 1))
    fi
}
no() { ! "$@"; }
called() { grep -qF -- "$1" "$MOCK_LOG"; }
shows() { atspi has "$1"; }
waits() { atspi wait "${2:-10}" "$1"; }
focused() { python3 /tests/probe.py focused "$1"; }
begin() {
    local scenario=$1
    shift
    [[ $scenario == none ]] || mock_up "$scenario"
    app_up "$@" || echo "no window: $(cat /tmp/app.log)"
}
finish() {
    # DEBUG=1: what the window asked the program, and what the window said itself
    [[ -n ${DEBUG:-} ]] && { echo "--- calls"; cat "$MOCK_LOG"; echo "--- app"; cat /tmp/app.log; }
    app_down
    mock_down
}

# --- A phone asks to pair -------------------------------------------------------------------------------------------
case_pairing() {
    begin pairing
    check "the request shows its key" waits "3F9A1C7E"
    check "neither answer has the focus when the page opens" no focused "Accept"
    check "...nor the other" no focused "Reject"
    check "nothing was answered by itself" no called AcceptPairing
    check "nothing was rejected by itself" no called RejectPairing
    atspi click "Accept" button
    check "Accept tells the program" bash -c "sleep 1; grep -qF '\"method\": \"AcceptPairing\", \"device\": \"sam_phone\"' $MOCK_LOG"
    check "the page says it paired" waits "Paired with Sam"
    finish

    begin pairing
    waits "3F9A1C7E" >/dev/null
    atspi click "Reject" button
    check "Reject tells the program" bash -c "sleep 1; grep -qF '\"method\": \"RejectPairing\", \"device\": \"sam_phone\"' $MOCK_LOG"
    check "...and nothing was accepted" no called AcceptPairing
    finish
}

# --- A phone changes, comes and goes while the window is open -----------------------------------------------------------
case_changes() {
    begin default
    check "the phones are listed" waits "Ada's Pixel 8"
    check "its battery shows" shows "87%"
    mock_do '{"op": "set", "device": "pixel8_ada", "props": {"BatteryLevel": 12, "BatteryCharging": false}}'
    check "a new battery level shows without asking" waits "12%" 5
    mock_do '{"op": "add", "device": {"id": "late_phone", "name": "Late Phone", "paired": false, "connected": true, "pairing": "incoming", "key": "AB12CD34", "deadline": 4102444800}}'
    check "a phone that arrives and asks to pair shows its key" waits "AB12CD34" 5
    check "...and is not answered" no called AcceptPairing
    mock_do '{"op": "remove", "device": "late_phone"}'
    check "a phone that goes is gone" bash -c "sleep 1; ! python3 /atspi.py amethystora-phone has AB12CD34"
    finish

    begin none
    check "with no program the window says the link is off" waits "The phone link is off"
    check "...and how to turn it on" shows "ame desktop phone on"
    mock_up default
    check "when the program starts the phones come" waits "Ada's Pixel 8" 10
    mock_do '{"op": "quit"}'
    check "when it goes the window says so again" waits "The phone link is off" 10
    finish
}

# --- Unpairing is asked about first ---------------------------------------------------------------------------------
case_unpair() {
    begin default
    waits "Ada's Pixel 8" >/dev/null
    atspi click "Unpair…" button
    check "a question comes before unpairing" waits "Unpair Ada's Pixel 8?"
    check "...and nothing was unpaired yet" no called '"method": "Unpair"'
    check "the question's own button has the keyboard focus, which the probe can see" focused "Unpair"
    xdotool key Escape
    sleep 1
    check "Escape leaves the phone paired" no called '"method": "Unpair"'
    atspi click "Unpair…" button
    waits "Unpair Ada's Pixel 8?" >/dev/null
    xdotool key Return
    check "confirming unpairs it" bash -c "sleep 1; grep -qF '\"method\": \"Unpair\", \"device\": \"pixel8_ada\"' $MOCK_LOG"
    finish
}

# --- Sending ---------------------------------------------------------------------------------------------------------
case_send() {
    begin default send --device pixel8_ada /tmp/home/Pictures/holiday-photo.jpg /tmp/home/Pictures/notes.pdf
    check "the files are listed" waits "holiday-photo.jpg"
    check "nothing went before Send" no called SendFiles
    xdotool key Return
    check "Send passes both files, as file: addresses" bash -c "sleep 1; grep -F SendFiles $MOCK_LOG | grep -qF 'file:///tmp/home/Pictures/holiday-photo.jpg' && grep -F SendFiles $MOCK_LOG | grep -qF 'file:///tmp/home/Pictures/notes.pdf'"
    check "progress shows" waits "of 4.2 MB" 8
    check "the end shows" waits "Sent" 8
    finish

    begin default send --device pixel8_ada /tmp/home/Pictures
    check "a folder is not sent" waits "A folder cannot be sent"
    check "...and nothing was asked of the program" no called SendFiles
    finish

    begin default send --device pixel8_ada "file://example.org/etc/passwd"
    check "a file on another host is refused with a word" waits "missing something"
    finish

    begin default send --device pixel8_ada
    waits "A link" >/dev/null
    atspi click "A link" button
    sleep 0.5
    xdotool type --delay 30 "example.org/menu?lang=en"
    xdotool key Return
    check "a link is sent as https" bash -c "sleep 1; grep -F SendUrl $MOCK_LOG | grep -qF 'https://example.org/menu?lang=en'"
    check "...and said to be sent" waits "Link sent"
    finish

    begin default send --device pixel8_ada
    waits "A link" >/dev/null
    atspi click "A link" button
    sleep 0.5
    xdotool type --delay 30 "javascript:alert(1)"
    xdotool key Return
    check "a link that is no web, mail or telephone address is not sent" bash -c "sleep 1; ! grep -qF SendUrl $MOCK_LOG"
    finish

    begin default send https://example.org/menu
    check "a link on the command line fills the box" waits "Send to a phone"
    finish
}

# --- Replying ---------------------------------------------------------------------------------------------------------
case_reply() {
    begin default reply pixel8_ada "pixel8_ada|0|com.example.chat|42"
    check "the phone's words are shown" waits "Are you coming tonight?"
    check "...as text, not as markup" shows "<i>lovely</i>"
    xdotool type --delay 30 "On my way"
    xdotool key Return
    check "the reply goes to that notification" bash -c "sleep 1; grep -F ReplyToNotification $MOCK_LOG | grep -qF 'pixel8_ada|0|com.example.chat|42' && grep -F ReplyToNotification $MOCK_LOG | grep -qF 'On my way'"
    finish

    begin default reply pixel8_ada "pixel8_ada|0|gone|1"
    check "a notification that is gone says so" waits "That notification is gone"
    finish

    begin default reply pixel8_ada "bad
id"
    check "an id with a line break is refused" waits "not the name of a phone or a notification"
    finish
}

# --- What a phone shared ------------------------------------------------------------------------------------------------
case_text() {
    begin default text pixel8_ada -- "<b>Dinner</b> at https://example.org/menu, then www.example.org/book."
    check "the text is shown as it was written" waits "<b>Dinner</b> at"
    check "nothing opened by itself" bash -c "! pgrep -f [x]dg-open && ! pgrep -f [f]irefox"
    finish

    begin default text pixel8_ada -- "--version"
    check "a text that looks like an option is only text" waits "--version"
    finish

    begin default text pixel8_ada -- "https://example.org/shared"
    check "a shared link offers to open it" waits "Open the link"
    finish
}

# --- Texts ---------------------------------------------------------------------------------------------------------------
case_messages() {
    begin default messages pixel8_ada
    check "the conversations are listed" waits "Grace Hopper"
    check "a message is text, whatever it holds" bash -c "atspi() { python3 /atspi.py amethystora-phone \"\$@\"; }; atspi has '<b>Not markup</b>'"
    atspi click "Grace Hopper" button
    check "a conversation shows its messages" waits "Are you coming tonight?"
    check "...asked for from the phone" called RequestMessages
    xdotool type --delay 30 "See you soon"
    xdotool key Return
    check "a text goes to the thread's number" bash -c "sleep 1; grep -F SendMessage $MOCK_LOG | grep -qF '+1 555 0100' && grep -F SendMessage $MOCK_LOG | grep -qF 'See you soon' && grep -F SendMessage $MOCK_LOG | grep -qF '101'"
    check "it waits for the phone, then is the phone's" waits "See you soon" 8
    finish

    begin default messages pixel8_ada
    waits "Grace Hopper" >/dev/null
    atspi click "+1 555 0122" button
    check "a group is read here" waits "Reply to it on the phone"
    check "...with nowhere to write" no shows "Write a message"
    finish

    begin default messages pixel8_ada
    waits "Grace Hopper" >/dev/null
    atspi click "New conversation" button
    sleep 0.5
    xdotool type --delay 30 "+1 555 0177"
    xdotool key Return
    sleep 0.5
    xdotool type --delay 30 "Hello there"
    xdotool key Return
    check "a new conversation starts at thread 0" bash -c "sleep 1; grep -F SendMessage $MOCK_LOG | grep -qF '+1 555 0177' && grep -F SendMessage $MOCK_LOG | grep -qF 'Hello there' && grep -F SendMessage $MOCK_LOG | grep -qF ', 0]'"
    finish

    begin default messages pixel8_ada
    waits "Grace Hopper" >/dev/null
    mock_do '{"op": "text", "device": "pixel8_ada", "thread": 101, "body": "A message that just came in"}'
    atspi click "Grace Hopper" button
    check "a message that came in shows" waits "A message that just came in" 8
    mock_do '{"op": "text", "device": "pixel8_ada", "thread": 101, "body": "And another, while it is open"}'
    check "...and one while it is open" waits "And another, while it is open" 8
    finish

    begin default messages tab_s9
    check "a phone that shares no texts says so" waits "does not share its texts"
    finish
}

# --- What the window remembers --------------------------------------------------------------------------------------------
case_state() {
    begin default messages pixel8_ada
    waits "Grace Hopper" >/dev/null
    finish
    check "the page it was left on is kept" grep -q '"page":"messages"' "$HOME/.local/state/amethystora/phone.json"
    begin default
    check "...and is the one it opens on with nothing to do" waits "Pick a conversation"
    finish
    begin default unknowncommand
    check "a command it does not know is said" waits "does not know"
    finish
}

# --- Who owns the program's name ----------------------------------------------------------------------------------------
# The name is free while the link is off: a program that is not amethystora-connect may take it, and is then
# believed in nothing and sent nothing.
case_owner() {
    mock_up default
    AMETHYSTORA_CONNECT_EXE=/usr/libexec/amethystora-connect app_up || echo "no window: $(cat /tmp/app.log)"
    check "a program that is not amethystora-connect is said to be in the way" waits "Another program is using the phone link's name"
    check "...the link shows as off" shows "The phone link is off"
    sleep 2
    check "...and the window asked it nothing at all" bash -c "! [ -s $MOCK_LOG ]"
    check "...and none of its phones show" no shows "Ada's Pixel 8"
    finish

    begin default
    check "the program that is, is believed" waits "Ada's Pixel 8"
    finish
}

# --- Ids that start with a dash -----------------------------------------------------------------------------------------
# A phone chooses its id and its notifications' ids, so an id may look like an option. The program (and the
# module) put `--` before them, which GLib takes off before the window reads its words.
case_dashes() {
    local paired="-dash-phone-0123456789abcdef0123456789" nearby="-dash-nearby-0123456789abcdef012345678"
    local add='{"op": "add", "device": {"id": "%s", "name": "%s", "paired": %s, "connected": true}}'
    mock_up default
    mock_do "$(printf "$add" "$paired" "Dash Phone" true)"
    mock_do "$(printf "$add" "$nearby" "Dash Nearby" false)"
    app_up messages -- "$paired" || echo "no window: $(cat /tmp/app.log)"
    check "texts of a phone whose id starts with a dash" waits "Dash Phone"
    check "...asked of that phone" bash -c "sleep 1; grep -F RequestConversations $MOCK_LOG | grep -qF -- '$paired'"
    app_down

    app_up send --device="$paired" /tmp/home/Pictures/notes.pdf || echo "no window: $(cat /tmp/app.log)"
    check "sending to such a phone, by --device=ID" waits "Send to Dash Phone"
    check "...with the file" shows "notes.pdf"
    app_down

    app_up reply -- "$paired" "-notification-1|0|-pkg|-3" || echo "no window: $(cat /tmp/app.log)"
    check "a reply to a notification whose id starts with a dash reaches the phone" bash -c "sleep 2; grep -F GetRepliable $MOCK_LOG | grep -qF -- '$paired'"
    check "...and the window is the reply's" waits "That notification is gone"
    app_down

    app_up reply -- "$paired" "--gapplication-service" || echo "no window: $(cat /tmp/app.log)"
    check "a notification id that is GApplication's own option is only an id" waits "That notification is gone"
    app_down

    app_up pair -- "$nearby" || echo "no window: $(cat /tmp/app.log)"
    check "pairing a phone whose id starts with a dash asks that phone" bash -c "sleep 2; grep -F '\"method\": \"Pair\"' $MOCK_LOG | grep -qF -- '$nearby'"
    app_down

    app_up || echo "no window: $(cat /tmp/app.log)"
    check "with no arguments, the phones" waits "Dash Phone"
    finish
}

cases=("$@")
[[ ${#cases[@]} -eq 0 ]] && cases=(pairing changes unpair send reply text messages state owner dashes)
for name in "${cases[@]}"; do
    echo "== $name"
    "case_$name"
done
echo "$ok ok, $failed failed"
exit "$failed"
