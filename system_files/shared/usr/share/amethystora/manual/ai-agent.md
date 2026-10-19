# The AI agent

The AI agent is off until you turn it on: in [Control](control.md)'s **AI agent** page, or with
`ame agent toggle on`. Until then nothing on this page is there: no hotkey, no menu entries, no
**Ask the agent** buttons, and no agent is told anything about this system.

Once it is on, `Super+Ctrl+Shift+A` opens an AI agent in a terminal: Claude Code by default, or Opencode, Codex,
Antigravity CLI, Copilot CLI or Cursor CLI if you prefer. It comes with a skill that explains this system
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
proposes before you say yes. Opencode's own normal mode asks for almost nothing, so started from here it
asks before a command, an edit and a web fetch, unless your own `~/.config/opencode/opencode.json` sets a
`permission`, which then wins.

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
| `amethystora-agent use <agent>` | Choose the agent: `claude`, `opencode`, `codex`, `agy`, `copilot` or `cursor-agent`; also `ame agent use` |
| `amethystora-agent install` | Install the chosen agent ahead of time; also `ame agent install` |
| `ame agent toggle on` | Turn the agent features on for your account, or `off` again |

[Control](control.md)'s **AI agent** page has the same switch and choice, and installs the chosen agent.

## Installing and updating

The agents are not part of the image, because they release far more often than it does. The first
time you open one, it offers to install it into your home with its maker's own installer. From then
on it keeps itself up to date, and you can update it yourself: `claude update`, `opencode upgrade`,
`codex update`, `agy update`, `copilot update` or `cursor-agent update`. Claude Code is installed on its stable
channel, a release about a week old. Because it lives in your home, the same copy also works inside
any toolbox or distrobox.

Antigravity CLI (`agy`) is Google's agent, in place of Gemini CLI. A Gemini CLI you already chose and
installed still opens, and `ame update` upgrades it with the rest of your Homebrew apps; to move,
choose `agy`. Antigravity's installer also adds `~/.local/bin` to your shell's `PATH` in your shell's
startup files.

## Turning it on and off

The agent features are off on a new machine and for every new account, and an update turned them
off for every account that had them on, which a notification said once. Each account turns them on
for itself: `ame agent toggle on` adds the menu entries, the hotkey and the **Ask the agent** buttons,
and links the skill; `ame agent toggle off` takes them away again. An agent you installed stays
installed either way.

No agent does anything until you sign in to it, and what you send it goes to the provider you
signed in to.

## Root commands

When you let the agent make changes, a command it needs to run as root asks you first in the agent, and
then as an administrator chose in [Control](control.md)'s **AI agent** page, for every account:

| Mode | What your password gives |
| --- | --- |
| **Once per agent session** (`session`, the default) | One password; then root commands run until the agent ends, the screen locks, or an hour passes without one |
| **For five minutes** (`minutes`) | One password, then five minutes for that agent alone |
| **Every time** (`each`) | A password for every command |
| **In a terminal** (`terminal`) | Each command opens in a terminal, where you read it and type your password for `sudo` |

`ame agent root MODE` changes it. Every root command shows a notification and is written to the journal
(`journalctl -t amethystora-agent-root`).

## The lock

An administrator can cap what any account may turn on, in Control or with `ame agent lock act|know|off`:
`act` allows both levels, `know` only the agent and its read-only tools, `off` nothing. One account can
have its own, `ame agent lock ACCOUNT know`, and `ame agent lock ACCOUNT default` puts it back. The lock
governs Amethystora's agent features; it is not a sandbox, and for a child's account Parental Controls'
app filter is the stronger tool. Both settings are in `/etc/amethystora/agent.conf`.

## History and undo

Every change the agent's tools make is recorded, with what it was before and how to undo it:
`ame agent history`, or **What the agent changed** in Control. Ask the agent to undo one by its id.
