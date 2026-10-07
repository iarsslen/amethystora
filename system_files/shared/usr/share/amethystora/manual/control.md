# Control

Most of what you can change about Amethystora is a command in the terminal, and a command nobody tells
you about is one you never use. **Control** puts those settings in one window: `Super+Ctrl+Shift+C`,
**Control** in the app grid, or **Control** in the Amethystora menu.

Each setting says what it is now and what it changes, and the page of this manual it is on. A change
runs the same `ame` command you could type yourself, which the card shows under it, so nothing in
Control is out of reach of a terminal, and `ame control` lists every setting there. A change that asks
something, explains a risk first or needs your password opens in a terminal, marked **Terminal** on its
card, and Control reads everything again when you come back to it.

## What is where

| Page | Settings |
| --- | --- |
| **Appearance** | The [theme](themes.md#switching) and its [wallpapers](themes.md#wallpapers), the [transition](themes.md#transitions) that reveals a new one and how long it takes, and the [boot menu](themes.md#the-boot-menu)'s artwork |
| **Desktop** | The [window layout](desktop.md#tiling-windows), the [widgets](widgets.md) in the top bar, the terminal's [greeting](terminal.md#the-greeting) and its [tools](terminal.md#command-line-tools) |
| **Apps** | [Games](games.md#games), [Android apps](games.md#android-apps), [drawing tablets](hardware.md#drawing-tablets), [the AUR](software.md#the-aur), [web apps](web-apps.md), and add-ons that install with one command: JetBrains Toolbox, the command-line tools, Homebrew's collections, the CNCF's tools and the apps the image comes with |
| **AI agent** | Whether the [AI agent](ai-agent.md) is on, which one, and installing it |
| **System** | The [image and the stream](updates.md#switching-streams-and-images) this machine follows, [developer mode](developer.md#turning-it-on), [an image of your own](developer.md#an-image-of-your-own), the [CPU scheduler](games.md#a-faster-cpu-scheduler-for-games), the firmware's settings, [freeing disk space](troubleshooting.md#the-disk-is-filling-up), the [pools of disks](hardware.md#pools-of-disks-raid) in a **Disks** group, where a pool says how it is doing and offers what it needs, and [starting over](troubleshooting.md#starting-over) |
| **Your setup** | Your [setup file](setup.md): saving it, what this machine and the file disagree on, and applying it |

The search box finds a setting on any page by what it is called or what it does.

## What is not here

- **Security settings** are in Amethystora Security, whose report says what each protection does and
  turns it on ([Security](security.md#see-where-you-stand)). Control's sidebar opens it.
- **Automatic updates** are switched in Updates, which shows when the next one comes
  ([Updates](updates.md)). Control's sidebar says whether they are on, and opens it.
- **Backups**, setting one up, backing up now and the daily run, are in Backups, which also puts files
  back ([Backups](security.md#backups)). Control's sidebar opens it.
- **GNOME's own settings**, such as displays, sound, networks and accounts, are in GNOME's Settings.

## In a terminal

```bash
ame control           # every setting, what it is now, and the command that changes it
```

The commands it names take their choice as an argument, so a script can use them too:

```bash
ame desktop layout classic
ame desktop greeting off
ame agent use opencode
ame apps aur off
```
