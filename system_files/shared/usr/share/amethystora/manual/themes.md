# Themes

A theme is one palette, and everything is painted from it. Switch themes and the whole desktop
changes together: GNOME's light or dark style and accent colour, the terminal, the shell prompt, the
top bar, the dock, the wallpaper, VSCodium, and this manual. Each theme also has its own
[style](#styles), [font](#fonts), [icons](#icons) and pointer, and you can keep the first three whatever the theme (a pointer you
choose yourself in Settings stays too). A light theme gives the dock a faint dark
tint, so its icons still stand out on a pale wallpaper. The colours reach the applications too, at a contrast
that reads: see [Colours in applications](#colours-in-applications).

## Switching

| Key | Does |
| --- | --- |
| `Super+Ctrl+Shift+Space` | Pick a theme |
| `Super+Ctrl+D` | Flip between the light and dark version of the theme |
| `Super+Ctrl+Space` | Next wallpaper of the current theme |

The same from a terminal:

```bash
ame desktop theme                   # pick one from a list, or name it: ame desktop theme Nord
amethystora-theme list              # the themes, with the current one marked
amethystora-theme set "Tokyo Night" # apply one by name
amethystora-theme toggle            # light or dark
amethystora-theme current           # which one is on
amethystora-theme reload            # apply the current one again, after editing its files
```

Or open [Control](control.md) (`Super+Ctrl+Shift+C`), whose **Appearance** page shows every theme in
its own colours, and the current theme's wallpapers. Amethystora's own apps take on the theme's colours
as it changes.

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

Every window has the three coloured lights in its corner. The two Amethystora themes also bring the
Amethystora GTK theme for the GTK 3 applications that draw with a theme of their own; the others use adw-gtk3,
GNOME's own look, in the theme's colours.
`Super+Ctrl+D` flips a theme to its partner (Catppuccin Mocha and Latte, Amethystora and Amethystora
Light); a theme without a partner flips to Amethystora in the other mode.

## Colours in applications

The theme's colours reach every application, not only the ones that are Amethystora's own:

- **GNOME's and libadwaita's applications** (Files, Settings, Text Editor, Calendar and most of what a
  Flatpak installs) are drawn in the theme's surfaces, text, accent and status colours, in place of Adwaita's
  grey. The accent is the theme's own, not the nearest of GNOME's nine, and a text colour on it, a link, a
  dimmed label, an error and the line round a field are each moved in lightness until they read: 4.5 to 1 for
  text and 3 to 1 for a line, on every surface they are drawn on. The hue stays the theme's.
- **GTK 3 applications** that draw with adw-gtk3 take the same palette.
- **KDE and Qt applications** take it from `~/.config/kdeglobals` (a Flatpak of KDE's lets itself at it).
  A `kdeglobals` with colours of your own, which this did not write, is left as it is.
- **VSCodium**, on the developer image, takes the editor, sidebars, status bar, terminal and syntax colours,
  merged into your settings over its own Default Dark Modern or Default Light Modern. A colour of yours that
  the theme does not name stays.
- **The terminal, the prompt, btop and the pointer** follow too: the white Breeze Light on a dark theme, the dark
  Breeze on a light one.

While High Contrast is on (Settings, Accessibility), libadwaita applications keep their own high-contrast
colours and the palette steps aside, and comes back when it is switched off. An application that is open
takes a new theme's colours, and a new style's corners, the next time it starts; GNOME Shell, Amethystora's own
apps and the terminal change at once.

## Wallpapers

Every theme comes with three wallpapers of made-up places drawn in its own colours, and switching to
a theme puts its first one on the desktop: a neon city in the rain for Tokyo Night, an aurora over a
mountain lake for Nord, misty pines for Everforest, a desert sunset for Gruvbox, peaks under a
pastel moon for Catppuccin, an eclipse for Matte Black, and so on. `Super+Ctrl+Space` cycles
through them. The two Amethystora themes open on a cut stone's facets, and also have the crystal
field and a night sky of violet smoke; GNOME's Settings offers those under Appearance.

To add your own, put pictures (JPG, PNG, WebP or SVG) in a folder named after the theme. They come
after the theme's own pictures:

```bash
mkdir -p ~/.config/amethystora/backgrounds/amethystora
cp ~/Pictures/mountains.jpg ~/.config/amethystora/backgrounds/amethystora/
```

`amethystora-theme bg list` shows what the current theme has to cycle through, and
`ame desktop background <picture>` sets one of those directly; without a picture it shows the next, as
`Super+Ctrl+Space` does.

## Transitions

A new theme or wallpaper does not simply appear. The screen holds still for a moment while everything
changes underneath it, then the new desktop opens out in a circle from the pointer, with a glow in the
theme's accent colour along the edge. It works the same whichever way you make the change: the keys
above, GNOME's Settings, or the Dark Style button in the quick settings.

```bash
ame desktop transition         # pick one from a list
ame desktop transition wave    # or name it
```

| Transition | Looks like |
| --- | --- |
| `grow` | A circle opens from the pointer. The default |
| `outer` | The new desktop closes in on the pointer from the edges |
| `wipe` | A soft edge sweeps across at an angle |
| `wave` | The same, with a wavy edge |
| `fade` | A plain crossfade |
| `random` | One of the first four, at any angle |
| `none` | No animation: the wallpaper fades as GNOME fades it |

A transition takes 1.2 seconds. To change that, give it in milliseconds after the transition, from 200
to 5000, or move the slider on Control's **Appearance** page:

```bash
ame desktop transition grow 800
```

There are no transitions while animations are turned off in Settings, under Accessibility. They come
from the Amethystora Transitions extension, which Extension Manager can turn off.

## Styles

Each theme comes with a style: the shape the whole desktop is drawn in, from the top bar to the
menus, quick settings, notifications, password prompts and other dialogs, volume and brightness
alerts, buttons, switches and entries, the dock, and the applications' windows.

| Style | Looks like | The theme it comes with |
| --- | --- | --- |
| `islands` | A floating pill for each part of the top bar, the workspaces as dots, soft corners everywhere | Amethystora Light, Catppuccin Latte, Nord |
| `floating` | One rounded top bar held off the edge of the screen | Amethystora, Everforest |
| `hairline` | A thin, solid top bar, crisp corners and fine lines | Matte Black |
| `capsule` | The clock in a dark capsule, the rest of the top bar bare over the wallpaper, everything else a pill | Rosé Pine Dawn |
| `terminal` | Monospace, square corners and lined edges, like a terminal | Gruvbox |
| `segments` | The top bar in blocks of the theme's colours | Catppuccin Mocha |
| `neon` | Dark glass outlined and glowing in the theme's accent colour | Tokyo Night |

In the applications every control is rounded by the style: buttons, entries, tabs, menu rows, switches,
cards and lists, popovers, dialogs, tooltips and toasts, and the sliders' troughs. A group of buttons or fields
is rounded at the ends of the group and straight between its members, and the two halves of a split button
meet. Floating leaves the applications their own corners.

Any style goes with any theme. `ame desktop style neon` keeps neon whatever the theme, and
`ame desktop style theme` goes back to the theme's own. Run `ame desktop style` alone to pick from a list,
or use the **Style** choice on Control's **Appearance** page. The desktop changes at once. An application
that is already open takes the new shape the next time it starts.

## Fonts

Each theme is written in a font of its own, used by the desktop and the applications:

| Theme | Font |
| --- | --- |
| Amethystora, Amethystora Light | Quicksand |
| Catppuccin Mocha, Catppuccin Latte | Nunito |
| Everforest | Manrope |
| Gruvbox | JetBrains Mono |
| Matte Black | Geist |
| Nord | Inter |
| Rosé Pine Dawn | Figtree |
| Tokyo Night | Space Grotesk |

`ame desktop font "Space Grotesk"` keeps a font whatever the theme. Any font installed on the computer
works, by its name as Fonts shows it. `ame desktop font theme` goes back to the theme's own, and
`ame desktop font` alone offers the fonts the themes use, with Adwaita Sans, GNOME's own. Control has the
same choice under **Appearance**. Documents are set in the same font, a size up.

The terminal, code and Text Editor have a monospace font of their own, which goes with the theme's:

| Theme | Monospace font |
| --- | --- |
| Amethystora, Amethystora Light, Gruvbox | JetBrains Mono |
| Catppuccin Mocha, Catppuccin Latte | Fira Code |
| Everforest | DM Mono |
| Matte Black | Geist Mono |
| Nord | IBM Plex Mono |
| Rosé Pine Dawn | Victor Mono |
| Tokyo Night | Space Mono |

`ame desktop mono-font "Fira Code"` keeps one whatever the theme, `ame desktop mono-font theme` goes back,
and Control has the choice too. kitty takes it at once, and so does the top bar of the terminal style.

## Icons

Nine icon packs are drawn for Amethystora, each icon in colours of its own, so that a theme has one
that reads on its ground and suits its style:

| Pack | Draws each icon as | The themes it comes with |
| --- | --- | --- |
| **Glass** | A gradient with a glass sheen | Amethystora |
| **Glass for light** | The same, its colours deepened to read on a light ground | Amethystora Light |
| **Duotone** | A gradient, its details in a contrasting one | Catppuccin Mocha |
| **Clay** | A soft matte volume, a highlight above and a shade below | Catppuccin Latte, Rosé Pine Dawn |
| **Muted** | Glass in quieter colours with half the sheen | Everforest, Nord |
| **Pixel** | Duotone on a grid of 16 pixels | Gruvbox |
| **Line** | One even outline, in colours that read on every theme | Matte Black |
| **Neon** | Outlines lit in colours of their own | Tokyo Night |
| **Neon for light** | Neon, its colours deepened for a light ground | None: pick it on a light theme |

They draw Amethystora's apps, GNOME's, the system's, folders, file types,
devices, dialogs and the pictograms of a job, and the apps of other makers by what each one does:
a terminal as a terminal, a mail app as an envelope, a music player as a note.

An app whose icon is its maker's logo keeps it. Firefox, Thunderbird, Steam, a JetBrains IDE and
others like them show the icon their maker drew, exactly as it ships, with no tile or frame added:
a logo is a trademark, and how it looks is its owner's to decide. That is why the dock can mix the two.

`ame desktop icons clay` (or the name of any pack: `glass`, `glass-light`, `neon`, `neon-light`, `duotone`,
`line`, `clay`, `muted`, `pixel`) picks one whatever the theme, and
`ame desktop icons theme` goes back to what the theme chooses. Control has the same choice under
Appearance.

## Change a theme, or make your own

Themes ship read-only in `/usr/share/amethystora/themes`. A folder of the same name in
`~/.config/amethystora/themes` is laid over the top, so you only write the files you want to change.
A folder with a name of its own is a new theme. Each file is small and optional, except the palette:

| File | Holds |
| --- | --- |
| `colors.toml` | The palette: `accent`, `foreground`, `background`, `cursor`, `selection_foreground`, `selection_background`, and `color0` to `color15`. A palette whose `color1`, `color2` and `color3` are not a red, a green and a yellow can add `error`, `success` and `warning`, which the applications' status colours come from |
| `light.mode` | Present, and empty, when the theme is light |
| `pair.theme` | The theme `Super+Ctrl+D` flips to |
| `accent.theme` | GNOME's accent colour: blue, teal, green, yellow, orange, red, pink, purple or slate. Without it the closest one is picked |
| `gtk.theme` | A GTK theme name, instead of GNOME's own look |
| `icons.theme` | An icon theme, instead of Glass (or Glass for light, on a light theme) |
| `style.theme` | The style: `islands`, `floating`, `hairline`, `capsule`, `terminal`, `segments` or `neon`. Without it, floating |
| `font.theme` | The font's name, instead of Adwaita Sans |
| `mono.theme` | The monospace font's name, instead of JetBrains Mono |
| `cursor.theme` | A cursor theme, instead of Adwaita |
| `vscode.theme` | A VSCodium colour theme to switch to, instead of the palette's colours merged into its settings |
| `shell-workspaces.css`, `shell-meters.css` | The top bar's colours for the workspaces and the meters, in GNOME Shell's CSS, instead of the ones drawn from the palette |
| `backgrounds/` | Wallpapers |
| `backgrounds.list` | Wallpapers kept elsewhere on the system, one path per line. The first is the one the theme opens on |

A theme with no pictures of its own gets four drawn in its colours: a soft glow, hills in a haze, a
contour map and flowing ribbons.

A theme of your own takes three commands:

```bash
mkdir -p ~/.config/amethystora/themes/sunset
cp /usr/share/amethystora/themes/amethystora/colors.toml ~/.config/amethystora/themes/sunset/
amethystora-theme set sunset
```

Edit the colours, run `amethystora-theme set sunset` again, and look at the result.

## Going further

- **How a config is written.** The terminal palette, the prompt, btop's colours and the drawn
  wallpapers are templates in `/usr/share/amethystora/themed`. Copy one to
  `~/.config/amethystora/themed/` and edit the copy to change how every theme renders it.
- **Run something on every switch.** Put an executable in
  `~/.config/amethystora/hooks/theme-set.d/`. It gets the theme's name in `AMETHYSTORA_THEME` and its
  folder in `AMETHYSTORA_THEME_DIR`.
- **Your own prompt stays yours.** If you have written `~/.config/starship.toml` yourself, the theme
  leaves it alone.
- **Never edit `~/.config/amethystora/current/`.** It is rewritten on every switch.

## The boot menu

The boot menu carries the Amethystora artwork too. The boot menu lives outside the image, so the
artwork is put on once, as the machine first starts with it, and shows from the restart after;
once taken off, it stays off:

```bash
ame desktop boot-menu
```

It says whether the artwork is on and asks whether to put it on or take it off; `ame desktop boot-menu on`
and `off` skip the question. The switch on Control's **Appearance** page opens the same in a terminal. Once it is on, image updates keep it up to date.
