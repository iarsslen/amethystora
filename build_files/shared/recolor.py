#!/usr/bin/env python3
"""Rotate the cool half of a stylesheet's colours onto Amethystora's amethyst.

The Sweet theme is built around a teal accent on navy chrome. Both are cool colours, so a single
hue mapping turns the whole theme amethyst in one pass, and every shade Sweet derived from those
two - the hover, active, backdrop and border variants - follows on its own, because they sit in the
same part of the wheel. Enumerating them one by one would go stale the moment Sweet is bumped.

Saturation and lightness are what hold a vivid accent apart from a dark background, and Sweet
already has them right, so they are kept. That also leaves greys alone for free: with no saturation
there is no hue to rotate. The one exception is lightness on the saturated colours, which is lifted:
a purple reads considerably darker than a teal of the same lightness, so carrying Sweet's numbers
across unchanged would land the accent at #5a00d3 instead of the #8e3aff that matches the palette
the rest of Amethystora is drawn from. The lift is held off the chrome by the saturation floor.

The band stops short of red, orange and yellow, which carry meaning rather than branding -
destructive buttons, warnings, the error colour - and of the magentas, which are already amethyst's
neighbours and would be pushed away from it.

    recolor.py FILE...             rewrite each file in place
    recolor.py --check FILE..      report what is left in the band and fail if anything is
    recolor.py --band LOW:HIGH ..  rotate a different band, in degrees, onto the same amethyst

--band is for the handful of files Sweet draws in a colour the default band deliberately spares.
The switch, whose filled half is amber, is the one that matters: amber means the same thing as the
default band's teal there, an accent, and not the warning it means everywhere else.
"""

import colorsys
import re
import sys

# Degrees on the colour wheel. The band runs from the yellow-greens, through teal and cyan, to the
# indigo just short of violet; it lands on a narrow spread around Amethystora's own accent, #9148f0
# at 266 degrees. The spread is what keeps Sweet's colours distinguishable from each other: its
# teal accent arrives at 265, the navy chrome behind it at 278.
COOL_LOW, COOL_HIGH = 90.0, 265.0
AMETHYST_LOW, AMETHYST_HIGH = 250.0, 285.0

# Only a colour vivid enough to be branding rather than chrome is lightened, and by how much of the
# headroom above it. Together these put Sweet's teal accent on Amethystora's, and leave the dark
# backgrounds, the borders and the body text at the lightness Sweet chose for them.
VIVID = 0.5
LIFT = 0.34

# Below this saturation a colour is a grey with a tint, and its hue is too faint to survive the trip
# through eight-bit channels: Sweet's near-white #f6f7f6 comes back as #f6f6f7, which is a different
# grey at a hue the rotation does not aim at. --check ignores these, because they are not colours
# anyone sees, and treating them as work left undone would mean the check could never pass. Sweet's
# own chrome sits well above it: its body text is at 0.11 and the window background at 0.27.
FAINT = 0.08

HEX = re.compile(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b")
RGB = re.compile(r"(rgba?\(\s*)(\d{1,3})(\s*,\s*)(\d{1,3})(\s*,\s*)(\d{1,3})")


def in_band(hue):
    return COOL_LOW <= hue <= COOL_HIGH


def unmapped(hue):
    """What --check reports: a colour the rotation should have moved and did not.

    The two ranges meet between 250 and 265, so a colour the rotation has already put there is in
    the band again and would be moved a second time. That sliver is what this leaves out, which is
    why --check is a check and not the same thing as running the rotation twice.
    """
    return in_band(hue) and not (AMETHYST_LOW <= hue <= AMETHYST_HIGH)


def rotate(red, green, blue, only_unmapped=False):
    """Map one colour, or return None when it is outside the band and has to stay as it is."""
    hue, lightness, saturation = colorsys.rgb_to_hls(red / 255, green / 255, blue / 255)
    degrees = hue * 360
    wanted = unmapped if only_unmapped else in_band
    if saturation == 0 or not wanted(degrees):
        return None
    if only_unmapped and saturation < FAINT:
        return None
    moved = AMETHYST_LOW + (degrees - COOL_LOW) * (AMETHYST_HIGH - AMETHYST_LOW) / (COOL_HIGH - COOL_LOW)
    if saturation > VIVID:
        lightness += LIFT * (1 - lightness)
    turned = tuple(round(channel * 255) for channel in colorsys.hls_to_rgb(moved / 360, lightness, saturation))
    # A colour a hair off grey, like the #f6f6f7 Sweet uses for a light background, has so little
    # hue that turning it lands back on the same three bytes. Reporting it as changed would be
    # wrong, and --check would then see it sitting in the band afterwards and call it a leftover.
    return None if turned == (red, green, blue) else turned


def expand(digits):
    """#abc and #aabbccdd alike come back as (r, g, b, trailing alpha digits)."""
    if len(digits) == 3:
        return tuple(int(d * 2, 16) for d in digits) + ("",)
    return (int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16), digits[6:])


def rewrite(text, found, only_unmapped=False):
    def hex_colour(match):
        red, green, blue, alpha = expand(match.group(1))
        moved = rotate(red, green, blue, only_unmapped)
        if moved is None:
            return match.group(0)
        found.append(match.group(0))
        return "#%02x%02x%02x%s" % (*moved, alpha)

    def rgb_colour(match):
        head, red, first, green, second, blue = match.groups()
        moved = rotate(int(red), int(green), int(blue), only_unmapped)
        if moved is None:
            return match.group(0)
        found.append(match.group(0))
        return f"{head}{moved[0]}{first}{moved[1]}{second}{moved[2]}"

    return RGB.sub(rgb_colour, HEX.sub(hex_colour, text))


def main(argv):
    global COOL_LOW, COOL_HIGH

    check = False
    paths = []
    argv = list(argv)
    while argv:
        argument = argv.pop(0)
        if argument == "--check":
            check = True
        elif argument == "--band":
            low, _, high = argv.pop(0).partition(":")
            COOL_LOW, COOL_HIGH = float(low), float(high)
        else:
            paths.append(argument)

    if not paths:
        print(__doc__, file=sys.stderr)
        return 2

    total = 0
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        found = []
        new = rewrite(text, found, only_unmapped=check)
        total += len(found)
        if check:
            if found:
                sample = ", ".join(sorted(set(found))[:5])
                print(f"::error::{path} still has {len(found)} colours in the cool band: {sample}", flush=True)
            continue
        if new != text:
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(new)
        print(f"recolor: {path}: {len(found)} colours", flush=True)

    if check:
        return 1 if total else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
