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
ujust enroll-secure-boot-key
```

Restart, and a blue screen appears before the system starts: the MOK manager. Choose
**Enroll MOK**, then **Continue**, then **Yes**, and type the password `amethystora`. The screen uses
a US (QWERTY) keyboard layout whatever your own is, which matters if your keyboard puts the letters
elsewhere. `ujust security-status` tells you whether the keys are enrolled.

If Secure Boot is off, a notification says so once. Turn it on in the machine's firmware settings,
then run the recipe above.

## Graphics

- **Intel and AMD** work out of the box. The developer image adds ROCm for GPU compute on AMD.
- **NVIDIA** needs the `-nvidia-open` images, which carry NVIDIA's open kernel driver ([Installing](installing.md#pick-an-image)).
  Builds of those images are paused at the moment. The NVIDIA driver is built for the machine and
  signed with its own key, so the NVIDIA images do not use kernel lockdown.

## Docks and displays

- **DisplayLink docks** work with the driver built into the image. With Secure Boot on, the dock
  stays dark until the key above is enrolled.
- **External monitor brightness** can be set from the command line with `ddcutil`, for monitors
  that support it.

## Disks

- **Encryption** is chosen when installing and cannot be added afterwards. Once it is on,
  `ujust setup-disk-unlock` lets the TPM unlock the disk at boot instead of you typing the
  passphrase ([Security](security.md#unlock-the-disk-with-the-tpm)).
- **ZFS** is available on the `stable` stream.

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
- **Remapping keys:** `ujust setup-input-remapper` turns on Input Remapper ([Security](security.md#key-remapping)
  explains why it starts off).
- **FIDO2 security keys** can replace your password: [Security](security.md#security-keys).

## Laptops

Framework laptops get their known fixes at first boot, for suspend, audio and the keyboard, and the
13-inch model a text size to suit its screen. Keep the firmware current on every machine:

```bash
fwupdmgr get-updates
fwupdmgr update
```

## Cameras

Virtual cameras (OBS's, for instance) work without anything to install, through the loopback
module built into the image.
