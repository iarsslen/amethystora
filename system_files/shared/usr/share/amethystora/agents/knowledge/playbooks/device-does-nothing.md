# A device does nothing

## Symptom

A USB device, keyboard, controller, tablet, webcam or USB stick is plugged in and nothing happens; or a
program cannot reach it: a keyboard configurator, Steam Input, a tablet driver, a key remapper.

## Look

- `state security-settings`, with a switch's name as filter (`virtual-input`, `blocked-modules`,
  `block-webcam`, `block-automount`, `block-bluetooth`).
- `logs` identifier `kernel`, grep `not authorized for usage` (USB protection refused it), then grep `usb`.
- `state app-permissions` with the app's id, for a Flatpak app.
- `lsusb`, `journalctl -k -b -g usb --no-pager`
- `systemctl is-enabled usbguard.service input-remapper.service`
- `getfacl /dev/uinput`, `udevadm info /dev/hidrawN` (the vendor ID), `getfacl /dev/hidrawN`
- `modprobe -n -v MODULE` (a blocked one prints `install /usr/bin/false`)

## Causes on Amethystora

1. **USB protection refuses it** (only after the user turned on `ame security usb`). USBGuard blocks what
   was not plugged in at setup. Tell: `usbguard.service` enabled, the kernel logs "Device is not authorized
   for usage", `ame security events` says USB protection blocked a device.
2. **`/dev/uinput` is root's** (as shipped). Steam Input, OpenTabletDriver and key remappers make virtual
   devices through it, and a virtual keyboard types into any window. Tell: no user in
   `getfacl /dev/uinput`; `virtual-input` on.
3. **A Flatpak app is refused the input devices** by `/etc/flatpak/overrides/global`; an app with
   `--device=all`, such as Steam, keeps its devices. Tell: `state app-permissions`.
4. **Raw HID goes to the person at the seat only.** A keyboard's hidraw device carries every key typed, so
   the image's rules (`/usr/lib/udev/rules.d/92-viia.rules`, `/usr/lib/udev/rules.d/50-zsa.rules`, the
   controllers' `71-…-gdu.rules`) use `TAG+="uaccess"`, and other keyboards get none. Tell: VIA, Vial or
   Oryx reach Keychron, Lemokey, ZSA and Vial keyboards at the machine, not over SSH, not another make.
5. **A blocked kernel module**: FireWire, CAN, floppy, parallel ports, old protocols and filesystems (HFS).
   Tell: `modprobe -n -v MODULE`; the list is `/usr/lib/modprobe.d/60-amethystora-hardening.conf`.
6. **A stricter setting the user turned on**: `block-webcam` (no webcam), `block-automount` (a stick
   mounts only when opened in Files), `block-bluetooth` (no Bluetooth mice or keyboards). Tell:
   `state security-settings`; the report's `stricter` check names them.
7. **Key remapping is off** (as shipped): Input Remapper opens, but no mapping applies. Tell:
   `input-remapper.service` disabled.

## Fix

### 1. USB protection

The user runs `ame security usb allow` (root) and picks the device; it stays allowed. Never run it
yourself.

### 2. Virtual input

- Controllers: `change` `gaming` `on` (in a terminal), or `ame apps gaming`: Steam from Flathub, and
  `/dev/uinput` given back.
- Drawing tablets: `change` `opentabletdriver` `on`, or `ame apps opentabletdriver on` (root); (restart)
  if the tablet was plugged in.
- Anything else: the user runs `ame security virtual-input off` (root). Whoever sits at the machine, and
  every app that may reach all of `/dev`, browsers included, can then type into any window.

### 3. A Flatpak app

Say that it lets the app read every keyboard, then `flatpak override --user --device=input APP`, and start
the app again.

### 4. Raw HID

Use the device at the machine. For another keyboard, the user gives it to the seat (root), with the vendor
ID from `lsusb`, then plugs it in again:
`echo 'KERNEL=="hidraw*", ATTRS{idVendor}=="1234", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/70-keyboard.rules`.
Never `MODE="0666"`.

### 5. Blocked module

The user runs `ame security blocked-modules off` (root): every module on the list can load again.

### 6. Stricter settings

The user runs `ame security block-webcam off` (root) and plugs the webcam in again ((restart) if it was in
use), `ame security block-automount off` (root), or `ame security block-bluetooth off` (root). A stick also
mounts by opening it in Files.

### 7. Key remapping

The user runs `ame security input-remapper on` (root): a root service that reads every key typed.

## Verify

- `state security-settings` with the switch's name.
- `getfacl /dev/uinput` names the user.
- `logs` identifier `kernel`, grep `not authorized for usage`: nothing new after plugging in again.
- The device works once plugged in again.

## Undo

- An allowed USB device: `sudo usbguard list-rules`, then `sudo usbguard remove-rule ID` (root).
- Virtual input: `ame security virtual-input on` (root) (restart). `ame apps opentabletdriver off` and
  `ame apps gaming off` put it back unless the other still needs it; the second uninstalls Steam with its
  games: ask first.
- A Flatpak app: `flatpak override --user --nodevice=input APP`.
- The HID rule: `sudo rm /etc/udev/rules.d/70-keyboard.rules` (root), then plug the device in again.
- Each `ame security` switch above: the same command with `on`; key remapping with `off`.
