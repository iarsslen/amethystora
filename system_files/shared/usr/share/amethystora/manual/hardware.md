# Hardware

Amethystora runs best on hardware that Linux supports well: Intel and AMD graphics, and the laptops
their makers certify for Linux. Most things work the moment they are plugged in; this page is about
the ones that need a step from you.

## Secure Boot

Leave Secure Boot on. With it, the machine only boots a kernel it has checked, and the kernel's
[lockdown](security.md) has something to stand on.

The kernel modules built into the image, for DisplayLink docks and virtual cameras, are signed with
Amethystora's own key, and the firmware has to be told to trust it once:

```bash
ame security secure-boot
```

Restart, and a blue screen appears before the system starts: the MOK manager. Choose
**Enroll MOK**, then **Continue**, then **Yes**, and type the password `amethystora`. The screen uses
a US (QWERTY) keyboard layout whatever your own is, which matters if your keyboard puts the letters
elsewhere. `ame security status` tells you whether the keys are enrolled.

If Secure Boot is off, a notification says so once. Turn it on in the machine's firmware settings,
then run the command above.

A [sealed image](updates.md#sealed-images) needs Amethystora's key before it can start at all, so its
installer asks the MOK manager for it, together with the modules' key: the blue screen comes at the
first start, and asks the same password.

## Graphics

- **Intel and AMD** work out of the box. The developer image adds ROCm for GPU compute on AMD.
- **NVIDIA** needs the `-nvidia-open` images, which carry NVIDIA's open kernel driver ([Installing](installing.md#pick-an-image)).
  The NVIDIA driver is built for the machine and signed with its own key, which the kernel trusts
  only with Secure Boot on. So the NVIDIA images turn kernel lockdown on only with Secure Boot, as
  the kernel itself does, never with an argument of their own.
- **Installed the image without NVIDIA's driver on a machine with an NVIDIA card?** There is no
  installer for the NVIDIA images, so this is how most NVIDIA machines start. A few minutes after the
  first boot a notification offers **Switch images…**, which opens `ame system rebase` on the
  matching `-nvidia-open` image; it takes signed images only and asks before it switches. An NVIDIA
  image on a machine without an NVIDIA card offers the image without the driver, which keeps
  lockdown on. Nothing switches by itself, it is said once for the machine, and **Don't ask again**
  stops it for good.

## Docks and displays

- **DisplayLink docks** work with the driver built into the image. With Secure Boot on, the dock
  stays dark until the key above is enrolled.
- **External monitor brightness** can be set from the command line with `ddcutil`, for monitors
  that support it.

## Disks

- **Encryption** is chosen when installing and cannot be added afterwards. Once it is on,
  `ame security disk-unlock` lets the TPM unlock the disk at boot instead of you typing the
  passphrase ([Security](security.md#unlock-the-disk-with-the-tpm)).
- **Several disks** can keep copies of each other: [Pools of disks](#pools-of-disks-raid).
- **ZFS** is available on the `stable` stream.

## Pools of disks (RAID)

Two disks or more can hold the same files, so that one can fail without taking a file with it. That is
a pool. The **Disks** group on [Control](control.md)'s **System** page shows them and makes them, or in
a terminal:

```bash
ame system raid              # how the pools are, and what can be done next
ame system raid create       # a pool from spare disks
```

`create` offers only the disks nothing is using: never the system's own, nor one with anything mounted
or open on it. Pick the disks, a layout and whether to encrypt, and type `ERASE`: everything on those
disks is erased, and the list shows what is on each first. Each question has its answer chosen
already, so it can be Enter, Enter, Enter and `ERASE`. The pool is then at `/var/mnt/data` (or the
name given with `--name`), belongs to you, and is in the Files sidebar.

| Layout | From | Survives | Worth knowing |
| --- | --- | --- | --- |
| **Two copies** | 2 disks | one dead disk | The one to choose unless you have a reason not to |
| **Three copies** | 3 disks | two dead disks | A third of the space for files |
| **Striped two copies** | 4 disks | one dead disk | Faster for large files, and as safe as two copies |
| **Parity** | 3 disks | one dead disk | btrfs's own advice: not for production, only for testing. A power cut can damage what was being written: check every copy after one |
| **Double parity** | 4 disks | two dead disks | The same as parity |
| **Combined** | 2 disks | none | Joins the disks into one and keeps no copies: a dead disk takes its files with it |

The list of layouts says how much each would hold on the disks you picked.

- **Encrypted** unless you say no. The pool's key is kept on the system disk, so the pool opens with
  the system and is as safe as the system disk is, and a pool disk that leaves the house, sent back
  under warranty or thrown away, gives nothing away. `create` shows a **recovery key** once: write it
  down. It opens the pool's disks on any Linux machine, and without it a pool whose system disk is
  lost is lost too.
- **A pool is not a backup.** A file deleted, or encrypted by ransomware, is gone from every disk at
  once. [Backups](security.md#backups) cover your home folder; to back up a pool as well, add its
  folder to `AMETHYSTORA_BACKUP_PATHS` in `~/.config/amethystora/backup.env`, after your home folder.
- **A disk on USB** can be part of a pool, but a loose cable takes it out: keep it plugged in.

### When a disk fails

A pool that loses a disk goes on working, which is why nobody notices until the second one goes. So
Amethystora looks every hour and says so in a notification: which pool, which disk by its model and
serial number, and whether every file is still there. **Open Control** goes to the Disks group, where
the pool says what happened and offers what to do:

- **Replace a disk** (`ame system raid replace NAME`) takes a spare disk at least as large, erases it
  and copies onto it what the old one held. It asks for the pool's recovery key, to put it on the new
  disk too; left empty, every disk of the pool gets a new one. It goes on if the window is closed.
- **Open it with a disk missing** (`ame system raid mount NAME`) is for a pool that did not open
  because a disk was missing when the machine started. What is written to it then has one copy until
  the disk is replaced. A pool missing more disks than its layout survives opens read-only, so that
  what is left can be copied off.
- **Put the copies back** comes up when the missing disk came back: what was written while it was
  away has one copy until then.
- A disk **counting errors** had reads or writes fail. btrfs read the other copy, so no file was lost,
  but a count that keeps rising means the disk, or its cable, is going. Once the cause is fixed,
  `sudo btrfs device stats --reset /var/mnt/NAME` sets the count back to zero.

### Looking after a pool

- **The monthly check** reads every copy, on mains power, and repairs a damaged one from a good one.
  **Check every copy now** (`ame system raid scrub now`) does it straight away: do that after a power
  cut on a pool with parity. `ame system raid scrub off` turns the monthly check off.
- **Add a disk** (`ame system raid add NAME`) makes room for more. It asks whether to spread what is
  already there over every disk now, which takes hours on a large pool.
- **Forget** (`ame system raid forget NAME`) stops mounting a pool and leaves its files on its disks.
  GNOME Disks' **Format** erases them when you want the disks back.

### The system's own disks

The installer makes no pools: install on one disk, and make a pool of the others afterwards. Two disks
chosen in the installer hold the system with one copy of each file, so either one failing loses
everything. **Protect the system's disks** (`ame system raid mirror`) keeps a copy of each file on
each disk instead, and erases nothing. The machine still starts only from its first disk, which has
the boot files, and may need help to start at all with a disk dead, but every file stays readable on
the disk that is left, from the live USB stick.

## Printers and scanners

Most printers are found on the network and just work, without a driver. Drivers for HP printers and
many Brother and older laser printers are included for the rest. Add a printer in
**Settings → Printers**.

## Phones

- **Android:** GSConnect links the phone to the desktop: notifications, file transfer, a shared
  clipboard and texts. Install KDE Connect on the phone and pair them from the quick settings.
- **iPhone:** plug it in and trust the computer on the phone; its photos and files show up in Files.

## Keyboards, mice and security keys

- **Gaming mice:** the service that configures them is included; install **Piper** from Bazaar to
  change buttons, lighting and resolution.
- **Remapping keys:** `ame security input-remapper` turns on Input Remapper ([Security](security.md#key-remapping)
  explains why it starts off).
- **FIDO2 security keys** can replace your password: [Security](security.md#security-keys).

## Drawing tablets

Most drawing tablets work as soon as they are plugged in, and GNOME's Settings has a page for one once
it is. For a tablet the kernel's own drivers handle badly, which is often the case for Huion, XP-Pen
and Gaomon models, or to set every tablet up the same way, use OpenTabletDriver:

```bash
ame apps opentabletdriver on
```

It installs OpenTabletDriver from Flathub, copies its rules for which devices it may read into `/etc`,
from the release Amethystora pins and checked against that release's checksum, and starts its driver
at each login. It also turns off the kernel's own tablet drivers, which would take the tablet first,
so restart if the tablet was plugged in. It moves the pointer through `/dev/uinput`, which the image keeps
from apps, so it gives that back to whoever sits at the machine ([Switches](security.md#switches), `ame
security virtual-input`). Set the pen's pressure, its buttons and the part of the screen
the tablet covers in **OpenTabletDriver**, in the app grid. `ame apps opentabletdriver off` takes it all
away again, and the kernel's drivers come back after a restart. The **Drawing tablets** switch on
[Control](control.md)'s **Apps** page does either in a terminal.

## Laptops

Framework laptops get their known fixes at first boot, for suspend, audio and the keyboard, and the
13-inch model a text size to suit its screen. Keep the firmware current on every machine: **Updates**
shows what there is, or in a terminal:

```bash
fwupdmgr get-updates
fwupdmgr update
```

[Firmware](updates.md#firmware) says more.

## Cameras

Virtual cameras (OBS's, for instance) work without anything to install, through the loopback
module built into the image.
