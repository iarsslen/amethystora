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
  Windows file sharing and IPv6 setup; your Tailscale tailnet is trusted, so who on it may
  reach this machine is decided by the tailnet's own access rules (ACLs). To let something else in,
  such as a development server you want to reach from your phone, use the **Firewall** app or
  `sudo firewall-cmd --add-port=8080/tcp` (add `--permanent` to keep it after a restart).
  `ame security firewall-away on` answers nothing at all on networks you have not named home
  ([Stricter settings](#stricter-settings)).
- **Your phone reaches this machine only at home.** GSConnect, which pairs it, is open only on the
  networks you name home, and closed on every other, a café's or a new one included. Name yours with
  `ame security home-networks`, which lists the networks this machine has joined.
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
  programs cannot read each other's memory, only a program's own debugger can write over its code, and
  rarely used modules (old network protocols and filesystems, FireWire, test drivers, CAN, the floppy and
  parallel ports) cannot load. `gdb -p` on a process you did not start needs `sudo`.
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
- **What would survive a restart is watched, and you are told.** Changes to accounts, to who may use
  `sudo`, to what starts by itself (your autostart entries, your own systemd services, the shell
  startup files) and to the security settings, and every program that opens an input device, are
  recorded. On most machines a small sensor records them where they happen, so watching them costs
  the rest of the machine nothing; where its kernel will not run it, the kernel's own audit log does
  the same, which makes every program a little slower. Either way the security watcher reads what was
  recorded every 15 minutes and says what changed and which program changed it. Something with root can
  stop the sensor: that is said too, but what happens while it is down is not recorded, whereas the audit
  log, locked at boot, holds until the next restart. `ame security audit-locked` keeps the audit log doing
  it if you would rather. [The security watcher](#the-security-watcher).
- **A virus scan runs every week** over your home and temporary folders, and **Lynis audits the
  settings every month.** By default neither deletes or moves anything: a false positive that takes
  away a file you wanted is worse than most of what it would remove. `ame security scan` shows what
  the last scan found, and `ame security scan now` runs one. [Scanning for viruses](#scanning-for-viruses)
  does the same in a window, and [Settings](#settings) makes scans quarantine or delete what they find.

## The security watcher

Every 15 minutes, or as things happen with [real-time watching](#settings) on, the watcher looks at what
is listed below. On battery, its runs every 15 minutes wait for mains power, and the next one reads the audit
log and the journal from where the last one stopped; `ame security settings on-battery run` keeps them going
on battery too.

The watcher looks at:

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
X11, the input devices or, as the apps the image installs that need it are, the Flatpak service. If you did not mean it to, change it in **Flatseal**, or take back
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
- **YARA rules for the virus scanner**: three sources, each `off` (the default) or `on`, which ClamAV
  then matches files against by their structure, where a hash signature misses a variant: `yara-elastic`,
  Elastic's rules for Linux malware; `yara-signature-base`, Florian Roth's, mostly about Windows malware and
  attack tools, some of which a security professional runs on purpose; and `yara-forge`, YARA Forge's core
  set from many authors, of which only the rules whose licence asks nothing but their author's name are
  used. They are downloaded on this machine daily, not on a metered connection, and each rule ClamAV cannot
  load is left out. A match names the rule and its author. The weekly scan, with them or not, waits for
  mains power on a laptop; a scan you start does not.
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
- **A profile for what looks for new threats.** `ame security profile light` records the cheapest of
  [what looks for new threats](#looking-for-new-threats) and says ransomware, agents' settings and apps
  that gain permissions; `balanced` says all of those, records secrets read, programs run from the
  downloads and programs loaded into the kernel, puts the chains of steps together and fetches the
  command-server lists daily; `thorough` turns all of it on, the decoy key, the YARA rules and the
  behaviour sensor included, which costs memory, CPU and downloads, and on a developer's machine some
  noise. Each sets every other switch to its default, and none turns on what sends something to somebody
  else. Every switch can still be changed alone afterwards; the Settings page then says the switches are
  changed from the profile.
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
- **Something you know is fine.** An event on the **Events** page that names a file or a program has
  **Allow…**: what matches it is recorded from then on, and no longer said. In a terminal,
  `ame security allow persistence '~/.local/share/gnome-shell/extensions/*'` does the same for a path or a
  glob of paths, `~/` standing for every home folder, and `ame security allow persistence` lists what is
  allowed. Allow only what you know: whatever matches, malware included, goes unannounced from then on.
  The image allows a few of its own the same way, such as Fedora's sssd and tuned rewriting their settings
  at every start and fwupd's passim listening for nearby machines: `ame security allow hardening` and
  `ame security allow listeners` list them.

What the image enforces from the start has switches of its own, each on until you turn it off, each in
the Settings page and as a command that says what it changes before it does:

| Command | What it switches | Turned off |
| --- | --- | --- |
| `ame security kernel` | Kernel addresses and messages hidden, programs kept from each other's memory, no unprivileged BPF, a panic after a hundred oopses | From the next restart. `gdb -p`, `strace -p`, `perf` and `dmesg` work without `sudo` |
| `ame security blocked-modules` | Old network protocols and filesystems, FireWire, test and fault-injection drivers, CAN, GNSS, the floppy and parallel ports kept from loading | At once. FireWire sound cards and cameras, disks from old Macs, SCTP, CAN buses |
| `ame security kernel-args` | `init_on_alloc=1`, `slab_nomerge`, `page_alloc.shuffle=1`, `randomize_kstack_offset=on`, `vsyscall=none`, `proc_mem.force_override=ptrace` (only a program's own debugger writes over its code), each on its own | From the next restart. Not on a sealed image. Older releases of the `rr` debugger need the last one off |
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

## Looking for new threats

New malware has no virus signature yet, so these look for what it does rather than what it is. Each is
off until you turn it on, in the Settings page or with `ame security settings`, and each can be `record`,
which keeps what it finds in the history and the Events page without a notification, or `on`. None sends
anything anywhere unless its own entry says so.

- **Odd processes** (`processes`): every 15 minutes, what runs. A program whose file was deleted while it
  runs, or that runs from memory alone, which malware does to leave nothing to scan; one in a temporary
  folder, `~/.cache` or your download folder; a process that names itself like a kernel thread but runs a
  program, which kernel threads never do; a network tool or an AI agent started by an npm package's install
  script; and an AI agent run with its own checks turned off (such as `--dangerously-skip-permissions` or
  `--yolo`), said when it was not started at a terminal. Each is said the first time for that program.
  Flatpak's and Homebrew's updates, containers, AppImages and Go's tests are allowed already.
- **Ransomware behaviour** (`snapshot-watch`): ransomware and wipers, whatever their family, rewrite or
  delete many files at once. After each hourly snapshot ([Ransomware protection](#ransomware-protection),
  which this needs), the watcher lists what changed since the one before, from the snapshots' bookkeeping
  alone. When more than 300 files of one account changed, it looks at up to a hundred of them: a file that
  went from readable to random is what encryption looks like, while photos and archives, already random, do
  not count. Caches, build output and dependency folders are left out. Encryption, or more than 300 files
  deleted, is critical, and its event has **Open in Backups**, at the snapshot from before it.
- **Programs run from download folders** (`exec-watch`): the audit log records each program run from a
  temporary folder, `~/.cache` or your download folder, and each is said the first time: a download or a
  dropped file starting. Builds run thousands of programs from `/tmp`, so `record` keeps it quiet while it
  learns. It takes effect from the next restart, and a script started through its interpreter (`sh
  /tmp/x`) is seen by odd processes instead.
- **AI agents run with their checks off** (`agent-clis`): an AI agent started with a flag that has it do
  whatever it is told without asking, such as `--dangerously-skip-permissions` or `--yolo`. The Nx attack of
  August 2025 ran agents that way from an npm install script, to search the machine for secrets. The audit
  log records each run of an agent from the folders it is installed in, and one started with no terminal is
  said; one you started at a terminal is recorded. It takes effect from the next restart, and an agent
  installed since then is seen by odd processes instead. A script of yours that runs an agent on purpose is
  allowed with **Allow…** on its event.
- **Credential tripwires** (`credentials`): password stealers, and the poisoned npm and PyPI packages that
  carried one, read keys and tokens, send them out and exit, leaving nothing to scan. The audit log records
  each read of where secrets are kept: SSH's keys, npm's, PyPI's, git's, GitHub's, the clouds' and the
  container registries' tokens, the keyring, the browsers' passwords and cookies, and the AI agents' tokens.
  A program reading one that is not its own is said, and one process reading several kinds is critical:
  that is the sweep a stealer makes. SSH, git, the browsers, the agents, the backup, the virus scans and the
  file indexer are allowed already. It records which programs read secrets, never what they read, and takes
  effect from the next restart. Chromium's saved passwords are in a file whose name has a space, which the
  audit log cannot watch.
- **Decoy key** (`decoy`): puts a fake SSH key, `~/.ssh/id_backup`, in each home folder. SSH never offers a
  key by that name on its own, so nothing legitimate reads it, and any read of it is critical. It is a
  switch of its own because it puts a file in your home folder; turned off, it is taken away again at the
  next restart. A key of your own by that name is never touched, and then no decoy is made.
- **Apps that gain permissions** (`app-permissions`): a Flatpak app that gains a way out of its sandbox
  ([App permissions](#app-permissions)), through an update, an override or another app in its place. An
  app installed with its permissions is recorded; a permission added to one you have is said. It is read
  as each account, for the accounts with a session in the last day, and said to that account alone.
- **SELinux denials** (`selinux-denials`): SELinux keeps each confined service to what its policy allows,
  and records what it refused. A service suddenly refused something it never tried before is often what
  an exploit looks like from outside. Each different denial is said the first time; one SELinux let
  through, because that service's domain is permissive, is recorded. It reads the audit log, so it needs
  the audit log on.
- **AI agents' settings** (`agent-config`): what your AI agents' own settings have them run by themselves.
  A hook runs a command at every step the agent takes, and an MCP server is a program it starts, or an
  address it sends to: planted in its settings, either runs the next time you ask it anything. Claude
  Code's, Codex's, Antigravity CLI's, Gemini CLI's, Opencode's, Cursor's and Copilot's are read, with the commands their
  settings run (a status line, a key helper), the plugins and extensions they load, and a permission mode
  that turns their checks off. Folders and tools you trust are recorded. Only your own settings: read a
  repository's agent files (`.claude/`, `.mcp.json`, `.vscode/tasks.json`) before you open it with an
  agent. Read as each account, like app permissions.
- **Programs in the kernel** (`bpf-programs`): eBPF rootkits load small programs into the kernel that
  hide files, processes and connections. systemd and the firewall load the same few every time, so a new
  one is recorded, and said when a program outside the system loaded it, or when it watches what the kernel
  does and nothing is left holding it. A rootkit that also hides its programs from this is not caught; most
  do not.
- **Startup hooks in developer tools** (`dev-hooks`): code put where a developer tool runs it by itself.
  A Python `.pth` file whose lines start with `import` runs them at every start of Python, which is how a
  poisoned package stays after it is removed; git's `core.hooksPath`, `core.fsmonitor` and
  `core.sshCommand` run in every repository; SSH's `ProxyCommand`, `LocalCommand` and `Match exec` run
  on connecting; npm's `script-shell` and `node-options` change what npm and Node run. A new VSCodium
  extension is said too, and its updates, which it installs by itself, are recorded. Read as each
  account, like app permissions. Virtual environments are not looked into.

- **Behaviour sensor** (`behaviour`): Falco, which sees what every process does as the kernel sees it, each
  command, file opened and connection, through an eBPF probe, and matches it against its rules: a shell
  started by a server, a secret read by a program that has no business with it, a binary dropped and run.
  The watcher reads what they notice. Unlike the others it runs all the time, for a little CPU and a few
  hundred megabytes of memory, and its rules are the ones its package ships, never downloaded. If the probe
  cannot load into the running kernel, the report says so under **Detection services**.
- **Chains of steps** (`chains`): an attack is steps that each look harmless alone: a program run from the
  downloads, a token read, a connection out. Each finding names its account and its step, and this puts them
  together: two different steps for one account within half an hour are said, and three, or reading secrets
  and then reaching a command server, are critical. What the others only record counts too, so they can stay
  quiet and still help; what you allowed does not. Each chain is said once, and again only when it grows.

**Hash reputation** (`ame security settings reputation`, off until you choose it) looks up each program that
odd processes or the download folders' watch saw run for the first time with MalwareBazaar, by its hash,
and says at once if it is known malware. It sends only the hash, never the file, its name or its path, to
abuse.ch, with your own free key from [auth.abuse.ch](https://auth.abuse.ch/), which the command asks for and
keeps where only root can read it. A hash can still say which files you have, and the lookups made with one
key say when new programs ran, which is why you choose it on its own. It knows only malware someone has
already sent in, and changing one byte of a program defeats it: it catches nothing new, only the old sooner.

With **Ask the agent about events** on (`ame security settings triage`, off until you choose it), each event
on the Events page has **Ask the agent**: your AI agent explains, in a terminal, what it most likely is and
how sure it is, reading only and changing nothing. The event, and what the agent then reads on this machine,
goes to the agent's maker, which is why you choose it on its own. An event is written partly by whatever it
is about, so the agent is told to read it as data, never as instructions.

What one of them finds about your own account, such as your apps, is said to you. The rest is said to
the administrators, who see all of it on the **Events** page.

### Stricter settings

Each of these takes something away that a desktop may need, so each is off until you turn it on, in the
Settings page or with its command, which says what it costs first. The report lists the ones that are
on, in case one is why something stopped working.

| Command | What it does | What it costs |
| --- | --- | --- |
| `ame security kernel strict` | No io_uring, debuggers attach only as root, more address randomisation, no IPsec | QEMU, Samba and some Node programs lose io_uring; `gdb -p` needs `sudo`; sanitizers; libreswan and strongSwan |
| `ame security kernel-args <argument> on` | `init_on_free=1`, `iommu.strict=1` (the IOMMU on, and strict), `ia32_emulation=0`, each on its own | Slower; slower disks and network; no Steam or 32-bit Wine |
| `ame security lockdown strict` | Root cannot read the running kernel either | `bpftrace`, `perf` with kernel data, eBPF security tools |
| `ame security time` | The clock set only from time servers that prove who they are (NTS), three agreeing, never one a network suggests | Networks that block port 4460 leave the clock unsynced |
| `ame security firewall-away` | Networks you have not named home answer nothing; `ame security home-networks` names more | Printers and shares only at home, as phone pairing always is |
| `ame security network-daemons` | Avahi, ModemManager and passim (fwupd's sharing of firmware updates with machines nearby) stopped | Printers by address only; no mobile broadband; each machine downloads its own firmware updates |
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

### A duress finger or password

A duress finger, or a duress password, is a second way to unlock the machine, for when someone makes you
unlock it in front of them. At the login screen and the lock screen it unlocks the machine like your
usual finger or password, so nothing looks different. At `sudo`, administrator prompts, the text consoles
and over SSH it is refused, as a finger or a password that did not match, so it never hands over
administrator rights. Either way, an action you chose beforehand runs as root, once until the next start:

```bash
ame security duress
```

**Set up a duress finger** enrols one more finger, has you touch the reader with it and with another
finger to check that the reader tells them apart, and asks what its action should be. **Set up a duress
password** asks for a second password, only yours and different from the one you log in with, and asks the
same. The finger and the password **each have their own action**, so each can do something different; you
change either later with **Change the duress finger's action** or **Change the duress password's action**.
An action is one of: an alert sent to an address of yours (an [ntfy.sh](https://ntfy.sh) topic only you
know, for example), the disk's key taken out of the TPM so that the next start asks for the passphrase
([Unlock the disk with the TPM](#unlock-the-disk-with-the-tpm)), power off ten minutes later, or a script
of your own, which it shows you before it keeps it. None of the examples erases anything, but the action is
an ordinary root script and yours to write, so it can do whatever root can. **Test my duress finger** says
which finger a touch matched and never runs the action; **Remove my duress finger** and **Remove my duress
password** forget yours, and **Turn off for everyone** forgets every account's and both actions.

A duress finger needs a reader that compares a touch with every enrolled finger at once, which most
readers built into laptops do; the setup says so when yours does not. A duress password needs no reader.
Nothing about either reaches the journal or the Security report while it works, and the setup lives in a
folder only root can read. The security watcher checks each: when an action, or a duress finger's print,
changes other than through `ame security duress`, that action no longer runs, and the report and a
notification say so under its own heading. Enrolling the finger again, or **Remove all fingers** in
`ame security fingerprint`, removes a duress finger too; set it up again afterwards.

What it cannot do: stop anyone asking for your usual password instead, help against a copy of the disk
made before, or hide from someone who already has root on this machine. In many places, destroying data
while compelled by the authorities is an offence of its own; what the action does is yours to decide.

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

What you allowed is in `/etc/amethystora/browser-extensions`, one ID a line. To take one back,
`ame security browser disallow <id>`. It is off by default: Firefox comes exactly as Fedora builds it,
and what it may install is your decision, not the image's.

**Site checking** (`ame security browser osprey`) allows Osprey: Browser Protection, which checks each
site you open against more than twenty threat-intelligence providers, and warns you or blocks the site.
Amethystora does not make it, and never installs it: you do, from your browser's own store, which the
command opens, and it can be removed there like any other extension. It sends the address of every site
you open to Osprey Project LLC, in California, which passes it on to its providers without the query
string and without your address. That is why it is off until you choose it, and why no profile turns it
on. Which providers it asks is set in Osprey's own settings, and Amethystora sets none of them.
`ame security browser osprey off` takes it off the list again: with browser protection on, browsers then
turn it off, and Firefox removes it; with protection off, remove it yourself.

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
Firefox asks the same resolver, since its own DNS-over-HTTPS is off as Fedora builds it. Turned on in
Firefox's settings (**Privacy & Security**, **DNS over HTTPS**), it sends Firefox's lookups to the
provider chosen there instead, encrypted too.

A network that wants you to log in first, in a hotel or on a train, cannot show its login page while
this is on. A notification offers to pause it: for ten minutes, the network's own servers answer, in
plain text. `ame security dns pause` does the same, `ame security dns resume` ends the pause early,
and `ame security dns off` turns encrypted DNS off.

### A different address on each network

```bash
ame security mac
```

A wired network knows a computer by its hardware (MAC) address, which is the same on every network,
and every network is told the machine's name, and over IPv6 an identity made from it, so a café, an
office and an airport can each tell it is the same machine. Wi-Fi networks already see an address of
their own, one for each network name. With this on, each Wi-Fi and wired network sees an address and
an identity of its own for this machine, the same each time it comes back, so your router keeps what
it reserved for it and a login page remembers it, and no network is told the machine's name. It
applies from the next time each network connects. Temporary IPv6 addresses, which change over time,
are on already (`ame security ipv6-privacy`).

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

Two more sets of rules can join it, each off until you turn it on:

- **Faster command-server lists** (`ame security settings network-feeds daily` or `hourly`): abuse.ch's
  lists of botnet servers, of the certificates command servers use, and of addresses that served malware,
  which know a new campaign within hours, where the rules above take days. Under `block`, the first two
  block; the malware addresses only report, since one is often a shared host. They are downloaded on this
  machine, not on a connection marked as metered, and take more memory: the malware addresses are some
  forty thousand rules.
- **Hunting rules** (`ame security settings network-hunting record`): Emerging Threats' rules for what is
  suspicious but uncertain, which is where new attacks first show. They are recorded, for the
  [chains of steps](#looking-for-new-threats), and never said or blocked.

**Odd names in DNS** (`ame security settings dns-names`) needs none of this. It follows what the system's
resolver is asked, encrypted DNS or not, and keeps only a name that looks made by a program, as malware
makes the names of its command servers, or one long enough to carry data, as DNS tunnelling does. Every
name passes through it, and only those are kept, for up to 15 minutes, where only root can read them: it
keeps no history of the sites you visit. A browser that sends its own encrypted DNS goes past it; Firefox
does not unless you turn that on in its settings. CDNs, which name their servers at random, are allowed
already.

### Key remapping

Input Remapper runs as root and reads every key typed into every application. That is what
remapping needs, and a keylogger in every other respect, so it ships switched off. If you remap keys
or mouse buttons, turn it on with `ame security input-remapper`.
