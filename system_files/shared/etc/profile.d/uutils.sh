#!/usr/bin/env bash
# uutils, the Rust coreutils, ahead of the system's own, for the account that installed them with Homebrew.
# Homebrew's folder belongs to the first account (brew.sh beside this says why), so they go first in its
# shells only: ahead of /usr/bin in anyone else's, root's above all, they would run that account's programs
# in place of ls or cp.
if [[ -d "/home/linuxbrew/.linuxbrew/opt/uutils-coreutils/libexec/uubin" && $- == *i* && ${EUID} -ne 0 &&
    -O /home/linuxbrew/.linuxbrew ]] ; then
  PATH="/home/linuxbrew/.linuxbrew/opt/uutils-coreutils/libexec/uubin:$PATH"
  PATH="/home/linuxbrew/.linuxbrew/opt/uutils-diffutils/libexec/uubin:$PATH"
  PATH="/home/linuxbrew/.linuxbrew/opt/uutils-findutils/libexec/uubin:$PATH"
  export PATH
  # Fix compatibility issue with atuin - use GNU stty instead of uutils stty
  # uutils stty has format compatibility issues with GNU stty's saved state
  alias stty='/usr/bin/stty'
fi
