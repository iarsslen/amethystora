#!/usr/bin/python3
"""clipcopy.py MODE VALUE: puts something on the clipboard from a GTK window of its own, as an app does, and serves
it for a few seconds. Wayland lets only the window with the keyboard focus set the clipboard, and GNOME does not
always give a new window the focus, or may take it back before the copy reaches it: the window covers the screen,
so that a click anywhere (91-clipboard.sh's, through keys.py) gives it the focus as a person's would, and it copies
each time it gets the focus and each time it is clicked. For 91-clipboard.sh, which runs it in the account's session.

    clipcopy.py text TEXT      plain text
    clipcopy.py secret TEXT    what a password manager copies: the text, with x-kde-passwordManagerHint "secret"
    clipcopy.py keepass TEXT   plain text, from a window whose app id (its window class) is KeePassXC's

Serves for 8 seconds after its last copy. Exits 3 when the window never got the focus.
"""
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

mode, value = sys.argv[1], sys.argv[2]
APP_ID = "org.keepassxc.KeePassXC" if mode == "keepass" else "org.amethystora.VmlabCopy"
status = 3
quit_after = 0


def provider():
    text = Gdk.ContentProvider.new_for_bytes("text/plain;charset=utf-8", GLib.Bytes.new(value.encode()))
    if mode == "secret":
        hint = Gdk.ContentProvider.new_for_bytes("x-kde-passwordManagerHint", GLib.Bytes.new(b"secret"))
        return Gdk.ContentProvider.new_union([text, hint])
    return text


def activate(app):
    window = Gtk.ApplicationWindow(application=app, title="vmlab copy")

    def copy(*_args):
        global status, quit_after
        if not window.is_active():
            return
        window.get_clipboard().set_content(provider())
        status = 0
        if quit_after:
            GLib.source_remove(quit_after)
        quit_after = GLib.timeout_add_seconds(8, app.quit)

    click = Gtk.GestureClick()
    click.connect("released", copy)
    window.add_controller(click)
    window.connect("notify::is-active", copy)
    window.fullscreen()
    window.present()
    GLib.idle_add(copy)
    # Never focused: give up
    GLib.timeout_add_seconds(30, lambda: status == 3 and app.quit())


app = Gtk.Application(application_id=APP_ID, flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", activate)
app.run([sys.argv[0]])
sys.exit(status)
