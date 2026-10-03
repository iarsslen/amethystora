# Amethystora Copilot Instructions

This document provides essential information for coding agents working with the Amethystora repository to minimize exploration time and avoid common build failures.

## Repository Overview

**Amethystora** is a cloud-native desktop operating system, based on Bluefin and maintained by Arsslen Idadi (@iarsslen). It is an OS built on Fedora Linux using container technologies with atomic updates.

- **Type**: Container-based Linux distribution build system
- **Base**: `ghcr.io/ublue-os/silverblue-main` (Fedora with the GNOME desktop and GDM) + Universal Blue infrastructure; GNOME Shell extensions are git submodules under `system_files/shared/usr/share/gnome-shell/extensions`, built by `build_files/shared/build-gnome-extensions.sh`
- **Languages**: Bash scripts, JSON configuration, Python utilities
- **Build System**: Just (command runner), Podman/Docker containers, GitHub Actions
- **Target**: desktop OS with two variants (base + developer experience)

## Repository Structure

### Root Directory Files
- `Containerfile` - Main container build definition (stages: `ctx`, `brew`, `base`)
- `Justfile` - Build automation recipes (like a Makefile but more readable)
- `.pre-commit-config.yaml` - Pre-commit hooks for basic validation
- `image-versions.yml` - Image version configurations
- `cosign.pub` - Container signing public key

### Key Directories
- `system_files/` - Files copied into the image, overlaid on those of the upstream layers
  - `shared/` - Every image: configurations, fonts, themes, the manual, `ujust` recipes
  - `dx/` - `amethystora-dx` only, copied in by `build_files/shared/build-dx.sh`
- `build_files/` - Build scripts organized as base/, dx/, shared/
  - `base/` - Base image build scripts (00-image-info.sh through 20-tests.sh)
  - `dx/` - Developer experience build scripts
  - `shared/` - Common build utilities and helper scripts
- `branding/` - Source of the artwork; `node branding/generate.mjs` draws it
- `iso/` - `iso.toml`, the bootc-image-builder configuration of the installer ISO; `product/`, which `build-iso.yml` adds to the ISO as `images/product.img`: the installer's Amethystora look (a stylesheet and artwork drawn by `branding/generate.mjs`), crash reporting (libreport files that send crash reports to Amethystora's issue tracker instead of Fedora's Bugzilla) and the Anaconda profile that keeps Fedora's installer settings although the installer's os-release says `generic`; and `installer-packages.py`, which lists what the installer is made of
- `.github/workflows/` - Comprehensive CI/CD pipelines

The desktop layer Amethystora took from Bluefin's `projectbluefin/common` (the `ujust` recipes,
the Homebrew Brewfiles, the setup services and hooks, the GNOME defaults, udev rules) is kept in
`system_files/shared`, already renamed; Bluefin is not a build input. Only `ublue-os/brew`, for
Homebrew's own setup, is still copied in by the `ctx` stage of the `Containerfile`. Where to edit:
- `system_files/shared/usr/share/amethystora/just/` - the `ujust` recipes; `60-custom.just` holds the ones written for Amethystora
- `system_files/shared/usr/share/amethystora/homebrew/system-flatpaks.Brewfile` - the default Flatpak list (no browser, Firefox is in the image; Amethystora Logs in place of GNOME Logs)
- `system_files/shared/usr/share/flatpak/preinstall.d/` - Flatpaks installed on every machine
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
- `reusable-build.yml` - Core build logic for all image variants
- `generate-release.yml` - Generates release artifacts and changelogs
- `build-iso.yml` - Builds the installer ISO of a stable image with bootc-image-builder and uploads it, with its checksum signed by cosign, to Cloudflare R2 (a Release asset is limited to 2 GiB). `Stable Images` runs it after scheduled and dispatched builds, once for `amethystora` and once for `amethystora-dx`, each upload replacing the last under the same name; the NVIDIA images have no ISO, and the workflow fails on any other image. A pull request that changes it only builds `amethystora`'s. bootc-image-builder picks the installer's packages by os-release `ID` and has no definition for `amethystora`, so the workflow runs its container by hand and writes Fedora's definition out under that name, with `generic-logos` and `generic-release` added so that the installer carries neither `fedora-logos` nor `fedora-release`; do not switch back to its GitHub action, which cannot. `iso/installer-packages.py` then lists the installer's packages from the builder's manifest for the ISO to carry beside `LICENSE` and `NOTICE`, and fails the workflow before the upload if one of Fedora's two is among them. The builder is pinned by digest to its last build that reads definitions from a folder; its successor compiles them in, so moving to it means rewriting that step
- `validate-renovate.yml` - Validates the Renovate configuration on pull requests
- `scorecard.yml` - OpenSSF Scorecard supply-chain checks (weekly)
- `clean.yml` - Cleanup old images and artifacts
- `moderator.yml` - Repository moderation tasks

