#!/usr/bin/python3
"""The emoji and symbols picker's lists and names (Super+., modules/emoji.js of Amethystora UI), made when the
image is built from Unicode's own files, which 09-emoji.sh downloads and checks against their pinned sums:

    emoji-data.py SOURCES OUT

SOURCES holds emoji-test.txt (Emoji 16.0), UnicodeData.txt (16.0.0), and CLDR release 47's annotations as
ann-<lang>.xml and annotationsDerived as der-<lang>.xml for every language below. OUT gets emoji.json (the tabs and
the skin tones) and names-<lang>.json (the names and search words of each character). An emoji the image's colour
emoji font cannot draw is left out, and how many is said. Standard library only.
"""

import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ElementTree

LANGUAGES = ["en", "fr", "de", "es", "ar"]

# emoji-test.txt's groups, by the tab each becomes; its Component group (the skin tones and hair styles on their
# own) is no tab
GROUPS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "people",
    "Animals & Nature": "nature",
    "Food & Drink": "food",
    "Travel & Places": "places",
    "Activities": "activities",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}

# The skin tones, lightest first: the order of the picker's strip and of the skin-tone key's values
TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]

# The four tabs of symbols, chosen for this image, in the order they are shown
SYMBOLS = {
    "arrows": "← → ↑ ↓ ↔ ↕ ↖ ↗ ↘ ↙ ⇐ ⇒ ⇑ ⇓ ⇔ ⇕ ↩ ↪ ⟵ ⟶ ⟷ ⇄ ⇆ ↺ ↻ ⤴ ⤵ ↰ ↱ ↲ ↳ ⇠ ⇢ ⇡ ⇣ ➔ ➜ ➤ ⇥ ⇤",
    "maths": "+ − × ÷ ± ∓ = ≠ ≈ ≡ < > ≤ ≥ ∞ √ ∛ ∑ ∏ ∫ ∂ ∆ ∇ π ° ‰ ¼ ½ ¾ ⅓ ⅔ ¹ ² ³ ∈ ∉ ∩ ∪ ⊂ ⊃ ∀ ∃ ¬ ∧ ∨ µ Ω ∅ ∝ ∠ ⊥",
    "money": "€ £ ¥ ₹ ₩ ₺ ₽ ¢ $ ₴ ₦ ₫ ₪ ₱ ₿ ₣ ₡ ₸ ₼ ₾ ฿ ₲ ₵ ₭ ₮ ﷼ ¤",
    "punctuation": "— – … « » „ “ ” ‘ ’ ‚ ‹ › • · ¡ ¿ § ¶ † ‡ © ® ™ № ′ ″ ※ ¦ ‽ ، ؛ ؟",
}

# What joins or marks an emoji's parts rather than being drawn: never looked for in the font
JOINERS = {0x200D, 0xFE0F, 0x20E3} | set(range(0xE0020, 0xE0080))


def read_emoji_test(path):
    """The fully-qualified emoji by tab, in the file's order, and each one's skin tones"""
    tabs = {tab: [] for tab in GROUPS.values()}
    toned = {}
    group = None
    with open(path, encoding="utf-8") as lines:
        for line in lines:
            if line.startswith("# group:"):
                group = GROUPS.get(line.split(":", 1)[1].strip())
                continue
            if line.startswith("#") or ";" not in line or group is None:
                continue
            points, status = (part.strip() for part in line.split("#", 1)[0].split(";"))
            if status != "fully-qualified":
                continue
            codes = [int(code, 16) for code in points.split()]
            tones = [code for code in codes if code in TONES]
            if not tones:
                tabs[group].append("".join(map(chr, codes)))
            elif len(set(tones)) == 1:
                base = "".join(chr(code) for code in codes if code not in TONES)
                toned.setdefault(plain(base), {})[tones[0]] = "".join(map(chr, codes))
    # An emoji has tones when all five are there; one with two people of different tones is left out
    tones = {}
    for tab in tabs.values():
        for item in tab:
            variants = toned.get(plain(item), {})
            if len(variants) == len(TONES):
                tones[item] = [variants[tone] for tone in TONES]
    return tabs, tones


