#!/bin/sh
# shellcheck shell=sh disable=SC1091,SC2039,SC2166
# Modified by Amethystora from https://github.com/ublue-os/brew (Apache-2.0)
# Homebrew's bash completions. A completion file is a script, and Homebrew's folder belongs to the first
# account (brew.sh beside this says why), so only that account sources them. Root and every other account
# source nothing from it.
# Check for interactive bash and that we haven't already been sourced.
if [ "x${BASH_VERSION-}" != x -a "x${PS1-}" != x -a "x${BREW_BASH_COMPLETION-}" = x ] &&
    [ "$(id -u)" -ne 0 ] && [ -O /home/linuxbrew/.linuxbrew ]; then

    # Check for recent enough version of bash.
    if [ "${BASH_VERSINFO[0]}" -gt 4 ] ||
        [ "${BASH_VERSINFO[0]}" -eq 4 -a "${BASH_VERSINFO[1]}" -ge 2 ]; then
        if ! test -L /home/linuxbrew/.linuxbrew/etc/bash_completion.d/brew; then
            /home/linuxbrew/.linuxbrew/bin/brew completions link > /dev/null
        fi
        if test -d /home/linuxbrew/.linuxbrew/etc/bash_completion.d; then
            for rc in /home/linuxbrew/.linuxbrew/etc/bash_completion.d/*; do
                if test -r "$rc"; then
                . "$rc"
                fi
            done
            unset rc
        fi
    fi
    BREW_BASH_COMPLETION=1
    export BREW_BASH_COMPLETION
fi
