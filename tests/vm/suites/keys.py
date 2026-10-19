#!/usr/bin/python3
"""keys.py STEP...: types on a keyboard of its own, which the kernel's uinput makes, as a person types: GNOME
takes it for real input, and gives the focus to what it opens. Run as root (the image keeps /dev/uinput
root's). A STEP is a key or a chord of keys joined by + (super, ctrl+shift+c, alt+tab, return), or text: to
type, its letters, digits and spaces each pressed in turn. Waits a moment after each step.

    keys.py super text:control return
"""
import fcntl
import os
import struct
import sys
import time

KEYS = {
    "esc": 1, "tab": 15, "return": 28, "enter": 28, "ctrl": 29, "shift": 42, "alt": 56, "space": 57,
    "super": 125, "backspace": 14, "up": 103, "down": 108, "left": 105, "right": 106, "f4": 62, "w": 17,
}
for i, c in enumerate("1234567890"):
    KEYS[c] = 2 + i
for row, start in (("qwertyuiop", 16), ("asdfghjkl", 30), ("zxcvbnm", 44)):
    for i, c in enumerate(row):
        KEYS[c] = start + i

UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
EV_SYN, EV_KEY = 0, 1


def emit(fd, kind, code, value):
    now = time.time()
    os.write(fd, struct.pack("llHHi", int(now), int(now % 1 * 1e6), kind, code, value))


def press(fd, codes):
    for code in codes:
        emit(fd, EV_KEY, code, 1)
        emit(fd, EV_SYN, 0, 0)
        time.sleep(0.03)
    for code in reversed(codes):
        emit(fd, EV_KEY, code, 0)
        emit(fd, EV_SYN, 0, 0)
        time.sleep(0.03)


def main(steps):
    if not steps:
        sys.exit(__doc__)
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    # Every key a keyboard has: udev calls a device a keyboard (ID_INPUT_KEYBOARD), which is what the
    # compositor reads keys from, only when it has all of the first 31
    for code in range(1, 256):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    # struct uinput_user_dev: the name, the input_id, ff_effects_max, then the four absolute-axis arrays
    os.write(fd, struct.pack("80sHHHHi", b"vmlab keyboard", 3, 0x1234, 0x5678, 1, 0) + bytes(4 * 64 * 4))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    # The compositor finds the new keyboard through udev first
    time.sleep(2)
    try:
        for step in steps:
            if step.startswith("text:"):
                for c in step[5:].lower():
                    press(fd, [KEYS["space" if c == " " else c]])
            else:
                press(fd, [KEYS[k] for k in step.lower().split("+")])
            time.sleep(1.5)
    finally:
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        os.close(fd)


main(sys.argv[1:])
