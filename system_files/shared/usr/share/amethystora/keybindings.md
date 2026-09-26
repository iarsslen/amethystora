# Hotkeys

Amethystora is built to be driven from the keyboard. `Super` is the key with the Windows or Command
logo on it. This list is also what `ujust keybindings` shows, and the Amethystora menu
(`Super+Alt+Space`) reaches most of what these keys do.

## Tiling

Tactile draws a grid over the focused monitor. Press `Super+T`, then type the letter of one zone
to move the window there, or two letters to make it span from the first to the second.

```
 ┌─────┬─────┬─────┬─────┐
 │  Q  │  W  │  E  │  R  │
 ├─────┼─────┼─────┼─────┤
 │  A  │  S  │  D  │  F  │
 └─────┴─────┴─────┴─────┘
```

| Key | Action |
| --- | --- |
| `Super+T` | Show the grid |
| `Super+T` then `Q` | Move the window to the top-left quarter-width column |
| `Super+T` then `Q` `R` | Span it across the whole top row |
| `Super+T` then `Q` `F` | Fill the screen |
| `Super+Ctrl+T` | Change the grid: columns, rows, weights, gaps |
| `Super+Up` / `Super+Down` | Maximize / unmaximize |
| `Super+Backspace` | Resize the window with the arrow keys |
| `Super+W` | Close the window |
| `Shift+F11` | Full screen, keeping the title bar |

## Workspaces

Six fixed workspaces, so a number always means the same one. The one you are on is highlighted in
the top bar on the left.

| Key | Action |
| --- | --- |
| `Super+1` … `Super+6` | Go to that workspace |
| `Super+Shift+1` … `Super+Shift+6` | Take the window there |
| `Super+Shift+Left` / `Right` | Move the window to the next monitor |
| `Alt+1` … `Alt+9` | Go to the pinned app in that dock slot |
| `Super+Tab` / `Alt+Tab` | Switch application / window |

## Launching

| Key | Action |
| --- | --- |
| `Super+Space` | Search and launch |
| `Super` | The overview: every open window, and search |
| `Super+A` | Every installed app |
| `Super+Return` | Terminal |
| `Ctrl+Alt+T` | Terminal, the way most Linux desktops open it |
| `Super+Shift+B` | Browser |
| `Super+Shift+F` | Files |
| `Super+E` | Home folder |
| `Ctrl+Shift+Esc` | Mission Center, to see and stop what is running |
| `Ctrl+Alt+Space` or `Super+.` | Emoji picker |
| `Super+Ctrl+Shift+A` | An AI agent that knows this system (`ujust toggle-agentic` turns it off) |
| `Super+F1` | This manual |

## Appearance

| Key | Action |
| --- | --- |
| `Super+Alt+Space` | The Amethystora menu |
| `Super+Ctrl+Shift+Space` | Pick a theme |
| `Super+Ctrl+Space` | Next wallpaper for this theme |
| `Super+Ctrl+D` | Switch between the light and dark theme |

The same from a terminal: `amethystora-theme list`, `amethystora-theme set <name>`,
`amethystora-theme bg next`, or `ujust theme`.

## The desktop

| Key | Action |
| --- | --- |
| `Super+V` | Notifications and the calendar |
| `Super+L` | Lock the screen |
| `Super+D` | Show the desktop |
| `Print` | Take a screenshot or record the screen |
| `Ctrl+Shift+Alt+R` | Start or stop a screen recording |
| `Super+Shift+Space` | Next keyboard layout, when you have more than one |
