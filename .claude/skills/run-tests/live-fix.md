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
5. **Rerun only what failed.** Run that suite, or that step, against the VM, and read its log and screenshot:
   the issue is fixed when it is gone from both, not when the count is.
6. **Repeat** until it passes there, then **rerun it once more** to be sure it is stable, and run the other
   suites of the current work the same change touches. Carry the change into the checkout and commit it (one
   commit per cause).
7. **Reset** the VM to the run's clean disk before validating the next, unrelated fix, if the last one
   changed state the next would see.
8. **One final build** with every live fix. On it, the **full suite only if the changes are risky**
   (packages, the build, boot, security, PAM, the kernel, the image's units, or a shared library many suites
   use), else a final test of the current work's suites. While iterating, never run every suite.

## What cannot be fixed live

The kernel, the initramfs, a package, a change to `20-tests.sh` or another build-time script. Check such a fix
in a container of the image (`ghcr.io/iarsslen/amethystora:stable` or the run's own image) and leave it to the
final run.

## Exact commands

`tests/vm/live.sh` does the loop (it copies `tests/vm/live.mjs` into the lab and runs it there, beside the lab's own
`lab.mjs`; it never touches a run's `/build/src`). Everything is per VM: `VMLAB_LIVE=NAME` (default `live`), with its
files in the lab's `/vm/live/NAME/` (`runs/SUITE.log` and `.png`). Docker on PATH and `MSYS_NO_PATHCONV=1` as in
[SKILL.md](SKILL.md). Times measured on round 1's image (r1), 16 processors and 14 GB in the lab.

**A disk to keep.** A run's `make-disk.sh` replaces `/vm/disks/test.qcow2` with `mv`, which leaves an overlay on it
pointing at a new base. Keep the run's disk under a name of its own first, a hard link (no space, the inode stays):

```bash
docker exec amevm sh -c 'cd /vm/disks && ln test.qcow2 r1.qcow2 && ln test.vars.json r1.vars.json && cp test.digest r1.digest'
docker exec amevm podman tag localhost/amethystora-run:test localhost/amethystora-live:r1   # for live.sh delta; a run prunes untagged images
```

**Start, sign in, keep the state** (once per disk):

```bash
export VMLAB_LIVE=live1
bash tests/vm/live.sh start r1 --fresh   # 70-120 s: overlay, boot, `bootc usr-overlay`
bash tests/vm/live.sh ready              # 10-account.sh (50 s), flatpak-preinstall waited for (585 s after a first
                                         # boot), powered off from inside and kept as the stopped VM live1-ready
bash tests/vm/live.sh reset              # live1 deleted and started fresh `from` live1-ready (vm_start's from, as
                                         # run.sh --parallel): booted, session up, /usr unlocked, pushes forgotten
bash tests/vm/live.sh save               # the running VM kept whole, memory too (QEMU migration into a file)
bash tests/vm/live.sh restore            # back to it, running and signed in, without a boot
```

`ready` waits for flatpak-preinstall because a state kept half way installs the Flatpaks again at every start, and
the account's shell then starts so late that GDM puts its greeter in front and GNOME locks the session. It powers
off from inside: after vm_stop's power button the next boot came up the same way.

**One fix round:**

```bash
bash tests/vm/live.sh affected [REV]     # 1.5-3 s: the suites whose "# vmlab-paths:" a change since REV touches
bash tests/vm/live.sh push-diff [REV]    # every changed system_files/ and suite file (REV default HEAD)
bash tests/vm/live.sh push FILE...       # or named files: 21 s for one extension file (most of it the relogin)
bash tests/vm/live.sh suites 11-dock 12  # each suite in turn; prints its counts, every not ok, the log and png paths
bash tests/vm/live.sh round [REV]        # push-diff, then the affected suites
```

`push` puts the files in with LF endings and the checkout's modes (git's, else Git Bash's `-x`), labels them for
SELinux, and reloads what reads them: extension schemas compiled per extension with the image's overrides (as
`build-gnome-extensions.sh`; the image's own extensions put back in zz0's `enabled-extensions`, which the source file
lacks), the system schemas, `dconf update`, icon caches, `systemctl daemon-reload` (restart the unit yourself),
`amethystora-theme reload` for themed templates, and a new session for anything the shell reads. `/etc/...` goes to
`/etc` and `/usr/etc`. 328 files, everything main changed since round 1, took 51 s. A restart throws `/usr` away;
`live.sh` unlocks again after one and puts back every file pushed since the last reset (`push.list`).

**Look inside:** `live.sh exec 'CMD'` (root), `live.sh exec --session 'CMD'` (the test account's session),
`live.sh shot FILE.png`, `live.sh relogin`; `stop`, `delete`.

**What a push cannot reach** (the build turns files into others: emoji data, the shell's gresource, translations, the
agent's index, the apps): `live.sh delta REV` builds an image `FROM` the VM's own image with the working tree's
system_files and only the build steps they feed since REV (`tests/vm/delta.sh`), pushes it to the lab's registry
and switches the VM to it with `bootc switch` and a soft reboot when it allows one. The apps need their build:
`DELTA_APPS=<an apps stage image>`, or `live.sh app` (a release build of the apps in `amethystora-rust`).

**Rules learnt:**
- **No VM beside a lab build.** A build and one 4 GB VM filled Docker's 13 GB and wedged it (2026-10-29, again).
  Beside nothing else, two VMs; beside a run's test stage, one.
- A suite asking `next_boot` (a power cycle with disks or credentials) or `usb_next` needs `run.sh test --suites NN`;
  `live.sh suite` does plain restarts (exit 100) and `continue_phase` (101).
- The guest's agent answers one client at a time: never leave a long `exec` running while something else needs the VM.
- Never edit `live.sh` while it runs (bash reads a script as it goes).
- A run's own VM (`test`, `test-screens` after `run.sh test --keep`) can be pushed into and tested, never
  started, reset or deleted from `live.sh`.
