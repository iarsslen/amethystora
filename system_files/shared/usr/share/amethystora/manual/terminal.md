# The terminal

Amethystora is made for people who like the command line as much as for people who never open it.
When you do, it is ready for you.

## Opening one

`Super+Return` opens a terminal, and so do `Ctrl+Alt+T` and `Ctrl+Alt+Return`. The terminal is
Ptyxis. It knows about containers: the menu next to the new tab button opens a tab on the host or
inside any of your [Distrobox and Toolbox containers](software.md#containers).

Its colours follow the [theme](themes.md), and so does the prompt.

## The greeting

A new terminal says hello with the Amethystora logo, a summary of the machine, the image you are
running, a few useful commands and a tip. `ame desktop greeting off` turns it off, `on` brings it back,
and so does the switch on [Control](control.md)'s **Desktop** page.

`fetch` shows the logo and the system summary again whenever you like. A glint crosses the logo's
facets before the summary appears; you get the still logo instead over SSH, in the text console, in a
terminal without full colour, with `NO_COLOR` set, or when **Reduce Animation** is on in
**Settings → Accessibility**. Anything you add after `fetch` goes to fastfetch, which it runs.

## Shells

The shell is bash, with the Starship prompt. fish and zsh are installed too. The way to switch is in
the terminal rather than system-wide, so that a broken shell configuration can never lock you out of
logging in:

1. Open the terminal's **Preferences** and edit your profile.
2. Turn on **Use Custom Command** and enter `/usr/bin/fish` or `/usr/bin/zsh`.

## ame

`ame` runs the commands that come with the system: small, tested scripts for the jobs that would
otherwise take a web search, in groups such as `desktop`, `security` and `system`. This manual
mentions them where they help; to see all of them:

```bash
ame                           # the groups, and the commands outside them
ame security                  # the commands in one group, with a line about what each does
ame --list --list-submodules  # every command, in every group
ame -n security status        # print what a command would run, without running it
```

`ame pkg` is [amethystora-pkg](software.md#packages-from-other-distributions). `ujust`, the older
name of `ame`, runs the same commands, and their names from before they were grouped, such as
`ujust setup-backup`, still work.

The commands are `just` recipes, and `just` itself is yours for your own projects: a `justfile` in any
folder turns its commands into recipes the same way.

## Command line tools

Command line tools come from Homebrew, which installs into your home without `sudo` and without
touching the system:

```bash
brew install ripgrep
brew search <name>
brew upgrade
```

Browse what there is at [formulae.brew.sh](https://formulae.brew.sh). Homebrew is updated along with
the system. Never run it with `sudo`: it is yours, not root's.

Already on the image: `just`, `gum`, `glow`, `tmux`, `fastfetch`, `git` and the rest of the usual
tools. The fonts include Inter, JetBrains Mono and the Nerd Fonts symbols, so prompts and file
managers in the terminal draw their icons.

`ame apps cli` installs a set of newer tools from Homebrew, eza, bat, ripgrep, zoxide and more, and
sets your shell up to use them in place of the usual ones: `ls` lists with eza, `cat` shows with bat,
`grep` searches with ugrep. `ame desktop bling off` takes that out of your shell's settings, and `on`
puts it back; the **Terminal tools** switch on Control's **Desktop** page does the same.
