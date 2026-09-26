# Getting started

A few minutes now and the machine looks after itself from then on. None of these steps is
required, but each one is worth doing once.

## 1. Let Secure Boot trust the image

If Secure Boot is on, the kernel modules built into the image (DisplayLink docks, virtual cameras)
only load once their signing key is enrolled. The first boot may already have asked you to; if it
did not, run:

```bash
ujust enroll-secure-boot-key
```

At the next restart a blue screen appears, the MOK manager. Choose **Enroll MOK**, then
**Continue**, then **Yes**, and type the password `amethystora`. The screen uses a US (QWERTY)
keyboard layout. [Hardware](hardware.md#secure-boot) has the details.

## 2. Check that everything is on

```bash
ujust security-status
```

One screen of what the machine's security settings are actually doing, and what to do about
anything that is off. It changes nothing and asks for no password. The same report is in the app
grid as **Security Report**.

## 3. Install your apps

Open **Bazaar**, the software centre, and install what you use from Flathub. The browser is Brave;
if you would rather have Firefox or Chrome, they are in Bazaar too. [Installing
software](software.md) covers command line tools and everything else.

## 4. Make it yours

- `Super+Ctrl+Shift+Space` picks a theme. It repaints the whole desktop, the terminal and the
  prompt at once. [Themes](themes.md).
- `Super+T` tiles the focused window onto a grid. Try it now; it is the fastest way to arrange a
  screen. [Getting around](desktop.md).
- `Super+Alt+Space` opens the Amethystora menu, which reaches everything in this manual from the
  keyboard.

## 5. Set up a backup

```bash
ujust setup-backup
```

A daily backup to somewhere that ransomware on this machine cannot delete from. The recipe walks you
through choosing where. [Security](security.md#backups).

## 6. Learn the keys

The [Hotkeys](../keybindings.md) page is worth a read. Keep it open on a second workspace for your
first week.

## Then forget about it

Updates arrive by themselves and are applied the next time you restart. Shut the machine down when
you are done for the day and it stays current without you thinking about it.
[Updates](updates.md) explains what happens and how to undo one.
