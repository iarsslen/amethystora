# Amethystora Copilot Instructions

This document provides essential information for coding agents working with the Amethystora repository to minimize exploration time and avoid common build failures.

## Repository Overview

**Amethystora** is a cloud-native desktop operating system, based on Universal Blue and maintained by Arsslen Idadi (@iarsslen). It is an OS built on Fedora Linux using container technologies with atomic updates.

- **Type**: Container-based Linux distribution build system
- **Base**: `ghcr.io/ublue-os/silverblue-main` (Fedora with the GNOME desktop and GDM) + Universal Blue infrastructure; GNOME Shell extensions are git submodules under `system_files/shared/usr/share/gnome-shell/extensions`, built by `build_files/shared/build-gnome-extensions.sh`, except `amethystora-transitions@iarsslen.github.io` (see The transitions) and `amethystora-widgets@iarsslen.github.io` (see Widgets)
- **Languages**: Bash scripts, JSON configuration, Python utilities
- **Build System**: Just (command runner), Podman/Docker containers, GitHub Actions
- **Target**: desktop OS with two variants (base + developer experience)

## Repository Structure

### Root Directory Files
- `Containerfile` - Main container build definition (stages: `ctx`, `brew`, `base`)
- `Containerfile.sealed` - The sealed variant of a built image (`just seal`; see Sealed images)
- `secure-boot.crt` - The certificate of the Secure Boot key sealed images are signed with, once `just secure-boot-key` has made it
- `Justfile` - Build automation recipes (like a Makefile but more readable)
- `.pre-commit-config.yaml` - Pre-commit hooks for basic validation
- `image-versions.yml` - Image version configurations
- `cosign.pub` - Container signing public key
- `SECURITY.md` - How to report a vulnerability (privately, through the repository's Security tab)

### Key Directories
- `system_files/` - Files copied into the image, overlaid on those of the upstream layers
  - `shared/` - Every image: configurations, fonts, themes, the manual, the `ame` commands
  - `dx/` - `amethystora-dx` only, copied in by `build_files/shared/build-dx.sh`
  - `sealed/` - the sealed images only, copied in by `build_files/sealed/00-sealed.sh`
- `build_files/` - Build scripts organized as base/, dx/, shared/
  - `base/` - Base image build scripts (00-image-info.sh through 20-tests.sh)
  - `dx/` - Developer experience build scripts
  - `sealed/` - The sealing stage of `Containerfile.sealed`: prepare, build the UKI, test
  - `shared/` - Common build utilities and helper scripts
- `branding/` - Source of the artwork; `node branding/generate.mjs` draws it
- `iso/` - `iso.toml`, the bootc-image-builder configuration of the installer ISO; `product/`, which `build-iso.yml` adds to the ISO as `images/product.img`: the installer's Amethystora look (a stylesheet and artwork drawn by `branding/generate.mjs`), crash reporting (libreport files that send crash reports to Amethystora's issue tracker instead of Fedora's Bugzilla) and the Anaconda profile that keeps Fedora's installer settings although the installer's os-release says `generic`; `installer-packages.py`, which lists what the installer is made of; and `live/`, the live system of the live ISO: a `Containerfile` built `FROM` the published image with `build.sh`, which adds Fedora's live boot, live session and Anaconda's web installer, a copy of the image for an offline install (`installer.ks`), a profile for the image's own os-release ID, and the boot menu Titanoboa reads (`iso.yaml`)
- `po/` - The gettext catalogs of the shell programs that are translated, the security report and the app permissions (text domain `amethystora`): `amethystora.pot`, which `node build_files/shared/check-translations.js --write --po po system_files/shared` writes from the scripts, and one `<language>.po` each, which `14-security.sh` compiles into `/usr/share/locale`
- `.github/workflows/` - Comprehensive CI/CD pipelines

The desktop layer (the `ujust` recipes, the Homebrew Brewfiles, the setup services and hooks, the
GNOME defaults, udev rules) is kept in `system_files/shared`, already renamed, and is not pulled
from upstream. Only `ublue-os/brew`, for
Homebrew's own setup, is still copied in by the `ctx` stage of the `Containerfile`. Where to edit:
- `system_files/shared/usr/share/amethystora/just/` - the commands `/usr/bin/ame` runs, as just recipes in groups (`ame security scan now`). `00-entry.just` declares each group with `mod` (`agent`, `apps`, `desktop`, `security`, `system`, each in the file of its name), imports the top-level commands (`backup.just`, `changelog.just`, `control.just`, `report.just`, `update.just`), and runs `amethystora-pkg` as `ame pkg`. A command that switches something takes `on|off` (or the value it sets) as an argument, so that Control and scripts can say what they want; without one it may ask or flip, as before. `ujust` is the same command, and the flat names the recipes had under it are private aliases there: when a command is renamed or moved, alias its old name. `20-tests.sh` fails on an `ame` command that the image names and that does not exist, so in prose write `ame` in backticks or with punctuation after it
- `system_files/shared/usr/share/flatpak/preinstall.d/` - the Flatpaks every machine comes with, which `flatpak-preinstall.service` installs on the first boot that has a network (the ISO carries none) and retries until it does: `amethystora.preinstall` is the default list (no browser, Firefox is in the image; Amethystora Logs in place of GNOME Logs), and `system_files/dx` adds `amethystora-dx.preinstall`. Every group needs its `Branch` (`stable`, `3.22` for a GTK 3 theme), and taking an app off a list uninstalls it from the machines that got it from there
- `system_files/shared/usr/share/glib-2.0/schemas/zz0-amethystora-modifications.gschema.override` - the base GNOME defaults (the dash, the custom keybinding list); `build-gnome-extensions.sh` adds each extension it installs to its `enabled-extensions`, and `zz1-amethystora-modifications` overrides it

### Architecture
- **Two Build Targets**: `base` (regular users) and `dx` (developer experience)
- **Image Flavors**: main, nvidia-open
- **Fedora Versions**: resolved per build by `just fedora_version` (see Version Detection); `04-packages.sh` has cases for 42, 43 and 44
- **Stream Tags**: `stable`, `latest`, `beta`
- **Build Process**: Sequential shell scripts in build_files/ directory
- **Base Images**: Uses `ghcr.io/ublue-os/silverblue-main` as foundation from Universal Blue

## Build Instructions

### Prerequisites
**ALWAYS install these tools before attempting any builds:**

```bash
# Install Just command runner (REQUIRED for build commands, may not be available)
# If external access is limited, Just commands will not work
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Verify container runtime (usually available)
podman --version || docker --version

# Install pre-commit for validation (usually works)
pip install pre-commit
```

**Note**: In restricted environments, Just command runner may not be installable. Most validation can still be done with pre-commit and manual JSON validation.

### Essential Commands

**Build validation (ALWAYS run before making changes):**
```bash
# 1. Validate syntax and formatting (2-3 minutes)
# Note: .devcontainer.json will fail JSON check due to comments - this is expected
pre-commit run --all-files

# 2. Check Just syntax (requires Just installation)
just check  # Only if Just command runner is available

# 3. Fix formatting issues automatically
just fix    # Only if Just command runner is available
```

**Build commands (use with extreme caution - these take 30+ minutes and require significant resources):**
```bash
# Build base image (30-60 minutes, requires 20GB+ disk space)
just build amethystora latest main

# Build developer variant (45-90 minutes, requires 25GB+ disk space)
just build amethystora-dx latest main

# Build with specific kernel pin
just build amethystora latest main "" "" "" "6.10.10-200.fc40.x86_64"
```

**Utility commands:**
```bash
# Clean build artifacts (if Just available)
just clean

# List all available recipes (if Just available)
just --list

# Validate image/tag/flavor combinations (if Just available)
just validate amethystora latest main
```

**Working without Just (when external access is restricted):**
```bash
# Manual validation instead of 'just check':
find . -name "*.just" -exec echo "Checking {}" \; -exec head -5 {} \;

# Manual cleanup instead of 'just clean':
rm -rf *_build* previous.manifest.json changelog.md output.env

# View Justfile recipes manually:
grep -n "^[a-zA-Z].*:" Justfile | head -20
```

### Critical Build Notes

1. **Container builds require massive resources** (20GB+ disk, 8GB+ RAM, 30+ minute runtime)
2. **Always run `just check` before making changes** - catches syntax errors early
3. **Pre-commit hooks are mandatory** - run `pre-commit run --all-files` to validate changes
4. **Never run full builds in CI unless specifically testing container changes**
5. **Use `just clean` to reset build state if encountering issues**

### Common Build Failures & Workarounds

**Pre-commit failures:**
```bash
# Known issue: .devcontainer.json contains comments (invalid for JSON checker)
# This failure is expected and can be ignored:
# ".devcontainer.json: Failed to json decode"

# Fix end-of-file and trailing whitespace automatically
pre-commit run --all-files
```

**Just syntax errors (if Just is available):**
```bash
# Auto-fix formatting
just fix

# Manual validation
just check
```

**Container build failures:**
- Ensure adequate disk space (25GB+ free)
- Clean previous builds: `just clean` (if available)
- Check container runtime: `podman system info` or `docker system info`
- Build failures often indicate resource constraints rather than code issues

## Validation Pipeline

### Pre-commit Hooks (REQUIRED)
The repository uses mandatory pre-commit validation:
- `check-json` - Validates JSON syntax
- `check-toml` - Validates TOML syntax
- `check-yaml` - Validates YAML syntax
- `end-of-file-fixer` - Ensures files end with newline
- `trailing-whitespace` - Removes trailing whitespace

**Always run:** `pre-commit run --all-files` before committing changes.

### GitHub Actions Workflows
- `build-image-latest-main.yml` - Builds latest images on main branch changes
- `build-image-stable.yml` - Builds stable release images
- `build-image-beta.yml` - Builds beta images
- `build-images.yml` - Runs the stable, latest and beta builds together (manual dispatch only)
- `reusable-build.yml` - Core build logic for all image variants, and on the stable stream the sealed images (see Sealed images)
- `generate-release.yml` - Generates release artifacts and changelogs
- `build-iso.yml` - Builds the installer ISO of a stable image, `amethystora-non-uefi.iso` (the only one that starts computers without UEFI), with bootc-image-builder and uploads it, with its checksum signed by cosign, to Cloudflare R2 (a Release asset is limited to 2 GiB). `Stable Images` runs it after scheduled and dispatched builds for `amethystora` only, each upload replacing the last under the same name; `amethystora-dx` and the NVIDIA images have no ISO, and the workflow fails on any other image. bootc-image-builder picks the installer's packages by os-release `ID` and has no definition for `amethystora`, so the workflow runs its container by hand and writes Fedora's definition out under that name, with `generic-logos` and `generic-release` added so that the installer carries neither `fedora-logos` nor `fedora-release`; do not switch back to its GitHub action, which cannot. `iso/installer-packages.py` then lists the installer's packages from the builder's manifest for the ISO to carry beside `LICENSE` and `NOTICE`, and fails the workflow before the upload if one of Fedora's two is among them. Both kickstarts (`iso/iso.toml`, `iso/live/installer.ks`) switch the installed machine with `--enforce-container-sigpolicy`, which only rewrites the origin and needs no network, and both ISO builds fail on a switch without it. The builder is pinned by digest to its last build that reads definitions from a folder; its successor compiles them in, so moving to it means rewriting that step. Its second job, `live-iso`, builds the live ISO of `amethystora` only, `amethystora.iso` (https://download.amethystora.org/amethystora.iso): it checks the published image against `cosign.pub`, builds `iso/live` from it with `podman build --cap-add sys_admin`, and has Titanoboa (`ublue-os/titanoboa`, Apache-2.0, pinned to its first commit that takes only an image) squash it into a UEFI-only ISO, then lists the live system's packages, fails on Fedora's logo or release package, adds `LICENSE`, `NOTICE` and the list, and signs and uploads as the installer job does. Titanoboa's offline-install store in `/usr/lib/containers/storage` does not work with Fedora 45's podman 6 (ublue-os/titanoboa#151): solve that before the stable image moves to 45
- `validate-renovate.yml` - Validates the Renovate configuration on pull requests
- `scorecard.yml` - OpenSSF Scorecard supply-chain checks (weekly)
- `clean.yml` - Cleanup old images and artifacts
- `moderator.yml` - Repository moderation tasks

**Workflow Architecture:**

- Stream-specific workflows (stable, latest, beta) call `reusable-build.yml`
- `reusable-build.yml` builds both base and dx variants for all flavors (main, nvidia-open)
- Fedora version is dynamically detected based on stream tag
- Images are signed with cosign and pushed to GHCR
- Every workflow sets `permissions: {}` or read-only access at the top and grants write access on the job that needs it, which OpenSSF Scorecard checks (`build-images.yml` is the exception: each job it runs needs the same write access)

### Manual Validation Steps
1. `pre-commit run --all-files` - Runs validation hooks (2-3 minutes, .devcontainer.json failure is expected)
2. `just check` - Validates Just syntax (if Just is available, 30 seconds)
3. `just fix` - Auto-fixes formatting issues (if Just is available, 30 seconds)
4. Test builds only if making container-related changes (30+ minutes)

## Package Management

### Package Configuration
Packages are defined directly in build scripts rather than in a central configuration file:
- `build_files/base/04-packages.sh` - Core package installations
  - `FEDORA_PACKAGES` array - Packages from official Fedora repos (installed in bulk)
  - `COPR_PACKAGES` array - Packages from COPR repos (installed individually with isolated enablement)
  - Fedora version-specific package sections using case statements (e.g., `42)`, `43)`)
- `build_files/dx/00-dx.sh` - Developer experience package additions. The editor is VSCodium, from its repository with the key pinned in `system_files/dx/etc/pki/rpm-gpg`: Microsoft's VS Code licence does not allow it to be shared inside a published image, so do not bring it back. Nothing joins an account to `docker`, `incus-admin` or `libvirt`, each root under another name: `ame system dx-group` offers the groups listed in `system_files/shared/usr/share/amethystora/developer-groups`, which Control and the security report read too

### Games, Android apps, drawing tablets and the CPU scheduler

Each is installed and off, and turned on per machine or per account by one command that says first what
it changes. `ame apps gaming` installs Steam, ProtonPlus and the MangoHud and gamescope Vulkan layers of
Steam's own runtime branch from Flathub, and grants X11 back to Steam alone, for the account
(`flatpak override --user`), and gives `/dev/uinput` back for Steam Input (`ame security virtual-input off`;
the image keeps it root's, Solaar's rule included, since a virtual keyboard types into any window, and
`ame apps opentabletdriver` does the same); Steam itself never goes into the image (its package is RPM Fusion's
non-free one). `gamemode` is in the image for games to reach through its portal. `ame apps android`
sets up Waydroid (Fedora's package, with its own SELinux policy; binder is built into Fedora's kernel):
it enables `waydroid-container.service`, which ships disabled, and downloads LineageOS without Google's
apps on the machine; never offer Google's. `ame system scheduler` picks a sched-ext scheduler through
`scx_loader.service` (shipped disabled, configured in `/etc/scx_loader/config.toml`) from CachyOS's
COPR `bieszczaders/kernel-cachyos-addons`, which Bazzite uses too: Fedora's own scx packages predate the
kernel interface. It checks `/sys/kernel/sched_ext` and falls back to the kernel's scheduler when the
kernel will not load one. `ame apps opentabletdriver` installs OpenTabletDriver from Flathub and copies
the udev rules of its release into `/etc`: the tag and the SHA-256 of the tarball are pinned in
`apps.just`, where Renovate's `github-release-attachments` manager bumps both, so nothing reaches `/etc`
from an unchecked download. Its daemon runs from the image's own user unit,
`amethystora-opentabletdriver.service`, which nothing enables for every account.

### The browser

The browser is Firefox, Fedora's package, installed by `04-packages.sh` so that a machine has one
before it is online. Mozilla lets Firefox be redistributed only unaltered, so it ships exactly as
Fedora builds it: do not add a `policies.json`, an extension, a preference file or a home page for
it, in the image or from a setup hook (`20-tests.sh` fails on a policy file). That is why the image
has no browser policy and installs no extension. The one thing taken out, by the maintainer's choice
of 2026-10-04, is Fedora's start page: `04-packages.sh` deletes the two lines of Fedora's preferences
that open Firefox on start.fedoraproject.org and pin it on the new tab page, which leaves Firefox's
own home page. Never put amethystora.org or any other page there: Mozilla's distribution policy
names a changed home page among the changes that need its written consent. Brave, the browser before it, is not in the image
and not on the Flatpak lists: its terms license its package for personal use, not for
redistribution. Like every other browser, it is the user's to install from Bazaar.

Browser protection, the extension allowlist and the block on WebUSB, WebSerial, WebHID and Web
Bluetooth, is opt-in for the same reason: a policy the machine's owner turns on is theirs, not the
image's. `ame security browser` runs `/usr/libexec/amethystora-browser-policy`, which
writes `usr/share/amethystora/browser-policy/chromium.json` or `firefox.json`, with the IDs in
`/etc/amethystora/browser-extensions` added, to every place in its `TARGETS` table: Brave, Chrome,
Chromium, Edge and Firefox, as packages and as Flatpaks. To cover another browser, add its line
there. Keep the Firefox forks out: a system policy replaces the one they ship. The policies only
allow extensions and must never install one. The Security report reads the helper's `status`.

### Agentic features

Every image, base and dx, ships `amethystora-agent`, the launcher behind `Super+Ctrl+Shift+A` and
the menu's "Ask an agent". The agents it offers, Claude Code, Opencode, Codex, Gemini CLI, Copilot CLI
and Cursor CLI (`AGENTS` in the launcher, which `amethystora-agent list` prints for Control), are
deliberately not in the image: they release far more often than it does, so the launcher installs the
chosen one into the user's home with its maker's installer on first launch (or `ame agent install`),
where it updates on the user's terms. Gemini CLI is the exception: Google publishes no installer, so it
comes from Homebrew and updates with it. Do not add them to `04-packages.sh`; `20-tests.sh` fails if
one appears in `/usr/bin`. The
skill in `system_files/shared/usr/share/amethystora/agents/skills/amethystora/SKILL.md` tells
agents how to change *a user's machine* safely: this repository is where it is written, not a place
it applies to. `amethystora-diagnose/SKILL.md` beside it is the read-only method behind
`amethystora-agent diagnose`. `user-setup.hooks.d/13-agentic.sh` links every skill there into
`~/.claude/skills`, which Claude Code reads, and `~/.agents/skills`, which the others read. Opencode reads
both and requires skill names to be unique across them, so the launcher starts it with
`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`. The features are on by default. `ame agent toggle` turns them off per user by writing
`~/.config/amethystora/no-agentic`. Keep the skill accurate when you change a command, path or
recipe that it names.

Updates, Security and Logs offer **Ask the agent** where something failed, while the features are on
(`amethystora-agent status`): each runs `amethystora-agent diagnose` with what its main process picked
itself, never words from its page. Updates passes the failed updater unit (one of its two), Security the
check's id looked up in the report it read (and passes that check's title and sentence), Logs a crash's
process number or the `.service` an entry came from, both checked for their shape.

