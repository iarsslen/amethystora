# Fixing live in a kept VM

The maintainer's rule (2026-10-29): build and test round trips are the expensive part, so a failure is fixed in
a running VM of the image the run built and validated there, then committed, and only one final full run
checks the commits together. The exact commands are below; they are written and proven against the lab by a
tester before they are relied on.

## The loop

1. **Keep a VM.** End the run with the VM left running (`run.sh test --keep`, or start one from the last run's
   disk under a name of its own). Never reuse another session's VM.
2. **Make the system writable for this boot.** The image is read-only; an unlocked deployment gives a writable
   overlay on `/usr` until the next restart, so a fix tried live never survives into the next boot.
3. **Put the fix in.** Copy the changed file from the checkout into the guest with LF line endings (the
   checkout is CRLF on Windows).
4. **Reload what reads it.**
   - A GNOME Shell extension file: log the test account out and back in (on Wayland the shell cannot reload
     an extension in place).
   - A `/usr/libexec` helper or an `ame` recipe: nothing, the next call reads it.
   - A systemd unit: `systemctl daemon-reload`, then restart the unit.
   - An Amethystora app: rebuild the one program in the `amethystora-rust` container and copy the binary in.
5. **Rerun only what failed.** Run that suite, or that step, against the VM, and read its log and screenshot.
6. **Repeat** until it passes there, then carry the same change into the checkout and commit it (one commit
   per cause).
7. **Reset** the VM to the run's clean disk before validating the next, unrelated fix, if the last one
   changed state the next would see.
8. **One final full run** of the commits when every failure is fixed.

## What cannot be fixed live

The kernel, the initramfs, a package, a change to `20-tests.sh` or another build-time script. Check such a fix
in a container of the image (`ghcr.io/iarsslen/amethystora:stable` or the run's own image) and leave it to the
final run.

## Exact commands

<!-- Filled in and proven by the tester of the run of 2026-10-29: starting the VM, the shell in the guest,
unlocking, copying a file, relogging the test account, running one suite, resetting, and how many VMs the lab
can hold beside nothing else. -->
