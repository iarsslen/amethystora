# Getting around

The desktop is GNOME, arranged for the keyboard. Everything here also works with the mouse, but once
the keys are in your fingers you will rarely reach for it.

## The top bar

- **On the left**, the six workspaces. The one you are on is highlighted; click another to go
  there.
- **In the middle**, the clock. Click it, or press `Super+V`, for notifications and the calendar.
- **On the right**, CPU, memory and network meters, then the system menu: Wi-Fi, sound, power and
  the rest of the quick settings.

The meters and the workspaces follow the colours of the current [theme](themes.md).

## Finding things

- `Super+Space` searches for apps, files and settings, and launches whatever you pick.
- `Super` alone opens the overview: every open window at once, with search at the top.
- `Super+A` shows every installed app.

## The dock

The dock at the bottom holds your pinned apps and the ones that are running. `Alt+1` to `Alt+9`
switch to the app in that slot, and open it if it is not running. Right-click an app to pin or unpin
it.

## The Amethystora menu

`Super+Alt+Space` opens one menu for the things that are otherwise scattered over Settings, the
terminal and `ujust`:

| Entry | Does |
| --- | --- |
| Ask an agent | Opens the [AI agent](ai-agent.md) |
| Diagnose a problem | Has the agent find out why something broke |
| Theme | The theme picker |
| Background | The wallpapers of the current theme |
| Keybindings | The hotkeys, in the terminal |
| Manual | This manual |
| Web apps | Install or remove a [web app](web-apps.md) |
| Apps and system commands | Every `ujust` recipe |
| System | Lock, log out, restart, shut down, check for updates, the security report |

Move with the arrow keys or type to filter, `Enter` to choose, `Esc` to go back.

## Tiling windows

Windows tile onto a grid instead of being dragged into place. Press `Super+T` and a grid of four
columns and two rows appears over the focused monitor, with a letter in every box:

```
 ┌─────┬─────┬─────┬─────┐
 │  Q  │  W  │  E  │  R  │
 ├─────┼─────┼─────┼─────┤
 │  A  │  S  │  D  │  F  │
 └─────┴─────┴─────┴─────┘
```

Type one letter to put the window in that box, or two to stretch it from the first box to the
second. `Q` `R` fills the top row, `Q` `F` the whole screen, `W` `D` the middle half. Your left hand
never leaves the keys it is already on.

`Super+Ctrl+T` changes the grid itself: the number of columns and rows, how wide each one is, and
the gaps between windows.

## Windows

| Key | Does |
| --- | --- |
| `Super+W` | Close the window |
| `Super+Up` / `Super+Down` | Maximise / restore |
| `Super+Backspace` | Resize with the arrow keys |
| `Shift+F11` | Full screen, keeping the title bar |
| `Super+Tab` / `Alt+Tab` | Switch between apps / between windows |

The buttons on the right of every title bar minimise, maximise and close.

## Workspaces

There are always six, so `Super+3` always means the same place. A common way to use them: a browser
on 1, a terminal on 2, chat on 6. `Super+Shift+3` takes the focused window to workspace 3, and
`Super+Shift+Left` / `Super+Shift+Right` move it to the next monitor.

## Extensions

These GNOME Shell extensions come with the image:

| Extension | What it does |
| --- | --- |
| Tactile | The tiling grid on `Super+T` |
| Space Bar | The workspaces in the top bar |
| TopHat | The CPU, memory and network meters |
| Dash to Dock | The dock |
| Search Light | The search on `Super+Space` |
| Blur my Shell | The frosted glass behind the panel, the overview and windows |
| Just Perfection | Quicker animations, and no popup when you change workspace |
| AppIndicator | Tray icons for apps that use them |
| Caffeine | A switch in the quick settings that keeps the screen awake |
| GSConnect | Your Android phone: notifications, files, clipboard, texts |
| Logo Menu | The gem at the top left: shortcuts to system tools |
| Gradia | Annotate a screenshot straight after taking it |
| Bazaar integration | Connects the shell to Bazaar, the software centre |

Turn any of them off, or change their settings, in **Extension Manager**. One thing to know: after
every image update the image's own extensions are switched back on, so that one turned off by
accident, or by a crash, does not stay off for good. Turning one off lasts until the next update.

## Files

`Super+Shift+F` opens a Files window and `Super+E` your home folder. Folders open on a grid, where
the icon theme's folders show as the artwork they are.
