# Tests of amethystora-connect

The program is `apps/connect` (the crate `amethystora-connect`); its plan and specs are in `plans/PLAN-amethystora-connect.md`
and `plans/amethystora-connect/`. There is no GTK in it, so everything below runs on a plain Fedora with Rust, glib-networking and
gdk-pixbuf (the `amethystora-rust` container, or the Containerfile's `apps` stage, which runs all of it with
`cargo test --release --locked --workspace -- --test-threads=1`).

    cargo test -p amethystora-connect -- --test-threads=1

| Where | What it holds |
|---|---|
| `src/*.rs` (`#[cfg(test)]`) | The pure parts: framing and the packet parser with its negative cases, the identity and the names phones accept, the verification key against the spec's two vectors, the pairing machine (every flow of spec 5.3, the deadline, the flood limits), the certificate (read back by OpenSSL in the interop run), file names that cannot leave their folder, the plugins (battery, clipboard, contacts, texts, calls, a phone's notifications, share), the line reader and its limits, the stores. |
| `loopback.rs` | Two copies of the program in one process over real sockets and real TLS: discovery by datagram, the handshake, pairing with the key compared, every plugin of the first version both ways, a file each way (and cancelled, and a name from a hostile phone, and a file too large), pictures in Pictures/Phone and the photo-folder setting's two values, the phone's connectivity reports (the vectors V-CR-1 to 9 of `plans/beyond/spec-phone-files-first.md` 2.1, a property change only when a value changed, a report from a phone that did not list it dropped, the signal forgotten when it goes), unpairing, a hostile peer made from the crate's own parts. The spec's transcript. |
| `security.rs` | The findings of the security review (`plans/amethystora-connect/review-security-opus.md`) as attacks that must fail: a second connection that takes a pending pairing over, a flood of prompts from one and from many addresses, a forged protocol 7 datagram, connections that stall a payload, and, on a session bus of its own (`dbus-daemon`; skipped without it), who may call what, what is sent to whom, and which networks are home as a firewalld stand-in says. |
| `notifications.rs` | The program's notifications against a stand-in for the desktop's notification server: a button is not a dismissal (what a shell does), the server being slow to answer, the activation token that goes with the app, Reply finding its notification. |
| `computers.rs` | Computer to computer (`plans/beyond/spec-r4-later.md`, part A): two computers that neither call nor answer each other while the switch `computers` is off, pair with the key compared once it is on, send a file and share the clipboard; off again, the other leaves the bus and its pairing is kept; a paired computer calling itself a phone is still refused; on again, it is back without a prompt. The interop run turns the switch on for Fedora's KDE Connect, a desktop, and off and on once. |
| `no_tls.rs` | A TLS library that cannot take the certificate does not make a new identity or forget a pairing. A process of its own. |
| `common/mod.rs` | What these share. |
| `interop/` | The same program against Fedora's own KDE Connect (see below). |

## The interop test

`interop/run.sh` runs the program in the `amethystora-rust` container beside Fedora's `kdeconnectd` (protocol 8, version 26.08.1 at the
time of writing) in a container of `interop/Containerfile.phone`, on a user-defined Docker network. Each has a session bus of its own;
the program's notifications go to a stand-in server (`fake-notifications.py`) that logs them and lets the test press a button; its
settings are the image's schema, compiled in the container, in a key file shared with `gsettings`.

    cargo.sh connect build -p amethystora-connect           # the binary, in the volume amethystora-target-connect
    docker build -f apps/connect/tests/interop/Containerfile.phone -t amethystora-connect-phone apps/connect/tests/interop
    bash apps/connect/tests/interop/run.sh [--keep]         # --keep leaves the containers for a look

It checks: both found each other (the phone's datagram, then our call), pairing started by the phone and by the program with the
verification keys compared on both sides, the notification's buttons, ping both ways, a file each way (checksums), a second copy of
the same file, a link, a text, a notification of the phone's desktop, unpairing from the phone, the settings written by `gsettings`,
a restart of the program (a paired phone comes back without a prompt), and garbage on the control port. And, from `plans/beyond/spec-phone-files-first.md`
2.5: no connectivity feature or signal for this peer (it sends no reports); `PhotoFolder` and a real JPEG landing in Pictures/Phone
(checksum, 0600 in a 0700 folder, a second copy, a name that climbs out with backslashes kept inside), a text file in Downloads/Phone/<name>, the
`photo-folder` key switching it to Downloads and back; and a link with a stand-in for the shell's module (`fake-module.py`, which the
program takes for the module through `--module-exe`) that takes the links: it is sent `UrlReceived` and no notification is raised,
while without it the link is a notification as before. `TARGET_VOLUME` names the volume of another build of the program. The logs of both sides are
copied to `$OUT`. What the desktop peer cannot send (battery on a machine without one, texts, calls, a reply to a notification) is the
loopback test's.

The program lets only the Phone app and the shell's module call it on the bus (by the file the caller runs); the container starts it
with `--app-exe` set to `gdbus`, which stands in for the app.
