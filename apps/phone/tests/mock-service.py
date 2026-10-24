#!/usr/bin/python3
"""A stand-in for the program amethystora-connect on the session bus, for the screenshots and tests of
amethystora-phone (tests/README.md). It owns the name org.amethystora.Connect and serves the interfaces of
apps/connect/dbus/org.amethystora.Connect.xml with canned data, the way the real program answers.

    mock-service.py [--xml FILE] [--scenario NAME] [--log FILE]

Scenarios: default (four phones), pairing (a phone asks to pair), empty (no phone found yet), messages (the
phones, and the texts of the first), many (a dozen phones).

Every call a client makes is appended to the log, one JSON object a line, for a test to read back. A test
that needs the phone to do something (a pairing request arrives, the battery moves, a text comes in) calls
the mock's own interface, org.amethystora.ConnectMock on the manager's path:

    Do(s json)   {"op": "set", "device": ID, "props": {"BatteryLevel": 40}}
                 {"op": "add", "device": {...}}       {"op": "remove", "device": ID}
                 {"op": "text", "device": ID, "thread": N, "body": "..."}   an incoming text
                 {"op": "quit"}
"""

import argparse
import json
import os
import sys
import time
import zlib

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.amethystora.Connect"
PATH = "/org/amethystora/Connect"
DEVICE_PATH = PATH + "/Device/"
DEVICE = "org.amethystora.Connect.Device"
PROPS = "org.freedesktop.DBus.Properties"

MOCK_XML = """<node><interface name="org.amethystora.ConnectMock">
<method name="Do"><arg name="json" type="s" direction="in"/></method></interface></node>"""

TYPES = {"Id": "s", "Name": "s", "Type": "s", "Paired": "b", "Connected": "b", "Pairing": "s", "PairingKey": "s",
         "PairingDeadline": "x", "Address": "s", "BatteryLevel": "i", "BatteryCharging": "b", "Features": "as"}

ALL = ["ping", "battery", "notifications", "share", "clipboard", "sms", "telephony"]
NOW = time.time()


def ms(seconds_ago):
    return int((time.time() - seconds_ago) * 1000)


def path_of(device_id):
    return DEVICE_PATH + "".join(c if c.isalnum() else "_" for c in device_id)


class Phone:
    def __init__(self, id, name, kind="phone", paired=True, connected=True, battery=-1, charging=False,
                 features=None, pairing="none", key="", deadline=0, address=""):
        self.path = path_of(id)
        self.props = {"Id": id, "Name": name, "Type": kind, "Paired": paired, "Connected": connected,
                      "Pairing": pairing, "PairingKey": key, "PairingDeadline": deadline,
                      "Address": address or ("192.168.1.%d:1716" % (20 + zlib.crc32(id.encode()) % 200) if connected else ""),
                      "BatteryLevel": battery, "BatteryCharging": charging,
                      "Features": (ALL if features is None else features) if (paired and connected) else []}
        self.conversations = []
        self.messages = {}
        self.shown = {}
        self.repliable = []


def variant(name, value):
    return GLib.Variant(TYPES[name], value)


def conversation(thread, addresses, name, last, group=False, unread=False):
    return {"thread_id": thread, "addresses": addresses, "name": name, "snippet": last[0], "date": last[1],
            "unread": unread, "group": group}


def make_history(thread, who, address, count, group_members=None):
    """A long conversation, newest `count` messages going back in time, a few exchanges a day"""
    lines_in = ["Are you coming tonight?", "Running ten minutes late, sorry!", "Did you see the photos I sent?",
                "Lunch at one? There is a place with a terrace: https://example.org/terrace",
                "Thanks, that really helped.", "Call me when you are free.", "Good morning!",
                "I will bring the charger.", "Not yet. Soon, I hope.", "See you at the station, platform 4."]
    lines_out = ["Yes, see you there.", "No problem, take your time.", "On my way.", "Sounds good to me.",
                 "I will ask and let you know.", "Thank you!", "Almost there.", "Can you send me the address?"]
    out = []
    t = 60
    for i in range(count):
        outgoing = i % 3 == 1
        sender = (group_members[i % len(group_members)] if group_members and not outgoing else address)
        t += 60 * (7 if i % 4 else 190)
        out.append({"id": 1000 * thread + i, "thread_id": thread, "address": "" if outgoing else sender,
                    "name": "" if outgoing else (who if not group_members else sender),
                    "body": (lines_out if outgoing else lines_in)[(i * 7) % (len(lines_out) if outgoing else len(lines_in))],
                    "date": 0, "outgoing": outgoing, "read": True})
        out[-1]["_ago"] = t
    # Newest last: the oldest has the largest age
    out.reverse()
    for m in out:
        m["date"] = ms(m.pop("_ago"))
    return out


