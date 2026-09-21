# Amethystora

[![Stable Images](https://github.com/iarsslen/amethystora/actions/workflows/build-image-stable.yml/badge.svg)](https://github.com/iarsslen/amethystora/actions/workflows/build-image-stable.yml)[![Latest Images](https://github.com/iarsslen/amethystora/actions/workflows/build-image-latest-main.yml/badge.svg)](https://github.com/iarsslen/amethystora/actions/workflows/build-image-latest-main.yml)

**Amethystora** is a cloud-native desktop operating system built on Fedora, using container technology and atomic updates. Its desktop is [GNOME](https://www.gnome.org).

For end users, it aims to be as reliable as a Chromebook with near-zero maintenance. For developers, it offers a cloud-native workflow with integrated container tools, declarative system management and CI/CD-built images.

Amethystora is created and maintained by **Arsslen Idadi** ([@iarsslen](https://github.com/iarsslen)).

## Mission

Amethystora aims to be a robust, cloud-native desktop that brings enterprise-grade infrastructure practices to everyday computing:

- **Reliability**: Atomic updates keep the system stable
- **Developer Experience**: Integrated cloud-native tooling and workflows, including Kubernetes and container support
- **Sustainability**: Low maintenance overhead through modern cloud-native build infrastructure

## Images

| Image | Description |
| --- | --- |
| `ghcr.io/iarsslen/amethystora` | The standard desktop |
| `ghcr.io/iarsslen/amethystora-dx` | Developer Experience: adds Docker, Incus, libvirt and developer tools |
| `ghcr.io/iarsslen/amethystora-nvidia-open` | Standard desktop with the open NVIDIA kernel modules |
| `ghcr.io/iarsslen/amethystora-dx-nvidia-open` | Developer Experience with the open NVIDIA kernel modules |

Each image is published in the `stable`, `latest` and `beta` streams.

## Getting Started

From an existing Fedora Atomic or Universal Blue system, switch to Amethystora with:

```bash
sudo bootc switch ghcr.io/iarsslen/amethystora:stable
```

Then reboot. Replace `amethystora` with any image name from the table above, and `stable` with the stream you want.

### Using the desktop

You log in on GDM to a GNOME session with the Amethystora wallpaper and a purple accent. These GNOME Shell extensions are preinstalled: Dash to Dock, Blur my Shell, AppIndicator, Caffeine, GSConnect, Logo Menu, Search Light, Tactile, Space Bar, TopHat, Just Perfection, Gradia and Bazaar integration. Turn them on or off in the Extensions app.

The top bar carries the six workspaces on the left, where Activities used to be, and CPU, memory and network meters on the right. Both follow the current theme.

#### Tiling and keyboard navigation

Windows tile on a grid instead of being dragged into place. `Super+T` draws a 4×2 grid over the focused monitor; type the letter of a zone (`Q W E R` on the top row, `A S D F` on the bottom) to send the window there, or two letters to span from one to the other. `Super+Ctrl+T` changes the grid itself.

There are six fixed workspaces on `Super+1` to `Super+6`, `Super+Shift+N` takes the window with you, and `Alt+1` to `Alt+9` reach the pinned apps in the dock. `Super+Return` opens a terminal (kitty), `Super+W` closes a window, `Super+Space` searches.

`Super+Alt+Space` opens the Amethystora menu, which reaches all of this from the keyboard. The full list is in `ujust keybindings`.

#### Themes

`Super+Ctrl+Shift+Space` picks a theme, `Super+Ctrl+D` flips between light and dark, and `Super+Ctrl+Space` cycles the wallpaper. One switch repaints GNOME's colour scheme and accent, the kitty and Ptyxis palettes, the shell prompt, btop and the wallpaper, because each theme is a single palette file everything else is rendered from. The same from a terminal:

```bash
ujust theme                      # pick one
amethystora-theme set nord       # or name it
amethystora-theme list
```

Amethystora ships Amethystora (light and dark), Tokyo Night, Catppuccin Mocha and Latte, Gruvbox, Nord, Rosé Pine Dawn, Everforest and Matte Black. To add your own, drop a directory into `~/.config/amethystora/themes/` with a `colors.toml` in it; a directory that matches a shipped theme's name is layered over it, so you can change one colour without copying the rest. `/usr/lib/amethystora/theme/lib.sh` documents the other files a theme can hold.

The icons are [candy-icons](https://github.com/EliverLara/candy-icons), the same set under every theme; the panel keeps GNOME's own monochrome icons so the meters and indicators stay legible. A theme that wants a different set names it in an `icons.theme` file.

#### Boot menu

The GRUB menu can carry the Amethystora artwork too — the same crystal field as the wallpaper, the wordmark above the entries, and the boot splash following on the same dark ground. It is off by default and turned on with:

```bash
ujust setup-grub-theme
```

It is a separate step because GRUB reads the boot filesystem and `/boot` is not part of the image: the theme ships read-only in `/usr/share/grub/themes/amethystora` and is copied onto `/boot` on the machine. Settings go in `/boot/grub2/user.cfg` inside a marked block, leaving `grub.cfg` alone — `grub2-mkconfig` cannot regenerate it on Fedora Atomic, and bootupd rewrites it anyway. Once the theme is on, image updates refresh the artwork by themselves. `ujust setup-grub-theme` turns it off again, and the machine falls back to the plain menu.

#### Security keys

A FIDO2 security key (YubiKey, Thetis, or a fingerprint model such as the YubiKey Bio or Thetis Bio) can sign you in, unlock the screen and approve `sudo` and administrator prompts in place of your password. Register one with `ujust setup-security-key`. Choose "Add a fingerprint key" for a fingerprint model so that the key checks your fingerprint and not just a touch. The key needs a PIN and an enrolled fingerprint first; set these in Brave at `brave://settings/securityKeys`, or with `ykman fido fingerprints add` on a YubiKey Bio. Register a second key as a spare. Your password keeps working, and it is used whenever no registered key is plugged in.

### Building locally

```bash
just build amethystora latest main
just build amethystora-dx latest main
```

### Security

Amethystora hardens the Fedora defaults:

- **Updates must be signed.** Only images signed with Amethystora's key are accepted, so a tampered or substituted image is refused instead of installed. The first boot after this change switches an existing installation over automatically.
- **The firewall rejects incoming connections.** Fedora Workstation leaves every port above 1024 open to the local network; Amethystora only allows printer and device discovery (mDNS), Windows file sharing, IPv6 setup and GSConnect. Tailscale is trusted, where your tailnet's access rules apply. To let something else in, for example a development server you want to open on your phone, use the Firewall app or `sudo firewall-cmd --add-port=8080/tcp` (add `--permanent` to keep it after a reboot).
- **Ten wrong passwords in a row** lock an account for ten minutes. Unlock it early from another administrator account with `sudo faillock --user <name> --reset`.
- **Too many failed logins from one address** and fail2ban has the firewall reject that address: five failures within ten minutes cost an hour, and each further ban of the same address lasts longer than the last, up to a day. It watches the SSH server, the only thing here that can be logged into over the network, and it leaves the tailnet alone. See what is blocked with `ujust blocked-addresses`, and let an address back in with `ujust blocked-addresses <address>`.
- **Kernel hardening**: memory is wiped as it is handed out, kernel addresses are hidden, programs cannot read each other's memory, and rarely used modules (old network protocols and filesystems, FireWire) cannot load. `gdb -p` on a process you did not start now needs `sudo`.
- **The SSH server stays off** and refuses root logins when you turn it on.
- **Applications cannot watch each other's keyboards.** Every Flatpak is refused X11, the whole of `/dev` and `/dev/input`, and the Flatpak service itself, whatever its own manifest asks for. X11 is the one way left on a Wayland desktop for one application to read what you type into another, and `/dev/input` is every key on the machine. Applications that speak Wayland are unaffected; X11-only ones (Wine, some Electron builds, older games) need it granted back. Flatseal is preinstalled for exactly that, one application at a time, or use `flatpak override --user --socket=x11 <application>`. The system-wide rules are in `/etc/flatpak/overrides/global`.
- **The browser refuses extensions that are not on a list.** A browser extension sees every page you open, and that is how most credential stealers arrive. Brave installs only the password managers named in `/etc/brave/policies/managed/10-amethystora.json`; to allow another, add its extension ID in a file of your own next to that one. Web pages are also cut off from WebUSB, WebSerial, WebHID (which can read a keyboard) and Web Bluetooth.
- **Key remapping is off until you ask for it.** Input Remapper runs as root and reads every input device on the machine, which is every key typed into every application. That is what remapping a key needs, and it is a keylogger in every other respect, so it ships switched off. Turn it on with `ujust setup-input-remapper` if you remap keys.
- **Block USB devices you did not plug in** with `ujust setup-usb-protection`. A USB device can claim to be a keyboard and type by itself, and a hardware keylogger can sit between a real keyboard and the machine. USBGuard allows what is connected when you set it up and blocks anything new until you allow it. It is off by default, because a machine that blocked its own keyboard on first boot would be unusable.
- **Back up somewhere ransomware cannot reach** with `ujust setup-backup`. Ransomware encrypts everything it can reach, and that includes a backup this machine can delete from. The daily restic backup only ever adds to its repository: it never runs `forget` or `prune`, so an append-only repository at the other end keeps what was backed up before the machine was taken over. The recipe explains how to set one up on rest-server, Borg, an object store with immutability, or a USB drive you unplug between backups. Thinning out old snapshots is done from somewhere else, with credentials this machine does not hold.
- **Unlock the disk with the TPM** instead of typing the passphrase at every boot, with `ujust setup-disk-unlock`. The TPM hands over the key only while Secure Boot is on and the enrolled signing keys are the ones enrolled when you set it up, so turning Secure Boot off stops the disk opening. It does not measure the initramfs, which changes with every kernel update; add a PIN if you want the disk to need something you know as well. Your passphrase keeps working, so a cleared TPM never locks you out.
- **The kernel refuses to be rewritten while it runs.** Lockdown blocks loading a module the kernel does not trust, writing `/dev/mem`, and tracing kernel memory with BPF, so a root compromise ends at the next reboot instead of moving into the kernel where nothing can find it. This needs Secure Boot on and `ujust enroll-secure-boot-key` run, because the modules built with the image (evdi, for DisplayLink docks) are signed with Amethystora's own key. On a machine where Secure Boot cannot be turned on, drop it with `sudo rpm-ostree kargs --delete=lockdown=integrity`. The NVIDIA images do not use it at all: their driver is signed the same way.
- **What would have to change to survive a reboot is watched.** Audit records writes to your autostart entries, your own systemd units, the shell startup files, the permission overrides above, and every attempt to open an input device. Read what it caught with `sudo ausearch -k persistence -i`, or `-k input-capture` for the last.
- **A virus scan runs weekly** over home and temporary directories, and **Lynis audits the settings monthly**. Neither deletes, quarantines or moves anything: a false positive that takes away a file you wanted is worse than most of what it would be removing. See what the last scan found, or run one now, with `ujust virus-scan`.
- **Check the machine over whenever you like** with `ujust security-audit`. Lynis goes through a few hundred checks and prints what it found together with what to do about each one; it reads the system and changes nothing. What it checks is set in `/etc/lynis/custom.prf`.

### Secure Boot

Secure Boot is supported. Amethystora uses the kernel modules from Universal Blue's akmods, which are signed with the Universal Blue key. After the first installation, you will be prompted to enroll the Secure Boot key in the BIOS.

Enter the password `amethystora` when prompted to enroll the key.

If this step is not completed during the initial setup, you can manually enroll the key by running the following command in the terminal:

```bash
ujust enroll-secure-boot-key
```

The public key can be found in the akmods repository [here](https://github.com/ublue-os/akmods/raw/main/certs/public_key.der).
If you'd like to enroll this key prior to installation or rebase, download the key and run the following:

```bash
sudo mokutil --timeout -1
sudo mokutil --import public_key.der
```

## Branding

The logo, wallpapers, boot splash and fastfetch logo are generated from [branding/generate.mjs](branding/generate.mjs). To change the colours or shapes, edit that script and re-run it (needs Node.js and Edge or Chrome):

```bash
node branding/generate.mjs
```

[build_files/base/06-branding.sh](build_files/base/06-branding.sh) replaces the Bluefin names and links that come from the shared `projectbluefin/common` layer.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests are welcome at [iarsslen/amethystora](https://github.com/iarsslen/amethystora).

## Acknowledgements

Amethystora is based on [Bluefin](https://github.com/ublue-os/bluefin) by the [Universal Blue](https://universal-blue.org/) project, and it keeps building on their shared infrastructure. Thanks to the Bluefin and Universal Blue contributors for the work this project stands on.

The theme switcher follows the design of [Omakub](https://omakub.org) and its fork [Omabuntu](https://omabuntu.omakasui.org/), and most of the colour palettes are ported from them (MIT). Tiling is [Tactile](https://gitlab.com/lundal/tactile) by Per Thomas Lundal (GPL-2.0-or-later). The boot menu follows the theme layout of [grub2-themes](https://github.com/vinceliuice/grub2-themes) by Vince Liuice (GPL-3.0). The icons are [candy-icons](https://github.com/EliverLara/candy-icons) by Eliver Lara (GPL-3.0).

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) and [NOTICE](NOTICE) files for details.

### Third-Party Components

Amethystora incorporates and builds upon several open source projects:
- **Bluefin / Universal Blue**: Base images, the shared desktop layer (`projectbluefin/common`), kernel modules and build tooling
- **Fedora Linux**: Base operating system
- **GNOME Desktop Environment**: Desktop interface
- **Various CNCF Projects**: Cloud-native tooling and containers

All incorporated components keep their respective licenses and attributions.
