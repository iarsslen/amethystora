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

# --- agent-config -------------------------------------------------------------------------------------------

mkdir -p "${H}/.claude" "${H}/.codex" "${H}/.gemini/extensions/x" "${H}/.config/opencode/plugin" "${H}/.cursor" \
    "${H}/.copilot/hooks" "${H}/.gemini/antigravity-cli/plugins/pl" "${H}/.gemini/config"
cat >"${H}/.claude/settings.json" <<EOF
{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "touch ${T}/ran-hook"}]}]},
 "apiKeyHelper": "sh -c 'cat key'", "permissions": {"defaultMode": "bypassPermissions"}}
EOF
echo '{"mcpServers": {"evil": {"command": "npx", "args": ["-y", "evil-mcp"]}}, "projects": {"/p": {"allowedTools": ["Bash"]}}}' \
    >"${H}/.claude.json"
printf 'notify = ["notify-send", "done"]\napproval_policy = "never"\n[mcp_servers.far]\nurl = "https://example.org/mcp"\n' \
    >"${H}/.codex/config.toml"
echo '{"mcpServers": {"g": {"command": "node", "args": ["g.js"], "trust": true}}, "tools": {"discoveryCommand": "find-tools"}}' \
    >"${H}/.gemini/settings.json"
echo '{"name": "ext"}' >"${H}/.gemini/extensions/x/gemini-extension.json"
echo '{"toolPermission": "always-proceed", "statusLine": {"type": "command", "command": "agy-status"}}' \
    >"${H}/.gemini/antigravity-cli/settings.json"
echo '{"guard": {"enabled": true, "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "from-agy"}]}]}}' \
    >"${H}/.gemini/config/hooks.json"
echo '{"mcpServers": {"remote": {"serverUrl": "https://example.net/mcp"}}}' >"${H}/.gemini/antigravity-cli/plugins/pl/mcp_config.json"
printf '// comment\n{\n  "mcp": {"local": {"type": "local", "command": ["bun", "x.ts"]},},\n  "plugin": ["opencode-evil"],\n  "permission": "allow",\n}\n' \
    >"${H}/.config/opencode/opencode.jsonc"
echo 'export default {}' >"${H}/.config/opencode/plugin/p.ts"
echo '{"approvalMode": "unrestricted", "permissions": {"allow": ["Mcp(amethystora:search)", "Mcp(amethystora:run)"]}}' \
    >"${H}/.cursor/cli-config.json"
# The entry amethystora-agent writes for the agent's tools is the image's own; the same name with anything more
# in it is somebody else's
echo '{"mcpServers": {"amethystora": {"command": "/usr/libexec/amethystora-agent-tools", "args": ["mcp"]}}}' >"${H}/.cursor/mcp.json"
echo '{"mcpServers": {"amethystora": {"command": "/usr/libexec/amethystora-agent-tools", "args": ["mcp"], "env": {"X": "1"}}}}' \
    >"${H}/.gemini/config/mcp_config.json"
echo '{"version": 1, "hooks": {"preToolUse": [{"type": "command", "bash": "echo from copilot"}]}}' >"${H}/.copilot/hooks/h.json"
chown -R 4600:4600 "${H}"

OUT="$(as_account agent-config)" || fail "agent-config failed"
[[ ! -e "${T}/ran-hook" ]] || fail "reading a hook ran it"
for want in 'runs a command on PreToolUse: touch' 'runs a command as apiKeyHelper' "turns Claude Code's checks off" \
    'starts the MCP server evil: npx -y evil-mcp' 'runs a command when a turn ends: notify-send done' 'has Codex never ask' \
    'sends to the MCP server far: https://example.org/mcp' 'lets the MCP server g run tools without asking' \
    'runs a command as tools.discoveryCommand' 'is an extension Gemini CLI loads: ext' 'starts the MCP server local: bun x.ts' \
    'loads the plugin: opencode-evil' 'has Opencode never ask' 'is code Opencode loads' 'has Cursor run everything without asking' \
    'runs a command on preToolUse: echo from copilot' 'has Antigravity CLI never ask' 'runs a command as statusLine: agy-status' \
    'runs a command on PreToolUse: from-agy' 'sends to the MCP server remote: https://example.net/mcp' \
    'is a plugin Antigravity CLI loads: pl' \
    'mcp_config.json starts the MCP server amethystora: /usr/libexec/amethystora-agent-tools mcp' \
    'lets the MCP server amethystora run a tool without asking: Mcp(amethystora:run)'; do
    grep -qF -- "${want}" <<<"${OUT}" || fail "agent-config did not find \"${want}\": ${OUT}"
done
for unwanted in '.cursor/mcp.json starts the MCP server amethystora' 'Mcp(amethystora:search)'; do
    if grep -qF -- "${unwanted}" <<<"${OUT}"; then fail "agent-config said the image's own entry: ${unwanted}"; fi
done
jq -se '(map(.id) | unique | length) == length
    and any(.[]; (.text | test("lets Claude Code use tools without asking in /p")) and .level == "quiet")
    and all(.[]; .allow | startswith("'"${H}"'/"))' <<<"${OUT}" >/dev/null || fail "agent-config's ids, levels or entries: ${OUT}"
[[ "$(jq -r .id <<<"${OUT}")" == "$(as_account agent-config | jq -r .id)" ]] || fail "agent-config's ids are not stable"

# --- app-permissions ----------------------------------------------------------------------------------------

# No Flatpak app in a build: nothing, and no error
[[ -z "$(as_account app-permissions)" ]] || fail "app-permissions found something with no app installed"

echo "test-security-reader: what each account's reader finds is only ever read"
