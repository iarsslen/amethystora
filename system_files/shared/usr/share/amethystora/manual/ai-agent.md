# The AI agent

`Super+Ctrl+Shift+A` opens an AI agent in a terminal: Claude Code by default, or opencode if you
prefer. It comes with a skill that explains this system to it, so it knows which files belong to
the image and which are yours to change, how themes and hotkeys work, how software is installed on
an image-based system, and what to ask you before it touches anything.

Ask it things in plain language:

- "Make the dock icons smaller."
- "Why is my laptop fan always running?"
- "Set up a Python project with uv in ~/code/scraper."
- "Add a hotkey that opens Mission Center."

It starts in its normal mode, so it asks before it runs a command or changes a file. Read what it
proposes before you say yes.

## Diagnose a problem

**Diagnose a problem** in the Amethystora menu (`Super+Alt+Space`) hands the agent something that
went wrong: a crash, a failed service, or your own description ("Wi-Fi drops after suspend"). It
investigates from the logs and crash reports, changes nothing, and comes back with the cause and a
proposed fix.

```bash
amethystora-agent diagnose                       # look for anything that failed recently
amethystora-agent diagnose "wifi drops after suspend"
amethystora-agent diagnose NetworkManager.service
amethystora-agent diagnose 4242                  # a process ID
```

## Commands

| Command | Does |
| --- | --- |
| `amethystora-agent` | Open the agent (the same as `Super+Ctrl+Shift+A`) |
| `amethystora-agent ask "<question>"` | Open it with a first question |
| `amethystora-agent diagnose [...]` | Find out why something broke, changing nothing |
| `amethystora-agent use claude` or `use opencode` | Choose the agent |
| `amethystora-agent install` | Install the chosen agent ahead of time; also `ujust install-agent` |
| `ujust toggle-agentic` | Turn the agent features off, or on again |

## Installing and updating

The agents are not part of the image, because they release far more often than it does. The first
time you open one, it offers to install it into your home with its maker's own installer. From then
on it updates itself, when you decide: `claude update` or `opencode upgrade`. Claude Code is
installed on its stable channel, a release about a week old. Because it lives in your home, the same
copy also works inside any toolbox or distrobox.

## Privacy and turning it off

Neither agent does anything until you sign in to it, and what you send it goes to the provider you
signed in to. `ujust toggle-agentic` removes the menu entries, disables the hotkey and unlinks the
skill; an agent you installed stays installed either way.
