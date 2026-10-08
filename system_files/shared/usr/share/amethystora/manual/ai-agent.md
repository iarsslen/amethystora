# The AI agent

`Super+Ctrl+Shift+A` opens an AI agent in a terminal: Claude Code by default, or Opencode, Codex,
Gemini CLI, Copilot CLI or Cursor CLI if you prefer. It comes with a skill that explains this system
to it, so it knows which files belong to the image and which are yours to change, how themes and
hotkeys work, how software is installed on an image-based system, and what to ask you before it
touches anything.

Ask it things in plain language:

- "Make the dock icons smaller."
- "Why is my laptop fan always running?"
- "Set up a Python project with uv in ~/code/scraper."
- "Add a hotkey that opens Mission Center."
- "Make a top bar widget that shows the weather." See [Widgets](widgets.md).

It starts in its normal mode, so it asks before it runs a command or changes a file. Read what it
proposes before you say yes.

A repository someone else wrote can tell an agent what to do as it opens: before you start one in a
folder you cloned, read its `.claude/`, `.mcp.json` and `.vscode/tasks.json`, if it has them. Each can
name commands the agent or your editor will run, or servers it will talk to, as you.

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

The apps hand it what went wrong where you see it go wrong: **Ask the agent why** in **Updates** when
an update did not finish, **Ask the agent** in **Security** beside anything that needs your attention,
and **Ask the agent** in **Logs** beside a crash or something a service wrote. They pass on only the
service, the process number or the report's own words, and the agent reads the rest itself. While the
agent features are off, the buttons are not there.

## Commands

| Command | Does |
| --- | --- |
| `amethystora-agent` | Open the agent (the same as `Super+Ctrl+Shift+A`) |
| `amethystora-agent ask "<question>"` | Open it with a first question |
| `amethystora-agent diagnose [...]` | Find out why something broke, changing nothing |
| `amethystora-agent use <agent>` | Choose the agent: `claude`, `opencode`, `codex`, `gemini`, `copilot` or `cursor-agent`; also `ame agent use` |
| `amethystora-agent install` | Install the chosen agent ahead of time; also `ame agent install` |
| `ame agent toggle` | Turn the agent features off, or on again (`ame agent toggle off` says which) |

[Control](control.md)'s **AI agent** page has the same switch and choice, and installs the chosen agent.

## Installing and updating

The agents are not part of the image, because they release far more often than it does. The first
time you open one, it offers to install it into your home with its maker's own installer. From then
on it keeps itself up to date, and you can update it yourself: `claude update`, `opencode upgrade`,
`codex update`, `copilot update` or `cursor-agent update`. Claude Code is installed on its stable
channel, a release about a week old. Because it lives in your home, the same copy also works inside
any toolbox or distrobox.

Google publishes no installer for Gemini CLI, so it comes from Homebrew instead, and `ame update` and
the automatic updates upgrade it with the rest of your Homebrew apps.

## Privacy and turning it off

No agent does anything until you sign in to it, and what you send it goes to the provider you
signed in to. `ame agent toggle` removes the menu entries, disables the hotkey and unlinks the
skill; an agent you installed stays installed either way.
