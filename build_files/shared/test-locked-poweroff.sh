#!/usr/bin/bash
# ame security locked-poweroff, for 20-tests.sh: the machine powers off only once every desktop session has
# stayed locked for 18 hours, against stand-ins for loginctl and systemctl in a temporary folder.

set -euo pipefail

T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
fail() { echo "test-locked-poweroff: $*" >&2; exit 1; }
mkdir -p "${T}/bin"
# Sessions as "id type class locked", one a line, in ${T}/sessions
cat >"${T}/bin/loginctl" <<'EOF'
#!/usr/bin/bash
case "$1" in
    list-sessions) awk '{ print $1, "1000 someone seat0 100 user tty2 no -" }' "${SESSIONS}" ;;
    show-session) awk -v id="$2" '$1 == id { print "Type=" $2; print "Class=" $3; print "LockedHint=" $4 }' "${SESSIONS}" ;;
esac
EOF
printf '#!/usr/bin/bash\necho "$*" >>"${CALLS}"\n' >"${T}/bin/systemctl"
chmod +x "${T}/bin/loginctl" "${T}/bin/systemctl"
export PATH="${T}/bin:${PATH}" SESSIONS="${T}/sessions" CALLS="${T}/calls" AMETHYSTORA_LOCKED_STATE="${T}/since"
run() { AMETHYSTORA_LOCKED_NOW="$1" /usr/libexec/amethystora-locked-poweroff >/dev/null; }
powered() { grep -qx poweroff "${CALLS}" 2>/dev/null; }

: >"${SESSIONS}"
run 1000
[[ ! -e "${AMETHYSTORA_LOCKED_STATE}" ]] || fail "nobody signed in counts as locked"
printf '2 wayland user yes\n3 tty user no\n' >"${SESSIONS}"
run 1000
[[ "$(cat "${AMETHYSTORA_LOCKED_STATE}")" == 1000 ]] || fail "a locked desktop does not start the count"
run $((1000 + 17 * 3600))
powered && fail "powered off before 18 hours"
printf '2 wayland user yes\n4 wayland user no\n' >"${SESSIONS}"
run $((1000 + 17 * 3600 + 60))
[[ ! -e "${AMETHYSTORA_LOCKED_STATE}" ]] || fail "an unlocked desktop does not end the count"
printf '2 wayland user yes\n4 wayland user yes\n' >"${SESSIONS}"
run 100000
run $((100000 + 18 * 3600))
powered || fail "every desktop locked for 18 hours did not power off"
echo "test-locked-poweroff: off only after 18 hours of every desktop locked"
