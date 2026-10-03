---
name: amethystora
description: How to inspect and change an Amethystora desktop (Fedora atomic, GNOME). Use whenever the user asks to change, fix or explain something about this machine - themes, wallpaper, keybindings, GNOME settings, the terminal, installing software, updates, security settings or ame (ujust) commands - and before editing anything under ~/.config/amethystora, dconf or /etc.
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
- `ame --list --list-submodules` lists every system command with a one-line description, in groups;
  `ame <group> <command>` runs one (`ame security status`). Prefer one over doing the same by hand: it
  knows the image. `ujust` is the same command, and also takes the names commands had before groups.
- `amethystora-theme --help`, `amethystora-menu --help` and `amethystora-agent --help` print usage.
- Keybindings: `/usr/share/amethystora/keybindings.md`.

## Installing software

In this order of preference:

1. GUI apps: Flatpak, `flatpak install --user flathub <app-id>`.
2. CLI tools: Homebrew, `brew install <formula>`.
3. Anything needing another distribution's packages: `amethystora-pkg` (`amepkg`), which makes
   distrobox containers from templates and installs with their own package managers.
4. `rpm-ostree install` layers a package onto the image. Last resort: it slows every update and
   needs a reboot. Ask the user first.

Never add dnf repositories or run `dnf install` on the host; there is no writable package database.

### Containers (amepkg)

- `amepkg containers list --json` is the state: names, templates, managers, `exported_apps`,
  `packages`, `last_upgrade` (Unix seconds). `amepkg templates list --json` and `managers list --json`
  list the templates (debian, ubuntu, fedora, arch, alpine, opensuse-tumbleweed, opensuse-leap) and
  managers (apt, dnf, pacman, zypper, apk). Run it as the user, never with sudo.
- Make one: `amepkg containers new --template <t> --name <n> --no-prompt`. Install:
  `amepkg <n> install <pkg>` puts the package's launchers in the app grid; `remove` takes them out.
  `amepkg <n> run <cmd>` runs one command inside; `enter` is a shell for the user, not for you.
- A `.deb`, `.rpm` or `.pkg.tar.zst`: `amepkg install <file>`. It scans the file, shows where it comes
  from and offers Flathub or the container's repositories first; let the user answer those questions.
- Only containers it made are listed (labels `amethystora.pkg.*`, real names `pkg-<name>`); leave the
  user's other distrobox containers alone. `containers rm` and `reset` delete what is installed:
  ask first.
- The AUR is off unless the user ran `ame apps aur`; never turn it on for them. AUR packages
  need a terminal to review their PKGBUILD, so leave those installs to the user.
- Containers are not a sandbox: they share the home folder, display and session bus. Prefer Flatpak
  for apps with windows. They upgrade daily (`amethystora-pkg-upgrade.timer`, user); `amepkg
  upgrade-all` does it now.
- Definitions the user made live in `~/.local/share/amethystora/pkg`, state in
  `~/.local/state/amethystora/pkg`: change them with `amepkg templates|managers new|update`, not by hand.

Notes and to-do lists are the Notes app (`amethystora-notes`), which the image ships in place of Joplin
and Planify; suggest it before installing either. Its data in `~/.local/share/amethystora-notes` is
usually encrypted with the user's passphrase, which a passkey on a security key can stand in for:
never read, move or delete anything there, and never ask for the passphrase or the key's PIN.

## Themes

`amethystora-theme list | set "<name>" | toggle | current | reload | bg next|list|set`.

A theme is a directory of small files (see `/usr/lib/amethystora/theme/lib.sh` for the full list):
`colors.toml` (the palette), `accent.theme`, `light.mode`, `pair.theme`, `gtk.theme`,
`icons.theme`, `vscode.theme`, `backgrounds.list` (wallpapers elsewhere on the system, the first
one is what the theme opens on), `backgrounds/`.

- Tweak a shipped theme: create `~/.config/amethystora/themes/<name>/` holding only the files that
  differ; they are copied over the shipped ones. A directory that exists only there is a new theme.
- Change how a config is rendered: copy the template from `/usr/share/amethystora/themed/` to
  `~/.config/amethystora/themed/` and edit the copy.
