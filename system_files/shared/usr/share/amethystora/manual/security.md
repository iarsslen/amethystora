# Security

Amethystora is hardened beyond Fedora's defaults, and says so plainly: everything below can be
checked, and most of it can be changed if it gets in your way.

## See where you stand

Open **Security** from the app grid, or run:

```bash
ame security status
```

Both show what the security settings are actually doing right now, with what to do about anything
that is off, and neither changes anything or asks for a password. In the app, what needs your
attention comes first, with the command that fixes it and a button that runs it in a terminal, and
the protections below that are off until you want them are each one button away. For a deeper look,
`ame security audit` runs Lynis through a few hundred checks and explains each finding.

The app's **Containers** page lists what is installed outside Flatpak: the containers `amepkg` made,
the apps in your app grid that come from them, and what was built from the AUR, each with when it
was last upgraded. The report says so when one has gone two weeks without an upgrade.
[Containers](software.md#containers).

## On from the start

- **Updates must be signed.** Only images signed with Amethystora's key are installed, so a tampered
  or substituted image is refused. [Updates](updates.md#signed-updates).
- **The firewall refuses incoming connections.** Allowed in are printer and device discovery,
  Windows file sharing, IPv6 setup and GSConnect; your Tailscale tailnet is trusted. To let something
  else in, such as a development server you want to reach from your phone, use the **Firewall** app
  or `sudo firewall-cmd --add-port=8080/tcp` (add `--permanent` to keep it after a restart).
- **Ten wrong passwords in a row** lock an account for ten minutes. Unlock it early from another
  administrator account with `sudo faillock --user <name> --reset`.
- **Repeated failed logins over the network** get the address blocked: five failures within ten
  minutes cost an hour, and each further ban of the same address lasts longer, up to a day. It
  watches the SSH server, the only thing here that can be logged into over the network, and leaves
  the tailnet alone. `ame security addresses` lists what is blocked, and
  `ame security addresses <address>` lets one back in.
- **The SSH server is off,** and refuses root logins when you turn it on.
- **Applications cannot watch each other's keyboards.** Flatpak apps are refused X11 and input
  devices ([Installing software](software.md#what-flatpak-apps-may-not-do)), and the key remapper,
  which reads every key, is off until you ask for it.
- **The kernel is hardened:** memory is wiped as it is handed out, kernel addresses are hidden,
  programs cannot read each other's memory, and rarely used modules (old network protocols and
  filesystems, FireWire) cannot load. `gdb -p` on a process you did not start needs `sudo`.
- **The kernel refuses to be rewritten while it runs.** Lockdown blocks loading untrusted modules,
  writing `/dev/mem` and tracing kernel memory with BPF, so a compromise of root ends at the next
  restart. It needs Secure Boot on and the key enrolled ([Hardware](hardware.md#secure-boot)). On a
  machine where Secure Boot cannot be turned on, drop it with
  `sudo rpm-ostree kargs --delete=lockdown=integrity`. The NVIDIA images do not use it.
- **What would survive a restart is watched, and you are told.** The audit log records changes to
  accounts, to who may use `sudo`, to what starts by itself (your autostart entries, your own
  systemd services, the shell startup files) and to the security settings, and every program that
  opens an input device. The security watcher reads it every 15 minutes and says what changed and
  which program changed it. [The security watcher](#the-security-watcher).
- **A virus scan runs every week** over your home and temporary folders, and **Lynis audits the
  settings every month.** By default neither deletes or moves anything: a false positive that takes
  away a file you wanted is worse than most of what it would remove. `ame security scan` shows what
  the last scan found, and `ame security scan now` runs one. [Scanning for viruses](#scanning-for-viruses)
  does the same in a window, and [Settings](#settings) makes scans quarantine or delete what they find.

## The security watcher

Every 15 minutes, or as things happen with [real-time watching](#settings) on, the watcher looks at:

- **The audit log**: accounts, `sudo` rules, what starts by itself, the security settings and kernel
  modules loaded from a login, each with the program that made the change. A program opening the
  keyboard directly is said the first time that program does it; games and key remappers do it too.
- **The journal**: an account locked after wrong passwords, three or more wrong `sudo` or
  administrator passwords, and USB devices [USB protection](#block-usb-devices-you-did-not-plug-in)
  blocked.
- **`/etc` against the image**: the image keeps its own copy of `/etc` in `/usr/etc`, so a changed
  security setting, or a file in `/etc` that replaces one of the image's in `/usr/lib`, shows as
  **Image settings** in the report.
- **What should not exist on this system**: a setuid program outside `/usr`, `/etc/ld.so.preload`,
  a plain file in `/dev`, a kernel module that did not come with the image or is not signed, and a
  network interface reading every packet. These are **Rootkit checks** in the report.
- **What accepts connections**: each program that listens on the network, which every device on
  your tailnet can reach. A new one is said once.
- **What your session finds first**: a program in `~/.local/bin`, `~/bin` or Homebrew's folder
  named like one of the system's commands, which your shell runs in place of the real one. A fake
  `sudo` or `ssh` there is an old way to catch a password, so those are said loudest; Homebrew's
  folder only counts for those. And a launcher in your app grid that no container export made. Each is
  said when it appears, and again if it changes.
- **Network protection**, while it is on: each connection it blocked, with the way to allow it
  again, and what it recognised without blocking when the rule rates it serious.
  [Network protection](#network-protection).
- **The report itself**: when a check that says something was turned off, such as the firewall,
  signed updates or the audit log, stops being fine.

Anything new is a notification, and waits in the report until you read it:

```bash
ame security events
```

`ame security events now` looks first. If you made the change, or installed something that did,
there is nothing to do.

## Scanning for viruses

**Virus scan** in the **Security** app (or `amethystora-security scan`) scans whenever you ask:

- **Your home folder**, apart from caches.
- **A file or folder**: choose it, or drop it anywhere on the window.
- **The whole machine**: every home and temporary folder, as the weekly scan does. It asks for no
  password and carries on if you close the window. What it finds is kept where only an
  administrator can read it, so seeing that does ask for your password.

A scan you start runs as you, so it checks what your account can read. By default nothing it finds is
deleted, quarantined or moved: the result lists each file, with **Show in Files**, and leaves the
decision to you. A match can be a false positive, so check where a file came from before you delete
it, then scan again. If you set scans to quarantine or delete, the app asks for your password once
the scan is done and says what happened to each file. The scans you ran are listed in
`~/.local/state/amethystora/security-scans.json`.

## Settings

```bash
ame security settings
```

- **What happens to what a virus scan finds**: `report` (the default) leaves it where it is,
  `quarantine` moves it to `/var/lib/amethystora/quarantine`, where nothing can open or run it, and
  `delete` deletes it. This applies to the weekly scan, the scans you start in the app and real-time
  scanning. Each file is checked again before anything is done to it. `ame security scan quarantine`
  lists what is in quarantine, and `ame security scan restore` puts a file back and can tell the
  scanner to leave that exact file alone from then on.
- **Real-time watching**: `off` (the default) or `on`. On, the security watcher reads each change as
  the audit log records it, and every file written in a home folder is scanned as it is closed. It
  costs some CPU while files are being written, and scanning starts once the first virus signatures
  have downloaded.
- **Network protection**: `off` (the default), `watch` or `block`.
  [Network protection](#network-protection).

All three are kept in `/etc/amethystora/security.conf`. The command applies a change at once; an edit to
the file by hand applies at the next restart.

## Worth turning on

### Security keys

A FIDO2 security key (YubiKey, Thetis, or a fingerprint model such as the YubiKey Bio) can sign you
in, unlock the screen and approve `sudo` and administrator prompts instead of your password:

```bash
ame security key
```

Choose **Add a fingerprint key** for a fingerprint model, so the key checks your fingerprint and not
only a touch. The key needs a PIN, and a fingerprint model an enrolled finger, first: set them in
Firefox at `about:webauthn`, or with `ykman fido fingerprints add` on a YubiKey Bio.
Register a second key as a spare. Your password keeps working whenever no registered key is plugged
in.

### Backups

```bash
ame backup
```

A daily restic backup to a repository that ransomware on this machine cannot delete from. The
backup only ever adds to the repository and never deletes old snapshots, so an append-only
repository at the other end keeps everything backed up before an attack. The command explains how to
set one up on rest-server, Borg, an object store with immutability, or a USB drive you unplug
between backups. `ame backup now` backs up straight away, and `ame backup snapshots`
lists what is there.

Each backup also keeps your setup beside your files: the image and stream you follow, your Flatpak
apps and where they came from, your Homebrew packages, the containers `amepkg` made with what you
installed in them, the GNOME extensions you had on and your theme. No passwords, keys or tokens go
in it. On a new machine, point `ame backup` at the same repository with the same password,
then:

```bash
ame restore-setup
```

It shows what it would do first, and does only the parts you pick: switch to the same image, through
`ame system rebase`, which takes signed images only; install the apps and Homebrew packages; make
the containers again and install what was in them; turn the extensions back on; set the theme.
`ame restore-setup <snapshot>` picks an older setup. Your files themselves come back with restic.

### Ransomware protection

```bash
ame security ransomware
```

Every hour, a read-only snapshot of every home folder on this machine, kept in `/var/home/.snapshots`.
Ransomware running as you can encrypt everything you can write, and a snapshot is not something you
can write: changing or deleting one takes an administrator. Every snapshot from the last day is kept,
and one a day for two weeks. The report says when the latest one is more than a few hours old.

To get files back, run `ame security ransomware restore` and pick the time to go back to.
**Open it in Files** shows your home folder as it was then, to copy from; **Put a folder back**
copies a whole folder back in place, replacing the files it has and leaving the ones it does not, such
as what ransomware renamed. Nobody else's files are visible in a snapshot, and yours are not visible to
them.

It needs the home folders on a btrfs subvolume of their own, which is how the installer sets up a disk
unless it was partitioned by hand. The cost is disk space: a snapshot holds on to what was changed or
deleted since, so a file you delete to make room frees its space only when the last snapshot that has
it goes, up to two weeks later. Snapshots are never deleted to make room, because ransomware that
rewrites every file would then delete the ones from before it. Turning it off offers to delete them.

Snapshots live on the same disk, and ransomware that gets administrator rights can delete them. Keep a
[backup](#backups) somewhere else as well.

### Unlock the disk with the TPM

```bash
ame security disk-unlock
```

Instead of typing the disk passphrase at every boot, the machine's TPM hands over the key, but only
while Secure Boot is on and the signing keys are the ones enrolled when you set it up. Add a PIN if
you want the disk to need something you know as well. Your passphrase keeps working, so a cleared
TPM never locks you out. This needs a disk that was encrypted when it was installed.

### Block USB devices you did not plug in

```bash
ame security usb
```

A USB device can claim to be a keyboard and type by itself, and a hardware keylogger can sit
between a real keyboard and the machine. USB protection allows what is connected when you set it up
and blocks anything new until you allow it with `ame security usb allow`. It is off by
default, because a machine that blocked its own keyboard on first boot would be unusable.

### Browser protection

```bash
ame security browser
```

An extension sees every page you open, and that is how most password stealers arrive. With browser
protection on, browsers install only the extensions on a list: the Bitwarden, 1Password, Proton Pass
and KeePassXC password managers, and the ones you add with
`ame security browser allow <id>`. Web pages are also kept from USB, serial, HID and
Bluetooth devices. It covers Firefox, Brave, Chrome, Chromium and Edge, whether installed now or
later, for every account on the machine. Other browsers are not covered.

Allow the extensions you use before you turn it on. Firefox removes the ones that are not on the
list, with their settings, the next time it starts; the other browsers turn theirs off. Firefox
shows each extension's ID in `about:support`, under Add-ons, and the others on their extensions page
with developer mode on. Themes, dictionaries and language packs in Firefox are left alone.

What you allowed is in `/etc/amethystora/browser-extensions`, one ID a line. To take one back, remove
its line and run `ame security browser on` again. It is off by default: Firefox comes
exactly as Fedora builds it, and what it may install is your decision, not the image's.

### Network protection

```bash
ame security settings network
```

Suricata inspects every connection this machine makes and receives against the Emerging Threats
Open rules, which it downloads every day:

- **`watch`** says what it recognises and blocks nothing. Start here: a week of it shows what blocking
  would get in the way of.
- **`block`** also cuts off connections to known malware and its command servers, exploits, phishing
  pages and cryptominers, and to addresses on the Spamhaus and DShield block lists. What the rules
  recognise with less certainty is only reported.

Each blocked connection is a notification. **Network** in the **Security** app lists what was
blocked and noticed, and so does `ame security connections`. If a connection was yours and wanted,
**Allow**, or `ame security connections allow <rule>`, leaves that one rule out on this machine, and
`ame security connections block <rule>` puts it back.

Whatever goes wrong with it, your connections keep working: while Suricata starts, restarts, falls
behind or stops, they pass uninspected rather than not at all. An encrypted connection is inspected
up to its handshake, the server name and certificate, because what follows cannot be read. Its log
keeps what it recognised and nothing else, never a list of the sites you visit. It inspects this
machine's own connections, not what it forwards for virtual machines or containers run as root, and
takes a few hundred megabytes of memory. It is off by default: blocking anything is a decision about
your own traffic, and yours to make.

### Key remapping

Input Remapper runs as root and reads every key typed into every application. That is what
remapping needs, and a keylogger in every other respect, so it ships switched off. If you remap keys
or mouse buttons, turn it on with `ame security input-remapper`.
