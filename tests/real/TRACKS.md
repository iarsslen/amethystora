# Real-machine testing: the tracks that run at once

What is left of `tests/real/checklist` (1458 open items on 2026-10-30, from origin/main at
the time of writing), split by what an item needs, so that more than one session can work at once. Written by the lab
session; the real-machine session owns it from here and changes it as it learns (`STATE.md` says where each track is).

**One screen, one walker.** Only one session ever gives the desktop input or judges what it shows. Everything else runs
from a terminal or SSH, never through RemoteDesktop, never on the screen, and changes nothing a person sees: no
`ame desktop`, no theme, no `gsettings` of the desktop, no logout.

**One file, one writer**, so two pushes never touch the same lines: the desktop track marks `10-desktop.md` and
`20-apps.md`; the terminal track marks `30-security.md` and `40-system.md`. The desktop track's items in those two
files wait until the terminal track has finished with them. Every track pushes after every item or two
(`git pull --rebase origin main`, then `git push origin main`) and writes its line in `STATE.md`.

**A hang stops every track.** After one: the tails of `journalctl -b -1` saved first (where `STATE.md` says), then each
track resumes from its last pushed mark. Until the dock is understood, nothing plugs or unplugs it, and nothing suspends.

## 1. Desktop: the screen's walker (1007 items, one session, in order)

The walk as it was: by RemoteDesktop or by the person's hands, one item at a time, the shell's journal read after each.
It takes the items below in this order: `10-desktop.md` first, then `20-apps.md`, then what `30-security.md` and
`40-system.md` hold for it once the terminal track is through them. Items that only need a state the walker can make
itself (the agentic features on, both screens, a container, the network) are here too: it makes the state, checks, and
puts it back.

