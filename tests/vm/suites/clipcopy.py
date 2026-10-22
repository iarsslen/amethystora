#!/usr/bin/python3
"""clipcopy.py MODE VALUE: puts something on the clipboard from a GTK window of its own, as an app does, and serves
it for a few seconds. Wayland lets only the window with the keyboard focus set the clipboard, and GNOME does not
always give a new window the focus, or may take it back before the copy reaches it: the window covers the screen,
so that a click anywhere (91-clipboard.sh's, through keys.py) gives it the focus as a person's would, and it copies
each time it gets the focus and each time it is clicked. For 91-clipboard.sh, which runs it in the account's session.

    clipcopy.py text TEXT      plain text, from a GTK 4 window on Wayland
    clipcopy.py keepass TEXT   the same, from a window whose app id (its window class) is KeePassXC's
    clipcopy.py gtk-hint TEXT  the same, with x-kde-passwordManagerHint offered, which GTK 4 then sends empty
    clipcopy.py x11 TEXT       plain text, from a GTK 3 window on X11 (Xwayland)
    clipcopy.py secret TEXT    what a password manager copies: the text, with x-kde-passwordManagerHint "secret"

The secret copy is made on X11: on Wayland GTK, 3 and 4, sends no type without a slash in its name, as
x-kde-passwordManagerHint is (Qt, which KeePassXC is written with, does), while GNOME passes an X11 window's
targets on under their own names. The x11 copy, without the hint, is its control.

Serves for 8 seconds after its last copy. Exits 3 when the window never got the focus.
"""
import os
import sys

import gi

mode, value = sys.argv[1], sys.argv[2]
X11 = mode in ("x11", "secret")
os.environ["GDK_BACKEND"] = "x11" if X11 else "wayland"
gi.require_version("Gtk", "3.0" if X11 else "4.0")
gi.require_version("Gdk", "3.0" if X11 else "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

APP_ID = "org.keepassxc.KeePassXC" if mode == "keepass" else "org.amethystora.VmlabCopy"
status = 3
quit_after = 0


def copied(app):
    global status, quit_after
    status = 0
    if quit_after:
        GLib.source_remove(quit_after)
    quit_after = GLib.timeout_add_seconds(8, app.quit)


def provider():
    text = Gdk.ContentProvider.new_for_bytes("text/plain;charset=utf-8", GLib.Bytes.new(value.encode()))
    if mode == "gtk-hint":
        hint = Gdk.ContentProvider.new_for_bytes("x-kde-passwordManagerHint", GLib.Bytes.new(b"secret"))
        return Gdk.ContentProvider.new_union([text, hint])
    return text


def activate(app):
    window = Gtk.ApplicationWindow(application=app, title="vmlab copy")

    def copy(*_args):
        if not window.is_active():
            return
        window.get_clipboard().set_content(provider())
        copied(app)

    click = Gtk.GestureClick()
    click.connect("released", copy)
    window.add_controller(click)
    window.connect("notify::is-active", copy)
    window.fullscreen()
    window.present()
    GLib.idle_add(copy)


def activate_x11(app):
    window = Gtk.ApplicationWindow(application=app, title="vmlab copy")
    clipboard = Gdk.Atom.intern("CLIPBOARD", False)
    targets = [("UTF8_STRING", value.encode()), ("text/plain;charset=utf-8", value.encode())]
    if mode == "secret":
        targets.append(("x-kde-passwordManagerHint", b"secret"))

    def send(_window, data, info, _time):
        name, payload = targets[info]
        data.set(Gdk.Atom.intern(name, False), 8, payload)

    def copy(*_args):
        if not window.is_active():
            return
        # The targets once the window has its X11 window, which GTK adds them to
        Gtk.selection_clear_targets(window, clipboard)
        for info, (name, _payload) in enumerate(targets):
            Gtk.selection_add_target(window, clipboard, Gdk.Atom.intern(name, False), info)
        Gtk.selection_owner_set(window, clipboard, Gtk.get_current_event_time())
        copied(app)

    window.connect("selection-get", send)
    window.add_events(Gdk.EventMask.BUTTON_RELEASE_MASK)
    window.connect("button-release-event", copy)
    window.connect("notify::is-active", copy)
    window.fullscreen()
    window.show_all()
    window.present()
    GLib.idle_add(copy)


app = Gtk.Application(application_id=APP_ID, flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", activate_x11 if X11 else activate)
# Never focused: give up
GLib.timeout_add_seconds(30, lambda: status == 3 and app.quit())
app.run([sys.argv[0]])
sys.exit(status)
