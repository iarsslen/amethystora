# Installing software

There is no `dnf install` here, and you will not miss it. Each kind of software has its own place,
none of them changes the system image, and so no app can ever break an update or be broken by one.

| You want | Use | How |
| --- | --- | --- |
| An app with a window | Flatpak, from Flathub | Bazaar, the software centre |
| A command line tool | Homebrew | `brew install <name>` |
| A whole Linux userland: `apt`, `dnf`, `pacman`, a toolchain | A container | `amepkg` ([Containers](#containers)) |
| A `.deb` or an `.rpm` from a website | A container made for it | Open it in Files ([A package file](#a-package-file)) |
| A website as an app | A web app | `amethystora-webapp install` ([Web apps](web-apps.md)) |
| Something that must be on the host itself | Layering | `rpm-ostree install`, as a last resort |

## Apps: Bazaar and Flathub

Open **Bazaar** and install from [Flathub](https://flathub.org), where nearly every Linux desktop app
is published. Flatpak apps update themselves along with the system, and removing one leaves nothing
behind. From a terminal:

```bash
flatpak install flathub org.gimp.GIMP
flatpak list --app
flatpak uninstall --delete-data org.gimp.GIMP
```

Two more tools are there for Flatpaks:

- **Flatseal** shows and changes what each app is allowed to reach: folders, devices, the network.
- **Warehouse** manages installed apps and cleans up what they leave behind.

### What Flatpak apps may not do

Every Flatpak is refused X11, `/dev/input` and the Flatpak service itself, whatever its own manifest
asks for. Together those are how one app could read what you type into another. Apps written for
Wayland do not notice. An app that only speaks X11 (Wine, some games, some older Electron builds)
needs it granted back, one app at a time, in Flatseal or with:

```bash
flatpak override --user --socket=x11 <app-id>
```

What each app can reach beyond its sandbox, what it asked for and what you granted it, is on the
**Apps** page of the Security app, and in a terminal with `ame security apps`
([App permissions](security.md#app-permissions)).

## Command line tools: Homebrew

```bash
brew install ripgrep fd bat
brew search <name>
```

Homebrew installs into its own prefix, without `sudo`, and is updated along with the system. The
[terminal](terminal.md#command-line-tools) page has more.

## Containers

For anything that expects a traditional distribution (a compiler toolchain, a `.deb` a vendor ships,
a package only on the Arch User Repository, an Ubuntu-only tool), make a container. It shares your
home folder and your display, so apps inside it open windows like any other, and it can be thrown away
without a trace. Nothing installed in one touches the system.

> **A container is not a sandbox.** What you install in one runs as you, with your home folder, your
> display, your sound and your session bus. When an app is on Flathub, have it from there: Flatpak
> apps are sandboxed, signed and updated with the system.

### Packages from other distributions

`amepkg`, short for `amethystora-pkg`, makes containers from templates (Debian, Ubuntu, Fedora, Arch,
Alpine, openSUSE Tumbleweed and openSUSE Leap) and installs into them with their own package managers:

```bash
amepkg containers new --template debian
amepkg debian install gimp
amepkg debian enter
```

The first line downloads the image the template names, makes the container and brings it up to
date. `install` installs from Debian's own signed repositories with `apt`, and puts every app the
package brought with it in the app grid, marked "(on debian)"; `remove` takes them out again. Before
it installs an app, `amepkg` looks for the same app on Flathub and offers that first.

| Command | Does |
| --- | --- |
| `amepkg containers list` | The containers, their templates, when each was last upgraded, their apps |
| `amepkg containers new` | A new container: it asks for the template and the name |
| `amepkg containers rm <name>` | Deletes the container and everything installed in it |
| `amepkg containers reset <name>` | Deletes it and makes it again from its template; its home folder stays |
| `amepkg <name> install`, `remove` or `purge <package>` | Installs or removes packages |
| `amepkg <name> search <words>`, `show <package>` or `list` | Looks through its repositories, or what is installed |
| `amepkg <name> update`, `upgrade`, `autoremove` or `clean` | Refreshes its package lists, upgrades it, tidies up |
| `amepkg <name> enter` or `run <command>` | A shell in it, or one command |
| `amepkg <name> start` or `stop` | Starts or stops it |
| `amepkg <name> export --app <app>` or `--bin <path>` | Puts an app in the app grid, or a command in `~/.local/bin`; `unexport` takes it back |

It lists and touches only the containers it made: Distrobox containers of your own are left alone. On
Arch, `update` only refreshes the package lists, and Arch does not support installing from lists
newer than the packages already there: `upgrade`, which refreshes them first, is the one to run.

### A package file

Double-click a `.deb` or an `.rpm` in Files, or from a terminal:

```bash
amepkg install ~/Downloads/some-app.deb
```

A `.deb` goes into a Debian container, an `.rpm` into a Fedora one and a `.pkg.tar.zst` into an Arch
one, made from its template if there is none yet. First the file is scanned for viruses, and nothing
is installed if it matches known malware. Then it says what the file says about itself: its name and
version, who made it, whether it is signed, and whether it runs scripts of its own as it installs. An
`.rpm` can carry a signature; a `.deb` normally does not, because Debian signs its repositories rather
than each file, so a `.deb` from a website carries no proof of who made it. If the same app is on
Flathub, or the package is in the container's own repositories, those are offered first: both are
signed and kept up to date, and a file from a website is neither.

A package installed from a file is upgraded with its container only if its maker's repository comes
with it, as some vendors' packages set up as they install.

### Keeping them up to date

Every container is upgraded once a day by a timer of your own account
(`amethystora-pkg-upgrade.timer`). Like the automatic updates of the system, it waits while the
machine runs on a low battery, is busy, or is short of memory. **Update now** in
[System Updates](updates.md#updating-now) upgrades them too, straight after the system, and shows how
it went under **Containers**: a container that did not upgrade never makes the system's update a
failed one. In a terminal:

```bash
amepkg upgrade-all
```

The [security report](security.md#see-where-you-stand) says so when a container has gone two weeks
without an upgrade, and the **Containers** page of the Security app lists what is installed in each.

### Templates and package managers

A template names the image a container starts from, the package manager it is handled with, and the
packages each new container starts with. A package manager is the ten commands `amepkg` runs for it,
from `install` to `clean`. Make your own:

```bash
amepkg templates new --name devbox --base quay.io/toolbx/ubuntu-toolbox:24.04 \
    --pkg-manager apt --packages "build-essential git"
amepkg templates list
amepkg managers list
```

A template can give its containers a home folder of their own (`--own-home`), which keeps their
settings apart from yours, and distrobox's `--unshare` options (`--unshare netns,ipc`), which suit
command-line tools; an app with a window usually needs what they take away. A home folder of its own
does not hide your files: they stay reachable by their full path. Yours are kept in
`~/.local/share/amethystora/pkg`, and the built-in ones cannot be changed or removed. `export` writes
one to a file, and `import` reads it back, here or on another machine. A definition is a program: a
package manager's commands run in every container made with it, and a template chooses the image they
start from, so import only what you would run yourself. `ame restore-setup` shows each one a backup
brings and asks before it imports it.
`import` also reads the YAML files Apx writes for its stacks and package managers.

The built-in templates' images are pinned to a digest that ships inside the signed system image, so
a container starts from exactly the image Amethystora was built and tested with, and the Debian,
Alpine, openSUSE Tumbleweed and openSUSE Leap images are checked against their publishers'
signatures as well: Leap's against openSUSE's own keys, which check any Leap image you pull too. The
image of a template of your own is taken as its registry hands it out: `templates list` marks it
unverified, and making a container from it asks first, unless it is pinned with `@sha256:…` or comes
from a registry whose signatures this machine checks.

### The AUR

The Arch User Repository is off. Turn it on with the first of these, or the switch on
[Control](control.md)'s **Apps** page, and make a container for it with the second:

```bash
ame apps aur on
amepkg containers new --template arch-aur
```

That adds the `arch-aur` template, whose containers get a home folder of their own, and the `paru`
package manager, which is built from the AUR in the container the first time. Anyone can upload to
the AUR and nobody reviews what is there, so before anything is built `amepkg` shows what the AUR
says of it: who maintains it, how many vote for it, when it was submitted and last updated, and
whether it is flagged out of date, with a warning for one less than 30 days old or with no votes.
paru then shows you the PKGBUILD, the script that builds it: read it. What Arch's own repositories
have comes from them first. The daily upgrade leaves what came from the AUR alone, because each new
version is a new script to read: `amepkg <name> upgrade`, in a terminal, upgrades those too.

### In scripts

The lists print JSON whose fields stay put, with `--json`:

- `amepkg containers list --json`: `name`, `container` (its name in podman), `template`, `manager`,
  `image`, `status`, `home`, `init`, `unshare`, `exported_apps`, `exported_bins`, `packages`,
  `files`, `aur_packages`, `aur_pending`, `created`, `last_upgrade` (both in Unix seconds) and
  `last_upgrade_result`
- `amepkg templates list --json`: `name`, `description`, `base`, `manager`, `packages`, `own_home`,
  `unshare`, `built_in`, `verified` and `pinned`
- `amepkg managers list --json`: `name`, `need_sudo`, `noconfirm`, the ten commands and `built_in`

`containers new`, `templates new` and `update`, and `managers new` and `update` ask on a terminal for
whatever they were not given. With `--no-prompt`, they take flags only and fail on what is missing.
Scripts, launchers and services call it `amethystora-pkg`, its full name.

### Containers by hand

Distrobox and Toolbox work as they do anywhere:

```bash
distrobox create --name ubuntu --image quay.io/toolbx/ubuntu-toolbox:24.04
distrobox enter ubuntu
```

**DistroShelf** shows every container, yours and `amepkg`'s, in a window, and the terminal opens a
tab inside any of them from the menu next to its new tab button. An app installed in one can be put
in the app grid from inside it with `distrobox-export --app <name>`.

## Layering: the last resort

`rpm-ostree install` adds a package to the image on this machine. Use it only for what cannot live
anywhere else, such as a driver or a system service:

```bash
sudo rpm-ostree install <package>
```

Restart to use it. Every layered package makes every update slower, and the package is only kept
while you update through `rpm-ostree`. Two things to know:

- **Switching images or streams:** `bootc switch` builds the new system from the image alone and
  drops layered packages without a word. On a machine with layered packages, switch with
  `sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/iarsslen/<image>:<stream>` instead.
  Automatic updates handle this for you.
- **Undoing it:** `sudo rpm-ostree uninstall <package>` removes one, and `sudo rpm-ostree reset`
  goes back to the plain image.

Adding a `dnf` repository or running `dnf install` on the host does not work: the system has no
writable package database.

## VPN

- **Tailscale** is installed, and you can run it without `sudo`: `tailscale up` joins your tailnet.
  The firewall trusts the tailnet, where your tailnet's own access rules apply.
- **WireGuard** configurations from any provider can be imported in **Settings → Network → VPN**.
