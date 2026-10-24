#!/usr/bin/python3
"""A stand-in for the desktop's notification server (org.freedesktop.Notifications) for the interop test: it
writes every call to a JSON-lines file and lets the test press a button or close a notification by D-Bus,
the way a person would."""
import json
import sys
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

LOG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/notifications.jsonl"

XML = """
<node>
  <interface name="org.freedesktop.Notifications">
    <method name="Notify">
      <arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
      <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
      <arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/>
    </method>
    <method name="CloseNotification"><arg type="u" direction="in"/></method>
    <method name="GetCapabilities"><arg type="as" direction="out"/></method>
    <method name="GetServerInformation">
      <arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/>
    </method>
    <signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
    <signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
  </interface>
  <interface name="org.amethystora.FakeNotifications">
    <method name="Invoke"><arg type="u" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Dismiss"><arg type="u" direction="in"/></method>
  </interface>
</node>
"""

state = {"next": 1, "bus": None}


def log(record):
    record["time"] = time.time()
    with open(LOG, "a") as f:
        f.write(json.dumps(record) + "\n")


def on_call(conn, sender, path, iface, method, params, invocation):
    if iface == "org.freedesktop.Notifications":
        if method == "Notify":
            app, replaces, icon, summary, body, actions, hints, timeout = params.unpack()
            nid = replaces if replaces else state["next"]
            if not replaces:
                state["next"] += 1
            log({"call": "Notify", "id": nid, "replaces": replaces, "app": app, "icon": icon, "summary": summary, "body": body,
                 "actions": actions, "hints": {k: str(v) for k, v in hints.items()}, "timeout": timeout})
            invocation.return_value(GLib.Variant("(u)", (nid,)))
        elif method == "CloseNotification":
            nid = params.unpack()[0]
            log({"call": "CloseNotification", "id": nid})
            conn.emit_signal(None, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "NotificationClosed", GLib.Variant("(uu)", (nid, 3)))
            invocation.return_value(None)
        elif method == "GetCapabilities":
            invocation.return_value(GLib.Variant("(as)", (["body", "actions", "body-markup"],)))
        elif method == "GetServerInformation":
            invocation.return_value(GLib.Variant("(ssss)", ("fake", "amethystora", "1", "1.2")))
    else:
        if method == "Invoke":
            nid, action = params.unpack()
            log({"call": "Invoke", "id": nid, "action": action})
            conn.emit_signal(None, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked", GLib.Variant("(us)", (nid, action)))
        elif method == "Dismiss":
            nid = params.unpack()[0]
            log({"call": "Dismiss", "id": nid})
            conn.emit_signal(None, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "NotificationClosed", GLib.Variant("(uu)", (nid, 2)))
        invocation.return_value(None)


def on_bus(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    for iface in node.interfaces:
        conn.register_object("/org/freedesktop/Notifications", iface, on_call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.Notifications", Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
