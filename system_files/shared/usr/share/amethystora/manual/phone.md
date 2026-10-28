# The phone link

The phone link ties an Android phone to this computer: the phone's notifications show up here, you
read and write its texts in a window, files and links go both ways, and a phone icon in the top bar
shows its battery. It speaks the protocol of the **KDE Connect** app, so that app, from the Play Store
or F-Droid, is all the phone needs. The link is Amethystora's own program, and it takes the place of
GSConnect. It is off until you turn it on, and it reaches your phone only on [networks you named
home](security.md#on-from-the-start).

## Turn it on

```bash
ame desktop phone on
```

or the **Phone pairing** switch on [Control](control.md)'s **Desktop** page. `ame desktop phone off`
stops the program and keeps it from starting at the next login: it listens for phones only while the
link is on. Nothing else is needed on this side. On the phone, install KDE Connect and give it the
permissions for what you want: notifications, texts, contacts (for names in your texts), and the phone
state (for calls).

The phone has to be on a network you named home (`ame security home-networks`, see
[Security](security.md#on-from-the-start)): the firewall keeps it out everywhere else, and this
computer only announces itself on those networks.

## Pair a phone

Open **Phone** in the app grid. Its **Phones** page lists every phone the link knows: the ones paired
with this computer, the ones that are away, and the ones nearby that are not paired yet.

1. Open KDE Connect on the phone. This computer is in its list. Ask to pair from there, or press
   **Pair** on a phone nearby, on the **Phones** page.
2. A **verification key** of eight characters shows on this computer and on the phone, and a
   notification here carries it too. **Compare them.** If they are the same, the phone in your hand
   is the one that is asking. Accept on both sides.
3. The request lapses after thirty seconds, with a count shown beside the key. A pairing is never
   accepted without you: nothing here answers for you, and a phone you do not recognise has **Reject**.

**Unpair** on a phone's card, after a question, ends it from this side and tells the phone. A phone
that unpairs from its side disappears from the list, and has to be paired again, with the key.

**Look again**, at the top of the page, announces this computer on your home networks once more and
tries the last address of every paired phone. Use it when a phone that should be there is not.

## Notifications

What the phone shows as notifications appears here as ordinary desktop notifications, while it is connected.
Those it already had when it connected are not shown again, and neither are ones it marks as ongoing, such as
a music player's or a download's progress. What a notification offers depends on the phone's app:

- **Reply**, for a message you can answer from the phone's notification: it opens a small window with the
  text and a box to answer in.
- The buttons the phone's own notification has, such as **Archive** or **Mark as read**, which do that on the
  phone.
- **Dismiss**, for one the phone lets you clear. Closing a notification here dismisses it on the phone, and
  dismissing it on the phone takes it away here.

Whatever the phone says is shown as text, never as a command: a link in a notification is not opened by
itself.

## Files and links

**Send:** select a file in Files, then **Open With → Send to Phone** (it is offered for pictures, videos,
sounds, PDFs, text files and archives, and is never what a file opens with by itself); or press **Send…** on a
phone's card, which takes any file; or the phone icon in the top bar. A window asks which phone, if there is more
than one connected, and
shows each file's progress. Folders cannot be sent, only the files in them. A link is sent from the
same window, on its **A link** tab, or from the top bar with the link on the clipboard. The phone
opens it with whatever handles it.

From a terminal:

```bash
amethystora-phone send --device ID report.pdf photo.jpg
amethystora-phone send https://example.org/menu
```

**Receive:** a file from the phone goes to `~/Downloads/Phone/` in a folder named for the phone, and
never overwrites one that is there: the second `report.pdf` is `report (1).pdf`. A notification offers
**Show in folder**, and **Open** for a picture, a text, a PDF, a sound or a video: any other kind of file is
not opened from here. Nothing opens by itself. Text or a link the phone shares comes as a notification, too,
whose **Show** opens a window with the words as text: select and copy them, and click a web address to open it
in the browser. A web link the phone shares waits in the [live pill](desktop.md#the-live-pill) until you open or
copy it; **Not now** leaves it in the notification list, with **Open** and **Copy**.

## Texts

**Messages** shows the conversations of a phone that shares its texts, and a chat for each one. Write in
the box below and press `Enter`, or `Shift+Enter` for a new line. **+** begins a conversation, with a
number, or with someone you have written to. **Load older messages** asks the phone for earlier ones.

The words of your conversations are never written to disk: the window shows what the phone has sent the link since it
connected, and a conversation comes and goes with the connection. A message you send waits as *Sending…*
until the phone shows it. There is no delivery report in the protocol: *sent* means the phone has
it, and a message the phone never shows says that it was not confirmed. A group conversation can be
read here and is answered on the phone, and a picture message shows as *Attachment*. Only the names and numbers
of the phone's contacts are kept, in a file only you can read, so that a conversation has a name; unpairing
deletes them.

## Calls

While the phone rings, a notification says who is calling, with **Mute**, which silences the ringer on
the phone. The [live pill](desktop.md#the-live-pill) shows who is calling too, with **Mute ringer**. A missed
call arrives as a notification of the phone's. The link does not change the sound on
this computer, and makes no calls.

## The clipboard

The clipboard is shared in two directions, each its own switch, and both are **off**, since a phone
that can paste into this computer's clipboard can put text where you will paste it into a password
field:

```bash
ame desktop phone clipboard send on      # what you copy here goes to the phones you paired
ame desktop phone clipboard receive on   # what a paired phone copies is put on this clipboard
```

or on [Control](control.md)'s **Desktop** page. Only text goes, and only while the screen is not locked.
Anything copied this way also appears in the [clipboard history](desktop.md#the-clipboard) like any
other copy.

## The top bar

While a paired phone is connected, a phone icon with its charge appears in the top bar, with a bolt
while it charges. Its menu has **Send files…**, **Send a link**, **Ping**, **Messages** (when the
phone shares its texts) and **Phones…**, which opens this app.

## What it does not do

The link is deliberately small. It does not let a phone run commands here, type on this computer,
control its volume or its players, or mount its storage, and it does not send this computer's
notifications to the phone. KDE Connect has features for some of those; this computer does not
advertise them, so the app on the phone shows them as unavailable.

## When something does not work

- **The phone does not show up.** Is the phone on a network you named home, and the link on
  (`ame desktop phone on`)? Press **Look again**. Some routers keep devices apart from each other
  ("client isolation") and nothing can find the phone then.
- **The key differs.** Reject it on both sides: a different key means the other side is not the one
  you chose.
- **A paired phone is not connecting.** Open KDE Connect on the phone once, and check that it is
  allowed to run in the background.
- **Messages stays empty.** The phone's KDE Connect needs the permission to read and send texts, and
  one to read contacts for names. The page says so when the phone does not share its texts at all.
- **No notifications.** On the phone, KDE Connect needs notification access, and each app you want
  mirrored has to be ticked in it.
- **After an update** from GSConnect: a phone paired with it has to be paired again, which a notification
  says once.

## In a terminal

| Command | What it does |
| --- | --- |
| `ame desktop phone [on\|off]` | Turns the link on or off |
| `ame desktop phone clipboard send\|receive [on\|off]` | Shares the clipboard one way or the other |
| `amethystora-phone` | Opens the app on the phones |
| `amethystora-phone messages [ID]` | Opens it on a phone's texts |
| `amethystora-phone send [--device ID] FILE_OR_LINK...` | Sends files, or one link |
| `amethystora-phone pair ID` | Shows the pairing of a phone, and asks for it if the phone is nearby |
