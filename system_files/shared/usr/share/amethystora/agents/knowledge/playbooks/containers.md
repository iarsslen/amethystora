# A container or its app fails

## Symptom

A container that `amepkg` (`amethystora-pkg`) made does not start, cannot install or upgrade, or its app
is missing from the app grid or does not open; System Updates shows a failed **Containers** step; or the
security report says a container went two weeks without an upgrade.

## Look

- `state health` (finding `containers`), `state software` (the containers, their templates and upgrades).
- `logs` user_unit `amethystora-pkg-upgrade.service`; identifier `amethystora-pkg-upgrade` has one JSON
  line per container and run.
- As the user, never with sudo:
  - `amepkg containers list --json`: `status`, `image`, `last_upgrade`, `last_upgrade_result`,
    `exported_apps`, `aur_pending`
  - `amepkg templates list --json`: `pinned`, `verified`
  - `systemctl --user status amethystora-pkg-upgrade.timer amethystora-pkg-upgrade.service`
  - `podman ps -a`, `podman system df`, `df -h /var/home`

## Causes on Amethystora

1. **The daily upgrade held back.** Started by `amethystora-pkg-upgrade.timer`, `amepkg upgrade-all` skips
   a run on a low battery, under load, short of memory or offline, with uupd's thresholds from
   `/etc/uupd/config.json`. Tell: the journal says "Not upgrading the containers now: …".
2. **One container's upgrade failed**: a mirror, a held package, a full disk. The others, and the system's
   update, are not affected. Tell: `last_upgrade_result` `failed`, and the package manager's lines before
   it. On Arch, `update` only refreshes the lists; `upgrade` is the one to run.
3. **AUR packages wait for a person.** The daily run never upgrades what came from the AUR: each version
   is a new PKGBUILD to read. Tell: `aur_pending` is not empty.
4. **The image was refused or not found.** Built-in templates are pinned by digest inside the signed image,
   and `/etc/containers/policy.json` checks the toolbx images and openSUSE Leap against their publishers'
   keys in `/usr/lib/pki/containers`. Tell: "podman could not pull …", with "signature", "manifest
   unknown" or a network error. A template of the user's own, neither pinned nor checked, is listed
   `unverified` and asks before it is used.
5. **The app is missing or does not open.** Its launcher is `~/.local/share/applications/<container>-…`,
   written by `distrobox-export`. Tell: `exported_apps` lacks it; `amepkg NAME run COMMAND` shows the
   program's own error.
6. **Podman's storage.** A full home disk, or storage from an older podman after an image update changed
   its version. Tell: `podman system df`, `df -h`; errors naming the storage, the OCI runtime or user
   namespaces.
7. **Run with sudo.** Root's podman has none of the user's containers, so the list is empty.
8. **Not one of amepkg's.** Distrobox containers made by hand are neither listed nor upgraded (no `pkg-`
   prefix in `podman ps -a`). Leave those alone.

## Fix

### 1 and 2. Upgrades

- `amepkg upgrade-all` runs now and holds back for nothing; `amepkg NAME upgrade` does one. **Update now**
  in System Updates (`amethystora-update`) does the same after the system.
- For a failure, read the package manager's message, then `amepkg NAME clean` and `amepkg NAME upgrade`.

### 3. AUR

The user runs `amepkg NAME upgrade` in a terminal and reads each PKGBUILD. Never turn the AUR on for them.

### 4. The image

Retry once the registry is reachable. A refused signature means the image is not the one the template
names: never edit `/etc/containers/policy.json` or fetch the image another way. A pin the registry no longer
serves is replaced by the next image: `ame update` (restart). Pin a template of the user's own:
`amepkg templates update --name T --base IMAGE@sha256:DIGEST`.

### 5. The app

`amepkg NAME export --app APP` puts the launcher back; `amepkg NAME start`, then open the app.
`amepkg containers reset NAME` makes the container again from its template and keeps its home folder, but
deletes what was installed in it: ask first, and install the packages it prints again.

### 6. Storage

`run` `ame system clean` (Control's `clean`, in a terminal): it asks before pruning podman's unused
images. After a podman update: `podman system migrate`.

### 7. As the user

Run `amepkg` as the user, without sudo: the containers are the user's, in rootless podman.

## Verify

- `/usr/libexec/amethystora-doctor --only containers` (exits 0 when it finds nothing).
- `amepkg containers list --json`: `last_upgrade_result` `ok` and a new `last_upgrade`.
- The app is in the app grid and opens.

## Undo

- An export: `amepkg NAME unexport --app APP`.
- An upgrade cannot be undone package by package; `amepkg containers reset NAME` is the way back to the
  template (ask first).
- A template's base: `amepkg templates update --name T --base OLD-IMAGE`.
