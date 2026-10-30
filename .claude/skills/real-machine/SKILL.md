---
name: real-machine
description: Test and fix Amethystora live on the real machine this checkout runs on (not the VM lab). Use when Claude Code runs on an installed Amethystora computer and the user asks to test the OS, try a feature on the hardware, or fix something live.
---

# Testing and fixing on a real machine

This checkout is on a computer that runs Amethystora itself. The maintainer's PC runs the VM lab
(`run-tests`); this machine is for what the lab cannot show: the GPU and real displays (HiDPI, two screens,
refresh rates), touch and pens, Wi-Fi, Bluetooth, suspend and the lid, the battery, the fingerprint reader,
security keys, a real phone for the phone link, sound devices, the TPM and firmware.

`AGENTS.md` at the top of the checkout holds the project's rules: read it first (Claude Code reads
`CLAUDE.md`, which this repository does not have).

## Before anything

- `cat /usr/share/amethystora/image-info.json` and `git log -1`: say which image and commit the machine runs
  and which the checkout is at. A fix is only tested here if the machine's image has what the fix builds on.
- `bootc status`: a sealed image (`/usr/share/amethystora/sealed`) cannot be changed live; stop and say so.
- The person's data is real. Never erase or partition a disk (`ame system raid create`, `mirror`), never set up
  or touch the duress feature, never run `ame system reset-settings` or Start over, never lower a security
  setting to make a test pass, and ask before anything that restarts the machine or logs the person out.

## Validating every feature: the checklist

`tests/real/checklist/*.md` lists every feature of the OS, one line each, with how to reach it and what a person
should see: `10-desktop.md` (the shell), `20-apps.md` (the apps), `30-security.md`, `40-system.md` (commands,
software and the hardware). The maintainer's rule: **every item is validated, one by one, none skipped because
it looks fine.**

- Work on the branch `real/checklist` (`git switch real/checklist` if it exists on `origin`, else create it).
  Take the items in order, file by file. For each one: do what `How:` says, look at the screen (a screenshot through the
  portal, `org.freedesktop.portal.Screenshot` with `interactive` false, whose file comes in the request's
  `Response` signal and which asks the person once to allow it; or ask the person to press `Print`, which
  saves in `~/Pictures/Screenshots`; then read the PNG), and compare it with
  `Expect:` and with what the person would call right: misplaced, clipped, overlapping, unreadable in a
  theme, wrong in a style, slow, flickering or untranslated counts as a bug even when the line does not say so.
- Mark the line where it stands, replacing `[ ]`:
  `[x] … → PASS`, `[x] … → FIXED <sha>: <what was wrong>`, `[!] … → FAIL: <what is wrong, why not fixed
  here>` (a kernel, package or build fix, or a design choice for the maintainer), or `[-] … → N/A: <why>`
  (no such hardware). Never `PASS` an item you did not see work.
- A bug found: fix it with the live loop below, check the item again, then check the items next to it that the
  same file touches. Commit the fix (one commit per cause) and the checklist lines it settles.
- Commit the checklist every few items (`test(real): checklist <ids>`), and push the branch, so that nothing is
  lost and the maintainer's PC can follow it.
- Flags: `changes setting: put back with …` is put back right after the check; `logout` and `reboot` items
  are gathered and done together with the person; `risky` items run only after the person says yes to that
  item; `never` items are only looked at, never configured. An item whose `Expect:` turns out wrong (the
  feature works differently by design) is corrected in the checklist, with the source that says so.
- A feature found that has no line gets one, in its file, in the same format.

## The live loop

1. **Writable for this boot only:** `sudo bootc usr-overlay`. `/usr` takes changes until the next restart,
   which throws them away: the machine always comes back to its image.
2. **Put the fix in:** a file of `system_files/shared/PATH` (and `system_files/dx/PATH` on dx) is `/PATH` in
   the machine: `sudo install -m MODE system_files/shared/usr/... /usr/...`, then `sudo restorecon -F` on it.
   `/etc` is the machine's own and survives a restart: put back what you change there before you finish
   (copy the original aside first).
3. **Reload what reads it:**
   - a `/usr/libexec` helper or an `ame` recipe: nothing, the next call reads it;
   - a systemd unit: `sudo systemctl daemon-reload` (`systemctl --user daemon-reload` for a user unit), then
     restart the unit;
   - a GNOME Shell extension file: log out and back in (ask the person first);
   - a gschema: `sudo glib-compile-schemas /usr/share/glib-2.0/schemas` (an extension's own `schemas/` too);
   - an Amethystora app (`apps/`): build it in a toolbox, which the image has:
     `toolbox create amebuild && toolbox run -c amebuild sudo dnf -y install rust cargo gcc gtk4-devel libadwaita-devel`,
     then `toolbox run -c amebuild cargo build --release --locked -p amethystora-apps --manifest-path apps/Cargo.toml`
     (the binary is `apps/target/release/amethystora-apps`), and `sudo install -m 0755` it over
     `/usr/lib/amethystora-apps/amethystora-apps` and each `/usr/lib/amethystora-<app>/amethystora-<app>` that
     `build_files/base/13-apps.sh` links. The phone link, the agent's tools and the clipboard's seal are
     packages of their own (`-p amethystora-connect` and so on, as `build_files/shared/build-apps.sh` builds them).
4. **Check it as the person would,** on the screen, and with what the suite for that area checks
   (`tests/vm/suites/NN-*.sh` say what to look for; do not run them here, they expect the lab's helper).
   Then once more, to be sure it holds.
5. **What cannot be fixed live:** the kernel, the initramfs, kernel arguments, packages, firmware and build
   scripts. Write down what you found and the fix, commit it, and leave it to the lab's build.

## Committing

- Commit on a branch of its own, never on `main`: `git switch -c real/<topic>`, one commit per cause,
  conventional commits, the footer `Assisted-by: <model> via Claude Code` and no Co-Authored-By line.
- `git push origin real/<topic>` and tell the person the branch. The maintainer's PC takes it through the
  lab (`run-tests`), and only a lab-validated commit reaches `main` (`queue-latest`).
- Write down in the commit body what the hardware was (`lspci -nn`, `lsusb`, the model) and what was seen.
- A bug that only real hardware shows still gets the check that would have caught it where one can be
  written (`20-tests.sh` or a suite), or a line in the commit body saying why none can.
