#!/usr/bin/bash
# What the real-machine walk is doing, on disk before it does it, so that a freeze names the test it came in.
#   ledger.sh start ITEM "what it does"   one test at a time: refuses while another is open
#   ledger.sh step "what comes next"      written before the step runs
#   ledger.sh end RESULT ["note"]         pass, fail, skip or stopped
#   ledger.sh status                      the open test and the last lines
#   ledger.sh beat                        a heartbeat in the background: every 5 s, does GNOME Shell answer
#   ledger.sh hang                        after a freeze: the test that was open, and the last heartbeats
# The file is on the machine, each line synced before the command returns; tests/real/LEDGER.tsv is its pushed copy.
# Lines name checklist items and steps only: the repository is public.
set -uo pipefail

DIR="${HOME}/.local/state/amethystora/walk"
# A track that runs beside the walk and never touches the screen keeps its own: WALK_TRACK=terminal
LEDGER="${DIR}/ledger${WALK_TRACK:+-${WALK_TRACK}}.tsv"
BEATS="${DIR}/beats.tsv"
mkdir -p "${DIR}"

put() {
    printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$2" "$3" >>"${LEDGER}"
    sync -d "${LEDGER}"
    logger -t amethystora-walk -- "$1 $2 $3"
}

# The test still open: its last start with no end after it
open_test() {
    awk -F'\t' '$2 == "start" { t = $3 } $2 == "end" { t = "" } END { print t }' "${LEDGER}" 2>/dev/null
}

case "${1:-}" in
start)
    current="$(open_test)"
    if [[ -n "${current}" ]]; then
        echo "${current} is still open: end it first" >&2
        exit 1
    fi
    put start "$2" "${3:-}"
    ;;
step)
    put step "$(open_test)" "$2"
    ;;
end)
    put end "$(open_test)" "$2 ${3:-}"
    ;;
status)
    echo "open: $(open_test)"
    tail -n "${2:-8}" "${LEDGER}"
    ;;
beat)
    systemctl --user is-active --quiet amethystora-walk-beat.service && exit 0
    systemd-run --user --quiet --unit=amethystora-walk-beat --collect "$(realpath "$0")" beating
    ;;
beating)
    while :; do
        if timeout 3 gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
            --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then shell=ok; else shell=NO-ANSWER; fi
        printf '%s\t%s\t%s\n' "$(date '+%F %T')" "${shell}" "$(cut -d' ' -f1 /proc/loadavg)" >>"${BEATS}"
        sync -d "${BEATS}"
        sleep 5
    done
    ;;
hang)
    echo "open when it stopped: $(open_test)"
    echo "--- last of the ledger"
    tail -n 12 "${LEDGER}"
    echo "--- last heartbeats"
    tail -n 6 "${BEATS}" 2>/dev/null
    for other in "${DIR}"/ledger-*.tsv; do
        [[ -e "${other}" ]] && echo "--- ${other##*/}" && tail -n 5 "${other}"
    done
    echo "--- first time the shell stopped answering, in the last run of them"
    awk -F'\t' '$2 == "ok" { first = "" } $2 != "ok" && first == "" { first = $0 } END { print first }' "${BEATS}" 2>/dev/null
    ;;
*)
    sed -n '2,8p' "$0" >&2
    exit 64
    ;;
esac
