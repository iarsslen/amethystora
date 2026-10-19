# Security on Amethystora

## The report and its switches

- `ame security status` summarises the security settings. The Security app (`amethystora-security`)
  shows the same report and scans for viruses. What a scan finds is only reported unless
  `ON_DETECTION` in `/etc/amethystora/security.conf` says quarantine or delete; `ame security settings`
  changes it and real-time watching (`REALTIME`). Never edit that file to loosen it without asking.
- Every security feature is a switch, and off costs nothing. `ame security settings` lists the detection
  ones with their values (`/usr/libexec/amethystora-security-config --list`): the watcher and each part
  of it, the virus scanner (`VIRUS_SCAN`, whose daemon holds the signatures in memory), the settings
  audit, the audit log, real-time watching and scanning, notifications. What the image enforces has its
  own commands: `ame security kernel`, `blocked-modules`, `kernel-args`, `firewall`, `failed-logins`,
  `lockout`, `app-sandbox`, `ssh-settings` and `signed-updates` (`/usr/libexec/amethystora-hardening
  status`). `ame security profile off` and `ame security profile default` do all the detection ones, and
  `light`, `balanced` and `thorough` set what looks for new threats (odd processes, secrets read, the
  behaviour sensor and the rest, off as the image ships). Three switches send something away (site
  checking with Osprey, asking the agent about events, hash reputation): never turn those on for the
  user, and no profile does. When the user asks for a faster machine or for something security blocks,
  name the one switch that does it and what it gives up, and let them run its command: never turn one
  off for them unasked, and always through its command, which the report then shows as turned off
  rather than as a fault. A warning that cannot be fixed on this machine can be accepted with `ame
  security allow report`, and a path or program a feature keeps saying with `ame security allow FEATURE
  ENTRY` (`ame security allow FEATURE` lists them): leave both to the user, since what is allowed is
  never said again, malware included.

## The watcher

- `ame security events` shows what the security watcher (`amethystora-security-watch`, every 15
  minutes) noticed in the audit log, the file-watch sensor's (`/var/log/amethystora-sensor/audit.log`,
  where it records those changes in audit's place) and the journal. Changes you make under `/etc`
  show up there, and a file in `/etc` that differs from the image's copy in `/usr/etc` shows as
  **Image settings**. So does a program you put in `~/.local/bin` or `~/bin` with a system command's
  name, and a launcher in `~/.local/share/applications` that no container export made: name yours
  differently. With what looks for new threats on, running an agent with its checks off from a script,
  reading another tool's token, adding a hook or MCP server to an agent's settings, or attaching to a
  program you did not start with anything but a debugger is said too: tell the user that a change of
  yours may show up there, and why.
- `ame security app-integrity` shows what the daily check of the system's files and every Flatpak app
  against what their updates installed found (`APP_INTEGRITY`, off as the image ships, on in every
  profile); `check` runs one, and `repair [APP]` fetches an app again and installs it again, keeping its
  data. Any file you change inside `/var/lib/flatpak` or `~/.local/share/flatpak`, and any launcher you put
  in their `exports`, is a finding: install, update and remove apps only with `flatpak` or Bazaar. A
  finding about the system's own files (`/sysroot/ostree`, `/boot`) means something with root changed
  them: never try to put such a file back, and leave reinstalling to the user.

## The network

- Network protection is Suricata inline on this machine's own traffic (`amethystora-ips.service`,
  helper `/usr/libexec/amethystora-ips`), set by `NETWORK` in `/etc/amethystora/security.conf`: `off`
  (default), `watch` or `block`, changed with `ame security settings network`. It fails open. With
  `block`, a site or app that suddenly cannot connect may be one it blocked: `ame security connections`
  lists them, or read `/var/lib/amethystora/security/network.json` (readable by wheel).
  `ame security connections allow <rule>` leaves one rule out; rules allowed are in
  `/etc/amethystora/ips-allowed`.
- Encrypted DNS (`ame security dns`, off by default; `/usr/libexec/amethystora-dns status` and `name`)
  sends every lookup to one resolver over DNS-over-TLS, through a drop-in in
  `/etc/systemd/resolved.conf.d` and one in `/etc/NetworkManager/conf.d`; `resolvectl status` shows it.
  A network whose login page will not load may need it paused, which asks for a password:
  `ame security dns pause` (ten minutes). A different address on each network (`ame security mac`,
  off by default; `/usr/libexec/amethystora-mac status`) gives each network its own hardware address,
  and a network that registers devices by address then refuses the machine.

## Logins

- Fingerprint login is already on in the image's PAM setup: a finger enrolled with `ame security
  fingerprint`, or in Settings, works for login, the lock screen, sudo and polkit. Enrolling needs the
  user's finger, so leave it to them.
- Never run `authselect select` by hand: it drops the features the image turns on (account lockout,
  fingerprint login, security keys) unless each is named again. A domain is joined and left with
  `realm join` and `realm leave`, whose login commands keep them (`/etc/realmd.conf`,
  `/usr/libexec/amethystora-domain-logins`).
- One-time codes for SSH ask for a code from a phone app after the password (`ame security ssh-codes`,
  off by default; `/usr/libexec/amethystora-ssh-codes status`). Setting up codes needs the user's
  phone, so leave `ame security ssh-codes setup` to them, and never turn codes on for an account that
  has neither codes nor an SSH key.

## The kernel and groups

- Kernel lockdown is on with Secure Boot, and without it through the `lockdown=integrity` argument
  (`ame security lockdown on|off`, `cat /sys/kernel/security/lockdown`). With Secure Boot off it keeps
  the image's own modules, such as DisplayLink's evdi, from loading.
- The developer groups (`ame system dx-group`, listed in `/usr/share/amethystora/developer-groups`) are
  joined only when the user picks them: `docker`, `incus-admin` and `libvirt` let any program they run
  become root without the sudo password. Prefer Podman, or `qemu:///session` for virtual machines.

## Disks

`ame system raid` with anything but `status` makes, changes and forgets pools of disks, mirrors the
system onto a new disk (`mirror DISK`, which restarts the machine) and replaces a disk of the system
(`replace system`), and erases disks: ask first. Never choose the disks or the layout for the user, and
never type `ERASE` or the disk's passphrase: the command asks for them in a terminal, and those answers
are the user's. Read the state of the pools and of the system's disks with
`/usr/libexec/amethystora-raid status --json`, which needs no root. Never edit `/boot/grub2/custom.cfg`
between its `amethystora-raid` markers, the boot entries, `/etc/crypttab` or the `md-boot` array by
hand.
