# What the image does on purpose

Written for AI agents: the defaults Amethystora hardens, each with the symptom it causes, the command that
confirms it, and the switch that changes it. These are the usual root causes of "it works on Fedora but not
here". Name the switch and what it gives up, and let the user run any switch that loosens protection: the
agent never does. `state security-settings` shows which of these are on.

## Apps and devices

### Flatpak apps get no X11, input devices or Flatpak service

Symptom: an app has no window or crashes at start (it needs X11), a game or tool cannot see a controller or
tablet, a launcher app cannot start other Flatpaks. Confirm: `state app-permissions` with the app's id as
filter, or `flatpak info --show-permissions APP`; the image's override is `/etc/flatpak/overrides/global`.
Change: one app, one permission, for the user: `flatpak override --user --socket=x11 APP` (or
`--device=input`, `--talk-name=org.freedesktop.Flatpak`); say what it gives the app first. `ame security
app-sandbox off` drops the whole override for every app (the user's choice).

### /dev/uinput is root's

Symptom: Steam Input, a drawing tablet's driver or a key remapper cannot make a virtual device. Confirm:
`ls -l /dev/uinput`. Change: `ame security virtual-input off` gives it back (the user runs it); `ame apps
gaming` and `ame apps opentabletdriver` do it for what they install.

### Some devices are given only to the person at the seat

Symptom: a keyboard's configuration tool, a microcontroller board or a USB DAC works for the person logged
in at the screen but not over SSH or for another account. Confirm: the device's rule in
`/usr/lib/udev/rules.d` uses `TAG+="uaccess"`. Change: nothing to change: log in at the machine.

### USB devices plugged in later are refused (only with USBGuard on)

Symptom: a new USB device does nothing. Confirm: `systemctl is-active usbguard.service`, `usbguard
list-devices` (root); with `usbguard-dbus.service` not masked, the mode is `locked`, which blocks only what
is plugged in while the screen is locked. Change: `ame security usb` lets the user allow it; off as the
image ships.

### Rarely used kernel modules do not load

Symptom: a floppy, a parallel port, some old network protocols (SCTP, DCCP, TIPC) or filesystems (HFS, JFFS2,
UFS, minix) do nothing. Confirm: `modprobe -n -v MODULE` prints `install /usr/bin/false`; the list is
`/usr/lib/modprobe.d/60-amethystora-hardening.conf`. Change: `ame security blocked-modules off` (the user's).

### FireWire does not load

Symptom: a FireWire sound card, DV camera or disk does nothing; a FireWire device reads and writes memory by
itself. Confirm: `modprobe -n -v firewire_ohci` prints `install /usr/bin/false`; the file is
`/usr/lib/modprobe.d/61-amethystora-firewire.conf`. Change: `ame security firewire off` (the user's).

### Kernel lockdown keeps unsigned modules out

Symptom: a module built outside the image (an out-of-tree driver, VirtualBox) will not load, or DisplayLink's
`evdi`, `xone` or `hid-xpadneo` fails with Secure Boot off. Confirm: `cat /sys/kernel/security/lockdown`; `mokutil --sb-state`.
Change: `ame security secure-boot` enrolls the image's key for its own modules; `ame security lockdown off`
(the user's) for the rest.

### Some programs lost their setuid bit

Symptom: `chfn`, `chage`, `gpasswd`, `newgrp`, `ksu` or `mount.davfs` fail for a normal account. Confirm: `ls -l
/usr/bin/chfn`. Change: run them with `sudo`; this is by design.

### The clipboard history is sealed under the login keyring

Symptom: the clipboard history (`Super+Shift+V`) shows only what was copied since login, under a row "Unlock
to see earlier items" (a login by fingerprint or security key leaves the login keyring locked), or says
"Not saved" (there is no keyring). Confirm: the history is Amethystora Clipboard's, sealed in
`~/.local/state/amethystora/clipboard` under a key kept in the login keyring; `busctl --user get-property
org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked`
says whether that keyring is locked (never print the key). Change: click the row and type the login password,
or log in with the password. How long it is kept: `ame desktop clipboard always|restart|session`. A history
that did not open with the keyring's key (another machine's, or a keyring made again after a password reset)
was moved aside to `history.unreadable`, not deleted.

## The kernel

### dmesg, ptrace and core dumps are restricted

Symptom: `dmesg` says "Operation not permitted" without sudo; a debugger cannot attach to a program it did not
start (`ptrace_scope` 1); a crashed setuid program leaves no core. Confirm: `sysctl kernel.dmesg_restrict
kernel.yama.ptrace_scope fs.suid_dumpable`, set in `/usr/lib/sysctl.d/60-amethystora-hardening.conf`. Change:
use `sudo dmesg`; start the program under the debugger; `ame security kernel off` (the user's) drops the whole
set.

### The image's kernel arguments

Symptom: rare: a debugging tool that needs `vsyscall`, or memory that is zeroed on allocation costing a little
speed. Confirm: `cat /proc/cmdline`; the image's are in `/usr/lib/bootc/kargs.d/10-amethystora-hardening.toml`.
Change: `ame security kernel-args ARGUMENT off` (the user's). On a machine with layered packages, kernel
arguments the image added later never arrive: rpm-ostree ignores kargs.d.

## The network

### The firewall answers only what a desktop needs

Symptom: a server started on this machine (a dev server, a game host, SSH) is unreachable from another
machine. Confirm: `firewall-cmd --get-active-zones`, `firewall-cmd --zone=amethystora --list-all`. Change: open
the one port for the user to confirm: `sudo firewall-cmd --permanent --zone=amethystora --add-port=PORT/tcp` then
`sudo firewall-cmd --reload` (root); `ame security firewall off` (the user's) puts Fedora's zone back.

### Phone pairing is open only at home

Symptom: GSConnect does not find the phone. Confirm: `nmcli -g connection.zone connection show NAME` for the
network; only the networks named home use `amethystora-home`. Change: `ame security home-networks` names this network home (the
user's choice).

### Away from home, nothing answers (only with firewall-away on)

Symptom: on an unnamed network even ping fails. Confirm: the default zone is `amethystora-away`. Change: name
the network home, or `ame security firewall-away off`.

### fail2ban blocks an address after failed SSH logins

Symptom: SSH from one machine is refused after a few wrong passwords. Confirm: `ame security addresses`.
Change: `ame security addresses ADDRESS` lets it back in.

### Encrypted DNS behind a network's login page (only with DNS on)

Symptom: a hotel or café network's login page will not load, or names do not resolve on one network. Confirm:
`/usr/libexec/amethystora-dns status`, `resolvectl status`. Change: `ame security dns pause` (ten minutes, a
password); never pause or turn it off for the user.

### A new hardware address on each network (only with it on)

Symptom: a network that registers devices by address refuses the machine, or a router's reservation stops
working. Confirm: `/usr/libexec/amethystora-mac status`. Change: `ame security mac off` (the user's).

### Network protection blocks a connection (only with NETWORK=block)

Symptom: one site or app suddenly cannot connect. Confirm: `ame security connections`. Change: `ame security
connections allow RULE` leaves one rule out (the user's).

### Temporary IPv6 addresses and Bluetooth privacy

Symptom: a server that allows by IPv6 address sees a new one; a Bluetooth device is visible for 30 seconds
only. Confirm: `ame security ipv6-privacy`, `ame security bluetooth-privacy`. Change: their `off` (the user's).

## Logins

### Ten wrong passwords lock an account for ten minutes

Symptom: the right password is refused at login, sudo or the lock screen. Confirm: `faillock --user ACCOUNT`.
Change: wait ten minutes, or `sudo faillock --user ACCOUNT --reset`; `ame security lockout off` (the user's).

### Parental Controls' hours at the text consoles and over SSH

Symptom: a child's account is refused at a text console or over SSH outside its hours, while the desktop shows
GNOME's own lock. Confirm: the account's hours in Settings, Parental Controls. Change: the hours there.

### The sudo PATH is fixed

Symptom: `sudo mytool` finds no `mytool` installed in the home or by Homebrew. Confirm: `sudo sh -c 'echo $PATH'`.
Change: give the full path, `sudo /home/linuxbrew/.linuxbrew/bin/TOOL`.

### Login stacks are the image's

Symptom: a change to PAM by hand is undone, or the security report calls it drift. Change: never run
`authselect select` or edit `/etc/pam.d`: the image's features (lockout, fingerprint, security keys) come from
its own profile; domains join with `realm join`.

## Updates and the image

### Only signed images are installed

Symptom: `bootc switch` or a rebase to another image is refused. Confirm: `/etc/containers/policy.json`.
Change: `ame system trust-image` trusts the owner's key for their own image (the user's); `ame system rebase`
takes signed images only.

### Layered packages slow every update

Symptom: updates take long or fail on a package conflict. Confirm: `state overview` lists layered packages.
Change: move the package to a Flatpak, Homebrew or a container, then `rpm-ostree uninstall PACKAGE` (root,
restart).

## The stricter settings (off unless turned on)

Each is `ame security NAME on|off`, said in the report's `stricter` check when on.

### noexec-temp

Symptom: an installer or build script fails with "Permission denied" running something from `/tmp`. Confirm:
`findmnt /tmp`. Change: run it from the home; `ame security noexec-temp off` (the user's).

### time

Symptom: the clock does not set on a network that blocks NTS. Confirm: `chronyc sources`. Change: `ame security
time off` (the user's).

### block-xwayland

Symptom: every X11-only app fails, games included. Confirm: `ame security block-xwayland`. Change: its `off`.

### block-webcam, block-bluetooth, block-automount, block-user-extensions

Symptom: no camera; no Bluetooth at all; a USB stick does not mount until opened in Files; extensions cannot
be installed from extensions.gnome.org. Change: each one's `off` (the user's).

### flathub-verified, flatpak-password

Symptom: an app from an unverified maker cannot be installed; installing for the whole machine asks for an
administrator's password. Change: install into an installation of the account's own that has Flathub, or each one's `off`.

### package-cooldown, brew-attestations

Symptom: npm, pnpm or uv refuse a version published in the last few days; Homebrew refuses a bottle without a
build attestation, or needs gh and a GitHub login. Change: wait, pin an older version, or each one's `off`.

### no-coredumps, locked-poweroff, boot-password, network-daemons

Symptom: a crash leaves no core for `coredumpctl debug`; the machine powers off after 18 hours locked; the
boot menu asks for a password to edit an entry; printers and devices are not discovered and mobile broadband
does not work (Avahi, ModemManager and passim are off). Change: each one's `off` (the user's).
