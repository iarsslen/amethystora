#!/usr/bin/python3
"""touchpad.py STEP...: a touchpad of its own, which the kernel's uinput makes, for the gestures a VM has no
hardware for. It carries the resolution of its axes (10 units a millimetre, a pad 100 by 70 mm), a button pad's
properties and the tools of one to five fingers, which libinput needs to call a device a touchpad with gestures.
Run as root (the image keeps /dev/uinput root's). A STEP is:

    swipe:FINGERS,DX,DY    FINGERS fingers 10 mm apart put down in the pad's middle, moved DX and DY millimetres in
                           20 steps of 8 ms, and lifted
    pinch:FINGERS,SCALE    FINGERS fingers on a circle of 20 mm radius, moved to 20 * SCALE mm in 20 steps, lifted
    sleep:MS               nothing for MS milliseconds

    touchpad.py pinch:3,0.5 swipe:4,-40,0
"""
import fcntl
import math
import os
import struct
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT, UI_SET_PROPBIT = 0x40045564, 0x40045565, 0x40045567, 0x4004556E
UI_DEV_SETUP, UI_ABS_SETUP = 0x405C5503, 0x401C5504
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
INPUT_PROP_POINTER, INPUT_PROP_BUTTONPAD = 0, 2
BTN_LEFT, BTN_TOUCH = 0x110, 0x14A
BTN_TOOL_FINGER, BTN_TOOL_QUINTTAP, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP, BTN_TOOL_QUADTAP = (
    0x145, 0x148, 0x14D, 0x14E, 0x14F)
TOOLS = {1: BTN_TOOL_FINGER, 2: BTN_TOOL_DOUBLETAP, 3: BTN_TOOL_TRIPLETAP, 4: BTN_TOOL_QUADTAP, 5: BTN_TOOL_QUINTTAP}
ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0, 1, 0x2F, 0x35, 0x36, 0x39
# Units a millimetre, and the pad's size in units
RES = 10
WIDTH, HEIGHT = 1000, 700
STEPS = 20
STEP_TIME = 0.008


def emit(fd, kind, code, value):
    now = time.time()
    os.write(fd, struct.pack("llHHi", int(now), int(now % 1 * 1e6), kind, code, value))


def create():
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for key in (BTN_LEFT, BTN_TOUCH, *TOOLS.values()):
        fcntl.ioctl(fd, UI_SET_KEYBIT, key)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
    fcntl.ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_POINTER)
    fcntl.ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_BUTTONPAD)
    # struct uinput_abs_setup: the axis, then struct input_absinfo (value, min, max, fuzz, flat, resolution)
    for code, maximum in ((ABS_X, WIDTH), (ABS_Y, HEIGHT), (ABS_MT_POSITION_X, WIDTH), (ABS_MT_POSITION_Y, HEIGHT),
                          (ABS_MT_SLOT, 4), (ABS_MT_TRACKING_ID, 65535)):
        fcntl.ioctl(fd, UI_SET_ABSBIT, code)
        resolution = RES if code in (ABS_X, ABS_Y, ABS_MT_POSITION_X, ABS_MT_POSITION_Y) else 0
        fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack("H2xiiiiii", code, 0, 0, maximum, 0, 0, resolution))
    # struct uinput_setup: the input_id, the name, ff_effects_max
    fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 0x18, 0x1234, 0x567A, 1, b"vmlab touchpad", 0))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    # libinput finds the new device through udev first
    time.sleep(2)
    return fd


class Fingers:
    def __init__(self, fd):
        self.fd = fd
        self.ids = 100

    def frame(self, points, down=False, up=False):
        fd = self.fd
        for slot, (x, y) in enumerate(points):
            emit(fd, EV_ABS, ABS_MT_SLOT, slot)
            if down:
                self.ids += 1
                emit(fd, EV_ABS, ABS_MT_TRACKING_ID, self.ids)
            if up:
                emit(fd, EV_ABS, ABS_MT_TRACKING_ID, -1)
                continue
            emit(fd, EV_ABS, ABS_MT_POSITION_X, round(min(WIDTH, max(0, x))))
            emit(fd, EV_ABS, ABS_MT_POSITION_Y, round(min(HEIGHT, max(0, y))))
        if down or up:
            emit(fd, EV_KEY, BTN_TOUCH, 0 if up else 1)
            emit(fd, EV_KEY, TOOLS[len(points)], 0 if up else 1)
        if not up:
            emit(fd, EV_ABS, ABS_X, round(min(WIDTH, max(0, points[0][0]))))
            emit(fd, EV_ABS, ABS_Y, round(min(HEIGHT, max(0, points[0][1]))))
        emit(fd, EV_SYN, 0, 0)

    def stroke(self, start, end):
        self.frame(start, down=True)
        time.sleep(0.05)
        for i in range(1, STEPS + 1):
            self.frame([(a[0] + (b[0] - a[0]) * i / STEPS, a[1] + (b[1] - a[1]) * i / STEPS)
                        for a, b in zip(start, end)])
            time.sleep(STEP_TIME)
        time.sleep(0.05)
        self.frame(end, up=True)


def swipe(fingers, fingers_count, dx, dy):
    n, dx, dy = int(fingers_count), float(dx) * RES, float(dy) * RES
    # 10 mm apart in a row across the middle, the whole row kept on the pad
    cx, cy = WIDTH / 2 - dx / 2, HEIGHT / 2 - dy / 2
    start = [(cx + (i - (n - 1) / 2) * 10 * RES, cy) for i in range(n)]
    fingers.stroke(start, [(x + dx, y + dy) for x, y in start])


def pinch(fingers, fingers_count, scale):
    n, scale = int(fingers_count), float(scale)
    radius = 20 * RES
    circle = [(math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n)) for i in range(n)]
    start = [(WIDTH / 2 + c * radius, HEIGHT / 2 + s * radius) for c, s in circle]
    end = [(WIDTH / 2 + c * radius * scale, HEIGHT / 2 + s * radius * scale) for c, s in circle]
    fingers.stroke(start, end)


def main(steps):
    if not steps:
        sys.exit(__doc__)
    fd = create()
    fingers = Fingers(fd)
    try:
        for step in steps:
            kind, _, args = step.partition(":")
            if kind == "swipe":
                swipe(fingers, *args.split(","))
            elif kind == "pinch":
                pinch(fingers, *args.split(","))
            elif kind == "sleep":
                time.sleep(float(args) / 1000)
                continue
            else:
                sys.exit(f"touchpad.py: {step} is not a step")
            time.sleep(1)
    finally:
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        os.close(fd)


main(sys.argv[1:])
