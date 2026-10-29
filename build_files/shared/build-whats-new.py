#!/usr/bin/python3
"""What's new (R4-15): the notes of a stream's last few releases, for the Manual's page and the live pill's card.

Two steps, one script:

    build-whats-new.py notes COMMITS_JSON     on the host, from release-commits.sh: prints the notes
    build-whats-new.py image NOTES_JSON ROOT  in the build (build.sh): writes the page and the pill's file

COMMITS_JSON is what release-commits.sh gathered: this build's version, the subjects of the commits since the build its
stream last published, and that build's own notes (its org.amethystora.whats-new label). The notes are that list with
this build in front: each release's conventional `feat` commits, the newest MOST_RELEASES releases that brought any. A
rebuild of the same commit keeps the notes of the builds before it, and a machine that skipped versions is told what
all of them brought (modules/pill/whatsnew.js shows the releases newer than the one the account saw). The notes are
also this build's label, which the next build reads.

A title is kept only when it is plain words: anything else a subject may hold (a command, a path, an upstream name,
Markdown) is what the image's own checks refuse in /usr/share/amethystora, or could, so that feature is left out of the
notes rather than the build failing (test-whats-new.sh holds it).
"""

import json
import os
import re
import sys

MOST_ITEMS = 12
MOST_RELEASES = 6
FEAT = re.compile(r"^feat(?:\(([a-z0-9-]+)\))?!?:\s*(.+)$")
VERSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
# Letters and digits of any script, spaces and this punctuation, nothing else
PUNCTUATION = set(" ,.'’:;()!?&+-")
# Words the image's checks look for in its text: commands (20-tests.sh's `ame` check), upstream names (debrand.py)
REFUSED = re.compile(r"\bame\b|\bujust\b|\bamepkg\b|ublue|universal.?blue", re.I)
# A commit's scope, as the pill and the page say where it is
AREAS = {
    "desktop": "desktop", "ui": "desktop", "shell": "desktop", "dock": "desktop", "theme": "desktop",
    "security": "security", "hardening": "security",
    "control": "control",
    "apps": "apps", "notes": "apps", "manual": "apps", "backups": "apps", "logs": "apps", "phone": "apps",
    "updates": "updates", "update": "updates",
}
WHERE = {
    "desktop": "On the desktop.",
    "security": "In Security.",
    "control": "In Control.",
    "apps": "In the apps.",
    "updates": "In Updates.",
    "system": "Across the system.",
}


def plain_title(text):
    """The title, capitalised, when it is plain words; else None"""
    title = re.sub(r"\s+", " ", text if isinstance(text, str) else "").strip().rstrip(".")
    if not title or REFUSED.search(title) or not all(c.isalnum() or c in PUNCTUATION for c in title):
        return None
    title = title[0].upper() + title[1:]
    return title[:89].rstrip() + "…" if len(title) > 90 else title


def items_from(commits):
    items, seen = [], set()
    for subject in commits if isinstance(commits, list) else []:
        match = FEAT.match(subject.strip()) if isinstance(subject, str) else None
        title = plain_title(match.group(2)) if match else None
        if not title or title.lower() in seen:
            continue
        seen.add(title.lower())
        items.append({"title": title, "area": AREAS.get(match.group(1) or "", "system")})
        if len(items) == MOST_ITEMS:
            break
    return items


def clean_releases(releases):
    """The notes as a label or a file gives them, each title checked again"""
    out = []
    for release in releases if isinstance(releases, list) else []:
        if not isinstance(release, dict) or not VERSION.match(str(release.get("version", ""))):
            continue
        items = []
        for item in release.get("items") or []:
            title = plain_title(item.get("title")) if isinstance(item, dict) else None
            if title:
                items.append({"title": title, "area": item.get("area") if item.get("area") in WHERE else "system"})
        if items:
            out.append({"version": release["version"], "items": items[:MOST_ITEMS]})
    return out


def notes(data):
    data = data if isinstance(data, dict) else {}
    version = data.get("version")
    if not isinstance(version, str) or not VERSION.match(version):
        return {"version": None, "releases": []}
    items = items_from(data.get("commits"))
    earlier = [r for r in clean_releases(data.get("history")) if r["version"] != version]
    releases = ([{"version": version, "items": items}] if items else []) + earlier
    return {"version": version, "releases": releases[:MOST_RELEASES]}


def os_release_version(root):
    for name in ("usr/lib/os-release", "etc/os-release"):
        try:
            with open(os.path.join(root, name), encoding="utf-8") as f:
                for line in f:
                    key, _, value = line.strip().partition("=")
                    if key == "IMAGE_VERSION":
                        return value.strip("\"'")
        except OSError:
            continue
    return None


def page(releases):
    lines = ["# What's new", ""]
    if not releases:
        lines += ["What the last few builds of Amethystora brought is written on this page when the image is built, "
                  "from the changes each made. There is nothing to tell for this one; "
                  "[Updates](updates.md#whats-new) says how the desktop tells you about one that has.", ""]
        return "\n".join(lines)
    lines += ["What the last few builds of Amethystora brought, the newest first; the pages of the Manual describe "
              "them.", ""]
    for release in releases:
        lines += [f"## Amethystora {release['version']}", ""]
        lines += [f"- **{item['title']}**. {WHERE[item['area']]}" for item in release["items"]]
        lines.append("")
    return "\n".join(lines)


def image(notes_path, root):
    try:
        with open(notes_path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    releases = clean_releases(data.get("releases") if isinstance(data, dict) else [])
    version = os_release_version(root) or ""
    if not VERSION.match(version):
        version = "unknown"
    share = os.path.join(root, "usr/share/amethystora")
    with open(os.path.join(share, "whats-new.json"), "w", encoding="utf-8") as f:
        json.dump({"version": version, "releases": releases}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    with open(os.path.join(share, "manual/whats-new.md"), "w", encoding="utf-8") as f:
        f.write(page(releases))
    print(f"what's new in {version}: {sum(len(r['items']) for r in releases)} item(s), {len(releases)} release(s)")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "notes":
        try:
            with open(sys.argv[2], encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        json.dump(notes(data), sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
    elif len(sys.argv) == 4 and sys.argv[1] == "image":
        image(sys.argv[2], sys.argv[3])
    else:
        sys.exit("usage: build-whats-new.py notes COMMITS_JSON | image NOTES_JSON ROOT")


if __name__ == "__main__":
    main()
