# Real-machine testing: state

Resume from `git pull` alone: read this, then `.claude/skills/real-machine/SKILL.md`. Updated with every push of marks.
If the machine hung: first save the tails of `journalctl -b -1` into `tests/real/hangs/`, push, then go on.

## Now

- Updated: 2026-10-30 14:15 EDT. Boot 97075e68, started 13:59:21. Image `latest-44.20261030`, built from 587de45,
  without today's search crash, deadlock, frozen-screen and Glance fixes. Checkout at aa1d7bd.
- Running: the checklist walk (`10-desktop.md`, from D-GRID-05, a subagent of the desktop session, input through Mutter
  RemoteDesktop) and the no-DisplayLink test.
- The walk still runs inside the desktop session, so a shell crash takes it with it. Moving it out is not done.
- Owner: the real-machine Claude session, since the lab session handed this over on 2026-10-30. Nobody takes commits
  through the lab meanwhile, and nothing here is validated by it. Never start `Latest Images` from here.

## The hang

Seen:
- Abrupt ends of today's boots, by journal: 09:45:46, 10:21:20, 12:13:17, 13:05:32. Uptimes 35, 35, 110 and 51 minutes.
- 12:13: the maintainer forced the restart, all 4 screens black, 30 s after a resume, with `Failed to get ACT` and
  `Bad EDID` before it. That login turned the two DisplayLink LG screens on; the healthy logins at 12:15 and 12:30 did not.
- 13:05: all screens black, keyboard dead, `Ctrl+Alt+F3` nothing, direct monitor and keyboard no help, forced power-off,
  next boot 13:59:21. In the maintainer's words: "i started the tests, then i went for a break, got back and it was black".
- No kernel error, GPU reset, lockup, oops or core dump in the kept log of the 13:05 boot. `/var/lib/systemd/pstore` empty.
  `/sys/fs/pstore` needs sudo and has not been read.

Inferred, weak:
- The whole machine rather than GNOME Shell, since the console switch failed.
- The journal then synced only every 5 minutes, so up to 5 minutes before each end may be missing: the last lines
  (a graphical program starting, in three of the four) are not firm evidence.
- Not explained: the cause. Candidates are amdgpu on the dock's MST link, and evdi (DisplayLink, out of tree).

## The no-DisplayLink test

- Started 14:06:29: `displaylink.service` masked with `--runtime` and stopped, `kernel.sysrq=1`,
  `/etc/systemd/journald.conf.d/hang-test.conf` with `SyncIntervalSec=1s`. `evdi` could not be unloaded (still loaded,
  use count 2): that needs a logout. The LG screens are off, the Samsungs are `DP-1` and `DP-11`.
- Not input-free: the walk was resumed at the maintainer's word at about 14:12.
- The first mark that means much: about 15:50, 110 minutes into this boot.
- Seen at 14:08:02, on a switch to the text console, recovered: amdgpu `REG_WAIT timeout ... dcn31_program_compbuf_size`,
  a WARNING at `dcn31_hubbub.c:151`, under `fbcon_init`.
- If it hangs anyway: the Samsungs plugged directly into the machine, not through a dock (the maintainer's hands).
- Take away afterwards: `sudo rm /etc/systemd/journald.conf.d/hang-test.conf`, `sudo systemctl restart systemd-journald`.
  The mask and `sysrq` end at the next restart.

## To check on this machine once an image has them

Needs an image past 587de45, or `/usr` overlay and a logout (the overlay is lost at each restart).

- Glance, b2446bd: Space stays up, Down steps, Space closes with the search kept (D-SEARCH-20).
- Private mode's keyboard, aa1d7bd (D-CLIP-03; the walk leaves this item open).
- The login reveal, workspace click and rename (D-TOPBAR-04, 06), Today headings, Playing now heading, Manual cards and
  section links.
- The wheel, 01cdf9b: needs the maintainer's real mouse (D-TOPBAR-07).
- `ame desktop daylight on`, when the image has 3886e3d.
- The search crash fix, 376d1b0, was seen working here at 12:34 through an overlay that a restart then discarded.

## Open, not fixed

- D-GRID-02: a **No results** label stays over the app grid. Cause not found; not checked on a fresh login.
- D-SEARCH-21: with Glance off, Space on a file row closes the box and opens nothing.
- `meta_window_set_stack_position_no_sync: assertion` about once a minute in the shell's log. Unexplained.
- `gsd-media-keys` segfaults at session changes, in `_pa_context_get_card_info_by_index_cb`.

## Decisions for the maintainer

- Extension Manager (D-APP-27).
- Space on the Ask the agent row: it starts the agent, against D-SEARCH-18's "nothing starts before Enter".
- The identical HDMI output names.
- A patched mutter for GNOME/mutter#5136.
- Whether `Latest Images` is queued for today's fixes.
- A git identity for this machine (commits pass the author inline meanwhile).

## Machine state to put back

- Suspend and blanking are off at the maintainer's request (old values in
  `~/.local/state/amethystora/idle-settings-before-2026-10-30.txt`), and Daylight is off. Put back when told.
