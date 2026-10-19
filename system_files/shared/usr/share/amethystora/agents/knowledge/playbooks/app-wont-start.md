# An app that will not start

## Symptom

Clicking an app does nothing, a window flashes and closes, or the app runs with no window to be seen.
Often it works on Fedora or another distribution.

## Look

- `state crashes`, then `logs` identifier = the program's name, or grep = the app's id, boot `0`.
- `state app-permissions` with the app's id as filter: what it reaches, and what an override granted or
  took.
- `state software`: a Flatpak (user or system), a container's app, or Homebrew's.
- `state security`: the `app-integrity` check.

Then:

- `flatpak run APP` in a terminal prints the app's own error
- `flatpak info --show-permissions APP`; `flatpak info --show-metadata APP` (what its manifest asks for)
- `flatpak override --user --show APP`, `flatpak ps`
- `coredumpctl info PID`
- `amepkg containers list --json` (a container's `status` and `exported_apps`)

## Causes on Amethystora

1. **An X11-only app.** `/etc/flatpak/overrides/global` takes `x11` and `fallback-x11` from every Flatpak,
   whatever its manifest asks: Wine, older Electron and Java apps and many games get no display. Tell:
   "cannot open display" or "Missing X server"; the manifest asks for x11, the permissions lack it.
2. **No X11 at all.** With `ame security block-xwayland` on, no app gets X11, granted or not. Tell:
   `state security-settings` filter `block-xwayland`.
3. **The Flatpak service taken.** The same override takes `org.freedesktop.Flatpak`: launchers and IDEs
   that run programs on the host (`flatpak-spawn --host`) fail with an error naming it. Only the image's
   own tools that need it (Mission Center, Bazaar, Warehouse) have it back.
4. **Input devices taken** (`devices=!input`): it starts but sees no controller, tablet or wheel.
5. **The window is off the screen.** With the tiling layout (PaperWM) a new window opens past the edge of
   the strip, or on another workspace. Tell: `flatpak ps` lists it.
6. **The user's own overrides.** Security's Apps page took its network (it hangs or says offline), or an
   override took a socket or folder it needs. Tell: `state app-permissions` says "network taken away" or
   "has your overrides".
7. **Files changed outside an update** (app integrity on): the check names the app, or a launcher that
   starts something else. A security finding, not a glitch.
8. **Parental Controls.** A child's account opens only the apps its filter allows: the app is missing
   from its grid, and `flatpak run` says the administrator's policy does not allow it.
9. **A crash or a missing runtime.** `coredumpctl info` gives the stack; "not installed" names a runtime.
   NVIDIA images need the `org.freedesktop.Platform.GL.nvidia` extension matching the driver.
10. **A container's app** ("(on debian)"): a container removed or made again leaves its launcher pointing
    at nothing.

## Fix

### X11

Say that the app will see what is typed into every other X11 app, then, with a yes,
`flatpak override --user --socket=x11 APP`. Steam: `change` `gaming` `on`. With block-xwayland on, the
user runs `ame security block-xwayland off` (root), from the next login.

### Flatpak service

Say it is a full way out of the sandbox, then, with a yes,
`flatpak override --user --talk-name=org.freedesktop.Flatpak APP`. `ame security app-sandbox off` (root)
drops the override for every app: the user's decision only.

### Input devices

Say the app then reads every key pressed, then `flatpak override --user --device=input APP`.

### Off the screen

`Super+End`, or pick it in the overview. For floating windows: `change` `layout` `classic`.

### Own overrides

The network: **Give its network back** on Security's Apps page, or with a yes
`flatpak override --user --share=network APP`. Everything the user set: ask, then
`flatpak override --user --reset APP`, or `ame security apps reset`.

### Changed files

The user runs `ame security app-integrity repair APP` (root for a system app): fetched again, `~/.var/app`
kept. Never copy files into `/var/lib/flatpak` or `~/.local/share/flatpak` by hand.

### Parental Controls

An administrator allows the app there.

### Crash or runtime

`flatpak update --user` (the system's with root), then `flatpak repair --user`. A crash that stays goes to
the app's makers.

### Container

`amepkg NAME start`, then `amepkg NAME export --app APP`, or `amepkg NAME install PACKAGE` in a container
made again.

## Verify

- The window opens; `flatpak ps` lists the app; `state crashes` has nothing new.
- `state app-permissions` with the app's id: the reach granted.
- After a repair: `state security`, the `app-integrity` check.

## Undo

- `flatpak override --user` with `--nosocket=x11`, `--no-talk-name=org.freedesktop.Flatpak`,
  `--nodevice=input` or `--unshare=network`, and the app's id.
- `flatpak override --user --reset APP` drops all of the user's overrides for that app.
- `change` `layout` `tiling`.
- `ame security block-xwayland on`, `ame security app-sandbox on` (root) turn protection on: the agent
  may run them when the user asks.
