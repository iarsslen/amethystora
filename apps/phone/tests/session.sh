# Sourced by run-shot.sh and run-behaviour.sh, inside the Rust container: a desktop session in a virtual display, with
# the accessibility bus and the window's catalogs, font and theme. `session_up THEME`, then `mock_up SCENARIO` and
# `app_up ARGUMENTS...` as often as wanted, `app_down` and `mock_down` after each.

session_up() {
    local theme=$1
    export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/xdg LANG=${LANG:-en_US.UTF-8} DISPLAY=:9 GDK_BACKEND=x11 TZ=UTC GTK_A11Y=atspi
    # The stand-in for the program is a Python script: the window, a debug build, is told that is the program to believe
    : "${AMETHYSTORA_CONNECT_EXE:=$(readlink -f "$(command -v python3)")}"
    export AMETHYSTORA_CONNECT_EXE
    : "${SIZE:=1120x780}"
    rm -rf "$HOME" /tmp/xdg
    mkdir -p "$HOME/Downloads/Phone" /tmp/xdg /scratch/shots "$HOME/Pictures"
    chmod 700 /tmp/xdg
    # The repository's catalogs over the image's, and the windows' font
    mkdir -p /usr/lib/amethystora-phone/resources/app
    cp -a /repo/usr/lib/amethystora-phone/resources/app/. /usr/lib/amethystora-phone/resources/app/ 2>/dev/null
    install -D -m0644 /branding/fonts/QuicksandVariable.ttf /usr/lib/amethystora-apps/fonts/QuicksandVariable.ttf
    # RTL=1: the window in a right-to-left language, which it takes from a catalog (an empty one is enough to choose it)
    if [[ -n ${RTL:-} ]]; then
        export LANG=ar_EG.UTF-8
        echo "{}" >/usr/lib/amethystora-phone/resources/app/locale/ar.json
    fi
    mkdir -p "$HOME/.config/amethystora/current"
    cp -a "/repo/usr/share/amethystora/themes/$theme" "$HOME/.config/amethystora/current/theme"
    # Files to send
    head -c 4200000 /dev/urandom >"$HOME/Pictures/holiday-photo.jpg"
    head -c 812000 /dev/urandom >"$HOME/Pictures/notes.pdf"
    Xvfb :9 -screen 0 1600x1000x24 >/dev/null 2>&1 &
    sleep 1
    eval "$(dbus-launch --sh-syntax)"
    /usr/libexec/at-spi-bus-launcher --launch-immediately >/dev/null 2>&1 &
    sleep 1
    atspi() { python3 /atspi.py amethystora-phone "$@"; }
}

# The mock of amethystora-connect in a scenario of mock-service.py, its calls logged in $MOCK_LOG
mock_up() {
    : >"$MOCK_LOG"
    python3 /tests/mock-service.py --xml /dbus/org.amethystora.Connect.xml --scenario "$1" --log "$MOCK_LOG" >/tmp/mock.log 2>&1 &
    mock_pid=$!
    sleep 1.5
}

mock_down() {
    kill "${mock_pid:-0}" 2>/dev/null
    wait "${mock_pid:-0}" 2>/dev/null
    mock_pid=
}

# What the mock is told to do: mock_do '{"op": "set", "device": "tab_s9", "props": {"BatteryLevel": 10}}'
mock_do() {
    gdbus call --session --dest org.amethystora.Connect --object-path /org/amethystora/Connect \
        --method org.amethystora.ConnectMock.Do "$1" >/dev/null
}

app_up() {
    setsid /target/debug/amethystora-phone "$@" >/tmp/app.log 2>&1 &
    app_pid=$!
    app_id=
    local waited=0
    while [[ -z $app_id ]] && ((waited < 40)); do
        sleep 0.25
        waited=$((waited + 1))
        app_id=$(xdotool search --pid "$app_pid" 2>/dev/null | tail -1)
    done
    [[ -n $app_id ]] || return 1
    # GTK makes more than one X window; the last is the one on screen
    sleep 2
    app_id=$(xdotool search --pid "$app_pid" 2>/dev/null | tail -1)
    xdotool windowmove "$app_id" 0 0
    xdotool windowsize "$app_id" "${SIZE%x*}" "${SIZE#*x}" 2>/dev/null
    sleep 1
}

app_down() {
    kill "${app_pid:-0}" 2>/dev/null
    wait "${app_pid:-0}" 2>/dev/null
    app_pid=
    sleep 0.5
}
