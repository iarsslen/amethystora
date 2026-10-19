# Software on Amethystora

## Installing software

In this order of preference:

1. GUI apps: Flatpak, `flatpak install flathub <app-id>` (Flathub is the machine's remote, so the app goes
   into the machine's installation, as the image's own commands put theirs; no password unless the stricter
   `flatpak-password` is on).
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

## Containers (amepkg)

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

## Notes and to-do lists

Notes and to-do lists are the Notes app (`amethystora-notes`), which the image ships in place of Joplin
and Planify; suggest it before installing either. Its data in `~/.local/share/amethystora-notes` is
usually encrypted with the user's passphrase, which a passkey on a security key can stand in for:
never read, move or delete anything there, and never ask for the passphrase or the key's PIN.

## The agents themselves

The agents are not part of the image. `amethystora-agent list` shows which are installed. They live in
the user's home (`~/.local/bin`, or `~/.opencode/bin` for Opencode), `ame update` leaves them alone and
they update themselves: `claude update`, `opencode upgrade`, `codex update`, `agy update`, `copilot
update`, `cursor-agent update`. A Gemini CLI installed before Antigravity CLI replaced it comes from
Homebrew, which `ame update` upgrades.
