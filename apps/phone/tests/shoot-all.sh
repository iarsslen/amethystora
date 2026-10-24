#!/usr/bin/bash
# shoot-all.sh THEME [NAME...]: every page and dialog of the window against the mock, in one theme (a folder of
# system_files/shared/usr/share/amethystora/themes: amethystora is dark, amethystora-light is light). Needs what
# shoot.sh needs (CARGO, SCRATCH). Without names, all of them. NAME.sh in steps/ is what is done in the window first.
theme=${1:?a theme}
shift
here=$(dirname "${BASH_SOURCE[0]}")
P=/tmp/home/Pictures
SHARED="Dinner at eight? The menu is at https://example.org/menu?lang=en&day=fri, and www.example.org/book is where to book (see you there)."
declare -A SHOTS=(
    [phones]="default"
    [pairing]="pairing"
    [empty]="empty"
    [many]="many"
    [off]="default"
    [narrow]="default"
    [messages-list]="default messages pixel8_ada"
    [messages]="default messages pixel8_ada"
    [messages-new]="default messages pixel8_ada"
    [messages-draft]="default messages pixel8_ada"
    [messages-group]="default messages pixel8_ada"
    [messages-bank]="default messages pixel8_ada"
    [messages-nosms]="default messages tab_s9"
    [send-choose]="default send"
    [send]="default send --device pixel8_ada $P/holiday-photo.jpg $P/notes.pdf"
    [send-progress]="default send --device pixel8_ada $P/holiday-photo.jpg $P/notes.pdf"
    [send-link]="default send --device pixel8_ada"
    [reply]="default reply pixel8_ada pixel8_ada|0|com.example.chat|42"
    [unpair]="default"
    [untrusted]="default"
    [rtl-phones]="default"
    [rtl-messages]="default messages pixel8_ada"
)
order=(phones pairing empty many off narrow messages-list messages messages-new messages-draft messages-group messages-bank messages-nosms send-choose send send-progress send-link reply text unpair untrusted rtl-phones rtl-messages)
[[ $# -gt 0 ]] && order=("$@")
for name in "${order[@]}"; do
    extra=()
    [[ $name == off ]] && extra=(NOMOCK=1)
    [[ $name == narrow ]] && extra=(SIZE=820x600)
    [[ $name == rtl-* ]] && extra=(RTL=1)
    # Another program than the real one holds the name
    [[ $name == untrusted ]] && extra=(AMETHYSTORA_CONNECT_EXE=/usr/libexec/amethystora-connect)
    echo "== $name"
    if [[ $name == text ]]; then
        env "${extra[@]}" bash "$here/shoot.sh" -n default "$theme" text text pixel8_ada -- "$SHARED"
    else
        read -r -a spec <<<"${SHOTS[$name]}"
        env "${extra[@]}" bash "$here/shoot.sh" -n "${spec[0]}" "$theme" "$name" "${spec[@]:1}"
    fi
done
