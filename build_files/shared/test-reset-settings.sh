#!/usr/bin/bash
# The machine's half of `ame system reset-settings` (/usr/libexec/amethystora-reset-settings, or the copy named
# first) against a stand-in /etc and /usr/etc, for 20-tests.sh: it puts back, takes away and brings back exactly
# what differs from the image, and nothing it keeps: what the machine knows, every place the security watcher
# watches (its DRIFT_PATHS, read from the watcher named second), the units Security switches and the files
# amethystora-hardening names. It saves everything first, and undo brings /etc back byte for byte.

set -euo pipefail

RESET="${1:-/usr/libexec/amethystora-reset-settings}"
WATCH="${2:-/usr/libexec/amethystora-security-watch}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
export AMETHYSTORA_RESET_ROOT="${T}"
E="${T}/etc"
U="${T}/usr/etc"
put() {
    mkdir -p "$(dirname "$1")"
    printf '%s\n' "$2" >"$1"
}
link() {
    mkdir -p "$(dirname "$2")"
    ln -s "$1" "$2"
}
fail() {
    echo "test-reset-settings: $*" >&2
    exit 1
}

# The image's /etc, which a machine starts with
put "${U}/foo.conf" image
put "${U}/gone.conf" image
put "${U}/same.conf" image
put "${U}/passwd" "root:x:0:0:root:/root:/bin/bash"
put "${U}/chrony.conf" "server image"
put "${U}/dconf/db/local" compiled
link /usr/lib/systemd/system/fstrim.timer "${U}/systemd/system/timers.target.wants/fstrim.timer"
link /usr/lib/systemd/system/uupd.timer "${U}/systemd/system/timers.target.wants/uupd.timer"
link /usr/share/zoneinfo/UTC "${U}/localtime"
mkdir -p "${E}"
cp -a "${U}/." "${E}/"

# What this machine changed since, which goes back
put "${E}/foo.conf" changed
rm "${E}/gone.conf"
put "${E}/added.conf" added
put "${E}/NetworkManager/conf.d/99-mine.conf" mine
rm "${E}/systemd/system/timers.target.wants/fstrim.timer"
link /usr/lib/systemd/system/sshd.service "${E}/systemd/system/multi-user.target.wants/sshd.service"
link /dev/null "${E}/systemd/system/cups.service"
# ...and what it keeps: an account, a time zone, a network, the dconf databases compiled at every start, the
# units Security, Updates and a domain's logins switch, the switches' files, and every place Security watches
put "${E}/passwd" "root:x:0:0:root:/root:/bin/bash
someone:x:1000:1000::/var/home/someone:/bin/bash"
rm "${E}/localtime"
link /usr/share/zoneinfo/Europe/Paris "${E}/localtime"
put "${E}/NetworkManager/system-connections/home.nmconnection" wifi
put "${E}/NetworkManager/conf.d/60-amethystora-mac.conf" mac
put "${E}/systemd/resolved.conf.d/60-amethystora-dns.conf" dns
put "${E}/dconf/db/local" recompiled
rm "${E}/systemd/system/timers.target.wants/uupd.timer"
link /usr/lib/systemd/system/fail2ban.service "${E}/systemd/system/multi-user.target.wants/fail2ban.service"
link /usr/lib/systemd/system/sssd.service "${E}/systemd/system/multi-user.target.wants/sssd.service"
link /dev/null "${E}/systemd/system/avahi-daemon.socket"
put "${E}/systemd/system/auditd.service.d/override.conf" mine
put "${E}/amethystora/hardening-on" time
put "${E}/chrony.conf" "server nts"
mapfile -t WATCHED < <(bash -c "$(sed -n '/^DRIFT_PATHS=(/,/)$/p' "${WATCH}")"'; printf "%s\n" "${DRIFT_PATHS[@]}"')
[[ ${#WATCHED[@]} -gt 30 ]] || fail "read no DRIFT_PATHS from ${WATCH}"
for rel in "${WATCHED[@]}"; do
    put "${E}/${rel}/reset-test" watched
done

BEFORE="${T}/before"
cp -a "${E}" "${BEFORE}"
EXPECTED="added	/etc/NetworkManager/conf.d/99-mine.conf
added	/etc/added.conf
changed	/etc/foo.conf
removed	/etc/gone.conf
added	/etc/systemd/system/cups.service
added	/etc/systemd/system/multi-user.target.wants/sshd.service
removed	/etc/systemd/system/timers.target.wants/fstrim.timer"
LISTED="$("${RESET}" list)"
[[ "${LISTED}" == "${EXPECTED}" ]] || fail "list gave:
${LISTED}"

"${RESET}" machine >/dev/null
for rel in foo.conf gone.conf same.conf; do
    cmp -s "${E}/${rel}" "${U}/${rel}" || fail "/etc/${rel} is not the image's"
done
[[ "$(readlink "${E}/systemd/system/timers.target.wants/fstrim.timer")" == /usr/lib/systemd/system/fstrim.timer ]] ||
    fail "the image's fstrim.timer link is not back"
for rel in added.conf NetworkManager/conf.d/99-mine.conf systemd/system/multi-user.target.wants/sshd.service \
    systemd/system/cups.service; do
    [[ ! -e "${E}/${rel}" && ! -L "${E}/${rel}" ]] || fail "/etc/${rel} is still there"
done
# Everything kept is as it was
for rel in passwd localtime NetworkManager/system-connections/home.nmconnection \
    NetworkManager/conf.d/60-amethystora-mac.conf systemd/resolved.conf.d/60-amethystora-dns.conf chrony.conf \
    dconf/db/local systemd/system/multi-user.target.wants/fail2ban.service \
    systemd/system/multi-user.target.wants/sssd.service systemd/system/avahi-daemon.socket \
    systemd/system/auditd.service.d/override.conf "${WATCHED[@]/%//reset-test}"; do
    if [[ -L "${BEFORE}/${rel}" ]]; then
        [[ "$(readlink "${E}/${rel}")" == "$(readlink "${BEFORE}/${rel}")" ]] || fail "/etc/${rel} changed"
    else
        cmp -s "${E}/${rel}" "${BEFORE}/${rel}" || fail "/etc/${rel} changed"
    fi
done
[[ ! -e "${E}/systemd/system/timers.target.wants/uupd.timer" ]] || fail "uupd.timer, Updates' to switch, came back"
# Saved first, and a second reset finds nothing
SAVE="$("${RESET}" saved machine)"
[[ "$(wc -l <"${SAVE}/changes")" == 7 ]] || fail "the save lists $(wc -l <"${SAVE}/changes") changes"
cmp -s "${SAVE}/etc/foo.conf" "${BEFORE}/foo.conf" || fail "the changed foo.conf was not saved"
[[ -z "$("${RESET}" list)" ]] || fail "a second reset still finds: $("${RESET}" list)"

# Undo: /etc as it was, byte for byte and link for link, and the save kept under another name
"${RESET}" undo machine >/dev/null
diff -r --no-dereference "${BEFORE}" "${E}" >/dev/null || fail "undo left /etc different: $(diff -rq --no-dereference "${BEFORE}" "${E}")"
[[ -d "${SAVE}.undone" ]] || fail "the undone save is gone"
"${RESET}" saved machine >/dev/null && fail "an undone reset is still offered to undo"
true
