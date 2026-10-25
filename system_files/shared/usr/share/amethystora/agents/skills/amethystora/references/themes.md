# Themes

`amethystora-theme list | set "<name>" | toggle | current | reload | bg next|list|set`.

A theme is a directory of small files (see `/usr/lib/amethystora/theme/lib.sh` for the full list):
`colors.toml` (the palette), `accent.theme`, `light.mode`, `pair.theme`, `gtk.theme`,
`icons.theme`, `style.theme`, `font.theme`, `vscode.theme`, `backgrounds.list` (wallpapers elsewhere on the
system, the first one is what the theme opens on), `backgrounds/`.

- Tweak a shipped theme: create `~/.config/amethystora/themes/<name>/` holding only the files that
  differ; they are copied over the shipped ones. A directory that exists only there is a new theme.
- Change how a config is rendered: copy the template from `/usr/share/amethystora/themed/` to
  `~/.config/amethystora/themed/` and edit the copy.
- Icons: three packs, `ame desktop icons glass|neon|duotone|theme`. The choice is kept in `~/.config/amethystora/icons`,
  which wins over the theme's own `icons.theme`; `theme` removes it. Without either, a dark theme gets Glass and a light one Duotone.
- Style, the shape of the whole desktop (top bar, menus, notifications, dialogs, OSDs, buttons, the applications'
  windows and controls): `ame desktop style islands|floating|hairline|capsule|terminal|segments|neon|theme`, kept in
  `~/.config/amethystora/style` over the theme's `style.theme`. The shell draws it from
  `/usr/share/amethystora/themed/shell-styles.css.tpl`, the applications from `style-<style>.gtk.css.tpl`; it is the
  key `org.gnome.shell.extensions.amethystora-ui.style` `style`, which a theme switch writes, so never set that key
  alone.
- Font: `ame desktop font "<family>"|theme`, kept in `~/.config/amethystora/font` over the theme's `font.theme`; any
  installed family works (`fc-list : family`).
- Run something on every theme switch: an executable in `~/.config/amethystora/hooks/theme-set.d/`.
- Extra wallpapers: `~/.config/amethystora/backgrounds/<theme>/`, cycled with `Super+Ctrl+Space`
  after the theme's own pictures (`amethystora-theme bg list` shows the order). The
  `wallpaper*.svg` rendered from the palette are only used by a theme with no pictures at all.
  To make a theme open on a different picture, lay a `backgrounds.list` over it in
  `~/.config/amethystora/themes/<theme>/` with that picture first.
- A light theme gets a faint dark veil over the dock's glass: Amethystora UI's `dock` module draws it because the theme is
  light, with nothing to set and no key to reset.
- The animation that reveals a new theme or wallpaper is the extension
  `amethystora-transitions@iarsslen.github.io`: `ame desktop transition
  <grow|outer|wipe|wave|fade|random|none> [milliseconds]`, which sets
  `org.gnome.shell.extensions.amethystora-transitions` `style` and `duration`. It does nothing while
  GNOME's animations are off.
- `ame desktop background <picture>` shows one of the pictures `amethystora-theme bg list` names.
- After a change, run `amethystora-theme set "$(amethystora-theme current)"` and check for errors.

Never edit `~/.config/amethystora/current/`: it is regenerated on every switch.
