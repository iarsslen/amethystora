# Security

Amethystora is hardened beyond Fedora's defaults, and says so plainly: everything below can be
checked, and every part of it can be turned off if it gets in your way ([Switches](#switches)).

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
  Windows file sharing, IPv6 setup and GSConnect; your Tailscale tailnet is trusted, so who on it may
  reach this machine is decided by the tailnet's own access rules (ACLs). To let something else in,
  such as a development server you want to reach from your phone, use the **Firewall** app or
  `sudo firewall-cmd --add-port=8080/tcp` (add `--permanent` to keep it after a restart).
  `ame security firewall-away on` answers nothing at all on networks you have not named home
  ([Stricter settings](#stricter-settings)).
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
  filesystems, FireWire, test drivers, CAN, the floppy and parallel ports) cannot load. `gdb -p` on a
  process you did not start needs `sudo`.
- **Less to follow you by:** each network sees a temporary IPv6 address that changes, and Bluetooth a
  random address, visible and pairable for 30 seconds when you ask for it.
- **The kernel refuses to be rewritten while it runs.** Lockdown refuses modules without a signature
  the kernel trusts, writing to `/dev/mem`, and BPF programs that write into another program's
  memory, so a compromise of root ends at the next restart. Programs that only read, such as
  `bpftrace`, keep working. With Secure Boot on, the kernel locks itself down at every start. Without
  it, the image turns lockdown on with a kernel argument, but the modules built into the image, such
  as DisplayLink's, cannot load then ([Hardware](hardware.md#secure-boot)). On a machine where Secure
  Boot cannot be turned on, `ame security lockdown off` leaves the argument out, and
  `ame security lockdown on` puts it back, from the next restart. The NVIDIA images leave the argument
  out, and on a sealed image it is part of the signed kernel and cannot be changed.
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

- **The audit log**: accounts, `sudo` rules, what starts by itself (services, autostart entries, the
  shell startup files, `~/.ssh`, GNOME Shell extensions, top-bar widgets, D-Bus services, udev rules, git's settings), the
  security settings, SELinux's, and kernel modules loaded from a login, each with the program that made the
  change. A program opening the keyboard directly is said the first time that program does it; games and
  key remappers do it too. When too many events come at once, the kernel drops some rather than slow the
  machine down, and **Audit rules** in the report says how many it dropped in the last week.
- **The journal**: an account locked after wrong passwords, three or more wrong `sudo` or
  administrator passwords, and USB devices [USB protection](#block-usb-devices-you-did-not-plug-in)
  blocked.
- **`/etc` against the image**: the image keeps its own copy of `/etc` in `/usr/etc`, so a changed
  security setting, or a file in `/etc` that replaces one of the image's in `/usr/lib`, shows as
  **Image settings** in the report.
- **What should not exist on this system**: a setuid program outside `/usr`, `/etc/ld.so.preload`,
  a plain file in `/dev`, a file or folder in `/etc` or `/usr/local` that belongs to a login account
  rather than to root, a kernel module that did not come with the image or is not signed, and a
  network interface reading every packet. These are **Rootkit checks** in the report.
- **What accepts connections**: each program that listens on the network, which every device on
  your tailnet can reach. A new one is said once.
- **What your session finds first**: a program in `~/.local/bin`, `~/bin` or Homebrew's folder
  named like one of the system's commands, which your shell runs in place of the real one. A fake
  `sudo` or `ssh` there is an old way to catch a password, so those are said loudest; Homebrew's
  folder only counts for those. And a launcher in your app grid that no container export made. Each is
  said when it appears, and again if it changes. A folder the audit log watches, such as `~/.config`,
  made a link to somewhere outside your home folder is said too, once: the audit log stops watching it.
- **Network protection**, while it is on: each connection it blocked, with the way to allow it
  again, and what it recognised without blocking when the rule rates it serious.
  [Network protection](#network-protection).
- **The report itself**: when a check that says something was turned off, such as the firewall,
  signed updates, SELinux or the audit log, stops being fine, and when one of the protections that are off
  until you turn them on is turned off again. A change you make with its own command is recorded and not
  said (see [Switches](#switches)).
- **Itself**: a run that failed, or none for an hour, is said by the report, and by the next run that
  finishes.

What it reads that somebody else wrote, a file name, a program's name, a launcher's command, a host name
from the network, is shown as plain text everywhere: a name cannot write over a terminal or a
notification, or pretend to be another line of the history. Each finding keeps when it happened, which
part of the watcher found it, the account it is about and the kind of attack it would belong to, in
`/var/log/amethystora-security-events.jsonl`, and the last 500 in the Security app's **Events** page.

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

The **Network** list on the same page takes the network away from one app, as an override of your
account's own (`flatpak override --user --unshare=network`): it cannot then send anything it reads.
**Give its network back** undoes it. Either applies from the app's next start.

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

The **Settings** page of the Security app lists every switch, with what each does and, while it runs,
what it costs. In a terminal:

```bash
ame security settings
```

- **What happens to what a virus scan finds**: `report` (the default) leaves it where it is,
  `quarantine` moves it to `/var/lib/amethystora/quarantine`, where nothing can open or run it, and
  `delete` deletes it. This applies to the weekly scan, the scans you start in the app and real-time
  scanning. Each file is checked again before anything is done to it. `ame security scan quarantine`
  lists what is in quarantine, and `ame security scan restore` puts a file back and can tell the
  scanner to leave that exact file alone from then on.
- **Real-time watching**: `off` (the default) or `on`, for both halves at once, which can also be set
  each on its own. `realtime-watch` has the security watcher read each change as the audit log records
  it. `realtime-scan` scans every file written in a home folder as it is closed: it costs some CPU while
  files are being written, and starts once the first virus signatures have downloaded.
- **Network protection**: `off` (the default), `watch` or `block`.
  [Network protection](#network-protection).
- **The virus scanner**: `weekly` (the default), `manual`, which scans only when you start a scan, or
  `off`, which runs nothing at all and downloads nothing. Either way clamd, which holds the virus
  signatures in memory, over a gigabyte, runs only while something scans: it starts when a scan
  connects, which takes it a moment, and stops within half an hour of the last one. Real-time scanning
  keeps it running.
- **The settings audit**: Lynis every month, `on` (the default) or `off`. `ame security audit` runs one
  whenever you ask.
- **The security watcher**: `on` (the default) or `off`, and each part of what it reads on its own: the
  audit log's kinds of change (accounts, `sudo`, what starts by itself, the security settings, kernel
  modules, keyboard readers, programs in home folders), the journal, the image's settings, the setuid
  sweep, open ports, the commands a session finds first, and the report's alerts. Each is `off`,
  `record`, which keeps what it finds in the history without a notification, or `on`.
- **The audit log**: `on` (the default) or `off`, from the next restart.
- **Notifications**: `all` (the default), `critical`, or `none`. Whatever is not said is still in the
  report and in `ame security events`.

They are kept in `/etc/amethystora/security.conf`. The command and the app apply a change at once,
apart from the audit log, which follows at the next restart.

## Switches

Every security feature is a switch, so that you can take back any of it if it makes this machine slower
or gets in your way. Off costs nothing: nothing runs, nothing is downloaded and nothing is said. The
audit log's rules are locked until the next restart, so a part of it you turn off stops being read at
once and stops being recorded from the next restart.

- **Everything at once.** `ame security profile off` turns off everything that can be: the watcher, the
  virus scanner, the settings audit, real-time watching, network protection and the audit log.
  `ame security profile default` puts every switch back as the image ships it. The Settings page has
  both as buttons.
- **From a text console.** Each service reads its switch as it starts, so a line edited by hand in
  `/etc/amethystora/security.conf`, such as `VIRUS_SCAN=off`, takes effect at the next restart even when
  the desktop does not start.
- **Off is not a warning.** A feature you switched off is shown in the report as turned off, with the
  command that turns it back on. Turned off some other way, such as a service disabled with
  `systemctl`, it is still a warning, because that is what it would look like if something else did it.
- **A change you make is not news.** The watcher records a change made through a switch, and does not
  notify you about it. A change made any other way is said.
- **A warning you cannot fix** on this machine, such as Secure Boot on a computer without it, can be
  accepted with **Accept** on it in the Security app, or `ame security allow report`. It stays in the
  report as information, out of the count, and is never said, until it turns worse.
  `ame security allow report <check> remove` shows it again.

What the image enforces from the start has switches of its own, each on until you turn it off, each in
the Settings page and as a command that says what it changes before it does:

| Command | What it switches | Turned off |
| --- | --- | --- |
| `ame security kernel` | Kernel addresses and messages hidden, programs kept from each other's memory, no unprivileged BPF, a panic after a hundred oopses | From the next restart. `gdb -p`, `strace -p`, `perf` and `dmesg` work without `sudo` |
| `ame security blocked-modules` | Old network protocols and filesystems, FireWire, test and fault-injection drivers, CAN, GNSS, the floppy and parallel ports kept from loading | At once. FireWire sound cards and cameras, disks from old Macs, SCTP, CAN buses |
| `ame security kernel-args` | `init_on_alloc=1`, `slab_nomerge`, `page_alloc.shuffle=1`, `randomize_kstack_offset=on`, `vsyscall=none`, each on its own | From the next restart. Not on a sealed image |
| `ame security firewall` | The Amethystora firewall zone | At once. Fedora Workstation's zone lets in every port from 1025 up; opening one port is the narrower answer |
| `ame security failed-logins` | Blocking an address after failed SSH logins | At once |
| `ame security lockout` | Locking an account after ten wrong passwords | At once |
| `ame security app-sandbox` | Taking X11, the input devices and the Flatpak service from every app | From each app's next start; granting one app X11 in Flatseal is the narrower answer |
| `ame security virtual-input` | `/dev/uinput`, which makes a virtual keyboard that types into any window, kept from apps | At once. Steam Input and OpenTabletDriver need it off, and their setup turns it off |
| `ame security ssh-settings` | No root login, three tries and no X11 forwarding for the SSH server, and no SSH over vsock from the host of a virtual machine | At once |
| `ame security signed-updates` | Switching this machine back to signature-checked updates at every start | From the next start; for an image of your own, `ame system trust-image` is the answer |
| `ame security ipv6-privacy` | A temporary IPv6 address that changes, on every connection | From each network's next connection |
| `ame security bluetooth-privacy` | Bluetooth's random address, and visible and pairable for 30 seconds at a time | At once; Bluetooth restarts |

`ame security lockdown` and the protections that are off until you turn them on, below, are switches
already. Something with root can change any of this, but not quietly: each change is recorded by the
audit log, until you turn that off too.

### Stricter settings

Each of these takes something away that a desktop may need, so each is off until you turn it on, in the
Settings page or with its command, which says what it costs first. The report lists the ones that are
on, in case one is why something stopped working.

| Command | What it does | What it costs |
| --- | --- | --- |
| `ame security kernel strict` | No io_uring, debuggers attach only as root, more address randomisation, no IPsec | QEMU, Samba and some Node programs lose io_uring; `gdb -p` needs `sudo`; sanitizers; libreswan and strongSwan |
| `ame security kernel-args <argument> on` | `proc_mem.force_override=ptrace`, `init_on_free=1`, `iommu.strict=1` (the IOMMU on, and strict), `ia32_emulation=0`, each on its own | Untested with Wine and anti-cheat; slower; slower disks and network; no Steam or 32-bit Wine |
| `ame security lockdown strict` | Root cannot read the running kernel either | `bpftrace`, `perf` with kernel data, eBPF security tools |
| `ame security time` | The clock set only from time servers that prove who they are (NTS), three agreeing, never one a network suggests | Networks that block port 4460 leave the clock unsynced |
| `ame security firewall-away` | Networks you have not named home answer nothing; `ame security firewall-away home` names more | Printers, shares and phone pairing only at home |
| `ame security network-daemons` | Avahi and ModemManager stopped | Printers by address only; no mobile broadband |
| `ame security block-bluetooth` | Bluetooth cannot load | Headphones, mice and keyboards that use it |
| `ame security block-webcam` | The USB webcam driver cannot load | The webcam |
| `ame security block-automount` | USB sticks and disks mounted only when you open them | A click in Files |
| `ame security block-user-extensions` | No GNOME extensions installed from extensions.gnome.org; the report lists the ones you have | The image's own extensions are not affected |
| `ame security block-xwayland` | No X11, from your next login | Steam, Wine, Proton and older apps |
| `ame security flathub-verified` | Only Flathub apps whose makers Flathub verified | Installed apps from anyone else stop updating |
| `ame security flatpak-password` | Installing or removing an app for the whole machine asks for an administrator's password | A password in Bazaar |
| `ame security noexec-temp` | Nothing started from `/tmp`, `/var/tmp` or `/dev/shm` | Some installers, build scripts and `go test` |
| `ame security no-coredumps` | No copy of a crashed program's memory on disk | Crashes cannot be diagnosed from one |
| `ame security package-cooldown` | npm, pnpm and uv refuse versions published in the last 3 days; `strict` waits 7 and runs no install scripts | A fix published today waits too; strict breaks packages that build native code |
| `ame security brew-attestations` | Homebrew checks each bottle's build attestation | `gh` and `gh auth login` on every account, or `brew install` fails |
| `ame security locked-poweroff` | The machine powers off once every desktop session has stayed locked for 18 hours, so that the disk keys leave memory | Whatever was open and not saved |
| `ame security boot-password` | A password before anyone edits a boot entry or opens the boot menu's command line | Forget it and only a USB stick changes it. Not on a sealed image |
| `ame security vscodium-extensions` | VSCodium updates no extension by itself, and with names in `/etc/amethystora/vscodium-extensions` installs only those | Updates by hand. Developer mode only |

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
lists every point in time there is to go back to, in the backup and in the hourly
[snapshots](#ransomware-protection).

Files come back in **Backups**, in the app grid (or **Backups** under **System** in the Amethystora
menu). It shows your home folder as it was, with every point in time down its side: the hourly
snapshots kept on this machine and the daily backups, each marked by where it is. Pick a time, open a
folder, select what you want and press **Put back**. Nothing is deleted: a file your folder no longer
has simply comes back, and one that changed since comes back beside it, with its date in its name
(`report (2026-10-04 14.00).pdf`), unless you choose **Replace** or **Skip** when it asks. **Look**
opens a read-only copy, **Versions** lists each time a file changed, and **Put the whole folder back**
returns a folder as it was, replacing what has the same name. In Files, **Open With** on a folder
offers Backups too, and `amethystora-backups ~/Documents` opens it there.

Its **Status** page shows the last good backup and when the next one runs, with **Back up now**,
**Change…** (`ame backup setup`, in a terminal) and the daily run's switch. The security report warns
when no backup has succeeded for a week, and **Ask the agent** looks into one that failed. The hourly
snapshots are switched in Security, which Backups only opens.

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
`ame restore-setup <snapshot>` picks an older setup. Your files themselves come back in Backups. To
keep your setup in a file of your own as well, in git, see [Your setup in a file](setup.md).

### Ransomware protection

```bash
ame security ransomware
```

Every hour, a read-only snapshot of every home folder on this machine, kept in `/var/home/.snapshots`.
It is on from the first start of a machine installed from an Amethystora ISO; on one that was running
before, it stays as you left it.
Ransomware running as you can encrypt everything you can write, and a snapshot is not something you
can write: changing or deleting one takes an administrator. Every snapshot from the last day is kept,
and one a day for two weeks. The report says when the latest one is more than a few hours old.

To get files back, open **Backups** and pick a time from before the attack ([Backups](#backups)):
**Put the whole folder back** replaces the files the folder had then and leaves the ones it did not,
such as what ransomware renamed. In a terminal, `ame security ransomware restore` asks for the time
to go back to: **Open it in Files** shows your home folder as it was then, to copy from, and **Put a
folder back** does what Backups does. Nobody else's files are visible in a snapshot, and yours are not
visible to them.

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
while Secure Boot is on and the signing keys are the ones enrolled when you set it up, and only after
you type a short PIN. Your passphrase keeps working, so a cleared TPM never locks you out. This needs
a disk that was encrypted when it was installed.

The PIN is what keeps the key from someone who takes the machine. On an image that is not sealed, the
boot menu and the programs that ask for the disk key are plain files: someone holding the machine
could start it into a shell, or with a disk of their own made to look like yours, and Secure Boot
would see nothing changed. So it is set up only with a PIN here, and the report has a **Disk unlock**
check that warns about a TPM key set up without one, as earlier versions allowed:
`ame security disk-unlock on-pin` replaces it.

On a [sealed image](updates.md#sealed-images) the programs that ask for the disk key are inside the
signed kernel image, so they cannot be swapped for others that would keep it. The PIN is still asked
for there: Secure Boot does not see which disk the signed system starts from, or the settings in `/etc`
on it, and a disk of someone else's made to look like yours would start the same system with theirs.
Updates keep it working as long as Amethystora's key does not change.

`ame security boot-password on` puts a password on the boot menu as well: editing a boot entry, which is
how someone at the keyboard would start the machine into a root shell, asks for it, and starting
normally does not.

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

### Encrypted DNS

```bash
ame security dns
```

Every site you open and every server an app talks to is first a name looked up with a DNS server. By
default that is whichever one the network hands out, asked in plain text: the network sees every name,
and can answer with any address it likes. With encrypted DNS on, every lookup goes to one resolver you
choose, over DNS-over-TLS, and to nobody else: Quad9, Mullvad, Cloudflare, Google, or servers of your
own (`ame security dns custom 192.0.2.1#dns.example.net`). That resolver then sees every name in the
network's place, so choose one you trust; the command says who runs each, and
`ame security dns quad9` picks one straight away.

Names on the network itself, such as a printer's, still go to the network's own servers, and so does
the check of whether a network reaches the internet. Which names count as the network's own is the
network's to say (its search domains): one that claims a whole domain, such as `com`, has every name in
it asked of its own servers, in plain text. `resolvectl domain` shows what each network claimed. A VPN's own names keep working, and Tailscale's.
Firefox may look names up itself, over DNS-over-HTTPS, as its own settings say.

A network that wants you to log in first, in a hotel or on a train, cannot show its login page while
this is on. A notification offers to pause it: for ten minutes, the network's own servers answer, in
plain text. `ame security dns pause` does the same, `ame security dns resume` ends the pause early,
and `ame security dns off` turns encrypted DNS off.

### A different address on each network

```bash
ame security mac
```

A network knows a laptop by its hardware (MAC) address, which is the same on every network, and most
networks are told the machine's name as well, so a café, an office and an airport can each tell it is
the same machine. With this on, each Wi-Fi and wired network sees an address of its own for this
machine, the same each time it comes back, so your router keeps what it reserved for it and a login
page remembers it. No network is told the machine's name, and connections out use a temporary IPv6
address. It applies from the next time each network connects.

A network that lets in only devices it has registered, as some universities and offices do, then
refuses the machine. For that one network, open it in **Settings**, then **Identity**, and set
**Cloned Address** to **Permanent**. `ame security mac off` turns it off everywhere.

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
