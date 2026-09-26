# Updates

Updates are automatic and quiet. The system, your Flatpak apps and your Homebrew tools are checked in
the background and downloaded while you work. The new system is staged next to the running one and
takes over at the next restart, all at once. Nothing is ever half-updated, so an update cannot leave
the machine in a state that does not start.

> **The one habit to keep:** shut down or restart when you are done for the day. That is when a
> staged update is applied.

## Updating now

```bash
ujust update
```

Updates the system, Flatpaks and Homebrew in one go; a new system still takes over at the next
restart. It is also **Check for updates** under **System** in the Amethystora menu.

| Command | Does |
| --- | --- |
| `ujust update` | Update everything now |
| `ujust toggle-updates` | Turn automatic updates off, or on again |
| `ujust changelogs` | What changed in the packages since the image you are running |
| `rpm-ostree status` | The running system, the staged update and the one to roll back to |
| `fwupdmgr get-updates` | Firmware updates for this machine, from its maker |

The release notes for every stable build are on
[GitHub](https://github.com/iarsslen/amethystora/releases).

## Rolling back

The previous system is always kept. If an update brings a problem:

- **At the boot menu,** pick the second entry, which is the system before the update. Nothing is
  changed, and the next restart goes back to the newest one.
- **To stay on the previous system,** make it the default and restart:

```bash
sudo rpm-ostree rollback
systemctl reboot
```

Your files and settings are the same in both. Then [report the problem](troubleshooting.md#reporting-a-problem),
and follow the stream again when a fixed image is out.

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

Replace `amethystora` with `amethystora-dx` for [developer mode](developer.md), and `latest` with the
stream you want.

If you have [layered packages](software.md#layering-the-last-resort), switch with `rpm-ostree` instead,
because `bootc switch` builds the new system from the image alone and would drop them:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/iarsslen/amethystora:latest
```

## Holding on to one build

Every build also has a tag of its own, such as `stable-44.20260922`, from the version in the release
notes. Switching to it holds the machine on that build, which is useful while you wait for a fix.
A machine on a single build receives no updates; `ujust security-status` reminds you, and prints the
command that goes back to following the stream.

## Signed updates

An update is only accepted if it carries Amethystora's signature, checked against the key in
`/etc/pki/containers/amethystora.pub`. A tampered image, or one from anyone else, is refused instead
of installed. A service checks at every boot that signature checking is still on, and turns it back
on if a switch turned it off.