**Workflow Architecture:**

- Stream-specific workflows (stable, latest, beta) call `reusable-build.yml`
- `reusable-build.yml` builds both base and dx variants for all flavors (main, nvidia-open)
- Fedora version is dynamically detected based on stream tag
- Images are signed with cosign and pushed to GHCR

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
- `build_files/dx/00-dx.sh` - Developer experience package additions. The editor is VSCodium, from its repository with the key pinned in `system_files/dx/etc/pki/rpm-gpg`: Microsoft's VS Code licence does not allow it to be shared inside a published image, so do not bring it back

### The browser

The browser is Firefox, Fedora's package, installed by `04-packages.sh` so that a machine has one
before it is online. Mozilla lets Firefox be redistributed only unaltered, so it ships exactly as
Fedora builds it: do not add a `policies.json`, an extension, a preference file or a home page for
it, in the image or from a setup hook (`20-tests.sh` fails on a policy file). That is why the image
has no browser policy and installs no extension. Brave, the browser before it, is not in the image
and not on the Flatpak lists: its terms license its package for personal use, not for
redistribution. Like every other browser, it is the user's to install from Bazaar.

Browser protection, the extension allowlist and the block on WebUSB, WebSerial, WebHID and Web
Bluetooth, is opt-in for the same reason: a policy the machine's owner turns on is theirs, not the
image's. `ujust setup-browser-protection` runs `/usr/libexec/amethystora-browser-policy`, which
writes `usr/share/amethystora/browser-policy/chromium.json` or `firefox.json`, with the IDs in
`/etc/amethystora/browser-extensions` added, to every place in its `TARGETS` table: Brave, Chrome,
Chromium, Edge and Firefox, as packages and as Flatpaks. To cover another browser, add its line
there. Keep the Firefox forks out: a system policy replaces the one they ship. The policies only
allow extensions and must never install one. The Security report reads the helper's `status`.

### Agentic features

Every image, base and dx, ships `amethystora-agent`, the launcher behind `Super+Ctrl+Shift+A` and
the menu's "Ask an agent". Claude Code and opencode are deliberately not in the image: they release
far more often than it does, so the launcher installs the chosen one into the user's home with its
maker's installer on first launch (or `ujust install-agent`), where it updates on the user's terms.
Do not add them back to `04-packages.sh`; `20-tests.sh` fails if either appears in `/usr/bin`. The
skill in `system_files/shared/usr/share/amethystora/agents/skills/amethystora/SKILL.md` tells
agents how to change *a user's machine* safely: this repository is where it is written, not a place
it applies to. `amethystora-diagnose/SKILL.md` beside it is the read-only method behind
`amethystora-agent diagnose`. `user-setup.hooks.d/13-agentic.sh` links every skill there into
`~/.claude/skills`, the one
directory both agents read (opencode requires skill names to be unique across its skill directories). The features are on by
default. `ujust toggle-agentic` turns them off per user by writing
`~/.config/amethystora/no-agentic`. Keep the skill accurate when you change a command, path or
recipe that it names.

### The manual

The Amethystora Manual (`amethystora-manual`, `Super+F1`, "Manual" in the Amethystora menu) is the
user documentation, shipped in the image so that it always describes the image it is on. Its pages
are the Markdown files in `system_files/shared/usr/share/amethystora/manual`, listed and grouped in
`pages.json`; the hotkeys page is `keybindings.md` one level up, which `ujust keybindings` also
shows. **Keep the manual accurate** when you change a command, recipe, hotkey, path or default that
it describes, and add to it when you add something a user would look for there.