def plain(text):
    """The text without the variation selector that asks for the emoji style, as CLDR keys it"""
    return text.replace("\ufe0f", "")


def read_unicode_names(path):
    names = {}
    with open(path, encoding="utf-8") as lines:
        for line in lines:
            fields = line.split(";")
            if len(fields) > 1 and not fields[1].startswith("<"):
                names[chr(int(fields[0], 16))] = fields[1].lower()
    return names


def read_annotations(*paths):
    """CLDR's names (tts) and search words for one language, by character without its variation selector"""
    names, words = {}, {}
    for path in paths:
        for node in ElementTree.parse(path).getroot().iter("annotation"):
            cp, text = node.get("cp"), (node.text or "").strip()
            if not cp or not text:
                continue
            key = plain(cp)
            if node.get("type") == "tts":
                names.setdefault(key, text)
            else:
                words.setdefault(key, [word.strip() for word in text.split("|") if word.strip()])
    return names, words


def drawable(font):
    """The code points the colour emoji font has a glyph for"""
    charset = subprocess.run(["fc-query", "--format", "%{charset}", font], check=True, capture_output=True,
                             text=True).stdout
    points = set()
    for span in charset.split():
        first, _, last = span.partition("-")
        points.update(range(int(first, 16), int(last or first, 16) + 1))
    return points


def main(sources, out):
    tabs, tones = read_emoji_test(os.path.join(sources, "emoji-test.txt"))

    font = subprocess.run(["fc-match", "-f", "%{file}", "Noto Color Emoji"], check=True, capture_output=True,
                          text=True).stdout.strip()
    points = drawable(font)
    can_draw = lambda item: all(ord(ch) in points for ch in item if ord(ch) not in JOINERS)
    dropped = 0
    for tab, items in tabs.items():
        kept = [item for item in items if can_draw(item)]
        dropped += len(items) - len(kept)
        tabs[tab] = kept
    tones = {item: [variant for variant in variants if can_draw(variant)] for item, variants in tones.items()}
    tones = {item: variants for item, variants in tones.items() if len(variants) == len(TONES) and can_draw(item)}
    emoji_count = sum(len(items) for items in tabs.values())
    print(f"emoji-data: {emoji_count} emoji from {font}, {dropped} left out that it cannot draw, "
          f"{len(tones)} with skin tones")

    for tab, symbols in SYMBOLS.items():
        tabs[tab] = symbols.split()

    every = [item for items in tabs.values() for item in items]
    unicode_names = read_unicode_names(os.path.join(sources, "UnicodeData.txt"))
    os.makedirs(out, exist_ok=True)
    missing = 0
    for language in LANGUAGES:
        names, words = read_annotations(os.path.join(sources, f"ann-{language}.xml"),
                                        os.path.join(sources, f"der-{language}.xml"))
        table = {}
        for item in every:
            key = plain(item)
            name = names.get(key)
            if name is None and language == "en":
                # A symbol CLDR does not name takes the Unicode name, in lower case
                name = unicode_names.get(item) if len(item) == 1 else None
                if name is None:
                    missing += 1
                    continue
            if name is None:
                continue
            table[item] = [name] + [word for word in words.get(key, []) if word != name]
        with open(os.path.join(out, f"names-{language}.json"), "w", encoding="utf-8") as file:
            json.dump(table, file, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    if missing:
        sys.exit(f"emoji-data: {missing} characters have no English name")

    with open(os.path.join(out, "emoji.json"), "w", encoding="utf-8") as file:
        json.dump({"version": 1, "unicode": "16.0", "cldr": "47", "tabs": tabs, "tones": tones}, file,
                  ensure_ascii=False, separators=(",", ":"), sort_keys=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: emoji-data.py SOURCES OUT")
    main(sys.argv[1], sys.argv[2])