### The manual

The Amethystora Manual (`amethystora-manual`, `Super+F1`, "Manual" in the Amethystora menu) is the
user documentation, shipped in the image so that it always describes the image it is on. Its pages
are the Markdown files in `system_files/shared/usr/share/amethystora/manual`, listed and grouped in
`pages.json`; the hotkeys page is `keybindings.md` one level up, which `ame desktop keybindings` also
shows. **Keep the manual accurate** when you change a command, recipe, hotkey, path or default that
it describes, and add to it when you add something a user would look for there.

- Link between pages as files (`updates.md#rolling-back`). `build_files/shared/check-manual.js`
  runs in `20-tests.sh` and fails the build on a page that is missing or a link that lands nowhere.
- `07-debrand.sh` rewrites every Universal Blue name in the image except on a line that
  also carries a copyright or licence phrase, or a comment that opens with a credit (`# Written by`,
  `# Modified by`, `# Source:`), so upstream is credited only that way (`about.md`).
- The window is an Electron app in `system_files/shared/usr/lib/amethystora-manual/resources/app`.
  It only loads its own pages, opens web links in the browser, and follows the theme's palette.
  `13-manual.sh` adds the pinned Electron and `marked` it runs on. The sidebar draws the same wordmark
  as Security, from its own copy of `gem.svg`.
