# Bluetooth will not pair, or a device is not seen

## Symptom

No Bluetooth in the quick settings, or it will not turn on; a mouse, keyboard or headset never shows in
the list; a phone or another computer cannot find this machine; pairing fails or times out; or a paired
device will not connect again.

## Look

- `state security-settings` filter `block-bluetooth`, then `bluetooth-privacy`: the image's switches, and
  whether they differ from how it ships.
- `state units` filter `bluetooth.service`; `logs` unit `bluetooth.service`; `logs` identifier `kernel`,
  grep `Bluetooth|btusb|hci|firmware`.

Then:

- `rfkill list bluetooth`, `systemctl status bluetooth.service`
- `bluetoothctl show` (Powered, Discoverable, Pairable), `bluetoothctl devices`, `bluetoothctl info MAC`
- `grep -E '^(Privacy|DiscoverableTimeout|PairableTimeout)' /etc/bluetooth/main.conf`
- `systemctl is-active usbguard.service`, for a USB adapter

## Causes on Amethystora

1. **Bluetooth is blocked.** With `ame security block-bluetooth` on (off as the image ships),
   `/etc/modprobe.d/61-amethystora-no-bluetooth.conf` keeps `bluetooth` and `btusb` from loading,
   `bluetooth.service` is disabled and the radio blocked. Tell: the filter above says on.
2. **Visible and pairable for 30 seconds only.** The image sets `DiscoverableTimeout = 30` and
   `PairableTimeout = 30` in `/etc/bluetooth/main.conf` (BlueZ reads no drop-ins): once Settings'
   Bluetooth page makes the machine visible, it stops being visible, and accepting pairing, 30 seconds
   later. A device that looks for this machine after that finds nothing, or is refused. Tell:
   `bluetoothctl show` says `Discoverable: no`.
3. **An address that changes.** `Privacy = network` in the same file gives the machine a random address.
   Bonded devices follow it; an old or unusual one may pair, then fail to reconnect or to find it again.
4. **The radio is off.** Airplane mode, a switch or a key: `rfkill list bluetooth` says Soft or Hard
   blocked.
5. **A USB adapter refused.** With `ame security usb` on (USBGuard, off as the image ships), an adapter
   plugged in after its setup is blocked. Tell: `usbguard.service` active; the kernel log says the device
   is not authorized.
6. **A web page.** With `ame security browser` on, browsers keep web pages from Bluetooth devices: a site
   that sets up a device cannot see it.
7. **The device side.** Still paired with another computer or phone, not in pairing mode, or a stale
   pairing here: `bluetoothctl info MAC` says Paired but not Connected.
8. **The driver or its firmware.** The kernel log names `btusb` or firmware that did not load. Began with
   an update: `rpm-ostree db diff`.

A headset that plays badly: `playbook/no-sound`. The phone link pairs a phone over the network:
`playbook/wifi-dns`.

## Fix

### Blocked

The user runs `ame security block-bluetooth off` (root): Bluetooth comes back at once, and with it a radio
anyone in range can reach.

### 30 seconds

Pair from this machine's side, which needs no visibility: put the device in pairing mode, search in
Settings, Bluetooth, or `bluetoothctl --timeout 20 scan on`, then `bluetoothctl pair MAC`,
`bluetoothctl trust MAC` and `bluetoothctl connect MAC`. For a device that has to find this machine, keep
Settings' Bluetooth page open and start on the device within 30 seconds; `bluetoothctl discoverable on`
and `bluetoothctl pairable on` give 30 more. For good, the user runs `ame security bluetooth-privacy off`
(root): BlueZ's defaults, a fixed address, visible until turned off.

### Changing address

The user runs `ame security bluetooth-privacy off` (root); then `bluetoothctl remove MAC` and pair again.

### Radio off

Airplane mode off, or `rfkill unblock bluetooth`, which the person at the machine may run. A hard block
needs the switch or key.

### USB adapter

The user runs `ame security usb allow` (root) and picks the adapter. Allowing a device is what USB
protection guards against: never run it for them.

### Web page

The user decides on browser protection in `ame security browser`, or uses the maker's own app.

### Device side

`bluetoothctl remove MAC`, put the device in pairing mode, and pair again from this machine.

### Driver

`systemctl restart bluetooth.service` (root). Broken by an update: the boot menu's second entry, then
`bootc rollback` (root) (restart), and `ame report`.

## Verify

- `bluetoothctl show`: `Powered: yes`; `bluetoothctl info MAC`: `Paired: yes`, `Connected: yes`.
- `state security-settings` filter `bluetooth-privacy` (or `block-bluetooth`): what the user chose.
- `rfkill list bluetooth`: not blocked.

## Undo

- `ame security bluetooth-privacy on`, `ame security block-bluetooth on` (root) turn protection on: the
  agent may run them when the user asks. Bluetooth restarts, and devices reconnect.
- `bluetoothctl remove MAC` forgets a device; `rfkill block bluetooth` turns the radio off.
- An allowed adapter: `usbguard list-rules`, then `usbguard remove-rule ID` (root).
