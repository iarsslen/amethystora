#!/usr/bin/bash
# Backups (amethystora-backups, /usr/libexec/amethystora-restore) on a machine laid out as the installer lays it
# out, the home folders a btrfs subvolume of their own, with the hourly snapshots on and the daily backup going
# to an append-only rest-server: what the helper lists, finds and puts back from both, as the account; that
# putting back shares a snapshot's blocks, takes the SELinux label of where it lands, refuses what leads out of
# the home, and deletes nothing; and the window, used through its page as a person would (cdp.mjs): back up now
# with the journal followed, the daily run, keep both, versions, look, the whole folder, a stale and a failed
# backup, the agent, setting up, Security, and opening it on a folder as Files does. `bootc install to-disk`
# makes no home subvolume, so phase 1 makes one, as the installer would have, and restarts.
source "$(dirname "$0")/lib.sh"
cd /

HERE="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="/var/home/${TEST_USER}"
SNAPSHOTS=/var/home/.snapshots
KEEP=/var/lib/vmlab-tests/backups
# restic's rest-server 0.14.0, run with --append-only as the plan asks of a backup server
REST_IMAGE=docker.io/restic/rest-server@sha256:d2aff06f47eb38637dff580c3e6bce4af98f386c396a25d32eb6727ec96214a5
REST_PASSWORD=vmlab-rest-account
REPO_PASSWORD=vmlab-repository-key
REPO="rest:http://${TEST_USER}:${REST_PASSWORD}@127.0.0.1:8000/${TEST_USER}/"
SHOWN="rest:http://127.0.0.1:8000/${TEST_USER}/"
# The window's page, reachable over Chromium's debugging protocol on this port
PORT=9333
ELECTRON=/usr/lib/amethystora-backups/amethystora-backups
OPENED=/tmp/vmlab-opened

# After a restart, the session comes back by itself (GDM signs the account in)
if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi

subvolume() { [[ "$(stat -f -c %T /var/home)" == btrfs && "$(stat -c %i /var/home)" == 256 ]]; }

if [[ "${SUITE_PHASE}" == 1 ]] && ! subvolume; then
    # The subvolume "home" at the top of the system's btrfs, mounted on /var/home as Anaconda writes it, with
    # what is there now copied in while nobody is signed in
    device="$(findmnt -no SOURCE -T /var/home | sed 's/\[.*//')"
    uuid="$(blkid -s UUID -o value "${device}")"
    systemctl stop gdm
    loginctl terminate-user "${TEST_USER}" 2>/dev/null
    wait_for 60 sh -c "! pgrep -u ${TEST_USER} >/dev/null"
    mkdir -p /run/vmlab-top
    mount -o subvolid=5 "${device}" /run/vmlab-top
    [[ -d /run/vmlab-top/home ]] || btrfs subvolume create /run/vmlab-top/home >/dev/null
    chown --reference=/var/home /run/vmlab-top/home
    chmod --reference=/var/home /run/vmlab-top/home
    chcon --reference=/var/home /run/vmlab-top/home
    cp -a --reflink=auto /var/home/. /run/vmlab-top/home/
    umount /run/vmlab-top
    grep -qs ' /var/home btrfs ' /etc/fstab || echo "UUID=${uuid} /var/home btrfs subvol=home,compress=zstd:1 0 0" >>/etc/fstab
    reboot_and_continue
fi

if subvolume; then
    ok "the home folders are a btrfs subvolume of their own"
else
    not_ok "/var/home is not a btrfs subvolume after the restart" "$(findmnt /var/home)" "$(grep home /etc/fstab)"
    finish
fi

uid="$(id -u "${TEST_USER}")"
# The account, with its session's bus, as a terminal in its session has it
as_tester() { user_bus env HOME="${HOME_DIR}" USER="${TEST_USER}" LOGNAME="${TEST_USER}" "$@"; }
TTY_TESTER=(runuser -u "${TEST_USER}" -- env HOME="${HOME_DIR}" USER="${TEST_USER}" LOGNAME="${TEST_USER}"
    XDG_RUNTIME_DIR="/run/user/${uid}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus")