def build(scenario):
    phones = []
    if scenario == "empty":
        return phones
    pixel = Phone("pixel8_ada", "Ada's Pixel 8", battery=87, charging=True)
    tablet = Phone("tab_s9", "Galaxy Tab S9", "tablet", battery=54, features=["ping", "battery", "notifications", "share", "clipboard"])
    away = Phone("moto_g", "Old Moto G", paired=True, connected=False)
    nearby = Phone("pixel6a_guest", "Pixel 6a", paired=False, connected=True, battery=-1)
    phones = [pixel, tablet, away, nearby]
    if scenario == "pairing":
        phones.insert(0, Phone("sam_phone", "Sam's Phone", paired=False, connected=True, pairing="incoming", key="3F9A1C7E",
                               deadline=int(time.time()) + 26))
    if scenario == "many":
        for n in range(12):
            phones.append(Phone("extra%d" % n, "Spare phone %d" % (n + 1), battery=10 + n * 7, paired=n % 3 != 0,
                                connected=n % 2 == 0))
    # Texts: for the first phone
    threads = [
        (101, ["+1 555 0100"], "Grace Hopper", 90, False),
        (102, ["+1 555 0111"], "Alan", 40, False),
        (103, ["+1 555 0122", "+1 555 0133", "+1 555 0144"], "", 25, True),
        (104, ["+44 20 7946 0958"], "", 3, False),
        (105, ["+1 555 0155"], "Mum", 30, False),
        (106, ["+1 555 0166"], "محمد", 12, False),
    ]
    for thread, addresses, name, count, group in threads:
        members = addresses if group else None
        history = make_history(thread, name or addresses[0], addresses[0], count, members)
        if thread == 104:
            history = [
                {"id": 104001, "thread_id": 104, "address": addresses[0], "name": "", "body": "Your one-time code is 482913. Do not share it with anyone.", "date": ms(3600 * 5), "outgoing": False, "read": False},
                {"id": 104002, "thread_id": 104, "address": addresses[0], "name": "", "body": "Your statement is ready: https://example.org/statement?id=77&lang=en. Questions? Reply HELP.", "date": ms(1800), "outgoing": False, "read": False},
                {"id": 104003, "thread_id": 104, "address": addresses[0], "name": "", "body": "<b>Not markup</b> & <a href=\"https://evil.example\">not a link</a>", "date": ms(900), "outgoing": False, "read": False},
            ]
        if thread == 106:
            history[-1]["body"] = "مرحبا، هل أنت مستعد للغداء؟"
        pixel.messages[thread] = history
        pixel.shown[thread] = 20
        last = history[-1]
        pixel.conversations.append(conversation(thread, addresses, name, (last["body"], last["date"]), group, unread=thread in (104, 102)))
    pixel.conversations.sort(key=lambda c: -c["date"])
    pixel.repliable = [
        {"id": "pixel8_ada|0|com.example.chat|42", "app": "Chat", "title": "Grace Hopper",
         "text": "Are you coming tonight? The menu is here: https://example.org/menu and it is <i>lovely</i>."},
        {"id": "pixel8_ada|0|com.example.mail|7", "app": "Mail", "title": "Build finished", "text": "All 1,204 tests passed."},
    ]
    return phones


