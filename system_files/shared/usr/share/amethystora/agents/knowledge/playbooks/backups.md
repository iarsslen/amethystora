# A backup fails or is stale, or a file has to come back

## Symptom

Backups or the security report (check `backup-runs`) says the daily backup failed, or that none has
succeeded for a week; or the user wants a file or folder back as it was earlier.

## Look

- `state backups` (hourly snapshots; the backup: daily run, last good, STALE, FAILED), `state health`
  (finding `backups`).
- `logs` user_unit `amethystora-backup.service`; for the snapshots, unit `amethystora-home-snapshot.service`.
- `/usr/libexec/amethystora-restore status --json`
- `systemctl --user list-timers amethystora-backup.timer`
- `journalctl --user -u amethystora-backup.service -n 50 --no-pager`
- `/usr/libexec/amethystora-restore points --json`, `versions PATH --json`, `ls POINT [PATH] --json`: read
  only, with restic's `--no-lock`.

## Causes on Amethystora

Stale means the daily run is on and nothing has succeeded for 7 days, counted from the setup when nothing
ever has. With the daily run off, nothing is stale.

1. **The repository is out of reach**: a USB drive unplugged between backups, as `ame backup setup`
   advises, a server down, no network. Tell: "unable to open repository", "connection refused" or "no such
   file or directory" in the journal; `points` says the backup could not be read.
2. **The daily run is off, or nothing is set up.** Without `~/.config/amethystora/backup.env` the unit
   does not run at all. Tell: `state backups`.
3. **The password no longer fits.** Tell: "wrong password or no key found"; the file
   `~/.config/amethystora/backup-password` is missing or changed.
4. **The repository is locked** by a `check` or `prune` run from elsewhere. Tell: "repository is already
   locked".
5. **No space**, for restic's cache or on the repository's disk. Tell: "no space left on device", `df -h`.
6. **The machine was rarely on.** The timer catches up after a sleep (`Persistent=true`) but waits up to two
   hours at random. Tell: no failure in the journal, the next run in `list-timers`.
7. **Hourly snapshots are off, or impossible.** They are a security switch, on from the first start of an
   ISO install, as the owner left them otherwise; impossible when `/var/home` is not a btrfs subvolume of
   its own. Tell: `state backups`.

## Fix

### A failed or stale backup

- Bring the repository back (plug the drive in, reach the server), then `ame backup now`: it runs
  `amethystora-backup.service` and shows its journal.
- The daily run off: `ame backup on`.
- Not set up, a new repository or a new password: the user runs `ame backup setup` in a terminal. Never
  ask for the repository's password.
- Locked: wait for the other run to end, then `ame backup now`.
- Space: `run` `ame system clean` (in a terminal), then `ame backup now`.

### Hourly snapshots

Only when the user asks: `ame security ransomware on` (root). It costs disk space: a deleted file's space
comes back up to two weeks later.

### A file to bring back

1. Find the point: `/usr/libexec/amethystora-restore versions PATH --json` (each point where it differs),
   or `points --json`.
2. Show it, changing nothing: `/usr/libexec/amethystora-restore ls POINT DIR --json`, `open POINT PATH`
   (a read-only copy in its app), or the Backups app: `amethystora-backups DIR`.
3. Ask the user, naming the version and where it goes, then
   `/usr/libexec/amethystora-restore put-back POINT PATH --keep-both`. A missing file comes back; a changed
   one comes back beside the current one, as `name (YYYY-MM-DD HH.MM).ext`. `--replace` only when the user
   asked for it; `--skip` leaves changed files alone.

### Never

Nothing on this machine deletes from the backup or a snapshot, and neither does the agent: no
`restic forget`, `prune`, `key` or `rewrite`, no `btrfs subvolume delete`. Old snapshots are thinned from
elsewhere, with credentials this machine does not hold.

## Verify

- `/usr/libexec/amethystora-doctor --only backups` (exits 0 when it finds nothing).
- `state backups`: a new last good backup, no STALE or FAILED.
- A file put back: `ls -l` on it, and on the copy beside it.

## Undo

- `ame backup off` stops the daily run and keeps the settings and the repository; `ame backup on` undoes
  that.
- Hourly snapshots: the user runs `ame security ransomware off`. It offers to delete the snapshots: that
  answer is the user's alone.
- A put-back with `--keep-both` only added files: the user deletes the copy they do not want (ask first).
  After `--replace`, the version replaced is in the latest hourly snapshot or backup: put it back from that
  point the same way.
