#!/usr/bin/bash
# The private folder (/usr/libexec/amethystora-private-folder, or the copy named first) against stand-ins for
# gocryptfs, systemd-run, systemctl, zenity and findmnt, for 20-tests.sh, since a build has no FUSE: opening
# refuses a mount point with plain files in it, starts the watcher before it mounts and stops it when the
# mount fails, and the password reaches no argument and no file; closing takes away the thumbnails and the
# recent files of what was in the folder and nothing else, writes the rest of the list back as it was, and
# names the programs that had a file open in it; removing refuses a folder with something in it. It runs as
# nobody, since the helper refuses root.

set -euo pipefail

HELPER="${1:-/usr/libexec/amethystora-private-folder}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
fail() { echo "test-private-folder: $*" >&2; exit 1; }
mkdir -p "${T}/bin" "${T}/home" "${T}/state"
HOME_DIR="${T}/home"
PLAIN="${HOME_DIR}/Private"
CIPHER="${HOME_DIR}/.local/share/amethystora/private"
LOG="${T}/state/log"
: >"${LOG}"
# The password the dialog gives, kept outside the home
printf 'wrong one\n' >"${T}/answer"

# Every stand-in logs how it was called. gocryptfs opens the folder for one password only; the mount and the
# two units are files in ${T}/state.
cat >"${T}/bin/stub" <<'EOF'
#!/usr/bin/bash
echo "${0##*/} $*" >>"${LOG}"
case "${0##*/}" in
    systemctl)
        [[ "$1" == --user ]] && shift
        unit="${@: -1}"
        case "$1" in
            start) touch "${STATE}/${unit}" ;;
            stop) rm -f "${STATE}/${unit}"; [[ "${unit}" == *.scope ]] && rm -f "${STATE}/mounted" ;;
            is-active) [[ -e "${STATE}/${unit}" ]]; exit ;;
        esac
        ;;
    systemd-run)
        while [[ "$1" != -- ]]; do shift; done
        shift
        touch "${STATE}/amethystora-private-folder.scope"
        "$@" || { rc=$?; rm -f "${STATE}/amethystora-private-folder.scope"; exit "${rc}"; }
        ;;
    gocryptfs)
        read -r password
        [[ "${password}" == right-password ]] || exit 12
        touch "${STATE}/mounted"
        ;;
    zenity)
        [[ "$1" == --password ]] && cat "${ANSWER}"
        ;;
    findmnt) [[ -e "${STATE}/mounted" ]]; exit ;;
    fusermount3) rm -f "${STATE}/mounted" ;;
esac
exit 0
EOF
chmod +x "${T}/bin/stub"
for name in systemctl systemd-run gocryptfs zenity findmnt fusermount3 notify-send gio; do
    ln -s stub "${T}/bin/${name}"
done
chown -R 65534:65534 "${T}/home" "${T}/state"
chmod 0755 "${T}"
run() {
    setpriv --reuid=65534 --regid=65534 --clear-groups env HOME="${HOME_DIR}" PATH="${T}/bin:${PATH}" \
        LOG="${LOG}" STATE="${T}/state" ANSWER="${T}/answer" "$@"
}
# On a terminal of its own, for what asks questions
on_terminal() {
    run python3 -I -c 'import os, pty, sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))' "$@" </dev/null
}
as_nobody() { run bash -c "$1"; }

[[ "$(run "${HELPER}" status --json | jq -r .state)" == none ]] || fail "no folder is not none"
as_nobody "mkdir -p '${CIPHER}' '${PLAIN}' && touch '${CIPHER}/gocryptfs.conf' && chmod 0500 '${PLAIN}'"
[[ "$(run "${HELPER}" status --json | jq -r .state)" == closed ]] || fail "a folder not mounted is not closed"

# Plain files in the mount point while it is closed are not encrypted, and opening says so and stops there
as_nobody "chmod 0700 '${PLAIN}' && touch '${PLAIN}/loose.txt' && chmod 0500 '${PLAIN}'"
out="$(run "${HELPER}" open --show 2>&1 </dev/null)" && fail "opened over a file left in the mount point"
grep -q "loose.txt" "${LOG}" || [[ "${out}" == *loose.txt* ]] || fail "the file left in the mount point was not named"
grep -qE "^(gocryptfs|systemctl --user start)" "${LOG}" && fail "it went on to open over a file left in the mount point"
as_nobody "chmod 0700 '${PLAIN}' && rm '${PLAIN}/loose.txt' && chmod 0500 '${PLAIN}'"

# The wrong password, five times: the watcher started before the first try and stopped after the last
: >"${LOG}"
run "${HELPER}" open --show </dev/null >/dev/null 2>&1 && fail "opened with the wrong password"
grep -nE "^(systemctl --user start|systemd-run|systemctl --user stop amethystora-private-folder-watch)" "${LOG}" >"${T}/order"
head -n1 "${T}/order" | grep -q "start amethystora-private-folder-watch.service" || fail "the watcher did not start first"
[[ "$(grep -c "^gocryptfs" "${LOG}")" == 5 ]] || fail "the wrong password was not asked again, four times"
tail -n1 "${T}/order" | grep -q "stop amethystora-private-folder-watch.service" || fail "the watcher stayed after a failed open"
[[ "$(stat -c %a "${PLAIN}")" == 500 ]] || fail "the mount point stayed writable after a failed open"

# The right one opens it and shows it, and is nowhere but where it came from
printf 'right-password\n' >"${T}/answer"
: >"${LOG}"
run "${HELPER}" open --show </dev/null || fail "did not open with the right password"
[[ "$(run "${HELPER}" status --json | jq -r .state)" == open ]] || fail "an open folder is not open"
grep -q "^gio open ${PLAIN}$" "${LOG}" || fail "the open folder was not shown in Files"
grep -q "^gocryptfs -q ${CIPHER} ${PLAIN}$" "${LOG}" || fail "gocryptfs was not given the folder"
grep -rqF right-password "${LOG}" "${HOME_DIR}" && fail "the password reached an argument or a file"

