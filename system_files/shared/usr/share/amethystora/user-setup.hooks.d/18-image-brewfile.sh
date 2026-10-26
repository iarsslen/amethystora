#!/usr/bin/env bash
#
# Install, for each account, what Homebrew's part of an image of one's own names: the Brewfile
# `amethystora-setup bake` wrote from the image's setup.json, of names only. Once per version of that file, and
# only what is missing (--no-upgrade): Homebrew updates what it installed on its own schedule.
#
# Homebrew is set up at the first boot, which may still be under way at the first login: then nothing is
# recorded and the next login tries again. The install runs outside the setup service, which kills what it
# leaves behind, and writes its stamp only once it has finished.

set -euo pipefail

BREWFILE=/usr/share/amethystora/image-setup/Brewfile
BREW=/home/linuxbrew/.linuxbrew/bin/brew
STAMP="${XDG_STATE_HOME:-${HOME}/.local/state}/amethystora/image-brewfile"

[[ -s "${BREWFILE}" && -x "${BREW}" ]] || exit 0
SUM="$(sha256sum "${BREWFILE}" | cut -d' ' -f1)"
[[ "$(cat "${STAMP}" 2>/dev/null)" == "${SUM}" ]] && exit 0
command -v systemd-run >/dev/null || exit 0

mkdir -p "$(dirname "${STAMP}")"
systemd-run --user --quiet --collect --unit=amethystora-image-brewfile --description="The image's Homebrew apps" \
    -- /usr/bin/bash -c '"$1" bundle install --no-upgrade --file="$2" && printf "%s\n" "$3" >"$4"' \
    bash "${BREW}" "${BREWFILE}" "${SUM}" "${STAMP}" || true
