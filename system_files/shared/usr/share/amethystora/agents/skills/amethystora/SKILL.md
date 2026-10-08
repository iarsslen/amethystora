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
- `/usr/libexec/amethystora-control-list --json` (or `ame control` for people) is the state of every
  Amethystora setting outside security, read without root: each entry's `state`, its `choices` and the
  `command` that sets each, and `terminal: true` where that command asks questions or needs a
  password, which leaves it to the user. Read it before answering what a setting is set to, and use the
  commands it lists. The window over it is Amethystora Control (`amethystora-control [page]`,
  `Super+Ctrl+Shift+C`); security settings are in `ame security status` instead.
- `amethystora-theme --help`, `amethystora-menu --help` and `amethystora-agent --help` print usage.
- Keybindings: `/usr/share/amethystora/keybindings.md`.

## Installing software

In this order of preference:

1. GUI apps: Flatpak, `flatpak install --user flathub <app-id>`.
2. CLI tools: Homebrew, `brew install <formula>`.
3. Anything needing another distribution's packages: `amethystora-pkg` (`amepkg`), which makes
   distrobox containers from templates and installs with their own package managers.
4. `rpm-ostree install` layers a package onto the image. Last resort: it slows every update and
   needs a reboot. Ask the user first. A sealed image (`/usr/share/amethystora/sealed` exists) has no
   rpm-ostree and takes no layered packages.

Never add dnf repositories or run `dnf install` on the host; there is no writable package database.

Every Flatpak is refused X11, the input devices and the Flatpak service by
`/etc/flatpak/overrides/global` (which Flatpak reads through a link in `/var/lib/flatpak/overrides`). An
app that needs one back gets it per app and per user, `flatpak override --user --socket=x11 <app-id>`,
after you say what it gives the app; never edit the global file. `/usr/libexec/amethystora-app-permissions
--json` (or `ame security apps`) shows what each app can reach and what was granted.

Games, Android apps, drawing tablets and the CPU scheduler each have one command, which explains
itself and asks first: `ame apps gaming` (Steam from Flathub with X11 granted to it alone; `ame apps
gaming launchers` adds Heroic or Lutris), `ame apps android` (Waydroid; `start`, `stop`, `off`), `ame
apps opentabletdriver` (`on`, `off`), and `ame system scheduler` (`kernel`, `lavd`, `bpfland`,
`flash`). Use them rather than installing these by hand, and leave them to the user to run: each asks
questions, and the last three use `sudo`.

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
- The AUR is off unless the user ran `ame apps aur on`; never turn it on for them. AUR packages
  need a terminal to review their PKGBUILD, so leave those installs to the user.
- Containers are not a sandbox: they share the home folder, display and session bus. Prefer Flatpak
  for apps with windows. They upgrade daily (`amethystora-pkg-upgrade.timer`, user); `amepkg
  upgrade-all` does it now.
- Definitions the user made live in `~/.local/share/amethystora/pkg`, state in
  `~/.local/state/amethystora/pkg`: change them with `amepkg templates|managers new|update`, not by hand.

### The setup file (ame setup)

- `ame setup save` writes the user's setup to `~/.config/amethystora/setup.json` (or a file named
  after it): image and stream, Flatpaks, Homebrew, amepkg containers, extensions, theme, and the layout,
  dock apps, keybindings and PaperWM gaps they changed. The manual's `setup.md` documents the format.
- `ame setup diff --json [FILE]` compares the machine with it and changes nothing: read it before
  answering what the machine lacks. `ame setup apply --yes [FILE]` installs and sets what is missing,
  once you have told the user what `diff` lists. `--remove` uninstalls and resets what the file does not name, and asks in a terminal: leave it to the
  user. Switching the image needs a terminal too.
- The file names things only. Never put a remote, a URL, a Brewfile, a command or any other GNOME key
  in it: it is refused, by design, because a shared file must not run anything.
- If the user keeps the file (often in git), offer to run `ame setup save` after you change their apps
  or settings, and show `git diff` rather than committing for them.

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
- The animation that reveals a new theme or wallpaper is the extension
  `amethystora-transitions@iarsslen.github.io`: `ame desktop transition
  <grow|outer|wipe|wave|fade|random|none> [milliseconds]`, which sets
  `org.gnome.shell.extensions.amethystora-transitions` `style` and `duration`. It does nothing while
  GNOME's animations are off.
