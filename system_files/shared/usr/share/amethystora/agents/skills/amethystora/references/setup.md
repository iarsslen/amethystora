# The setup file (ame setup)

- `ame setup save` writes the user's setup to `~/.config/amethystora/setup.json` (or a file named
  after it): image and stream, Flatpaks, Homebrew, amepkg containers, extensions, theme, and the layout,
  dock apps, keybindings and PaperWM gaps they changed. The manual's `setup.md` documents the format.
- `ame setup diff --json [FILE]` compares the machine with it and changes nothing: read it before
  answering what the machine lacks. `ame setup apply --yes [FILE]` installs and sets what is missing,
  once you have told the user what `diff` lists. `--remove` uninstalls and resets what the file does not
  name, and asks in a terminal: leave it to the user. Switching the image needs a terminal too.
- The file names things only. Never put a remote, a URL, a Brewfile, a command or any other GNOME key
  in it: it is refused, by design, because a shared file must not run anything.
- If the user keeps the file (often in git), offer to run `ame setup save` after you change their apps
  or settings, and show `git diff` rather than committing for them.
- On a new machine, `ame restore-setup` remakes the user's setup from the manifest their restic backup
  stores (`/usr/libexec/amethystora-setup-manifest` writes it); it is interactive, so leave it to them.
