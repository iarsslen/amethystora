# Getting around

The desktop is GNOME, arranged for the keyboard. Everything here also works with the mouse, but once
the keys are in your fingers you will rarely reach for it.

## The top bar

- **On the left**, the six workspaces. The one you are on is highlighted; click another to go
  there.
- **In the middle**, the clock. Click it, or press `Super+V`, for notifications and the calendar.
- **On the right**, CPU, memory and network meters, then the system menu: Wi-Fi, sound, power and
  the rest of the quick settings.

The meters and the workspaces follow the colours of the current [theme](themes.md). The bar can
also show [widgets](widgets.md) of your own, which the AI agent makes for you.

## Finding things

- `Super+Space` searches for apps, files and settings, and launches whatever you pick.
- `Super` alone opens the overview: every open window at once, with search at the top.
- `Super+A` shows every installed app.

Both searches forgive typos in app names: `calxu` still finds Calculator.

## The clipboard

`Super+Shift+V` opens the clipboard history: the last 15 things you copied. Pick one to copy it
again, type to search, and pin the ones you keep coming back to. It is also the clipboard icon in
the top bar.

The history lives only as long as your session, and only pinned items are saved. Before copying
something secret, turn on **Private mode** in the same menu, and nothing is recorded until you turn
it off.

## The dock

The dock at the bottom holds your pinned apps and the ones that are running. `Alt+1` to `Alt+9`
switch to the app in that slot, and open it if it is not running. Right-click an app to pin or unpin
it.

## The Amethystora menu

`Super+Alt+Space` opens one menu for the things that are otherwise scattered over Settings, the
terminal and [`ame`](terminal.md#ame):

| Entry | Does |
| --- | --- |
| Ask an agent | Opens the [AI agent](ai-agent.md) |
| Diagnose a problem | Has the agent find out why something broke |
| Make a widget | Has the agent make a [widget](widgets.md) for the top bar |
| Theme | The theme picker |
| Background | The wallpapers of the current theme |
| Keybindings | The hotkeys, in the terminal |
| Control | Amethystora's own settings, in [a window of their own](control.md) |
| Manual | This manual |
| Web apps | Install or remove a [web app](web-apps.md) |
| Apps and system commands | Every `ame` command, in its group |
| System | Lock, log out, restart, shut down, check for updates, the security report |

Move with the arrow keys or type to filter, `Enter` to choose, `Esc` to go back.

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
go to it. On a touchpad, swipe with three fingers to slide the strip.

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
| `Super+Shift+R` | The same for the height of a window in a column |
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
| `Super+Tab` / `Alt+Tab` | Switch between apps / between windows |

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
| Clipboard Indicator | The [clipboard history](#the-clipboard) on `Super+Shift+V` |
| Blur my Shell | The frosted glass behind the panel, the overview and windows |
| Just Perfection | Quicker animations, and no popup when you change workspace |
| AppIndicator | Tray icons for apps that use them |
| Caffeine | A switch in the quick settings that keeps the screen awake |
| GSConnect | Your Android phone: notifications, files, clipboard, texts |
| Logo Menu | The Amethystora logo at the top left: shortcuts to system tools |
| Gradia | Annotate a screenshot straight after taking it |
| Bazaar integration | Connects the shell to Bazaar, the software centre |

Turn any of them off, or change their settings, in **Extension Manager**. One thing to know: after
every image update the image's own extensions are switched back on, so that one turned off by
accident, or by a crash, does not stay off for good. Turning one off lasts until the next update. The
exception is PaperWM under the [classic layout](#classic-windows), which stays off.

## Files

`Super+Shift+F` opens a Files window and `Super+E` your home folder. Folders open on a grid, where
the icon theme's folders show as the artwork they are.