# The helper as the window runs it: its JSON on standard output, whether it succeeded or not
restore() { as_tester /usr/libexec/amethystora-restore "$@" --json; }
# json_check WHAT JSON FILTER: ok when FILTER is true of JSON
json_check() {
    if jq -e "$3" <<<"$2" >/dev/null 2>&1; then ok "$1"; else not_ok "$1" "$(head -c 3000 <<<"$2")"; fi
}
newest_snapshot() { find "${SNAPSHOTS}" -mindepth 1 -maxdepth 1 -regextype egrep -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}' -printf '%f\n' | sort | tail -n 1; }
# A snapshot named for a minute none has yet: snapshots are named to the minute
snapshot() {
    sleep $((61 - $(date +%-S)))
    systemctl start amethystora-home-snapshot.service && newest_snapshot
}
backup_ids() { restore points | jq -r '.points[] | select(.source == "backup") | .id'; }
in_home() { as_tester bash -c "cd ~ && $1"; }
# The window's page (cdp.mjs): BODY run in it, and what it returns
page() { ELECTRON_RUN_AS_NODE=1 "${ELECTRON}" "${HERE}/cdp.mjs" "${PORT}" "$1"; }
# The window, started as its launcher starts it, in English, with its page reachable; ARGS after its own
WINDOW_UNIT=""
window() {
    WINDOW_UNIT="vmlab-backups-${RANDOM}"
    user_bus systemd-run --user --unit="${WINDOW_UNIT}" --collect --quiet --setenv=LC_ALL=en_US.UTF-8 \
        --setenv=LANGUAGE=en -- /usr/bin/amethystora-backups "--remote-debugging-port=${PORT}" \
        '--remote-allow-origins=*' "$@"
    wait_for 120 page 'if (!state.status || !state.timeline) throw new Error("still loading")'
}
# Closed as quitting closes it: its main process told to end
close_window() {
    [[ -z "${WINDOW_UNIT}" ]] || user_systemctl kill --kill-whom=main --signal=SIGTERM "${WINDOW_UNIT}.service" >/dev/null 2>&1
    wait_for 30 sh -c "! pgrep -u ${TEST_USER} -f '^${ELECTRON}'"
}
# The timeline's point ID picked, and its listing of the folder shown read
go_to() {
    page "const i = state.timeline.points.findIndex((p) => p.id === '$1');
        if (i < 0) throw new Error('no point $1 in ' + JSON.stringify(state.timeline.points));
        document.querySelectorAll('.moment')[i].click();" >/dev/null &&
        wait_for 180 page "if (state.point !== '$1' || !state.listing || !state.listing.entries) throw 0"
}
# The folder NAME in the listing opened, then RELATIVE (its path in the home) shown
open_folder() {
    page "click('.file-name.folder', '$1')" >/dev/null &&
        wait_for 180 page "if (state.folder !== '$2' || !state.listing || !state.listing.entries) throw 0"
}
select_file() {
    page "const row = [...document.querySelectorAll('.file-row')].find((r) => r.querySelector('.file-name').textContent === '$1');
        if (!row) throw new Error('no row for $1');
        const box = row.querySelector('input');
        if (!box.checked) box.click();
        return true;" >/dev/null
}
# What the last thing done in the window came to, once it has
banner() {
    wait_for 300 page 'if (state.working || !state.banner) throw 0' && page 'return state.banner'
}
# What Ctrl+R does: what is set up and every point read again
reload() { page 'await load({ quiet: true })' >/dev/null; }
show_status() { page 'click(".nav [data-page=status]")' >/dev/null && sleep 1; }
show_browse() { page 'click(".nav [data-page=browse]")' >/dev/null && sleep 1; }

cleanup() {
    close_window
    pkill -TERM -o -u "${TEST_USER}" -f '^/usr/lib/amethystora-security/amethystora-security' 2>/dev/null
    pkill -u "${TEST_USER}" -f 'amethystora-agent diagnose|amethystora-in-terminal ame backup' 2>/dev/null
    as_tester systemctl --user disable --now amethystora-backup.timer >/dev/null 2>&1
    rm -f "${HOME_DIR}/.config/amethystora/backup.env" "${HOME_DIR}/.config/amethystora/backup-password" \
        "${HOME_DIR}/.local/state/amethystora/backup-last-success" "${HOME_DIR}/.local/share/applications/vmlab-opener.desktop" \
        "${HOME_DIR}/escape" "${OPENED}"
    sed -i '/vmlab-opener/d' "${HOME_DIR}/.config/mimeapps.list" 2>/dev/null
    chmod -R u+w "${HOME_DIR}/.cache/amethystora-restore" 2>/dev/null
    rm -rf "${HOME_DIR}/.cache/amethystora-restore"
    podman rm -f vmlab-rest >/dev/null 2>&1
    rm -rf "${KEEP}" /run/vmlab-backups
}
trap cleanup EXIT
since="$(date '+%F %T')"

