# Real-machine testing: state

Resume from `git pull` alone: read this, then `.claude/skills/real-machine/SKILL.md`. Updated with every push of marks.
If the machine hung: first save the tails of `journalctl -b -1` into `tests/real/hangs/`, push, then go on.

## Now

- Updated: 2026-10-30 14:50 EDT. Boot e68f5f3b, started 14:42:41, after a third hard hang in this log. Image
  `latest-44.20261030`, built from 587de45, without today's fixes. DisplayLink is running again (its mask ended with the
  restart), `kernel.sysrq` is 16, and the journald drop-in is still in `/etc`, so sync stays 1 s.
- The first 40 items of `10-desktop.md` from D-GRID-05 are walked (last marks fa85ddd, 14:49). Nothing is walking now. Next:
  the items the walk left for a mouse or a person, then the rest of `10-desktop.md`, then 20, 30, 40. Left held: D-MENU-01, 02.
- Driver: `$D click` never landed (RemoteDesktop); a large relative move stops at the current screen's edge, so home through the join.
- One Terminal launcher, the maintainer's choice of 2026-10-30, is committed; it reaches this machine with an image.
- Journal tails of each hang are kept on the machine, in `~/.local/state/amethystora/hangs`, not here: this repository is
  public and they hold personal data.
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

- 14:37: journal ends 14:37:33.02 with sync at 1 s, so this tail is firm. DisplayLink's service had been stopped since
  14:06:29, `evdi` loaded. In the maintainer's words: "it crashed again afgter i plugged the dock back again. So i have a
  multiswitch kvm, when i switched back to this machine. it froze". SysRq (`kernel.sysrq=1`) did nothing; a keyboard plugged
  straight into the machine stayed off. No kernel line after 14:25:29 (the Lenovo dock's USB disconnect, which it
  survived for 12 minutes), so no USB connect line for the replug. No oops, no core dump, `pstore` folder empty. The walk
  was sending keys and screenshots at that moment.

Inferred:
- The kernel itself stopped: SysRq is handled in the kernel, and a powerless keyboard suggests the USB controller went too.
  Not GNOME Shell, and not a daemon. DisplayLink's service is not required for it, since it was stopped; its driver was loaded.
- Leading idea: a display hotplug hangs the machine (a KVM switch or a dock replug drops and re-trains the link). The
  maintainer says the KVM was switched before each of the freezes (told 2026-10-30). Not reproduced on purpose yet. Earlier amdgpu display warnings are in the same area (10:18 DSC, 12:13 ACT, 14:08 REG_WAIT).
- The whole machine rather than GNOME Shell, since the console switch failed.
- The journal then synced only every 5 minutes, so up to 5 minutes before each end may be missing: the last lines
  (a graphical program starting, in three of the four) are not firm evidence.
- Not explained: the cause. Candidates are amdgpu on the dock's MST link, and evdi (DisplayLink, out of tree).

## The no-DisplayLink test

- Started 14:06:29: `displaylink.service` masked with `--runtime` and stopped, `kernel.sysrq=1`,
  `/etc/systemd/journald.conf.d/hang-test.conf` with `SyncIntervalSec=1s`. `evdi` could not be unloaded (still loaded,
  use count 2): that needs a logout. The LG screens are off, the Samsungs are `DP-1` and `DP-11`.
- Not input-free: the walk was resumed at the maintainer's word at about 14:12.
- Ended by the 14:37 hang, 31 minutes in. Result: it hangs without DisplayLink's service. `evdi` stayed loaded, so the driver
  is not ruled out.
- Seen at 14:08:02, on a switch to the text console, recovered: amdgpu `REG_WAIT timeout ... dcn31_program_compbuf_size`,
  a WARNING at `dcn31_hubbub.c:151`, under `fbcon_init`.
- Next, the maintainer's hands: switch the KVM away and back with nothing walking, to see if that alone hangs it; then the same with the Samsungs plugged directly into the machine.
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
- 14:37:10 to 14:37:29: a kitty launched every 4.6 s through the menu, with two screenshots a cycle, until the hang. The walk's history has no such loop. Unexplained.

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
