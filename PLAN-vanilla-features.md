# Plan: Vanilla OS features in Amethystora

Written 2026-10-03 for the session that implements it. Nothing here is built yet. Read `AGENTS.md` first:
the build order, the tests, and the rules about the manual, the agent skill and licences all apply.

## Context

This plan brings five Vanilla OS features to Amethystora, on its Fedora and bootc base, rebuilt as
Amethystora's own. Vanilla OS 3 "Reunion" was also evaluated as a base, and the Fedora base came out more
secure: Reunion is a frozen Debian sid snapshot with no security repository, boots with `lsm=integrity` (no
SELinux, and very likely no AppArmor, Yama or lockdown), does not verify update signatures, and encrypts
only `/var`.

## Ground rules

1. **Clean room.** Do not read or copy source, help text, translations or artwork from Vanilla OS projects
   (Apx, Apx GUI, VSO, Sideload, First Setup, Continuity, the ABRoot rollback notifier). This document is the
   behaviour spec. Licences, for the record: Apx, Apx GUI, VSO, Sideload, First Setup and the notifier are
   GPL-3.0; Continuity is MIT; Apx's built-in definitions, its community templates and the VSO GNOME
   extension have no licence at all. Write the CLI in bash and any GUI in Electron, like the other
   Amethystora tools (Apx is Go, Apx GUI is Python).
2. **Amethystora names only.** No "Vanilla", "Apx", "VSO" or "Sideload" in commands, menus, app names or
   strings. The manual may say that `amethystora-pkg` reads Apx's file format: that only describes
   compatibility. Templates may be named after distributions; show no distribution logos (the existing
   "nobody else's logo" rule).
3. **No third-party code in the image.** New code is Amethystora's (Apache-2.0). Everything else is fetched
   on the user's machine from its own source: DistroShelf from Flathub, container images from their
   registries, the AUR helper and all packages inside containers. `NOTICE` and `SOURCES` must not change.
   Do not bundle Apx's definitions or community templates.
4. **Rootless containers only.** Nothing installed through this work touches the host system.
5. **Keep everything in step.** Every command, path and default added here goes into the manual
   (`usr/share/amethystora/manual/software.md` and wherever else it belongs), the agent skill
   (`usr/share/amethystora/agents/skills/amethystora/SKILL.md`) and `build_files/base/20-tests.sh`.

## Item 1: `amethystora-pkg`, Apx's feature set rebuilt

A bash tool at `/usr/bin/amethystora-pkg` on distrobox and podman, both already in the image. Apx's terms
are renamed: subsystems become **containers**, stacks become **templates**, package managers stay
**managers** on the command line.

### Commands (parity with Apx 3, checked against its command definitions)

```
amethystora-pkg containers list [--json]
amethystora-pkg containers new [--template T] [--name N] [--home DIR] [--init]
amethystora-pkg containers rm N [--force]
amethystora-pkg containers reset N [--force]             # delete, then recreate from its template
amethystora-pkg N enter | run CMD… | start | stop

amethystora-pkg N install [--no-export] PKG…
amethystora-pkg N remove PKG… | purge PKG…
amethystora-pkg N search QUERY | show PKG | list
amethystora-pkg N update | upgrade | autoremove | clean
amethystora-pkg N export|unexport --app A | --bin B [--bin-output DIR]

amethystora-pkg templates list [--json] | show T
amethystora-pkg templates new|update [--name --base --packages --pkg-manager] [--no-prompt]
amethystora-pkg templates rm T [--force] | export T [--output F] | import F

amethystora-pkg managers list [--json] | show M
amethystora-pkg managers new|update [--name --need-sudo --install --remove --purge --search --show
                                     --list --update --upgrade --autoremove --clean] [--no-prompt]
amethystora-pkg managers rm M [--force] | export M [--output F] | import F

amethystora-pkg install FILE                             # beyond Apx, see below
amethystora-pkg upgrade-all                              # beyond Apx, see "Container updates"
```

### Behaviour

- **Short name `amepkg`.** Ship `/usr/bin/amepkg` as a symlink to `amethystora-pkg`; both behave the same, and
  help and error messages use the name that was typed. Register completions for both names in bash, zsh and
  fish. The manual's examples use `amepkg`; scripts, desktop entries and units use the full name. Checked
  2026-10-03: no Homebrew formula and no file in Debian is named `amepkg`.
