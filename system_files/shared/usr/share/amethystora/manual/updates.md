# Updates

Updates are automatic and quiet. The system, your Flatpak apps and your Homebrew tools are checked in
the background and downloaded while you work. The new system is staged next to the running one and
takes over at the next restart, all at once. Nothing is ever half-updated, so an update cannot leave
the machine in a state that does not start.

> **The one habit to keep:** shut down or restart when you are done for the day. That is when a
> staged update is applied.

## Updating now

Open **System Updates** from the app grid (or **Check for updates** under **System** in the
Amethystora menu, or `amethystora-update`) and press **Update now**. It updates the system, the Flatpak
apps of the machine and of every account signed in, and your Homebrew tools in one go and shows each of
them as it happens, without asking for a password, and without the checks for the battery, a busy
machine and memory that hold the automatic updates back. It is the same
update the automatic ones run, so if one is already under way the window follows it rather than
starting another. You can close the window at any time; the update carries on.

A new system still takes over at the next restart. Once one is ready, System Updates says so and
offers the restart. It also shows the version you are running, the one waiting for the restart and
the one kept for [rolling back](#rolling-back), and turns automatic updates off or on again, which
asks for an administrator's password. **Release notes** at the top opens them on GitHub.

If you have [containers](software.md#keeping-them-up-to-date) from `amepkg`, **Update now** upgrades
them straight after the rest, under **Containers**. One that does not upgrade says so there, with
`journalctl --user -u amethystora-pkg-upgrade` for what it said, and the system's update still counts
as done.

An update that does not finish says which part stopped, and the rest is still up to date. **Try again**
starts it once more; an automatic one also tries again by itself a minute later. When a new system is
ready all the same, **Restart now** is still offered, and with the [AI agent](ai-agent.md) on, **Ask the
agent why** has it look into it. **What the updater said** shows the updater's messages to
administrators, with the `journalctl` command for all of them.

In a terminal, the same in one go:

```bash
ame update
```

| Command | Does |
| --- | --- |
| `ame update` | Update everything now |
| `ame update restart` | Restart to finish the update, in seconds when it can be ([restarting in seconds](#restarting-in-seconds)) |
| `amepkg upgrade-all` | Upgrade the containers of other distributions now |
| `ame system auto-updates on` | Turn automatic updates on, or `off`; without either it asks |
| `ame changelog` | The release notes of the build you are running, from GitHub (on a stream other than `stable`, the newest release's) |
| `rpm-ostree status` | The running system, the staged update and the one to roll back to (`sudo bootc status` on a [sealed](#sealed-images) machine) |
| `fwupdmgr get-updates` | Firmware updates for this machine, from its maker |

The release notes for every stable build are on
[GitHub](https://github.com/iarsslen/amethystora/releases).

## Restarting in seconds

Most updates change what runs on top of the kernel, not the kernel itself. When the one waiting for the restart
keeps the kernel, its initramfs, its settings and the SELinux policy as they are, **Restart now** in System
Updates finishes it with a *soft reboot*: your apps close, the system starts again from the new version, and
the login screen is back in a few seconds, without the firmware, the boot menu or the disk's passphrase. System
Updates says when an update can be finished that way, and asks before it closes your apps. In a terminal:

```bash
ame update restart
```

The computer itself still restarts for an update with a new kernel, one that brings another version of a
driver in use, one a firmware update is waiting behind, and on a [sealed image](#sealed-images):
`ame update restart` then says why. **Restart** in the system menu always restarts the computer. Either way
the whole update takes over at once, and the machine starts from it from then on. An app that asks not to end
the session, for a document not yet saved, still gets its say: the restart is then left to GNOME's own
dialog, which names it. The disk stays unlocked through a soft reboot, as the kernel keeps running: to have it
locked again, shut down.

## Firmware

The firmware of the machine and of its devices (the UEFI firmware, docks, SSDs, keyboards, the
fingerprint reader) is updated apart from the system, because a firmware update can need the machine
plugged in and a restart. Every day, fwupd looks for new firmware on LVFS, where makers publish it, and
the **Firmware** section of **Updates** lists each device that has some, from which version to which. A
notification says so once for each new release, and opens **Updates** when clicked. A firmware update
its maker marks as important for security is marked **Important** there. The [security report](security.md#see-where-you-stand)'s
**Firmware updates** check names them too, since many firmware updates fix security holes.
**Update firmware…** installs it in a terminal, where fwupd says what it is about to do and asks before
it restarts the machine. **Check now** asks LVFS again straight away. In a terminal:

```bash
fwupdmgr get-updates      # what there is
fwupdmgr update           # install it
fwupdmgr security         # how well the firmware protects this machine
```

Firmware for the UEFI firmware itself is written at the next restart, by the firmware: leave the
machine plugged in until it has started again. The security report shows fwupd's rating of the
firmware's protections, from HSI:0 to HSI:5; how high a machine can get is mostly up to its maker.

Two things in it ask for something to be done:

- **Revoked boot programs:** LVFS has a newer list of the boot programs Secure Boot must refuse (the
  UEFI dbx) than the firmware holds. `fwupdmgr update` installs it, and refuses while a boot program on
  this machine is one the list refuses.
- **Platform key:** the machine's maker shipped a test key whose private half is published (PKfail),
  so anyone can sign what Secure Boot starts. Only the maker can replace it, with a firmware update.

## Rolling back

The previous system is always kept. If an update brings a problem:

- **At the boot menu,** pick the second entry, which is the system before the update. Nothing is
  changed, and the next restart goes back to the newest one. A notification at login says you are on
  the previous version, and clicking it opens System Updates, which offers to **Keep this version**,
  which makes it the one the machine starts and asks for your password, or to **Restart into the
  latest**.
- **To stay on the previous system** from a terminal, make it the default and restart:

```bash
sudo bootc rollback
systemctl reboot
```

Your files and settings are the same in both. The next update brings the newest version back,
automatic or not, so to stay where you are until a fix is out, turn automatic updates off in System
Updates, or [hold on to the build](#holding-on-to-one-build) you are on. Then
[report the problem](troubleshooting.md#reporting-a-problem), and follow the stream again when a fixed
image is out.

## Streams

| Tag | What you get |
| --- | --- |
| `stable` | Built every week, with the kernel held back to Fedora CoreOS's, which lags a little behind Fedora's so that kernel regressions are caught first. For everyone. |
| `stable-daily` | The same, rebuilt whenever Amethystora changes rather than weekly |
| `latest` | The newest Fedora and kernel, rebuilt whenever Amethystora changes |
| `beta` | What comes next. Expect rough edges. |

## Switching streams and images

To move to another stream or image, switch to it and restart:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/iarsslen/amethystora:latest
```

Replace `amethystora` with `amethystora-dx` for [developer mode](developer.md), add `-nvidia-open` or
`-nvidia-lts` for NVIDIA's driver ([which one](hardware.md#graphics); with Secure Boot on, enroll the keys
first), and replace `latest` with the stream you want. A [sealed](#sealed-images) machine switches only
between the sealed images.
[Control](control.md)'s **System** page lists the images and streams: choosing one opens `ame system
rebase` in a terminal with it chosen, which takes signed images only and asks before it switches. In a
terminal, `ame system rebase amethystora-dx latest` starts with that image and stream chosen, and still
asks. It offers `stable`, `stable-daily` and `latest`; `beta` only `bootc switch` reaches. It keeps
layered packages, and it refuses an NVIDIA image while Secure Boot is on and the image's keys are not
enrolled.

If you have [layered packages](software.md#layering-the-last-resort), switch with `rpm-ostree` instead,
because `bootc switch` builds the new system from the image alone and would drop them:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/iarsslen/amethystora:latest
```

## Holding on to one build

Every build also has a tag of its own, such as `stable-44.20260922`, from the version in the release
notes. Switching to it holds the machine on that build, which is useful while you wait for a fix.
A machine on a single build receives no updates of the system, while apps and command line tools
still update; System Updates and `ame security status` remind you, and the second prints the command
that goes back to following the stream.

## Signed updates

An update is only accepted if it carries Amethystora's signature, checked against the key in
`/etc/pki/containers/amethystora.pub`. A tampered image, or one from anyone else, is refused instead
of installed. A service checks at every boot that signature checking is still on, and turns it back
on if a switch turned it off.

## Sealed images

On a [sealed image](installing.md#sealed-images) the signature is not the last check. The kernel, its
settings and the digest of every file of the system are one file, a unified kernel image, signed with
Amethystora's Secure Boot key. The firmware starts shim, shim starts the boot menu, systemd-boot, and
systemd-boot starts that kernel only if its signature holds. The system is then mounted only if its
files match the digest, and each file is checked again whenever it is read. A file changed on the
disk, by a program running as root or by someone who took the disk out, reads as an error instead of
running. A disk changed so that its files cannot be checked at all does not start: a message says so,
and the [live ISO](installing.md#try-it) can still read your files. `/etc` and `/var` are your
machine's own, and are not covered.

What is different on a sealed machine:

- **Updates and rolling back work as on any other,** from System Updates, or with `sudo bootc upgrade`
  and `sudo bootc rollback`. There is no `rpm-ostree`, so nothing can be layered.
- **The kernel's settings are fixed.** They are inside the signed kernel image, so the boot menu cannot
  edit them, and nothing on the machine can. If it does not start, start the
  [live ISO](installing.md#try-it): it can unlock and read the disk.
- **It follows `stable-sealed`,** and switches only between the sealed images: `ame system rebase`
  offers no others.
- **Sealed and regular do not mix.** A regular installation keeps its system in ostree and a sealed one
  in composefs, and bootc cannot move a machine from one to the other yet. Going either way means
  installing again, after a [backup](security.md#backups). That may change once bootc declares the
  sealed layout stable.
- **The boot loader is placed once,** by the installer. Updates bring a new kernel image each time, but
  not a new systemd-boot or shim.
