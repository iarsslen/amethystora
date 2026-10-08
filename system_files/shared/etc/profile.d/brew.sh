#!/usr/bin/env bash
# Homebrew in an interactive bash, in place of Homebrew's own setup file.
# Modified by Amethystora from https://github.com/ublue-os/brew (Apache-2.0)
#
# /home/linuxbrew/.linuxbrew belongs to the account brew-setup.service gave it to, the first one made, so
# everything in it is that account's program. Only that account runs Homebrew's own setup, `brew shellenv`,
# which is a script it can change. Every other account gets Homebrew's commands after the system's, and
# runs nothing from the folder just by opening a shell; root gets nothing, as sudo's PATH does not
# (08-hardening.sh). The system's commands come first either way, so that Homebrew never stands in for one
# of them, such as dbus.
_brew_prefix=/home/linuxbrew/.linuxbrew
if [[ $- == *i* && -z "${HOMEBREW_PREFIX:-}" && -d "${_brew_prefix}" && ${EUID} -ne 0 ]]; then
  if [[ -O "${_brew_prefix}" ]]; then
    eval "$("${_brew_prefix}/bin/brew" shellenv | grep -Ev '\bPATH=')"
    HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-${_brew_prefix}}"
  fi
  [[ ":${PATH}:" == *":${_brew_prefix}/bin:"* ]] || export PATH="${PATH}:${_brew_prefix}/bin:${_brew_prefix}/sbin"
fi
unset _brew_prefix
