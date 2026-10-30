# Desktop shell

Walk each item on the real machine as a person would: look, click, press the keys. Unless an item says otherwise the
machine is in its shipped state (tiling layout, the style the theme suggests, Prism glass, every switch at its
default). Where an item changes a setting, put it back with the command in its flags before moving on. The manual
pages named are in `/usr/share/amethystora/manual/` (or `Super+F1`); `desktop.md` is "Getting around", `themes.md`
"Themes".

## Top bar

- [ ] D-TOPBAR-01 Logo at the far left. How: look at the top bar's left end. Expect: the Amethystora gem, crisp at bar height, then the six workspaces; no Activities button anywhere on the bar.
- [ ] D-TOPBAR-02 Logo middle click. How: middle-click the logo. Expect: the overview opens; a second middle click closes it.
- [ ] D-TOPBAR-03 Six workspaces row. How: look right of the logo, then press `Super+3`. Expect: exactly six workspace buttons, the current one highlighted; the highlight follows and no workspace popup shows in the middle of the screen.
- [ ] D-TOPBAR-04 Click another workspace. How: click workspace 3's button. Expect: you go to workspace 3.
- [ ] D-TOPBAR-05 Click the current workspace. How: click the highlighted workspace, then again. Expect: the overview shows, then hides.
- [ ] D-TOPBAR-06 Click an empty workspace. How: click a workspace with no windows. Expect: it goes there and the overview opens, ready to start something.
- [ ] D-TOPBAR-07 Scroll on the bar. How: scroll the mouse wheel, or two fingers on a touchpad, anywhere over the top bar. Expect: next / previous workspace, one per notch, no skipping or double steps.
- [ ] D-TOPBAR-08 Drag a workspace along the row. How: drag workspace 2's button onto place 4. Expect: the workspace moves there with its windows and its name.
- [ ] D-TOPBAR-09 Drop a window on a workspace. How: open the overview (`Super`), drag a window onto workspace 5's button in the top bar. Expect: the window moves to workspace 5.
- [ ] D-TOPBAR-10 Automatic workspace names. How: open two terminal windows on an unnamed workspace. Expect: the button shows its number and then the app's name (the app with most windows) in lighter type.
- [ ] D-TOPBAR-11 Automatic names off. How: `ame desktop space-names off`. Expect: unnamed workspaces show numbers only. [changes setting: put back with `ame desktop space-names on`]
- [ ] D-TOPBAR-12 Rename a workspace. How: right-click workspace 2, type a name. Expect: the name replaces the app's at once; **Use the app's name** in the same menu goes back to the automatic one.
- [ ] D-TOPBAR-13 Clock in the middle. How: look at the middle of the bar, then click it. Expect: the time, centred; the click (or `Super+V`) opens notifications, the calendar and Today.
- [ ] D-TOPBAR-14 Meters. How: look left of the system menu. Expect: CPU, memory and network meters in the theme's colours, updating about every 5 s.
- [ ] D-TOPBAR-15 CPU meter menu. How: click the CPU meter. Expect: each processor over the last few minutes, the busiest processes, and a button that opens Mission Center.
- [ ] D-TOPBAR-16 Memory meter menu. How: click the memory meter. Expect: memory over the last few minutes, the busiest processes, the Mission Center button.
- [ ] D-TOPBAR-17 Network meter menu. How: click the network meter during a download, then start a VPN or a container's download. Expect: traffic over the last minutes; only Wi-Fi and wired count, so VPN or container traffic is not counted twice.
- [ ] D-TOPBAR-18 Tray icon. How: start an app that keeps a tray icon. Expect: its icon between the meters and the system menu, sized like the bar's other icons.
- [ ] D-TOPBAR-19 Tray clicks. How: right-click, double-click, then middle-click a tray icon. Expect: right-click shows the app's menu in the shell's menu look (items work); double-click opens the app; middle-click runs its second action.
- [ ] D-TOPBAR-20 Tray for a Flatpak. How: run a Flatpak app with a tray icon. Expect: its icon shows only if it may talk to `org.kde.StatusNotifierWatcher` (`flatpak info --show-permissions APP`); an X11-only app's icon only while X11 apps are allowed.
- [ ] D-TOPBAR-21 Bar over fullscreen. How: play a video fullscreen, push the pointer against the top edge, move away. Expect: the bar comes down over the video and goes when you move away.
- [ ] D-TOPBAR-22 Peek off. How: `ame desktop top-bar peek off`, repeat. Expect: the bar no longer comes down. [changes setting: put back with `ame desktop top-bar peek on`]
- [ ] D-TOPBAR-23 Hide the bar on one workspace. How: `Super+Ctrl+B` on workspace 1, go to workspace 2 and back, press it again. Expect: the bar hides on workspace 1 only and comes back with the second press.
- [ ] D-TOPBAR-24 Busy-app chip. How: hold the processor at 70 % or more for two minutes (e.g. a heavy page in Firefox, or `stress-ng --cpu 0` if installed). Expect: a chip beside the meters says e.g. **Firefox is busy**; its menu has **Show it**, **Not now**, **Quit Firefox** (no Quit for a terminal); the chip goes when the processor calms; not again for that app within the hour; never while a fullscreen window is in front.
- [ ] D-TOPBAR-25 Busy-app chip off. How: `ame desktop power busy off`, repeat the load. Expect: no chip. [changes setting: put back with `ame desktop power busy on`]
- [ ] D-TOPBAR-26 Volume and brightness pill. How: press the volume keys, the brightness keys and Caps Lock. Expect: a slim pill just under the top bar shows each (not GNOME's card low in the middle); each volume step plays a soft click.
- [ ] D-TOPBAR-27 Top bar on every screen. How: look at the second screen. Expect: a top bar as tall and as round as the main one, the workspaces (the one that screen shows lit) and the clock; no tray, quick settings or meters there. [needs: two screens]
- [ ] D-TOPBAR-28 Other screens' bars off. How: `ame desktop top-bar screens off`. Expect: the other screens lose their bar at once. [changes setting: put back with `ame desktop top-bar screens on`] [needs: two screens]
- [ ] D-TOPBAR-29 Tooltips and menus on the bar. How: rest the pointer on each bar item, open each menu. Expect: menus open under their button, inside the screen, in the current style's shape; text readable on the glass.

## Quick settings

- [ ] D-QUICK-01 Layout. How: click the system menu at the right end of the bar. Expect: tiles two to a row, each saying what it knows (Wi-Fi network and strength, earbuds and their battery, the power mode); then the sliders, the apps playing sound, a swatch for every theme, and Screenshot, Lock, Settings and Power.
- [ ] D-QUICK-02 Tile click and arrow. How: click the Wi-Fi tile, then its arrow. Expect: the click switches Wi-Fi; the arrow opens its menu inside quick settings.
- [ ] D-QUICK-03 Arrange by holding. How: hold a tile for half a second (or `Menu` on it), drag it to another place, close and reopen. Expect: tiles shrink a little and get a round button at a corner; the moved tile stays in its new place.
- [ ] D-QUICK-04 Hide a tile. How: in arranging mode press a tile's round button, then the same button in the **Hidden** row. Expect: the tile goes to a Hidden row and comes back. [changes setting: put back with `ame desktop quick-settings reset`]
- [ ] D-QUICK-05 Arrange with the keyboard. How: in arranging mode, `Ctrl`+arrow on a tile, `Delete`, `Enter` on a hidden one, then `Esc`. Expect: moves, hides and restores as with the mouse; Done, `Esc` or closing the menu ends the mode. [changes setting: put back with `ame desktop quick-settings reset`]
- [ ] D-QUICK-06 Reset tiles. How: `ame desktop quick-settings reset`, and Control's **Quick settings tiles**. Expect: every tile back in its first place, none hidden.
- [ ] D-QUICK-07 Battery tile. How: open quick settings on a laptop. Expect: the first tile is the battery: how full, and when it runs out or is full. [needs: laptop]
- [ ] D-QUICK-08 Keep the battery at 80 %. How: the battery tile's menu. Expect: **Keep the battery at 80%** where the laptop can stop charging early (absent otherwise); kept across a restart. [needs: laptop] [changes setting: put back with the same switch]
- [ ] D-QUICK-09 Battery explained. How: open the battery tile's menu. Expect: when it will be empty or full, the watts now and since unplugged, the apps that used most since last plugged in or out (said to be an estimate), health and cycles when the battery reports them. [needs: laptop]
- [ ] D-QUICK-10 Battery details off. How: `ame desktop power battery off`, reopen. Expect: the details are gone. [changes setting: put back with `ame desktop power battery on`] [needs: laptop]
- [ ] D-QUICK-11 Each app's volume. How: play sound in two apps, open quick settings. Expect: under the volume slider each app has its own slider and mute button; the buttons beside "Playing now" send sound to another output.
- [ ] D-QUICK-12 Theme swatch. How: tap a swatch. Expect: the desktop and Amethystora's apps switch to that theme at once, revealed by the transition; other apps at their next start.
- [ ] D-QUICK-13 Hide the swatches. How: `ame desktop quick-settings theme off`, reopen; `on`. Expect: the swatches go, then come back. [changes setting: put back with `ame desktop quick-settings theme on`]
- [ ] D-QUICK-14 Phone tile. How: with a paired phone connected. Expect: a tile with the phone and its battery; a click opens the Phone app. [needs: phone]
- [ ] D-QUICK-15 Focus tile. How: open the **Focus** tile. Expect: chips Off, Work, Games and Sleep; it says what the profile does and when it ends: when turned off, after **1 hour**, or **tomorrow** (06:00).
- [ ] D-QUICK-16 Screenshot, Lock, Settings, Power buttons. How: click each at the foot of quick settings. Expect: each does its job (screenshot bar, lock, GNOME Settings, power menu), and the menu closes first.

## Today and the calendar menu

- [ ] D-TODAY-01 Calendar menu. How: click the clock, or `Super+V`. Expect: notifications, the calendar, events, world clocks, in the current style's shape; `Super+V` again closes it.
- [ ] D-TODAY-02 Today's tasks. How: in Notes add a task due today and one overdue, keep Notes open and unlocked, open the calendar menu. Expect: both listed on today's page only; a click opens Notes' tasks; with an encrypted Notes locked or closed, none.
- [ ] D-TODAY-03 Tasks off. How: `ame desktop today tasks off`. Expect: no tasks section. [changes setting: put back with `ame desktop today tasks on`]
- [ ] D-TODAY-04 Getting set. How: on an account younger than four weeks, open the calendar menu. Expect: **Getting set** first: Pick a look, automatic updates, a backup, a PIN for the disk (left out on an unencrypted disk), pairing the phone; each ticked by what the machine says, never by a click; a click opens the place that does it, the security line opens Security.
- [ ] D-TODAY-05 Getting set Hide. How: click **Hide**. Expect: it goes for good, as `ame desktop getting-set off` does. [changes setting: put back with `ame desktop getting-set on`]
- [ ] D-TODAY-06 Weather while off. How: with the weather off, open the calendar menu. Expect: its place says it is off and what it sends, with **Turn on…**, which asks once more before turning it on.
- [ ] D-TODAY-07 Weather on. How: `ame desktop weather on` (it says what it sends), with a place chosen in GNOME Weather. Expect: temperature and sky beside the clock and in the calendar menu; with no place in Weather, the menu offers to open it. [changes setting: put back with `ame desktop weather off`]
- [ ] D-TODAY-08 Timer buttons. How: at the end of the calendar's column, under **Start a timer**. Expect: buttons 1, 5, 10 and 25 minutes; a click starts it in the pill and closes nothing unexpected.
- [ ] D-TODAY-09 World clocks. How: add a world clock in GNOME Clocks, open the calendar menu. Expect: it is listed with its time.

## Live pill

- [ ] D-PILL-01 Pill at rest. How: with nothing happening, look at the clock. Expect: exactly GNOME's clock, no pill.
- [ ] D-PILL-02 Timer. How: start a 1-minute timer from the calendar menu. Expect: the pill counts down; its card adds a minute, pauses, cancels; the timer buttons add that many minutes; at the end a sound, a notification (even while quiet) and **Timer done**.
- [ ] D-PILL-03 Timer while locked. How: start a 1-minute timer, lock for two minutes, unlock. Expect: it rings as soon as you unlock.
- [ ] D-PILL-04 What is playing. How: play music or a video in an app that reports to the desktop. Expect: the cover, title and artist and a small pause button that works; the card has Back, Pause, Next and how far in; a paused player stays ten minutes.
- [ ] D-PILL-05 Recording. How: `Ctrl+Shift+Alt+R`, then **Stop** in the pill. Expect: how long it has run, and Stop ends it; the file is in Videos › Screencasts.
- [ ] D-PILL-06 Card and right-click. How: click the pill while something shows; then right-click it. Expect: the card with its buttons, whatever else is happening below, the date and time last (opens the calendar); the right-click always opens the calendar.
- [ ] D-PILL-07 Only one thing at a time. How: play music and start a timer. Expect: the pill shows the first by the manual's order (timer before what is playing); the card lists the other below.
- [ ] D-PILL-08 Update ready. How: with an update staged. Expect: **Ready · quick restart** or **Ready · restart**; **Restart now** opens System Updates; **Tonight** hides it until 20:00.
- [ ] D-PILL-09 Updated. How: first login after an update. Expect: **Updated** for a minute; a click shows what came and opens the Manual's What's new; a rollback or a new account says nothing.
- [ ] D-PILL-10 What's new off. How: `ame desktop whats-new off`. Expect: no **Updated** after the next update. [changes setting: put back with `ame desktop whats-new on`]
- [ ] D-PILL-11 Battery at 20 %. How: rest the pointer on the battery icon; then run a laptop down to 20 %. Expect: the tooltip gives time left or until full; at 20 % the pill turns amber and offers power saving, once, never turning it on itself. [needs: laptop]
- [ ] D-PILL-12 A call. How: get a call on the paired phone. Expect: who is calling and **Mute ringer**; the card adds **Reply with a text**. [needs: phone]
- [ ] D-PILL-13 A link from the phone. How: share a link from the phone. Expect: the address with **Open** and **Not now**, never opened by itself; **Open in browser**, **Copy**; a look-alike name shows as `xn--…`. [needs: phone]
- [ ] D-PILL-14 Something finished, waiting banners. How: after quiet ends with banners held. Expect: the pill says e.g. **2 waiting in the list**; a click opens the list.
- [ ] D-PILL-15 Pill off. How: `ame desktop pill off`, then `ame desktop pill on`. Expect: GNOME's clock alone, then the pill back. [changes setting: put back with `ame desktop pill on`]

## Privacy dots and the recording glow

- [ ] D-DOTS-01 Microphone. How: record sound (GNOME Sound Recorder or a call). Expect: a small pill in the top bar with an amber dot; GNOME's own microphone icon hidden.
- [ ] D-DOTS-02 Camera. How: open GNOME Snapshot. Expect: a green dot; the list names the app. [needs: camera]
- [ ] D-DOTS-03 Screen. How: record or share the screen. Expect: a red dot; the list has the screen with **Stop**, which stops it.
- [ ] D-DOTS-04 Location. How: let GNOME Maps find you. Expect: a violet dot; the list only says location is in use.
- [ ] D-DOTS-05 Order and list. How: microphone and screen at once, click the dots. Expect: always amber, green, red, violet; the list shows all four, each with its own icon.
- [ ] D-DOTS-06 Recording glow. How: `Ctrl+Shift+Alt+R`, then stop. Expect: a thin red glow round every screen's edge over everything, gone when it stops.
- [ ] D-DOTS-07 Dots off. How: `ame desktop pill dots off`. Expect: GNOME's own icons back, no dots pill. [changes setting: put back with `ame desktop pill dots on`]
- [ ] D-DOTS-08 Glow off. How: `ame desktop pill glow off`, record. Expect: no glow. [changes setting: put back with `ame desktop pill glow on`]

## Privacy: share guard, shield, network by app

- [ ] D-PRIV-01 Share guard covers. How: open Notes and Security, share the whole screen (a browser video call test page, or GNOME Remote Desktop). Expect: their windows blurred so no word reads, labelled **Hidden while you share**; the live pill says once what is covered. [needs: a screen-share app]
- [ ] D-PRIV-02 Window opened during a share. How: during the share, open Backups. Expect: covered before it is first drawn.
- [ ] D-PRIV-03 Private folder in Files. How: open `~/Private` (open private folder) in Files during a share. Expect: that Files window is covered; another Files window is not.
- [ ] D-PRIV-04 Hold to uncover. How: hold a click on a cover for a moment. Expect: the window stays uncovered, with its menus and dialogs, until the share ends.
- [ ] D-PRIV-05 Window share only. How: share a single window instead of the screen. Expect: covers go as soon as the desktop knows every stream is a window; recording the screen yourself covers nothing.
- [ ] D-PRIV-06 Card instead of blur. How: `ame desktop share-guard card`, share. Expect: a solid card over the covered windows. [changes setting: put back with `ame desktop share-guard blur`]
- [ ] D-PRIV-07 Share guard off. How: `ame desktop share-guard off`, share. Expect: nothing covered. [changes setting: put back with `ame desktop share-guard blur`]
- [ ] D-PRIV-08 Apps covered. How: `ame desktop share-guard apps` (in a terminal, it asks), then `ame desktop share-guard apps reset`. Expect: the picker names the apps; reset puts back Notes, Security, Backups and the password managers. [changes setting: put back with `ame desktop share-guard apps reset`]
- [ ] D-PRIV-09 Private folder cover off. How: `ame desktop share-guard private off`, share with `~/Private` open. Expect: not covered. [changes setting: put back with `ame desktop share-guard private on`]
- [ ] D-PRIV-10 Shield tile. How: open quick settings, then the **Shield** tile's menu. Expect: *Protected* or how many need a look, home or away; the menu has the report's result (administrators), the network and firewall zone, encrypted DNS, USB protection, the private folder open or closed, camera and microphone permission; every line opens Security on its page and switches nothing.
- [ ] D-PRIV-11 Shield as a mark. How: `ame desktop shield mark`. Expect: a shield in the top bar beside the system's icons, green, amber when something needs a look; same menu. [changes setting: put back with `ame desktop shield tile`]
- [ ] D-PRIV-12 Shield only on attention. How: `ame desktop shield attention`. Expect: the shield shows only while something needs a look. [changes setting: put back with `ame desktop shield tile`]
- [ ] D-PRIV-13 Shield off. How: `ame desktop shield off`. Expect: no tile and no mark. [changes setting: put back with `ame desktop shield tile`]
- [ ] D-PRIV-14 Shield never shows duress. How: open the shield's menu. Expect: no line about a duress finger or password, whatever is set up.
- [ ] D-PRIV-15 Network by app. How: `ame desktop network-apps on`, open the network meter's menu with a browser running. Expect: at its end the apps with connections open, how many, and to where (a name only where the machine knows one, else an address); **Network per app, in Security** opens Security's Apps page. [changes setting: put back with `ame desktop network-apps off`]

## Notifications

- [ ] D-NOTIFY-01 Stacks. How: send three notifications from one app (`notify-send -a Test a; notify-send -a Test b; notify-send -a Test c`). Expect: one folded stack in the calendar's list showing how many after the app's name.
- [ ] D-NOTIFY-02 Banner look. How: `notify-send Hello World`. Expect: a banner in the current style's shape on glass, readable.
- [ ] D-NOTIFY-03 Do Not Disturb. How: switch Do Not Disturb at the foot of the list. Expect: no banners pop, notifications wait in the list; dock badges hidden.
- [ ] D-NOTIFY-04 Quiet while fullscreen. How: make a window fullscreen on the main screen, `notify-send test`. Expect: no banner, no sound; it waits in the list and counts on the clock's dot; `notify-send -u critical urgent` still pops.
- [ ] D-NOTIFY-05 Quiet ends. How: leave fullscreen. Expect: the pill says **N waiting in the list**; a click opens the list; held banners are not replayed one after another.
- [ ] D-NOTIFY-06 Quiet off. How: `ame desktop quiet off`, repeat D-NOTIFY-04. Expect: banners pop while fullscreen. [changes setting: put back with `ame desktop quiet on`]
- [ ] D-NOTIFY-07 Quiet at night. How: `ame desktop quiet night on` inside Night Light's times. Expect: banners wait in the list. [changes setting: put back with `ame desktop quiet night off`]
- [ ] D-NOTIFY-08 Digest. How: `ame desktop digest on`, `ame desktop digest times HH:MM` two minutes ahead, send a few notifications. Expect: no banners; at that time one card with a row per app, **Show all** and **Clear**; everything still in the list. [changes setting: put back with `ame desktop digest off` and `ame desktop digest times 12:00 18:00`]
- [ ] D-NOTIFY-09 Later. How: rest the pointer on a banner. Expect: after the app's own buttons, **Later**: **In an hour**, **This evening**, **Tomorrow morning**, **When I next unlock**; picking one removes the banner and the pill says when it comes back, with **Undo**.
- [ ] D-NOTIFY-10 Later when I next unlock. How: Later › **When I next unlock**, lock, unlock. Expect: it comes back as it was, with its buttons, and rings once.
- [ ] D-NOTIFY-11 Later with L. How: focus a banner with the keyboard and press `L`. Expect: Later in an hour.
- [ ] D-NOTIFY-12 Later list. How: open the calendar after snoozing. Expect: at the top **Later** says when each comes back with **Now**; the snoozed one also stays in the list and its buttons work.
- [ ] D-NOTIFY-13 Mute an app. How: on a banner, **Mute <App> for an hour**, then send more from it. Expect: they arrive in the list without banners; **Muted** at the top of the list says until when and how many, with **Unmute**, which shows them together.
- [ ] D-NOTIFY-14 Later off. How: `ame desktop notifications later off`. Expect: no Later or Mute on banners. [changes setting: put back with `ame desktop notifications later on`]
- [ ] D-NOTIFY-15 Later times. How: `ame desktop notifications later-times 19:00 08:00`, Later › This evening. Expect: it says 19:00. [changes setting: put back with `ame desktop notifications later-times 18:00 09:00`]
- [ ] D-NOTIFY-16 Badges on app icons. How: send notifications from an app pinned in the dock. Expect: its icon in the dock and the app grid shows the count waiting.

## Focus

- [ ] D-FOCUS-01 Work. How: Focus tile › Work. Expect: banners only from Calendar, Clocks and calls, without a sound; the rest waits in the list; the pill shows the mark and the time. [changes setting: put back with `ame desktop focus off`]
- [ ] D-FOCUS-02 Games. How: `ame desktop focus games`. Expect: banners held; the dock hides while a window touches it; performance power mode; Night Light paused. [changes setting: put back with `ame desktop focus off`]
- [ ] D-FOCUS-03 Sleep. How: `ame desktop focus sleep`. Expect: banners held, Night Light on at its warmest, the theme's Daylight night picture over the wallpaper, power saver, an amber accent; all put back when it ends. [changes setting: put back with `ame desktop focus off`]
- [ ] D-FOCUS-04 Ends after an hour or tomorrow. How: `ame desktop focus work hour`; then `ame desktop focus work tomorrow`. Expect: the tile says when it ends (in an hour; at 06:00 tomorrow). [changes setting: put back with `ame desktop focus off`]
- [ ] D-FOCUS-05 What is on. How: `ame desktop focus`. Expect: it says which profile is on and until when.
- [ ] D-FOCUS-06 End and count. How: during Work send two notifications, then turn it off. Expect: the pill says how many are waiting; everything as before (dock, accent, wallpaper, power).
- [ ] D-FOCUS-07 Edit a profile line. How: `ame desktop focus edit work power performance`, turn Work on. Expect: performance mode while on; `ame desktop focus edit work reset` gives the image's own. [changes setting: put back with `ame desktop focus edit work reset`]
- [ ] D-FOCUS-08 Profile apps. How: `ame desktop focus edit work apps`. Expect: a terminal picker of the apps let through. [changes setting: put back with `ame desktop focus edit work reset`]
- [ ] D-FOCUS-09 Grey screen. How: Control › Focus: Work › the screen in grey on, turn Work on. Expect: the whole screen without colour while on. [changes setting: put back with `ame desktop focus edit work reset`]
- [ ] D-FOCUS-10 Solid glass and shorter motion. How: Control › Focus: Games › solid glass and shorter motion on, turn Games on. Expect: glass solid and animations at half their time while on. [changes setting: put back with `ame desktop focus edit games reset`]
- [ ] D-FOCUS-11 Saved set offer. How: save a workspace set, set it in Control for Work, pick Work by hand. Expect: it asks before opening the set. [changes setting: put back with `ame desktop focus edit work reset`]
- [ ] D-FOCUS-12 Games trigger. How: `ame desktop focus trigger games on`, start a game (not Steam itself). Expect: Games turns on when the game gets the keyboard and ends when it closes. [changes setting: put back with `ame desktop focus trigger games off`]
- [ ] D-FOCUS-13 Sleep trigger. How: `ame desktop focus trigger sleep on`. Expect: Sleep starts at Night Light's evening time and ends at its morning time; turning Focus off meanwhile keeps it off until the next evening. [changes setting: put back with `ame desktop focus trigger sleep off`]
- [ ] D-FOCUS-14 Lock while a profile holds power. How: Games on, lock, check the power mode, unlock. Expect: the hold is let go while locked and taken again on unlock.

## Presenting

- [ ] D-PRESENT-01 Offer Present mode. How: `ame desktop present on`. Expect: a **Present** tile in quick settings. [changes setting: put back with `ame desktop present off`]
- [ ] D-PRESENT-02 Presenting. How: click **Present**. Expect: the top bar says **Presenting** and for how long (a click stops it); the screen does not dim, lock or sleep by itself; banners wait; a halo round the pointer.
- [ ] D-PRESENT-03 Torch. How: `ame desktop present mark torch`, present. Expect: everything dimmed but a circle round the pointer. [changes setting: put back with `ame desktop present mark halo`]
- [ ] D-PRESENT-04 No mark. How: `ame desktop present mark none`. Expect: the pointer as it is. [changes setting: put back with `ame desktop present mark halo`]
- [ ] D-PRESENT-05 Stop and count. How: send a notification while presenting, then stop. Expect: the top bar says how many are waiting.
- [ ] D-PRESENT-06 Ask when a screen is plugged in. How: plug in a screen. Expect: a question whether to present on it, once per screen per session; nothing happens without **Present**; presenting ends when that screen is unplugged. [needs: second screen or projector]
- [ ] D-PRESENT-07 Ask off. How: `ame desktop present ask off`, plug in. Expect: no question. [changes setting: put back with `ame desktop present ask on`] [needs: second screen]
- [ ] D-PRESENT-08 Ends with the share. How: start presenting during a screen share, end the share. Expect: presenting ends too.
- [ ] D-PRESENT-09 Scribble. How: `Super+Alt+D` (Present mode offered). Expect: ink over the whole screen, a bar at the bottom with a pen, a highlighter and three colours; windows under it take no clicks or keys.
- [ ] D-PRESENT-10 Scribble keys. How: draw, then `Ctrl+Z`, `1` `2` `3`, `P`, `H`, `Esc`. Expect: undo the last stroke, colours, pen, highlighter; `Esc` (or **Clear**) wipes the ink and gives the windows back; nothing saved.
- [ ] D-PRESENT-11 Screenshot with ink. How: draw, press `Print`. Expect: the screenshot holds the ink.
- [ ] D-PRESENT-12 Scribble needs Present. How: `ame desktop present off`, press `Super+Alt+D`. Expect: nothing.

## Desks

- [ ] D-DESKS-01 Turn on. How: `ame desktop desks on` (or Control › Desktop › **Desks**). Expect: nothing visible until a set of screens arrives. [changes setting: put back with `ame desktop desks off`] [needs: external screen]
- [ ] D-DESKS-02 First arrival card. How: plug in an external screen. Expect: a card at the top right shows how the sound output, the dock's place, the Focus profile and the power mode are set, with **Set up** and **Not now**. [needs: external screen]
- [ ] D-DESKS-03 Arrival toast. How: after Set up, move the dock (`ame desktop dock edge left`) away from it, unplug, change things, plug back in. Expect: what differs is set at once and a toast at the bottom says what, with **Undo**; unplugging puts back what the desk set. [needs: external screen]
- [ ] D-DESKS-04 Learn from a change. How: at a desk, pick another sound output, or move the dock. Expect: it asks whether the desk should remember it, once per change; a device that just connected is not asked about. [needs: external screen]
- [ ] D-DESKS-05 Not now remembered. How: answer **Not now** at a new desk, replug; then `ame desktop desks ask`. Expect: no card until asked again. [needs: external screen]
- [ ] D-DESKS-06 List, rename, forget. How: `ame desktop desks list`, `ame desktop desks rename ID Office desk`, `ame desktop desks forget ID`. Expect: listed with what each sets (named like "2 screens" until renamed), renamed, forgotten.
- [ ] D-DESKS-07 Unlock is no arrival. How: lock and unlock at a desk. Expect: no card, no toast.

## Sounds, lock screen and the reveal

- [ ] D-SOUND-01 Soft sound set. How: take a screenshot, plug in power, step the volume, press Backspace in an empty terminal (bell). Expect: Amethystora's soft sounds; a slow chord once the desktop has started after login.
- [ ] D-SOUND-02 Sounds off. How: `ame desktop sounds off`. Expect: the desktop makes none of its own sounds; apps still make theirs. [changes setting: put back with `ame desktop sounds soft`]
- [ ] D-LOCK-01 Lock screen. How: `Super+L`. Expect: a large clock and date, what is playing with controls, notifications as one row per app with a count, never their text; Amethystora's own colours whatever the theme.
- [ ] D-LOCK-02 Lock screen with High Contrast. How: Settings › Accessibility › High Contrast on, lock. Expect: GNOME's own high-contrast lock screen. [changes setting: put back with High Contrast off]
- [ ] D-LOCK-03 Unlock restores the desktop. How: unlock after a lock. Expect: every module back (dock, pill, meters, glass, pinned pictures, Later's held notifications) with no flash of an unstyled bar.
- [ ] D-REVEAL-01 The reveal at login. How: log out and in. Expect: the screen starts as the boot splash ended (dark sky, gem in the middle); the gem swells a little and flies into the top bar to become the logo while the desktop shows through and the bar settles, about a second; not on unlock. [logout]
- [ ] D-REVEAL-02 Reveal off. How: `ame desktop transition reveal off`, log out and in. Expect: no reveal. [changes setting: put back with `ame desktop transition reveal on`] [logout]

## Search (Super+Space)

- [ ] D-SEARCH-01 Open and close. How: `Super+Space`; then `Escape`, `Super+Space` again, and a click elsewhere. Expect: a box near the top of the screen over the windows (no overview); each of the three closes it.
- [ ] D-SEARCH-02 Enter opens the first. How: type `calc`, `Enter`. Expect: Calculator opens.
- [ ] D-SEARCH-03 Numbered results. How: type `files`, look at Amethystora's rows, press `Ctrl+2`. Expect: each Amethystora row shows its number at its end; `Ctrl+2` opens the second.
- [ ] D-SEARCH-04 Typos forgiven. How: type `calxu`, then `mc`. Expect: Calculator; Mission Center.
- [ ] D-SEARCH-05 Actions. How: type `power off` and `restart`. Expect: GNOME's Power Off and Restart actions are found (do not press Enter).
- [ ] D-SEARCH-06 Result menu and drag. How: right-click an app result; drag an app result onto the dock. Expect: its menu; the app is pinned in the dock.
- [ ] D-SEARCH-07 Sums. How: type `1284 * 0.18`, then `200 + 10%`, then `Enter`. Expect: 231.12; 220; Enter copies the answer; numbers in the session's language.
- [ ] D-SEARCH-08 Conversions. How: type `3.5 km in miles` and `21 °C in °F`. Expect: 2.1748 mi; 69.8 °F; no currencies.
- [ ] D-SEARCH-09 Sums off. How: `ame desktop search answers off`. Expect: no answer row. [changes setting: put back with `ame desktop search answers on`]
- [ ] D-SEARCH-10 Control's settings. How: type `phone pairing`. Expect: a row like *Phone pairing: On*; `Enter` changes it at once (or opens a terminal if it asks); *Control › …* opens Control there. [changes setting: put back with the same row]
- [ ] D-SEARCH-11 Settings off. How: `ame desktop search settings off`. Expect: no Control rows. [changes setting: put back with `ame desktop search settings on`]
- [ ] D-SEARCH-12 Open windows. How: with a window on another workspace, type part of its title, `Enter`. Expect: switches to it on its workspace.
- [ ] D-SEARCH-13 Windows off. How: `ame desktop search windows off`. Expect: no window rows. [changes setting: put back with `ame desktop search windows on`]
- [ ] D-SEARCH-14 The manual. How: type `rolling back an update`. Expect: manual pages that answer it; Enter opens the Manual there.
- [ ] D-SEARCH-15 Manual off. How: `ame desktop search manual off`. Expect: no manual rows. [changes setting: put back with `ame desktop search manual on`]
- [ ] D-SEARCH-16 Clipboard history. How: copy something, type `clip:`, then `clip: ssh`. Expect: the history only after `clip:`, narrowed by the words; `Enter` pastes the item where you were typing.
- [ ] D-SEARCH-17 Clipboard off. How: `ame desktop search clipboard off`, type `clip:`. Expect: no clipboard rows. [changes setting: put back with `ame desktop search clipboard on`]
- [ ] D-SEARCH-18 Ask the agent row. How: with `ame agent toggle on`, type a question. Expect: the last row *Ask the agent: …*; Enter opens the agent in a terminal with it as the first question; nothing starts before Enter. With the features off, no such row.
- [ ] D-SEARCH-19 Agent row off. How: `ame desktop search agent off`. Expect: no agent row. [changes setting: put back with `ame desktop search agent on`]
- [ ] D-SEARCH-20 Glance. How: type a file name Files finds, `↓` to it, `Space`; `↑`/`↓`; `Space` again. Expect: the file shown without opening it, the arrows go to the other files, the second Space closes it and the search is still there.
- [ ] D-SEARCH-21 Glance off. How: `ame desktop search glance off`. Expect: `Space` types a space. [changes setting: put back with `ame desktop search glance on`]
- [ ] D-SEARCH-22 Each switch listed. How: `ame desktop search`. Expect: all seven (answers, settings, manual, windows, clipboard, agent, glance) and whether each is on.
- [ ] D-SEARCH-23 Typing into an app afterwards. How: open search from a text field, `Escape`, type. Expect: the field still takes text with the input method (no lost IBus).

## Overview and app grid

- [ ] D-GRID-01 Overview. How: tap `Super`. Expect: every open window at once, search at the top, the glass behind it; tap again closes.
- [ ] D-GRID-02 App grid. How: `Super+A`, the app grid button on the dock, or a three-finger pinch. Expect: **Recently used** row at the top (most used first, at most eight), **All apps** over the grid.
- [ ] D-GRID-03 Folders. How: look at the grid. Expect: folders **Office**, **Graphics**, **Games**, **System**, **Development**, **Utilities** in the session's language; Security, Updates, Control, Backups, the Manual, Phone, Steam and Lutris stay loose.
- [ ] D-GRID-04 Recent row off. How: `ame desktop app-grid recent off`. Expect: no recent row. [changes setting: put back with `ame desktop app-grid recent on`]
- [ ] D-GRID-05 Folders reset. How: rename a folder, then `ame desktop app-grid folders reset`. Expect: the folders as the image has them. [risky: forgets your folder changes]
- [ ] D-GRID-06 Uninstall from the app menu. How: right-click a Flatpak app in the grid. Expect: **Uninstall** and the app's page in Bazaar; Uninstall asks with choices in the theme's colours. [risky: removes the app if confirmed]
- [ ] D-GRID-07 Updating app greyed. How: during a Flatpak update of an app. Expect: its icon greyed in the grid and dock; a progress bar while busy.

## Clipboard history

- [ ] D-CLIP-01 Open. How: `Super+Shift+V`, or the clipboard icon in the top bar. Expect: the last 15 things copied; pick one to copy it; type to search; pin items.
- [ ] D-CLIP-02 Pictures. How: copy an image, open the history. Expect: the picture listed.
- [ ] D-CLIP-03 Private mode. How: turn **Private mode** on in the menu, copy text, look. Expect: nothing recorded until it is off.
- [ ] D-CLIP-04 Password manager. How: copy from KeePassXC or Secrets. Expect: not recorded.
- [ ] D-CLIP-05 Keep time. How: `ame desktop clipboard session`, log out and in. Expect: only pinned items remain. [changes setting: put back with `ame desktop clipboard always`] [logout]
- [ ] D-CLIP-06 Fingerprint login. How: log in with a fingerprint, open the history. Expect: what you copy since, under **Unlock to see earlier items**, which asks for the password and then shows the rest. [needs: fingerprint reader]
- [ ] D-CLIP-07 Menu look. How: open it in each style. Expect: the clipboard menu in the theme's colours, matching the other menus.

## Shelf

- [ ] D-SHELF-01 Edge mode. How: `ame desktop shelf edge`, drag a file from Files. Expect: a glow at the right edge; drop on it and the shelf opens there, a narrow column above the windows, on every workspace. [changes setting: put back with `ame desktop shelf off`]
- [ ] D-SHELF-02 Drop more, drag out. How: drop text and a picture on it, then drag the file into another app. Expect: items listed; the dragged item leaves once the app took it; with `Ctrl` held it stays; a file is copied, never moved.
- [ ] D-SHELF-03 Keys and menu. How: focus an item, `Delete`; right-click an item; `Ctrl+Delete`. Expect: removes it; **Remove**, **Show in Files** (for a file), **Clear the shelf**; clears all; the shelf closes when empty.
- [ ] D-SHELF-04 Missing file. How: shelve a file, delete it in Files. Expect: its item turns grey.
- [ ] D-SHELF-05 Shake mode. How: `ame desktop shelf shake`, shake the pointer side to side while dragging. Expect: a card under the pointer to drop on. [changes setting: put back with `ame desktop shelf off`]
- [ ] D-SHELF-06 Alt+Tab reaches it. How: `Alt+Tab` with the shelf open. Expect: the shelf is a window in the switcher.
- [ ] D-SHELF-07 Limits. How: drop a very large text (over 1 MB). Expect: it says it cannot take it.

## Emoji and text shortcuts

- [ ] D-EMOJI-01 Open. How: in a text field, `Super+.`. Expect: emoji and symbols under the text cursor over the window; type to search (`euro`, `arrow`, `smile`, or words in the session language).
- [ ] D-EMOJI-02 Tabs and keys. How: `Tab`, arrows, `Ctrl+Page Down`/`Up`. Expect: **Recent**, **Smileys**, **Arrows**, **Maths**, **Money**, **Punctuation** and Unicode's emoji groups; the keys move between search, tabs and grid.
- [ ] D-EMOJI-03 Insert. How: `Enter` or a click on one; `Escape` another time. Expect: it is typed where you were; `Escape` types nothing. In a terminal it is pasted (`Ctrl+Shift+V`) and stays on the clipboard.
- [ ] D-EMOJI-04 Skin tone. How: right-click (or hold, or `Menu` on) a hand. Expect: six tones; the one picked becomes the tone for the rest; same as `ame desktop emoji tone medium`. [changes setting: put back with `ame desktop emoji tone none`]
- [ ] D-EMOJI-05 Input method after closing. How: pick an emoji in a GTK app, then type accented text with IBus. Expect: the input method still works in that window without refocusing.
- [ ] D-EMOJI-06 Smile app. How: `Ctrl+Alt+Space`. Expect: Smile opens.
- [ ] D-TEXT-01 Add and expand. How: `ame desktop text-shortcut add ';sig' 'Best, Me'`, `ame desktop text-shortcuts on`, type `;sig ` in Text Editor. Expect: replaced by its text; Undo takes it back; `{date}` gives today's date. [changes setting: put back with `ame desktop text-shortcuts off` and `ame desktop text-shortcut remove ';sig'`]
- [ ] D-TEXT-02 Not in password fields. How: type the shortcut in a password field. Expect: no expansion.
- [ ] D-TEXT-03 Terminal. How: type a one-line shortcut in kitty. Expect: replaced by BackSpaces and text; a multi-line text is not expanded there.
- [ ] D-TEXT-04 Control's Typing group. How: Control › Typing. Expect: the shortcuts, a field to try them in, and the switch.

## Screenshots and pins

- [ ] D-SHOT-01 Drawing tools. How: `Print`, choose an area. Expect: above the bar: move, pen, box, filled box, highlighter, arrow, text, numbered markers, eight colours and a width slider (the mouse wheel sets it too).
- [ ] D-SHOT-02 Tool keys. How: `1`…`9`, draw, `Ctrl+Z`, pick up a mark with move and `Delete`. Expect: tools picked by number; undo; the mark removed.
- [ ] D-SHOT-03 Copy and save. How: `Ctrl+C`; then `Ctrl+S`. Expect: the picture copied without saving; a save dialog to choose where.
- [ ] D-SHOT-04 Tool memory. How: give the pen a red colour and wide line, close, reopen. Expect: the pen comes back red and wide.
- [ ] D-SHOT-05 Thumbnail. How: take a screenshot. Expect: a thumbnail at the bottom right for six seconds (longer while hovered) instead of GNOME's notification; click opens the image viewer; **Edit** (Gradia), **Copy**, **Pin on top**, **Show in Files**, **Delete** (to the trash).
- [ ] D-SHOT-06 Thumbnail off. How: `ame desktop screenshot thumbnail off`. Expect: GNOME's notification instead. [changes setting: put back with `ame desktop screenshot thumbnail on`]
- [ ] D-SHOT-07 Pin from the bar. How: `Print`, frame an area, **Pin on top** beside the pointer button (or `Ctrl+P`). Expect: it stays exactly where it was, above every window, on every workspace, not saved or copied.
- [ ] D-SHOT-08 Pin handling. How: drag a pin, scroll over it, `Ctrl`+scroll. Expect: moves; larger or smaller; more see-through.
- [ ] D-SHOT-09 Click-through. How: click the arrow in its corner, click on it; click the arrow again. Expect: clicks pass to the window below and its ring turns amber; then it takes clicks again.
- [ ] D-SHOT-10 Pin menu and close. How: right-click a pin; click the cross; click a pin and `Esc`. Expect: copy, save, **Solid**, **See-through**, **Faint**; the cross and `Esc` let it go.
- [ ] D-SHOT-11 Six at most. How: pin seven. Expect: the oldest goes.
- [ ] D-SHOT-12 Pins through a lock. How: lock and unlock with a pin. Expect: still there; gone after logging out.
- [ ] D-SHOT-13 Pins blurred while sharing. How: share the whole screen with a pin and a thumbnail showing. Expect: both blurred with a small mark; sharp again when the share ends.
- [ ] D-SHOT-14 Pinning off. How: `ame desktop screenshot pin off`. Expect: no Pin buttons; pinned pictures let go. [changes setting: put back with `ame desktop screenshot pin on`]
- [ ] D-SHOT-15 Extract text. How: `Print`, drag over text, **Extract Text** or `Ctrl+E`. Expect: Gradia (first time asks a language to download) copies the text and says **Copied!**; the button is off for a window, the whole screen or a recording.
- [ ] D-SHOT-16 Screen recording. How: `Ctrl+Shift+Alt+R` twice. Expect: starts and stops a recording (pill, glow, red dot).

## Live captions

- [ ] D-CAPTIONS-01 Turn on. How: `ame desktop captions on`. Expect: it says it downloads a 39 MiB model from alphacephei.com and asks; after yes it is checked and captions are on. [changes setting: put back with `ame desktop captions off`]
- [ ] D-CAPTIONS-02 Captions. How: play an English video with speech. Expect: words in a dark box near the bottom of the screen, over every window (a fullscreen video too), clicks pass through; gone a few seconds after.
- [ ] D-CAPTIONS-03 Silence and pause. How: pause the video. Expect: the box goes; nothing listens while no app plays.
- [ ] D-CAPTIONS-04 Locked. How: lock while speech plays. Expect: no captions while locked.
- [ ] D-CAPTIONS-05 Quick settings toggle. How: **Live captions** in quick settings. Expect: turns them off and on; checked while on.
- [ ] D-CAPTIONS-06 Status and remove. How: `ame desktop captions status`, then `ame desktop captions remove`. Expect: says how things stand; remove turns them off and deletes the model. [risky: deletes the downloaded model]

## Accessibility helpers

- [ ] D-ACCESS-01 Colour filters. How: `ame desktop access filter protan`, then `deutan`, `tritan`, `grey`. Expect: a filter over the whole screen (zoom and every screen too); grey takes the colour away; screenshots keep the apps' colours. [changes setting: put back with `ame desktop access filter none`]
- [ ] D-ACCESS-02 Filter strength. How: the filter tile's 50 / 75 / 100, or `ame desktop access strength 50`. Expect: the filter weakens and strengthens. [changes setting: put back with `ame desktop access filter none`]
- [ ] D-ACCESS-03 HDR or uncopyable screen. How: with a filter on an HDR screen. Expect: left unfiltered and told once. [needs: HDR screen]
- [ ] D-ACCESS-04 Reading ruler band. How: `ame desktop access ruler band`, `Super+Ctrl+R`, move the pointer over text. Expect: a band follows the pointer; `Super+Ctrl+R` hides and shows it. [changes setting: put back with `ame desktop access ruler off`]
- [ ] D-ACCESS-05 Ruler dim and underline. How: `ame desktop access ruler dim`, then `underline`. Expect: the rest dimmed around the band; a line under it. [changes setting: put back with `ame desktop access ruler off`]
- [ ] D-ACCESS-06 Ruler key unbound when off. How: with the ruler off, `Super+Ctrl+R`. Expect: nothing.
- [ ] D-ACCESS-07 Read aloud. How: `ame desktop access read-aloud on`, select text in Firefox, `Super+Ctrl+S`; press again. Expect: read in the screen reader's voice, sentence by sentence; the second press stops. [changes setting: put back with `ame desktop access read-aloud off`]
- [ ] D-ACCESS-08 Read-aloud speed. How: `ame desktop access read-aloud-speed 1.5` (or Control). Expect: faster speech. [changes setting: put back with `ame desktop access read-aloud-speed 1`]
- [ ] D-ACCESS-09 Focus grey with a filter. How: filter deutan on and a Focus profile with grey. Expect: both apply together, neither cancels the other.

## Touch and pen

- [ ] D-TOUCH-01 Touch mode on. How: `ame desktop touch mode on`. Expect: top bar 12 px taller with larger text, dock icons up to 64 px, menu rows at least 44 px, and a handle at the right edge for Today. [changes setting: put back with `ame desktop touch mode off`]
- [ ] D-TOUCH-02 Today from the right edge. How: in touch mode, swipe in from the right edge (or use the handle). Expect: the calendar menu opens. [needs: touch screen]
- [ ] D-TOUCH-03 Follow the hinge. How: `ame desktop touch mode follow`, fold into a tablet. Expect: touch mode on folded, off unfolded; the on-screen keyboard follows. [needs: convertible] [changes setting: put back with `ame desktop touch mode off`]
- [ ] D-TOUCH-04 Status. How: `ame desktop touch`. Expect: how touch mode, the pen's tools and the pen's button are set.
- [ ] D-PEN-01 Ring. How: `ame desktop touch pen-ring ring`, `Super+Ctrl+P`. Expect: six tools round the tip: Scribble, Area, Note, Text, Right click, Back; move toward one to light it; a touch in the middle, `Escape` or a click outside closes. [changes setting: put back with `ame desktop touch pen-ring off`]
- [ ] D-PEN-02 Each tool. How: pick each tool. Expect: Scribble draws (only where present mode offers it), Area takes an area screenshot, Note opens a quick note, Text copies an area's text with Gradia, Right click and Back act where the ring was opened. [needs: pen]
- [ ] D-PEN-03 Strip. How: `ame desktop touch pen-ring strip`. Expect: the tools in a column at the screen's edge. [changes setting: put back with `ame desktop touch pen-ring off`]
- [ ] D-PEN-04 Tool order. How: `ame desktop touch pen-tools area note text right-click back`. Expect: the ring shows those, from the top, clockwise. [changes setting: put back with `ame desktop touch pen-tools scribble area note text right-click back`]
- [ ] D-PEN-05 Pen button. How: `ame desktop touch pen-button on`, press the pen's side button; then `off`. Expect: the button opens the tools; off gives back what it did. [needs: pen]

## Tips

- [ ] D-TIPS-01 A tip. How: after the first hour on a new account, hold `Super` (or shake the mouse, once Shake to find is on). Expect: a small card next to the feature with **Got it**; it never takes keys or clicks, closes after twelve seconds, comes once ever, never two at once, at least half an hour apart; none over fullscreen, a share, quiet, the overview or a dialog.
- [ ] D-TIPS-02 Tips off and reset. How: `ame desktop hints off`; `ame desktop hints reset`. Expect: no tips; the seen ones can come again. [changes setting: put back with `ame desktop hints on`]

## Pointer

- [ ] D-POINTER-01 Shake to grow. How: shake the mouse first (it is off by default: nothing happens), then `ame desktop pointer-shake grow` and shake quickly. Expect: the pointer swells to about three and a half times while you shake, then back. [changes setting: put back with `ame desktop pointer-shake off`]
- [ ] D-POINTER-02 Beacon. How: `ame desktop pointer-shake beacon`, shake. Expect: the pointer grows a little and rings go out from it. [changes setting: put back with `ame desktop pointer-shake off`]
- [ ] D-POINTER-03 Shake off. How: `ame desktop pointer-shake off`. Expect: nothing on shaking; this is the default.
- [ ] D-POINTER-04 Larger on dense screens. How: on a dense screen at 100 %. Expect: the pointer is 32 rather than 24; `ame desktop pointer-dense off` gives 24. [needs: HiDPI screen at 100 %] [changes setting: put back with `ame desktop pointer-dense on`]
- [ ] D-POINTER-05 Pointer sets. How: `ame desktop pointer halo`, `ink`, `facet`, then `theme`. Expect: white Halo, dark Ink, Facet; in GNOME Shell, GTK 4, GTK 3 and a Flatpak app; theme follows the theme (Halo on dark, Ink on light). [changes setting: put back with `ame desktop pointer theme`]

## Dock

- [ ] D-DOCK-01 Dock at rest. How: look at the bottom of each screen. Expect: a glass pill holding the pinned apps, running apps, up to three recent apps after a divider, the Downloads stack, mounted drives and the trash, and the app grid button; windows stop above it.
- [ ] D-DOCK-02 Swell. How: move the pointer along the dock. Expect: the icons grow in a wave under the pointer, smoothly, without the dock jumping.
- [ ] D-DOCK-03 Swell amount. How: `ame desktop dock amount 220`, then `120`. Expect: the icon under the pointer grows to about 2.2x, then 1.2x. [changes setting: put back with `ame desktop dock amount 160`]
- [ ] D-DOCK-04 Lift. How: `ame desktop dock magnify lift`. Expect: only the icon under the pointer rises. [changes setting: put back with `ame desktop dock magnify swell`]
- [ ] D-DOCK-05 No magnify. How: `ame desktop dock magnify off`. Expect: nothing grows. [changes setting: put back with `ame desktop dock magnify swell`]
- [ ] D-DOCK-06 Launch halo. How: open an app from the dock. Expect: a ring runs round its icon until its first window opens.
- [ ] D-DOCK-07 Launch hop, breathe, off. How: `ame desktop dock launch hop`, `breathe`, `off`, opening an app each time. Expect: the icon hops; pulses; no sign. [changes setting: put back with `ame desktop dock launch halo`]
- [ ] D-DOCK-08 Running bar. How: open one, then two windows of an app. Expect: a bar under its icon, longer with two windows.
- [ ] D-DOCK-09 Dot and glow. How: `ame desktop dock indicator dot`, then `glow`. Expect: a dot per window; a light under the icon. [changes setting: put back with `ame desktop dock indicator bar`]
- [ ] D-DOCK-10 Recent apps. How: open and close an unpinned app. Expect: it stays after a divider among the last three used; none with Usage history off in Settings › Privacy.
- [ ] D-DOCK-11 Recent off. How: `ame desktop dock recent off`. Expect: no recent apps. [changes setting: put back with `ame desktop dock recent on`]
- [ ] D-DOCK-12 Window previews. How: rest the pointer on a running app with two windows, click one. Expect: its windows shown above it on a glass card; the click brings that window forward.
- [ ] D-DOCK-13 Previews off. How: `ame desktop dock previews off`. Expect: only the names. [changes setting: put back with `ame desktop dock previews on`]
- [ ] D-DOCK-14 Fan out windows. How: right-click (or hold) a running app with several windows. Expect: its windows fan out over its menu; scroll or Left/Right go through them; a click or Space picks one.
- [ ] D-DOCK-15 Pin and unpin. How: right-click an app › **Pin to dock**; then **Remove from the dock**. Expect: pinned; removed (stays in the app grid).
- [ ] D-DOCK-16 Drag off to unpin. How: drag a pinned app off the dock. Expect: it dissolves; still in the app grid.
- [ ] D-DOCK-17 Amethystora apps' pages. How: right-click Manual, Notes, Logs, Backups, Security, Control in the dock. Expect: **Hotkeys**; **Tasks**; **Crashes** and **Apps and Services**; **Backup Status**; **Virus Scan**; **Appearance** and **System**; each opens that page.
- [ ] D-DOCK-18 Alt+number. How: `Alt+1`…`Alt+9`. Expect: switches to the pinned app in that slot, or opens it.
- [ ] D-DOCK-19 Numbers while holding Super. How: hold `Super` a second. Expect: numbers on the dock's apps (and the shortcuts card).
- [ ] D-DOCK-20 Badges and progress. How: an app with unread items or a download in progress (e.g. Firefox downloading). Expect: a count, a progress bar on its icon; greyed while it updates; nothing of it under Do Not Disturb.
- [ ] D-DOCK-21 Make a folder. How: drop one pinned app on another and wait until it lights up. Expect: a folder; click it to open, click its name to rename; **Take the folder apart** puts the apps back.
- [ ] D-DOCK-22 Downloads stack. How: click the Downloads stack. Expect: the twelve newest items, newest first, and **Open in Files**.
- [ ] D-DOCK-23 Add a stack. How: drag a folder from Files onto the dock, or `ame desktop dock stack add ~/Documents`. Expect: kept as a stack; drag it off (or `ame desktop dock stack remove ~/Documents`) to remove. [changes setting: put back with `ame desktop dock stack remove ~/Documents`]
- [ ] D-DOCK-24 Drop files on a stack. How: drag files onto a stack; with `Ctrl` held another time. Expect: moved into that folder (copied with Ctrl) by Files, which shows progress and can undo.
- [ ] D-DOCK-25 Folder colour on a stack. How: in Files, Scripts › Folder colour › Jade on a stacked folder, then open the stack. Expect: the stack takes the colour. [changes setting: put back with Scripts › Folder colour › No colour]
- [ ] D-DOCK-26 Trash. How: delete a file, right-click the trash. Expect: full trash icon; **Empty trash** (asks Files); clicking opens the trash in Files. [risky: empties the trash]
- [ ] D-DOCK-27 Drives. How: plug a USB disk. Expect: it appears on the dock; right-click › **Unmount** / **Eject**; a Files window showing it gets its dot. [needs: USB disk]
- [ ] D-DOCK-28 Send to the phone. How: drop a file on **Phone** in the dock. Expect: sends to the paired phone ("Sending to …", "Sent"); with no phone, **No phone is connected**; with pairing off, **Phone pairing is off**. [needs: phone]
- [ ] D-DOCK-29 Dock on the left or right. How: `ame desktop dock edge left`, then `right`. Expect: the dock moves to that physical edge in every language; cards and previews open beside it. [changes setting: put back with `ame desktop dock edge bottom`]
- [ ] D-DOCK-30 Main screen only. How: `ame desktop dock screens primary`. Expect: only the main screen has a dock. [changes setting: put back with `ame desktop dock screens every`] [needs: two screens]
- [ ] D-DOCK-31 Per-screen apps. How: put an app's window on the second screen. Expect: that screen's dock shows it beside the pinned ones. [needs: two screens]
- [ ] D-DOCK-32 Autohide. How: `ame desktop dock autohide touch`, maximize a window. Expect: windows use the whole screen; the dock slides away while one touches it and comes back when the pointer pushes the edge. [changes setting: put back with `ame desktop dock autohide off`]
- [ ] D-DOCK-33 This workspace's apps. How: `ame desktop dock workspace-apps on`. Expect: running apps without a window here leave the dock; a click on a pinned app whose windows are elsewhere takes you to them. [changes setting: put back with `ame desktop dock workspace-apps off`]
- [ ] D-DOCK-34 Settings list. How: `ame desktop dock`. Expect: every dock setting and its value.
- [ ] D-DOCK-35 Three fingers down. How: three fingers down on the touchpad. Expect: the windows of the app in use fanned out from the dock. [needs: touchpad]

## The Amethystora menu and the logo menu

- [ ] D-MENU-01 Amethystora menu. How: `Super+Alt+Space`. Expect: Ask an agent, Diagnose a problem, Make a widget (only while the agent is on), Theme, Background, Keybindings, Control, Manual, Web apps, Apps and system commands, System; arrows or typing filter, `Enter` chooses, `Esc` goes back.
- [ ] D-MENU-02 Menu parts. How: `amethystora-menu theme`, `background`, `keys`, `webapps`, `system`. Expect: each opens that part.
- [ ] D-MENU-03 Logo menu. How: click the logo. Expect: **About this computer**, **Manual**, **Settings**, **Software centre** (Bazaar), **Extensions**, **System monitor** (Mission Center), **Terminal** (kitty) and **Containers** (DistroShelf); labels in the session's language; an entry whose app is not installed is hidden, never installed from the click.
- [ ] D-MENU-04 Logo menu entries. How: click each entry in turn. Expect: each opens the right app or window, nothing errors, and the menu closes.

## Tiling

- [ ] D-TILE-01 Strip. How: open three windows on one workspace. Expect: side by side at full height, a new one to the right of the focused one, no overlap; a frame marks the focused window; the strip scrolls to keep it in view.
- [ ] D-TILE-02 Focus left and right. How: `Super+Left` / `Super+Right`. Expect: focus moves, the strip glides with no stop-start even when pressed quickly in a row.
- [ ] D-TILE-03 Up and down in a column. How: `Super+I` to stack two windows, `Super+Up` / `Super+Down`. Expect: focus moves within the column.
- [ ] D-TILE-04 First and last. How: `Super+Home`, `Super+End`. Expect: the first / last window on the workspace.
- [ ] D-TILE-05 Slide the strip. How: hold `Super+]` (and `Super+[`), let go of Super. Expect: the strip slides while held; focus lands on the window most in view.
- [ ] D-TILE-06 Move a column. How: `Super+Ctrl+Left` / `Right` (and `Super+Ctrl+,` / `.`). Expect: the window with its whole column moves along the strip.
- [ ] D-TILE-07 Move in a column. How: `Super+Ctrl+Up` / `Down` in a stacked column. Expect: the window moves up / down its column.
- [ ] D-TILE-08 Pull in, push out. How: `Super+I`, `Super+O`, `Super+Shift+O`. Expect: the window on the right joins this column below; the bottom one gets its own column; this window gets its own column.
- [ ] D-TILE-09 Widths. How: `Super+R` three times, `Super+Alt+R`. Expect: 38 %, 50 %, 62 % of the screen less margins, then back.
- [ ] D-TILE-10 Heights. How: in a stacked column `Super+Shift+R`, `Super+Alt+Shift+R`. Expect: the window's height steps through the heights and back.
- [ ] D-TILE-11 Step size. How: `Super+plus`, `Super+minus`, with Shift. Expect: wider / narrower; taller / shorter by a step.
- [ ] D-TILE-12 Fill the width. How: `Super+F` twice; then maximize from the title bar. Expect: fills the width and back; maximizing fills the width too.
- [ ] D-TILE-13 Centre. How: `Super+C`. Expect: the window centred on the screen.
- [ ] D-TILE-14 Focus mode. How: `Super+Shift+C` repeatedly. Expect: the strip scrolls a focused window just into view, to the centre, to the edge; an icon in the top bar shows which.
- [ ] D-TILE-15 Open position. How: `Super+Shift+W` repeatedly, open a window each time. Expect: right, left, below; an icon in the top bar shows which.
- [ ] D-TILE-16 New window. How: `Super+N` in Files. Expect: a new window of the same app.
- [ ] D-TILE-17 Carry. How: hold `Super`, press `T`, move with arrows / Page keys, let go. Expect: the window travels and drops where you let go.
- [ ] D-TILE-18 Float. How: `Super+Ctrl+Escape`; the window menu's **Float above the strip**. Expect: it floats above the strip; again puts it back.
- [ ] D-TILE-19 Hide floating windows. How: `Super+Alt+Escape` twice. Expect: every floated window hides, then returns.
- [ ] D-TILE-20 Dialogs float. How: open a Save dialog. Expect: it floats above the strip.
- [ ] D-TILE-21 On every workspace. How: window menu › Always on Visible Workspace. Expect: leaves the strip and stays where it is.
- [ ] D-TILE-22 Edge preview. How: push the pointer against the left or right edge with windows beyond. Expect: a small view of the window beyond; a click there goes to it.
- [ ] D-TILE-23 Drag in the strip. How: drag a window by its title bar and drop it elsewhere in the strip; scroll the wheel while holding it. Expect: it lands where dropped; the wheel moves along the strip.
- [ ] D-TILE-24 Resize onto another screen. How: resize a window by its edge onto another screen. Expect: it floats. [needs: two screens]
- [ ] D-TILE-25 Touchpad swipes. How: three fingers sideways, up, down. Expect: slides the strip; opens the overview; recent workspaces as a pile of cards. [needs: touchpad]
- [ ] D-TILE-26 Workspace cards. How: `Super+Page Up` / `Page Down`. Expect: the previous / next workspace with the cards shown in a row.
- [ ] D-TILE-27 Previous workspaces. How: `` Super+Ctrl+` `` several times. Expect: the window goes to the workspace you were on before, one more back each press, round again at the end.
- [ ] D-TILE-28 Live switcher (unbound). How: bind **live-alt-tab** in Tiling settings › Keyboard, use it. Expect: GNOME's switcher, the window chosen drawn where its strip would scroll it, over a fog. [changes setting: put back with Back to the default]
- [ ] D-TILE-29 Close and others. How: `Super+W`, `Super+H`, `Shift+F11`, `Super+Backspace` then arrows. Expect: close; minimize; full screen keeping the title bar; resize with the arrow keys.
- [ ] D-TILE-30 Shortcut collision kept. How: `ame desktop layout classic`, then `tiling`; check `Super+Up` in classic. Expect: GNOME's shortcuts the tiling took are given back in classic. [changes setting: put back with `ame desktop layout tiling`]

## Tiling settings window

- [ ] D-TILESET-01 Open. How: `ame desktop tiling-settings`, or Control › Desktop › **Tiling settings**. Expect: a window with pages Windows, Motion, Workspaces, Keyboard, Window rules; every change applies at once.
- [ ] D-TILESET-02 Gaps. How: Windows › Gaps: between windows, left and right, below the top bar, bottom. Expect: each spacing changes live. [changes setting: put back with Back to the default]
- [ ] D-TILESET-03 Focus frame. How: Windows › Focus frame: how far it stands out, corner roundness; 0. Expect: the frame round the focused window changes; 0 draws none; never further than the gap. [changes setting: put back with Back to the default]
- [ ] D-TILESET-04 New windows and places. How: Windows › where new windows open; the places Super+Shift+W goes through (right, left, start, end, below, above). Expect: open position and the key's cycle follow. [changes setting: put back with Back to the default]
- [ ] D-TILESET-05 Default scroll mode. How: Windows › how a workspace scrolls to a window (into view, centre, edge). Expect: every workspace goes back to it. [changes setting: put back with Back to the default]
- [ ] D-TILESET-06 Width and height steps. How: Windows › widths and heights (`38%, 50%, 62%` or `800px`). Expect: `Super+R` and `Super+Shift+R` step through the new values. [changes setting: put back with Back to the default]
- [ ] D-TILESET-07 Fill width share and maximize. How: the width `Super+F` gives; **Maximizing fills the width** off. Expect: `Super+F` fills that share; maximize covers the whole screen. [changes setting: put back with Back to the default]
- [ ] D-TILESET-08 Animation time. How: Motion › glide time 1 s, then 0. Expect: windows glide slowly; at once. [changes setting: put back with Back to the default]
- [ ] D-TILESET-09 Slide speeds. How: Motion › the speed of `Super+[`/`]` and of dragging against a side. Expect: faster or slower sliding. [changes setting: put back with Back to the default]
- [ ] D-TILESET-10 Map and darkening. How: Motion › map size (0 shows none), darkening. Expect: while moving around, a map of the strip and the other windows darkened. [changes setting: put back with Back to the default]
- [ ] D-TILESET-11 Screen edges. How: Motion › show the window beyond, size, click goes to it, after N ms, and on to the next. Expect: the edge behaves as chosen. [changes setting: put back with Back to the default]
- [ ] D-TILESET-12 Swipes. How: Motion › gestures on/off, fingers (3 or 4) for sliding and for workspaces, sensitivity, friction. Expect: the swipes follow. [changes setting: put back with Back to the default] [needs: touchpad]
- [ ] D-TILESET-13 Top bar icons. How: Motion › the focus-mode and open-position icons off. Expect: the two icons leave the top bar. [changes setting: put back with Back to the default]
- [ ] D-TILESET-14 Workspace name in the top bar. How: Motion › show the workspace's name. Expect: the name shows (each other screen its own); a click opens the overview, the right button renames, the wheel changes workspace. [changes setting: put back with Back to the default]
- [ ] D-TILESET-15 Position line. How: Motion › line under the top bar. Expect: a line shows where the focused window is in the strip; each other screen has one at its top. [changes setting: put back with Back to the default]
- [ ] D-TILESET-16 Overview filters. How: Motion › only the floating windows; leave them out. Expect: the overview shows only / leaves out floating windows. [changes setting: put back with Back to the default]
- [ ] D-TILESET-17 Overview close animation. How: Motion › coming back at once / gliding / fading in. Expect: closing the overview brings the strip to the focused window that way. [changes setting: put back with Back to the default]
- [ ] D-TILESET-18 Alt+Tab preview size. How: Motion › size of windows in Alt+Tab. Expect: larger or smaller previews. [changes setting: put back with Back to the default]
- [ ] D-TILESET-19 Wheel over the top bar. How: turn the top bar's wheel to the windows. Expect: the wheel over the bar goes to the window left / right instead of the workspace. [changes setting: put back with Back to the default]
- [ ] D-TILESET-20 Top bar per workspace. How: the default "top bar on every workspace" off. Expect: hidden on every workspace unless shown there with `Super+Ctrl+B`. [changes setting: put back with Back to the default]
- [ ] D-TILESET-21 Workspace pictures and colours. How: Workspaces › a picture and a colour for workspace 2; every-workspace picture; GNOME's wallpaper off. Expect: workspace 2 shows its picture (or its colour alone), its colour frames its card while going through workspaces; the glass still blurs GNOME's own wallpaper. [changes setting: put back with Back to the default]
- [ ] D-TILESET-22 Workspace folder. How: Workspaces › a folder for workspace 3, open a terminal there. Expect: the terminal starts in that folder. [changes setting: put back with Back to the default]
- [ ] D-TILESET-23 Keyboard page. How: Keyboard › click a shortcut, press new keys. Expect: GNOME asks once whether the window may have the desktop's keys (allow); the new keys work at once; a shortcut used twice is marked "Also used by …". [changes setting: put back with Back to the default]
- [ ] D-TILESET-24 Window rules. How: Window rules › Add a rule: class `org.gnome.Calculator`, float. Open Calculator. Expect: it opens floating; `/pattern/` and `*` work; Remove this rule takes it away. [changes setting: put back with Remove this rule]
- [ ] D-TILESET-25 Layout switch. How: the tiling on/off switch in the window. Expect: off is the classic layout at once. [changes setting: put back with `ame desktop layout tiling`]

## Several screens

- [ ] D-SCREENS-01 One workspace per screen. How: with two screens. Expect: each shows its own workspace; moving the pointer to the other screen makes its workspace current with no animation. [needs: two screens]
- [ ] D-SCREENS-02 Page keys per screen. How: `Super+Page Down` on each screen. Expect: goes through that screen's workspaces and the empty ones; the chosen one stays on that screen. [needs: two screens]
- [ ] D-SCREENS-03 Workspace by number. How: `Super+4` for a workspace last on the other screen. Expect: it comes up on its screen and the pointer goes there. [needs: two screens]
- [ ] D-SCREENS-04 Focus and move between screens. How: `Super+Shift+Left`/`Right`; `Super+Shift+Ctrl+Left`/`Right`. Expect: focus the other screen; move the window there. [needs: two screens]
- [ ] D-SCREENS-05 Swap and move workspaces. How: `Super+Alt+Left`/`Right`; `Ctrl+Alt+Shift+Left`/`Right`. Expect: swap this screen's workspace with the other's; move it there (needs one workspace more than screens). [needs: two screens]
- [ ] D-SCREENS-06 Second bar's workspaces. How: click a workspace on the second screen's bar. Expect: it shows on that screen; one another screen shows swaps places with it. [needs: two screens]
- [ ] D-SCREENS-07 Unplug and replug. How: unplug the screen you are working on, then plug it back. Expect: the most recent workspace of the other screen becomes current; replugged, it shows the workspace it had. [needs: two screens]
- [ ] D-SCREENS-08 Dynamic workspaces. How: Settings › Multitasking › dynamic. Expect: a workspace a screen shows is kept even when empty; always one more than screens. [needs: two screens] [changes setting: put back with fixed workspaces]
- [ ] D-SCREENS-09 Classic with two screens. How: `ame desktop layout classic`. Expect: the other screens' bars show the clock alone. [needs: two screens] [changes setting: put back with `ame desktop layout tiling`]
- [ ] D-SCREENS-10 Mixed scales. How: one HiDPI and one normal screen. Expect: bars, dock, glass and pointer sharp and the right size on each. [needs: two screens, HiDPI]

## Classic windows

- [ ] D-CLASSIC-01 Switch to classic. How: `ame desktop layout classic` (or Control › Desktop › **Window layout**). Expect: windows float and overlap; `Super+Up` maximizes, `Super+Down` restores, `Super+Left`/`Right` halves, `Super+Shift+Left`/`Right` next screen. [changes setting: put back with `ame desktop layout tiling`]
- [ ] D-CLASSIC-02 Layout offer. How: on a new account's first login, wait ninety seconds. Expect: a notification offers classic windows; only its button acts.
- [ ] D-CLASSIC-03 Snap layouts by drag. How: in classic, drag a window to the top of the screen. Expect: six layouts (halves, two thirds and a third, thirds, quarters, the middle, the whole screen); hover a part shows where; let go places it; dragging away gives the old size back.
- [ ] D-CLASSIC-04 Snap with Super+Z. How: `Super+Z`, arrows, `Enter`. Expect: same layouts; the arrows move between parts.
- [ ] D-CLASSIC-05 Snap off. How: `ame desktop windows snap off`. Expect: no layouts. [changes setting: put back with `ame desktop windows snap on`]
- [ ] D-CLASSIC-06 Typing switcher. How: `Alt+Tab`, keep Alt, type letters. Expect: every window in a live grid; only matching ones stay; the grid stays open after letting go until `Enter` or `Esc`.
- [ ] D-CLASSIC-07 Switcher off. How: `ame desktop windows switcher off`. Expect: GNOME's switcher. [changes setting: put back with `ame desktop windows switcher on`]
- [ ] D-CLASSIC-08 Show desktop on click. How: `ame desktop windows show-desktop on`, click empty wallpaper. Expect: windows slide to the edges leaving slivers; any click or key brings them back; a sliver click brings that window forward. [changes setting: put back with `ame desktop windows show-desktop off`]
- [ ] D-CLASSIC-09 Places. How: in classic, place a window, plug a screen, move it, unplug and replug. Expect: windows return to their places per arrangement; `ame desktop windows places forget` forgets. [needs: two screens]
- [ ] D-CLASSIC-10 Places off. How: `ame desktop windows places off`. Expect: windows open where GNOME puts them. [changes setting: put back with `ame desktop windows places on`]
- [ ] D-CLASSIC-11 Spread for the desktop. How: three-finger spread, then pinch. Expect: shows the desktop; brings windows back. [needs: touchpad]

## Windows in both layouts

- [ ] D-WIN-01 Hold Super. How: hold `Super` a second alone; tap `Super`. Expect: a card of the main shortcuts as set on this machine, numbers on the dock, fading on release; a quick tap opens the overview.
- [ ] D-WIN-02 Hold delay and off. How: `ame desktop windows hold-super 1500`; `ame desktop windows hold-super off`. Expect: waits 1.5 s; no card. [changes setting: put back with `ame desktop windows hold-super on` and `ame desktop windows hold-super 1000`]
- [ ] D-WIN-03 Hot corners. How: `ame desktop windows corner top-right overview` (and `desktop`, `lock`, `note`, `notifications` on other corners), push into each corner. Expect: fires after a short push past the edge, never by passing by; corners next to another screen do nothing. [changes setting: put back with `ame desktop windows corner top-right none` for each]
- [ ] D-WIN-04 Pinch for the app grid. How: three-finger pinch. Expect: the app grid. `ame desktop windows gesture pinch off` stops it. [needs: touchpad] [changes setting: put back with `ame desktop windows gesture pinch on`]
- [ ] D-WIN-05 Four fingers for Today. How: four fingers left, then right. Expect: Today and notifications open, then close. [needs: touchpad]
- [ ] D-WIN-06 Gesture switches. How: `ame desktop windows gesture spread off`, `down off`, `today off`. Expect: each gesture stops. [changes setting: put back with `on` for each] [needs: touchpad]
- [ ] D-WIN-07 Keep a copy in view. How: window menu (`Alt+Space`) › **Keep a copy in view**; drag the copy to another corner; click it. Expect: the window goes out of sight and a small live copy stays on top on every workspace; the click brings the real one back.
- [ ] D-WIN-08 Dim the others. How: `ame desktop windows dim on`. Expect: windows behind the focused one a little darker. [changes setting: put back with `ame desktop windows dim off`]
- [ ] D-WIN-09 Settings list. How: `ame desktop windows`. Expect: each windows setting and how it is set now.
- [ ] D-WIN-10 Window lights. How: look at any title bar; hover the buttons; unfocus the window. Expect: three lights on the right, amber, green, red (minimize, maximize, close) in every theme, signs on hover, grey while unfocused.
- [ ] D-WIN-11 Super+` and Super+Tab. How: two windows of one app, `` Super+` ``; `Super+Tab`. Expect: switch between that app's windows; switch application.
- [ ] D-WIN-12 Super+Escape. How: in a virtual machine window that grabbed the keyboard, `Super+Escape`. Expect: the keyboard comes back to the desktop.

## Force quit and not responding

- [ ] D-QUIT-01 Force quit list. How: `Super+Ctrl+Shift+Escape`. Expect: running apps with processor and memory each uses (counting what it started); one not responding first, marked **Not responding**.
- [ ] D-QUIT-02 Force quit an app. How: pick an app, **Force quit**. Expect: the card asks once more, naming it; then only that app ends. [risky: unsaved work in that app is lost]
- [ ] D-QUIT-03 Force quit off. How: `ame desktop force-quit off`. Expect: the key does nothing. [changes setting: put back with `ame desktop force-quit on`]
- [ ] D-QUIT-04 Not-responding dialog. How: freeze an app (`kill -STOP PID` of a GTK app, then click into it). Expect: a dialog over its window, in the image's look, with **Wait** first (`Esc` and `Enter` wait) and **Force quit**; with the agentic features on, **Ask the agent why**. Then `kill -CONT PID`.
- [ ] D-QUIT-05 GNOME's own dialog. How: `ame desktop frozen-dialog off`, repeat. Expect: GNOME's own question. [changes setting: put back with `ame desktop frozen-dialog on`]

## Motion

- [ ] D-MOTION-01 Droplet minimize. How: `Super+H`, then click its dock icon. Expect: the window gathers into a drop of glass and arcs into its dock icon, a ring ripples as it lands; it rises back and swells into the window.
- [ ] D-MOTION-02 Turn round half-way. How: minimize, click the icon again mid-flight. Expect: the window turns round from where it is.
- [ ] D-MOTION-03 Open from the dock. How: open an app from the dock. Expect: its window grows out of its icon.
- [ ] D-MOTION-04 Shrink. How: `ame desktop minimize shrink`. Expect: GNOME's own shrink-and-fade. [changes setting: put back with `ame desktop minimize droplet`]
- [ ] D-MOTION-05 Depth switch. How: `Super+2`, `Super+1`. Expect: windows travel a whole screen, the wallpaper a third, windows step back a little.
- [ ] D-MOTION-06 Slide. How: `ame desktop workspace-switch slide`. Expect: each workspace slides in whole. [changes setting: put back with `ame desktop workspace-switch depth`]
- [ ] D-MOTION-07 Reduce motion. How: `ame desktop comfort reduce-motion on`; minimize and switch workspaces. Expect: windows fade in place; workspaces crossfade. [changes setting: put back with `ame desktop comfort reduce-motion off`]
- [ ] D-MOTION-08 Animations off. How: Settings › Accessibility › animations off. Expect: nothing moves; no transition, no reveal. [changes setting: put back with animations on]
- [ ] D-MOTION-09 Animation speed. How: watch the overview and menus open. Expect: GNOME's animations a little quicker than stock (0.6 slow-down factor), never cut off.

## Workspaces and saved sets

- [ ] D-WS-01 Number keys. How: `Super+1`…`Super+6`, `Super+Shift+3`. Expect: go to that workspace; take the window there.
- [ ] D-WS-02 Window to next / previous. How: `Super+Ctrl+Page Up` / `Page Down`. Expect: the window goes to the previous / next workspace.
- [ ] D-WS-03 Swap workspaces. How: `Super+Ctrl+Alt+Left` / `Right`. Expect: the workspace swaps with its neighbour, windows and name included; stops at the first and last place.
- [ ] D-WS-04 Drag a window to a workspace card. How: in the overview, drag a window onto a workspace picture at the top. Expect: it moves there.
- [ ] D-WS-05 Save a set. How: right-click a workspace › **Save this workspace**. Expect: a set named after the workspace under **Sets** in the same menu.
- [ ] D-WS-06 Open a set. How: close the windows, click the set. Expect: its apps start and each window goes to its place on the workspace you are on (if empty, else the next empty one); with tiling, same order and widths; nothing closed.
- [ ] D-WS-07 Forget a set. How: the cross on a set. Expect: forgotten.
- [ ] D-WS-08 Sets off. How: `ame desktop sets off`. Expect: no Sets in the menu; saved sets kept for `on`. [changes setting: put back with `ame desktop sets on`]

## Themes

For each theme: switch to it, then look at the top bar, a menu, quick settings, a notification (`notify-send Test
Body`), the dock, a GTK 4 app (Files), a GTK 3 app, kitty and an Amethystora app (Control). Expect each to take the
theme's colours, style, font, icon pack and pointer (themes.md's tables), text readable everywhere. Put back with
`amethystora-theme set amethystora` at the end.

- [ ] D-THEME-01 Amethystora. How: `amethystora-theme set amethystora`. Expect: dark, floating style, Quicksand and JetBrains Mono, Glass icons, Halo pointer, a cut stone's facets wallpaper; GTK 3 apps in the Amethystora GTK theme.
- [ ] D-THEME-02 Amethystora Light. How: `amethystora-theme set amethystora-light`. Expect: light, islands style, Quicksand, Glass for light icons, Ink pointer; the dock has a faint dark tint.
- [ ] D-THEME-03 Catppuccin Mocha. How: `ame desktop theme catppuccin`. Expect: dark, segments style, Nunito and Fira Code, Duotone icons, Halo; pastel peaks under a moon.
- [ ] D-THEME-04 Catppuccin Latte. How: `amethystora-theme set catppuccin-latte`. Expect: light, islands style, Nunito, Clay icons, Ink.
- [ ] D-THEME-05 Everforest. How: `amethystora-theme set everforest`. Expect: dark, floating, Manrope and DM Mono, Muted icons; misty pines.
- [ ] D-THEME-06 Gruvbox. How: `amethystora-theme set gruvbox`. Expect: dark, terminal style, JetBrains Mono everywhere, Duotone icons; a desert sunset.
- [ ] D-THEME-07 Matte Black. How: `amethystora-theme set matte-black`. Expect: dark, hairline style, Geist and Geist Mono, Line icons; an eclipse; success, warning and error colours still green, yellow and red.
- [ ] D-THEME-08 Nord. How: `amethystora-theme set nord`. Expect: dark, islands, Inter and IBM Plex Mono, Muted icons; an aurora over a mountain lake.
- [ ] D-THEME-09 Rosé Pine Dawn. How: `amethystora-theme set rose-pine-dawn`. Expect: light, capsule style, Figtree and Victor Mono, Clay icons, Ink; status colours readable.
- [ ] D-THEME-10 Tokyo Night. How: `amethystora-theme set tokyo-night`. Expect: dark, neon style, Space Grotesk and Space Mono, Neon icons; a neon city in the rain.
- [ ] D-THEME-11 Theme picker. How: `Super+Ctrl+Shift+Space`. Expect: a picker of the ten themes; choosing one applies it.
- [ ] D-THEME-12 Light and dark partner. How: `Super+Ctrl+D` on Amethystora, on Catppuccin, on Nord. Expect: Amethystora ↔ Amethystora Light; Mocha ↔ Latte; Nord (no partner) to Amethystora Light.
- [ ] D-THEME-13 Dark Style toggle. How: the Dark Style button in quick settings. Expect: the switch is revealed with the transition, like a theme switch.
- [ ] D-THEME-14 Open apps after a switch. How: switch with Files and Text Editor open. Expect: the shell, Amethystora's apps and kitty change at once; Files and Text Editor at their next start; a notification says so.
- [ ] D-THEME-15 Control's Appearance page. How: Control › Appearance. Expect: every theme shown in its own colours, the current theme's wallpapers; picking one applies it.
- [ ] D-THEME-16 High Contrast. How: Settings › Accessibility › High Contrast on, open Files. Expect: libadwaita's own high-contrast colours, the palette steps aside, glass solid with strong outlines; back when off. [changes setting: put back with High Contrast off]
- [ ] D-THEME-17 Your own theme. How: `mkdir -p ~/.config/amethystora/themes/sunset && cp /usr/share/amethystora/themes/amethystora/colors.toml ~/.config/amethystora/themes/sunset/ && amethystora-theme set sunset`. Expect: applied; four drawn wallpapers (a glow, hills, contours, ribbons) in its colours. [changes setting: put back with `amethystora-theme set amethystora` and remove the folder]
- [ ] D-THEME-18 Theme list and current. How: `amethystora-theme list`, `amethystora-theme current`, `amethystora-theme reload`. Expect: the themes with the current one marked; its name; reapplied with the transition.

## Wallpapers, accents and colours

- [ ] D-WALL-01 Next wallpaper. How: `Super+Ctrl+Space` (or `ame desktop background`). Expect: the theme's next picture, revealed by the transition; round again after the last.
- [ ] D-WALL-02 Your own pictures. How: put a JPG in `~/.config/amethystora/backgrounds/amethystora/`, `amethystora-theme bg list`. Expect: listed after the theme's own; reachable with `Super+Ctrl+Space`.
- [ ] D-WALL-03 Daylight. How: look at the theme's first wallpaper at different times of day. Expect: dawn, day, dusk, night of the same place, fading between them; the lock screen shows the same; theme stays light or dark.
- [ ] D-WALL-04 Daylight off. How: `ame desktop daylight off`. Expect: the first wallpaper stays as drawn. [changes setting: put back with `ame desktop daylight on`]
- [ ] D-WALL-05 Accent. How: `ame desktop accent jade`. Expect: buttons, switches, checked boxes, selected rows, the current workspace, sliders and focus rings in jade, in the shell, kitty's prompt and Amethystora's apps at once; other apps at next start; kept when switching themes. [changes setting: put back with `ame desktop accent theme`]
- [ ] D-WALL-06 Every accent. How: try each of the twelve accents on a dark and a light theme. Expect: label on accent and accent text readable in each.
- [ ] D-WALL-07 Colours from the wallpaper. How: `ame desktop colours vivid`, then `soft`, `mono`. Expect: ground and accent taken from the picture (mono keeps the theme's accent); light stays light. [changes setting: put back with `ame desktop colours off`]
- [ ] D-WALL-08 Accent per workspace. How: `ame desktop accent-per-workspace on`, go through workspaces. Expect: workspace 1 the theme's, then Sky, Coral, Jade, Amber, Orchid; the shell and Amethystora's apps restyle once the slide ends, not during it. [changes setting: put back with `ame desktop accent-per-workspace off`]
- [ ] D-WALL-09 A workspace's accent. How: right-click a workspace label › **Accent**; `ame desktop accent-per-workspace 3 coral`. Expect: that workspace takes it. [changes setting: put back with `ame desktop accent-per-workspace off`]

## Transitions

- [ ] D-TRANS-01 Grow. How: switch theme with the pointer in a corner. Expect: the screen holds still, then the new desktop opens in a circle from the pointer with a glow in the accent along the edge, about 1.2 s; never held more than five seconds.
- [ ] D-TRANS-02 Outer. How: `ame desktop transition outer`, switch wallpaper. Expect: the new desktop closes in on the pointer from the edges. [changes setting: put back with `ame desktop transition grow`]
- [ ] D-TRANS-03 Wipe. How: `ame desktop transition wipe`. Expect: a soft edge sweeps across at an angle. [changes setting: put back with `ame desktop transition grow`]
- [ ] D-TRANS-04 Wave. How: `ame desktop transition wave`. Expect: the same with a wavy edge. [changes setting: put back with `ame desktop transition grow`]
- [ ] D-TRANS-05 Fade. How: `ame desktop transition fade`. Expect: a plain crossfade. [changes setting: put back with `ame desktop transition grow`]
- [ ] D-TRANS-06 Random. How: `ame desktop transition random`, switch a few times. Expect: one of the first four at any angle each time. [changes setting: put back with `ame desktop transition grow`]
- [ ] D-TRANS-07 None. How: `ame desktop transition none`. Expect: the wallpaper fades as GNOME fades it. [changes setting: put back with `ame desktop transition grow`]
- [ ] D-TRANS-08 Duration. How: `ame desktop transition grow 3000`; Control's slider. Expect: the reveal takes about three seconds. [changes setting: put back with `ame desktop transition grow 1200`]
- [ ] D-TRANS-09 Picker. How: `ame desktop transition`. Expect: a list to pick from.
- [ ] D-TRANS-10 GNOME Settings change. How: change the wallpaper in GNOME Settings › Appearance. Expect: the same transition.
- [ ] D-TRANS-11 One transition per switch. How: switch theme. Expect: a single reveal, not several in a row (wallpaper, colours, icons arrive together).

## Styles

Set each style with `ame desktop style <name>` and check every surface. Put back with `ame desktop style theme`.

- [ ] D-STYLE-01 Floating: top bar. How: `ame desktop style floating`. Expect: one rounded bar held off the screen's edge (about 8 px down, 10 px in), thin accent border, glass behind it.
- [ ] D-STYLE-02 Floating: menus and quick settings. How: open the calendar and quick settings. Expect: rounded glass menus whose corners match their glass.
- [ ] D-STYLE-03 Floating: notifications and OSD. How: `notify-send Test`, press volume. Expect: rounded banners and pill.
- [ ] D-STYLE-04 Floating: dock. How: look at the dock. Expect: the dock's rounded pill.
- [ ] D-STYLE-05 Floating: windows and apps. How: open Files, a GTK 3 app. Expect: windows keep their own corners (floating leaves applications their own).
- [ ] D-STYLE-06 Islands: top bar. How: `ame desktop style islands`. Expect: a floating pill behind each part of the bar (left, middle, right), the workspaces as dots, no pane behind the whole bar.
- [ ] D-STYLE-07 Islands: menus and quick settings. How: open them. Expect: soft, large corners (menus about 18 px, quick settings about 28 px), menu rows rounded.
- [ ] D-STYLE-08 Islands: notifications, OSD, dialogs. How: a banner, volume, a password prompt (`pkexec true`, cancel). Expect: rounded about 22–26 px.
- [ ] D-STYLE-09 Islands: dock. How: look. Expect: soft corners matching the style.
- [ ] D-STYLE-10 Islands: windows and apps. How: Files, Settings. Expect: windows about 16 px corners; buttons, entries, switches, cards rounded by the style; a linked group rounded only at its ends; split buttons meet.
- [ ] D-STYLE-11 Hairline: top bar. How: `ame desktop style hairline`. Expect: a thin, solid strip of a bar with a fine line, crisp corners.
- [ ] D-STYLE-12 Hairline: menus and quick settings. How: open them. Expect: small corners (about 6–10 px), fine 1 px lines.
- [ ] D-STYLE-13 Hairline: notifications, OSD, dialogs. How: as above. Expect: crisp, small corners.
- [ ] D-STYLE-14 Hairline: dock. How: look. Expect: about 10 px corners.
- [ ] D-STYLE-15 Hairline: windows and apps. How: Files. Expect: windows about 6 px; controls drawn with an outline line.
- [ ] D-STYLE-16 Capsule: top bar. How: `ame desktop style capsule`. Expect: the clock in a dark capsule, the rest of the bar bare over the wallpaper, its buttons pills.
- [ ] D-STYLE-17 Capsule: menus and quick settings. How: open them. Expect: large corners (24–32 px), everything a pill.
- [ ] D-STYLE-18 Capsule: notifications, OSD, dialogs. How: as above. Expect: the OSD a full pill, banners and dialogs about 30 px.
- [ ] D-STYLE-19 Capsule: dock. How: look. Expect: a pill.
- [ ] D-STYLE-20 Capsule: windows and apps. How: Files. Expect: windows about 18 px; pill buttons.
- [ ] D-STYLE-21 Terminal: top bar. How: `ame desktop style terminal`. Expect: a solid square bar in the monospace font, lined edges.
- [ ] D-STYLE-22 Terminal: menus and quick settings. How: open them. Expect: square corners, lined edges, monospace.
- [ ] D-STYLE-23 Terminal: notifications, OSD, dialogs. How: as above. Expect: square and lined.
- [ ] D-STYLE-24 Terminal: dock. How: look. Expect: square, lined.
- [ ] D-STYLE-25 Terminal: windows and apps. How: Files, Settings. Expect: square windows and controls drawn with a line; radio buttons still round; Amethystora's apps square too (their pills squared).
- [ ] D-STYLE-26 Segments: top bar. How: `ame desktop style segments`. Expect: the bar in blocks of the theme's colours, each label readable on its block, the end blocks rounded on their outer side.
- [ ] D-STYLE-27 Segments: menus and quick settings. How: open them. Expect: about 12–18 px corners.
- [ ] D-STYLE-28 Segments: notifications, OSD, dialogs. How: as above. Expect: about 14–16 px.
- [ ] D-STYLE-29 Segments: dock. How: look. Expect: about 18 px corners.
- [ ] D-STYLE-30 Segments: windows and apps. How: Files. Expect: windows about 12 px; the segments' own GTK lines.
- [ ] D-STYLE-31 Neon: top bar. How: `ame desktop style neon`. Expect: dark glass outlined and glowing in the accent.
- [ ] D-STYLE-32 Neon: menus and quick settings. How: open them. Expect: outlined in the accent with a glow; corners match the outline.
- [ ] D-STYLE-33 Neon: notifications, OSD, dialogs. How: as above. Expect: outlined and glowing.
- [ ] D-STYLE-34 Neon: dock. How: look. Expect: outlined in the accent.
- [ ] D-STYLE-35 Neon: windows and apps. How: Files. Expect: windows about 10 px; the neon glow lines on controls.
- [ ] D-STYLE-36 Overview, switcher and prompts per style. How: in each style open the overview, `Alt+Tab`, and a polkit prompt. Expect: tiles, switcher and prompt drawn in the style's shape.
- [ ] D-STYLE-37 Style picker and Control. How: `ame desktop style` alone; Control › Appearance › **Style**. Expect: a list; picking applies at once.
- [ ] D-STYLE-38 Style kept across themes. How: `ame desktop style neon`, switch theme. Expect: stays neon; `ame desktop style theme` follows the theme again. [changes setting: put back with `ame desktop style theme`]
- [ ] D-STYLE-39 Amethystora apps follow the style. How: open Control in each style. Expect: card corners scale with the style; avatars, dots and knobs stay circles.

## Glass and comfort

- [ ] D-GLASS-01 Prism. How: `ame desktop glass prism`. Expect: less tint, more colour, a lit top edge, a soft glint at the top left, the accent gathering along the bottom; the wallpaper blurred behind the bar, dock, menus, notifications and the overview.
- [ ] D-GLASS-02 Frost. How: `ame desktop glass frost`. Expect: thick milky glass with an even tint. [changes setting: put back with `ame desktop glass prism`]
- [ ] D-GLASS-03 Clear. How: `ame desktop glass clear`. Expect: the thinnest glass, brightest rim, a glow up the left side; darkens by itself where text needs it. [changes setting: put back with `ame desktop glass prism`]
- [ ] D-GLASS-04 Readable on any wallpaper. How: set a very bright picture, then a dark one. Expect: text on the glass readable on both (the glass darkens, on a light theme lightens).
- [ ] D-GLASS-05 Unfocused windows. How: two overlapping windows (classic) or side by side. Expect: windows not in use slightly see-through on glass showing the wallpaper, not the window behind; the focused one solid.
- [ ] D-GLASS-06 Glass follows the wallpaper. How: change the wallpaper. Expect: every glass surface shows the new picture blurred, on every screen its own.
- [ ] D-GLASS-07 Rim bends the picture. How: look closely at a glass edge. Expect: the picture bends inwards near the edge; continuous corners.
- [ ] D-COMFORT-01 Reduce transparency. How: `ame desktop comfort reduce-transparency on`. Expect: every glass surface in solid theme colours, nothing blurred. [changes setting: put back with `ame desktop comfort reduce-transparency off`]
- [ ] D-COMFORT-02 Increase contrast. How: `ame desktop comfort increase-contrast on`. Expect: solid glass, strong outlines in the text colour, dimmed text plain, outlined controls. [changes setting: put back with `ame desktop comfort increase-contrast off`]
- [ ] D-COMFORT-03 Power saver. How: power menu › Power Saver. Expect: the glass solid and every animation half its time while on. [changes setting: put back with Balanced]
- [ ] D-COMFORT-04 Status. How: `ame desktop comfort`. Expect: how each of the three is set.

## Fonts, icons and screen corners

- [ ] D-FONT-01 Interface font. How: `ame desktop font "Space Grotesk"`, switch theme. Expect: kept whatever the theme; documents a size up; `ame desktop font` alone offers the themes' fonts and Adwaita Sans. [changes setting: put back with `ame desktop font theme`]
- [ ] D-FONT-02 Monospace font. How: `ame desktop mono-font "Fira Code"`. Expect: kitty changes at once, the terminal style's bar too. [changes setting: put back with `ame desktop mono-font theme`]
- [ ] D-ICONS-01 Each icon pack. How: `ame desktop icons glass`, `glass-light`, `neon`, `neon-light`, `duotone`, `line`, `clay`, `muted`; look at the app grid, dock and Files. Expect: each draws Amethystora's apps, GNOME's apps, folders and file types in its own colours; no missing icons. [changes setting: put back with `ame desktop icons theme`]
- [ ] D-ICONS-02 Makers' logos untouched. How: look at Firefox, Steam, VSCodium icons under each pack. Expect: the maker's own icon, bare, no tile.
- [ ] D-ICONS-03 Packs read on light themes. How: Glass for light and Clay on a light theme. Expect: every icon readable on the light ground.
- [ ] D-ICONS-04 Folder colours. How: Files › Scripts › Folder colour › each colour, then No colour. Expect: the folder takes the colour in Files and in the icon pack; No colour gives special folders their emblem back. [changes setting: put back with No colour]
- [ ] D-CORNERS-01 Rounded screen corners. How: `ame desktop screen-corners on`. Expect: a small black curve in each corner of the laptop's own screen, over everything; external screens square. [changes setting: put back with `ame desktop screen-corners off`] [needs: laptop]

## Terminal and prompt look

- [ ] D-TERM-01 kitty opens. How: `Super+Return`, `Ctrl+Alt+T`, `Ctrl+Alt+Return`. Expect: kitty with a title bar and close button, in the theme's colours.
- [ ] D-TERM-02 Prompt. How: in kitty, `cd` into a git repository. Expect: Starship powerline: user@host, the folder, the branch on backgrounds of the theme's colours with arrows that never point at nothing; the command on its own line after `▶`.
- [ ] D-TERM-03 Live theme. How: switch theme with kitty open. Expect: the open kitty windows take the new colours at once.
- [ ] D-TERM-04 Greeting. How: `ame desktop greeting off`, open kitty; then `on`. Expect: the logo and summary go, then come back. [changes setting: put back with `ame desktop greeting on`]

## Clipboard extension

- [ ] D-CLIPX-01 Menu controls. How: open the clipboard menu in the top bar. Expect: a search field (**Type here to search...**), the items, **Private mode** switch, **Clear history**, **Settings**; empty shows **Clipboard is empty**.
- [ ] D-CLIPX-02 Pin and unpin. How: pin an item with its pin button, then delete it. Expect: pinned items stay first and survive Clear history; deleting a pinned one asks **Delete pinned item?**.
- [ ] D-CLIPX-03 Clear history. How: **Clear history**. Expect: asks first; pinned items kept. [risky: clears the unpinned history]
- [ ] D-CLIPX-04 Edit, paste, preview. How: an item's actions. Expect: **Edit** opens it to change, **Paste** pastes where you were typing, **Preview Image** for a picture.
- [ ] D-CLIPX-05 Settings window. How: **Settings**. Expect: pages for behaviour, limits, excluded apps (with a picker of installed apps), shortcuts; matches the theme.
- [ ] D-CLIPX-06 Excluded app. How: add Text Editor to excluded apps, copy from it. Expect: not recorded while it is focused. [changes setting: put back by removing it]
- [ ] D-CLIPX-07 No keyring. How: on an account whose keyring cannot open. Expect: **Not saved: there is no keyring to keep it in**.

## Widgets

- [ ] D-WIDGET-01 Nothing by default. How: look at the top bar of a new account. Expect: no widget until one is added; `amethystora-widgets` lists none.
- [ ] D-WIDGET-02 From an example. How: `amethystora-widgets new hello hello`. Expect: a widget appears in the bar as soon as it is saved, no log-out; label, icon and menu as printed. [changes setting: put back with `amethystora-widgets remove hello`]
- [ ] D-WIDGET-03 Pomodoro and do-not-disturb examples. How: `amethystora-widgets new pomo pomodoro`, `amethystora-widgets new dnd do-not-disturb`; use their menus. Expect: menus whose items run commands or flip switches; the dnd switch follows Do Not Disturb. [changes setting: put back with `amethystora-widgets remove pomo` and `amethystora-widgets remove dnd`]
- [ ] D-WIDGET-04 Edit reloads. How: change the hello widget's script. Expect: the bar shows the change without logging out.
- [ ] D-WIDGET-05 Broken widget. How: make the script exit 1. Expect: a warning sign in its place; click it to read what went wrong, **Fix it with the AI agent** (while the agent is on) and **Open its folder**; the desktop never freezes.
- [ ] D-WIDGET-06 Check. How: `amethystora-widgets run hello`. Expect: runs it once as the bar does and says what is wrong.
- [ ] D-WIDGET-07 Off and on. How: `amethystora-widgets off hello`, `on hello`. Expect: hidden, then shown.
- [ ] D-WIDGET-08 Restart. How: turn the widgets extension off in Extensions, `amethystora-widgets restart`. Expect: every widget restarts and the extension is on again.
- [ ] D-WIDGET-09 Make with the agent. How: with `ame agent toggle on`, Super+Alt+Space › **Make a widget**, or `amethystora-widgets make "a pomodoro timer"`. Expect: the agent asks before it writes; the widget appears once saved.
- [ ] D-WIDGET-10 Control's widget list. How: Control › Desktop › widgets. Expect: lists them, each switchable; start one from an example; make or fix with the agent.
- [ ] D-WIDGET-11 Stops while locked. How: lock and unlock. Expect: widgets stop while locked and come back.
- [ ] D-WIDGET-12 Desktop widgets. How: `ame desktop desktop-widgets on`, give a widget `"place": "desktop", "position": "top-left", "size": "large"`. Expect: a card in that corner on the wallpaper of the main screen, under the windows, not in the overview; first line large, up to six lines, icon beside the first; a click runs its click or opens its menu; not in the bar. [changes setting: put back with `ame desktop desktop-widgets off`]
- [ ] D-WIDGET-13 Desktop widgets stacked. How: two desktop widgets in one corner with `order`. Expect: stacked in that order.
- [ ] D-WIDGET-14 Desktop widgets off. How: `ame desktop desktop-widgets off`. Expect: the cards go and their commands stop running.

## AI agent on the desktop

Only while the agentic features are on (`ame agent toggle on`); put back with `ame agent toggle off`.

- [ ] D-AGENT-01 Agent launcher. How: `Super+Ctrl+Shift+A`. Expect: the agent opens in a terminal (first time it offers to install the chosen agent).
- [ ] D-AGENT-02 Ask about a selection. How: select text in any window, `Super+Shift+A`. Expect: a card shows the start of the text with **What do you want to know?**, **Cancel** and **Ask**; Ask opens the agent in a terminal with the text quoted as data.
- [ ] D-AGENT-03 Nothing selected. How: `Super+Shift+A` with nothing selected. Expect: **Select some text first**.
- [ ] D-AGENT-04 Key unbound while off. How: `ame agent toggle off`, `Super+Shift+A`. Expect: nothing.
- [ ] D-AGENT-05 Selection key off. How: `ame agent selection off`. Expect: the key does nothing. [changes setting: put back with `ame agent selection on`]
- [ ] D-AGENT-06 Agent in the pill. How: with `ame agent tools on`, have the agent change a setting. Expect: the live pill's agent activity lists each change (**Changes so far**) with **Undo** and **Stop the agent**; Undo reverts it, Stop ends the tool server. [changes setting: put back with `ame agent tools off`]
- [ ] D-AGENT-07 Agent pill off. How: `ame agent pill off`. Expect: no agent activity in the pill. [changes setting: put back with `ame agent pill on`]
- [ ] D-AGENT-08 Frozen app: Ask the agent why. How: freeze an app (`kill -STOP PID`, click it). Expect: the not-responding dialog has **Ask the agent why**, which opens the agent on it without ending it. Then `kill -CONT PID`.

## Uninstalling from the app menu

- [ ] D-BAZAAR-01 Uninstall entry. How: right-click a Flatpak app in the app grid or dock. Expect: **Uninstall** and the app's page in Bazaar.
- [ ] D-BAZAAR-02 Uninstall dialog. How: **Uninstall**. Expect: **Uninstall <App>?** with **Keep its data** or **Delete its data**, explaining each, in the theme's colours; afterwards **<App> is uninstalled** and whether its data was kept. [risky: removes the app]
- [ ] D-BAZAAR-03 Not a Flatpak. How: right-click Firefox (an image app). Expect: no Uninstall, or **Nothing to uninstall**.

## First look and new accounts

- [ ] D-FIRST-01 Pick a look on first login. How: log in to a new account. Expect: Control's **Pick a look** page comes forward once GNOME's welcome dialog closes, never over a window you chose or the Tour. [logout]
- [ ] D-FIRST-02 Welcome manual. How: new account's first login. Expect: the Manual opens on its welcome page once. [logout]
- [ ] D-FIRST-03 Image extensions come back. How: turn Amethystora UI off in Extensions, then update the image. Expect: after the update it is on again. [risky: turning Amethystora UI off removes the desktop until it is back on]

## Hotkeys not covered above

Check each against `/usr/share/amethystora/keybindings.md` (`ame desktop keybindings` prints it).

- [ ] D-KEYS-01 Keybindings list. How: `ame desktop keybindings`; Super+Alt+Space › Keybindings. Expect: the hotkeys page in the terminal.
- [ ] D-KEYS-02 Super+Shift+B. How: press it. Expect: the browser (Firefox) opens.
- [ ] D-KEYS-03 Super+Shift+F and Super+E. How: press each. Expect: a Files window; the home folder.
- [ ] D-KEYS-04 Ctrl+Shift+Esc. How: press it. Expect: Mission Center.
- [ ] D-KEYS-05 Alt+F2. How: press it, type `kitty`, Enter. Expect: GNOME's run-a-command box runs it.
- [ ] D-KEYS-06 Super+F1. How: press it. Expect: the Manual.
- [ ] D-KEYS-07 Super+Alt+N. How: press it. Expect: a quick note into Notes' inbox.
- [ ] D-KEYS-08 Super+Ctrl+Shift+C. How: press it. Expect: Control.
- [ ] D-KEYS-09 Super+L and Super+D. How: press each. Expect: locks the screen; shows the desktop.
- [ ] D-KEYS-10 Super+Shift+Space. How: with two keyboard layouts, press it. Expect: next layout. [needs: two input sources]
- [ ] D-KEYS-11 Super+Shift+V. How: press it. Expect: the clipboard history menu.
- [ ] D-KEYS-12 Print. How: press it. Expect: GNOME's screenshot bar with Amethystora's tools.
- [ ] D-KEYS-13 Ctrl+Shift+Alt+R. How: press it twice. Expect: a screen recording starts and stops.
- [ ] D-KEYS-14 Super+Escape. How: in a VM window that grabbed the keyboard. Expect: the keyboard comes back.
- [ ] D-KEYS-15 Conflicts. How: in Settings › Keyboard › shortcuts, look for duplicates of the keys above. Expect: none of the image's keys is bound twice; `Super+Alt+R` and `Super+Alt+S` are not taken by the ruler or read aloud.
- [ ] D-KEYS-16 Amethystora apps' zoom and reload. How: in Control press `Ctrl+=`, `Ctrl+-`, `Ctrl+0`, `Ctrl+R` / `F5`. Expect: everything in the window grows, shrinks, resets; it reads again.

## Other desktop settings

- [ ] D-OTHER-01 Rest reminders. How: `ame desktop breaks eyesight` (or Control's **Rest reminders**). Expect: every 20 minutes GNOME's notification to look away for 20 seconds, with **Delay**, **Skip** and **Take**; the screen fades gently when a break begins. [changes setting: put back with `ame desktop breaks off`]
- [ ] D-OTHER-02 Movement breaks. How: `ame desktop breaks movement`. Expect: a reminder to stand up for 5 minutes every 30 minutes. [changes setting: put back with `ame desktop breaks off`]
- [ ] D-OTHER-03 Text shortcuts list and remove. How: `ame desktop text-shortcut list`, then `ame desktop text-shortcut remove ';sig'`. Expect: lists the shortcuts; removes one.
- [ ] D-OTHER-04 Night Light. How: quick settings' Night Light toggle. Expect: the screen warmer at once and back; Quiet at night and Sleep follow its times. [changes setting: put back with the same toggle]
