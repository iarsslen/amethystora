# GNOME's own settings, from the shell

Written for AI agents. Amethystora's own settings go through `state settings` and `change`; GNOME's go through
these commands in the agent's own shell, as the user. Read before writing, change one thing, read it back;
`gsettings reset SCHEMA KEY` undoes a change.

## Appearance and text

- Dark style: `gsettings set org.gnome.desktop.interface color-scheme prefer-dark` (or `default`). On
  Amethystora the theme decides it: `amethystora-theme toggle` switches to the theme's light or dark pair,
  which is better than setting the key alone.
- Text size: `gsettings set org.gnome.desktop.interface text-scaling-factor 1.25`.
- Accent colour: `gsettings set org.gnome.desktop.interface accent-color purple` (a theme switch sets it again).
- Icons: `ame desktop icons glass|neon|duotone|theme`, not `gsettings set ... icon-theme`, which the next theme
  switch writes over.
- Animations: `gsettings set org.gnome.desktop.interface enable-animations false`; the theme transitions stop
  with them.

## Night light and the screen

- Night light: `gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true`, and its
  warmth `night-light-temperature` (uint32, for example `uint32 3500`).
- Screen blank after idle: `gsettings set org.gnome.desktop.session idle-delay uint32 600` (seconds; 0 never).
- Displays, scaling and refresh rate are GNOME Settings' (`gnome-control-center display`): nothing on the
  command line sets them reliably on Wayland.

## Notifications and Do Not Disturb

- Do Not Disturb: `gsettings set org.gnome.desktop.notifications show-banners false` (true to end it).

## Power

- Power profile: `powerprofilesctl list`, `powerprofilesctl set power-saver|balanced|performance`.
- Suspend when idle on mains power: `gsettings set org.gnome.settings-daemon.plugins.power
  sleep-inactive-ac-type nothing` (or `suspend`).

## Keyboard and input

- Layouts: `gsettings get org.gnome.desktop.input-sources sources`, and to set: `gsettings set
  org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'fr')]"`.
- Keybindings: `/usr/share/amethystora/keybindings.md` lists the image's; check it before binding a key.
  Custom ones live under `/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/` (the image uses
  `custom20` and up).
- Touchpad: `gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true`, `natural-scroll`.

## Radios and the network

- Wi-Fi on or off: `nmcli radio wifi on|off`; networks: `nmcli device wifi list`, `nmcli connection show`.
- Connect: `nmcli device wifi connect SSID --ask` asks the password in a terminal: leave it to the user.
- Airplane mode and Bluetooth power: `rfkill list`, `rfkill unblock bluetooth`; Bluetooth devices:
  `bluetoothctl devices`, pairing is the user's (it shows a code).

## Sound

- Outputs and inputs: `wpctl status`; the default: `wpctl set-default ID`; volume: `wpctl set-volume
  @DEFAULT_AUDIO_SINK@ 50%`; mute: `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`.

## The dock and windows

- The dock's apps: `gsettings get org.gnome.shell favorite-apps`.
- Windows tile (Amethystora UI's tiling module) unless the user chose classic windows: `ame desktop layout
  tiling|classic` (the `layout` entry of `state settings`), which sets `enabled` in
  `org.gnome.shell.extensions.amethystora-ui.tiling`. Its keys are in `...tiling.keybindings`; a combination
  it shares with a GNOME shortcut is taken from it while the tiling runs and given back when it is off
  (four keys' lists are changed in dconf, and what was taken is in `~/.local/state/amethystora/tiling.json`, with a
  copy `tiling.json.bak` beside it for when the file cannot be read; never edit either by hand).

## The phone

- The phone link is Amethystora's own program, `amethystora-connect` (a user service), speaking KDE Connect's
  protocol, so the KDE Connect app on an Android phone pairs with it. It starts off: `ame desktop phone on|off`
  (the `phone` entry of `state settings`), and it is open only on the networks named home.
- Pairing is the user's: the phone's name and a verification key are on both screens and the user accepts.
  Never pair, accept or unpair for them.
- The clipboard is shared only if chosen, one way at a time: `ame desktop phone clipboard send|receive on|off`.
  Leave these to the user: receiving lets a phone put text where any program can paste it.
- Files from a phone arrive in `~/Downloads/Phone/NAME`. The phone icon in the top bar is Amethystora UI's
  `connect` module, and shows only while a paired phone is connected.

## Copying text out of a picture on the screen

- The reading is Gradia's: `Print`, drag an area, then **Extract Text** or `Ctrl+E` in GNOME's screenshot UI
  (the button is Amethystora UI's screenshot module, in `amethystora-ui@iarsslen.github.io`, and needs the
  Flatpak `be.alexandervanhee.gradia`). The text is copied at once. It works on an area only; the
  button is off in window, screen and recording modes.
- Offline after one prompted download: the first use opens Gradia's "OCR Language Models" page, and the
  chosen language's `tessdata_best` file comes from GitHub into
  `~/.var/app/be.alexandervanhee.gradia/data/tessdata`. Look there to see which languages are installed.
- The capture is kept in the screenshot folder like any screenshot. There is no `tesseract` command in the
  image and no `ame` command for this; do not install one for the user.
- Button missing: `flatpak info be.alexandervanhee.gradia` and `gnome-extensions info
  amethystora-ui@iarsslen.github.io` (Extension Manager turns it back on; an image update does too).
