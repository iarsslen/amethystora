#!/usr/bin/env bash
#
# The agentic features were on for every account unless it turned them off (~/.config/amethystora/no-agentic),
# and are now off until an account turns them on (~/.config/amethystora/agentic), so every account is off after
# this update by construction. The old marker goes. An account that had them on is told once, a minute into
# the login, how to turn them on again: it had the skills linked at its last login, which 13-agentic.sh, run
# right after this, unlinks.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script agentic-off user 1 || exit 0

CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}/amethystora"
SKILL=/usr/share/amethystora/agents/skills/amethystora

if [[ -e "${CONFIG}/no-agentic" ]]; then
    rm -f "${CONFIG}/no-agentic"
    exit 0
fi
# Turned on already, by whoever got there first: nothing to say
[[ -e "${CONFIG}/agentic" ]] && exit 0

for dir in "${HOME}/.claude/skills" "${HOME}/.agents/skills" "${HOME}/.gemini/antigravity-cli/skills"; do
    if [[ "$(readlink "${dir}/amethystora" 2>/dev/null)" == "${SKILL}" ]]; then
        systemd-run --user --collect --quiet --on-active=60 -- /usr/libexec/amethystora-agentic-off-notice
        exit 0
    fi
done
exit 0
