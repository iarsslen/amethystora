#!/usr/bin/bash
# Amethystora Clipboard's sealed history, for 20-tests.sh: /usr/libexec/amethystora-clipboard-seal seals and
# opens, never holds the text in the clear and refuses a wrong key, label or call; the extension's store.js,
# under gjs with a stand-in for the keyring (there is no Secret Service in a build), in a home of its own
# (test-clipboard-store.js); and its new messages translated in the image's four languages.

set -euo pipefail

HELPER=/usr/libexec/amethystora-clipboard-seal
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT

key="$("${HELPER}" new-key)"
printf '%s\n%s' "${key}" "plain marker" | "${HELPER}" seal history >"${T}/sealed"
grep -q "plain marker" "${T}/sealed" && false
[[ "$({ printf '%s\n' "${key}"; cat "${T}/sealed"; } | "${HELPER}" open history)" == "plain marker" ]]
{ printf '%s\n' "$("${HELPER}" new-key)"; cat "${T}/sealed"; } | "${HELPER}" open history >/dev/null && false
{ printf '%s\n' "${key}"; cat "${T}/sealed"; } | "${HELPER}" open image >/dev/null && false
printf 'not a key\nplain' | "${HELPER}" seal history >/dev/null 2>&1 && false
"${HELPER}" seal "../history" </dev/null >/dev/null 2>&1 && false

mkdir -p "${T}/home"
HOME="${T}/home" XDG_STATE_HOME="" XDG_CACHE_HOME="" XDG_DATA_HOME="" \
    gjs -m /ctx/build_files/shared/test-clipboard-store.js "marker-$RANDOM-$RANDOM"

# Only a translated message is in a .mo file
for language in fr ar es de; do
    for message in "Unlock to see earlier items" "Not saved: there is no keyring to keep it in"; do
        grep -qF "${message}" "/usr/share/locale/${language}/LC_MESSAGES/amethystora-clipboard.mo"
    done
done