- **`ame` is taken.** Since 2026-10-03 it is the umbrella command over the system recipes, in groups
  (`ame desktop theme`, `ame update`), and `ame pkg` runs `amethystora-pkg`. Avoid `amy`: a Homebrew
  formula of that name exists.
- **Ownership.** Label every container created (`manager=amethystora-pkg`, its template, its short name)
  and give it a prefixed real name (for example `pkg-<name>`). List and act only on labelled containers;
  the user's other distrobox containers are left alone.
- **Prompts.** `containers new`, `templates new|update` and `managers new|update` ask for missing values
  on a terminal and fail without one; `--no-prompt` takes flags only. `rm` and `reset` confirm unless
  `--force`.
- **Creation.** The template's packages are installed when the container is created. `--home` gives the
  container its own home folder; `--init` runs systemd inside it (the image must support it).
- **Install exports, remove unexports.** After `install`, find the launchers from the package's own file
  list (`dpkg -L`, `rpm -ql`, `pacman -Ql`, `apk info -L`) and export each `usr/share/applications/*.desktop`
  with `distrobox-export --app`. `--no-export` skips this. `remove` and `purge` unexport those launchers
  before removing. (Apx guesses launchers from the package name and misses some; this does better.)
- **Export.** `--app` and `--bin` map to `distrobox-export`; `--bin-output` sets the export path.
- **Definitions.** Built-in templates and managers live read-only in `/usr/share/amethystora/pkg/`; the
  user's in `${XDG_DATA_HOME:-~/.local/share}/amethystora/pkg/`. Names are unique; built-ins cannot be
  edited or removed. Store them as JSON (jq is in the image).
- **Import.** `import` reads Amethystora's JSON and Apx's YAML. Apx stack files have `name`, `base`,
  `packages`, `pkgmanager`. Apx package-manager files have `name`, `needsudo`, `model` and `cmdinstall`,
  `cmdremove`, `cmdpurge`, `cmdsearch`, `cmdshow`, `cmdlist`, `cmdupdate`, `cmdupgrade`, `cmdautoremove`,
  `cmdclean`. Model 2 (the default) means each value is the whole command; model 1 means each value is
  appended to `name`.
- **JSON.** `--json` on the three lists prints stable, documented fields. Containers: name, template,
  image, status, home, init, exported apps, last upgrade. Templates: name, base, manager, packages,
  built-in, verified. Managers: name, need-sudo, the ten commands, built-in.
- **Built-in managers:** apt, dnf, pacman, zypper and apk. `paru` exists only while the AUR is on. Write
  the command table fresh.
- **Built-in templates**, each pinned by digest (see "Unchecked base images"):

  | Template | Image | Signed upstream |
  |---|---|---|
  | debian | `quay.io/toolbx-images/debian-toolbox:13` | yes, verified by the existing policy |
  | opensuse-tumbleweed | `quay.io/toolbx-images/opensuse-toolbox:tumbleweed` | yes |
  | alpine | `quay.io/toolbx-images/alpine-toolbox:<current>` | yes |
  | ubuntu | `quay.io/toolbx/ubuntu-toolbox:26.04` | no |
  | arch | `quay.io/toolbx/arch-toolbox:latest` | no |
  | fedora | `quay.io/fedora/fedora-toolbox:<current>` | no |
  | opensuse-leap | `registry.opensuse.org/opensuse/leap:<current>` | check |

  Checked 2026-10-03 through the quay.io API: the three toolbx-images repositories carry sigstore
  signatures; the Ubuntu, Arch and Fedora toolbox repositories carry none.

### Beyond Apx

- **`amethystora-pkg install FILE`** picks the container by file type and creates it from its template if
  needed: `.deb` to debian, `.rpm` to fedora, `.pkg.tar.zst` to arch. It installs the local file with that
  container's manager, then exports the launchers.
- **Double-click.** A desktop entry with `MimeType=application/vnd.debian.binary-package;application/x-rpm;`
  runs the install in a terminal through `/usr/libexec/amethystora-in-terminal`, as the Security app does.
- **Virus scan first.** Scan the file with the existing ClamAV (`clamdscan`, falling back to `clamscan`) and
  stop on a detection.
