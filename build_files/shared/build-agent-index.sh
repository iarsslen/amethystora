#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The AI agent's local index (plans/done/PLAN-agentic-os.md): the manual, the skills and the knowledge written for
# agents, cut into passages, and a reference generated from this image itself (every `ame` command, helper and
# unit, the security switches and Control's entries), each passage with its vector from the model 13-apps.sh
# installed. It runs once every name is final (after 07-debrand.sh) and every unit is enabled or not (after
# 17-cleanup.sh), and after the dx image's own files are in. 20-tests.sh asks it the golden questions.
/usr/libexec/amethystora-agent-tools index --write /usr/share/amethystora/agents/knowledge

echo "::endgroup::"
