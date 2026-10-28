#!/usr/bin/python3
"""A media player for the lab: owns org.mpris.MediaPlayer2.vmlab on the session bus and says it plays "Night Drive" by
"Lumen". Every method called is written, one per line, to $XDG_RUNTIME_DIR/vmlab-mpris.log; PlayPause toggles between
Playing and Paused, Stop stops. Started by suite 17 (the live pill) and by the headless harness. Never in the image."""

import os
import sys

from gi.repository import Gio, GLib

NAME = "org.mpris.MediaPlayer2.vmlab"
PATH = "/org/mpris/MediaPlayer2"
LOG = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "vmlab-mpris.log")
XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

state = {"status": "Playing", "track": 0, "started": GLib.get_monotonic_time(), "position": 102_000_000}
TRACKS = [("Night Drive", ["Lumen"]), ("Morning Light", ["Lumen"])]
connection = None


def metadata():
    title, artists = TRACKS[state["track"] % len(TRACKS)]
    return {
        "mpris:trackid": GLib.Variant("o", f"/org/vmlab/track/{state['track']}"),
        "mpris:length": GLib.Variant("x", 238_000_000),
        "xesam:title": GLib.Variant("s", title),
        "xesam:artist": GLib.Variant("as", artists),
    }


def position():
    if state["status"] == "Playing":
        return state["position"] + GLib.get_monotonic_time() - state["started"]
    return state["position"]


def prop(interface, name):
    values = {
        "CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", False),
        "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", "VM lab player"),
        "DesktopEntry": GLib.Variant("s", ""), "SupportedUriSchemes": GLib.Variant("as", []),
        "SupportedMimeTypes": GLib.Variant("as", []),
        "PlaybackStatus": GLib.Variant("s", state["status"]), "Metadata": GLib.Variant("a{sv}", metadata()),
        "Position": GLib.Variant("x", position()), "CanGoNext": GLib.Variant("b", True),
        "CanGoPrevious": GLib.Variant("b", True), "CanPlay": GLib.Variant("b", True),
        "CanPause": GLib.Variant("b", True), "CanSeek": GLib.Variant("b", False), "CanControl": GLib.Variant("b", True),
    }
    return values.get(name)


def changed(*names):
    props = {n: prop("org.mpris.MediaPlayer2.Player", n) for n in names}
    connection.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                           GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", props, [])))


def set_status(status):
    state["position"] = position()
    state["started"] = GLib.get_monotonic_time()
    state["status"] = status
    changed("PlaybackStatus")


def method(conn, sender, path, interface, name, params, invocation):
    with open(LOG, "a", encoding="utf-8") as log:
        log.write(name + "\n")
    if name == "PlayPause":
        set_status("Paused" if state["status"] == "Playing" else "Playing")
    elif name == "Play":
        set_status("Playing")
    elif name == "Pause":
        set_status("Paused")
    elif name == "Stop":
        set_status("Stopped")
    elif name in ("Next", "Previous"):
        state["track"] += 1 if name == "Next" else -1
        state["position"] = 0
        state["started"] = GLib.get_monotonic_time()
        changed("Metadata")
    invocation.return_value(None)


def get_property(conn, sender, path, interface, name):
    return prop(interface, name)


def main():
    global connection
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    for interface in node.interfaces:
        connection.register_object(PATH, interface, method, get_property, None)
    Gio.bus_own_name_on_connection(connection, NAME, Gio.BusNameOwnerFlags.NONE, None, None)
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    loop = GLib.MainLoop()
    if seconds > 0:
        GLib.timeout_add_seconds(seconds, loop.quit)
    loop.run()


if __name__ == "__main__":
    main()
