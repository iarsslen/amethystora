# Getting around

The desktop is GNOME, arranged for the keyboard. Everything here also works with the mouse, but once
the keys are in your fingers you will rarely reach for it.

## The top bar

- **On the left**, the Amethystora logo, a menu of the system's tools: about this computer, this
  manual, Settings, Bazaar, Extensions, Mission Center, the terminal and DistroShelf. A
  middle click on it opens the overview. Then the six workspaces: the one you are on is
  highlighted; click another to go there, or the one you are on to show or hide the overview. An empty
  one opens the overview, ready to start something. Scroll the mouse wheel, or two fingers on a
  touchpad, anywhere on the bar to go to the next or previous workspace. Drag a workspace along the row to move it, its windows with it, or
  drop a window from the overview on one to send it there. Right-click a workspace to give it a name
  (until you do, it is named after its main app).
- **In the middle**, the clock, with [the weather](#the-weather) beside it once you turn it on. Click it,
  or press `Super+V`, for notifications, the calendar and [Today](#today). While something is happening,
  the clock becomes the [live pill](#the-live-pill).
- **On the right**, CPU, memory and network meters, the icons apps keep in the tray, then the system
  menu: Wi-Fi, sound, power and the rest of the [quick settings](#quick-settings). Right-click a tray icon for its app's
  menu, double-click it to open the app, and middle-click it for the app's second action. A Flatpak app
  shows its icon only when it may talk to the tray (`org.kde.StatusNotifierWatcher`), and an old X11
  one only while X11 apps are allowed. Click a meter for the details: each processor, the memory and the
  network over the last few minutes, the busiest processes, and a button that opens Mission Center.
  The network meter counts your Wi-Fi and wired connections only, so a VPN or a container's traffic
  is not counted twice.

The meters and the workspaces follow the colours of the current [theme](themes.md). The bar can
also show [widgets](widgets.md) of your own, which the AI agent makes for you once you turn it on.

A fullscreen video or game keeps the whole screen; push the pointer against the top edge and the bar
comes down over it, and goes when you move away. `ame desktop top-bar peek off` turns that off. With
two monitors or more, each one has a top bar of its own: see [Several monitors](#several-monitors).

## Quick settings

The menu at the right end of the top bar opens on tiles, two to a row, each saying what it knows: the
Wi-Fi network and how strong it is, the earbuds and their battery, the power mode, and, while a paired
phone is connected, the phone and its battery (click it for the Phone app). Click a tile to switch it, and
its arrow for its menu. Under the tiles are the sliders, then the apps playing sound, a swatch for every
theme, and Screenshot, Lock, Settings and Power.

- **Moving and hiding tiles.** Hold a tile for half a second (or press `Menu` on it): the tiles shrink a
  little and each gets a round button at its corner. Drag a tile to its new place; the button puts it
  away, into a Hidden row, where the same button brings it back. With the keyboard, `Ctrl` and an arrow
  moves the tile you are on, `Delete` hides it and `Enter` brings a hidden one back. Done, `Esc` or
  closing the menu ends it. `ame desktop quick-settings reset` puts every tile back in its first place
  and shows them all, and so does **Quick settings tiles** in [Control](control.md).
- **The battery.** On a laptop the first tile is the battery: how full it is and when it runs out or is
  full. Click it for **Keep the battery at 80%**, where the laptop can stop charging early so the battery
  lasts more years; the switch is GNOME's own charge limit, which UPower keeps across restarts. A laptop
  that cannot stop charging early has no such switch.
- **Each app's volume.** While apps play sound, each has its own slider and mute button under the
  volume slider, and the buttons beside "Playing now" send the sound to another output, as the arrow of
  the volume slider does.
- **The theme.** A tap on a swatch switches to that theme, as `ame desktop theme` does: the desktop and
  Amethystora's apps change at once, other apps the next time they start.
  `ame desktop quick-settings theme off` hides the swatches, and `on` brings them back; you can also
  hide them as you hide a tile.

## Today

The calendar menu, under the calendar, holds the day: the events from your calendars, the tasks due
today and the overdue ones from [Notes](notes.md#tasks), your world clocks and the weather. The tasks
are there while Notes is open and unlocked, or not encrypted, and only on today's page of the calendar;
click them to open Notes' tasks. Nothing is asked of Notes until you open the menu, and Notes tells the
calendar nothing but the titles of those tasks, and nothing at all when the menu is closed. Notes answers
GNOME Shell alone: an app in a sandbox cannot ask, but a program you run yourself outside one could, as it
could read anything else of yours while your notes are open. `ame desktop today tasks off` leaves them out.

## The weather

The weather is off until you choose it, because it sends your place to weather services: the place you
chose in Weather goes to MET Norway (api.met.no) and OpenWeatherMap (api.openweathermap.org, which
refuses it, since Fedora's weather library has no key for it), and the code of the nearest airport to
NOAA's aviation reports (aviationweather.gov), each time the weather is shown. Its place in the calendar
menu says so, with **Turn on…**, which asks once more before it turns it on; `ame desktop weather on`
says what it sends and turns it on. Once it is on, the temperature and the sky show beside the clock and
in the calendar menu, refreshed when you open the menu, when the computer wakes and once an hour. If
Weather has no place yet, the menu offers to open it. `ame desktop weather off` stops it, and **What this
machine sends** in Security lists it. Whether it is on or off, GNOME Shell itself asks for the weather
once as you log in, and when Weather's place changes while the screen is locked, if you set a place in
Weather.

## Rest reminders

GNOME can remind you to look away from the screen now and then, and to stand up and move. Both are off
until you turn them on: `ame desktop breaks on` (look away for 20 seconds every 20 minutes),
`movement` (stand up for 5 minutes every 30 minutes), `both`, or `off`, or Control's **Rest reminders**.
The reminders are GNOME's own notifications, with **Delay**, **Skip** and **Take**, and the screen fades
gently when a break begins. The times are in Settings, under **Wellbeing**.

## The live pill

While something is happening, the clock in the middle of the top bar shows it, on a small round pill.
When nothing is, it is the clock again, exactly as before. Only one thing shows at a time, the first of
these that is happening: a call ringing on your phone, a recording of the screen, a link from your phone,
the battery's question at 20%, a word that something just finished, a timer, what is playing, an update
ready, and quiet. Click the pill for its card, with its buttons and, below them, whatever else is
happening; the card's last row is the date and time, which opens the calendar. A right-click on the
pill, or `Super+V`, always opens the calendar.

- **A timer.** At the end of the calendar's column, under **Start a timer**, are 1, 5, 10 and 25 minutes.
  The pill counts it down; its card adds a minute, pauses or cancels it. While one runs, the same
  buttons add that many minutes. When it ends you hear it, a notification says so (it comes through
  even when banners are quiet), and the pill says **Timer done**. A timer runs on while the screen is
  locked, and rings as soon as you unlock it if it ended meanwhile.
- **What is playing**, from any player that tells the desktop (as music and video apps do): the cover,
  the title and the artist, and a click on the small pause button pauses it. The card has Back, Pause
  and Next, and how far into the track you are. A player you paused stays for ten minutes.
- **A call** on your [paired phone](phone.md): who is calling, and **Mute ringer**. The card also has
  **Reply with a text**. You answer on the phone itself.
- **A recording** of the screen: how long it has run, and **Stop**. GNOME's own recordings go to
  Videos › Screencasts.
- **A link from your phone**: the address, with **Open** and **Not now**. A link is shown, never opened
  by itself: **Open in browser** opens it, **Copy** copies it, and **Not now** leaves it in the
  notification list. A name in another alphabet is shown in its plain form (`xn--…`), so a look-alike
  cannot pass for the site it imitates.
- **An update ready**: **Ready · quick restart** when the update can finish without restarting the
  computer, else **Ready · restart**. **Restart now** opens [System Updates](updates.md#updating-now),
  which asks before it restarts anything; **Tonight** puts it out of sight until 8 in the evening.
- **The battery.** Rest the pointer on the battery in the top bar for the time left, or the time until
  it is full. At 20%, the pill turns amber and offers power saving, once: it never turns it on by itself.

`ame desktop pill off` gives you GNOME's clock alone; `ame desktop pill on` brings the pill back.

## Privacy dots

While something uses the microphone, the camera, the screen or your location, a small pill in the top bar
holds a dot for each, always in this order: amber for the microphone, green for the camera, red for the
screen (recorded or shared), violet for the location. Click it for the list of all four, each with its
own icon so that colour is never the only sign: the apps recording sound, the apps using the camera
(PipeWire says which), the screen with a **Stop** button, and the location. GNOME does not say which app
asks for your location, so the list only says that it is in use. While the dots are on, GNOME's own icons
for the same four are hidden.

**The recording glow.** While the screen is recorded or shared, a thin red glow runs round its edges, over
everything, so nobody forgets. It shows in a recording of the whole screen: the desktop cannot leave it
out.

`ame desktop pill dots on|off` and `ame desktop pill glow on|off` turn each off and on again.

## Notifications

GNOME folds an app's notifications in the calendar's list into one stack; a folded stack shows how many it
holds after the app's name.

### Quiet

While a window is fullscreen on the main screen, or the screen is shared or recorded, banners are quiet:
a notification still arrives, waits in the list and counts on the clock's dot and on its app in the dock,
but does not pop up or make a sound. Calls, alarms, timers and anything marked urgent still come through.
When quiet ends, what came meanwhile is not shown one after another: the pill says **2 waiting in the
list**, and a click on it opens the list. While the top bar shows, the pill says that it is quiet and how
many are held.

**Quiet at night** does the same between Night Light's times, whether or not Night Light itself is on:
the times you set for it in Settings, or from sunset to sunrise. It is off until you turn it on.

`ame desktop quiet on|off` and `ame desktop quiet night on|off`. Quiet never touches Do Not Disturb, which
stays yours, in the calendar.

### The digest

With the digest on, banners that are not urgent wait all day and come together, as one card, at the
digest times (12:00 and 18:00 to begin with): one row for each app, **Show all** (the list) and **Clear**.
Nothing is lost when the card goes: everything is in the list. `ame desktop digest on|off`, and
`ame desktop digest times 12:00 18:00` for other times (up to six). Control offers four sets.

### Volume and brightness

The volume, the brightness and the other signs GNOME shows for a key (Caps Lock, flight mode) appear as
a slim pill just under the top bar, instead of a card low in the middle of the screen.

## Sounds

The desktop's own sounds are Amethystora's **Soft** set: lower and rounder, for a quiet room. You hear them for a
message from a chat app that asks for one (GNOME plays no sound for an ordinary notification), a text message from
your [phone](hardware.md#phones), plugging in the power, a screenshot, each step of the volume, an error and the
bell, and a slow chord once the desktop has started. Any other event an app asks for comes from the standard sound
theme.

`ame desktop sounds off` makes the desktop silent: it makes no sound of its own, and apps can still make theirs (a
call, music, a game). `ame desktop sounds soft` brings them back. Control has the same choice under Appearance, in
the **Sound** group. Choosing an alert sound in **Settings**, **Sound**, gives the bell that sound; Control then
shows neither choice as chosen, and `ame desktop sounds soft` goes back to the whole Soft set.

## The lock screen

The lock screen shows a large clock and the date, what is playing with its controls, and your notifications as one
row for each app, with how many it has: never what they say. To hide even those rows, turn off **Lock Screen
Notifications** in **Settings**, **Notifications**. The lock screen runs no extension, so it keeps Amethystora's own
colours whatever the theme. With **High Contrast** on (Settings, Accessibility), it is GNOME's own high-contrast lock
screen instead, with GNOME's clock and plain cards, which are easier to read.

## Night Light and the screen's colour

Night Light makes the screen's colours warmer, more yellow, from sunset to sunrise or between the times you
choose, which is easier on the eyes at night. If the screen turns yellow in the evening, that is Night Light.
Turn it on or off in the quick settings at the top right, and set its times and how warm it is in
**Settings**, **Displays**, **Night Light**. [Quiet at night](#quiet) follows the same times.

## Finding things

- `Super+Space` opens a search box near the top of the screen, over your windows: type, and `Enter`
  opens the first result; `Ctrl+1` to `Ctrl+9` open the result with that number, which each of
  Amethystora's rows shows at its end. `Escape`, the same keys again or a click elsewhere closes it.
  Right-click a result for its menu, or drag an app onto the dock to pin it.
- `Super` alone opens the overview: every open window at once, with search at the top.
- `Super+A` shows every installed app. Some are gathered in folders: **Utilities** (Flatseal, Warehouse,
  Extension Manager, Firmware, Ignition, Impression, Refine and the like), **Productivity**,
  **Development**, **Containers**, **Games**, **Gaming Utilities** and **Wine**.

Both searches forgive typos, missing letters and initials in app names: `calxu` still finds
Calculator, and `mc` finds Mission Center. They find Power Off, Restart and the other actions too.

Besides apps, files and GNOME's settings, both searches answer from this machine, and nothing is sent
anywhere:

- **Sums and conversions**, as you type, in your language's numbers: `1284 * 0.18` gives 231.12,
  `200 + 10%` gives 220, `3.5 km in miles` gives 2.1748 mi and `21 °C in °F` gives 69.8 °F. `Enter`
  copies the answer. It converts lengths (mm, cm, m, km, in, ft, yd, mi, nautical miles), weights (mg, g,
  kg, t, oz, lb, stone), temperatures (°C, °F, K), data (bits and bytes, kB to PB, KiB to PiB) and time
  (ms to weeks). No currencies: their rates would have to come from the internet.
- **Do it**: [Control](control.md)'s settings, found by their words. `Enter` on a row such as
  *Phone pairing: On* changes the setting at once; one that asks something or needs a password opens a
  terminal. *Control › …* opens it in Control.
- **Open windows**, by title or app, on any workspace: `Enter` switches to it.
- **The manual**: the pages of this manual that answer what you typed, by meaning as well as by words.
- **Clipboard history**, only when you type `clip:` first, and words after it to narrow it down:
  `clip: ssh`. `Enter` pastes the item where you were typing. It is the history
  [the clipboard](#the-clipboard) already keeps; the search stores nothing new.
- **The agent**, only while the [agentic features](ai-agent.md) are on: the last row, *Ask the agent:
  …*, opens your agent in a terminal with what you typed as its first question. Nothing starts before
  `Enter`, and the agent asks before it changes anything, as always.
- **Glance**: with the keyboard on a file Files found (`↓` to it), `Space` shows it without opening
  it. `↑` and `↓` go to the other files found; `Space` again closes it, and the search is still there.

Each can be turned off, in Control's **Search** group or in a terminal:

```bash
ame desktop search                     # each, and whether it is on
ame desktop search answers off         # answers, settings, manual, windows, clipboard, agent or glance
```

## The clipboard

`Super+Shift+V` opens the clipboard history: the last 15 things you copied. Pick one to copy it
again, type to search, and pin the ones you keep coming back to. It is also the clipboard icon in
the top bar.

The history is never on disk as you copied it: text and pictures alike are sealed (encrypted) in
`~/.local/state/amethystora/clipboard`, under a key kept in your login keyring, which your password
protects. A copy of the disk, a snapshot or a stolen laptop shows nothing of it without that password.
It is left out of [backups](security.md#backups). A keyring given no password, as some machines that sign
in by themselves have, keeps its key in the clear, and then the history is only as safe as the disk.

How long it is kept is yours to choose, in [Control](control.md)'s **Clipboard history** or in a terminal.
Pinned items are always kept, and the history outlasts locking the screen either way.

```bash
ame desktop clipboard always    # everything, until you clear it (the default)
ame desktop clipboard restart   # pinned items, and the rest until the computer restarts
ame desktop clipboard session   # pinned items, and the rest until you log out
```

Nothing is recorded of what a password manager marks secret, as KeePassXC does, or of what you copy
in KeePassXC, Secrets, Bitwarden, 1Password or Proton Pass. Before copying anything else secret, turn on
**Private mode** in the same menu, and nothing is recorded until you turn it off.

After logging in with a fingerprint or a security key, your keyring stays locked, so the menu shows
what you copy from then on, under **Unlock to see earlier items**. Click it and type your password to
see the rest. The history is sealed under this machine's keyring: on another machine, or after an
administrator resets your password, it does not open, and it is kept aside as `history.unreadable`.

## Emoji and symbols

`Super+.` opens emoji and symbols over the window you are typing in, under the text cursor. Type to
search, in your language or in English (`euro`, `arrow`, `smile`), or pick a tab: **Recent**,
**Smileys**, **Arrows**, **Maths**, **Money**, **Punctuation**, and the rest of Unicode's emoji. `Enter`
or a click puts the one picked where you were typing; `Escape` closes it without typing anything. The
arrow keys move in the grid, `Tab` goes between the search, the tabs and the grid, and
`Ctrl+Page Down` and `Ctrl+Page Up` change tab.

What you pick is typed straight in where the app allows it. Otherwise it goes through the clipboard and
is pasted with `Shift+Insert`, or `Ctrl+Shift+V` in a terminal, and then it stays on the clipboard.

Hands and people come in the skin tone you choose: right-click one, hold it, or press the `Menu` key on
it for the six tones, and the one you pick becomes the tone for the rest. It is also in Control's
**Typing** group, or:

```bash
ame desktop emoji tone medium    # none, light, medium-light, medium, medium-dark or dark
```

Your recent picks are kept on this computer only, in `~/.local/state/amethystora/emoji.json`. The lists
and the names come from Unicode's emoji list (Emoji 16.0) and the Unicode CLDR, under the Unicode
License. Smile, the emoji app, is still on `Ctrl+Alt+Space`.

## Screenshots

`Print` opens GNOME's screenshot bar. Above it, for an area or the whole screen, are tools to draw on the
picture before it is saved: move a mark, a pen, a box, a filled box to hide something, a highlighter, an
arrow, text and numbered markers, in eight colours and the width the slider (or the mouse wheel) sets.
`1` to `9` pick the tools, `Ctrl+Z` undoes, `Delete` removes the mark you picked up. `Ctrl+C` copies the
picture without saving it and `Ctrl+S` saves it where you choose. Once it is taken, a card at the bottom
right opens it in Gradia, shows it in Files or opens it in your image viewer.

## Copying text from the screen

Text in a picture, a video call, an error dialog that cannot be selected, a scanned page: Gradia reads it
and copies it for you, on your machine.

1. Press `Print` and drag over the text.
2. Click **Extract Text** in the screenshot bar, or press `Ctrl+E`.
3. The first time, Gradia asks for a language. Pick it: this is the one download, of that language's
   data from GitHub, and it is yours to agree to. After it, nothing leaves the machine.
4. The text is copied at once, and Gradia says **Copied!**. Paste it anywhere; it is in the
   [clipboard history](#the-clipboard) like anything else you copy.

Good to know:

- The button and `Ctrl+E` work on an area only. They are off when you choose a window, the whole screen or a
  recording.
- The capture is saved like any screenshot, in your screenshot folder. Delete it there if you do not want it.
- The language data lives in `~/.var/app/be.alexandervanhee.gradia/data/tessdata`. Open Gradia's
  preferences to add another language.
- Gradia is one of the apps every machine comes with; if you removed it, install it again from Bazaar
  and the button comes back.

## The dock

The dock holds your pinned apps, the ones that are running, the last few you used, your folders and the trash.
`Alt+1` to `Alt+9` switch to the pinned app in that place, and open it if it is not running; hold `Super` for a
second to see the numbers on the dock. Right-click an app to pin or unpin it, or drag it off the dock: it dissolves,
and stays in the app grid. Right-clicking one of Amethystora's own apps also offers its pages: **Hotkeys** in the
Manual, **Tasks** in Notes, **Crashes** and **Apps and Services** in Logs, **Backup Status** in Backups, **Virus
Scan** in Security, and **Appearance** and **System** in Control.

An app's icon, on the dock and in the app grid alike, shows how many notifications it has waiting,
a bar while it is busy with something long, and is greyed out while the app is being updated. Do
Not Disturb hides all of that.

### How the dock moves

The icons swell in a wave under the pointer. Choose **Lift** to raise only the icon under the pointer, or **Still**,
in [Control](control.md)'s **Dock** settings or in a terminal:

    ame desktop dock magnify lift      # or swell, off
    ame desktop dock amount 180        # how far Swell grows, 120 to 220 per cent

While an app starts, a ring runs round its icon until its window opens (`ame desktop dock launch hop`, `breathe`
or `off` for another sign or none). A bar under an icon marks a running app, twice as long when it has two windows
or more (`ame desktop dock indicator dot` for a dot per window, `glow` for a light under it).

### What the dock holds

After the running apps come the last three apps you used that are not pinned (`ame desktop dock recent off` to
leave them out). GNOME's own record of app use fills them at login, and again after the screen was locked, since
the dock remembers the order you used them in nowhere but in memory; with **Usage history** off in Settings ›
Privacy, there are none.

Rest the pointer on a running app for a moment to see its windows above it, and click one to bring it forward
(`ame desktop dock previews off` to see only names). Right-click it, or hold it, to fan all its windows out over
its menu: scroll or press Left and Right to go through them, and click one or press Space.

Drop one pinned app on another and wait until it lights up, to make a folder of them. Click the folder to open it,
and click its name to rename it; **Take the folder apart** in its menu puts the apps back.

Your Downloads folder is a stack: click it to see the twelve newest things in it, newest first, and **Open in Files**
for the rest. Drag a folder from Files onto the dock to keep it there as a stack too, and drag a stack off the dock to
take it away. Files dropped on a stack are moved into that folder, or copied while you hold `Ctrl`, by Files, which
shows how far it got and can undo it. Files dropped on **Phone** go to your paired phone.

    ame desktop dock stack add ~/Documents
    ame desktop dock stack remove ~/Documents

### Where the dock lives

The dock is at the bottom of every screen, and each screen's dock shows the apps whose windows are on that screen
beside the pinned ones. Put it on the left or right, or on the main screen only:

    ame desktop dock edge left          # or right, bottom
    ame desktop dock screens primary    # or every

To have it out of the way, `ame desktop dock autohide touch`: windows then use the whole screen, and the dock slides
away while one touches it. Push the pointer against that edge to bring it back. Where a screen continues on another
past that edge, GNOME cannot keep a strip free there, so that screen's dock always hides that way.

`ame desktop dock workspace-apps on` keeps only the apps of the workspace you are on, besides the pinned ones. A click
on a pinned app whose windows are on another workspace takes you to them.

## The Amethystora menu

`Super+Alt+Space` opens one menu for the things that are otherwise scattered over Settings, the
terminal and [`ame`](terminal.md#ame):

| Entry | Does |
| --- | --- |
| Ask an agent | Opens the [AI agent](ai-agent.md), while it is on |
| Diagnose a problem | Has the agent find out why something broke, while it is on |
| Make a widget | Has the agent make a [widget](widgets.md) for the top bar, while it is on |
| Theme | The theme picker |
| Background | The wallpapers of the current theme |
| Keybindings | The hotkeys, in the terminal |
| Control | Amethystora's own settings, in [a window of their own](control.md) |
| Manual | This manual |
| Web apps | Install or remove a [web app](web-apps.md) |
| Apps and system commands | Every `ame` command, in its group |
| System | Lock, log out, restart, shut down, check for updates, the security report, the logs and backups |

Move with the arrow keys or type to filter, `Enter` to choose, `Esc` to go back. From a terminal,
`amethystora-menu` opens it, and `amethystora-menu theme`, `background`, `keys`, `webapps` or `system`
opens that part of it.

## Tiling windows

The desktop arranges the windows for you. Each workspace is a strip of windows standing side by side at
full height, and the strip can be wider than the screen. A new window opens to the right of the one
you are on, windows never overlap, and the strip scrolls to keep the focused window in view, which a
frame around it marks:

```
  ┌────────┬──────────────┬──────────────────────┬────────┐
  │  Mail  │   Terminal   │       Browser        │  Chat  │
  └────────┴──────────────┴──────────────────────┴────────┘
           ╰──────────── the screen ─────────────╯
```

Mail and Chat are still open, just off the edge. `Super+Left` scrolls back to Mail. Push the pointer
against the left or right edge of the screen to see what is beyond it, and click a window there to
go to it. On a touchpad, swipe sideways with three fingers to slide the strip, up to open the overview,
and down to see the workspaces you have been on as a pile of cards. Drag a window by its title bar and
drop it where you want it in the strip, or against a screen edge to see where it will go first; the
mouse wheel moves along the strip while you hold it. A window you resize by its edge onto another
screen floats.

The keys follow one pattern. `Super` and an arrow moves to another window. Add `Ctrl` and the window
moves instead. Add `Shift` and you go to another monitor.

### Moving around

| Key | Does |
| --- | --- |
| `Super+Left` / `Super+Right` | The window to the left / right |
| `Super+Up` / `Super+Down` | The window above / below, when windows share a column |
| `Super+Home` / `Super+End` | The first / last window on the workspace |
| `Super+[` / `Super+]` | Slide the strip; the window most in view is the one you land on when you let go of `Super` |
| `Super+Page Up` / `Super+Page Down` | The previous / next workspace, shown as cards in a row |
| `Super+Alt+Left` / `Right` / `Up` / `Down` | Swap this monitor's workspace with the one the monitor in that direction shows |
| `Ctrl+Alt+Shift` and an arrow | Move this monitor's workspace to the monitor in that direction |
| `Super+Shift` and an arrow | The monitor in that direction |

### Several monitors

With two monitors or more, each shows a workspace of its own, and a workspace is on one monitor at a
time. The monitor the pointer is on is the one you work on: move the pointer to the other monitor and
its workspace is the current one, with no animation. `Super+Page Up` and `Super+Page Down` go
through the workspaces of the monitor you are on and the empty ones, and the one you choose stays on
that monitor. A workspace chosen another way (`Super` and a number, the workspaces in the top bar, an
app's window) comes up on the monitor it was last on, and the pointer goes there; when no monitor showed
it, the monitors slide to it as GNOME's do. Swapping or moving a workspace between monitors needs one
workspace more than you have monitors. If you chose dynamic workspaces in Settings (Multitasking), they
stay dynamic: a workspace a monitor shows is kept even when it is empty, and there is always one
more than you have monitors. When you unplug the monitor you are working on, the most recent workspace
of the other monitors becomes the current one, and a monitor plugged back in shows the workspace it had,
if it is still there.

Every monitor but the main one has a top bar of its own, as tall and as round as the main one, with the
workspaces (the one that monitor shows lit) and the clock. Click a workspace there to show it on that
monitor; one another monitor shows swaps places with it. Drop a window from the overview on a workspace
to send it there. The tray, quick settings and the menus stay on the main monitor's bar, and a bar you
hide with `Super+Ctrl+B` hides on the monitor showing that workspace. In the classic layout, where the
other monitors keep their windows on every workspace, their bars show the clock alone.
`ame desktop top-bar screens off` leaves the other monitors without a bar.

### Arranging

| Key | Does |
| --- | --- |
| `Super+Ctrl+Left` / `Super+Ctrl+Right` | Move the window, with the whole column it is in, left / right along the strip |
| `Super+Ctrl+Up` / `Super+Ctrl+Down` | Move it up / down in its column |
| `Super+I` | Pull the window on the right into this column, below this one |
| `Super+O` | Push the bottom window of this column out into a column of its own |
| `Super+Shift+O` | Push this window out into a column of its own |
| `Super+Ctrl+Page Up` / `Page Down` | Move it to the previous / next workspace |
| `Super+Shift+Ctrl` and an arrow | Move it to the monitor in that direction |
| `Super+T`, keep `Super` held | Carry the window along as you move around, and drop it where you let go |

### Sizing

| Key | Does |
| --- | --- |
| `Super+R` | Step the width through 38%, 50% and 62% of the screen less its margins (`Super+Alt+R` steps back) |
| `Super+Shift+R` | The same for the height of a window in a column (`Super+Alt+Shift+R` steps back) |
| `Super` and `+` / `-` | Widen / narrow the window a step; with `Shift` as well, its height |
| `Super+F` | Fill the width of the screen, and back; maximising a window does the same |
| `Super+C` | Centre the window on the screen |
| `Super+Shift+C` | Where the strip scrolls a focused window to: just into view, the centre or the edge |
| `Super+Shift+W` | Where new windows open: to the right, to the left, or below this one |

### Floating windows

Dialogs float above the strip on their own. `Super+Ctrl+Escape` lifts the focused window out of the
strip so that it floats as well, and puts it back; every window's menu has the same as **Float above the
strip**, a dialog's too. `Super+Alt+Escape` hides every window floated that way at once, and brings them back.
A window you put on every workspace (**Always on Visible Workspace** in its menu) leaves the strip and
stays where it is.

### And the rest

| Key | Does |
| --- | --- |
| `Super+N` | A new window of the app you are in |
| `Super+Ctrl+B` | Hide or show the top bar on this workspace |

### Tiling settings

**Tiling settings** on [Control](control.md)'s **Desktop** page, or `ame desktop tiling-settings`,
opens the tiling's settings window. Every change in it applies at once.

- **Windows**: the gaps between windows and around the screen, the frame around the window you are on,
  where new windows open and which places `Super+Shift+W` goes through, how a workspace scrolls to the
  window you go to, the widths `Super+R` and the heights `Super+Shift+R` step through (shares like
  `38%, 50%, 62%`, or widths like `800px`), the width `Super+F` gives, and whether maximizing a window
  fills the width or the whole screen.
- **Motion**: how long a window takes to glide, the speed of `Super+[` and `Super+]`, the map of the
  strip and the darkening of the other windows while you move around, what the screen edges do (show the
  window beyond, go to it on a click, or after the pointer stays there), the touchpad's swipes and their
  fingers, speed and friction, the two icons in the top bar, and the size of the windows in `Alt+Tab`.
  Off as the desktop comes, for whoever wants them: the workspace's name in the top bar (a click opens
  the overview, the other button renames it), a line under the top bar marking where the window is in
  the strip, and an overview with only the floating windows or without them.
- **Workspaces**: a picture for every workspace in place of the theme's wallpaper (or none, only each
  workspace's colour), and for each workspace a name, a picture, a colour and a folder of its own. The
  colour frames the workspace's card while you go through the workspaces, and apps started while the
  workspace is shown start in its folder.
- **Keyboard**: every shortcut, including the ones the image leaves unbound (the next window, the n-th
  column, the window above or else the previous workspace, centring both ways, closing, and a switcher
  that goes through the windows used last, drawing each where its strip would show it). Click one and
  press the new keys. The first time, GNOME asks whether the window may have the keys the desktop uses
  while you press them: allow it. A shortcut another one uses as well is marked.
- **Window rules**: a window picked by its class or its title as it opens can float, open at a width,
  or open on a workspace, once or every time. `/a pattern/` matches part of a name, and `*` any window
  no other rule picks.

`gsettings` changes them too: the settings are in `org.gnome.shell.extensions.amethystora-ui.tiling`,
and the shortcuts in `org.gnome.shell.extensions.amethystora-ui.tiling.keybindings`, which
[the setup file](setup.md) keeps.

### Classic windows

If you would rather have windows that float and overlap, as on Windows and macOS, switch to the
classic layout:

```bash
ame desktop layout classic
```

It turns the tiling off, and updates leave it off. Windows then open where GNOME puts them and you drag
them by the title bar. `Super+Up` maximises and `Super+Down` restores, `Super+Left` / `Super+Right` put
a window on that half of the screen, and `Super+Shift+Left` / `Super+Shift+Right` move it to the next
monitor. `ame desktop layout tiling` brings the strip back. The first time you log in, a notification
offers the same choice, and [Control](control.md)'s **Desktop** page has it any time.

## Windows in the classic layout

What follows is for the classic layout, unless it says otherwise. `ame desktop windows` lists each of these
settings and how it is set now, and [Control](control.md)'s **Desktop** page has them under **Windows**,
**Hot corners** and **Touchpad gestures**.

### Snap layouts

Drag a window by its title bar to the top of the screen, or press `Super+Z`, and six layouts appear:
halves, two thirds and a third, thirds, quarters, the middle, and the whole screen. Move over a part of one
and the screen shows where the window will go; let go, or click, and it goes there. With `Super+Z` the
arrow keys move between the parts and `Enter` chooses. Dragging it away gives it its old size back. The top
edge itself still maximises, and `Super` and the arrows still work. Off with `ame desktop windows snap off`.

### Switching windows

`Super+Tab` and `Alt+Tab` show every window in a grid, the windows themselves, live. Keep the key down and
press `Tab` to move on, or start typing: only the windows whose app or title has those letters stay, and
the grid stays open after you let go, until `Enter` switches or `Esc` leaves everything as it was. In the
tiling layout the keys switch as GNOME does. `ame desktop windows switcher off` gives GNOME's switcher back.

### Holding Super

Hold `Super` for a second, without another key, and a card shows the main shortcuts, as they are set on
this machine, with numbers on the dock: `Alt` and a number opens the app in that place. Let go and they
fade. A quick press of `Super` still opens the overview. `ame desktop windows hold-super 1500` waits a
second and a half; `off` turns it off. This works in both layouts.

### Hot corners

Each corner of the screen can do one thing when you push the pointer into it: the overview, show the
desktop, lock the screen, a quick note, or the notifications. All four do nothing until you choose, in
Control or with `ame desktop windows corner top-right overview`. A corner fires after a short push past
the edge, so passing by never sets it off. Corners next to another screen have none, and GNOME's own hot
corner, if you turn it on in Settings, keeps the top left. The corners work in both layouts; show the
desktop only in the classic one.

### Show desktop

With `ame desktop windows show-desktop on`, clicking empty wallpaper slides every window to the edges,
leaving a sliver of each. A click anywhere, or any key, brings them back; clicking a sliver also brings
that window to the front.

### Touchpad gestures

| Fingers | Does |
| --- | --- |
| Three up | GNOME's overview; again for the app grid |
| Three sideways | GNOME's next workspace |
| Pinch with three | The app grid |
| Spread three | Show the desktop; pinch to bring the windows back |
| Three down | The windows of the app you are in, fanned out from the dock |
| Four to the left | Today and the notifications; to the right closes them |

Two fingers stay the app's own. Each is a switch: `ame desktop windows gesture pinch off`. The pinch and
four fingers work in both layouts, unless the tiling's own gestures use four fingers.

### Places

Windows go back to their places for each arrangement of screens: plug a screen in and each app's windows go
where they were the last time it was there; unplug it and they return to their laptop places. Apps cannot
place themselves on Wayland, so Amethystora keeps the places, by the screens' connectors and sizes, in
`~/.local/state/amethystora/places.json`. `ame desktop windows places forget` forgets them.

### Keep a copy in view

Choose **Keep a copy in view** in a window's menu (right-click its title bar, or `Alt+Space`): the window
goes out of sight and a small live copy of it stays on top of every workspace, in a corner. Drag it to
another corner; click it to bring the real window back. Some apps stop drawing while out of sight, and the
copy then shows their last picture. This works in both layouts.

### Dimming

`ame desktop windows dim on` draws the windows behind the one you are using a little darker, so the eye goes
to the right one. A video an app draws on its own may stay bright.

## Windows

| Key | Does |
| --- | --- |
| `Super+W` | Close the window |
| `Super+Backspace` | Resize with the arrow keys |
| `Shift+F11` | Full screen, keeping the title bar |
| `Super+H` | Minimise the window |
| `Super+Tab` / `Alt+Tab` | Switch between apps / between windows; type to filter (classic layout) |
| `Super+Z` | Snap layouts for the focused window (classic layout) |
| Hold `Super` | The main shortcuts, and numbers on the dock |
| `` Super+` `` | Switch between the windows of the app you are in |

The three lights on the right of every title bar minimise, maximise and close the window, amber, green and
red in every theme, and grey while the window is not the one you are using. Move the pointer over them and
each shows its sign.

## Motion

Minimize a window and it gathers into a drop of glass, which arcs down into the window's icon in the dock; a ring
ripples out of the icon as it lands. Bring the window back, from the dock, `Alt+Tab` or anywhere else, and the drop
rises from the icon and swells back into the window. An app you open from the dock grows out of its icon the same
way. Changed your mind half-way? Click the icon again and the window turns round from where it is.

Changing workspace has depth: the windows travel a whole screen, the wallpaper only a third of the way, and the
windows step back a little as they go.

```bash
ame desktop minimize shrink          # GNOME's own: the window shrinks into its icon
ame desktop minimize droplet         # back to the drop
ame desktop workspace-switch slide   # each workspace slides in whole
```

With [Reduce motion](themes.md#comfort) on (`ame desktop comfort reduce-motion on`), windows fade in place instead
and workspaces crossfade. With animations turned off in Settings, under Accessibility, nothing moves at all.

## Workspaces

There are always six, so `Super+3` always means the same place. A common way to use them: a browser
on 1, a terminal on 2, chat on 6. `Super+Shift+3` takes the focused window to workspace 3.
`Super+Page Up` / `Super+Page Down` go to the previous / next workspace, and
`Super+Shift+Ctrl+Left` / `Super+Shift+Ctrl+Right` move the window to the next monitor.
`Super+Ctrl+Alt+Left` / `Super+Ctrl+Alt+Right` swap the workspace you are on with the one beside it,
windows and name included.

A workspace shows its number, and after it the name of the app with most windows on it, in lighter type. Give it a
name of your own with a right click on it; **Use the app's name** in that menu goes back to the automatic one, and
`ame desktop space-names off` turns automatic names off. To move a window to another workspace, open the overview
and drag the window onto the workspace in the top bar, or onto its picture at the top of the overview.

## Extensions

These GNOME Shell extensions come with the image:

| Extension | What it does |
| --- | --- |
| Amethystora Clipboard | The [clipboard history](#the-clipboard) on `Super+Shift+V`, sealed: a copy of Clipboard Indicator |
| Amethystora UI | Amethystora's own desktop, written for this image: [tiling windows](#tiling-windows) side by side on a scrolling strip, the dock, the glass (Frost, Prism or Clear, see [Glass](themes.md#glass)) behind the panel, the overview, menus and notifications (windows you are not using are made slightly see-through), the workspaces, the meters and the tray icons in the top bar, a phone icon there while a [paired phone](hardware.md#phones) is connected, the search on `Super+Space` app search that forgives typos, drawing on a screenshot and [copying the text out of it](#copying-text-from-the-screen), and uninstalling an app from its menu, quicker animations, no popup when you change workspace, and no Activities button; the [live pill](#the-live-pill), [privacy dots](#privacy-dots), [quiet notifications](#quiet) and the volume pill |
| Logo menu | The Amethystora logo at the top left and [its menu](#the-top-bar) of the system's tools |
| Amethystora Transitions | The animation that reveals a new theme or wallpaper ([Transitions](themes.md#transitions)) |
| Amethystora Widgets | Your own [widgets](widgets.md) in the top bar; nothing until you add one |

Turn any of them off, or change their settings, in **Extensions** (Extension Manager is for finding
new ones on extensions.gnome.org, which has none of these). One thing to know: after
every image update the image's own extensions are switched back on, so that one turned off by
accident, or by a crash, does not stay off for good. Turning one off lasts until the next update. The
[classic layout](#classic-windows) is not an extension turned off, so it stays as you set it.

## Files

`Super+Shift+F` opens a Files window and `Super+E` your home folder. Folders open on a grid, where
the icon theme's folders show as the artwork they are.

### Folder colours

Select one or more folders in Files, right-click, and pick **Scripts › Folder colour ›** Amethyst, Sky, Jade, Amber,
Coral or Slate (Files lists them in alphabetical order). The folder takes that colour at once in Files, and a stack
of it in the dock takes it as you open the stack or bring the pointer to the dock. The colour is drawn by your icon
pack, so it follows when you change the pack. **No colour** takes
it away, and gives Documents, Music, Pictures and the other special folders their emblem back. A picture you set as a
folder's icon yourself is left alone, and files in the selection are left as they are. Stars are Files' own: **Star**
in the same menu.

### Back in time

Right-click a folder (or a file) in your home folder and pick **Scripts › Back in time**: [Backups](security.md#backups)
opens on that folder's timeline, where you can see it as it was and put back what is gone. Files shows its Scripts menu
only for something selected: for the folder you are in, right-click it in the folder above, or use **Open With ›
Backups**. Folders outside your home folder are not in the snapshots or the backup, and the menu says so.

The two are scripts in `~/.local/share/nautilus/scripts`, written once for each account: delete one and it stays gone.

## The trash

The trash empties itself of what you deleted more than 30 days ago. GNOME checks it every hour while
you are logged in, and the first check comes an hour after you log in. It does the same to the trash of
a USB disk or other removable drive that is plugged in at the time. A file emptied from the trash is
still in the [hourly snapshots and the backup](security.md#backups), where you have them on.

Choose another age, or never, in [Control](control.md)'s **Empty the trash**, in GNOME Settings under
**Privacy**, or in a terminal:

```bash
ame desktop privacy trash 7     # what was deleted more than a week ago
ame desktop privacy trash off   # only when you empty it yourself
```

**Empty Trash** in Files empties all of it at once, whatever the age.
