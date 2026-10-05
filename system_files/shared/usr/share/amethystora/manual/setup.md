# Your setup in a file

Your apps, your Homebrew packages, your containers, the extensions you have on, your theme and a few
settings, written down in one file that is yours. Apply it to a new machine and it installs what is
missing; apply it here after trying things out and it puts back what you had. Keep it in git and you
have the history of your setup as well.

```bash
ame setup save      # write this machine's setup to ~/.config/amethystora/setup.json
ame setup diff      # what this machine and the file disagree on
ame setup apply     # add what the file names and this machine lacks
```

[Backups](security.md#backups) keep the same setup beside your files, and `ame restore-setup` makes it
again from there. `ame setup` is for a file you keep, read and edit yourself. [Control](control.md)'s
**Your setup** page shows what `ame setup diff` says, saves the file, and applies it in a terminal.

## Saving it

```bash
ame setup save
```

writes the file. `ame setup save ~/setup.json` writes it somewhere else, and `ame setup save -` prints
it. Run it again whenever your setup changes: it writes the whole file anew, with every list sorted, so
that git shows only what changed. It holds:

| Key | What |
| --- | --- |
| `image` | The image and stream this machine follows |
| `flatpaks` | Your Flatpak apps, those of the machine (`system`) and your own (`user`), each with the remote it came from |
| `brew` | Your Homebrew taps, formulae and casks |
| `containers` | The containers `amepkg` made, with their templates and the packages you installed in them |
| `extensions` | The GNOME extensions you have on |
| `theme` | Your [theme](themes.md) |
| `settings` | The window layout, the dock's apps, the keybindings you changed and PaperWM's gaps |

A setting goes in only where you changed it from what the image has, so that what a later image
changes still reaches you.

### What it never holds

The file names things, and nothing else: anything that is an address to download from or a command to
run stays out of it, because a file can be shared, and one somebody shares with you must not be able to
run anything on your machine. So it holds no Flatpak remotes (apps come from the remotes this machine
has, Flathub on every one), no Brewfile (Homebrew runs one as a program), no templates or package
managers of your own (each is an image's address and commands), none of your own custom keybindings
(each is a command) and no other GNOME setting. No passwords, keys or tokens either: a file with a key
the format does not know is refused, by `save` as well.

A template of your own goes to the other machine as a file of its own, with `amepkg templates export`
and `import` ([Templates and package managers](software.md#templates-and-package-managers)).

## Comparing

```bash
ame setup diff
```

changes nothing, and lists:

- `+` what the file names and this machine does not have,
- `~` what is set differently here,
- `-` what this machine has and the file does not name,
- `!` what the file names that this machine cannot have, and why: an app from a remote it does not
  have, a container from a template that is not here or from the AUR while [the AUR](software.md#the-aur)
  is off, an extension or a theme that is not installed.

`ame setup diff ~/setup.json` compares another file, and `--json` prints the same for scripts.

## Applying

```bash
ame setup apply
```

shows what it would add and set, and asks before it does any of it. It installs the apps, the Homebrew
packages and the containers, turns the extensions on, and sets the theme and the settings. Run it twice
and the second run finds nothing to do.

- **It takes nothing away**, unless you add `--remove`: then it also lists what this machine has and
  the file does not name, and asks again before it uninstalls, turns off, or puts a setting back as the
  image has it. Apps keep their data, and a container's home folder stays.
- **The system** is switched through `ame system rebase`, which takes signed images only and asks its
  own questions. The new system takes over at the next restart.
- **`--yes`** skips the first question, for a script. It skips neither `--remove`'s question nor the
  system switch, which both need a terminal.

## Editing it

The file is JSON, and a list it leaves out counts as empty: a file that names only your apps makes
`ame setup diff` list everything else as not in the file. A setting it leaves out is left as the
machine has it.

```json
{
  "version": 1,
  "flatpaks": {
    "system": [{"app": "org.gimp.GIMP", "origin": "flathub"}],
    "user": []
  },
  "settings": {
    "layout": "classic",
    "keybindings": {
      "org.gnome.desktop.wm.keybindings": {"close": ["<Super>q"]},
      "custom": {"custom20": ["<Super>t"]}
    },
    "paperwm": {"window-gap": 12}
  }
}
```

A keybinding is the keys of a GNOME keybinding by its schema and name, as `gsettings get
org.gnome.desktop.wm.keybindings close` shows it. `custom` holds the image's own
[keybindings](../keybindings.md) by their id (`custom20` opens the terminal), and only their keys:
`dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/` lists them. `layout` is
`tiling` or `classic` ([Classic windows](desktop.md#classic-windows)), and `paperwm` holds
`window-gap`, `horizontal-margin`, `vertical-margin` and `vertical-margin-bottom`, in pixels.

Everything in the file is checked before anything runs, and `ame setup diff` says what is wrong with
one it refuses.

## Keeping it in git

The folder the file is in also holds the password of your [backups](security.md#backups), so keep only
the file in git:

```bash
cd ~/.config/amethystora
git init
printf '*\n!.gitignore\n!setup.json\n' >.gitignore
git add .gitignore setup.json
git commit -m "My setup"
```

Then push it to a private repository on GitHub, GitLab or Codeberg. After `ame setup save`, `git diff`
shows what changed since. On another machine, clone the repository anywhere and apply its file:

```bash
git clone <your repository> ~/setup
ame setup apply ~/setup/setup.json
```
