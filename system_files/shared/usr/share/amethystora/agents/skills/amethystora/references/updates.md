# Updates, logs and earlier versions of files

## Updates

- `ame update` updates the image, Flatpaks and Homebrew. `rpm-ostree status` shows the booted and
  pending deployment; `rpm-ostree rollback` returns to the previous one after a reboot. A machine
  started from an older deployment than its default (the boot menu's second entry) keeps it with
  `sudo bootc rollback`; the next update brings the newest back.
- A sealed image (`/usr/share/amethystora/sealed` exists) has no rpm-ostree: `sudo bootc status` shows
  its deployments and `sudo bootc rollback` returns to the previous one. Its kernel arguments are
  inside its signed kernel image and cannot be changed on the machine; never try.
  `/usr/libexec/amethystora-deployments` prints `rpm-ostree status --json`'s shape on both kinds.
- The System Updates app (`amethystora-update`) does the same by starting `uupd-manual.service`, the
  updater of the automatic updates (`uupd.service`, on `uupd.timer`), and follows its log with
  `journalctl -u uupd-manual.service`. It needs no password and does not reboot. After it, it starts
  the user's `amethystora-pkg-upgrade.service` for the containers (`journalctl --user -u
  amethystora-pkg-upgrade`); uupd's own distrobox module stays off in `/etc/uupd/config.json`.
- `ame update restart` finishes a staged update with a soft reboot (only the system's programs start
  again, in seconds) when `/usr/libexec/amethystora-soft-reboot status` says `"quick":true`, and says why
  not otherwise (a new kernel, initramfs, kernel arguments or SELinux policy, another version of a loaded
  driver, firmware waiting). It ends the user's session like any restart: only when they ask for one.
- Firmware is fwupd's, outside the image: `fwupdmgr get-updates` lists it (the Updates app shows the
  same), `fwupdmgr update` installs it and can need a restart, so leave installing to the user;
  `fwupdmgr security` explains the HSI rating the security report shows.
- Switching images or streams: `ame system rebase [IMAGE] [STREAM]` (signed images only).

## Logs

- `journalctl -b -p warning`, `journalctl --user -b`, `coredumpctl list`. The Logs app
  (`amethystora-logs`, in place of GNOME Logs) reads the same journal for the user, one app or service
  at a time; `amethystora-logs crashes` opens it on the crashes.
- To find out why something crashed or stopped working, follow the `amethystora-diagnose` skill. The
  Updates, Security and Logs apps start you that way with **Ask the agent**, handing you a unit, a PID
  or the report's own words for a check.

## Earlier versions of the user's files

`/usr/libexec/amethystora-restore` lists them from the hourly snapshots (`/var/home/.snapshots`) and the
restic backup (`~/.config/amethystora/backup.env`) as one timeline: `status`, `points`, `ls POINT
[PATH]` and `versions PATH`, each with `--json`, read and change nothing. The Backups app
(`amethystora-backups [FOLDER]`) shows the same, and `put-back` brings files back into the home without
deleting anything: say which version comes back and where first, and use `--replace` only when they
asked for it (`--keep-both` puts the old file beside the current one). Nothing on the machine deletes
from the backup or a snapshot: never run `restic forget`, `prune` or `key remove` against it, or `btrfs
subvolume delete` on a snapshot.
