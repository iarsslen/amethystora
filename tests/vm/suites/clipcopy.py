#!/usr/bin/python3
"""clipcopy.py MODE VALUE: puts something on the clipboard from a GTK window of its own, as an app does, and serves
it for a few seconds. Wayland lets only the window with the keyboard focus set the clipboard, so the window is
shown first. For 91-clipboard.sh, which runs it in the account's session.

    clipcopy.py text TEXT      plain text
    clipcopy.py secret TEXT    what a password manager copies: the text, with x-kde-passwordManagerHint "secret"
    clipcopy.py keepass TEXT   plain text, from a window whose app id (its window class) is KeePassXC's
"""
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

mode, value = sys.argv[1], sys.argv[2]
APP_ID = "org.keepassxc.KeePassXC" if mode == "keepass" else "org.amethystora.VmlabCopy"


def provider():
    text = Gdk.ContentProvider.new_for_bytes("text/plain;charset=utf-8", GLib.Bytes.new(value.encode()))
    if mode == "secret":
        hint = Gdk.ContentProvider.new_for_bytes("x-kde-passwordManagerHint", GLib.Bytes.new(b"secret"))
        return Gdk.ContentProvider.new_union([text, hint])
    return text


def activate(app):
    window = Gtk.ApplicationWindow(application=app, title="vmlab copy")
    window.present()

    def put():
        window.get_clipboard().set_content(provider())
        GLib.timeout_add_seconds(5, app.quit)
        return False

    GLib.timeout_add(1500, put)


app = Gtk.Application(application_id=APP_ID, flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", activate)
sys.exit(app.run([sys.argv[0]]))
