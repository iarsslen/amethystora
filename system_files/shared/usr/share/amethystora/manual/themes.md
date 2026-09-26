# Themes

A theme is one palette, and everything is painted from it. Switch themes and the whole desktop
changes together: GNOME's light or dark style and accent colour, the terminal, the shell prompt, the
top bar, the wallpaper, VS Code, and this manual.

## Switching

| Key | Does |
| --- | --- |
| `Super+Ctrl+Shift+Space` | Pick a theme |
| `Super+Ctrl+D` | Flip between the light and dark version of the theme |
| `Super+Ctrl+Space` | Next wallpaper of the current theme |

The same from a terminal:

```bash
ujust theme                         # pick one from a list
amethystora-theme list              # the themes, with the current one marked
amethystora-theme set "Tokyo Night" # apply one by name
amethystora-theme toggle            # light or dark
amethystora-theme current           # which one is on
```

## The themes

| Theme | Name to use | Style |
| --- | --- | --- |
| Amethystora | `amethystora` | Dark, the default |
| Amethystora Light | `amethystora-light` | Light |
| Catppuccin Mocha | `catppuccin` | Dark |
| Catppuccin Latte | `catppuccin-latte` | Light |
| Everforest | `everforest` | Dark |
| Gruvbox | `gruvbox` | Dark |
| Matte Black | `matte-black` | Dark |
| Nord | `nord` | Dark |
| Rosé Pine Dawn | `rose-pine-dawn` | Light |
| Tokyo Night | `tokyo-night` | Dark |

The two Amethystora themes also bring the Amethystora GTK theme, the one with the three coloured
lights in the corner of every window. The others keep GNOME's own look in their accent colour.
`Super+Ctrl+D` flips a theme to its partner (Catppuccin Mocha and Latte, Amethystora and Amethystora
Light); a theme without a partner flips to Amethystora in the other mode.

## Wallpapers

Every theme comes with one wallpaper. To have more to cycle through with `Super+Ctrl+Space`, put
pictures (JPG, PNG, WebP or SVG) in a folder named after the theme:

```bash
mkdir -p ~/.config/amethystora/backgrounds/amethystora
cp ~/Pictures/mountains.jpg ~/.config/amethystora/backgrounds/amethystora/
```

`amethystora-theme bg list` shows what the current theme has to cycle through, and
`amethystora-theme bg set <picture>` sets one directly.

## Change a theme, or make your own

Themes ship read-only in `/usr/share/amethystora/themes`. A folder of the same name in
`~/.config/amethystora/themes` is laid over the top, so you only write the files you want to change.
A folder with a name of its own is a new theme. Each file is small and optional, except the palette:

| File | Holds |
| --- | --- |
| `colors.toml` | The palette: `accent`, `foreground`, `background`, `cursor`, `selection_foreground`, `selection_background`, and `color0` to `color15` |
| `light.mode` | Present, and empty, when the theme is light |
| `pair.theme` | The theme `Super+Ctrl+D` flips to |
| `accent.theme` | GNOME's accent colour: blue, teal, green, yellow, orange, red, pink, purple or slate. Without it the closest one is picked |
| `gtk.theme` | A GTK theme name, instead of GNOME's own look |
| `icons.theme` | An icon theme, instead of candy-icons |
| `cursor.theme` | A cursor theme |
| `vscode.theme` | The VS Code colour theme to switch to |
| `tophat.theme` | The colour of the top bar meters, when the accent reads badly as a thin line |
| `backgrounds/` | Wallpapers |

A theme of your own takes three commands:

```bash
mkdir -p ~/.config/amethystora/themes/sunset
cp /usr/share/amethystora/themes/amethystora/colors.toml ~/.config/amethystora/themes/sunset/
amethystora-theme set sunset
```

Edit the colours, run `amethystora-theme set sunset` again, and look at the result.

## Going further

- **How a config is written.** The terminal palette, the prompt, btop's colours and the generated
  wallpaper are templates in `/usr/share/amethystora/themed`. Copy one to
  `~/.config/amethystora/themed/` and edit the copy to change how every theme renders it.
- **Run something on every switch.** Put an executable in
  `~/.config/amethystora/hooks/theme-set.d/`. It gets the theme's name in `AMETHYSTORA_THEME` and its
  folder in `AMETHYSTORA_THEME_DIR`.
- **Your own prompt stays yours.** If you have written `~/.config/starship.toml` yourself, the theme
  leaves it alone.
- **Never edit `~/.config/amethystora/current/`.** It is rewritten on every switch.

## The boot menu

The boot menu can carry the Amethystora artwork too. It is off by default, because the boot menu
lives outside the image:

```bash
ujust setup-grub-theme
```

Run it again to take the artwork off. Once it is on, image updates keep it up to date.
