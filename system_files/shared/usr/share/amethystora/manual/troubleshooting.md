# Troubleshooting

Most problems on an image-based system have the same three answers: find out what happened, roll
back if an update caused it, and report it so the next image fixes it.

## Let the agent look first

**Diagnose a problem** in the Amethystora menu (`Super+Alt+Space`), or from a terminal:

```bash
amethystora-agent diagnose "the second monitor stays black after suspend"
```

It reads the logs and crash reports, changes nothing, and comes back with the cause and a fix to
consider. [The AI agent](ai-agent.md#diagnose-a-problem) has more.

## Read the logs yourself

| Command | Shows |
| --- | --- |
| `journalctl -b -p warning` | Warnings and errors since this boot |
| `journalctl -b -1 -p warning` | The same for the previous boot, after a crash or a freeze |
| `journalctl --user -b` | Your own session: the desktop, your apps |
| `systemctl --failed` | Services that failed to start |
| `coredumpctl list` | Programs that crashed |
| `ujust logs-this-boot` | Everything from this boot |
| `ujust check-local-overrides` | The files in `/etc` you, or something you ran, have changed |

## An update broke something

Pick the previous system at the boot menu to confirm it was the update, then stay on it with
`sudo rpm-ostree rollback` until a fixed image is out. [Updates](updates.md#rolling-back).

## Common problems

### A package I layered is gone

It was layered with `rpm-ostree install`, and the machine was then switched with `bootc switch`,
which builds the new system from the image alone. Install it again, and switch images or streams with
`rpm-ostree rebase` from now on ([Installing software](software.md#layering-the-last-resort)).

### An app cannot see a folder, a device, or will not open at all

Flatpak apps only reach what they are allowed to, and on Amethystora that excludes X11 and input
devices. Open **Flatseal**, pick the app, and grant what it needs: a folder under **Filesystem**, or
**X11 windowing system** for an app that does not speak Wayland.

### An extension misbehaves, or the desktop looks wrong

Turn the extension off in **Extension Manager**, then log out and back in. If the desktop still
misbehaves, reset GNOME's settings to the image's defaults and reapply your theme:

```bash
dconf reset -f /org/gnome/
amethystora-theme reload
```

That resets every GNOME setting of this account, including the dock, your custom hotkeys and your
extension choices, so keep it for when nothing else helped.

### `Super+Ctrl+Space` changes nothing

It moves to the next wallpaper of the current theme, and every theme ships one. Add some of your own
([Themes](themes.md#wallpapers)). The theme picker is `Super+Ctrl+Shift+Space`.

### The account is locked after wrong passwords

Ten wrong passwords lock the account for ten minutes. Wait, or unlock it from another administrator
account with `sudo faillock --user <name> --reset`.

### A DisplayLink dock shows nothing

With Secure Boot on, its driver loads only once Amethystora's key is enrolled:
`ujust enroll-secure-boot-key`, then restart ([Hardware](hardware.md#secure-boot)).

### Switching keyboard layouts

`Super+Space` is search here, so the next keyboard layout is on `Super+Shift+Space`. Add layouts in
**Settings → Keyboard**.

### The disk is filling up

```bash
ujust clean-system
```

Removes unused containers, images and Flatpak runtimes. `flatpak uninstall --unused` and
`podman system prune` do parts of the same by hand.

## Reporting a problem

Report bugs on [GitHub](https://github.com/iarsslen/amethystora/issues), and ask questions in the
[discussions](https://github.com/iarsslen/amethystora/discussions). `ujust report` gathers the
diagnostics for you, shows you everything before anything is sent, and opens a pre-filled issue.
Otherwise, include:

- the output of `rpm-ostree status`, which names the exact image,
- what you did, what you expected, and what happened instead,
- the relevant lines from the logs above,
- whether the previous image had the same problem.
