# No sound, or sound from the wrong place

## Symptom

Nothing plays; sound comes out of the wrong device (the laptop's speakers instead of headphones, a monitor
over HDMI instead of the speakers); Bluetooth headphones connect but sound like a phone call, or play
nothing; the microphone is missing; or one app is silent while the others play.

## Look

- `state units` filter `wireplumber.service`, then `pipewire.service` and `pipewire-pulse.service`
  (user units: each should be active).
- `logs` user_unit `wireplumber.service`; `logs` identifier `kernel`, grep `snd|sof|firmware|usb-audio`.
- `state crashes`: a crashed pipewire or wireplumber.
- `state security-settings` filter `block-bluetooth`, then `blocked-modules`.

Then:

- `wpctl status`: Sinks (outputs) and Sources (inputs); `*` marks the default
- `wpctl inspect @DEFAULT_AUDIO_SINK@`, `wpctl get-volume @DEFAULT_AUDIO_SINK@`
- `cat /proc/asound/cards`: the sound cards the kernel found
- `journalctl -k -b -g 'snd|sof|firmware' --no-pager`
- `rpm -q pipewire-codec-aptx`, and `rpm-ostree db diff` when it began with an update

## Causes on Amethystora

1. **Bluetooth is blocked.** With `ame security block-bluetooth` on (off as the image ships), Bluetooth
   cannot load and headphones never appear. Tell: the filter above says on. Pairing itself:
   `playbook/bluetooth`.
2. **The headset profile.** A headset switched to its headset profile (HSP/HFP), for the microphone,
   sounds like a phone call; music wants High Fidelity Playback (A2DP). Tell: the headset's
   configuration in Settings, Sound names the headset profile.
3. **A codec the image leaves out.** The image takes out negativo17's `pipewire-libs-extra`, whose LC3plus
   plugin may not be redistributed. Fedora's PipeWire carries SBC, AAC, LDAC, LC3 and Opus, and RPM
   Fusion's `pipewire-codec-aptx` adds aptX. A headset that offered LC3plus elsewhere uses another codec
   here. Tell: `wpctl inspect` on the headset's node, `api.bluez5.codec`.
4. **A FireWire sound card.** The image keeps FireWire from loading
   (`/usr/lib/modprobe.d/61-amethystora-firewire.conf`), since it gives a device direct access to memory.
   Tell: `modprobe -n -v firewire_ohci` prints `install /usr/bin/false`.
5. **The wrong default.** GNOME moves to the device plugged in last: a monitor, a dock or a USB headset
   takes over. Tell: the `*` in `wpctl status`.
6. **Muted, or at zero.** Tell: `wpctl get-volume` says `[MUTED]` or `0.00`.
7. **One app silent.** An override of the user's took its sound (`--nosocket=pulseaudio`); the image's
   own override leaves sound alone. Tell: `flatpak info --show-permissions APP` lacks `pulseaudio`.
   Sound goes to the person at the machine: a program started over SSH or in another account's session
   plays nothing.
8. **No card at all.** `/proc/asound/cards` is empty, and the kernel log names missing firmware (often SOF
   on recent Intel laptops) or a driver error. Began with an update: compare with `rpm-ostree db diff`.
9. **PipeWire stuck.** It crashed, or WirePlumber's saved state in `~/.local/state/wireplumber` keeps
   choosing a device that is gone.

## Fix

### Bluetooth blocked

The user runs `ame security block-bluetooth off` (root): Bluetooth comes back at once, and with it a radio
anyone in range can reach.

### Headset profile

Choose High Fidelity Playback as the headset's configuration in Settings, Sound. The microphone of most
Bluetooth headsets works only in the headset profile, so a call switches it back.

### Codec

Nothing to install: pick the codec the headset offers among those above. Never add negativo17's packages.

### FireWire

The user runs `ame security firewire off` (root): FireWire loads at once, and with it its devices' direct
access to memory. `ame security firewire on` blocks it again.

### Default and volume

`wpctl set-default ID` (a sink's id from `wpctl status`), `wpctl set-mute @DEFAULT_AUDIO_SINK@ 0`,
`wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5`.

### One app

With a yes, `flatpak override --user --socket=pulseaudio APP`, then start the app again.

### No card

When an update caused it, the boot menu's second entry, then `bootc rollback` (root) (restart), and
`ame report` for the issue. Otherwise report the kernel lines upstream.

### PipeWire stuck

`systemctl --user restart wireplumber.service pipewire.service pipewire-pulse.service`. If it comes back
wrong, move `~/.local/state/wireplumber` aside to `wireplumber.bak` beside it, and restart them again.

## Verify

- `wpctl status`: the right sink has the `*`; `wpctl get-volume @DEFAULT_AUDIO_SINK@` is not muted.
- Settings, Sound: the output's **Test** plays from each speaker.
- `state units` filter `wireplumber.service`: active.

## Undo

- `wpctl set-default` with the previous sink's id; the previous configuration in Settings, Sound.
- `flatpak override --user --nosocket=pulseaudio APP`.
- Move `wireplumber.bak` back to `~/.local/state/wireplumber`, then restart the three units.
- `ame security block-bluetooth on`, `ame security blocked-modules on` (root): these turn protection on,
  so the agent may run them when the user asks.
