# vim: set ft=make :

set default-list

# Turn the AI agent on or off: its menu entry, Super+Ctrl+Shift+A, and the skill that tells it about this system (ACTION: on or off; without it, it flips)
toggle ACTION="":
    #!/usr/bin/bash
    case "{{ ACTION }}" in
        on | off) amethystora-agent "{{ ACTION }}" ;;
        "")
            if amethystora-agent status >/dev/null; then
                amethystora-agent off
            else
                amethystora-agent on
            fi
            ;;
        *)
            echo "usage: ame agent toggle [on|off]"
            exit 64
            ;;
    esac

# Install the AI agent, where it keeps itself up to date: claude, opencode, codex, gemini, copilot or cursor-agent (default: the chosen one)
install AGENT="":
    @amethystora-agent install {{ AGENT }}

# Choose the AI agent that the menu, Super+Ctrl+Shift+A and Ask the agent open: claude, opencode, codex, gemini, copilot or cursor-agent
[positional-arguments]
use AGENT:
    @amethystora-agent use "$1"