- `10-desktop` D-TOPBAR: 07, 08, 09, 19, 20, 24, 25, 26
- `10-desktop` D-QUICK: 05, 16
- `10-desktop` D-TODAY: 02
- `10-desktop` D-PILL: 02, 03, 04, 06, 07, 08, 09
- `10-desktop` D-DOTS: 04
- `10-desktop` D-PRIV: 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15
- `10-desktop` D-NOTIFY: 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16
- `10-desktop` D-FOCUS: 08, 09, 10, 11, 12, 14
- `10-desktop` D-PRESENT: 07, 11
- `10-desktop` D-DESKS: 06, 07
- `10-desktop` D-SOUND: 01, 02
- `10-desktop` D-LOCK: 01, 02, 03
- `10-desktop` D-SEARCH: 06, 18
- `10-desktop` D-GRID: 07
- `10-desktop` D-CLIP: 03, 04, 07
- `10-desktop` D-SHELF: 01, 02, 03, 04, 05, 06, 07
- `10-desktop` D-EMOJI: 05
- `10-desktop` D-SHOT: 02, 04, 05, 08, 09, 10, 11, 12, 13, 15
- `10-desktop` D-CAPTIONS: 01, 02, 03, 04, 05
- `10-desktop` D-ACCESS: 01, 02, 07, 08, 09
- `10-desktop` D-TOUCH: 03
- `10-desktop` D-TIPS: 01, 02
- `10-desktop` D-POINTER: 04, 05
- `10-desktop` D-DOCK: 06, 07, 08, 12, 14, 15, 16, 17, 18, 20, 21, 22, 23, 24, 25, 27, 31, 32, 33
- `10-desktop` D-MENU: 01, 02, 03, 04
- `10-desktop` D-TILE: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26, 27, 28, 29, 30
- `10-desktop` D-TILESET: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25
- `10-desktop` D-SCREENS: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10
- `10-desktop` D-CLASSIC: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10
- `10-desktop` D-WIN: 01, 02, 03, 04, 07, 08, 09, 10, 11, 12
- `10-desktop` D-QUIT: 01, 03, 04, 05
- `10-desktop` D-MOTION: 01, 02, 03, 04, 05, 06, 07, 08, 09
- `10-desktop` D-WS: 01, 02, 03, 04, 05, 06, 07, 08
- `10-desktop` D-THEME: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18
- `10-desktop` D-WALL: 01, 02, 03, 04, 05, 06, 07, 08, 09
- `10-desktop` D-TRANS: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11
- `10-desktop` D-STYLE: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39
- `10-desktop` D-GLASS: 01, 02, 03, 04, 05, 06, 07
- `10-desktop` D-COMFORT: 01, 02, 03, 04
- `10-desktop` D-FONT: 01, 02
- `10-desktop` D-ICONS: 01, 02, 03, 04
- `10-desktop` D-TERM: 01, 02, 03, 04
- `10-desktop` D-CLIPX: 01, 02, 04, 05, 06, 07
- `10-desktop` D-WIDGET: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14
- `10-desktop` D-AGENT: 01, 02, 03, 04, 05, 06, 07, 08
- `10-desktop` D-BAZAAR: 01, 03
- `10-desktop` D-KEYS: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16
- `10-desktop` D-OTHER: 01, 02, 03, 04
- `20-apps` A-ALL: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16
- `20-apps` A-MANUAL: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27
- `20-apps` A-SECURITY: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 30, 31, 32, 33, 34, 36, 37, 38, 39, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 71
- `20-apps` A-UPDATES: 01, 02, 03, 04, 05, 07, 08, 09, 11, 14, 17, 18, 19, 20, 23, 24, 25, 26, 28, 29, 30, 31
- `20-apps` A-NOTES: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66
- `20-apps` A-LOGS: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 27, 28, 29
- `20-apps` A-BACKUPS: 01, 03, 04, 05, 12, 13, 14, 15, 16, 19, 20, 23, 24, 25, 26, 28, 29
- `20-apps` A-CONTROL: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 98, 99, 100, 101, 102, 103, 105, 106, 107, 109, 110, 111, 112, 113, 114, 115, 116, 117, 119, 121, 123, 124, 125, 127, 128, 129, 130, 131, 132, 133, 134, 138, 139, 140, 141, 142, 151, 152, 153, 154, 156, 157, 158, 159
- `20-apps` A-PHONE: 01, 02, 03, 04, 12, 17, 26, 28, 29, 30, 33
- `20-apps` A-SHELF: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13
- `30-security` S-WATCH: 06, 08, 12
- `30-security` S-SWITCH: 05, 07, 10, 14, 16
- `30-security` S-THREAT: 13, 14
- `30-security` S-NET: 03, 04, 09, 10
- `30-security` S-HARD: 09, 12
- `30-security` S-LOGIN: 09
- `30-security` S-LOCK: 05, 07, 09
- `30-security` S-APPS: 01, 02, 04, 05
- `30-security` S-DISK: 05
- `30-security` S-DESK: 03, 04, 05, 06
- `40-system` Y-AME: 01, 02, 05, 06, 07
- `40-system` Y-TOP: 01, 03, 04, 05, 14
- `40-system` Y-UPD: 01, 02, 03, 04, 05, 08, 10, 12, 16
- `40-system` Y-SYS: 13, 14, 17, 25, 28, 33
- `40-system` Y-DSK: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 59, 60, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99
- `40-system` Y-AGT: 02, 05, 06, 15, 16, 17, 19, 20, 27, 28, 29, 30, 31, 32, 33
- `40-system` Y-APP: 03, 05, 08, 09, 20, 25
- `40-system` Y-SW: 01, 02, 06, 11, 12
- `40-system` Y-PKG: 04, 05, 06, 07, 13, 15, 18
- `40-system` Y-WIN: 02, 03, 04, 05, 06
- `40-system` Y-TRM: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10
- `40-system` Y-SET: 01, 05, 06, 08, 09
- `40-system` Y-DX: 02, 11
- `40-system` Y-NEW: 01, 02, 03, 04, 05, 06, 09, 10, 16, 17
- `40-system` Y-DSKS: 01
- `40-system` Y-HW: 01, 02, 06, 08, 09, 10, 11, 13, 14, 19, 21, 24, 26, 30
- `40-system` Y-PHN: 01, 08, 12, 13, 14

## 2. Terminal: a second session beside the walker (250 items)