# --- What it starts from -------------------------------------------------------------------------------

# Nothing of a backup that a suite before this one set up
as_tester systemctl --user disable --now amethystora-backup.timer >/dev/null 2>&1
rm -f "${HOME_DIR}/.config/amethystora/backup.env" "${HOME_DIR}/.config/amethystora/backup-password" \
    "${HOME_DIR}/.local/state/amethystora/backup-last-success"

# The hourly snapshots, through Security's own switch
out="$(in_terminal 120 'Turn ransomware protection on' 'y' -- ame security ransomware on 2>&1)"
if systemctl is-enabled --quiet amethystora-home-snapshot.timer && [[ -n "$(newest_snapshot)" ]]; then
    ok "ame security ransomware on turns the hourly snapshots on and takes the first"
else
    not_ok "the hourly snapshots did not come on" "$(tail -n 15 <<<"${out}")"
    finish
fi

# The backup server: rest-server in append-only mode, an account for the test account, and its repository
# private to it, as the plan asks of a server
mkdir -p "${KEEP}/rest"
podman rm -f vmlab-rest >/dev/null 2>&1
if ! out="$(podman pull -q "${REST_IMAGE}" 2>&1)"; then
    not_ok "rest-server could not be pulled" "${out}"
    finish
fi
install -m 0640 /dev/null "${KEEP}/rest/.htpasswd"
podman run --rm -v "${KEEP}/rest:/data:Z" --entrypoint create_user "${REST_IMAGE}" "${TEST_USER}" "${REST_PASSWORD}" >/dev/null 2>&1
podman run -d --name vmlab-rest -p 127.0.0.1:8000:8000 -v "${KEEP}/rest:/data:Z" \
    -e OPTIONS="--append-only --private-repos" "${REST_IMAGE}" >/dev/null
check "an append-only rest-server answers" wait_for 60 curl -s -o /dev/null http://127.0.0.1:8000/

# What there is to go back to: files as they were at the first snapshot (S1), the first backup (B1, with
# report.txt changed once more) and the second snapshot (S2)
in_home 'mkdir -p Documents/notes .ssh && printf "version 1\n" >Documents/report.txt && printf "a 1\n" >Documents/notes/a.txt &&
    printf "b 1\n" >Documents/notes/b.txt && printf "gone\n" >Documents/gone.txt && printf "known 1\n" >.ssh/vmlab-known &&
    head -c 33554432 /dev/urandom >Documents/big.bin'
S1="$(snapshot)"
check "a snapshot holds the test files" test -f "${SNAPSHOTS}/${S1}/${TEST_USER}/Documents/report.txt"

# Setting the backup up, as Backups' "Set up a backup…" does: ame backup setup in a terminal
out="$(in_terminal 180 'Repository' "${REPO}"$'\r' 'Repository password' "${REPO_PASSWORD}"$'\r' \
    'What to back up' $'\r' -- "${TTY_TESTER[@]}" ame backup setup 2>&1)"
if as_tester systemctl --user is-enabled --quiet amethystora-backup.timer; then
    ok "ame backup setup sets up a backup to an append-only rest-server, the daily run on"
else
    not_ok "ame backup setup did not finish" "$(tail -n 20 <<<"${out}")"
    finish
fi
grep -q "Nothing there yet, creating the repository" <<<"${out}" &&
    echo "# ame backup setup: rest-server --append-only let restic init create the repository"

in_home 'printf "version 1b\n" >Documents/report.txt'
began=${SECONDS}
if as_tester systemctl --user start --wait amethystora-backup.service; then
    ok "the daily backup's run succeeds"
    echo "# the first backup of the test account's home: $((SECONDS - began)) s"