# What would show what was in it: thumbnails (the host's and a Flatpak app's, and a failed one) and recent files
uri="file://${PLAIN}"
thumb() {
    as_nobody "mkdir -p '$(dirname "$1")' && printf '\x89PNG\r\n\x1a\n....tEXtThumb::URI\0%s\0....' '$2' >'$1'"
}
thumb "${HOME_DIR}/.cache/thumbnails/large/private.png" "${uri}/holiday.jpg"
thumb "${HOME_DIR}/.cache/thumbnails/fail/gnome-thumbnail-factory/failed.png" "${uri}/broken.pdf"
thumb "${HOME_DIR}/.var/app/org.gnome.Loupe/cache/thumbnails/normal/app.png" "${uri}/sub/scan.png"
thumb "${HOME_DIR}/.cache/thumbnails/large/other.png" "file://${HOME_DIR}/Documents/report.png"
thumb "${HOME_DIR}/.cache/thumbnails/large/near.png" "file://${HOME_DIR}/Private-notes/a.png"
as_nobody "mkdir -p '${HOME_DIR}/.local/share' && cat >'${HOME_DIR}/.local/share/recently-used.xbel'" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0"
      xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"
      xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info"
>
  <bookmark href="${uri}/letter.odt" added="2026-10-21T10:00:00.000000Z" modified="2026-10-21T10:00:00.000000Z" visited="2026-10-21T10:00:00.000000Z">
    <info>
      <metadata owner="http://freedesktop.org">
        <mime:mime-type type="application/vnd.oasis.opendocument.text"/>
        <bookmark:applications>
          <bookmark:application name="LibreOffice" exec="&apos;soffice %u&apos;" modified="2026-10-21T10:00:00.000000Z" count="1"/>
        </bookmark:applications>
      </metadata>
    </info>
  </bookmark>
  <bookmark href="file://${HOME_DIR}/Documents/plan.txt" added="2026-10-21T11:00:00.000000Z" modified="2026-10-21T11:00:00.000000Z" visited="2026-10-21T11:00:00.000000Z">
    <info>
      <metadata owner="http://freedesktop.org">
        <mime:mime-type type="text/plain"/>
        <bookmark:applications>
          <bookmark:application name="Text Editor" exec="&apos;gnome-text-editor %u&apos;" modified="2026-10-21T11:00:00.000000Z" count="2"/>
        </bookmark:applications>
      </metadata>
    </info>
  </bookmark>
</xbel>
EOF

# A program with its working folder in it, which closing names
run bash -c "cd '${PLAIN}' && exec sleep 60" &
holder=$!
for _ in $(seq 50); do
    [[ "$(readlink "/proc/${holder}/cwd" 2>/dev/null)" == "${PLAIN}" ]] && break
    sleep 0.1
done
: >"${LOG}"
run "${HELPER}" close </dev/null || fail "did not close"
kill "${holder}" 2>/dev/null || true
grep -q "^systemctl --user stop amethystora-private-folder-watch.service$" "${LOG}" || fail "closing by hand left the watcher"
grep -q "^systemctl --user stop amethystora-private-folder.scope$" "${LOG}" || fail "gocryptfs's scope was not stopped"
[[ "$(run "${HELPER}" status --json | jq -r .state)" == closed ]] || fail "a closed folder is not closed"
[[ "$(stat -c %a "${PLAIN}")" == 500 ]] || fail "the closed mount point takes files"
grep -q "^notify-send .*sleep" "${LOG}" || fail "the program that had its working folder in it was not named"
for gone in .cache/thumbnails/large/private.png .cache/thumbnails/fail/gnome-thumbnail-factory/failed.png \
    .var/app/org.gnome.Loupe/cache/thumbnails/normal/app.png; do
    [[ ! -e "${HOME_DIR}/${gone}" ]] || fail "a thumbnail of the folder stayed: ${gone}"
done
for kept in .cache/thumbnails/large/other.png .cache/thumbnails/large/near.png; do
    [[ -e "${HOME_DIR}/${kept}" ]] || fail "a thumbnail of something else went: ${kept}"
done
XBEL="${HOME_DIR}/.local/share/recently-used.xbel"
grep -qF "${uri}/" "${XBEL}" && fail "a recent file in the folder stayed"
grep -qF "href=\"file://${HOME_DIR}/Documents/plan.txt\"" "${XBEL}" || fail "a recent file elsewhere went"
grep -q '<bookmark:application name="Text Editor"' "${XBEL}" || fail "the recent files were not written back as they were"
grep -q '<mime:mime-type type="text/plain"' "${XBEL}" || fail "the recent files lost their mime: prefix"

# As the watcher's ExecStopPost (systemd sets SERVICE_RESULT), closing does not stop the watcher it runs in
: >"${LOG}"
run env SERVICE_RESULT=success "${HELPER}" close </dev/null
grep -q "stop amethystora-private-folder-watch" "${LOG}" && fail "the watcher's own ExecStopPost stops the watcher"

# Nothing in it is ever deleted: removing an open folder with a file in it refuses
run "${HELPER}" open </dev/null >/dev/null || fail "did not open again"
as_nobody "touch '${PLAIN}/keep.txt'"
on_terminal "${HELPER}" remove >/dev/null 2>&1 && fail "removed a folder with a file in it"
[[ -e "${CIPHER}/gocryptfs.conf" && -e "${PLAIN}/keep.txt" ]] || fail "removing a folder with a file in it deleted something"
echo "test-private-folder: opening, closing and removing as the private folder should"
