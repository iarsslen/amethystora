# Getting around

The desktop is GNOME, arranged for the keyboard. Everything here also works with the mouse, but once
the keys are in your fingers you will rarely reach for it.

## The top bar

- **On the left**, the Amethystora logo, a menu of the system's tools: about this computer, this
  manual, Settings, Bazaar, Extension Manager, Mission Center, the terminal and DistroShelf. A
  middle click on it opens the overview. Then the six workspaces: the one you are on is
  highlighted; click another to go there.
- **In the middle**, the clock. Click it, or press `Super+V`, for notifications and the calendar.
- **On the right**, CPU, memory and network meters, then the system menu: Wi-Fi, sound, power and
  the rest of the quick settings.

The meters and the workspaces follow the colours of the current [theme](themes.md). The bar can
also show [widgets](widgets.md) of your own, which the AI agent makes for you once you turn it on.

## Finding things

- `Super+Space` searches for apps, files and settings, and launches whatever you pick.
- `Super` alone opens the overview: every open window at once, with search at the top.
- `Super+A` shows every installed app. Some are gathered in folders: **Utilities** (Flatseal, Warehouse,
  Extension Manager, Firmware, Ignition, Impression, Refine and the like), **Productivity**,
  **Development**, **Containers**, **Games**, **Gaming Utilities** and **Wine**.

Both searches forgive typos in app names: `calxu` still finds Calculator.

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

- The button works on an area only. It is off when you choose a window, the whole screen or a recording.
- The capture is saved like any screenshot, in your screenshot folder. Delete it there if you do not want it.
- The language data lives in `~/.var/app/be.alexandervanhee.gradia/data/tessdata`. Open Gradia's
  preferences to add another language.
- Gradia is one of the apps every machine comes with; if you removed it, install it again from Bazaar
  and the button comes back.

## The dock

The dock at the bottom holds your pinned apps and the ones that are running. `Alt+1` to `Alt+9`
switch to the app in that slot, and open it if it is not running. Right-click an app to pin or unpin
it. Right-clicking one of Amethystora's own apps also offers its pages: **Hotkeys** in the Manual,
**Tasks** in Notes, **Crashes** and **Apps and Services** in Logs, **Backup Status** in Backups,
**Virus Scan** in Security, and **Appearance** and **System** in Control.

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

PaperWM arranges the windows for you. Each workspace is a strip of windows standing side by side at
full height, and the strip can be wider than the screen. A new window opens to the right of the one
you are on, windows never overlap, and the strip scrolls to keep the focused window in view:

```
  ┌────────┬──────────────┬──────────────────────┬────────┐
  │  Mail  │   Terminal   │       Browser        │  Chat  │
  └────────┴──────────────┴──────────────────────┴────────┘
           ╰──────────── the screen ─────────────╯
```

Mail and Chat are still open, just off the edge. `Super+Left` scrolls back to Mail. Push the pointer
against the left or right edge of the screen to see what is beyond it, and click a window there to
go to it. On a touchpad, swipe sideways with three fingers to slide the strip, and up or down to change
workspace.

The keys follow one pattern. `Super` and an arrow moves to another window. Add `Ctrl` and the window
moves instead. Add `Shift` and you go to another monitor.

### Moving around

| Key | Does |
| --- | --- |
| `Super+Left` / `Super+Right` | The window to the left / right |
| `Super+Up` / `Super+Down` | The window above / below, when windows share a column |
| `Super+Home` / `Super+End` | The first / last window on the workspace |
| `Super+[` / `Super+]` | Slide the strip without changing the focused window |
| `Super+Shift` and an arrow | The monitor in that direction |

### Arranging

| Key | Does |
| --- | --- |
| `Super+Ctrl+Left` / `Super+Ctrl+Right` | Move the window left / right along the strip |
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
| `Super+R` | Step the width through 38%, 50% and 62% of the screen (`Super+Alt+R` steps back) |
| `Super+Shift+R` | The same for the height of a window in a column (`Super+Alt+Shift+R` steps back) |
| `Super` and `+` / `-` | Widen / narrow the window a step; with `Shift` as well, its height |
| `Super+F` | Fill the width of the screen, and back |
| `Super+C` | Centre the window on the screen |
| `Super+Shift+C` | Where the strip scrolls a focused window to: just into view, the centre or the edge |
| `Super+Shift+W` | Where new windows open: to the right, to the left, or below this one |