else
    not_ok "the backup failed" "$(journalctl _SYSTEMD_USER_UNIT=amethystora-backup.service -n 20 --no-pager -o cat)"
    finish
fi
B1="$(backup_ids | head -n 1)"
check "the run wrote when it last succeeded" test -s "${HOME_DIR}/.local/state/amethystora/backup-last-success"
if journalctl _UID="${uid}" --no-pager -o cat | grep -qF "${REST_PASSWORD}"; then
    not_ok "the rest-server's password is in the journal"
else
    ok "the journal holds no password of the repository's address"
fi

in_home 'printf "version 2\n" >Documents/report.txt && rm Documents/gone.txt && printf "a 2\n" >Documents/notes/a.txt &&
    printf "c 2\n" >Documents/notes/c.txt && printf "known 2\n" >.ssh/vmlab-known'
S2="$(snapshot)"

# --- The helper ------------------------------------------------------------------------------------------

st="$(restore status)"
json_check "status: the snapshots are possible, on and cover the account" "${st}" \
    '.snapshots.possible and .snapshots.on and .snapshots.covers and .snapshots.count >= 3'
json_check "status: the backup is set up, its address shown without the password, last good just now" "${st}" \
    ".backup.set_up and .backup.repository == \"${SHOWN}\" and .backup.daily and (.backup.stale | not)
        and .backup.last_success > (now - 900)"
grep -qF "${REST_PASSWORD}" <<<"${st}" && not_ok "status shows the rest-server's password"

