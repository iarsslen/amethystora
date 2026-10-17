# shellcheck shell=sh
command -v starship >/dev/null 2>&1 || return 0

if [ -n "${BASH_VERSION:-}" ]; then
  # What `starship init bash` prints, written by the build for this starship (05-override-install.sh)
  if [ -r /usr/share/amethystora/starship/init.bash ]; then
    . /usr/share/amethystora/starship/init.bash
  else
    eval "$(starship init bash)"
  fi
fi
