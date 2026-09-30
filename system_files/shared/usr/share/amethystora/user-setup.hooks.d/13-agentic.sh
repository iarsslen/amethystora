#!/usr/bin/bash
# Link the Amethystora skills into the account's agent config, or remove them when the user turned
# the agentic features off (ujust toggle-agentic). Runs at every login: the links point into the
# image, so they need no version bump to pick up a newer or a new skill.
/usr/bin/amethystora-agent sync
