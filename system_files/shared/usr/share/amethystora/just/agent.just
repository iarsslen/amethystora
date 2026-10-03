# vim: set ft=make :

set default-list

# Toggle the AI agent: its menu entry, Super+Ctrl+Shift+A, and the skill that tells it about this system
toggle:
    #!/usr/bin/bash
    if amethystora-agent status >/dev/null; then
        amethystora-agent off
    else
        amethystora-agent on
    fi

# Install the AI agent into your home, where it keeps itself up to date: claude or opencode (default: the chosen one)
install AGENT="":
    @amethystora-agent install {{ AGENT }}
