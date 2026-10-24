atspi wait 10 "A link" >/dev/null
atspi click "A link"
sleep 0.6
xdotool type --delay 40 "example.org/menu?lang=en"
sleep 0.6
