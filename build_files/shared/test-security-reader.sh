#!/usr/bin/bash
# What the security watcher reads as each account (amethystora-security-reader), for 20-tests.sh: each mode
# against a planted home, run as that account as the watcher runs it. What a mode finds has a stable id, a
# level and the entry `ame security allow` takes, and what the account wrote stays words: nothing it finds
# is run. Nothing here writes outside a temporary folder.

set -euo pipefail

READER=/usr/libexec/amethystora-security-reader
T="$(realpath "$(mktemp -d)")"
trap 'rm -rf "${T}"' EXIT
chmod 0755 "${T}"
fail() { echo "test-security-reader: $*" >&2; exit 1; }
H="${T}/home"
as_account() {
    setpriv --reuid=4600 --regid=4600 --clear-groups -- /usr/bin/env -i HOME="${H}" USER=bob PATH=/usr/bin:/usr/sbin \
        LANG=C.UTF-8 "${READER}" "$@"
}

# --- dev-hooks --------------------------------------------------------------------------------------------

mkdir -p "${H}/.local/lib/python3.14/site-packages" "${H}/.ssh" "${H}/.config/git" \
    "${H}/.vscode-oss/extensions/evil.ext-1.0.0"
printf 'import os; os.system("touch %s/ran")\n# a comment\n/some/path\n' "${T}" \
    >"${H}/.local/lib/python3.14/site-packages/x.pth"
printf '[include]\n\tpath = %s/.config/git/more\n[core]\n\tfsmonitor = touch %s/ran-git\n' "${H}" "${T}" >"${H}/.gitconfig"
printf '[core]\n\thooksPath = /tmp/hooks\n' >"${H}/.config/git/more"
printf 'Host x\n  ProxyCommand nc %%h %%p\n  User bob\nMatch exec "true"\n' >"${H}/.ssh/config"
printf 'registry=https://example.org\nnode-options=--require /tmp/x.js\n' >"${H}/.npmrc"
printf '{"publisher":"evil","name":"ext\\u001b[2J","version":"1.0.0"}' >"${H}/.vscode-oss/extensions/evil.ext-1.0.0/package.json"
chown -R 4600:4600 "${H}"

OUT="$(as_account dev-hooks)" || fail "dev-hooks failed"
[[ ! -e "${T}/ran" && ! -e "${T}/ran-git" ]] || fail "reading the hooks ran one"
jq -se 'length == 8 and (map(.id) | unique | length) == 8 and all(.[]; .text | test("[\u0000-\u001f]") | not)' <<<"${OUT}" >/dev/null ||
    fail "dev-hooks found: ${OUT}"
for want in 'runs code at every start of Python: import os' 'sets core.fsmonitor to touch' 'sets core.hookspath to /tmp/hooks' \
    'ProxyCommand nc' 'Match exec' 'node-options=--require' 'An editor extension was added: evil.ext??2J 1.0.0'; do
    grep -qF -- "${want}" <<<"${OUT}" || fail "dev-hooks did not find \"${want}\": ${OUT}"
done
jq -se '[.[] | select(.id | startswith("extension:"))] | .[1].level == "quiet" and .[1].within == .[0].id' <<<"${OUT}" >/dev/null ||
    fail "an extension's version is not within the extension"
jq -se 'all(.[]; .allow | startswith("'"${H}"'/"))' <<<"${OUT}" >/dev/null || fail "an entry to allow is not the file"
# The same home, read again, gives the same ids
[[ "$(jq -r .id <<<"${OUT}")" == "$(as_account dev-hooks | jq -r .id)" ]] || fail "the ids are not stable"

# --- app-permissions ----------------------------------------------------------------------------------------

# No Flatpak app in a build: nothing, and no error
[[ -z "$(as_account app-permissions)" ]] || fail "app-permissions found something with no app installed"

echo "test-security-reader: what each account's reader finds is only ever read"
