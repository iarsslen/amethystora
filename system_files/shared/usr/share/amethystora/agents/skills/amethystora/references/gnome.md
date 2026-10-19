# GNOME, keybindings, the terminal

- Read before writing: `gsettings get <schema> <key>`, `dconf dump /org/gnome/...`. Change with
  `gsettings set`, then read it back. `gsettings reset` undoes it.
- Custom keybindings live under `/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/`;
  the image uses `custom20` and up. Check `/usr/share/amethystora/keybindings.md` for a conflict
  before binding a key.
- Extensions: `gnome-extensions list --enabled`, and `gnome-extensions prefs <uuid>`.
- Windows tile with PaperWM unless the user chose classic, floating windows: `ame desktop layout
  classic` or `tiling`, remembered in `~/.config/amethystora/layout`. Change the layout with that
  command, not by turning PaperWM off yourself, or the next image update turns it back on.
- Something to show in the top bar (a widget, an indicator, a timer, a status, a switch): follow the
  `amethystora-widgets` skill, which makes it a folder in `~/.config/amethystora/widgets`. Never write
  a GNOME Shell extension for it.
- The terminal is Ptyxis. `amethystora-theme` sets its palette on every theme switch.
- Amethystora Control (`amethystora-control [page]`, `Super+Ctrl+Shift+C`) is the window over
  `/usr/libexec/amethystora-control-list`.
