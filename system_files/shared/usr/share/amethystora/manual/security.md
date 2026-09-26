# Security

Amethystora is hardened beyond Fedora's defaults, and says so plainly: everything below can be
checked, and most of it can be changed if it gets in your way.

## See where you stand

```bash
ujust security-status
```

One screen of what the security settings are actually doing right now, with what to do about
anything that is off. It changes nothing and asks for no password. **Security Report** in the app
grid shows the same. For a deeper look, `ujust security-audit` runs Lynis through a few hundred
checks and explains each finding.

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
  the tailnet alone. `ujust blocked-addresses` lists what is blocked, and
  `ujust blocked-addresses <address>` lets one back in.
- **The SSH server is off,** and refuses root logins when you turn it on.
- **Applications cannot watch each other's keyboards.** Flatpak apps are refused X11 and input
  devices ([Installing software](software.md#what-flatpak-apps-may-not-do)), and the key remapper,
  which reads every key, is off until you ask for it.
- **The browser only accepts approved extensions.** An extension sees every page you open, and that
  is how most password stealers arrive. Brave installs only the password managers named in
  `/etc/brave/policies/managed/10-amethystora.json`; to allow another, add its extension ID in a
  file of your own next to that one. Web pages are also cut off from WebUSB, WebSerial, WebHID
  (which can read a keyboard) and Web Bluetooth.
- **The kernel is hardened:** memory is wiped as it is handed out, kernel addresses are hidden,
  programs cannot read each other's memory, and rarely used modules (old network protocols and
  filesystems, FireWire) cannot load. `gdb -p` on a process you did not start needs `sudo`.
- **The kernel refuses to be rewritten while it runs.** Lockdown blocks loading untrusted modules,
  writing `/dev/mem` and tracing kernel memory with BPF, so a compromise of root ends at the next
  restart. It needs Secure Boot on and the key enrolled ([Hardware](hardware.md#secure-boot)). On a
  machine where Secure Boot cannot be turned on, drop it with
  `sudo rpm-ostree kargs --delete=lockdown=integrity`. The NVIDIA images do not use it.
- **What would survive a restart is watched.** The audit log records writes to your autostart
  entries, your own systemd services, the shell startup files and the permission overrides above,
  and every attempt to open an input device. Read it with `sudo ausearch -k persistence -i`, or
  `-k input-capture` for the last.
- **A virus scan runs every week** over your home and temporary folders, and **Lynis audits the
  settings every month.** Neither deletes or moves anything: a false positive that takes away a file
  you wanted is worse than most of what it would remove. `ujust virus-scan` shows what the last scan
  found, and `ujust virus-scan now` runs one. ClamUI does the same in a window.

## Worth turning on

### Security keys

A FIDO2 security key (YubiKey, Thetis, or a fingerprint model such as the YubiKey Bio) can sign you
in, unlock the screen and approve `sudo` and administrator prompts instead of your password:

```bash
ujust setup-security-key
```

Choose **Add a fingerprint key** for a fingerprint model, so the key checks your fingerprint and not
only a touch. The key needs a PIN, and a fingerprint model an enrolled finger, first: set them in
Brave at `brave://settings/securityKeys`, or with `ykman fido fingerprints add` on a YubiKey Bio.
Register a second key as a spare. Your password keeps working whenever no registered key is plugged
in.

### Backups

```bash
ujust setup-backup
```

A daily restic backup to a repository that ransomware on this machine cannot delete from. The
backup only ever adds to the repository and never deletes old snapshots, so an append-only
repository at the other end keeps everything backed up before an attack. The recipe explains how to
set one up on rest-server, Borg, an object store with immutability, or a USB drive you unplug
between backups. `ujust setup-backup now` backs up straight away, and `ujust setup-backup snapshots`
lists what is there.

### Unlock the disk with the TPM

```bash
ujust setup-disk-unlock
```

Instead of typing the disk passphrase at every boot, the machine's TPM hands over the key, but only
while Secure Boot is on and the signing keys are the ones enrolled when you set it up. Add a PIN if
you want the disk to need something you know as well. Your passphrase keeps working, so a cleared
TPM never locks you out. This needs a disk that was encrypted when it was installed.

### Block USB devices you did not plug in

```bash
ujust setup-usb-protection
```

A USB device can claim to be a keyboard and type by itself, and a hardware keylogger can sit
between a real keyboard and the machine. USB protection allows what is connected when you set it up
and blocks anything new until you allow it with `ujust setup-usb-protection allow`. It is off by
default, because a machine that blocked its own keyboard on first boot would be unusable.

### Key remapping

Input Remapper runs as root and reads every key typed into every application. That is what
remapping needs, and a keylogger in every other respect, so it ships switched off. If you remap keys
or mouse buttons, turn it on with `ujust setup-input-remapper`.