### Floating windows

Dialogs float above the strip on their own. `Super+Ctrl+Escape` lifts the focused window out of the
strip so that it floats as well, and puts it back. `Super+Alt+Escape` hides every window floated
that way at once, and brings them back.

### And the rest

| Key | Does |
| --- | --- |
| `Super+N` | A new window of the app you are in |
| `Super+Ctrl+B` | Hide or show the top bar on this workspace |

PaperWM's settings are under **PaperWM** in **Extension Manager**. That includes the gaps, the
widths `Super+R` steps through, and every key, some of which this page leaves out.

### Classic windows

If you would rather have windows that float and overlap, as on Windows and macOS, switch to the
classic layout:

```bash
ame desktop layout classic
```

It turns PaperWM off, and updates leave it off. Windows then open where GNOME puts them and you drag
them by the title bar. `Super+Up` maximises and `Super+Down` restores, `Super+Left` / `Super+Right` put
a window on that half of the screen, and `Super+Shift+Left` / `Super+Shift+Right` move it to the next
monitor. `ame desktop layout tiling` brings the strip back. The first time you log in, a notification
offers the same choice, and [Control](control.md)'s **Desktop** page has it any time.

## Windows

| Key | Does |
| --- | --- |
| `Super+W` | Close the window |
| `Super+Backspace` | Resize with the arrow keys |
| `Shift+F11` | Full screen, keeping the title bar |
| `Super+H` | Minimise the window |
| `Super+Tab` / `Alt+Tab` | Switch between apps / between windows |
| `` Super+` `` | Switch between the windows of the app you are in |

The buttons on the right of every title bar minimise, maximise and close.

## Workspaces

There are always six, so `Super+3` always means the same place. A common way to use them: a browser
on 1, a terminal on 2, chat on 6. `Super+Shift+3` takes the focused window to workspace 3.
`Super+Page Up` / `Super+Page Down` go to the previous / next workspace, and
`Super+Shift+Ctrl+Left` / `Super+Shift+Ctrl+Right` move the window to the next monitor.

## Extensions

These GNOME Shell extensions come with the image:

| Extension | What it does |
| --- | --- |
| PaperWM | [Tiling](#tiling-windows): windows side by side on a scrolling strip |
| Space Bar | The workspaces in the top bar |
| TopHat | The CPU, memory and network meters |
| Dash to Dock | The dock |
| Search Light | The search on `Super+Space` |
| Fuzzy App Search | App search that forgives typos |
| Amethystora Clipboard | The [clipboard history](#the-clipboard) on `Super+Shift+V`, sealed: a copy of Clipboard Indicator |
| Blur my Shell | The frosted glass behind the panel, the overview, menus and notifications, and windows you are not using made slightly see-through (**Applications** in its settings) |
| Amethystora UI | Amethystora's own desktop, written for this image: quicker animations, no popup when you change workspace, and no Activities button |
| AppIndicator | Tray icons for apps that use them |
| Caffeine | Off until you turn it on in Extension Manager; then a switch in the quick settings keeps the screen awake |
| GSConnect | Your Android phone, on the [networks you name home](security.md#on-from-the-start): notifications, files, clipboard, texts. Off until you [turn it on](hardware.md#phones) |
| Logo menu | The Amethystora logo at the top left and [its menu](#the-top-bar) of the system's tools |
| Gradia | Annotate a screenshot straight after taking it, in the Gradia app, and [copy the text out of it](#copying-text-from-the-screen) |
| Bazaar integration | Connects the shell to Bazaar, the software centre |
| Amethystora Transitions | The animation that reveals a new theme or wallpaper ([Transitions](themes.md#transitions)) |
| Amethystora Widgets | Your own [widgets](widgets.md) in the top bar; nothing until you add one |

Turn any of them off, or change their settings, in **Extension Manager**. One thing to know: after
every image update the image's own extensions are switched back on, so that one turned off by
accident, or by a crash, does not stay off for good. Turning one off lasts until the next update. The
exception is PaperWM under the [classic layout](#classic-windows), which stays off.

## Files

`Super+Shift+F` opens a Files window and `Super+E` your home folder. Folders open on a grid, where
the icon theme's folders show as the artwork they are.

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
