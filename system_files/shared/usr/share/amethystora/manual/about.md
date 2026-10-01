# About

Amethystora is created and maintained by Arsslen Idadi ([@iarsslen](https://github.com/iarsslen)).
It is free software under the Apache License 2.0, built in the open at
[github.com/iarsslen/amethystora](https://github.com/iarsslen/amethystora). Issues, ideas and pull
requests are welcome there.

Amethystora is based on [Bluefin](https://github.com/ublue-os/bluefin), a project of [Universal Blue](https://universal-blue.org), copyright the Bluefin and Universal Blue contributors and licensed under the Apache License 2.0.

## This manual

The pages are Markdown files in `/usr/share/amethystora/manual`, one per page, and the hotkeys page
is `/usr/share/amethystora/keybindings.md`, the same file `ujust keybindings` shows. They come with
the image, so the manual always describes the system you are running, and it works without a network
connection.

```bash
amethystora-manual                 # open it where you left off
amethystora-manual updates         # open a page by its file name
amethystora-manual --list          # the pages there are
```

Inside the manual: `Ctrl+K` or `/` searches, `Alt+Left` and `Alt+Right` go back and forward,
`Ctrl+=` and `Ctrl+-` change the text size, and `Ctrl+0` resets it.

## Standing on the shoulders of

Amethystora is built on [Fedora](https://fedoraproject.org) and [GNOME](https://www.gnome.org), and
on the work of many other projects: the Linux kernel and systemd, bootc and rpm-ostree, Flatpak and
Flathub, Homebrew, Distrobox and Podman, and every GNOME extension listed in
[Getting around](desktop.md#extensions). The icons are
[candy-icons](https://github.com/EliverLara/candy-icons) by Eliver Lara, and the Amethystora GTK
theme is recoloured from his Sweet. The themes' wallpapers are drawn for Amethystora.

Parts of this manual are adapted from the Bluefin documentation, copyright the Bluefin contributors and licensed under the Apache License 2.0.

The licences of everything in the image are in `/usr/share/licenses`. A few parts are not free
software and come under their makers' own terms: device firmware, the DisplayLink driver for docks,
and the NVIDIA driver on the NVIDIA images. `/usr/share/licenses/amethystora/NOTICE` lists them.

## Source code

Every package in the image is listed in `/usr/share/licenses/amethystora/SOURCES`, with its licence,
the source package it was built from and where that source is published. The source of a Fedora
package is in Fedora's build system at the address given there, or one command away:

```bash
dnf download --srpm <package>    # the source of the version Fedora has now
```

Everything else is built from [the Amethystora repository](https://github.com/iarsslen/amethystora)
at the commit named as `BUILD_ID` in `/usr/lib/os-release`. For at least three years after an image
was last published, the complete source of anything in it whose licence asks for its source to be
available (the GNU GPL and LGPL, the MPL, the CDDL, the Fraunhofer AAC codec's licence) is also
given to anyone who asks through the [issue tracker](https://github.com/iarsslen/amethystora/issues);
the written offer is in `/usr/share/licenses/amethystora/NOTICE`.