- `ame desktop background <picture>` shows one of the pictures `amethystora-theme bg list` names.
- After a change, run `amethystora-theme set "$(amethystora-theme current)"` and check for errors.

Never edit `~/.config/amethystora/current/`: it is regenerated on every switch.

## GNOME, keybindings, terminal

- Read before writing: `gsettings get <schema> <key>`, `dconf dump /org/gnome/...`. Change with
  `gsettings set`, then read it back. `gsettings reset` undoes it.
- Custom keybindings live under `/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/`;
  the image uses `custom20` and up. Check `keybindings.md` for a conflict before binding a key.
- Extensions: `gnome-extensions list --enabled`, and `gnome-extensions prefs <uuid>`.
- Windows tile with PaperWM unless the user chose classic, floating windows: `ame desktop layout
  classic` or `tiling`, remembered in `~/.config/amethystora/layout`. Change the layout with that
  command, not by turning PaperWM off yourself, or the next image update turns it back on.
- Something to show in the top bar (a widget, an indicator, a timer, a status, a switch): follow the
  `amethystora-widgets` skill, which makes it a folder in `~/.config/amethystora/widgets`. Never write
  a GNOME Shell extension for it.
- The terminal is Ptyxis. `amethystora-theme` sets its palette on every theme switch.

## Updates and diagnosis

