# Themes

`amethystora-theme list | set "<name>" | toggle | current | reload | bg next|list|set`.

A theme is a directory of small files (see `/usr/lib/amethystora/theme/lib.sh` for the full list):
`colors.toml` (the palette), `accent.theme`, `light.mode`, `pair.theme`, `gtk.theme`,
`icons.theme`, `vscode.theme`, `backgrounds.list` (wallpapers elsewhere on the system, the first
one is what the theme opens on), `backgrounds/`.

- Tweak a shipped theme: create `~/.config/amethystora/themes/<name>/` holding only the files that
  differ; they are copied over the shipped ones. A directory that exists only there is a new theme.
- Change how a config is rendered: copy the template from `/usr/share/amethystora/themed/` to
  `~/.config/amethystora/themed/` and edit the copy.
- Run something on every theme switch: an executable in `~/.config/amethystora/hooks/theme-set.d/`.
- Extra wallpapers: `~/.config/amethystora/backgrounds/<theme>/`, cycled with `Super+Ctrl+Space`
  after the theme's own pictures (`amethystora-theme bg list` shows the order). The
  `wallpaper*.svg` rendered from the palette are only used by a theme with no pictures at all.
  To make a theme open on a different picture, lay a `backgrounds.list` over it in
  `~/.config/amethystora/themes/<theme>/` with that picture first.
- A light theme sets Blur my Shell's `dash-to-dock/style-dash-to-dock` to 2 (a dark tint on the
  dock) and a dark theme resets it, on every switch, so a change made to that key by hand only
  lasts until the next switch.
- The animation that reveals a new theme or wallpaper is the extension
  `amethystora-transitions@iarsslen.github.io`: `ame desktop transition
  <grow|outer|wipe|wave|fade|random|none> [milliseconds]`, which sets
  `org.gnome.shell.extensions.amethystora-transitions` `style` and `duration`. It does nothing while
  GNOME's animations are off.
- `ame desktop background <picture>` shows one of the pictures `amethystora-theme bg list` names.
- After a change, run `amethystora-theme set "$(amethystora-theme current)"` and check for errors.

Never edit `~/.config/amethystora/current/`: it is regenerated on every switch.