Commands and what they print, from a terminal of its own (Ptyxis or kitty minimised, or SSH from another machine), never
the screen. `30-security.md` from its PREP items to its END items in order, then `40-system.md`. A switch it turns on is
put back right after (PREP saved the state); a notification a switch raises is expected, and the walker is told in
`STATE.md` before one is set off, so it does not take it for a fault. It does not run anything flagged `risky`,
`logout`, `reboot` or `never`, which are in track 3.

- `30-security` S-PREP: 01, 02
- `30-security` S-REPORT: 01, 02, 04, 05, 06, 07, 08, 09, 10, 11, 12
- `30-security` S-WATCH: 01, 02, 03, 04, 05, 07, 09, 10, 11, 13
- `30-security` S-SWITCH: 01, 02, 03, 04, 06, 09, 11, 12, 13, 15, 17, 18, 19, 20, 21, 22, 23, 24
- `30-security` S-PROFILE: 01, 02
- `30-security` S-THREAT: 01, 02, 03, 04, 09, 10, 11, 12, 15
- `30-security` S-SCAN: 01, 02, 03, 04, 05, 06, 07, 08
- `30-security` S-NET: 01, 02, 07, 08, 13, 14, 16, 17
- `30-security` S-HARD: 01, 02, 03, 04, 05, 06, 08, 10, 11, 14, 15
- `30-security` S-STRICT: 06, 07, 08, 11, 13, 14, 19
- `30-security` S-SENDS: 01, 02, 03, 04, 05, 06, 07
- `30-security` S-LOGIN: 01, 02, 03, 04, 05, 06, 08
- `30-security` S-LOCK: 01, 04, 08, 10
- `30-security` S-BROWSER: 01, 02, 03, 05
- `30-security` S-APPS: 03, 06
- `30-security` S-DISK: 01, 03, 04
- `30-security` S-DESK: 01
- `30-security` S-END: 01, 02
- `40-system` Y-AME: 03, 04, 08, 09
- `40-system` Y-TOP: 02, 06, 07, 08, 10, 12, 13, 16
- `40-system` Y-UPD: 06, 09, 11, 13, 14, 17, 18, 19
- `40-system` Y-SYS: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 16, 18, 42, 19, 22, 23, 24, 26, 27, 29, 30, 32, 34, 35, 36, 37, 38, 39, 40, 41
- `40-system` Y-AGT: 01, 03, 04, 07, 08, 09, 10, 11, 12, 13, 14, 18, 21, 22, 23, 24, 25, 26
- `40-system` Y-APP: 01, 02, 04, 06, 07, 10, 11, 12, 13, 14, 16, 17, 18, 19, 21, 22, 23, 24, 26
- `40-system` Y-SW: 03, 04, 05, 07, 08, 09, 10
- `40-system` Y-PKG: 01, 02, 03, 08, 09, 10, 11, 12, 14, 16, 17
- `40-system` Y-WIN: 01
- `40-system` Y-SET: 02, 03, 04, 07
- `40-system` Y-DX: 04
- `40-system` Y-NEW: 07, 08, 12, 13, 14, 15, 18
- `40-system` Y-DSKS: 02, 03, 04, 05, 06, 08
- `40-system` Y-HW: 05, 07, 15, 16, 18, 31, 33, 35

## 3. With the person (163 items, one sitting, gathered)

What needs the maintainer's hands, a device or a yes: a phone, a security key, a backup set up, a second account, a
staged update, the previous deployment, and everything `risky`, `logout`, `reboot` or `never`. Prepare the list of
the ones for the sitting with what each needs, ask once, and do them together; the dock's hang tests belong here too.

