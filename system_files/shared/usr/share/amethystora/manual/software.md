# Installing software

There is no `dnf install` here, and you will not miss it. Each kind of software has its own place,
none of them changes the system image, and so no app can ever break an update or be broken by one.

| You want | Use | How |
| --- | --- | --- |
| An app with a window | Flatpak, from Flathub | Bazaar, the software centre |
| A command line tool | Homebrew | `brew install <name>` |
| A whole Linux userland: `apt`, `dnf`, `pacman`, a toolchain | A container | Distrobox or Toolbox |
| A website as an app | A web app | `amethystora-webapp install` ([Web apps](web-apps.md)) |
| Something that must be on the host itself | Layering | `rpm-ostree install`, as a last resort |

## Apps: Bazaar and Flathub

Open **Bazaar** and install from [Flathub](https://flathub.org), where nearly every Linux desktop app
is published. Flatpak apps update themselves along with the system, and removing one leaves nothing
behind. From a terminal:

```bash
flatpak install flathub org.mozilla.firefox
flatpak list --app
flatpak uninstall --delete-data org.mozilla.firefox
```

Two more tools are there for Flatpaks:

- **Flatseal** shows and changes what each app is allowed to reach: folders, devices, the network.
- **Warehouse** manages installed apps and cleans up what they leave behind.

### What Flatpak apps may not do

Every Flatpak is refused X11, the whole of `/dev`, `/dev/input` and the Flatpak service itself,
whatever its own manifest asks for. Together those are how one app could read what you type into
another. Apps written for Wayland do not notice. An app that only speaks X11 (Wine, some games, some
older Electron builds) needs it granted back, one app at a time, in Flatseal or with:

```bash
flatpak override --user --socket=x11 <app-id>
```

## Command line tools: Homebrew

```bash
brew install ripgrep fd bat
brew search <name>
```

Homebrew installs into its own prefix, without `sudo`, and is updated along with the system. The
[terminal](terminal.md#command-line-tools) page has more.

## Containers

For anything that expects a traditional distribution (a compiler toolchain, a package only on the
Arch User Repository, an Ubuntu-only tool), make a container. It shares your home folder and your
display, so apps inside it open windows like any other, and it can be thrown away without a trace.

```bash
distrobox create --name ubuntu --image ubuntu:24.04
distrobox enter ubuntu
sudo apt install build-essential
```

`toolbox create` does the same with a Fedora container. **DistroShelf** manages containers from a
window, and the terminal opens a tab inside any of them from the menu next to its new tab button.

An app installed in a container can be put into the app grid from inside it with
`distrobox-export --app <name>`.

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

- **NordVPN** is installed. Open NordVPN from the app grid, or run `nordvpn login` and then
  `nordvpn connect` in a terminal. Administrator accounts can use it; an account made since the
  machine last started gets access at the next start. To let a standard account use it, run
  `sudo usermod -aG nordvpn <name>` and have that person log out and back in.
- **Tailscale** is installed, and you can run it without `sudo`: `tailscale up` joins your tailnet.
  The firewall trusts the tailnet, where your tailnet's own access rules apply.
- **WireGuard** configurations from any provider can be imported in **Settings → Network → VPN**.
