# Amethystora Copilot Instructions

This document provides essential information for coding agents working with the Amethystora repository to minimize exploration time and avoid common build failures.

## Repository Overview

**Amethystora** is a cloud-native desktop operating system, based on Bluefin and maintained by Arsslen Idadi (@iarsslen). It is an OS built on Fedora Linux using container technologies with atomic updates.

- **Type**: Container-based Linux distribution build system (75MB total, 74MB system files)
- **Base**: `ghcr.io/ublue-os/silverblue-main` (Fedora with the GNOME desktop and GDM) + Universal Blue infrastructure; GNOME Shell extensions are git submodules under `system_files/shared/usr/share/gnome-shell/extensions`, built by `build_files/shared/build-gnome-extensions.sh`
- **Languages**: Bash scripts, JSON configuration, Python utilities
- **Build System**: Just (command runner), Podman/Docker containers, GitHub Actions
- **Target**: desktop OS with two variants (base + developer experience)

## Repository Structure

### Root Directory Files
- `Containerfile` - Main container build definition (stages: `ctx`, `common`, `brew`, `base`)
- `Justfile` - Build automation recipes (33KB - like Makefile but more readable)
- `.pre-commit-config.yaml` - Pre-commit hooks for basic validation
- `image-versions.yml` - Image version configurations
- `cosign.pub` - Container signing public key

### Key Directories
- `system_files/` (74MB) - User-space files, configurations, fonts, themes
- `build_files/` - Build scripts organized as base/, dx/, shared/
  - `base/` - Base image build scripts (00-image-info.sh through 19-initramfs.sh)
  - `dx/` - Developer experience build scripts
  - `shared/` - Common build utilities and helper scripts
- `.github/workflows/` - Comprehensive CI/CD pipelines
- `just/` - Additional Just recipes for apps and system management
- `brew/` - Homebrew Brewfile definitions for various tool collections
- `flatpaks/` - Flatpak application lists (system-flatpaks.list, system-flatpaks-dx.list)

### Architecture
- **Two Build Targets**: `base` (regular users) and `dx` (developer experience)
- **Image Flavors**: main, nvidia-open
- **Fedora Versions**: 42, 43 supported
- **Stream Tags**: `latest` (F42/43), `beta` (F42/43), `stable` (F42)
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
- `build-image-beta.yml` - Builds beta images for testing F42/F43
- `reusable-build.yml` - Core build logic for all image variants
- `generate-release.yml` - Generates release artifacts and changelogs
- `validate-brewfiles.yml` - Validates Homebrew Brewfile syntax
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
- `build_files/dx/00-dx.sh` - Developer experience package additions

### Agentic features

