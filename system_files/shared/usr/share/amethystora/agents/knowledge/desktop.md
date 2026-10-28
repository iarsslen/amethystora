# GNOME's own settings, from the shell

Written for AI agents. Amethystora's own settings go through `state settings` and `change`; GNOME's go through
these commands in the agent's own shell, as the user. Read before writing, change one thing, read it back;
`gsettings reset SCHEMA KEY` undoes a change.

## Appearance and text

- Dark style: `gsettings set org.gnome.desktop.interface color-scheme prefer-dark` (or `default`). On
  Amethystora the theme decides it: `amethystora-theme toggle` switches to the theme's light or dark pair,
  which is better than setting the key alone.
- Text size: `gsettings set org.gnome.desktop.interface text-scaling-factor 1.25`.
- Accent colour: the theme's own (the apps' palette layer, `~/.config/gtk-4.0/gtk.css`, written by a theme switch);
  `gsettings set org.gnome.desktop.interface accent-color purple` only moves GNOME's nearest of nine, which the shell
  and the apps no longer take.
- Icons: `ame desktop icons glass|glass-light|neon|neon-light|duotone|line|clay|muted|theme`, not
  `gsettings set ... icon-theme`, which the next theme switch writes over.
- Font: `ame desktop font "<family>"|theme`, not `gsettings set ... font-name`, which the next theme switch writes over.
  The monospace font (terminal, code, Text Editor) is `ame desktop mono-font "<family>"|theme`, not
  `monospace-font-name`.
- The shape of the top bar, menus, notifications, dialogs, buttons and windows: `ame desktop style
  islands|floating|hairline|capsule|terminal|segments|neon|theme`.
- Animations: `gsettings set org.gnome.desktop.interface enable-animations false`; the theme transitions stop
  with them.
- The glass behind the top bar, dock, menus and notifications: `ame desktop glass frost|prism|clear`. Comfort:
  `ame desktop comfort reduce-transparency|reduce-motion|increase-contrast on|off` (the glass solid; GNOME's
  Reduced Motion; GNOME's High Contrast), and `ame desktop comfort` alone shows all of them and the power saver.
- Quick settings' tiles are moved and hidden by holding one (arrange mode), kept in
  `org.gnome.shell.extensions.amethystora-ui.quick` `tile-order` and `tile-hidden` (ids such as `wifi`, `dnd`,
  `battery`, `theme`): `ame desktop quick-settings reset` puts every tile back, `ame desktop quick-settings theme
  on|off` shows or hides the theme swatches. The battery's 80% switch is UPower's charge limit, nothing else.

## Night light and the screen

- Night light: `gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true`, and its
  warmth `night-light-temperature` (uint32, for example `uint32 3500`).
- Screen blank after idle: `gsettings set org.gnome.desktop.session idle-delay uint32 600` (seconds; 0 never).
- Displays, scaling and refresh rate are GNOME Settings' (`gnome-control-center display`): nothing on the
  command line sets them reliably on Wayland.

## Notifications and Do Not Disturb

- Do Not Disturb: `gsettings set org.gnome.desktop.notifications show-banners false` (true to end it).
- Rest reminders are GNOME's own (`org.gnome.desktop.break-reminders`): `ame desktop breaks
  on|eyesight|movement|both|off`; their times are in Settings, Wellbeing.

## The top bar and the calendar

- With two screens or more every other screen has a top bar with its workspaces and the clock:
  `ame desktop top-bar screens on|off`. Pushing the pointer against the top edge over a fullscreen window brings
  the bar down: `ame desktop top-bar peek on|off`.
- The calendar menu lists today's and overdue tasks from Notes while Notes is open and unlocked:
  `ame desktop today tasks on|off`. Notes says them on the session bus (`org.amethystora.Notes`,
  `/org/amethystora/Notes/Today`) to GNOME Shell alone.
- The weather beside the clock sends the place chosen in Weather to a weather service and is off until chosen:
  `ame desktop weather on|off`. Never turn it on without the user's word.

## Power

- Power profile: the image has no `powerprofilesctl` (tuned-ppd answers power-profiles-daemon's interface).
  Read it with `busctl --system get-property org.freedesktop.UPower.PowerProfiles
  /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile`, set it with
  `busctl --system set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles
  org.freedesktop.UPower.PowerProfiles ActiveProfile s power-saver` (or `balanced`, `performance`), or in the
  quick settings' power menu. While it is `power-saver` the glass is solid and animations take half their time.
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
  `org.gnome.shell.extensions.amethystora-ui.tiling`. Its other settings (`window-gap`, the margins,
  `cycle-width-steps`, `open-window-position`, `animation-time`, the edge and gesture keys, the window rules in
  `winprops`) are keys of the same schema, applied at once; `ame desktop tiling-settings` opens their window.
  With two screens or more each screen shows a workspace of its own, and the one under the pointer is GNOME's
  active workspace; the others are drawn from live pictures of their windows. Meanwhile the tiling sets
  `org.gnome.mutter workspaces-only-on-primary` false, putting the account's value back with one screen or classic
  windows. `dynamic-workspaces` stays the account's: with it on, GNOME removes no workspace a screen shows and keeps
  one more than there are screens. The image's six fixed workspaces are under `[org.gnome.mutter:GNOME]` in
  `zz1-amethystora-modifications.gschema.override`, since GNOME Shell sets that key for the GNOME desktop alone. Read
  a session's value with `XDG_CURRENT_DESKTOP=GNOME gsettings get ...`.
  Its keys are in `...tiling.keybindings`; a combination
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
