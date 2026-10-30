#!/usr/bin/bash
# Puts the checkout's GNOME Shell extensions and theme templates on this machine for this boot, for a live test: sudo tests/real/load-shell.sh
# Only files that differ, nothing deleted. /usr's overlay goes at the next restart, and with it all of this.
# They load at the next login.
set -euo pipefail
cd "$(dirname "$(realpath "$0")")/../.."
E=usr/share/gnome-shell/extensions
S="system_files/shared/${E}"

[[ "$(id -u)" == 0 ]] || { echo "run it with sudo" >&2; exit 1; }
[[ -e /usr/share/amethystora/sealed ]] && { echo "a sealed image cannot be changed live" >&2; exit 1; }
[[ "$(findmnt -no FSTYPE /usr || true)" == overlay ]] || bootc usr-overlay

changed=0
while IFS= read -r -d '' file; do
    rel="${file#"${S}"/}"
    cmp -s "${file}" "/${E}/${rel}" && continue
    install -D -m 0644 "${file}" "/${E}/${rel}"
    echo "  ${rel}"
    changed=$((changed + 1))
done < <(find "${S}" -type f ! -name gschemas.compiled -print0)

# The theme's templates: they reach the account when its theme is next applied
T=usr/share/amethystora/themed
while IFS= read -r -d '' file; do
    rel="${file#system_files/shared/"${T}"/}"
    cmp -s "${file}" "/${T}/${rel}" && continue
    install -D -m 0644 "${file}" "/${T}/${rel}"
    echo "  themed/${rel}"
    changed=$((changed + 1))
done < <(find "system_files/shared/${T}" -type f -print0)

for schemas in "/${E}"/*/schemas; do
    glib-compile-schemas "${schemas}"
done
restorecon -RF "/${E}" "/${T}"
echo "${changed} files. Log out and back in to load them."
