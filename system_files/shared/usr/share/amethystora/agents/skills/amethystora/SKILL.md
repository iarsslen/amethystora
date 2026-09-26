---
name: amethystora
description: How to inspect and change an Amethystora desktop (Fedora atomic, GNOME). Use whenever the user asks to change, fix or explain something about this machine - themes, wallpaper, keybindings, GNOME settings, the terminal, installing software, updates, security settings or ujust recipes - and before editing anything under ~/.config/amethystora, dconf or /etc.
---

# Amethystora

Amethystora is an image-based Fedora desktop with GNOME, built as a bootc container. The whole OS
is replaced at once on update; the user's changes live in `$HOME`, `/etc` and `/var`.

## Where changes go

| Path | Rule |
| --- | --- |
| `/usr` | Read-only, part of the image. Read it to learn the defaults, never try to edit it. |
| `/usr/share/amethystora/` | The image's themes, templates, hooks and this skill. Read-only. |
| `~/.config/amethystora/` | The user's layer over the above. Edit here. |
| `/etc` | Writable and kept across updates (three-way merged). Needs sudo; prefer a user-level change. |
| dconf / `gsettings` | GNOME settings, per user. The image's defaults are in `/etc/dconf/db/distro.d/`. |

Before you edit a file that already exists, copy it to `<file>.bak.$(date +%s)`. Say what you changed
and how to undo it.

## Finding commands

- The user manual is Markdown in `/usr/share/amethystora/manual` (start at `pages.json`): how the
  desktop, themes, software, updates and security work, written for the user. Read the page on a
  topic before answering about it, and point the user to it with `amethystora-manual <page>`.
- `ujust --list` lists every system recipe with a one-line description; `ujust <recipe>` runs one.
  Prefer a recipe over doing the same by hand: it knows the image.
- `amethystora-theme --help`, `amethystora-menu --help` and `amethystora-agent --help` print usage.
- Keybindings: `/usr/share/amethystora/keybindings.md`.

## Installing software

In this order of preference:

1. GUI apps: Flatpak, `flatpak install --user flathub <app-id>`.
2. CLI tools: Homebrew, `brew install <formula>`.
3. Anything needing a full Fedora userland: a distrobox or toolbox container.
4. `rpm-ostree install` layers a package onto the image. Last resort: it slows every update and
   needs a reboot. Ask the user first.

Never add dnf repositories or run `dnf install` on the host; there is no writable package database.

## Themes

`amethystora-theme list | set "<name>" | toggle | current | reload | bg next|list|set`.

A theme is a directory of small files (see `/usr/lib/amethystora/theme/lib.sh` for the full list):
`colors.toml` (the palette), `accent.theme`, `light.mode`, `pair.theme`, `gtk.theme`,
`icons.theme`, `vscode.theme`, `backgrounds/`.

- Tweak a shipped theme: create `~/.config/amethystora/themes/<name>/` holding only the files that
  differ; they are copied over the shipped ones. A directory that exists only there is a new theme.
- Change how a config is rendered: copy the template from `/usr/share/amethystora/themed/` to
  `~/.config/amethystora/themed/` and edit the copy.
- Run something on every theme switch: an executable in `~/.config/amethystora/hooks/theme-set.d/`.
- Extra wallpapers: `~/.config/amethystora/backgrounds/<theme>/`, cycled with `Super+Ctrl+Space`.
- After a change, run `amethystora-theme set "$(amethystora-theme current)"` and check for errors.

Never edit `~/.config/amethystora/current/`: it is regenerated on every switch.

## GNOME, keybindings, terminal

- Read before writing: `gsettings get <schema> <key>`, `dconf dump /org/gnome/...`. Change with
  `gsettings set`, then read it back. `gsettings reset` undoes it.
- Custom keybindings live under `/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/`;
  the image uses `custom20` and up. Check `keybindings.md` for a conflict before binding a key.
- Extensions: `gnome-extensions list --enabled`, and `gnome-extensions prefs <uuid>`.
- The terminal is Ptyxis. `amethystora-theme` sets its palette on every theme switch.

## Updates and diagnosis

- `ujust update` updates the image, Flatpaks and Homebrew. `rpm-ostree status` shows the booted and
  pending deployment; `rpm-ostree rollback` returns to the previous one after a reboot.
- The agents are not part of the image and `ujust update` leaves them alone. They live in the
  user's home (`~/.local/bin/claude`, `~/.opencode/bin/opencode`) and update themselves:
  `claude update`, `opencode upgrade`.
- Logs: `journalctl -b -p warning`, `journalctl --user -b`, `coredumpctl list`.
- `ujust security-status` summarises the security settings.
- To find out why something crashed or stopped working, follow the `amethystora-diagnose` skill.

## Ask the user first

- Anything with `sudo`, `pkexec` or `rpm-ostree`.
- Anything that loosens security: polkit rules, sudoers, the firewall (`firewall-cmd`), SELinux,
  sshd, kernel arguments, Secure Boot, USBGuard. The image hardens these on purpose; explain the
  trade-off instead of working around it.
- `gsettings reset-recursively`, deleting user files, or reverting the user's own customisations.

Turning these instructions off is `ujust toggle-agentic`.