- A page translated into another language is `manual/<language>/<page>.md` (the hotkeys page too, as
  `manual/<language>/keybindings.md`). Weblate writes them from the English, paragraph by paragraph, so
  edit the English only. A translated page's headings take the ids of the English page's headings in
  the same order, so `updates.md#rolling-back` lands in every language; `check-manual.js` checks the
  translations' links against the English headings and warns when a translation has a different number
  of headings.

### Translations

The Manual, Security, Updates, Logs, Notes, Control and Backups follow the session's language. They share one runtime,
`i18n.js`, kept in the Manual's folder and hard-linked into the others by their build scripts, as
Electron is. The English text in the code is the key: `t('Update now')`, `t('Last updated {when}', {
when })`, and plurals and variants in ICU MessageFormat (`{count, plural, one {# file} other {# files}}`).

- The first argument of `t(` or `t.parts(` is always a plain string in quotes, a whole sentence or label:
  never a template literal, never fragments joined into a sentence. Text in `index.html` is marked
  `data-i18n` or `data-i18n-attr`. Text an app reads from data goes through `t.dynamic()` and is listed
  in `check-translations.js`'s `DATA`, which already lists the Manual's section names and every app's
  launcher.
- Each app's catalogs are `locale/<language>.json` beside it, keyed by the English. `locale/en.json`
  lists every message and is what Weblate translates from: after changing a message, run
  `node build_files/shared/check-translations.js --write --po po system_files/shared`, which rewrites it
  and `po/amethystora.pot`. `20-tests.sh` runs the same check without `--write`.
- Dates, numbers and lists go through `Intl` with `t.locale` (`t.days()`, `t.list()`, `t.number()`),
  never `toLocale*String([])`: Chromium's own locale follows the session only for the languages whose
  `.pak` `13-manual.sh` keeps. Data that must read left to right in any language (paths, commands, ids)
  gets `dir="ltr"`; stylesheets use logical properties (`margin-inline-start`, `inset-inline-end`), so
  that Arabic lays out right to left.
- The security report, the app permissions and Control's list translate with gettext (`gettext`,
  `eval_gettext` and `eval_ngettext`, values as shell variables), and the Security and Control apps show
  their words as they come. Never pass the report's or the helpers' text through `t()`.
- `translate-desktop.py` writes each launcher's translated `Name`, `GenericName`, `Comment` and
  `Keywords` from the app's catalogs at build time: edit the English in the `.desktop` file only.

### The Security app

Amethystora Security (`amethystora-security`, **Security** in the app grid) is the security report and
the virus scanner, in place of the report's terminal launcher and ClamUI. Its checks live in one
script, `system_files/shared/usr/libexec/amethystora-security-status`: `ame security status` prints
it and the app asks it for `--json`, so a check added or changed there reaches both. Never write a
check into the recipe or the app. The app runs only the commands that script names, in a terminal
(`amethystora-in-terminal`). What a scan finds is only reported unless `ON_DETECTION` in
`/etc/amethystora/security.conf` (default `report`) says quarantine or delete, and then only through
`/usr/libexec/amethystora-quarantine`, which scans each file again first; never add `--move` or
`--remove` to a scan. `/usr/libexec/amethystora-security-config` is the one reader of that file.
Starting the whole-machine scan without a password is all `50-amethystora-virus-scan.rules` allows.
Network protection, the app's **Network** page, is Suricata inline on the machine's own traffic
(`amethystora-ips.service`, `/usr/libexec/amethystora-ips`), off until `NETWORK` in that file says
`watch` or `block`; only `block` cuts anything off. It fails open at every layer: the queue's `bypass`
in `amethystora-ips.nft`, and the fail-open, exception and stream settings
`build_files/shared/ips-config.py` writes into the configuration it derives from the package's. Keep it
that way: a failure must cost inspection, never the network.

The security watcher (`amethystora-security-watch`, on a 15-minute timer, or on each audit event when
`REALTIME_WATCH=on`) reads the audit log per key, the journal, `/etc` against `/usr/etc`, setuid files
outside `/usr` and listening ports, writes what only root can see to
`/var/lib/amethystora/security/status.json` for the report, and runs the report to notify when a watched
check turns bad. It also looks at what each account's session finds first: a command in `~/.local/bin`,
`~/bin` or Homebrew's prefix named like a system one, and a launcher in `~/.local/share/applications` that
no container export made. The audit rules ship one file per key in `/usr/share/amethystora/audit`, which
`amethystora-audit-home-rules` writes into `/etc/audit/rules.d/60-amethystora.rules` at every boot, beside
the per-home rules (`persistence`, `user-programs`). A new audit key has to be added to the watcher, to
`amethystora-security-realtime` and to `amethystora-security-config`; `20-tests.sh` fails otherwise. The
app's **Containers** page is what `amethystora-pkg containers list --json` says, run as the user.

