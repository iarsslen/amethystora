# GNOME, keybindings, the terminal

- Read before writing: `gsettings get <schema> <key>`, `dconf dump /org/gnome/...`. Change with
  `gsettings set`, then read it back. `gsettings reset` undoes it.
- Custom keybindings live under `/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/`;
  the image uses `custom20` and up. Check `/usr/share/amethystora/keybindings.md` for a conflict
  before binding a key.
- Extensions: `gnome-extensions list --enabled`, and `gnome-extensions prefs <uuid>`.
- Windows tile unless the user chose classic, floating windows: `ame desktop layout classic` or
  `tiling`, which sets `enabled` in `org.gnome.shell.extensions.amethystora-ui.tiling`. Change the layout
  with that command rather than by turning the Amethystora UI extension off, which the next image update
  turns back on.
- The trash empties itself of what was deleted more than 30 days ago: `ame desktop privacy trash
  DAYS|off` changes it, not `gsettings set`, which the running session would not read until the next login.
- Something to show in the top bar (a widget, an indicator, a timer, a status, a switch): follow the
  `amethystora-widgets` skill, which makes it a folder in `~/.config/amethystora/widgets`. Never write
  a GNOME Shell extension for it.
- The terminal is kitty (Ptyxis is the second choice). Its settings are `/etc/xdg/kitty/kitty.conf`, over which the
  account's `~/.config/kitty/kitty.conf` wins; `amethystora-theme` renders its colours on every theme switch and
  asks the open windows to read them again.
- Amethystora Control (`amethystora-control [page]`, `Super+Ctrl+Shift+C`) is the window over
  `/usr/libexec/amethystora-control-list`.
