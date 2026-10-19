#!/usr/bin/bash
# Link the Amethystora skills into the account's agent config while the agentic features are on
# (ame agent toggle on), and remove them while they are off, as the image ships them. Runs at every
# login: the links point into the image, so they need no version bump to pick up a newer or a new skill.
/usr/bin/amethystora-agent sync