**Every security feature is a switch, and off costs nothing** (the maintainer's rule of 2026-10-08). A
detection feature is a key in `security.conf`, defined in `amethystora-security-config` with its values,
words, group and how it applies (`--list --json`, the app's **Settings** page, `ame security settings`);
every unit that runs one reads its key in `ExecCondition=` (a drop-in for the packages' own: `clamd@`,
`clamav-freshclam`, `auditd`, `audit-rules`), and a key that is off writes no audit rule, so a line edited
by hand applies at the next boot. What the image enforces from the start (kernel settings, blocked
modules, kernel arguments, firewall zone, fail2ban, lockout, the Flatpak override, virtual input, SSH
settings, signed updates) is switched by `/usr/libexec/amethystora-hardening`, one `ame security` command each, which keeps
what is off in `/etc/amethystora/hardening-off` and names the files it writes, which the watcher's drift
check accepts exactly. A feature switched off is `info` in the report with the command that turns it on,
never a warning; turned off any other way it still warns. A change made through a switch is noted
(`amethystora-security-config note`), and the watcher records it without notifying. `ame security
profile off|default` sets every detection key at once. `ame security allow report` accepts a check that
cannot be fixed on the machine (`/usr/libexec/amethystora-security-allow`). `test-security-switches.sh`
checks all of it. A new feature gets its switch with it, off by default.

What each Flatpak can reach beyond its sandbox is `/usr/libexec/amethystora-app-permissions --json`,
run as the user, which the report's **App permissions** check, the app's **Apps** page and `ame
security apps` all read. It compares `flatpak info --show-permissions` (every override applied) with the
app's manifest and its own overrides, and gives each reach an id from its fixed list; the report flags
the ids that leave the sandbox, whoever granted them. The app takes back only the account's own
overrides for an app the list says has some (`flatpak override --user --reset`). The global override
the image ships, `/etc/flatpak/overrides/global`, only applies through the link
`amethystora-flatpak-overrides.conf` makes in `/var/lib/flatpak/overrides`: Flatpak reads no other place.
It takes X11, the input devices and the Flatpak service from every app, and leaves `--device=all` to the
apps that ask for it.

Encrypted DNS (`ame security dns`, `/usr/libexec/amethystora-dns`) and a different address on each
network (`ame security mac`, `/usr/libexec/amethystora-mac`) are switched by the files their helpers write,
not by `security.conf`: a resolved drop-in with the resolver, `DNSOverTLS=yes` and `Domains=~.`, and
NetworkManager drop-ins copied from `/usr/share/amethystora/network`. The DNS one sets each network's own
servers to plain text, for its own names and the connectivity check, which would otherwise find every
network offline. Three things in the helper were settled from the programs' source, and `20-tests.sh`
holds them: systemd-resolved is reloaded, never restarted, since a reload keeps what NetworkManager and
Tailscale set on each network and a restart forgets it; networks connected already are changed with
`nmcli device modify`, since `nmcli device reapply` on an unchanged connection rebuilds nothing; and on a
network that wants a login first, the user unit `amethystora-dns-portal.service` (in the session, not a
NetworkManager dispatcher script) offers a ten-minute pause, which the person at the machine starts:
never pause it automatically, or any network could turn the encryption off.
The sidebar draws the boot splash's wordmark live, from `gem.svg` (written by `branding/generate.mjs`)
and Quicksand, with the generator's own sizes and glow.

### Logins

The image's authselect profile carries `with-pam-u2f` (`04-packages.sh`), `with-faillock` and
`with-fingerprint` (`08-hardening.sh`, the installer's own feature last), and no profile change may drop
them. realmd's stock login commands would (`authselect select sssd with-mkhomedir --force`), so
`/etc/realmd.conf` runs `/usr/libexec/amethystora-domain-logins` for all four: a join selects `sssd` or
`winbind` with the image's features and `with-mkhomedir`, and `realm leave` the image's own profile again.
The watcher takes that setup, and nothing else, as the image's (`amethystora-domain-logins check`). A
domain's accounts are not in `/etc/passwd` and are numbered far above 65534, so the per-account checks
find accounts by their folders in `/var/home` as well, and never filter on `uid < 65534`.

- **Parental Controls' allowed hours** are `pam_malcontent` in `login` and `sshd` only, by the
  maintainer's choice of 2026-10-05: GNOME Shell's own lock covers the desktop and keeps unsaved work,
  where the module would close the session. Keep it out of GDM's services, and keep its line before
  `account include`, where the `sssd` and `winbind` profiles' `sufficient pam_localuser.so` cannot end
  the stack ahead of it.
- **`ame security ssh-codes`** (off by default) makes a password login over SSH ask for a code from
  google-authenticator too. Its state is the two files `/usr/libexec/amethystora-ssh-codes` writes, an
  sshd drop-in and one line in `/etc/pam.d/sshd`, deliberately not a key in `security.conf`, which sshd
  cannot read. The watcher accepts exactly those two and nothing in between.

### The Updates app

System Updates (`amethystora-update`) replaces upstream's System Update launcher, which opened a
terminal on `ujust update`; `ame update` stays for the terminal. **Update now** starts
`uupd-manual.service`, the same updater the automatic updates run, which the `uupd.rules` the uupd
package ships lets anyone start without a password (the ublue-os/packages build installs it in
`/etc/polkit-1/rules.d`, not `/usr/share`). The window never runs `bootc`, `flatpak` or `brew`
itself, with one exception: on a machine started from an older deployment than its default one,
**Keep this version** runs `pkexec bootc rollback`, after an administrator's password
(`amethystora-update-alert.service` says so at login and opens the window). It follows uupd's JSON log
in the journal and reads the deployments from `rpm-ostree status`. If uupd changes the `Updating`,
`module_fail` or `Updates Completed Successfully` messages it logs, update `main.js` to match. After an
update started there, it starts the account's `amethystora-pkg-upgrade.service` and shows it as the
**Containers** step, which reuses the step `update.js` keeps for uupd's own distrobox module; a
container's failure shows there only, never as a failed system update. Its **Firmware** section asks
fwupd (`fwupdmgr get-updates --json`, no password) and installs in a terminal (`fwupdmgr update`), where
fwupd asks before a restart; `fwupd-refresh.timer`, which `17-cleanup.sh` enables because Fedora leaves
it to GNOME Software, fetches what LVFS has. The top bar draws the same wordmark as Security, from its
own copy of `gem.svg`.

### The Logs app

Amethystora Logs (`amethystora-logs`, **Logs** in the app grid) replaces GNOME Logs, which
`amethystora.preinstall` leaves out and `system-setup.hooks.d/21-retire-gnome-logs.sh` uninstalls,
once, from a machine that already had it. It is read-only: it runs
`journalctl` as the user, and nothing else but a terminal, the Manual and the agent's diagnosis on what
`main.js` picked, so administrators (`wheel`) see the whole machine and anyone else their own session. `main.js` builds every `journalctl` argument from the page's choices:
an app has to be one `main.js` found with `journalctl --field`, a unit or program only ever reaches it
as the value of `--unit`, `--user-unit` or `--identifier`, and the search only as the value of `--grep`.
Keep it that way, and never pass a string from the page as an argument of its own. Its manual section
is `troubleshooting.md#the-logs`. The sidebar draws the same wordmark as Security, from its own copy
of `gem.svg`. While it reads the journal it shows the gem with its stem blinking, from `gem-bowl.svg`
and `gem-stem.svg`, which the generator writes as well.

### The Notes app

Amethystora Notes (`amethystora-notes`, **Notes** in the app grid) is the notes and to-do app, in
place of Joplin and Planify: notebooks, Markdown notes with tags, attachments, history and a trash,
and tasks in an inbox or projects with sections, dates, repeats, reminders, priorities, labels and
subtasks. It imports Joplin's JEX export and Planify's JSON backup. Nothing is synced and it opens no
connection: keep it that way, and keep Joplin and Planify off the Flatpak lists (`20-tests.sh`
checks). Everything is in `~/.local/share/amethystora-notes`. When encrypted (offered, and chosen by
default, on first run), the data and each attachment are sealed with AES-256-GCM under a random key,
which is itself sealed under a key derived from the passphrase with scrypt. `main.js` holds the key
only while unlocked and serves attachments to the page through `res://`. The page renders Markdown
with the Manual's `marked`, with raw HTML escaped. Keep both properties. Its manual page is
`notes.md`. It hard-links `marked` from the Manual, so a `marked` bump reaches both. Its lock screen
draws the gem from `gem-bowl.svg` and `gem-stem.svg` (written by `branding/generate.mjs`), so that the
stem can lift while the passphrase is checked.

A passkey (**Settings**, **Add a passkey**) opens the notes beside the passphrase, never in its place:
the same random key sealed once more, under the secret a FIDO2 security key computes with `hmac-secret`
for the credential and salt kept in `vault.json`. `main.js` asks the security key through `fido2-token`,
`fido2-cred` and `fido2-assert` (`fido2-tools`, in `04-packages.sh`), which take their parameters and
the PIN on stdin, and always with its PIN or a fingerprint (`pin=true` or `uv=true`): a touch alone
must never open the notes. Nothing is stored on the security key, and a backup carries no passkey.

### The Control app

Amethystora Control (`amethystora-control [page]`, **Control** in the app grid, `Super+Ctrl+Shift+C`) is
the window for Amethystora's own settings outside security: the theme, wallpaper and transition, the
window layout, widgets, the terminal's greeting and tools, games, Android apps, drawing tablets, the AUR,
web apps, the add-ons, the AI agent, the image and stream, developer mode, an image of one's own, the CPU
scheduler, the firmware, freeing space, the pools of disks, starting over, and the setup file. What it shows is one script,
`system_files/shared/usr/libexec/amethystora-control-list`: `ame control` prints it and the window asks
it for `--json`, so a setting added or changed there reaches both. Never write a setting into the window.

- **Every change is an `ame` command.** The script writes each command in plain words, so that the check
  in `20-tests.sh` for commands that do not exist sees them, and a setting no `ame` command reaches gets
  a recipe first. A command marked `terminal: true` opens in `amethystora-in-terminal`; every command
  that asks something, explains a risk or needs a password is marked so. One run directly has no
  terminal and must never prompt.
- **The page sends only ids.** It sends back an entry's id and one of the values the list gave, and
  `main.js` runs the command the list has for it, as an argument vector. The only things typed on the
  page, a slider's number, a new widget's name and a repository to trust, are checked in `main.js` first;
  the repository against `amethystora-trust-image`'s own expression, which `20-tests.sh` compares. The
  key is picked in `main.js`'s own file dialog, and the page never names it.
- **Security stays in Security,** by the maintainer's rule: nothing in the script or the window runs
  `ame security`. The sidebar opens Security, Updates (whose switch automatic updates keep) and Backups
  (whose controls the backup keeps).
- **Pools of disks** are the System page's Disks group: a `disks` entry with one row for each pool from
  `amethystora-raid status --json`, each with the actions the list gives it, which `main.js` runs with
  `pool(action, id)`. Every one of them is an `ame system raid` command in a terminal (`20-tests.sh`).

Its manual page is `control.md`, and each card links to its own section. The sidebar draws the same
wordmark as Security, from its own copy of `gem.svg`, and the app grid's icon is the tile `generate.mjs`
draws (`amethystora-control.svg`).

### The Backups app

Amethystora Backups (`amethystora-backups [FOLDER | status]`, **Backups** in the app grid, **Open With**
on a folder in Files) is the home folder as it was at any hour the hourly snapshots
(`amethystora-home-snapshot`) or the daily restic backup (`amethystora-backup`) kept, on one timeline, and
putting back what was lost. What it shows is one script, `/usr/libexec/amethystora-restore`, run as the
user: `status`, `points`, `ls`, `versions`, `put-back` and `open`, each with `--json`. `ame backup
snapshots` and `ame security ransomware restore` take their lists from `points` too, and the security
report's `backup-runs` check reads `status`. Never work out a point, a path or a state in the window.

- **The page sends back only what `main.js` read.** A point is one `points` gave, a path one `ls` listed
  (or a folder above it, or the folder the window was opened on), and a way to put back one of
  `keep-both`, `replace` and `skip`; each is an argument of its own. The helper refuses a path that
  leaves the home or starts with `-`, and puts back only inside the home.
- **Nothing deletes.** Neither the helper nor the window runs `restic forget`, `prune`, `rewrite` or
  `key`, restore's `--delete`, or `btrfs subvolume delete`; `20-tests.sh` greps for them. Putting back
  adds what is missing and keeps a file that changed beside the old one (`name (2026-10-04 14.00).ext`)
  unless the page was told otherwise. Looking runs restic with `--no-lock`, so it works against an
  append-only repository; `restic mount` is not used.
- **The backup's controls stay here,** by the maintainer's choice: **Set up** runs `ame backup setup` in
  a terminal, the daily run is `ame backup on|off`, and **Back up now** starts `amethystora-backup.service`
  and follows it in the journal. The hourly snapshots are a security switch: the window shows them and
  opens Security, and never runs `ame security`.
- **The last good backup** is the stamp `amethystora-backup` writes to
  `~/.local/state/amethystora/backup-last-success`. A daily run with none for 7 days is stale, which the
  window and the report's `backup-runs` check say. The security watcher runs as root, sees no account's
  backup, and does not notify about it.
- Déjà Dup is still on `amethystora.preinstall`. Taking it off, after a release of notices, is
  `plans/PLAN-backups-and-features.md`'s last step.

Its manual section is `security.md#backups`. The sidebar draws the same wordmark as Security, from its
own copy of `gem.svg`; the app grid's icon is drawn for the image in `build_files/shared/candy-icons`
(named in `NOTICE`), with the tile `generate.mjs` draws (`amethystora-backups.svg`) for other themes.

### Pools of disks

`ame system raid` (`/usr/libexec/amethystora-raid`, run as the user, asking sudo for each step that
needs root) makes btrfs RAID pools from spare disks with one command, `ame system raid create`, and
replaces, adds, opens and forgets them. Its plan, with what is left to do, is `plans/PLAN-raid.md`.

- **btrfs's own RAID, nothing installed.** Every layout is offered, each with its cost said first: two
  and three copies, raid10, raid5 and raid6 with btrfs's own warning, and combined. Metadata is raid1 on
  two disks and raid1c3 from three, never parity.
- **Nothing erases a disk it should not.** A disk is offered only when nothing holds it (mounted, swap,
  LUKS, md, LVM, a member of a btrfs or of a pool that did not mount, zram, read-only), and erased only
  in a terminal after `ERASE` is typed, with the list read again just before: there is no `--yes`, and
  `test-raid.sh` checks the filter and that nothing runs without a terminal.
- **A pool** is a GPT partition per disk named `raid-POOL-N`, LUKS2 under it unless the user said no
  (key in `/etc/cryptsetup-keys.d/raid-POOL.key`, one recovery key in every disk's slot 1), lines in
  `/etc/crypttab` and `/etc/fstab` with `nofail`, and the fstab line marked `x-amethystora-raid`, which
  is how the status knows of a pool that did not mount. A pool that lost a disk is mounted degraded only
  by `ame system raid mount`, never by itself and never in fstab.
- **One source of state:** `amethystora-raid status --json`, which needs no root (sysfs, lsblk,
  findmnt, `btrfs filesystem show` on a mounted pool, and what the services write to
  `/var/lib/amethystora/raid`). Control's Disks group and the check read it; its sentences are each
  reader's own. Security's report has no RAID check, by the maintainer's choice.
- **Watched:** `amethystora-raid-check.timer` (hourly, as root) reads SMART into `disks.json` and
  notifies, with an **Open Control** button, what changed since `last.json`, which is written only once
  somebody was logged in to tell. `amethystora-raid-scrub.timer` scrubs monthly on mains power and
  resumes a scrub a suspend cut short. Both are enabled in every image and skip a machine with nothing to
  watch (`ExecCondition=... present`).
- **The system's disks:** `ame system raid mirror` converts an installer-made multi-disk `single`
  system to raid1. Mirroring the system onto a new disk (the plan's 2b) is not built: it waits for a VM
  spike, and starting with a disk of the system dead is unsolved.
- `ame security disk-unlock` and the report's disk-unlock tile take the system's LUKS partitions from
  `amethystora-raid root-luks`, never the first LUKS device on the machine, which may be a pool's.

### The transitions

Amethystora Transitions (`amethystora-transitions@iarsslen.github.io`, written for this image and
kept in `system_files/shared/usr/share/gnome-shell/extensions`, not a submodule) reveals a new theme
or wallpaper with an animation, as swww does on Hyprland. It freezes the screen in GNOME Shell's own
`screenTransition` actor, which makes the background manager swap the wallpaper at once instead of
fading it, and once nothing has changed for 300 ms a GLSL shader opens the picture onto the new
desktop. `amethystora-theme` calls `Hold` and `Release` on `/org/amethystora/Transitions` (on
`org.gnome.Shell`) around a theme switch so that it is one transition; a change to a watched
background or interface key starts one by itself, and the Dark Style toggle reaches it through
`screenTransition.run()`. The screen is never held for more than five seconds, and nothing is held
while GNOME's animations are off. Its schema is in `/usr/share/glib-2.0/schemas`, for `ame desktop
transition`. `stage.paint_to_content` took a colour-state argument in GNOME 50: check that call before
adding a GNOME to its `shell-version`, which `20-tests.sh` requires.

### Widgets

Amethystora Widgets (`amethystora-widgets@iarsslen.github.io`, in `system_files` like the transitions)
is the top bar's counterpart of Omarchy's bar plugins, made for agents to write. A widget is a folder in
`~/.config/amethystora/widgets` holding `widget.json` and a command; the extension runs the command and
shows what it prints as a label, an icon and a menu, and loads a widget again whenever its folder
changes. Widgets are deliberately not code inside GNOME Shell: on Wayland the shell is the compositor,
so a mistake in it ends the session, and new code only loads after logging out. `protocol.js` is the one
definition of the format and `runner.js` the one way a command runs (its own session, a fixed `PATH`,
`WIDGET_ID`, `WIDGET_DIR`, `WIDGET_STATE`, 30 seconds per run); `check.js`, which `amethystora-widgets
run` is, imports both, so what the check passes is what the bar shows. Keep it that way. The
`amethystora-widgets` skill documents the format for agents and `widgets.md` for users: change them with
`protocol.js`. `amethystora-widgets make` and `fix` hand the work to `amethystora-agent`, and the
examples in `/usr/share/amethystora/widgets/examples` pass the check in `20-tests.sh`. Nothing here may
run as root or ship a widget that is on by default.

### Packages from other distributions

`amethystora-pkg` (`/usr/bin/amethystora-pkg`, a bash script; `amepkg` is the link `17-cleanup.sh`
makes, because the build's rsync skips links in `system_files`) makes distrobox containers from
templates and drives each with its own package manager. It reimplements Vanilla OS's Apx feature set
from a written description, clean-room: never read or copy Vanilla OS projects' source, help text or
artwork, and never ship their definitions or community templates. No command, menu, app or string
names Vanilla OS, Apx, VSO or Sideload; the manual says once, in `software.md` (and once in each of its translations), that `import` reads
Apx's YAML files, and `20-tests.sh` fails on any other mention. `ame pkg` runs it too, under `ame`,
the command over Amethystora's own; `amy` is a Homebrew formula, so nothing may take that name.

- Built-in templates and managers are JSON in `system_files/shared/usr/share/amethystora/pkg` (the AUR's
  `paru` and `arch-aur` under `aur/`, shown only while `~/.config/amethystora/aur` exists, which `ame
  apps aur` writes); the user's own are in `~/.local/share/amethystora/pkg`. Every built-in template
  image is pinned by digest, the pins shipping in the signed image; Renovate follows each tag's digest
  (custom manager, depType `pkg-template`) and never moves a template to a new release, which is done
  by hand with its `description`. Images are pulled by digest before `distrobox create`, so neither the
  pin nor `policy.json` can be skipped. Leave the policy's catch-all as it is, and do not re-sign third-
  party images under `ghcr.io/iarsslen`.
- `policy.json` checks `registry.opensuse.org/opensuse/leap` against openSUSE's two container keys
  (`keyPaths`, containers/image 5.33 and later), both from openSUSE's `openSUSE-build-key` package,
  whose RPM signature was checked against openSUSE's project key: `opensuse-container-key.pub`, the
  2048-bit key that signs openSUSE's published images today, converted to PEM from the package's
  OpenPGP file, and `opensuse-container-key-2023.pub`, its successor, as the package ships it. The rule
  covers Leap only, by the maintainer's choice: the rest of openSUSE's namespace holds build projects
  (infrastructure, tools, templates, Factory's staging) that sign with keys of their own. Every update
  is verified against the same file, so `20-tests.sh` has skopeo load it.
- Containers carry `amethystora.pkg.*` labels and real names `pkg-<name>`; distrobox's own
  `manager=distrobox` label stays, since distrobox, DistroShelf and Ptyxis find containers by it. Only
  labelled containers are listed or touched.
- `--json` field names are documented in `software.md#in-scripts`: keep them stable.
- AUR packages are built only after their PKGBUILD has been shown on a terminal, `--yes` or not, and are
  never upgraded unattended; the AUR's own metadata is shown first.
- `amethystora-pkg-upgrade.timer` (user, enabled with `--global`) upgrades the containers daily and,
  when its timer starts it (`$TRIGGER_UNIT`), skips a run when uupd's hardware checks would fail, with
  the thresholds of `/etc/uupd/config.json`. uupd's own distrobox module stays off there.
- A `.deb` or `.rpm` opens in `amethystora-pkg-install.desktop`, the default for both types in
  `/etc/xdg/mimeapps.list`: a ClamAV scan, provenance, and Flathub or the container's repositories
  offered first. The security report's two-week check on the containers is in
  `amethystora-security-status`, like every check.

Everything it installs is fetched on the user's machine from its source (DistroShelf from Flathub,
images from their registries, packages inside containers), so `NOTICE` and `SOURCES` do not change for
it.

### New machines

- `user-setup.hooks.d/17-welcome.sh` opens `amethystora-manual welcome` once per account, through
  `systemd-run --user`, because the setup service kills what it leaves behind. The Manual itself
  spawns nothing. Ninety seconds later, `/usr/libexec/amethystora-layout-offer` offers classic windows
  in a notification, which only `ame desktop layout classic` acts on. The classic layout is PaperWM
  turned off, remembered in `~/.config/amethystora/layout`, which `15-extensions.sh` reads so that the
  update that turns the image's extensions back on leaves PaperWM off.
- `amethystora-gpu-check.timer` offers the matching `-nvidia-open` image on a machine with an NVIDIA
  card (PCI class `0x03`, vendor `0x10de`), or the image without the driver on one without, once per
  machine, through `amethystora-notify-users --action` and `ame system rebase IMAGE STREAM`. It
  never switches by itself; its state is `/var/lib/amethystora/gpu-check`.
- `amethystora-backup` stores `amethystora-setup-manifest`'s JSON beside each backup, as a restic
  snapshot tagged `amethystora-setup` (no secrets in it), and `ame restore-setup`
  (`/usr/libexec/amethystora-restore-setup`) makes the setup again from it, each step chosen first.

### Your setup as a file

`ame setup save|diff|apply` (`/usr/libexec/amethystora-setup`, the `setup.just` group) keeps the
account's setup in `~/.config/amethystora/setup.json`: what `amethystora-setup-manifest` writes, less
the machine and everything that is an address or a script (the Flatpak remotes, the Brewfile, templates
and package managers of the account's own, the AUR's switch). A file can be shared, so it names things
only. Its settings are a fixed short list, and only where the account changed them from the image: the
layout, the dock's apps, keybindings by schema and key (the image's own custom keybindings by id, and
only their binding) and PaperWM's gaps. Never add a GNOME key that can hold a command, or a field that
is an address. The script refuses a file with a key or a name it does not know, `save` included;
`apply` shows what it adds and sets and asks first (`--yes` skips that), and takes nothing away without
`--remove`, which always asks in a terminal. `build_files/shared/test-setup.sh`, run by `20-tests.sh`
against stand-ins for flatpak, brew and GNOME, checks all of this. The manual page is `setup.md`.

### An image of your own

`iarsslen/amethystora-image-template`, a repository of its own, builds an image `FROM` the stable image,
signed with its owner's cosign key. Its build runs two scripts shipped here, so keep their arguments as
they are: `/usr/libexec/amethystora-trust-image` (`ame system trust-image` on a machine, before it
switches) writes the owner's key, a `registries.d` file and a `sigstoreSigned` policy entry for the
image's repository, and refuses Amethystora's own repositories; `/usr/libexec/amethystora-image-check`
fails a build that loosened the signature policy, carries Fedora's logo or release package, or lost the
`ame` commands, and `20-tests.sh` runs it on every Amethystora image. The image's policy takes a
repository it does not name unsigned (Fedora's `insecureAcceptAnything` for `docker`), which is why the
trust comes first. `ame system rebase` must keep taking signed images only. The manual's section is
`developer.md#an-image-of-your-own`.

### Sealed images

`:stable-sealed` is each of the four stable images sealed (`Containerfile.sealed`, after Fedora's sealed
test images, https://github.com/travier/fedora-atomic-desktops-sealed, CC0-1.0): a UKI signed with
Amethystora's Secure Boot key carries the composefs digest of the whole tree in its kernel command
line, and the initramfs mounts the system only with fs-verity required. Experimental and for new
installations only: bootc cannot move an ostree deployment to the composefs backend or back, so the
ostree images stay the default.

- **Built in the stable build job**, right after `just build-ghcr`: `just seal` builds `FROM` the local
  image, before it is rechunked. `build_files/sealed/00-sealed.sh` takes out rpm-ostree, bootupd and
  GRUB, installs systemd-boot, copies `system_files/sealed`, sets `image-tag` to `stable-sealed`, ships
  the certificate as `/usr/share/amethystora/secure-boot/amethystora-uki.der`, rebuilds the initramfs
  with dracut's `bootc` module and writes `SOURCES` again. chunkah rechunks the tree **before** the
  digest: nothing may change the tree after `bootc container ukify` (`10-uki.sh`) has read it, and the
  UKI under `/boot/EFI/Linux` is the only thing added afterwards. `20-tests-sealed.sh` checks the
  signatures, the digest and the command line. The UKI's kernel arguments are the image's `kargs.d`,
  there is no other way to add one, and they never include a debug shell.
- **Keys: shim and MOK** (the maintainer's choice of 2026-10-04, over replacing the firmware's PK, KEK
  and db). The private key is the `SECUREBOOT_KEY` secret, separate from the cosign key; its certificate
  is `secure-boot.crt`, which `just seal` checks the key against. Until both exist, and always for pull
  requests, `just seal` signs with a throwaway key and labels the image
  `org.amethystora.secure-boot-key=throwaway`, which CI never publishes. Never replace the certificate:
  every sealed machine trusts that one only.
- **Published** with gzip layers (the composefs backend cannot pull zstd:chunked yet, bootc-dev/bootc#2408),
  pushed twice, signed with cosign and attested, then removed from the runner before the rechunk needs
  the disk. It has no SBOM of its own. A failure fails a pull request, but never keeps the stable image
  from publishing (`continue-on-error`).
- **Installed** only by `iso/live/amethystora-install-sealed`, in the live ISO, since Anaconda cannot
  install the composefs backend: a whole disk, a 2 GiB ESP, a discoverable root partition (LUKS2, btrfs,
  subvolume `root`), `bootc install to-filesystem --composefs-backend`, then shim placed in
  `EFI/amethystora` in front of systemd-boot (`grubx64.efi`), a firmware boot entry, and every
  `/usr/share/amethystora/secure-boot/*.der` of the image queued with `mokutil`.
- **In the image**, a sealed machine is told apart by `/usr/share/amethystora/sealed`. It has no
  rpm-ostree, so read deployments through `/usr/libexec/amethystora-deployments`, which prints
  `rpm-ostree status --json`'s shape on both kinds of image (on a sealed one from `bootc status`,
  through pkexec and `50-amethystora-deployments.rules`), and branch on the marker for anything that
  changes kernel arguments: they cannot change there. `amethystora-signed-updates.service` does not run
  on it. The manual's `updates.md#sealed-images` describes it for users.
- **Not verified yet; do it before setting the secret.** Boot a sealed image in a VM with Secure Boot
  (`bcvk libvirt run --firmware=uefi-secure --filesystem=btrfs`, the image's certificate enrolled in the
  VM's db): `/proc/cmdline` has `composefs=`, the root mount `verity=require`, `mokutil --sb-state` says
  enabled, and a byte changed in a file under `/usr` on a copy of the disk makes it unreadable. Check
  that `bootc switch` to an unsigned image is refused (bootc does not document whether its composefs
  backend applies `policy.json` to every pull), that uupd updates it, and the live installer on real
  hardware. Older machines need a shim signed with Microsoft's 2011 CA as well as the 2023 one:
  `20-tests-sealed.sh` prints whose signatures Fedora's carries.

### COPR Package Installation

COPR packages use the `copr_install_isolated()` helper function from `build_files/shared/copr-helpers.sh`:
```bash
# Install packages from COPR with isolated repo enablement
copr_install_isolated "ublue-os/staging" package1 package2

```

This function:
1. Enables the COPR repo
2. Immediately disables it
3. Installs packages with `--enablerepo` flag to prevent repo conflicts

### Making Package Changes
1. Edit the appropriate shell script in `build_files/base/` or `build_files/dx/`
2. Add packages to the appropriate array (`FEDORA_PACKAGES` or `COPR_PACKAGES`)
3. For version-specific packages, add them in the Fedora version case statement
4. Validate shell script syntax: `bash -n build_files/base/04-packages.sh`
5. Run pre-commit hooks: `pre-commit run --all-files`
6. Test with container build if making critical changes

### Package Security Model
**CRITICAL**: Packages are split into separate arrays to prevent COPR repos from injecting malicious versions of Fedora packages:
- Fedora packages are installed first in bulk (safe)
- COPR packages are installed individually with isolated repo enablement

### Licences and trademarks

The repository is Apache-2.0, and the image is not: it redistributes other people's work on their
terms. `NOTICE` is where each of those is named, and `20-tests.sh` checks what follows.

- **A file under another licence says so.** Name it in `NOTICE` and ship its licence in
  `system_files/shared/usr/share/licenses/<project>/`. The zsh configuration is Prezto's and zimfw's
  (MIT); `50-usb-realtek-net.rules` is GPL-2.0 and says so in its first lines.
- **Credits stay as their authors wrote them.** The udev rules name who wrote each and where
  (`ublue-os/config/pull/...`); `debrand.py` leaves such comment lines alone, and so should an edit.
- **Licence texts stay in the image.** Do not delete a package's documentation without first moving
  its licence, copyright and NOTICE files, as `05-override-install.sh` does.
- **Nobody else's logo.** Not in the icon theme (`10-icons.sh`), not in the Logo Menu
  (`06-branding.sh`), not from a setup hook. Fedora's guidelines ask a remix to carry neither
  `fedora-logos` nor `fedora-release`, and to describe itself without Fedora's name: say that
  Amethystora is built on Fedora, never that it is a Fedora desktop.
- **Source travels with what asks for it.** A package from RPM Fusion, negativo17 or Copr under the
  GPL, LGPL, MPL, EPL or CDDL has its source package fetched into the image by `source-manifest.sh`.

## Configuration Files

### Key Configuration Locations
- `system_files/shared/` - System-wide configurations
- `build_files/base/` - Base image build scripts
- `build_files/dx/` - Developer experience build scripts
- `build_files/shared/` - Common build utilities
- `.github/workflows/` - CI/CD pipeline definitions

### Linting/Build Configurations
- `.pre-commit-config.yaml` - Pre-commit hook configuration
- `Justfile` - Build recipe definitions and validation
- `.github/renovate.json5` - Automated dependency updates
- `Containerfile` - Container build instructions

## Build System Deep Dive

### Justfile Structure
The `Justfile` is the central build orchestration tool with these key recipes:

**Validation Recipes:**
- `just check` - Validates Just syntax across all .just files
- `just fix` - Auto-formats Just files
- `just validate <image> <tag> <flavor>` - Validates image/tag/flavor combinations

**Build Recipes:**
- `just build <image> <tag> <flavor>` - Main build command (calls build.sh)
- `just build-ghcr <image> <tag> <flavor>` - Build for GHCR (GitHub Container Registry)
- `just rechunk <image> <tag> <flavor>` - Rechunk image for optimization
- `just seal <image> <tag> <flavor>` - The sealed variant of a built image, `localhost/<image>:<tag>-sealed`
- `just secure-boot-key` - Makes the sealed images' Secure Boot key and `secure-boot.crt`, once

**Image/Tag Definitions:**
```bash
images: amethystora, amethystora-dx
flavors: main, nvidia-open
tags: stable, latest, beta
```

**Version Detection:**
- `just fedora_version <image> <tag> <flavor>` - Dynamically detects Fedora version from upstream base images
- For `stable`: Checks `quay.io/fedora/fedora-coreos:stable` (CoreOS does not use cosign)
- For `latest`/`beta`/`gts`: Checks `ghcr.io/ublue-os/base-main:<tag>`
- A `kernel_pin` overrides the result, taking the version from the `fcNN` portion of the kernel
- Returns the Fedora major version (e.g., 43, 44)

Do not assume the streams sit on different Fedora releases. They frequently
resolve to the same major version, so anything version-dependent must key off
the value this recipe returns rather than off the stream name.

### Containerfile Multi-Stage Build
The `Containerfile` uses a multi-stage build process:

1. **Stage `ctx`** (FROM scratch): Copies all build context (system_files, build_files, etc.)
2. **Stage `base`** (FROM silverblue-main): Base Amethystora image
   - Mounts build context from `ctx` stage
   - Runs `/ctx/build_files/shared/build.sh` which executes all scripts in order
3. **dx**: not a stage of its own. `just build amethystora-dx` passes `IMAGE_FLAVOR=dx`, and
   `build.sh` runs `build-dx.sh` inside the `base` stage once the rest has finished

**Build Arguments:**
- `BASE_IMAGE_NAME` - Upstream base (silverblue/kinoite)
- `BASE_IMAGE_SHA` - Digest of the base image, resolved from `image-versions.yml`
- `FEDORA_MAJOR_VERSION` - Dynamically set by Just (43/44)
- `IMAGE_NAME` - Target image name (amethystora/amethystora-dx)
- `KERNEL` - Pinned kernel version (optional)
- `UBLUE_IMAGE_TAG` - Stream tag (stable/latest/beta)

### Base Image Pinning

`image-versions.yml` is the single source of truth for pinned upstream digests,
and every entry in it is load-bearing. `just build` reads each digest with `yq`
and passes it into the Containerfile, which builds `FROM image:tag@digest`.

Base image entries are keyed by Fedora major version and must be named
`<base_image_name>-main-<fedora_version>`, for example `silverblue-main-44`.
The key is the version `just fedora_version` resolves at build time, not the
stream name, so the pinned digest can never disagree with the version the
kernel and akmods were resolved for.

At a Fedora rollover, add a new entry before building. A missing entry fails
the build with `No digest pinned for silverblue-main-<version>` rather than
silently falling back to a floating tag.

`repo:tag@sha256:...` is valid for buildah `FROM` and for cosign, but `skopeo
inspect` and `podman manifest inspect` both reject it with "Docker references
with both a tag and digest are currently not supported". Do not "fix" a working
`FROM` on the basis of that error.

### Publishing and Image Signing

Every tag is pushed twice. podman does not send layer annotations on the first
push unless the layers already exist in the registry, so the first push of a
rechunked image produces a different manifest digest than later pushes. Pushing
each tag once left every tag on its own digest while only one of them received
the cosign signature, the SBOM and the attestation. See
[containers/podman#27796](https://github.com/containers/podman/issues/27796)
and the equivalent workaround in `ublue-os/aurora`. Do not collapse the
duplicate push.

Publishing is skipped for `pull_request` events, so PR builds validate the
image but never push. `Latest Images` publishes only on `merge_group` and
`workflow_dispatch`; there is no cron. Only `Stable Images` is scheduled
(Tuesdays 01:00 UTC). Merging directly to `main` and bypassing the merge queue
therefore publishes nothing.

### Build Script Execution Order
`build_files/shared/build.sh` runs the scripts in `build_files/base/` in this order, which is not
the numerical one. Before the first of them it removes the base image's `ublue-os-*` packages that
`system_files` replaces, and swaps Fedora's logo and release packages for Fedora's generic ones, as
its trademark guidelines ask of a remix: `fedora-logos` for `generic-logos`, and the `fedora-release`
packages for `generic-release` in the package database only, their files staying in place.
1. `00-image-info.sh` - Sets image metadata and os-release info, and takes Fedora's name out of the other release files (`/usr/lib/fedora-release`, the CPE, the software identification tags)
2. `03-install-kernel-akmods.sh` - Installs kernel and akmod packages
3. `04-packages.sh` - Installs Fedora and COPR packages
4. `05-override-install.sh` - Overrides base image packages. Among them the multimedia stack: the base image installs negativo17's FFmpeg, built with `--enable-nonfree` and labelled by FFmpeg itself "nonfree and unredistributable", and its `pipewire-libs-extra`, whose LC3plus plugin links `liblc3plus`, which has no licence to redistribute. Both are replaced with Fedora's `ffmpeg-free` and `fdk-aac-free`, RPM Fusion's `libavcodec-freeworld`, and RPM Fusion's aptX plugin. negativo17's repository is `fedora-multimedia` in the base image and outranks Fedora's, so `17-cleanup.sh` turns it off; do not install FFmpeg, codec or PipeWire packages from it. `20-tests.sh` fails on any FFmpeg library that reports itself unredistributable. The script also deletes `/usr/share/doc`, after moving the licence, copyright and NOTICE files that some 120 packages keep only there into `/usr/share/licenses`, and installs Starship from a pinned release checked against its published checksum (the pin is bumped by Renovate)
5. `06-branding.sh` - Puts the Amethystora artwork (generated by `node branding/generate.mjs`) where the boot menu, the boot splash, GDM and the Logo Menu look for it: the GRUB font, the Plymouth theme, Fedora's own logo files, which GDM, the Settings About page and the fallback splash look up by fixed path, and the Logo Menu's panel icon, which `07-debrand.sh` would only rename, not redraw. The Logo Menu ships a logo for every distribution and maker it knows of; the script removes them all and cuts the extension's two lists down to the Amethystora entry, index 0, which the dconf defaults select. `20-tests.sh` fails if another logo is left
6. `build_files/shared/build-gnome-extensions.sh` - Builds the GNOME Shell extensions from the git submodules
7. `10-icons.sh` - Installs the candy-icons icon theme from a pinned upstream commit (the pin is bumped by Renovate; see `.github/renovate.json5`). Apps the pack has no artwork for are aliased to its nearest icon; where nothing is near enough, the icon is drawn for this image in the pack's style and kept in `build_files/shared/candy-icons`, from where the script installs it into the theme. `NOTICE` names each of those icons with where its outline comes from and its licence, and `20-tests.sh` fails on one it does not name; an icon that reuses the pack's artwork, as the Security shield does, is GPL-3.0 like the pack, not Apache-2.0. The theme redraws nobody's logo: a logo is a trademark, and Mozilla, JetBrains, Anthropic and most others allow theirs unaltered or not at all. Of the pack's application icons only the drawings named in `build_files/shared/candy-icons/keep` stay, the pictograms of a job rather than of a product, and every application whose logo the pack redrew (Firefox, Thunderbird, the JetBrains IDEs and some 700 more) shows the icon it brought with it; the logos on the pack's folder, file type and status icons are removed too. Do not alias an application to another maker's logo, do not draw one for this image (Bazaar's is the one that is, and `NOTICE` says so: its maker publishes no trademark terms, which is what `keep` asks of a logo), and add a name to `keep` only after looking at the drawing; `20-tests.sh` fails on an application icon that is neither on the list nor drawn here. `user-setup.hooks.d/16-retire-jetbrains-icons.sh` takes back the links an earlier image made to the IDE drawings
8. `11-gtk-theme.sh` - Installs the Amethystora GTK theme: EliverLara's Sweet, by the author of candy-icons, with every cool colour in it rotated onto the amethyst palette by `build_files/shared/recolor.py`. It ships under Amethystora's own name because the palette is no longer Sweet's. Only the `amethystora` and `amethystora-light` themes name it in their `gtk.theme`; the rest stay on adw-gtk3, which follows the GNOME accent colour. libadwaita ignores `gtk-theme` and a Flatpak cannot see `/usr/share/themes` at all, so both are reached by `theme-set.hooks.d/20-gtk-apps.sh`: it mirrors the active theme into `~/.themes`, which `/etc/flatpak/overrides/global` grants every sandbox read-only, and writes the `~/.config/gtk-4.0/gtk.css` that imports from the mirror
9. `12-login-screen.sh` - Patches the login screen background into GNOME Shell's own stylesheet. GNOME reads it from the `#lockDialogGroup` rule inside `gnome-shell-theme.gresource` and from nowhere else, so the bundle is unpacked, the rule appended and the bundle rebuilt. The picture is the crown the boot splash ends on, as sharp as the splash draws it and without the gem, drawn by `branding/generate.mjs`
10. `12-tour.sh` - Swaps the picture on GNOME Tour's first page, which Fedora builds with Fedora's logo on it, for Amethystora's, in the resource bundle the Tour reads its pictures from (`/usr/share/gnome-tour/resources.gresource`), unpacked and rebuilt as `12-login-screen.sh` does. The picture is the boot splash at the top of its glow, drawn by `branding/generate.mjs` into `/usr/share/amethystora/tour/welcome.svg`
11. `13-manual.sh` - Installs the runtime of the Amethystora Manual (`amethystora-manual`, `Super+F1`): a pinned Electron release, checked against the checksum Electron publishes, and a pinned `marked` from the npm registry, checked against its integrity. Both are bumped by Renovate. It also adds Quicksand for the wordmark, from `branding/fonts`, keeps Chromium's own `.pak` only for the languages the apps are translated into, and writes the apps' launchers in those languages (`translate-desktop.py`). The app itself is `system_files/shared/usr/lib/amethystora-manual/resources/app` and its pages are `system_files/shared/usr/share/amethystora/manual`
12. `14-security.sh` - Installs the runtime of Amethystora Security (`amethystora-security`), the security report and virus scanner that replace the report's terminal launcher and ClamUI: hard links to the Manual's Electron, so that the image carries one Electron for both, and Quicksand for its wordmark from `branding/fonts`, which the `ctx` stage copies in. The app itself is `system_files/shared/usr/lib/amethystora-security/resources/app`; the report it draws is `/usr/libexec/amethystora-security-status`, which `ame security status` prints. It also derives network protection's Suricata configuration (`/usr/share/amethystora/ips/suricata.yaml`) from the one the suricata package ships, with `build_files/shared/ips-config.py`, so that it fits Suricata 7 and 8 alike, and compiles `po/*.po`, the report's and the app permissions' translations, into `/usr/share/locale/<language>/LC_MESSAGES/amethystora.mo` with `msgfmt --check`
13. `15-update.sh` - Installs the runtime of System Updates (`amethystora-update`), the window that replaces upstream's System Update launcher, a terminal on `ujust update`: the same hard links to the Manual's Electron and the same Quicksand as `14-security.sh`. The app itself is `system_files/shared/usr/lib/amethystora-update/resources/app`; upstream's launcher is not shipped
14. `16-notes.sh` - Installs the runtime of Amethystora Notes (`amethystora-notes`), the encrypted notes and tasks app that replaces Joplin and Planify: the same hard links to the Manual's Electron and the same Quicksand as `14-security.sh`, and a hard link to the Manual's `marked`. The app itself is `system_files/shared/usr/lib/amethystora-notes/resources/app`
15. `16-logs.sh` - Installs the runtime of Amethystora Logs (`amethystora-logs`), the journal viewer that replaces GNOME Logs: the same hard links to the Manual's Electron and the same Quicksand as `14-security.sh`. The app itself is `system_files/shared/usr/lib/amethystora-logs/resources/app`; GNOME Logs is left off the Flatpak list
16. `16-backups.sh` - Installs the runtime of Amethystora Backups (`amethystora-backups`), the window that goes back through the hourly snapshots and the restic backup and puts files back: the same hard links to the Manual's Electron and `i18n.js` and the same Quicksand as `14-security.sh`. The app itself is `system_files/shared/usr/lib/amethystora-backups/resources/app`; what it shows is `/usr/libexec/amethystora-restore`'s
17. `16-control.sh` - Installs the runtime of Amethystora Control (`amethystora-control`), the window for Amethystora's own settings outside security: the same hard links to the Manual's Electron and the same Quicksand as `14-security.sh`. The app itself is `system_files/shared/usr/lib/amethystora-control/resources/app`; what it lists is `/usr/libexec/amethystora-control-list`, which `ame control` prints
18. `07-debrand.sh` - Renames every remaining Universal Blue file, command, service and reference to Amethystora (logic in `build_files/shared/debrand.py`; `20-tests.sh` fails the build if any is left). Licence files, copyright lines and the comments that credit an author keep upstream's names
19. `08-hardening.sh` - Signature-verified updates, firewall default zone, account lockout, Parental Controls' allowed hours at the text consoles and over SSH (see Logins), kernel lockdown, and the sudo PATH that `ublue-os/main` leaves open. The polkit and udev fixes are made in the files themselves (`org.amethystora.privileged.user.setup.policy`, `50-zsa.rules`). Lockdown is skipped on the NVIDIA images, whose driver is an akmods build signed with the machine owner key: forcing lockdown on a machine with Secure Boot off would leave it without a graphics driver. With Secure Boot on, Fedora's kernel locks itself down whatever the arguments say (`20-tests.sh` checks its config), so the argument only matters without; `ame security lockdown` adds or takes it off per machine. The settings that are plain files live in `system_files/shared` (`usr/lib/sysctl.d`, `usr/lib/modprobe.d`, `usr/lib/bootc/kargs.d`, `etc/ssh/sshd_config.d`, `etc/security/faillock.conf`, `etc/flatpak/overrides/global`, `etc/audit/rules.d`)
20. `17-cleanup.sh` - Cleanup operations, and the systemd units the image enables, the per-user ones with `systemctl --global` (`amethystora-pkg-upgrade.timer`, `amethystora-update-alert.service`, `amethystora-dns-portal.service`). It also makes the `amepkg` link, since the build's rsync skips links in `system_files`. Two things here are deliberately *disabled*: `input-remapper.service`, which runs as root and reads every input device, and `usbguard.service`, which would block the keyboard on a machine where nobody had allowed it yet. Both are turned on per machine by an `ame security` command (`usb`, `input-remapper`). So are `waydroid-container.service` and `scx_loader.service` (`ame apps android`, `ame system scheduler`). It enables `fwupd-refresh.timer`, which Fedora leaves to GNOME Software, and the pools of disks' `amethystora-raid-check.timer` and `amethystora-raid-scrub.timer`
21. `18-workarounds.sh` - Temporary fixes/workarounds
22. `19-initramfs.sh` - Regenerates initramfs, adding dracut's `tpm2-tss` module where dracut has it so that `ame security disk-unlock` can hand the disk key to the TPM
23. `build_files/shared/build-dx.sh` - dx only: copies `system_files/dx`, runs `build_files/dx/00-dx.sh` and then `01-tests-dx.sh`
24. `build_files/shared/source-manifest.sh` - Writes `/usr/share/licenses/amethystora/SOURCES`: every package with its licence, source package and where that source is, which the GPL asks for and the written offer in `NOTICE` points to. Fedora keeps its own in Koji. RPM Fusion, negativo17 and Copr publish only their current builds, so the script fetches the source packages of theirs that are under a licence asking for the source into `/usr/src/amethystora`, and the build fails when one cannot be fetched; a Copr project the image starts installing from goes in its `COPR_PROJECTS`. NVIDIA's own repository, which the NVIDIA images take the container toolkit from, publishes no source packages at all, so its packages are listed with the address of their source instead (`NO_SOURCE_PACKAGES`); a GPL package from any other maker the script does not know still fails the build. `20-tests.sh` fails if a package is missing from the list or a source package from the image
25. `20-tests.sh` - Runs last, after the repositories are validated and the build cleaned up; fails the build on anything missing or left behind, including a GNOME Shell extension shipped without its licence

The sealed images then run `build_files/sealed/` from `Containerfile.sealed`, on the finished image (see Sealed images).

## Development Guidelines

### Making Changes
1. **ALWAYS validate first:** `just check && pre-commit run --all-files`
2. **Make minimal modifications** - prefer configuration over code changes
3. **Test formatting:** `just fix` to auto-format
4. **Avoid full container builds** unless specifically testing container changes
5. **Focus on system_files/ changes** for most user-facing modifications

### File Editing Best Practices
- **JSON files**: Validate syntax with `pre-commit run check-json`
- **YAML files**: Validate syntax with `pre-commit run check-yaml`
- **Justfile**: Always run `just check` after modifications
- **Shell scripts**: Follow existing patterns in build_files/

### Common Modification Patterns
- **Adding packages**: Edit `build_files/base/04-packages.sh`, add to appropriate array
- **System configuration**: Modify files in `system_files/shared/`
- **Build logic**: Edit scripts in `build_files/base/` or `build_files/dx/`
- **CI/CD**: Modify workflows in `.github/workflows/`

## Trust These Instructions

**The information in this document has been validated against the current repository state.** Only search for additional information if:
- Instructions are incomplete for your specific task
- You encounter errors not covered in the workarounds section
- Repository structure has changed significantly

This repository is complex but well-structured. Following these instructions will significantly reduce build failures and exploration time.

## Dependency Updates (Renovate)

Renovate is configured in `.github/renovate.json5` and tracks its work on the
Dependency Dashboard, issue #2680.

Never hand-edit a `renovate/*` branch and never merge `main` into one. Renovate
will not update or replace a branch it no longer owns; the PR moves to "PR
Edited (Blocked)" on the dashboard and that dependency silently stops updating.
Nothing about the PR looks wrong from the outside, so this is only visible on
the dashboard. `rebaseWhen` is set to `behind-base-branch` so Renovate keeps its
own branches current and there is no reason to touch them by hand.

Closing a Renovate PR is not a fix either. It moves the entry to "PR Closed
(Blocked)" and Renovate stops recreating it. Only close one once the dependency
has actually been updated by other means, and say so in the closing comment.

Renovate PRs are authored by `app/ubot-7274`, not `app/renovate`. Filtering by
the latter silently returns nothing.

## Other Rules that are Important to the Maintainers

- Ensure that [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/#specification) are used and enforced for every commit and pull request title.
- Always be surgical with the least amount of code, the project strives to be easy to maintain.
- This project is published at iarsslen/amethystora
- The desktop layer is maintained here, in `system_files/shared`; it is not pulled from upstream

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

Example:

```text
Assisted-by: Claude 3.5 Sonnet via GitHub Copilot
```
