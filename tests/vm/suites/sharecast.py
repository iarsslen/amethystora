#!/usr/bin/python3
"""sharecast.py [SECONDS]: shares the screen as a video call would, through Mutter's own screen cast interface
(org.gnome.Mutter.ScreenCast on the session bus, which GNOME Shell lets a lab session call): one session recording the
whole monitor, started and held for SECONDS (20 by default). Prints "started" once Mutter has started it, and "closed"
when the session ends before its time, as the privacy dots' Stop ends it. Suite 17 and 18 (the live pill). Never in
the image."""

import sys

from gi.repository import Gio, GLib

BUS = "org.gnome.Mutter.ScreenCast"
PATH = "/org/gnome/Mutter/ScreenCast"


def call(connection, path, interface, method, args, reply):
    return connection.call_sync(BUS, path, interface, method, args, GLib.VariantType(reply) if reply else None,
                                Gio.DBusCallFlags.NONE, 10000, None)


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    loop = GLib.MainLoop()
    try:
        (session,) = call(connection, PATH, BUS, "CreateSession", GLib.Variant("(a{sv})", ({},)), "(o)").unpack()
        call(connection, session, f"{BUS}.Session", "RecordMonitor", GLib.Variant("(sa{sv})", ("", {})), "(o)")
        connection.signal_subscribe(BUS, f"{BUS}.Session", "Closed", session, None, Gio.DBusSignalFlags.NONE,
                                    lambda *a: (print("closed", flush=True), loop.quit()))
        call(connection, session, f"{BUS}.Session", "Start", None, None)
    except GLib.Error as error:
        print(f"refused: {error.message}", flush=True)
        sys.exit(2)
    print("started", flush=True)

    def done():
        try:
            call(connection, session, f"{BUS}.Session", "Stop", None, None)
        except GLib.Error:
            pass
        loop.quit()

    GLib.timeout_add_seconds(seconds, done)
    loop.run()


if __name__ == "__main__":
    main()
