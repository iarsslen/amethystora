# The machine is stuck while booting, or ends in an emergency shell

## Symptom
The start hangs on the boot logo, on a black screen, or on "A start job is running for
/dev/disk/by-uuid/…"; or it ends in "You are in emergency mode" ("the root account is locked", Enter
continues); or a sealed machine stops with "Amethystora was not started: its system files on this disk
cannot be verified".

## Look
Once the machine is up again (the previous boot menu entry, or a later start):
- `state overview`: deployments, "started from an older deployment", layered packages, sealed or not.
- `state disks`: pools, and whether the system's own disks are all there.
- `state units` for failed units; `logs` with boot `-1`, priority `err`.
- `journalctl --list-boots`, `journalctl -b -1 -p err` (or `ame system logs-last-boot`),
  `systemd-analyze critical-chain`, `cat /proc/cmdline`, `/usr/libexec/amethystora-raid status --json`.

A start that never reached the system's disk left nothing in the journal: ask what the screen said.

## Causes on Amethystora
1. **The console size query.** systemd asks the console for its size and waits for an answer that never
   comes while Plymouth holds it: a random hang on the logo. The image's argument
   `systemd.tty.term.console=dumb` (`/usr/lib/bootc/kargs.d/12-amethystora-console.toml`) prevents it,
   but a machine with layered packages updates through rpm-ostree, which ignores kargs.d. Tell: the
   argument missing from `/proc/cmdline`.
2. **A system over several disks with one dead.** It waits for the missing disk with no end. Tell: "A
   start job is running for /dev/disk/by-uuid/…", and `state disks` naming the system's pool.
3. **An update broke the start.** Tell: the previous boot menu entry starts.
4. **NVIDIA:** a black screen on an NVIDIA image is the driver: read `playbook/nvidia`.
5. **The disk passphrase, not a hang.** After a firmware update, a Secure Boot change or a key enrolled
   with `ame security secure-boot`, the TPM no longer hands over the key set up by
   `ame security disk-unlock`, and the passphrase prompt waits. Tell: the passphrase still works.
6. **A line in `/etc/fstab` for a disk that is gone,** one the user added without `nofail` (pools' lines,
   marked `x-amethystora-raid`, have it): emergency mode after 90 seconds. Tell: the failed
   `.mount` unit named above the emergency message.
7. **Plymouth itself.** Tell: Esc on the splash shows messages that are still moving.
8. **Sealed: the system's files cannot be verified.** It refuses to start rather than run changed files.

## Fix
1. `sudo rpm-ostree kargs --append-if-missing=systemd.tty.term.console=dumb` (root) (restart). A sealed
   image has it in its signed kernel image already.
2. Restart and choose **Start with a disk missing** in the boot menu (shown 5 seconds on such a system).
   Then the user runs `ame system raid replace system` in a terminal and types `ERASE` themselves
   (root). A pool of other disks never holds up the start (`ame system raid mount NAME` opens one).
   Never edit `/boot/grub2/custom.cfg`.
3. Start the previous entry (Esc or Shift as the machine starts shows a hidden menu). To stay on it:
   **Keep this version** in Updates, or `sudo bootc rollback` (root). Then `ame report`.
4. See `playbook/nvidia`.
5. Type the passphrase. Then the user runs `ame security disk-unlock on-pin` again (root), which asks
   for the passphrase and a new PIN.
6. Copy `/etc/fstab` to `/etc/fstab.bak.$(date +%s)`, then add `nofail` to that one line's options
   (root). Never edit `/etc/crypttab` or the `x-amethystora-raid` lines.
7. At the boot menu press `e` and add `plymouth.enable=0` for that one start, to see where it stops (not
   on a sealed image; asks the boot password if `ame security boot-password` is on).
8. Start the live ISO (amethystora.iso), copy the files off, and install again. A sealed image's kernel
   arguments cannot change; its previous entry and `sudo bootc rollback` work as on any other.

## Verify
- `cat /proc/cmdline` has `systemd.tty.term.console=dumb`; `journalctl -b -p err` is quiet.
- `state overview` shows the booted deployment as the default; `state disks` no disk missing.
- `state health` no longer points to this playbook.

## Undo
- 1: `sudo rpm-ostree kargs --delete-if-present=systemd.tty.term.console=dumb` (root) (restart).
- 3: the next update brings the newest version back; `sudo bootc rollback` again switches back sooner
  (root) (restart).
- 5: `ame security disk-unlock off` takes the TPM key out (root).
- 6: copy the `.bak` file back (root).
- 7: a one-time edit, nothing to undo.
