#!/usr/bin/bash
# Link the Amethystora skill into the account's agent config, or remove it when the user turned the
# agentic features off (ujust toggle-agentic). Runs at every login: the link points into the image,
# so it needs no version bump to pick up a newer skill.
/usr/bin/amethystora-agent sync
