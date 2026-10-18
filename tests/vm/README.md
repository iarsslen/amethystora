# The VM lab

A virtual machine for trying an Amethystora image as it boots: UEFI with Secure Boot and Microsoft's keys, a
TPM 2.0, GNOME on a 1280×800 screen. It builds the image from the last commit, boots it and runs the test
suites in it (`run.sh`), and an agent drives it by hand through an MCP server (`server.mjs`).

Nothing of the lab is in the image. Commands reach the guest through `agent.py`, which QEMU hands to systemd as
a credential at boot (SMBIOS type 11) and which runs from `/run` until the VM shuts down. It answers on a
virtio-serial port no other machine can reach. The screen, keys and mouse go through QEMU's own monitor. The
security watcher may say that a unit it does not know ran: that is the lab's helper.

## Setting it up

The lab is a privileged Fedora container, `amevm`, with QEMU, KVM, OVMF, swtpm, and what `just build`
needs. It needs Docker or Podman on Linux, or Docker Desktop on Windows (nested virtualization in WSL 2 gives
it `/dev/kvm`, once `setup.sh` has loaded the module).

```bash
bash tests/vm/setup.sh
```

`setup.sh` builds the lab's image and starts the container again. Disks and VMs stay in the volume
`amevm-vm`, pulled and built images in `amevm-storage`; VMs that were running are stopped. Run it again after
changing the `Containerfile`; a test run brings the other files here up to date itself.

To give the MCP server to Claude Code, for this checkout only:

```bash
claude mcp add amethystora-vm --scope local -- docker exec -i amevm node /opt/amethystora-vm/server.mjs
```

The tools appear in the next session.

## Test runs

```bash
bash tests/vm/run.sh                # build HEAD, install it onto a disk, boot it, run the suites
bash tests/vm/run.sh build|disk|test   # one stage, from what the last run left
bash tests/vm/run.sh test --keep    # and leave the VM ("test") running afterwards
```

