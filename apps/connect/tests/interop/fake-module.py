#!/usr/bin/python3
"""A stand-in for the shell's module (Amethystora UI's connect) for the interop test: it reads a property, so that the
program counts it as a client, says it shows the links phones share (TakeLinks), and writes every UrlReceived it is sent
to a file, one line each. The program is started with --module-exe set to this interpreter."""
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

LOG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/module.log"
NAME, PATH, IFACE = "org.amethystora.Connect", "/org/amethystora/Connect", "org.amethystora.Connect"

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def heard(_bus, _sender, _path, _iface, _signal, params):
    device, url = params.unpack()
    with open(LOG, "a") as log:
        log.write(f"UrlReceived {device} {url}\n")


bus.signal_subscribe(NAME, IFACE, "UrlReceived", PATH, None, Gio.DBusSignalFlags.NONE, heard)
bus.call_sync(NAME, PATH, "org.freedesktop.DBus.Properties", "Get", GLib.Variant("(ss)", (IFACE, "Name")), None, Gio.DBusCallFlags.NONE, 3000, None)
bus.call_sync(NAME, PATH, IFACE, "TakeLinks", GLib.Variant("(b)", (True,)), None, Gio.DBusCallFlags.NONE, 3000, None)
with open(LOG, "a") as log:
    log.write("ready\n")
GLib.MainLoop().run()