- Link between pages as files (`updates.md#rolling-back`). `build_files/shared/check-manual.js`
  runs in `20-tests.sh` and fails the build on a page that is missing or a link that lands nowhere.
- `07-debrand.sh` rewrites every Bluefin or Universal Blue name in the image except on a line that
  also carries a copyright or licence phrase, or a comment that opens with a credit (`# Written by`,
  `# Modified by`, `# Source:`), so upstream is credited only that way (`about.md`).
- The window is an Electron app in `system_files/shared/usr/lib/amethystora-manual/resources/app`.
  It only loads its own pages, opens web links in the browser, and follows the theme's palette.
  `13-manual.sh` adds the pinned Electron and `marked` it runs on. The sidebar draws the same wordmark
  as Security, from its own copy of `gem.svg`.

### The Security app

Amethystora Security (`amethystora-security`, **Security** in the app grid) is the security report and
the virus scanner, in place of the report's terminal launcher and ClamUI. Its checks live in one
script, `system_files/shared/usr/libexec/amethystora-security-status`: `ujust security-status` prints
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
`REALTIME=on`) reads the audit log per key, the journal, `/etc` against `/usr/etc`, setuid files outside
`/usr` and listening ports, writes what only root can see to `/var/lib/amethystora/security/status.json`
for the report, and runs the report to notify when a watched check turns bad. A new audit key in
`60-amethystora.rules` has to be added to the watcher and to `amethystora-security-realtime`;
`20-tests.sh` fails otherwise.
The sidebar draws the boot splash's wordmark live, from `gem.svg` (written by `branding/generate.mjs`)
and Quicksand, with the generator's own sizes and glow.

### The Updates app

System Updates (`amethystora-update`) replaces upstream's System Update launcher, which opened a
terminal on `ujust update`; the recipe stays for the terminal. **Update now** starts
`uupd-manual.service`, the same updater the automatic updates run, which the `uupd.rules` the uupd
package ships lets anyone start without a password (the ublue-os/packages build installs it in
`/etc/polkit-1/rules.d`, not `/usr/share`). The window never runs `bootc`, `flatpak` or `brew`
itself. It follows uupd's JSON log in the journal and reads the deployments from `rpm-ostree status`.
If uupd changes the `Updating`, `module_fail` or `Updates Completed Successfully` messages it logs,
update `main.js` to match. The top bar draws the same wordmark as Security, from its own copy of
`gem.svg`.

### The Logs app

