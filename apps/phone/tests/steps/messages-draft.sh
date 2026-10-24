atspi wait 10 "Grace Hopper" >/dev/null
atspi click "New conversation" button
sleep 1
xdotool type --delay 60 "+1 555 0177"
sleep 0.5
xdotool key Return
sleep 1
xdotool type --delay 50 "Hello from the new conversation"
sleep 0.5
