# Getting started

A few minutes now and the machine looks after itself from then on. None of these steps is
required, but each one is worth doing once.

## 1. Let Secure Boot trust the image

If Secure Boot is on, the kernel modules built into the image (DisplayLink docks, virtual cameras)
only load once their signing key is enrolled. The first boot may already have asked you to; if it
did not, run:

```bash
ame security secure-boot
```

At the next restart a blue screen appears, the MOK manager. Choose **Enroll MOK**, then
**Continue**, then **Yes**, and type the password `amethystora`. The screen uses a US (QWERTY)
keyboard layout. [Hardware](hardware.md#secure-boot) has the details.

## 2. Check that everything is on

```bash
ame security status
```

One screen of what the machine's security settings are actually doing, and what to do about
anything that is off. It changes nothing and asks for no password. The same report is in the app
grid as **Security**, which scans for viruses too ([Security](security.md#scanning-for-viruses)).

## 3. Install your apps

The apps Amethystora comes with (Calculator, Text Editor, Extension Manager and the rest) install by
themselves the first time the machine is online, and appear in the app grid as each one finishes.
To have them at once, run `ame apps flatpaks`. Uninstall any you do not want; they stay uninstalled.

Then open **Bazaar**, the software centre, and install what you use from Flathub. The browser is Firefox;
if you would rather have Chrome or Brave, they are in Bazaar too. [Installing
software](software.md) covers command line tools and everything else.

Coming from another Amethystora machine that was backed up? `ame restore-setup` puts back its
apps, containers, extensions and theme from the backup ([Backups](security.md#backups)). Kept your
setup in a file? `ame setup apply <file>` does the same from it ([Your setup in a file](setup.md)).

## 4. Make it yours

- `Super+Ctrl+Shift+Space` picks a theme. It repaints the whole desktop, the terminal and the
  prompt at once. [Themes](themes.md).
- Windows tile on their own, side by side on a strip that scrolls. Open two or three apps and move
  between them with `Super+Left` and `Super+Right`. [Tiling windows](desktop.md#tiling-windows).
  If you would rather have windows that float and overlap, `ame desktop layout classic` switches to
  them ([Classic windows](desktop.md#classic-windows)).
- `Super+Alt+Space` opens the Amethystora menu, which reaches everything in this manual from the
  keyboard.
- **Control** (`Super+Ctrl+Shift+C`, **Control** in the app grid) has Amethystora's own settings in
  one window: the theme and wallpaper, the window layout, games, Android apps, the AI agent, the image
  and more. [Control](control.md).

## 5. Set up a backup

```bash
ame backup
```

A daily backup to somewhere that ransomware on this machine cannot delete from. The command walks you
through choosing where. [Security](security.md#backups).

## 6. Learn the keys

The [Hotkeys](../keybindings.md) page is worth a read. Keep it open on a second workspace for your
first week.

## Then forget about it

Updates arrive by themselves and are applied the next time you restart. Shut the machine down when
you are done for the day and it stays current without you thinking about it.
[Updates](updates.md) explains what happens and how to undo one.