- `10-desktop` D-QUICK: 14
- `10-desktop` D-PILL: 12, 13
- `10-desktop` D-PRIV: 01
- `10-desktop` D-DESKS: 01, 02, 03, 04, 05
- `10-desktop` D-REVEAL: 01, 02
- `10-desktop` D-GRID: 05, 06
- `10-desktop` D-CLIP: 05
- `10-desktop` D-CAPTIONS: 06
- `10-desktop` D-DOCK: 26, 28
- `10-desktop` D-QUIT: 02
- `10-desktop` D-CLIPX: 03
- `10-desktop` D-BAZAAR: 02
- `10-desktop` D-FIRST: 01, 02, 03
- `20-apps` A-SECURITY: 14, 29, 35, 40, 51, 53, 70
- `20-apps` A-UPDATES: 06, 10, 12, 13, 15, 16, 21, 22, 27, 32
- `20-apps` A-NOTES: 31, 32, 51
- `20-apps` A-LOGS: 26
- `20-apps` A-BACKUPS: 02, 06, 07, 08, 09, 10, 11, 17, 18, 21, 22, 27
- `20-apps` A-CONTROL: 104, 108, 118, 120, 122, 126, 135, 136, 137, 143, 144, 145, 146, 147, 148, 149, 150, 155
- `20-apps` A-PHONE: 05, 06, 07, 08, 09, 10, 11, 13, 14, 15, 16, 18, 19, 20, 21, 22, 23, 24, 25, 27, 31, 32
- `30-security` S-REPORT: 03
- `30-security` S-SWITCH: 08
- `30-security` S-PROFILE: 03, 04
- `30-security` S-THREAT: 05, 06, 07, 08
- `30-security` S-NET: 05, 06, 11, 12, 15
- `30-security` S-HARD: 07, 13, 16, 17, 18
- `30-security` S-STRICT: 01, 02, 03, 04, 05, 09, 10, 12, 15, 16, 17, 18
- `30-security` S-LOGIN: 07, 10
- `30-security` S-LOCK: 02, 03, 06
- `30-security` S-BROWSER: 04
- `30-security` S-DISK: 02, 06
- `30-security` S-DESK: 02
- `40-system` Y-TOP: 09, 11, 15, 17
- `40-system` Y-UPD: 07, 15
- `40-system` Y-SYS: 20, 21
- `40-system` Y-DSK: 12, 61
- `40-system` Y-NEW: 11
- `40-system` Y-DSKS: 07
- `40-system` Y-HW: 03, 04, 17, 22, 23, 27, 28
- `40-system` Y-PHN: 02, 03, 04, 05, 06, 07, 09, 10, 11

## 4. Not on this machine (38 items)

Needs hardware this machine does not have, by its `needs:` (touchpad, pen, laptop lid or battery, a dx image, HDR, a game
controller, a camera, a fingerprint reader). The terminal track confirms each absence once (`lsusb`, `libinput list-devices`,
`fprintd-list`, `cat /usr/share/amethystora/image-info.json`) and marks the items `N/A` with what it found; any that
the machine does have go back to track 1 or 3.

- `10-desktop` D-PILL: 11
- `10-desktop` D-DOTS: 02
- `10-desktop` D-PRESENT: 06
- `10-desktop` D-ACCESS: 03
- `10-desktop` D-TOUCH: 02
- `10-desktop` D-PEN: 02, 05
- `10-desktop` D-DOCK: 35
- `10-desktop` D-TILE: 25
- `10-desktop` D-TILESET: 12
- `10-desktop` D-CLASSIC: 11
- `10-desktop` D-WIN: 05, 06
- `10-desktop` D-CORNERS: 01
- `20-apps` A-CONTROL: 50, 51, 52, 53, 97
- `40-system` Y-SYS: 15, 31
- `40-system` Y-DSK: 33, 58
- `40-system` Y-APP: 15
- `40-system` Y-DX: 01, 03, 05, 06, 07, 08, 09, 10
- `40-system` Y-HW: 12, 20, 25, 29, 32, 34

## 5. After the new image

When an image with today's fixes is installed, each fix's own check goes first, ahead of every track: the reveal after a
theme or wallpaper change, the wheel with the real mouse (01cdf9b), a click and a rename on a workspace (82353f8, 029e959),
the Today and Playing now headings (240bf6f, 4bbc850), Glance (b2446bd: Space keeps the preview up, Down steps, Space
closes with the search kept), Private mode by keyboard (aa1d7bd), the Manual's cards and section links (463a788, 985fc18),
Shake to find off (de9c1c7), no search crash (376d1b0), and `ame desktop daylight on` (3886e3d). Then `FIXED` lines
whose body says "not seen working here" are checked again and corrected.

## The lab, in parallel

The VM lab on the maintainer's PC can run its suites on the same commits whenever someone runs it, and does not wait on
this machine. Its findings and this machine's are both pushed to `main`.
