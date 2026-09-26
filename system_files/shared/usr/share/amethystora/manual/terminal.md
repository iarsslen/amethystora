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
running, a few useful commands and a tip. `ujust toggle-user-motd` turns it off, and on again.

## Shells

The shell is bash, with the Starship prompt. fish and zsh are installed too. The way to switch is in
the terminal rather than system-wide, so that a broken shell configuration can never lock you out of
logging in:

1. Open the terminal's **Preferences** and edit your profile.
2. Turn on **Use Custom Command** and enter `/usr/bin/fish` or `/usr/bin/zsh`.

## ujust

`ujust` runs the recipes that come with the system: small, tested scripts for the jobs that would
otherwise take a web search. This manual mentions them where they help; to see all of them:

```bash
ujust              # choose one from a list
ujust --list       # every recipe with a line about what it does
ujust -n <recipe>  # print what a recipe would run, without running it
```

`just` itself is yours for your own projects: a `justfile` in any folder turns its commands into
recipes the same way.

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
