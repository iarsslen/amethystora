# Notes and tasks

**Notes** in the app grid keeps your notes and your to-do lists in one window. Everything stays on
this computer. Nothing is synced, and the app never connects to the internet. It takes the place of
Joplin and Planify, and brings in what you already have in them (see
[Coming from Joplin or Planify](#coming-from-joplin-or-planify)).

The first time you open it, it offers to encrypt your notes with a passphrase. That is the choice it
recommends, and the rest of this page assumes you took it.

## Notes

Notes are written in Markdown and sit in notebooks, which can hold other notebooks. The editor shows
the text and the formatted note side by side. **Ctrl+E** switches between the text, both, and the
formatted note alone.

- **Checklists:** `- [ ] like this`. Tick the boxes in the formatted note.
- **Attachments:** paste an image, drop a file on the note, or use the paperclip. Pictures show in
  the note. Click any other attachment to save a copy.
- **Tags:** type in the tag row under the title and press **Enter**. Tags are listed in the sidebar.
- **Moving a note:** pick another notebook at the top of the note, or drag the note onto a notebook
  in the sidebar.
- **Earlier versions:** the clock at the top of a note. A version is kept each time you come back to
  change a note after ten minutes away from it, up to the last 30. Restoring one keeps the text it
  replaces as a version too.
- **Trash:** a note you delete goes to the trash, where you can restore it or delete it for good.
- **PDF:** the **⋯** menu of a note exports it as a PDF.

## Tasks

**Tasks** at the top of the sidebar switches to your to-do lists:

| View | Shows |
| --- | --- |
| Inbox | Tasks that are not in a project |
| Today | What is due today, and anything overdue |
| Upcoming | The week ahead, day by day, and everything after it |
| Pinned | The tasks you pinned |
| Completed | What you finished, most recent first |

Projects group tasks and can be divided into sections. Labels cut across projects. Click a task to
set its date and time, repeat, reminder, priority, labels and notes, and to add subtasks.

The **Add a task** field understands a little plain language. It takes these out of the title:

| Type | For |
| --- | --- |
| `today`, `tomorrow`, `friday`, `next week`, `2026-10-31` | The date |
| `5pm`, `17:30` | The time, with a reminder at that time |
| `every day`, `every 2 weeks`, `monthly` | A task that repeats |
| `p1` to `p4` | The priority, `p1` the highest |
| `@errand` | A label, made if it is new |
| `#Garden` | A project that exists |

Completing a repeating task moves it to its next date.

### Reminders

A task with a time can remind you, from **At the time** to **1 day before**. Reminders appear as
notifications while Notes is running. When you close the window, Notes keeps running in the background
until the reminders still to come have gone off. You can turn that off in **Settings**. Your notes are
locked while it runs like that; only the titles and times of the reminders are kept, in memory.

## Encryption

With encryption on, your notes, tasks and attachments are written to disk encrypted with AES-256-GCM,
under a random key that only your passphrase, or a [passkey](#passkeys) you add, can open. The
passphrase is stretched with scrypt, which costs 128 MiB of memory for every guess, so trying
passphrases one after another is slow.

It stays secure against quantum computers. What a quantum computer breaks is public-key cryptography
(RSA, elliptic curves), and none is used here. Against a cipher like AES, the best a quantum computer
can do is halve the key length. That leaves AES-256 at 128-bit strength, which is why AES-256 is what
NIST and the NSA's CNSA 2.0 keep for the years after quantum computers.

> **Nobody can recover a forgotten passphrase.** Not Amethystora, not an administrator, not anyone.
> Keep it somewhere safe, and keep a [backup](#backing-up).

Your notes lock:

- after 10 minutes without using Notes (**Settings**, **Lock when away**),
- when the screen locks, the computer sleeps, or the window closes,
- when you press **Ctrl+L** or **Lock** in the sidebar.

**Settings** also changes the passphrase, and turns encryption off or on again. Changing the
passphrase changes the key too, unless you turn **Change the key as well** off: everything is
encrypted anew, so that an older copy of the notes folder, from a snapshot or a backup, cannot open
what you write from now on with the old passphrase. That older copy itself still opens with it.
Passkeys have to be added again after a new key.

While your notes are encrypted, Notes reads only encrypted files: notes or an attachment put in the
folder unencrypted are not read.

### Passkeys

A FIDO2 security key (YubiKey, Thetis, or a fingerprint model such as the YubiKey Bio) can open your
notes, so that you need not type the passphrase each time. The passphrase keeps working, and it is
what opens your notes if the key is lost: a passkey is a second way in, never the only one.

To add one, plug the key in, open **Settings** and choose **Add a passkey**. Enter your passphrase and
the PIN of the key, or leave the PIN empty for a key that reads your fingerprint. The key blinks twice;
touch it each time. From then on the lock screen offers **Open with a passkey**, which asks for the
key's PIN, or your fingerprint, and a touch. Have only that key plugged in.

- **The key needs a PIN**, and a fingerprint model an enrolled finger. Set them in Firefox at
  `about:webauthn`. A touch alone never opens your notes: someone who finds the key cannot use it
  without the PIN or your finger, and the key blocks its PIN after eight wrong tries.
- **The key has to support FIDO2's `credProtect`**, with which Notes tells it to refuse the passkey
  without the PIN or a fingerprint. Notes says so when a key does not. A passkey added before Notes
  asked for it is marked in **Settings**: remove it and add it again.
- **Add a second key as a spare**, one at a time. Each is listed in **Settings**, where **Remove**
  stops it opening your notes.
- **If a key is lost**, remove it, then change the passphrase with **Change the key as well** on.
  Someone who holds the key, knows its PIN and has an older copy of your notes folder could otherwise
  open your notes with it. Add the keys you still have again afterwards.
- A [backup](#backing-up) always asks for the passphrase: passkeys are not part of it.

The key keeps nothing of your notes. It holds a secret that never leaves it, and with the PIN or
fingerprint checked it computes a value (HMAC-SHA256, FIDO2's `hmac-secret`) under which a second
copy of your notes' key is encrypted. What is on disk is still encrypted with AES-256 only.

## Backing up

Since nothing is synced, keep a copy somewhere else. In **Settings**:

- **Back up to a file** writes one `.amnotes` file with everything in it, attachments included,
  encrypted like your notes. It opens with the passphrase you had when you made it, on any computer:
  choose it under **Import**.
- **Export as Markdown** writes every note as a Markdown file in a folder per notebook, and every
  project as a checklist. These files are **not** encrypted.

Your notes themselves are in `~/.local/share/amethystora-notes`.

## Coming from Joplin or Planify

Open **Settings** and use **Import**. Importing the same file again updates what came from it rather
than adding it twice.

- **Joplin:** in Joplin, choose **File**, **Export all**, **JEX**. Import the `.jex` file.
  Notebooks, notes, tags and attachments come across. Joplin's to-dos become tasks in the inbox.
- **Planify:** in Planify, open **Preferences**, **Backup**, and create a backup. Import its `.json`
  file from `~/.var/app/io.github.alainm23.planify/data/io.github.alainm23.planify/backups`. Projects,
  sections, tasks, subtasks, labels, dates and repeats come across.
- **Markdown files** go into a notebook called **Imported**.

Once everything is across, you can remove the old apps in Bazaar, or with
`flatpak uninstall net.cozic.joplin_desktop io.github.alainm23.planify`.

## Keys

| Key | Does |
| --- | --- |
| **Ctrl+N** | A new note, or a new task in **Tasks** |
| **Ctrl+F** | Search notes or tasks |
| **Ctrl+1** / **Ctrl+2** | Notes / Tasks |
| **Ctrl+E** | Text, both, or the formatted note |
| **Ctrl+B**, **Ctrl+I**, **Ctrl+K** | Bold, italic, link |
| **Ctrl+L** | Lock |
| **Ctrl+,** | Settings |
