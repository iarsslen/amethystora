#!/usr/bin/bash
# What's new's notes (build-whats-new.py) against the subjects this repository really has, for 20-tests.sh: a subject
# that names a command, a path, an upstream name or Markdown never reaches the Manual's page or the pill's file, where
# the image's own checks (the `ame` command check, debrand.py --check) would fail every later build of the stream; a
# rebuild with no new commit keeps the notes of the builds before it; a label with something else in it is checked
# again, title by title.
#   test-whats-new.sh [build-whats-new.py]
set -euo pipefail

SCRIPT="${1:-/ctx/build_files/shared/build-whats-new.py}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/root/usr/share/amethystora/manual" "${T}/root/usr/lib"
printf 'NAME="Amethystora"\nIMAGE_VERSION="44.20261104"\n' >"${T}/root/usr/lib/os-release"

jq -n '{version: "44.20261104", from: "44.20261027",
    commits: [
        "feat(i18n): the ame desktop commands speak the account'"'"'s language",
        "feat(i18n): the ame commands, notifications and widgets menu speak the account'"'"'s language",
        "feat(build): follow ublue-os/brew'"'"'s new layout",
        "feat(build): what Universal Blue ships as well",
        "feat(security): `ame security foo` turns X on",
        "feat(security): ujust and amepkg in the report",
        "feat(apps): files in /usr/share/amethystora/x",
        "feat(desktop): **bold** and <b>markup</b> and [a link](https://example.org)",
        "feat(desktop): Focus profiles, Work, Games and Sleep",
        "feat(desktop): first start, tips, the app grid'"'"'s folders, and saved workspace sets",
        "feat(security): settings by category",
        "fix(control): the settings list resolves its messages without a process each",
        "feat(desktop): Focus profiles, Work, Games and Sleep"],
    history: [
        {version: "44.20261027", items: [{title: "Snooze a notification", area: "desktop"},
            {title: "run ame desktop dock", area: "desktop"}, {title: "Nothing here", area: "nowhere"}]},
        {version: "44.20261104", items: [{title: "A rebuild of this very version", area: "desktop"}]},
        "not a release"]}' >"${T}/commits.json"
python3 "${SCRIPT}" notes "${T}/commits.json" >"${T}/notes.json"
[[ "$(jq -c '[.releases[] | .version]' "${T}/notes.json")" == '["44.20261104","44.20261027"]' ]]
[[ "$(jq -c '[.releases[0].items[].title]' "${T}/notes.json")" == \
    '["Focus profiles, Work, Games and Sleep","First start, tips, the app grid'"'"'s folders, and saved workspace sets","Settings by category"]' ]]
[[ "$(jq -c '.releases[1].items' "${T}/notes.json")" == \
    '[{"title":"Snooze a notification","area":"desktop"},{"title":"Nothing here","area":"system"}]' ]]

# The image's files, then the image's own checks' patterns on them
python3 "${SCRIPT}" image "${T}/notes.json" "${T}/root" >/dev/null
OUT=("${T}/root/usr/share/amethystora/whats-new.json" "${T}/root/usr/share/amethystora/manual/whats-new.md")
if grep -hoE '\bame [a-z][a-z0-9-]*( [a-z][a-z0-9-]*)?' "${OUT[@]}" || grep -inE 'ublue|universal.?blue|/usr/|`|<' "${OUT[@]}"; then
    echo "What's new keeps a subject the image's checks refuse"
    exit 1
fi
[[ "$(jq -r .version "${OUT[0]}")" == 44.20261104 ]]
grep -qx "# What's new" "${OUT[1]}"
grep -qx "## Amethystora 44.20261027" "${OUT[1]}"
grep -qxF -- "- **Snooze a notification**. On the desktop." "${OUT[1]}"

# A rebuild of the same commit: no subject, the notes of the builds before it carried forward
jq -n --slurpfile n "${T}/notes.json" '{version: "44.20261104.1", commits: [], history: $n[0].releases}' >"${T}/again.json"
python3 "${SCRIPT}" notes "${T}/again.json" >"${T}/again-notes.json"
[[ "$(jq -c '[.releases[].version]' "${T}/again-notes.json")" == '["44.20261104","44.20261027"]' ]]

# No file, or one that is not JSON: no notes, a page that says so, and nothing fails
python3 "${SCRIPT}" image "${T}/missing.json" "${T}/root" >/dev/null
[[ "$(jq -c .releases "${OUT[0]}")" == "[]" ]]
echo '{"version": "44.1", "commits": "nope", "history": {"a": 1}}' >"${T}/bad.json"
[[ "$(python3 "${SCRIPT}" notes "${T}/bad.json")" == '{"version":"44.1","releases":[]}' ]]
echo "what's new: every hostile subject left out, notes carried forward"
