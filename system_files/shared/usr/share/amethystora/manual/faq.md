# Questions and answers

## Why can I not use `dnf install`?

Because the system is an image, and the image is the same on every machine. That is what makes
updates safe and rollbacks instant. Apps come from Flathub, tools from Homebrew, and anything else
from a container; [Installing software](software.md) shows which is which. In a Fedora container,
`dnf install` works exactly as you know it.

## Where is Firefox?

The browser is Brave, which is also what runs [web apps](web-apps.md). Firefox, Chrome and every
other browser are in Bazaar. To make one the default, open **Settings → Apps → Default Apps**.

## Is this Fedora?

Underneath, yes: Amethystora is built on Fedora's atomic desktop and GNOME, and follows Fedora's
releases. What it adds is the desktop around it, the hardening, the tools, and an image that is
tested and signed before it reaches you.

## Can I play games?

Yes. Install Steam, Heroic or Lutris from Bazaar. Many Windows games run through Proton in Steam.
Some launchers still need X11: grant it to that app in Flatseal.

## Can I run Windows software?

Often. Install **Bottles** from Bazaar, which runs Windows programs in their own prefixes. Wine
needs X11, so grant it to Bottles in Flatseal. For the rest, a Windows virtual machine in the
[developer image](developer.md) works for nearly everything.

## How do I run an AppImage?

Install **Gear Lever** from Bazaar. It puts AppImages in the app grid and keeps them updated.

## Where do my settings live?

In your home folder: `~/.config` and `~/.local` for apps and the desktop,
`~/.config/amethystora` for the theme and the rest of Amethystora's own settings, and
`~/.var/app` for each Flatpak. Back up your home folder and you have backed up everything that is
yours.

## Why six workspaces, always?

So that a number always means the same place. With workspaces that come and go, `Super+3` depends on
what you had open an hour ago; with six fixed ones, the browser on 1 and the terminal on 2 are
always exactly where your fingers expect them.

## Why can I not change files in `/usr`?

`/usr` is the image, read-only on purpose, and replaced as a whole by every update. Settings that
belong to the whole machine go in `/etc`, where your changes are kept and merged with each update.
Settings for your account go in your home folder.

## Can I trust the image?

It is built in public on GitHub from the source in
[iarsslen/amethystora](https://github.com/iarsslen/amethystora), signed with a key whose public half
ships in every image, and only accepted by your machine if that signature checks out.
