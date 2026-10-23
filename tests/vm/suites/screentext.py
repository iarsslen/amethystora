#!/usr/bin/python3
"""screentext.py SENTENCE: a GTK 4 window on Wayland that covers the screen and shows SENTENCE in large black
letters on white, the picture 22-screen-text.sh has Gradia read. Runs until it is stopped.
"""
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, Gtk  # noqa: E402

SENTENCE = sys.argv[1]
CSS = b"""
window, label { background: #ffffff; color: #000000; }
label { font-family: sans-serif; font-size: 54px; font-weight: bold; }
"""


def activate(app):
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    window = Gtk.ApplicationWindow(application=app, title="vmlab screen text")
    window.set_child(Gtk.Label(label=SENTENCE))
    window.fullscreen()
    window.present()


app = Gtk.Application(application_id="org.amethystora.VmlabScreenText", flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", activate)
app.run([sys.argv[0]])