`run.sh` sends the last commit into the lab as a git bundle (whatever the checkout's line endings),
and `run.mjs` builds it with `just build amethystora latest main` (a throwaway module signing key, as every
build without the release key), installs it with `make-disk.sh`, and runs each suite in `suites/` as root
in the VM, in order. With `VMLAB_NAME=NAME`, a run has its own source tree, image tag
(`localhost/amethystora-run:NAME`), disks and VMs, and its files go to `/vm/runs/last-NAME`, so that two
sessions can share the lab; the build itself tags `localhost/amethystora:latest` first, so two builds at once
are agreed on beforehand. The disk's firmware has the image's own certificates in shim's MOK list, as on a
machine whose owner enrolled them. Everything a run did is in the lab's `/vm/runs/last`: one log per stage
and per suite, a screenshot after each suite, the guest's journal, `results.json` and `summary.md`, which
`run.sh` prints last. It exits 0 only when everything passed. The `run-tests` skill in `.claude/skills`
is how an agent runs it and fixes what fails.

### Suites

A suite is `suites/NN-name.sh`, run as root in the VM beside `lib.sh`, which it sources. It says one line per
check, as TAP does (`ok - ...`, `not ok - ...` with indented lines saying why, `skip - ...`), uses `check`,
`wait_for`, `as_user` and `in_session` from `lib.sh`, and ends with `finish`. Exit status 100
(`reboot_and_continue`) restarts the VM and runs the suite again with `SUITE_PHASE` one higher, six phases at
most; a restart empties `/run`, so what a suite keeps between phases goes in `/var/lib/vmlab-tests`. A line
starting with `#` is a measurement, which the report repeats. A phase that calls `next_boot JSON` first gets a
power cycle instead, the machine started again with a spare disk unplugged (`{"absent": [2]}`), with sectors
that fail every read (`{"faulty": {"3": [sector, ...]}}`, through QEMU's blkdebug), or with the disk's
passphrase typed at its prompt rather than handed over (`{"type_passphrase": true}`; the next phase finds how
many times it was asked in `VMLAB_PROMPTS`), without its own disk (`{"system_absent": true}`), or with a
credential left out (`{"credentials": {"cryptsetup.passphrase": null}}`, for the TPM alone). A later plain
restart keeps the machine as that start left it. Exit status 101 (`continue_phase`) runs the next phase in the
same boot, for what outlasts a phase's 30 minutes.

A suite whose second line is `# vmlab-vm: installer` runs on a second machine, installed as the installer
lays a disk out: an ESP, an ext4 `/boot`, and btrfs (subvolumes `root` and `home`) on LUKS2, with the fstab and
crypttab lines Anaconda writes and the serial console in its kernel arguments (`make-disk.sh --installer`). Its
passphrase (`VMLAB_PASSPHRASE`) and a TPM PIN for suites to enrol (`VMLAB_TPM_PIN`) reach systemd-cryptsetup as
credentials, so nothing has to be typed at boot. It has four spare disks, two of 8 GiB and two of 48 GiB,
larger than its own 40 GiB.

What asks a person something (gum, a typed `ERASE`, a check for a terminal) runs through `in_terminal`, which
gives the command a terminal of its own (`term.py`), waits for each question and types its answer. The test VM
has five blank SATA disks besides its own, serials `SPARE-1` to `SPARE-5` (four of 8 GiB, then 10 GiB), new for
every run, and a sixth of 24 GiB, more than the system's data, which stays unplugged until a suite asks for it
with `next_boot '{"absent": []}'`. Its home folders are not a btrfs subvolume of their own, as the installer
would make them: a suite that needs one (the hourly snapshots do) calls `make_home_subvolume` unless `home_subvolume` says it is one
already, then restarts.

An app's window is used as a person would use it, through the accessibility tree every GTK window has:
`atspi.py`, run as the account on its session's bus, finds, clicks and types into what the window shows and
reads what it says (`70-backups.sh` shows how).

| Suite | What it checks |
| --- | --- |
| `00-boot.sh` | every unit started, Secure Boot and lockdown on, a TPM, the image's own module loads, nothing crashed |
| `05-first-run.sh` | GNOME's first-run setup starts on a machine with no account, and no per-account setup runs in it |
| `10-account.sh` | the test account `tester` signs in on Wayland, and its first login's setup runs |
| `20-apps.sh` | each Amethystora app opens and stays open |
| `25-every-app.sh` | every other app in the app grid opens as the grid starts it and stays open, none crashes or is refused what its manifest asks for (Mission Center's gatherer runs), and neither opening them all nor a restart and a login makes the security watcher say anything |
| `30-detection.sh` | the thorough profile, after a restart, finds a secret read, the decoy read and a program run from Downloads; Falco's memory |
| `40-setup.sh` | `ame setup` save, diff and apply against real GNOME settings, Flathub and Homebrew; the setup kept with a backup and read back by `ame restore-setup`; `ame system trust-image`, a switch to an unsigned image refused, `amethystora-image-check` |
| `50-raid.sh` | pools of disks on the spare disks: parity, two copies encrypted and combined made, restarted, scrubbed (a scrub cut short is resumed), a disk taken away while mounted and one missing at boot, opened degraded, replaced, added to and forgotten; the recovery key, Control's words, no TPM unlock for a pool; a disk pulled out of an encrypted pool, one with bad sectors (the notification's Open Control clicked) replaced while it reads, a copy damaged behind btrfs's back repaired by a scrub, a real suspend during a scrub, a disk unplugged at boot and plugged back, its copies put back |
| `55-raid-system.sh` | on the installer-layout machine: the system mirrored onto a new disk (2b), the passphrase asked once, the restart from the new disk finishing it, the TPM on both disks and not a pool's, an update on both halves of `/boot` and both ESPs, each disk dead in turn (Start with a disk missing), one back with its copies put back, the other replaced |
| `60-vanilla.sh` | `amepkg`: an Alpine container with a launcher exported and taken back, the daily upgrade, Apx files imported, a `.deb` from a file scanned and installed; the watcher's fake `sudo` and stray launcher; the NVIDIA offer on stand-in hardware; "You're on the previous version" and `bootc rollback` |
| `70-backups.sh` | the home folders made a btrfs subvolume (a restart), the hourly snapshots and a backup to an append-only rest-server; Backups' helper and window on both: points, folders, versions, putting back (labels, reflinks, refusals), Look, the whole folder, Open With, a stale and a failed backup |
| `75-deja-dup.sh` | Déjà Dup from Flathub: where its schedule is kept, what `flatpak preinstall` uninstalls when its list stops naming an app, and the one notice at the next login |
| `85-raid-mirror.sh` | the system spread over two disks as the installer leaves it (SPARE-6), mirrored (2a), started with the second disk unplugged from Start with a disk missing, the disk back and its copies put back, then on one disk again |

A new feature gets its check here with it, and a bug a run found gets the check that would have caught it.

## Using it by hand

1. `disk_build` installs an image onto a disk with `bootc install to-disk` (btrfs, as the installer ISO
   makes it), about 10 minutes. `disk_list` says when it is ready.
2. `vm_start` starts a VM on an overlay of that disk, with spare disks (`spares_gb`), some of them `absent` or
   `faulty`, and `credentials` for systemd; `vm_wait` returns once the boot is over.
3. `vm_exec` runs a command as root, as an account, or in that account's graphical session (`session`).
   `vm_write` and `vm_read` move files.
4. `vm_screenshot`, `vm_keys` and `vm_mouse` see and use the desktop; `vm_serial` is the serial console.
5. `vm_snapshot` keeps checkpoints of a stopped VM; `vm_stop` and `vm_delete` end it.

A new disk has no account and starts GNOME's first-run setup; `suites/10-account.sh` shows how to sign a test
account in. The VM has 4 GB of memory and 4 processors unless `vm_start` says otherwise. Under nested
virtualization GNOME draws in software and is slow: the screen can show a click a few seconds late.
