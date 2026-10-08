#!/usr/bin/fish
#shellcheck disable=all
# Modified by Amethystora from https://github.com/ublue-os/brew (Apache-2.0)
# Homebrew in fish, in place of Homebrew's own file, which the build's renaming would otherwise put here.
# Homebrew's folder belongs to the first account (/etc/profile.d/brew.sh says why): only that account runs
# its setup and loads its completions; every other account gets its commands after the system's, and root
# nothing.
set -l brew_prefix /home/linuxbrew/.linuxbrew
if status --is-interactive; and test -d $brew_prefix; and test (id -u) -ne 0
    if test -O $brew_prefix
        $brew_prefix/bin/brew shellenv fish | source

        if test -d $brew_prefix/share/fish/completions
            set -ga fish_complete_path $brew_prefix/share/fish/completions
        end
        if test -d $brew_prefix/share/fish/vendor_completions.d
            set -ga fish_complete_path $brew_prefix/share/fish/vendor_completions.d
        end
    end

    # The system's commands first, so that Homebrew never stands in for one of them, such as dbus
    fish_add_path --move --append --path $brew_prefix/bin $brew_prefix/sbin
end