- **Safer sources and provenance first:** see "Unsandboxed software".
- **AUR, off by default.** `ujust toggle-aur` turns it on after a warning. It adds the `paru` manager and an
  `arch-aur` template whose containers get their own home folder by default. Before installing, show the AUR
  metadata (maintainer, votes, popularity, first submitted, last updated, out-of-date flag) from the AUR RPC
  interface, and warn on packages less than 30 days old or with no votes. Keep paru's PKGBUILD review on.
- **GUI.** Move `com.ranfdev.DistroShelf` from `usr/share/amethystora/homebrew/system-flatpaks.Brewfile` into
  `usr/share/flatpak/preinstall.d/` beside `bazaar.preinstall` and `flatseal.preinstall`. It manages
  containers and installs package files, but has no search by name and no templates or managers pages.
  Full Apx GUI parity (an Amethystora "Packages" Electron app with containers, templates and managers pages
  driven by `--json`, and Ptyxis for the terminal) is a later, separate decision.

### Container updates

`/etc/uupd/config.json` turns uupd's distrobox module off, and that stays: Bluefin did it on purpose
(ublue-os/bluefin#2436, May 2025) because `distrobox upgrade -a` made manual updates slow and broken user
containers became distribution bug reports. The module upgrades every container of every signed-in user.
Amethystora takes responsibility only for the containers `amethystora-pkg` creates:

- `amethystora-pkg upgrade-all` refreshes and upgrades each labelled container with its manager. One
  failure does not stop the rest. It logs one JSON line per container to the journal and records the date.
- A per-user `amethystora-pkg-upgrade.timer` runs it daily (`Persistent=true`, a randomised delay), enabled
  for everyone with `systemctl --global enable` in `17-cleanup.sh`. It skips a run when uupd's hardware
  checks would fail, using the thresholds in `/etc/uupd/config.json` (battery, CPU, memory).
- Amethystora Updates: after "Update now" finishes, start the user unit and show it under the step that
  `update.js` already defines for uupd's `Distrobox` module ("Containers"). A container failure shows on
  that step only and never marks the system update as failed.
- Security report: warn when a managed container has not been upgraded for 14 days. The check goes in
  `usr/libexec/amethystora-security-status` and nowhere else (AGENTS.md).

### Unsandboxed software

Containers are not a sandbox: what runs in them shares the user's home folder, display, audio and session
bus. Reduce the exposure without taking features away:

1. **Offer the safer source first.** Before installing by name or from a file, look for the same app on
   Flathub (sandboxed, signed, updated) and in the container's own signed repositories, and offer those
   before a loose file or the AUR.
2. **Show provenance before installing:** name, version, vendor or maintainer, signature (`rpm -K` for an
   `.rpm`; say plainly that `.deb` files are normally unsigned), whether it runs install scripts, and the AUR
   metadata above.
3. **Isolate where it does not break the app.** AUR containers get their own home folder by default.
   Templates can ask for a separate home or distrobox's `--unshare-*` options, which suit command-line
   tools; GUI apps usually need the shared display and GPU.
4. **Catch persistence.** Extend the security watcher to report new executables in `~/.local/bin` and other
   user PATH directories that shadow a system command (a fake `sudo`, `pkexec`, `ssh`, `gpg`), and desktop
   launchers that `distrobox-export` did not create. It already reports autostart entries, user systemd units
   and shell startup files. Per-home watches come from `usr/libexec/amethystora-audit-home-rules`; a new audit
   key must also go into the watcher, `amethystora-security-realtime` and `20-tests.sh` (AGENTS.md).
5. **Keep an inventory.** The Security app lists what is installed outside Flatpak: managed containers,
   their exported apps, AUR packages, each with its last upgrade.
6. **Say it.** The confirmation and the manual state the limit plainly.

### Unchecked base images

`/etc/containers/policy.json` verifies signatures only for `quay.io/toolbx-images` (sigstore) and Red Hat's
registries; its catch-all accepts any other image unchecked.

- Pin every built-in template image by digest. The pins ship inside the signed Amethystora image, so a
  pinned pull is authenticated through it. Add a Renovate custom manager in `.github/renovate.json5` so the
  pins stay current.
- Where upstream signs (Debian, openSUSE Tumbleweed, Alpine), podman also verifies the signature with the
  key the policy already trusts.
- `amethystora-pkg` pulls the image itself (`podman pull image@sha256:…`) before `distrobox create`, so the
  check cannot be skipped.
- After creation, everything inside comes from the distribution's signed repositories: apt, dnf, pacman,
  zypper and apk verify them by default.
- User templates may use any image. Mark them unverified in `templates list` and confirm at creation when
  the image is neither digest-pinned nor from a signature-verified registry.
- Do not tighten the policy's catch-all: it would break `podman pull` for everything else. Do not mirror and
  re-sign third-party images under `ghcr.io/iarsslen`: that makes Amethystora their redistributor, with the
  licence obligations that brings, for no gain over digest pins.

## Item 2: NVIDIA check on first boot

- Detect a PCI display device (class `0x03xxxx`) with vendor `0x10de` under `/sys/bus/pci/devices`, and read
  the running flavour from `/usr/share/amethystora/image-info.json` (`image-flavor`: `main` or `nvidia-open`).
- An NVIDIA card on a `main` image: notify (`usr/libexec/amethystora-notify-users`) offering the switch to the
  matching `-nvidia-open` image through `ujust rebase-helper`, which only accepts signed images. The reverse
  when an `nvidia-open` image runs without one. Never switch on its own. The message says that the NVIDIA
  images run without kernel lockdown (README, Security).
- Once per machine, with a "don't ask again", state under `/var/lib/amethystora`.
- Why it matters: the NVIDIA images have no ISO (`build-iso.yml`), so every NVIDIA owner installs the base
  image first.

## Item 3: "You're on the previous version"

- Detect that the booted deployment is not the default one (`bootc status --format=json` or
  `rpm-ostree status --json`).
- Amethystora Updates shows it with the date, and offers "Keep this version" (`bootc rollback`, through
  polkit) or "Restart into the latest". A notification at login opens the window. Link the manual's
  `updates.md#rolling-back`.

## Item 4: Restore your setup on a new machine

- `amethystora-backup` (restic) also stores a manifest with each snapshot: the image and stream
  (`image-info.json`), the Flatpaks of the machine and the user with their remotes, `brew bundle dump`, the
  managed containers and their templates (`amethystora-pkg containers list --json`), the enabled GNOME
  extensions and the theme. No secrets.
- `ujust restore-setup [snapshot]` shows the steps first, then switches the image through `ujust
  rebase-helper` (signed images only), installs the Flatpaks, runs `brew bundle`, recreates the containers
  and their packages, re-enables the extensions and sets the theme.

## Item 5: Welcome page on first login

- A user-setup hook opens `amethystora-manual welcome` once per user, guarded the way `11-theme.sh` runs once
  at first login. The Manual itself does not change: it still spawns nothing and loads only its own pages.

## Not doing

- Apx, VSO and Sideload themselves: item 1 replaces them. Apx GUI stays installable from Flathub.
- Smart updates: uupd's hardware checks already hold automatic updates back.
- A top-bar update indicator: the Updates window already follows any running update.
- `nrun` and the PRIME tools: GNOME's "Launch using Dedicated GPU" and `switcherooctl launch` cover them.
- VSO tasks, a first-boot app picker, arm64 and reproducible builds: each is a project of its own.
- Anything specific to ABRoot or Debian.

## Tests to add to `20-tests.sh`

- `amethystora-pkg` is installed, `amepkg` links to it, `ame pkg` runs it, and every `--json` list
  parses.
- Every built-in template image is pinned by digest (`@sha256:`).
- The double-click desktop entry validates (`desktop-file-validate`) and names both MIME types.
- `preinstall.d` holds DistroShelf beside Bazaar and Flatseal.
- `amethystora-pkg-upgrade.timer` is enabled globally; uupd's distrobox module is still disabled.
- No new file names Vanilla OS, Apx, VSO or Sideload, except the manual's compatibility note.

## Order

1. Item 1 core: containers, packages, export, templates, managers, JSON, digest-pinned templates.
2. Item 1 extras: file install, double-click, virus scan, provenance and safer sources, container updates,
   the watcher and inventory additions.
3. The AUR opt-in.
4. Items 3 and 2.
5. Item 4.
6. Item 5.
7. Later, if wanted: the Packages app for full Apx GUI parity.
