#!/usr/bin/python3
"""Asks the accessibility tree what tests/atspi.py (the suites' own) does not print: the state of a widget.

    probe.py focused TEXT     exits 0 when a showing widget named TEXT has the keyboard focus, 1 when none has
"""

import sys

sys.path.insert(0, "/")
import atspi  # noqa: E402  (tests/vm/suites/atspi.py, mounted at /)
from gi.repository import Atspi  # noqa: E402

app = atspi.application("amethystora-phone")
if app is None or len(sys.argv) < 3 or sys.argv[1] != "focused":
    sys.exit(2)
for node, _ in atspi.walk(app):
    if atspi.showing(node) and any(sys.argv[2] in word for word in atspi.words(node)):
        if node.get_state_set().contains(Atspi.StateType.FOCUSED):
            sys.exit(0)
sys.exit(1)