class Mock:
    def __init__(self, xml, scenario, log):
        self.log_file = open(log, "a", buffering=1) if log else None
        self.loop = GLib.MainLoop()
        self.info = Gio.DBusNodeInfo.new_for_xml(open(xml).read())
        self.manager_iface = self.info.lookup_interface("org.amethystora.Connect")
        self.device_iface = self.info.lookup_interface(DEVICE)
        self.phones = {p.props["Id"]: p for p in build(scenario)}
        self.registered = {}
        self.transfers = 0
        self.next_thread = 900
        self.props = {"Name": ("s", "Ada's laptop"), "ClipboardSend": ("b", False), "ClipboardReceive": ("b", False),
                      "ReceiveFolder": ("s", os.path.expanduser("~/Downloads/Phone"))}
        Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, self.on_bus, None, self.on_lost)

    # --- Bus ---------------------------------------------------------------------------------------------

    def on_lost(self, connection, name):
        print("could not own", name, file=sys.stderr)
        self.loop.quit()

    def on_bus(self, connection, name):
        self.conn = connection
        connection.register_object(PATH, self.manager_iface, self.manager_call, self.manager_get, None)
        connection.register_object(PATH, Gio.DBusNodeInfo.new_for_xml(MOCK_XML).interfaces[0], self.mock_call, None, None)
        for phone in self.phones.values():
            self.register(phone, announce=False)

    def register(self, phone, announce=True):
        self.registered[phone.path] = self.conn.register_object(phone.path, self.device_iface, self.device_call, self.device_get, None)
        if announce:
            self.emit(PATH, "org.amethystora.Connect", "DeviceAdded", GLib.Variant("(o)", (phone.path,)))

    def emit(self, path, interface, signal, params):
        self.conn.emit_signal(None, path, interface, signal, params)

    def log(self, **entry):
        if self.log_file:
            self.log_file.write(json.dumps(entry) + "\n")

    def changed(self, phone, **values):
        phone.props.update(values)
        changed = {k: variant(k, v) for k, v in values.items()}
        self.emit(phone.path, PROPS, "PropertiesChanged", GLib.Variant("(sa{sv}as)", (DEVICE, changed, [])))

    def fail(self, invocation, why="the phone is not connected"):
        invocation.return_dbus_error("org.amethystora.Connect.Error.NotAvailable", why)

    # --- The program -------------------------------------------------------------------------------------

    def manager_get(self, connection, sender, path, interface, prop):
        kind, value = self.props[prop]
        return GLib.Variant(kind, value)

    def manager_call(self, connection, sender, path, interface, method, params, invocation):
        self.log(method=method, args=params.unpack())
        if method == "GetDevices":
            invocation.return_value(GLib.Variant("(ao)", ([p.path for p in self.phones.values()],)))
        else:
            invocation.return_value(None)

    def mock_call(self, connection, sender, path, interface, method, params, invocation):
        invocation.return_value(None)
        request = json.loads(params.unpack()[0])
        op = request.get("op")
        phone = self.phones.get(request.get("device")) if isinstance(request.get("device"), str) else None
        if op == "set" and phone:
            self.changed(phone, **request["props"])
        elif op == "add":
            spec = dict(request["device"])
            new = Phone(spec.pop("id"), spec.pop("name"), **spec)
            self.phones[new.props["Id"]] = new
            self.register(new)
        elif op == "remove" and phone:
            self.conn.unregister_object(self.registered.pop(phone.path))
            del self.phones[phone.props["Id"]]
            self.emit(PATH, "org.amethystora.Connect", "DeviceRemoved", GLib.Variant("(o)", (phone.path,)))
        elif op == "text" and phone:
            self.add_message(phone, request["thread"], request["body"], outgoing=False)
        elif op == "quit":
            self.loop.quit()

    # --- A phone -----------------------------------------------------------------------------------------

    def device_get(self, connection, sender, path, interface, prop):
        phone = next(p for p in self.phones.values() if p.path == path)
        return variant(prop, phone.props[prop])

    def device_call(self, connection, sender, path, interface, method, params, invocation):
        phone = next(p for p in self.phones.values() if p.path == path)
        args = params.unpack()
        self.log(method=method, device=phone.props["Id"], args=args)
        connected = phone.props["Connected"] and phone.props["Paired"]
        needs = {"Ping", "SendFiles", "SendUrl", "SendText", "ReplyToNotification", "GetRepliable", "RequestConversations",
                 "RequestMessages", "SendMessage", "MuteRinger"}
        if method in needs and not connected:
            return self.fail(invocation)
        if method == "Pair":
            self.changed(phone, Pairing="outgoing", PairingKey="A1B2C3D4", PairingDeadline=int(time.time()) + 30)
            invocation.return_value(None)
        elif method == "AcceptPairing":
            self.changed(phone, Paired=True, Pairing="none", PairingKey="", PairingDeadline=0,
                         Features=ALL if phone.props["Connected"] else [])
            invocation.return_value(None)
        elif method in ("RejectPairing", "Unpair"):
            self.changed(phone, Paired=False, Pairing="none", PairingKey="", PairingDeadline=0, Features=[])
            invocation.return_value(None)
        elif method == "SendFiles":
            ids = [self.start_transfer(phone, uri) for uri in args[0]]
            invocation.return_value(GLib.Variant("(as)", (ids,)))
        elif method == "RequestConversations":
            invocation.return_value(None)
            GLib.timeout_add(600, self.later, phone, "ConversationsChanged", None)
        elif method == "ListConversations":
            invocation.return_value(GLib.Variant("(aa{sv})", ([self.vardict(c, {"thread_id": "x", "addresses": "as", "name": "s", "snippet": "s", "date": "x", "unread": "b", "group": "b"}) for c in phone.conversations[: args[0]]],)))
        elif method == "RequestMessages":
            thread, before, count = args
            invocation.return_value(None)
            have = len(phone.messages.get(thread, []))
            phone.shown[thread] = min(have, (20 if before == 0 else phone.shown.get(thread, 20) + count))
            GLib.timeout_add(500, self.later, phone, "MessagesChanged", thread)
        elif method == "ListMessages":
            thread, limit = args
            shown = phone.messages.get(thread, [])[-phone.shown.get(thread, 20):]
            invocation.return_value(GLib.Variant("(aa{sv})", ([self.vardict(m, {"id": "x", "thread_id": "x", "address": "s", "name": "s", "body": "s", "date": "x", "outgoing": "b", "read": "b"}) for m in shown[-limit:]],)))
        elif method == "SendMessage":
            addresses, body, thread = args
            invocation.return_value(None)
            if thread == 0:
                self.next_thread += 1
                thread = self.next_thread
                phone.messages[thread] = []
                phone.conversations.insert(0, conversation(thread, addresses, "", (body, ms(0))))
                phone.shown[thread] = 20
                GLib.timeout_add(900, self.later, phone, "ConversationsChanged", None)
            GLib.timeout_add(1200, lambda: self.add_message(phone, thread, body, outgoing=True) and False)
        elif method == "GetRepliable":
            invocation.return_value(GLib.Variant("(aa{sv})", ([self.vardict(n, {"id": "s", "app": "s", "title": "s", "text": "s"}) for n in phone.repliable],)))
        else:
            invocation.return_value(None)

    @staticmethod
    def vardict(values, types):
        return {k: GLib.Variant(types[k], v) for k, v in values.items() if k in types}

    def later(self, phone, signal, thread):
        params = GLib.Variant("(x)", (thread,)) if signal == "MessagesChanged" else None
        self.emit(phone.path, DEVICE, signal, params)
        return False

    def add_message(self, phone, thread, body, outgoing):
        messages = phone.messages.setdefault(thread, [])
        conv = next((c for c in phone.conversations if c["thread_id"] == thread), None)
        address = conv["addresses"][0] if conv else ""
        messages.append({"id": 50000 + len(messages), "thread_id": thread, "address": "" if outgoing else address,
                         "name": "" if outgoing else (conv["name"] if conv else ""), "body": body, "date": ms(0),
                         "outgoing": outgoing, "read": outgoing})
        phone.shown[thread] = phone.shown.get(thread, 20) + 1
        if conv:
            conv.update(snippet=body, date=ms(0), unread=not outgoing)
            phone.conversations.sort(key=lambda c: -c["date"])
        self.later(phone, "MessagesChanged", thread)
        self.later(phone, "ConversationsChanged", None)
        return True

    def start_transfer(self, phone, uri):
        self.transfers += 1
        tid = "t%d" % self.transfers
        name = os.path.basename(GLib.filename_from_uri(uri)[0]) if uri.startswith("file://") else uri
        try:
            total = os.stat(GLib.filename_from_uri(uri)[0]).st_size
        except OSError:
            total = 3_400_000
        total = max(total, 1)
        steps = [("started", 0), ("progress", total // 4), ("progress", total // 2), ("progress", total * 3 // 4), ("finished", total)]
        for at, (state, done) in enumerate(steps):
            GLib.timeout_add(400 + at * 900, lambda s=state, d=done: self.transfer_signal(phone, tid, name, d, total, s) and False)
        return tid

    def transfer_signal(self, phone, tid, name, done, total, state):
        self.emit(phone.path, DEVICE, "Transfer", GLib.Variant("(ssbxxs)", (tid, name, False, done, total, state)))
        return True


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", default=os.path.join(here, "..", "..", "connect", "dbus", "org.amethystora.Connect.xml"))
    parser.add_argument("--scenario", default="default")
    parser.add_argument("--log", default=os.environ.get("MOCK_LOG"))
    args = parser.parse_args()
    mock = Mock(args.xml, args.scenario, args.log)
    mock.loop.run()


if __name__ == "__main__":
    main()