Every image, base and dx, installs Claude Code and opencode (`04-packages.sh`) and ships
`amethystora-agent`, the launcher behind `Super+Ctrl+Shift+A` and the menu's "Ask an agent". The
skill in `system_files/shared/usr/share/amethystora/agents/skills/amethystora/SKILL.md` tells
agents how to change *a user's machine* safely: this repository is where it is written, not a place
it applies to. `user-setup.hooks.d/13-agentic.sh` links it into `~/.claude/skills`, the one
directory both agents read (opencode requires skill names to be unique across its skill directories). The features are on by
default. `ujust toggle-agentic` turns them off per user by writing
`~/.config/amethystora/no-agentic`. Keep the skill accurate when you change a command, path or
recipe that it names.

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
Scripts in `build_files/base/` execute in numerical order:
1. `00-image-info.sh` - Sets image metadata and os-release info
2. `03-install-kernel-akmods.sh` - Installs kernel and akmod packages
3. `04-packages.sh` - Installs Fedora and COPR packages
4. `05-override-install.sh` - Overrides base image packages
5. `06-branding.sh` - Replaces the Bluefin branding from projectbluefin/common with Amethystora (artwork is generated by `node branding/generate.mjs`). This includes the pictures the upstream layers ship under names that say nothing about Bluefin or Universal Blue — Fedora's own logo files, which GDM, the Settings About page and the fallback splash look up by fixed path, and the Logo Menu's panel icon — because `07-debrand.sh` renames names, not artwork. The build fails if a logo arrives in one of those directories without an Amethystora replacement.
6. `build_files/shared/build-gnome-extensions.sh` - Builds the GNOME Shell extensions from the git submodules
7. `09-desktop.sh` - Tiling keybindings, the panel command menu and the rest of the desktop defaults
8. `10-icons.sh` - Installs the candy-icons icon theme from a pinned upstream commit (the pin is bumped by Renovate; see `.github/renovate.json5`). Apps the pack has no artwork for are aliased to its nearest icon; where nothing is near enough, the icon is drawn for this image in the pack's style and kept in `build_files/shared/candy-icons`, from where the script installs it into the theme
9. `11-gtk-theme.sh` - Installs the Amethystora GTK theme: EliverLara's Sweet, by the author of candy-icons, with every cool colour in it rotated onto the amethyst palette by `build_files/shared/recolor.py`. It ships under Amethystora's own name because the palette is no longer Sweet's. Only the `amethystora` and `amethystora-light` themes name it in their `gtk.theme`; the rest stay on adw-gtk3, which follows the GNOME accent colour. libadwaita ignores `gtk-theme` and a Flatpak cannot see `/usr/share/themes` at all, so both are reached by `theme-set.hooks.d/20-gtk-apps.sh`: it mirrors the active theme into `~/.themes`, which `/etc/flatpak/overrides/global` grants every sandbox read-only, and writes the `~/.config/gtk-4.0/gtk.css` that imports from the mirror
10. `12-login-screen.sh` - Patches the login screen background into GNOME Shell's own stylesheet. GNOME reads it from the `#lockDialogGroup` rule inside `gnome-shell-theme.gresource` and from nowhere else, so the bundle is unpacked, the rule appended and the bundle rebuilt. The picture is the sky the boot splash ends on, blurred and without the gem, drawn by `branding/generate.mjs`
11. `07-debrand.sh` - Renames every remaining Bluefin / Universal Blue file, command, service and reference to Amethystora (logic in `build_files/shared/debrand.py`; `20-tests.sh` fails the build if any is left)
12. `08-hardening.sh` - Signature-verified updates, firewall default zone, account lockout, the Brave enterprise policy, kernel lockdown, and the fixes to what the upstream layers leave open (polkit, sudoers, udev). Lockdown is skipped on the NVIDIA images, whose driver is an akmods build signed with the machine owner key: forcing lockdown on a machine with Secure Boot off would leave it without a graphics driver. The settings that are plain files live in `system_files/shared` (`usr/lib/sysctl.d`, `usr/lib/modprobe.d`, `usr/lib/bootc/kargs.d`, `etc/ssh/sshd_config.d`, `etc/security/faillock.conf`, `etc/flatpak/overrides/global`, `etc/audit/rules.d`, `etc/brave/policies/managed`)
13. `17-cleanup.sh` - Cleanup operations, and the systemd units the image enables. Two things here are deliberately *disabled*: `input-remapper.service`, which runs as root and reads every input device, and `usbguard.service`, which would block the keyboard on a machine where nobody had allowed it yet. Both are turned on per machine by a `ujust` recipe
14. `18-workarounds.sh` - Temporary fixes/workarounds
15. `19-initramfs.sh` - Regenerates initramfs, adding dracut's `tpm2-tss` module where dracut has it so that `ujust setup-disk-unlock` can hand the disk key to the TPM

### Additional Recipe Collections
- `just/bluefin-apps.just` - User-facing app management recipes
- `just/bluefin-system.just` - System management recipes
- `brew/*.Brewfile` - Homebrew package collections (ai, cli, fonts, k8s)

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
- Changes to the shared desktop layer belong upstream in projectbluefin/common

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

Example:

```text
Assisted-by: Claude 3.5 Sonnet via GitHub Copilot
```
