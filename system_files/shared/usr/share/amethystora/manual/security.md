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

The app's **Apps** page lists what each Flatpak app can reach beyond its sandbox, and which of it was
granted on this machine ([App permissions](#app-permissions)).

The app's **Containers** page lists what is installed outside Flatpak: the containers `amepkg` made,
the apps in your app grid that come from them, and what was built from the AUR, each with when it
was last upgraded. The report says so when one has gone two weeks without an upgrade.
[Containers](software.md#containers).

When something needs your attention, **Ask the agent** hands it to the [AI agent](ai-agent.md), which
looks into it in a terminal and changes nothing until you agree.

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
- **The SSH server is off,** and refuses root logins when you turn it on. If you turn it on and log in
  with a password, [one-time codes](#one-time-codes-for-ssh) can ask for a code from your phone as well.
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
  `sudo rpm-ostree kargs --delete=lockdown=integrity`. The NVIDIA images do not use it, and on a
  sealed image it is part of the signed kernel and cannot be dropped.
- **A sealed image checks every file of the system as it is read.** If you installed one, its kernel
  carries the digest of the whole system, signed, and a file changed on the disk cannot be read at
  all, whoever changed it. [Sealed images](updates.md#sealed-images).
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

## App permissions

Every Flatpak app runs in a sandbox, and its permissions say how far beyond it the app can reach
without asking you. The **Apps** page of the Security app, and `ame security apps` in a terminal, list
for each app what it can reach, and say which of it was granted on this machine rather than asked for
by the app itself:

| What it can do | What that means |
| --- | --- |
| Talk to every service of your session or of the system, use the Flatpak service or your session's systemd, or put a program where it starts at your next login | It can leave its sandbox: whatever runs in it can do anything you can |
| Use X11, or read the input devices | It can see what you type into other apps. The image takes both from every app, so an app only has them if they were granted back |
| Use every device | Cameras, security keys and game controllers, without asking |
| Read and change your files, or only read them | Everything in your home folder, or every file you can open |
| Use your SSH or GPG keys, or read your keyring | Sign in, sign or decrypt as you, or read every password you saved |

What an app asks for through a portal, such as a file you choose for it, is asked each time and is
not listed. The security report says when an app can leave its sandbox, and when one was given back
X11 or the input devices. If you did not mean it to, change it in **Flatseal**, or take back
everything you granted one app with **Take back what you granted** on the Apps page, or:

```bash
ame security apps reset
```

## Sharing files without what they say about you

Photos, documents and recordings carry more than what they show: where a photo was taken and with
which phone, who wrote a document and when. **Metadata Cleaner** shows what a file says about you and
saves a copy without it. Open it from the app grid and add the files before you send or publish them.

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

### Fingerprint login

On a machine with a fingerprint reader, a finger can sign you in, unlock the screen and approve `sudo`
and administrator prompts, and your password keeps working beside it:

```bash
ame security fingerprint
```

**Add a finger** enrols one; enrol a second as a spare. **Settings › System › Users** does the same
under **Fingerprint Login**. Two things still ask for the password: the disk passphrase at boot, and
the keyring, which a sign-in by finger leaves locked until an app needs it. The readers that work are
listed at [fprint.freedesktop.org](https://fprint.freedesktop.org/supported-devices.html).

### One-time codes for SSH

If you turn the SSH server on and log in to this machine with a password, a stolen password is enough
to get in. With one-time codes on, a password login over SSH also asks for a six-digit code from an
authenticator app on your phone, such as Aegis or FreeOTP. A login with an SSH key works as before.

Set up your own codes first, then turn them on:

```bash
ame security ssh-codes setup
ame security ssh-codes on
```

`setup` shows a picture to scan with the app, then asks for the code it shows. Keep the emergency
scratch codes it prints somewhere safe and away from this machine: each one logs in once without the
phone. Each account that logs in over SSH with a password sets up its own; an account without codes
can then log in over SSH only with a key. `ame security ssh-codes off` turns them off and keeps
everyone's codes. They do not change how you log in at the machine itself.

If you have a FIDO2 security key, there is another way that needs nothing on this machine: make an SSH
key that lives on it with `ssh-keygen -t ed25519-sk` on the computer you connect from, and it asks
for a touch of the key at each login.

### Parental controls

For a child's account, make it a standard account, not an administrator, in **Settings › System ›
Users**, then open **Parental Controls** from the app grid, or from that account's page in Settings.
It decides which installed apps the account may open, whether it may install apps and up to which age
rating, and, from GNOME 50, how long a day it may use the computer and from what time in the evening it
may not. When the time is up, the screen locks, and that account cannot unlock it until its time comes
round again.

The text consoles (`Ctrl+Alt+F3`) and SSH have no lock screen, so there the account cannot log in
outside its hours, and a session there is closed when its time runs out, with anything unsaved in it.
There the daily limit counts each session afresh, and no session runs past midnight while a limit is
set.

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
`ame restore-setup <snapshot>` picks an older setup. Your files themselves come back with restic. To
keep your setup in a file of your own as well, in git, see [Your setup in a file](setup.md).

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

On a [sealed image](updates.md#sealed-images) the TPM's key is as safe as Secure Boot itself: the
programs that ask for the disk key are inside the signed kernel image, so they cannot be swapped for
others that would keep it. Updates keep it working as long as Amethystora's key does not change.

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
