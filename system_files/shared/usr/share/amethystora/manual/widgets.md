# Widgets

The top bar can show things of your own: a focus timer, the weather, unread mail, whether the VPN is
up, how many pull requests wait for your review. Each one is a *widget*, a small program whose output
the bar turns into a label, an icon and a menu. You do not have to write it yourself: the
[AI agent](ai-agent.md) does.

## Ask the agent for one

Choose **Make a widget** in the Amethystora menu (`Super+Alt+Space`) and say what it should show, or
run:

```bash
amethystora-widgets make "a pomodoro timer"
amethystora-widgets make "how many pull requests wait for my review on GitHub"
amethystora-widgets make                          # the agent asks you what you want
```

The agent writes the widget, checks it, and it appears in the bar as soon as it is saved, with no
need to log out. Ask for changes the same way: "make the weather widget show tomorrow too".

When a widget stops working, the bar shows a warning sign in its place. Click it to read what went
wrong; **Fix it with the AI agent** hands the problem to the agent.

## Commands

| Command | Does |
| --- | --- |
| `amethystora-widgets` | Lists your widgets, and which are on |
| `amethystora-widgets make ["<idea>"]` | Has the agent make one |
| `amethystora-widgets new <name> [<example>]` | Starts one from an example: `hello`, `pomodoro` or `do-not-disturb` |
| `amethystora-widgets run <name>` | Runs it once the way the bar does, and says what is wrong with it |
| `amethystora-widgets fix <name> ["<what is wrong>"]` | Has the agent find out why it fails, and fix it |
| `amethystora-widgets off <name>` and `on <name>` | Hides it from the bar, or shows it again |
| `amethystora-widgets remove <name>` | Moves it to the trash |
| `amethystora-widgets restart` | Stops and starts every widget |

`ame desktop widgets` runs the same commands.

## Making one yourself

A widget is a folder in `~/.config/amethystora/widgets`, holding a `widget.json` that names a command
and says how often to run it, and the command itself, usually a short script. The script prints a
line for the bar to show: plain text, or JSON with an icon, a colour from the theme and a menu whose
items run commands, open links or flip switches.

`amethystora-widgets new mywidget` copies the `hello` example into place to start from, and
`amethystora-widgets run mywidget` checks it after every change. The full format is the agent's own
guide to it, `/usr/share/amethystora/agents/skills/amethystora-widgets/SKILL.md`; the examples are in
`/usr/share/amethystora/widgets/examples`.

## Safety

A widget runs as you, with access to your files, like any program you start. Only keep widgets you
have read or asked the agent for, and read what the agent proposes before you say yes, as it asks
before it writes anything.

Widgets run outside GNOME Shell, so a broken or slow one shows a warning sign instead of freezing the
desktop or ending your session. They stop while the screen is locked.