Amethystora Logs (`amethystora-logs`, **Logs** in the app grid) replaces GNOME Logs, which
`system-flatpaks.Brewfile` leaves out and `system-setup.hooks.d/21-retire-gnome-logs.sh` uninstalls,
once, from a machine that already had it. It is read-only: it runs
`journalctl` as the user, and nothing else, so administrators (`wheel`) see the whole machine and
anyone else their own session. `main.js` builds every `journalctl` argument from the page's choices:
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
  (MIT); `fish_prompt.fish` and `50-usb-realtek-net.rules` are GPL-2.0 and say so in their first lines.
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
11. `13-manual.sh` - Installs the runtime of the Amethystora Manual (`amethystora-manual`, `Super+F1`): a pinned Electron release, checked against the checksum Electron publishes, and a pinned `marked` from the npm registry, checked against its integrity. Both are bumped by Renovate. It also adds Quicksand for the wordmark, from `branding/fonts`. The app itself is `system_files/shared/usr/lib/amethystora-manual/resources/app` and its pages are `system_files/shared/usr/share/amethystora/manual`
12. `14-security.sh` - Installs the runtime of Amethystora Security (`amethystora-security`), the security report and virus scanner that replace the report's terminal launcher and ClamUI: hard links to the Manual's Electron, so that the image carries one Electron for both, and Quicksand for its wordmark from `branding/fonts`, which the `ctx` stage copies in. The app itself is `system_files/shared/usr/lib/amethystora-security/resources/app`; the report it draws is `/usr/libexec/amethystora-security-status`, which `ujust security-status` prints. It also derives network protection's Suricata configuration (`/usr/share/amethystora/ips/suricata.yaml`) from the one the suricata package ships, with `build_files/shared/ips-config.py`, so that it fits Suricata 7 and 8 alike
13. `15-update.sh` - Installs the runtime of System Updates (`amethystora-update`), the window that replaces upstream's System Update launcher, a terminal on `ujust update`: the same hard links to the Manual's Electron and the same Quicksand as `14-security.sh`. The app itself is `system_files/shared/usr/lib/amethystora-update/resources/app`; upstream's launcher is not shipped
14. `16-notes.sh` - Installs the runtime of Amethystora Notes (`amethystora-notes`), the encrypted notes and tasks app that replaces Joplin and Planify: the same hard links to the Manual's Electron and the same Quicksand as `14-security.sh`, and a hard link to the Manual's `marked`. The app itself is `system_files/shared/usr/lib/amethystora-notes/resources/app`
15. `16-logs.sh` - Installs the runtime of Amethystora Logs (`amethystora-logs`), the journal viewer that replaces GNOME Logs: the same hard links to the Manual's Electron and the same Quicksand as `14-security.sh`. The app itself is `system_files/shared/usr/lib/amethystora-logs/resources/app`; GNOME Logs is left off the Flatpak list
16. `07-debrand.sh` - Renames every remaining Bluefin / Universal Blue file, command, service and reference to Amethystora (logic in `build_files/shared/debrand.py`; `20-tests.sh` fails the build if any is left). Licence files, copyright lines and the comments that credit an author keep upstream's names
17. `08-hardening.sh` - Signature-verified updates, firewall default zone, account lockout, kernel lockdown, and the sudo PATH that `ublue-os/main` leaves open. The polkit and udev fixes are made in the files themselves (`org.amethystora.privileged.user.setup.policy`, `50-zsa.rules`). Lockdown is skipped on the NVIDIA images, whose driver is an akmods build signed with the machine owner key: forcing lockdown on a machine with Secure Boot off would leave it without a graphics driver. The settings that are plain files live in `system_files/shared` (`usr/lib/sysctl.d`, `usr/lib/modprobe.d`, `usr/lib/bootc/kargs.d`, `etc/ssh/sshd_config.d`, `etc/security/faillock.conf`, `etc/flatpak/overrides/global`, `etc/audit/rules.d`)
18. `17-cleanup.sh` - Cleanup operations, and the systemd units the image enables. Two things here are deliberately *disabled*: `input-remapper.service`, which runs as root and reads every input device, and `usbguard.service`, which would block the keyboard on a machine where nobody had allowed it yet. Both are turned on per machine by a `ujust` recipe
19. `18-workarounds.sh` - Temporary fixes/workarounds
20. `19-initramfs.sh` - Regenerates initramfs, adding dracut's `tpm2-tss` module where dracut has it so that `ujust setup-disk-unlock` can hand the disk key to the TPM
21. `build_files/shared/build-dx.sh` - dx only: copies `system_files/dx`, runs `build_files/dx/00-dx.sh` and then `01-tests-dx.sh`
22. `build_files/shared/source-manifest.sh` - Writes `/usr/share/licenses/amethystora/SOURCES`: every package with its licence, source package and where that source is, which the GPL asks for and the written offer in `NOTICE` points to. Fedora keeps its own in Koji. RPM Fusion, negativo17 and Copr publish only their current builds, so the script fetches the source packages of theirs that are under a licence asking for the source into `/usr/src/amethystora`, and the build fails when one cannot be fetched; a Copr project the image starts installing from goes in its `COPR_PROJECTS`. NVIDIA's own repository, which the NVIDIA images take the container toolkit from, publishes no source packages at all, so its packages are listed with the address of their source instead (`NO_SOURCE_PACKAGES`); a GPL package from any other maker the script does not know still fails the build. `20-tests.sh` fails if a package is missing from the list or a source package from the image
23. `20-tests.sh` - Runs last, after the repositories are validated and the build cleaned up; fails the build on anything missing or left behind, including a GNOME Shell extension shipped without its licence

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
- This project is published at iarsslen/amethystora; upstream Bluefin documentation lives in ublue-os/bluefin-docs
- The desktop layer taken from projectbluefin/common is maintained here, in `system_files/shared`; it is no longer pulled from upstream

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

Example:

```text
Assisted-by: Claude 3.5 Sonnet via GitHub Copilot
```