began=${SECONDS}
points="$(restore points)"
echo "# points: 3 or more snapshots and one backup on the append-only rest-server in $((SECONDS - began)) s"
json_check "points: both sources, newest first, the setup's snapshot left out" "${points}" "
    .backup == \"ok\" and (.points | map(.time) | . == (sort | reverse))
    and ([.points[] | select(.source == \"backup\")] | length) == 1
    and ([.points[].id] | index(\"${S1}\") and index(\"${S2}\") and index(\"${B1}\"))"
out="$(as_tester ame backup snapshots 2>&1)"
if grep -qF "${S2}" <<<"${out}" && grep -qF "${B1}" <<<"${out}" && ! grep -qF "${REST_PASSWORD}" <<<"${out}"; then
    ok "ame backup snapshots lists the same points"
else
    not_ok "ame backup snapshots does not list the points" "${out}"
fi
out="$(in_terminal 60 'From which snapshot' $'\x1b' -- "${TTY_TESTER[@]}" ame security ransomware restore 2>&1)"
grep -qF "${S2}" <<<"${out}" && ok "ame security ransomware restore offers the snapshots" ||
    not_ok "ame security ransomware restore does not offer ${S2}" "$(tail -n 15 <<<"${out}")"

# One folder, its own entries only, each with how it is now
STATES='[.entries[] | {(.name): .now}] | add'
for point in "${S1}" "${B1}"; do
    listing="$(restore ls "${point}" Documents)"
    json_check "ls ${point} Documents: one level, and what is gone, changed and the same now" "${listing}" "
        (${STATES}) as \$now | \$now[\"report.txt\"] == \"changed\" and \$now[\"gone.txt\"] == \"missing\"
        and \$now.notes == \"present\" and \$now[\"big.bin\"] == \"same\"
        and all(.entries[]; .name | contains(\"/\") | not) and (any(.entries[]; .name == \"a.txt\") | not)"
done
json_check "ls of the whole home folder in the backup" "$(restore ls "${B1}")" 'any(.entries[]; .name == "Documents" and .type == "dir")'

began=${SECONDS}
versions="$(restore versions Documents/report.txt)"
echo "# versions of one file, from the snapshots and the append-only rest-server: $((SECONDS - began)) s"
json_check "versions: the three that differ, from both sources, newest first" "${versions}" '
    .backup == "ok" and (.versions | length) == 3 and ([.versions[].source] | index("backup") and index("local"))
    and (.versions | map(.time) | . == (sort | reverse)) and .now.type == "file"'

# --- The window: backing up ------------------------------------------------------------------------------

window
check "the window opens on the home folder at the newest point" page \
    'if (state.folder !== "" || state.point !== state.timeline.points[0].id) throw new Error(state.folder + " " + state.point)'
check "its timeline has both, marked by where each is kept" page '
    if (state.timeline.backup !== "ok") throw new Error(state.timeline.backup + " " + state.timeline.detail);
    const local = document.querySelectorAll(".moment.local").length, backup = document.querySelectorAll(".moment.backup").length;
    if (local < 3 || backup !== 1) throw new Error(local + " local, " + backup + " in the backup");'

show_status
check "Back up now starts the backup" page '
    window.vmlabLines = [];
    window.backups.onBackupLine((line) => window.vmlabLines.push(line));
    click(".card .btn", "Back up now");'
if wait_for 600 page 'if (!state.backup || state.backup.running) throw 0'; then
    done_="$(page 'return { ok: state.backup.ok, lines: window.vmlabLines, said: document.body.innerText.includes("Your home folder is in the backup as it is now.") }')"
    json_check "it says the backup succeeded" "${done_}" '.ok and .said'
    json_check "it follows the run in the journal as it goes" "${done_}" 'any(.lines[]; contains("Snapshots in this repository"))'
    json_check "from its first line" "${done_}" 'any(.lines[]; startswith("Backing up "))'
    json_check "what it followed has no password" "${done_}" "all(.lines[]; contains(\"${REST_PASSWORD}\") | not)"
else
    not_ok "the backup started from the window did not end within 10 minutes" "$(page 'return state.backup' 2>&1)"
fi
check "the new backup is on the timeline" wait_for 120 page \
    'if (state.timeline.points.filter((p) => p.source === "backup").length !== 2) throw 0'
B2="$(backup_ids | head -n 1)"

check "Turn off the daily run" page 'click(".card .btn", "Turn off the daily run")'
if wait_for 60 page 'if (state.dailyBusy || state.status.backup.daily) throw 0' &&
    ! as_tester systemctl --user is-enabled --quiet amethystora-backup.timer; then
    ok "the daily run is off, its timer disabled"
else
    not_ok "the daily run did not go off" "$(as_tester systemctl --user is-enabled amethystora-backup.timer 2>&1)"
fi
check "Turn on the daily run" page 'click(".card .btn", "Turn on the daily run")'
if wait_for 60 page 'if (state.dailyBusy || !state.status.backup.daily) throw 0' &&
    as_tester systemctl --user is-enabled --quiet amethystora-backup.timer; then
    ok "the daily run is on again, its timer enabled"
else
    not_ok "the daily run did not come back on"
fi

# --- The helper: putting back ----------------------------------------------------------------------------

# A file Look hands to the desktop is recorded by an app made the default for text, which the account can
# run: not under /var/lib/vmlab-tests, which 50-raid.sh keeps to root
install -d -m 0755 /run/vmlab-backups
cat >/run/vmlab-backups/opener <<EOF
#!/bin/sh
printf '%s\n' "\$1" >>${OPENED}
EOF
chmod 0755 /run/vmlab-backups/opener
in_home "mkdir -p .local/share/applications && printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=vmlab opener' \
    'Exec=/run/vmlab-backups/opener %f' 'MimeType=text/plain;' 'NoDisplay=true' >.local/share/applications/vmlab-opener.desktop &&
    xdg-mime default vmlab-opener.desktop text/plain"

when() { date -d "@$(jq -r --arg id "$1" '.points[] | select(.id == $id) | .time' <<<"${points}")" '+%Y-%m-%d %H.%M'; }
B1_WHEN="$(when "${B1}")"

out="$(restore put-back "${B1}" Documents/report.txt --keep-both)"
json_check "put-back --keep-both from the backup: kept beside" "${out}" '.kept == 1'
check "the backup's version is beside the newer one, its time in its name" \
    grep -qx "version 1b" "${HOME_DIR}/Documents/report (${B1_WHEN}).txt"
check "and the newer one is untouched" grep -qx "version 2" "${HOME_DIR}/Documents/report.txt"

out="$(restore put-back "${B1}" Documents/gone.txt --keep-both)"
json_check "put-back of a file deleted since, from the backup" "${out}" '.added == 1'
check "it is back as it was" grep -qx gone "${HOME_DIR}/Documents/gone.txt"
check "it has the label SELinux gives its folder (user_home_t), not the cache's" \
    sh -c "stat -c %C '${HOME_DIR}/Documents/gone.txt' | grep -q ':user_home_t:' && [ -z \"\$(restorecon -nv '${HOME_DIR}/Documents/gone.txt')\" ]"
rm -f "${HOME_DIR}/.ssh/vmlab-known"
out="$(restore put-back "${B1}" .ssh/vmlab-known --keep-both)"
json_check "put-back into ~/.ssh from the backup" "${out}" '.added == 1'
check "it has the label of ~/.ssh (ssh_home_t)" \
    sh -c "stat -c %C '${HOME_DIR}/.ssh/vmlab-known' | grep -q ':ssh_home_t:' && [ -z \"\$(restorecon -nv '${HOME_DIR}/.ssh/vmlab-known')\" ]"
check "what the backup was brought down into is gone again" \
    sh -c "[ -z \"\$(find '${HOME_DIR}/.cache/amethystora-restore' -maxdepth 1 -name 'run.*' 2>/dev/null)\" ]"

out="$(restore put-back "${S1}" Documents/report.txt --replace)"
json_check "put-back --replace from a snapshot" "${out}" '.replaced == 1'
check "the snapshot's version took the newer one's place" grep -qx "version 1" "${HOME_DIR}/Documents/report.txt"

rm -f "${HOME_DIR}/Documents/notes/b.txt"
out="$(restore put-back "${S1}" Documents/notes --skip)"
json_check "put-back --skip of a folder (cp --update=none)" "${out}" '.skipped == 1'
check "--skip brings back what is missing" grep -qx "b 1" "${HOME_DIR}/Documents/notes/b.txt"
check "--skip leaves what differs as it is" grep -qx "a 2" "${HOME_DIR}/Documents/notes/a.txt"
check "--skip deletes nothing the snapshot lacks" grep -qx "c 2" "${HOME_DIR}/Documents/notes/c.txt"

rm -f "${HOME_DIR}/Documents/big.bin"
out="$(restore put-back "${S1}" Documents/big.bin --keep-both)"
json_check "put-back of a large file from a snapshot" "${out}" '.added == 1'
exclusive="$(btrfs filesystem du -s --raw "${HOME_DIR}/Documents/big.bin" 2>&1 | awk 'NR == 2 { print $2 }')"
if [[ "${exclusive}" == 0 ]] && cmp -s "${HOME_DIR}/Documents/big.bin" "${SNAPSHOTS}/${S1}/${TEST_USER}/Documents/big.bin"; then
    ok "it shares the snapshot's blocks (a reflink: no time, no space)"
else
    not_ok "the file put back does not share the snapshot's blocks" "$(btrfs filesystem du -s --raw "${HOME_DIR}/Documents/big.bin" 2>&1)"
fi

ln -sfn /etc "${HOME_DIR}/escape"
before="$(sha256sum /etc/passwd)"
for path in ../../etc/passwd /etc/passwd -x escape/passwd; do
    json_check "put-back refuses ${path}" "$(restore put-back "${S1}" "${path}" --replace)" '.error == "outside"'
done
check "nothing outside the home was written" sh -c "[ \"\$(sha256sum /etc/passwd)\" = '${before}' ]"

rm -f "${OPENED}"
out="$(as_tester env XDG_CURRENT_DESKTOP=GNOME /usr/libexec/amethystora-restore open "${B1}" Documents/report.txt --json)"
opened="$(jq -r '.opened // empty' <<<"${out}")"
if [[ "${opened}" == "${HOME_DIR}/.cache/amethystora-restore/look/${B1}."*/report.txt ]] && grep -qx "version 1b" "${opened}"; then
    ok "open from the backup: a copy under the cache"
else
    not_ok "open from the backup did not bring the copy down" "${out}"
fi
check "the copy is read-only to the account" sh -c "! runuser -u ${TEST_USER} -- test -w '${opened}'"
check "it is handed to the app that opens text" wait_for 30 grep -qxF "${opened}" "${OPENED}"
out="$(as_tester env XDG_CURRENT_DESKTOP=GNOME /usr/libexec/amethystora-restore open "${S1}" Documents/report.txt --json)"
json_check "open from a snapshot: the snapshot's own file" "${out}" ".opened == \"${SNAPSHOTS}/${S1}/${TEST_USER}/Documents/report.txt\""

# --- The window: putting back ----------------------------------------------------------------------------

in_home 'printf "version 3\n" >Documents/report.txt && printf "a 3\n" >Documents/notes/a.txt'
S2_WHEN="$(when "${S2}")"
show_browse
if go_to "${S2}" && open_folder Documents Documents; then
    ok "the window shows Documents as it was at a snapshot"
    check "it marks what is gone and what changed since" page '
        const tag = (name) => [...document.querySelectorAll(".file-row")].find((r) => r.querySelector(".file-name").textContent === name)?.querySelector(".file-now").textContent;
        if (tag("report.txt") !== "Changed since" || tag("big.bin") !== "Same as now") throw new Error(tag("report.txt") + ", " + tag("big.bin"));'
    select_file report.txt
    check "Put back asks what to do with what is there now" page '
        click(".selection-bar .btn", "Put back");
        await new Promise((r) => setTimeout(r, 500));
        if (!find(".dialog [role=radio][aria-checked=true]", "Keep both")) throw new Error("no question, or not Keep both first");
        click(".dialog .btn.primary");'
    json_check "keep both puts it back beside" "$(banner)" '.tone == "done" and (.text | contains("beside"))'
    check "the snapshot's version is beside, the newer one untouched" sh -c \
        "grep -qx 'version 2' '${HOME_DIR}/Documents/report (${S2_WHEN}).txt' && grep -qx 'version 3' '${HOME_DIR}/Documents/report.txt'"

    select_file report.txt
    check "Versions lists every version that differs" page 'click(".selection-bar .btn", "Versions")'
    if wait_for 300 page 'if (!state.versions || state.versions.result === "reading") throw 0'; then
        check "with a row each, from both sources" page '
            const result = state.versions.result;
            if (result.error || result.backup !== "ok") throw new Error(JSON.stringify(result));
            const rows = document.querySelectorAll(".version-row");
            if (rows.length !== result.versions.length || rows.length < 3) throw new Error(rows.length + " rows");
            click(".link", "Back to the folder");'
    else
        not_ok "the versions were not found within 5 minutes"
    fi
else
    not_ok "the window did not show Documents at ${S2}" "$(page 'return state.listing' 2>&1)"
fi

if go_to "${B2}"; then
    lines="$(wc -l <"${OPENED}" 2>/dev/null || echo 0)"
    select_file report.txt
    check "Look, at a point in the backup" page 'click(".selection-bar .btn", "Look")'
    json_check "says it opened a read-only copy" "$(banner)" '.tone == "done" and (.text | startswith("Opened read-only"))'
    check "and handed the backup's copy to the app" wait_for 30 sh -c \
        "tail -n +$((lines + 1)) '${OPENED}' | grep -q '/.cache/amethystora-restore/look/${B2}\.'"
else
    not_ok "the window did not go to the backup ${B2}"
fi

if go_to "${S1}" && open_folder notes Documents/notes; then
    check "Put the whole folder back asks first" page '
        click(".folder-tools .btn", "Put the whole folder back");
        await new Promise((r) => setTimeout(r, 500));
        if (!has("nothing is deleted")) throw new Error("no warning");
        click(".dialog .btn.primary", "Put the folder back");'
    json_check "puts it back" "$(banner)" '.tone == "done"'
    check "what had the same name is the snapshot's again" grep -qx "a 1" "${HOME_DIR}/Documents/notes/a.txt"
    check "what the snapshot lacked is still there" grep -qx "c 2" "${HOME_DIR}/Documents/notes/c.txt"
else
    not_ok "the window did not show Documents/notes at ${S1}"
fi

# --- The window: opened on a folder ----------------------------------------------------------------------

folders="$(as_tester env XDG_CURRENT_DESKTOP=GNOME gio mime inode/directory 2>&1)"
grep -q '^Default application.*org.gnome.Nautilus.desktop' <<<"${folders}" && ok "Files stays the default for folders" ||
    not_ok "Files is not the default for folders" "${folders}"
grep -q 'amethystora-backups.desktop' <<<"${folders}" && ok "Backups is offered to open a folder (Open With)" ||
    not_ok "Backups is not among the apps that open a folder" "${folders}"
# As Files' Open With does it: the launcher with the folder, which the open window takes over. The window is
# on the home folder first, so that only the launch can take it to the folder.
page 'click(".crumb", "Home")' >/dev/null
wait_for 60 page 'if (state.folder !== "" || !state.listing?.entries) throw 0'
user_bus systemd-run --user --collect --quiet -p KillMode=process -- \
    gio launch /usr/share/applications/amethystora-backups.desktop "${HOME_DIR}/Documents/notes"
check "Open With on a folder shows that folder in the open window" wait_for 60 page \
    'if (state.folder !== "Documents/notes" || !state.listing?.entries) throw 0'
check "and the second start ends, leaving that window" wait_for 30 sh -c \
    "! pgrep -u ${TEST_USER} -f '^${ELECTRON} ${HOME_DIR}/Documents/notes'"
close_window
window "--at=${S1}" "${HOME_DIR}/Documents"
check "amethystora-backups --at=POINT FOLDER opens there" page \
    "if (state.folder !== 'Documents' || state.point !== '${S1}') throw new Error(state.folder + ' at ' + state.point)"

# --- The window: when the backup goes wrong --------------------------------------------------------------

as_tester sh -c 'date -d "8 days ago" +%s >"$HOME/.local/state/amethystora/backup-last-success"'
json_check "a week without a good backup is stale" "$(restore status)" '.backup.stale'
report="$(as_tester /usr/libexec/amethystora-security-status --json 2>/dev/null)"
json_check "the security report warns about it (backup-runs)" "${report}" '.checks[] | select(.id == "backup-runs") | .state == "check"'
reload
show_status
check "the window says so, with the agent offered" page '
    if (!has("No backup has succeeded for 8 days")) throw new Error("not said");
    if (document.getElementById("status-dot").hidden) throw new Error("no dot on Status");
    click(".link", "Ask the agent");'
check "Ask the agent hands it the backup's unit" wait_for 60 pgrep -u "${TEST_USER}" -f 'amethystora-agent diagnose amethystora-backup.service'
pkill -u "${TEST_USER}" -f 'amethystora-agent diagnose' 2>/dev/null
as_tester sh -c 'date +%s >"$HOME/.local/state/amethystora/backup-last-success"'
report="$(as_tester /usr/libexec/amethystora-security-status --json 2>/dev/null)"
json_check "the report's check is good again after a good backup" "${report}" '.checks[] | select(.id == "backup-runs") | .state == "ok"'

# A backup that cannot be read: the wrong key for the repository
as_tester sh -c "printf wrong >\"\$HOME/.config/amethystora/backup-password\""
reload
show_browse
check "with the backup unreadable, the snapshots are still shown and it says why" page '
    if (state.timeline.backup !== "unreachable") throw new Error(state.timeline.backup);
    if (!state.timeline.points.length || !has("The backup could not be read")) throw new Error("not said");'
show_status
page 'click(".card .btn", "Back up now")' >/dev/null
if wait_for 300 page 'if (!state.backup || state.backup.running) throw 0'; then
    check "a backup that fails says so, with what it logged and the agent" page '
        if (state.backup.ok) throw new Error("said it succeeded");
        if (!has("The backup did not succeed") || !find(".log", "wrong password")) throw new Error("no log");
        if (!find(".link", "Ask the agent")) throw new Error("no agent");'
else
    not_ok "the failing backup did not end within 5 minutes"
fi
as_tester sh -c "printf '%s' '${REPO_PASSWORD}' >\"\$HOME/.config/amethystora/backup-password\""

check "Change… opens ame backup setup in a terminal" page 'click(".card .btn", "Change")'
check "where the recipe runs" wait_for 60 pgrep -u "${TEST_USER}" -f '00-entry.just backup setup'
pkill -u "${TEST_USER}" -f 'amethystora-in-terminal ame backup|ame backup setup' 2>/dev/null
check "Security settings opens Security" page 'click("#open-security")'
check "which starts" wait_for 90 pgrep -u "${TEST_USER}" -f '^/usr/lib/amethystora-security/amethystora-security'
pkill -TERM -o -u "${TEST_USER}" -f '^/usr/lib/amethystora-security/amethystora-security' 2>/dev/null

close_window
dumps="$(crashes_since "${since}" COREDUMP_UID="${uid}")"
if [[ -z "${dumps}" ]]; then ok "nothing crashed"; else not_ok "something crashed" "${dumps}"; fi
finish
