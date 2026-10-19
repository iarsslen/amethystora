# vim: set ft=make :

set default-list

# Turn the AI agent on or off for your account, off until you turn it on: its menu entry, Super+Ctrl+Shift+A, and the skill that tells it about this system (ACTION: on or off; without it, it flips)
[positional-arguments]
toggle ACTION="":
    #!/usr/bin/bash
    case "${1:-}" in
        on | off) amethystora-agent "${1:-}" ;;
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

# Let the AI agent's tools make changes: settings, apps, and commands it hands you, each asked for every time (ACTION: on or off; without it, it flips). Needs the agentic features on
[positional-arguments]
tools ACTION="":
    #!/usr/bin/bash
    case "${1:-}" in
        on | off) amethystora-agent tools "$1" ;;
        "")
            if amethystora-agent tools status >/dev/null; then
                amethystora-agent tools off
            else
                amethystora-agent tools on
            fi
            ;;
        *)
            echo "usage: ame agent tools [on|off]"
            exit 64
            ;;
    esac

# Install the AI agent, where it keeps itself up to date: claude, opencode, codex, agy, copilot or cursor-agent (default: the chosen one)
[positional-arguments]
install AGENT="":
    @amethystora-agent install ${1:+"$1"}

# Choose the AI agent that the menu, Super+Ctrl+Shift+A and Ask the agent open: claude, opencode, codex, agy, copilot or cursor-agent
[positional-arguments]
use AGENT:
    @amethystora-agent use "$1"

# Lock the AI agent, for every account or for one (an administrator's): act lets it know and change things, know only know, off nothing, default puts one account back to everyone's. Without a level, says what it is
[positional-arguments]
lock *ARGS:
    #!/usr/bin/bash
    set -euo pipefail
    usage() { echo "usage: ame agent lock [ACCOUNT] act|know|off, or ame agent lock ACCOUNT default"; exit 64; }
    case "$#" in
        0) exec /usr/libexec/amethystora-agent-tools policy ;;
        1) [[ "$1" =~ ^(act|know|off)$ ]] || usage; set -- allow "$1" ;;
        2) [[ "$2" =~ ^(act|know|off|default)$ ]] || usage; set -- allow "$2" "$1" ;;
        *) usage ;;
    esac
    echo "This is an administrator's setting, and asks for an administrator's password."
    sudo /usr/libexec/amethystora-agent-tools conf "$@"

# How the AI agent's root commands are allowed, for every account (an administrator's): session (one password, then until the agent ends, the screen locks or an hour passes), minutes (five minutes), each (every time) or terminal (sudo in a terminal). Without one, says which it is
[positional-arguments]
root MODE="":
    #!/usr/bin/bash
    set -euo pipefail
    case "${1:-}" in
        "") exec /usr/libexec/amethystora-agent-tools policy ;;
        session | minutes | each | terminal) ;;
        *) echo "usage: ame agent root session|minutes|each|terminal"; exit 64 ;;
    esac
    echo "This is an administrator's setting, and asks for an administrator's password."
    sudo /usr/libexec/amethystora-agent-tools conf root "$1"

# What the AI agent's tools changed, newest first, each with its id (ID: one change's result)
[positional-arguments]
history ID="":
    @amethystora-agent history ${1:+"$1"}
