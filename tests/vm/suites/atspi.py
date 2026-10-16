#!/usr/bin/python3
"""Uses an app's window as a person would, through the accessibility tree (AT-SPI) every GTK window has, for
the suites that drive one. The Amethystora apps are GTK windows: what cdp.mjs did for their Electron pages,
this does for them.

    atspi.py APP has TEXT                  0 when the window shows TEXT (a name, a label's or an entry's text)
    atspi.py APP wait SECONDS TEXT         ...waiting for it as long as that
    atspi.py APP click TEXT [ROLE]         activates the first widget named TEXT (a button, a link...)
    atspi.py APP type TEXT [ENTRY]         puts TEXT in the first entry (or the one named ENTRY)
    atspi.py APP check TEXT [on|off]       sets the check box or switch named TEXT
    atspi.py APP text                      prints everything the window says, one line each
    atspi.py APP tree                      prints the tree: role, name, states

APP is the program's name, as AT-SPI lists it (amethystora-backups). TEXT matches when a name or text
contains it. Exits 1, saying why, when what was asked for is not there.
"""

import sys
import warnings
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

# get_action_name is deprecated in favour of a name libatspi 2.60 does not have yet
warnings.filterwarnings("ignore", category=DeprecationWarning)


def application(name):
    desktop = Atspi.get_desktop(0)
    for i in range(desktop.get_child_count()):
        app = desktop.get_child_at_index(i)
        if app is not None and (app.get_name() or "") == name:
            return app
    return None


def walk(node, depth=0):
    if node is None or depth > 80:
        return
    yield node, depth
    try:
        count = node.get_child_count()
    except Exception:
        return
    for i in range(count):
        try:
            child = node.get_child_at_index(i)
        except Exception:
            continue
        yield from walk(child, depth + 1)


def text_of(node):
    try:
        if node.get_text_iface() is not None:
            return Atspi.Text.get_text(node, 0, Atspi.Text.get_character_count(node)) or ""
    except Exception:
        pass
    return ""


def words(node):
    """What a widget says: its name, and its text"""
    found = []
    for value in (node.get_name() or "", text_of(node)):
        if value and value not in found:
            found.append(value)
    return found


def showing(node):
    try:
        states = node.get_state_set()
        return states.contains(Atspi.StateType.SHOWING) or states.contains(Atspi.StateType.VISIBLE)
    except Exception:
        return True


def find(app, text, role=None):
    for node, _ in walk(app):
        if role and node.get_role_name() != role:
            continue
        if showing(node) and any(text in word for word in words(node)):
            return node
    return None


def activate(node):
    if node.get_action_iface() is None:
        return False
    count = Atspi.Action.get_n_actions(node)
    for i in range(count):
        if Atspi.Action.get_action_name(node, i) in ("click", "activate", "press", "toggle"):
            return Atspi.Action.do_action(node, i)
    return count > 0 and Atspi.Action.do_action(node, 0)


def fail(why):
    print(why, file=sys.stderr)
    sys.exit(1)


def main(argv):
    if len(argv) < 3:
        fail(__doc__)
    name, command, rest = argv[1], argv[2], argv[3:]
    app = application(name)
    if app is None and command != "wait":
        fail(f"no application named {name} on the accessibility bus")
    if command == "has":
        sys.exit(0 if find(app, rest[0]) else 1)
    if command == "wait":
        deadline = time.monotonic() + float(rest[0])
        while time.monotonic() < deadline:
            app = application(name)
            if app is not None and find(app, rest[1]):
                return
            time.sleep(0.5)
        fail(f"{name} did not show {rest[1]!r} in {rest[0]} s")
    if command == "click":
        node = find(app, rest[0], rest[1] if len(rest) > 1 else None)
        if node is None:
            fail(f"nothing to click named {rest[0]!r}")
        if not activate(node):
            fail(f"{rest[0]!r} could not be activated")
        return
    if command == "type":
        node = find(app, rest[1], "text") if len(rest) > 1 else next((n for n, _ in walk(app) if n.get_role_name() in ("text", "entry")), None)
        if node is None:
            fail("no entry to type into")
        Atspi.EditableText.set_text_contents(node, rest[0])
        return
    if command == "check":
        node = find(app, rest[0])
        if node is None:
            fail(f"nothing named {rest[0]!r}")
        want = (rest[1] if len(rest) > 1 else "on") == "on"
        checked = node.get_state_set().contains(Atspi.StateType.CHECKED)
        if checked != want:
            activate(node)
        return
    if command == "text":
        for node, _ in walk(app):
            for word in words(node):
                print(word)
        return
    if command == "tree":
        for node, depth in walk(app):
            print(f"{'  ' * depth}{node.get_role_name()} {words(node)!r}")
        return
    fail(f"no command {command}")


if __name__ == "__main__":
    main(sys.argv)