- Run something on every theme switch: an executable in `~/.config/amethystora/hooks/theme-set.d/`.
- Extra wallpapers: `~/.config/amethystora/backgrounds/<theme>/`, cycled with `Super+Ctrl+Space`
  after the theme's own pictures (`amethystora-theme bg list` shows the order). The
  `wallpaper*.svg` rendered from the palette are only used by a theme with no pictures at all.
  To make a theme open on a different picture, lay a `backgrounds.list` over it in
  `~/.config/amethystora/themes/<theme>/` with that picture first.
- A light theme sets Blur my Shell's `dash-to-dock/style-dash-to-dock` to 2 (a dark tint on the
  dock) and a dark theme resets it, on every switch, so a change made to that key by hand only
  lasts until the next switch.
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

- `ame update` updates the image, Flatpaks and Homebrew. `rpm-ostree status` shows the booted and
  pending deployment; `rpm-ostree rollback` returns to the previous one after a reboot. A machine
  started from an older deployment than its default (the boot menu's second entry) keeps it with
  `sudo bootc rollback`; the next update brings the newest back.
- The System Updates app (`amethystora-update`) does the same by starting `uupd-manual.service`, the
  updater of the automatic updates (`uupd.service`, on `uupd.timer`), and follows its log with
  `journalctl -u uupd-manual.service`. It needs no password and does not reboot. After it, it starts
  the user's `amethystora-pkg-upgrade.service` for the containers (`journalctl --user -u
  amethystora-pkg-upgrade`); uupd's own distrobox module stays off in `/etc/uupd/config.json`.
- Switching images or streams: `ame system rebase [IMAGE] [STREAM]` (signed images only). On a new
  machine, `ame restore-setup` remakes the user's setup from the manifest their restic backup
  stores (`/usr/libexec/amethystora-setup-manifest` writes it); it is interactive, so leave it to them.
- The agents are not part of the image and `ame update` leaves them alone. They live in the
  user's home (`~/.local/bin/claude`, `~/.opencode/bin/opencode`) and update themselves:
  `claude update`, `opencode upgrade`.
- Logs: `journalctl -b -p warning`, `journalctl --user -b`, `coredumpctl list`. The Logs app
  (`amethystora-logs`, in place of GNOME Logs) reads the same journal for the user, one app or service
  at a time; `amethystora-logs crashes` opens it on the crashes.
- `ame security status` summarises the security settings. The Security app (`amethystora-security`)
  shows the same report and scans for viruses. What a scan finds is only reported unless
  `ON_DETECTION` in `/etc/amethystora/security.conf` says quarantine or delete; `ame security settings`
  changes it and real-time watching (`REALTIME`). Never edit that file to loosen it without asking.
- `ame security events` shows what the security watcher (`amethystora-security-watch`, every 15
  minutes) noticed in the audit log and journal. Changes you make under `/etc` show up there, and a
  file in `/etc` that differs from the image's copy in `/usr/etc` shows as **Image settings**. So
  does a program you put in `~/.local/bin` or `~/bin` with a system command's name, and a launcher
  in `~/.local/share/applications` that no container export made: name yours differently.
- Network protection is Suricata inline on this machine's own traffic (`amethystora-ips.service`,
  helper `/usr/libexec/amethystora-ips`), set by `NETWORK` in `/etc/amethystora/security.conf`: `off`
  (default), `watch` or `block`, changed with `ame security settings network`. It fails open. With
  `block`, a site or app that suddenly cannot connect may be one it blocked: `ame security connections`
  lists them, or read `/var/lib/amethystora/security/network.json` (readable by wheel).
  `ame security connections allow <rule>` leaves one rule out; rules allowed are in
  `/etc/amethystora/ips-allowed`.
- To find out why something crashed or stopped working, follow the `amethystora-diagnose` skill.

## Ask the user first

- Anything with `sudo`, `pkexec` or `rpm-ostree`.
- Anything that loosens security: polkit rules, sudoers, the firewall (`firewall-cmd`), SELinux,
  sshd, kernel arguments, Secure Boot, USBGuard, network protection (turning it off, or allowing a
  rule). The image hardens these on purpose; explain the trade-off instead of working around it.
- `gsettings reset-recursively`, deleting user files, or reverting the user's own customisations.

Turning these instructions off is `ame agent toggle`.
