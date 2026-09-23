#!/usr/bin/env bash
#
# Turn the image's extensions back on after every image update.
#
# The image enables its extensions through the schema default of org.gnome.shell enabled-extensions
# (build_files/shared/build-gnome-extensions.sh). A default only holds until the account has a value
# of its own, and one toggle in Extension Manager, or the switch that disables all extensions, writes
# one. From then on the image's list never reaches that account again, so an extension the image
# ships or adds stays off. Once per image version this puts every extension the image enables back
# into the account's list, takes it out of disabled-extensions, and clears disable-user-extensions.
# Extensions the user added are left as they are.
#
# There is no version-script here on purpose: this has to run after every image update, not once.
# A stamp holding the image version keeps it from running more than once per update, so turning one
# off lasts until the next update.

set -euo pipefail

command -v gsettings >/dev/null || exit 0

IMAGE_VERSION="$(. /usr/lib/os-release && echo "${IMAGE_VERSION:-}")"
STAMP="${XDG_STATE_HOME:-${HOME}/.local/state}/amethystora/extensions-image"
[[ -n ${IMAGE_VERSION} && "$(cat "${STAMP}" 2>/dev/null)" == "${IMAGE_VERSION}" ]] && exit 0

# One uuid per line. The memory backend reads no dconf at all, so it returns the image's default.
uuids() { gsettings get org.gnome.shell "$1" | grep -oE "'[^']+'" | tr -d "'" || true; }
variant() { printf "'%s'\n" "$@" | paste -sd, | sed 's/^/[/; s/$/]/'; }

mapfile -t defaults < <(GSETTINGS_BACKEND=memory uuids enabled-extensions)
mapfile -t enabled < <(uuids enabled-extensions)
mapfile -t disabled < <(uuids disabled-extensions)

wanted=("${enabled[@]}")
for uuid in "${defaults[@]}"; do
    printf '%s\n' "${enabled[@]}" | grep -qxF -- "${uuid}" || wanted+=("${uuid}")
done
kept=()
for uuid in "${disabled[@]}"; do
    printf '%s\n' "${defaults[@]}" | grep -qxF -- "${uuid}" || kept+=("${uuid}")
done

((${#wanted[@]} != ${#enabled[@]})) && gsettings set org.gnome.shell enabled-extensions "$(variant "${wanted[@]}")"
((${#kept[@]} != ${#disabled[@]})) && gsettings set org.gnome.shell disabled-extensions "$( ((${#kept[@]})) && variant "${kept[@]}" || echo '[]')"
gsettings set org.gnome.shell disable-user-extensions false

mkdir -p "$(dirname "${STAMP}")"
printf '%s\n' "${IMAGE_VERSION}" >"${STAMP}"