- `ame update` updates the image, Flatpaks and Homebrew. `rpm-ostree status` shows the booted and
  pending deployment; `rpm-ostree rollback` returns to the previous one after a reboot. A machine
  started from an older deployment than its default (the boot menu's second entry) keeps it with
  `sudo bootc rollback`; the next update brings the newest back.
- A sealed image (`/usr/share/amethystora/sealed` exists) has no rpm-ostree: `sudo bootc status` shows
  its deployments and `sudo bootc rollback` returns to the previous one. Its kernel arguments are
  inside its signed kernel image and cannot be changed on the machine; never try.
- The System Updates app (`amethystora-update`) does the same by starting `uupd-manual.service`, the
  updater of the automatic updates (`uupd.service`, on `uupd.timer`), and follows its log with
  `journalctl -u uupd-manual.service`. It needs no password and does not reboot. After it, it starts
  the user's `amethystora-pkg-upgrade.service` for the containers (`journalctl --user -u
  amethystora-pkg-upgrade`); uupd's own distrobox module stays off in `/etc/uupd/config.json`.
- Firmware is fwupd's, outside the image: `fwupdmgr get-updates` lists it (the Updates app shows the
  same), `fwupdmgr update` installs it and can need a restart, so leave installing to the user;
  `fwupdmgr security` explains the HSI rating the security report shows.
- Switching images or streams: `ame system rebase [IMAGE] [STREAM]` (signed images only). On a new
  machine, `ame restore-setup` remakes the user's setup from the manifest their restic backup
  stores (`/usr/libexec/amethystora-setup-manifest` writes it); it is interactive, so leave it to them.
- The agents are not part of the image. `amethystora-agent list` shows which are installed. Most
  live in the user's home (`~/.local/bin`, or `~/.opencode/bin` for Opencode), `ame update` leaves
  them alone and they update themselves: `claude update`, `opencode upgrade`, `codex update`,
  `copilot update`, `cursor-agent update`. Gemini CLI comes from Homebrew, which `ame update`
  upgrades.
- Logs: `journalctl -b -p warning`, `journalctl --user -b`, `coredumpctl list`. The Logs app
  (`amethystora-logs`, in place of GNOME Logs) reads the same journal for the user, one app or service
  at a time; `amethystora-logs crashes` opens it on the crashes.
- Earlier versions of the user's files: `/usr/libexec/amethystora-restore` lists them from the hourly
  snapshots (`/var/home/.snapshots`) and the restic backup (`~/.config/amethystora/backup.env`) as one
  timeline: `status`, `points`, `ls POINT [PATH]` and `versions PATH`, each with `--json`, read and
  change nothing. The Backups app (`amethystora-backups [FOLDER]`) shows the same, and `put-back`
  brings files back into the home without deleting anything. Nothing on the machine deletes from the
  backup or a snapshot: never run `restic forget`, `prune` or `key remove` against it, or `btrfs
  subvolume delete` on a snapshot.
- `ame security status` summarises the security settings. The Security app (`amethystora-security`)
  shows the same report and scans for viruses. What a scan finds is only reported unless
  `ON_DETECTION` in `/etc/amethystora/security.conf` says quarantine or delete; `ame security settings`
  changes it and real-time watching (`REALTIME`). Never edit that file to loosen it without asking.
- Every security feature is a switch, and off costs nothing. `ame security settings` lists the detection
  ones with their values (`/usr/libexec/amethystora-security-config --list`): the watcher and each part
  of it, the virus scanner (`VIRUS_SCAN`, whose daemon holds the signatures in memory), the settings
  audit, the audit log, real-time watching and scanning, notifications. What the image enforces has its
  own commands: `ame security kernel`, `blocked-modules`, `kernel-args`, `firewall`, `failed-logins`,
  `lockout`, `app-sandbox`, `ssh-settings` and `signed-updates` (`/usr/libexec/amethystora-hardening
  status`). `ame security profile off` and `ame security profile default` do all the detection ones. When
  the user asks for a faster machine or for something security blocks, name the one switch that does it
  and what it gives up, and let them run its command: never turn one off for them unasked, and always
  through its command, which the report then shows as turned off rather than as a fault. A warning that
  cannot be fixed on this machine can be accepted with `ame security allow report`.
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
- Fingerprint login is already on in the image's PAM setup: a finger enrolled with `ame security
  fingerprint`, or in Settings, works for login, the lock screen, sudo and polkit. Enrolling needs the
  user's finger, so leave it to them.
- Never run `authselect select` by hand: it drops the features the image turns on (account lockout,
  fingerprint login, security keys) unless each is named again. A domain is joined and left with
  `realm join` and `realm leave`, whose login commands keep them (`/etc/realmd.conf`,
  `/usr/libexec/amethystora-domain-logins`).
- One-time codes for SSH ask for a code from a phone app after the password (`ame security ssh-codes`,
  off by default; `/usr/libexec/amethystora-ssh-codes status`). Setting up codes needs the user's
  phone, so leave `ame security ssh-codes setup` to them, and never turn codes on for an account that
  has neither codes nor an SSH key.
- Encrypted DNS (`ame security dns`, off by default; `/usr/libexec/amethystora-dns status` and `name`)
  sends every lookup to one resolver over DNS-over-TLS, through a drop-in in
  `/etc/systemd/resolved.conf.d` and one in `/etc/NetworkManager/conf.d`; `resolvectl status` shows it.
  A network whose login page will not load may need it paused, which asks for a password:
  `ame security dns pause` (ten minutes). A different address on each network (`ame security mac`,
  off by default; `/usr/libexec/amethystora-mac status`) gives each network its own hardware address,
  and a network that registers devices by address then refuses the machine.
- Kernel lockdown is on with Secure Boot, and without it through the `lockdown=integrity` argument
  (`ame security lockdown on|off`, `cat /sys/kernel/security/lockdown`). With Secure Boot off it keeps
  the image's own modules, such as DisplayLink's evdi, from loading.
- The developer groups (`ame system dx-group`, listed in `/usr/share/amethystora/developer-groups`) are
  joined only when the user picks them: `docker`, `incus-admin` and `libvirt` let any program they run
  become root without the sudo password. Prefer Podman, or `qemu:///session` for virtual machines.
- To find out why something crashed or stopped working, follow the `amethystora-diagnose` skill. The
  Updates, Security and Logs apps start you that way with **Ask the agent**, handing you a unit, a PID
  or the report's own words for a check.

## Ask the user first

- Anything with `sudo`, `pkexec` or `rpm-ostree`.
- Anything that loosens security: polkit rules, sudoers, the firewall (`firewall-cmd`), SELinux,
  sshd, kernel arguments (`ame security lockdown off` among them), Secure Boot, USBGuard, network
  protection (turning it off, or allowing a rule), encrypted DNS (pausing or turning it off), and
  joining an account to `docker`, `incus-admin` or `libvirt`. The image hardens these on purpose;
  explain the trade-off instead of working around it.
- `gsettings reset-recursively`, deleting user files, or reverting the user's own customisations.
- `amethystora-restore put-back`: say which version comes back and where first, and use `--replace`
  only when they asked for it (`--keep-both` puts the old file beside the current one).
- `ame system raid` with anything but `status`: it makes, changes and forgets pools of disks, and
  erases disks. Never choose the disks or the layout for the user, and never type `ERASE`: the command
  asks for it in a terminal, and that answer is the user's. Read a pool's state with
  `/usr/libexec/amethystora-raid status --json`, which needs no root.

Turning these instructions off is `ame agent toggle off`.
