#!/usr/bin/env python3
"""Rename what the upstream layers ship as Bluefin / Universal Blue (ublue) to Amethystora.

The ublue-os base image, projectbluefin/common, ublue-os/brew and the ublue COPR packages
install files, commands, services and settings under their own names. This renames all of
them to Amethystora and rewrites every reference, so the image carries no upstream names.

    debrand.py          apply the changes (07-debrand.sh)
    debrand.py --check  report what is left and fail on anything renameable (20-tests.sh)

Left alone on purpose:
  - compiled files: the uupd binary, the kernel and akmods packages and their signing certificate
  - licence files and copyright lines: upstream's attribution must stay (Apache-2.0)
  - the RPM database and kernel modules
  - files owned by other RPMs, where words like "bluefin" (the tuna) are not our branding

DEBRAND_ROOT points the script at a staged tree instead of / for testing.
"""

import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.environ.get("DEBRAND_ROOT", "/")
REPO = "iarsslen/amethystora"
REPO_URL = f"https://github.com/{REPO}"
VENDOR = REPO.split("/")[0]

SCAN_DIRS = ("usr", "etc")
PRUNE = ("usr/lib/modules", "usr/src", "usr/lib/sysimage", "usr/share/licenses", "usr/lib/.build-id")
LEGAL = re.compile(r"^(LICEN[CS]E|COPYING|NOTICE)", re.I)
MAX_TEXT_SIZE = 16 * 1024 * 1024

TRACE = re.compile(r"ublue|bluefin|universal.?blue", re.I)
TRACE_BYTES = re.compile(rb"ublue|bluefin|universal.?blue", re.I)
TAP = re.compile(r"ublue-os/(?:experimental-)?tap")


def path(rel):
    return os.path.join(ROOT, rel)


def rel(full):
    return os.path.relpath(full, ROOT).replace(os.sep, "/")


def log(message):
    print(f"debrand: {message}", flush=True)


# --- Renaming rules ---------------------------------------------------------------------------

def keep_case(word):
    def replace(match):
        found = match.group(0)
        if found.isupper():
            return word.upper()
        if found[0].isupper():
            return word.capitalize()
        return word
    return replace


# Names, applied to both file names and file contents
WORDS = [
    (re.compile(r"universal[\s_-]?blue", re.I), keep_case("amethystora")),
    (re.compile(r"projectbluefin", re.I), keep_case("amethystora")),
    (re.compile(r"ublue[-_]os", re.I), keep_case("amethystora")),
    (re.compile(r"ublue", re.I), keep_case("amethystora")),
    (re.compile(r"bluefin", re.I), keep_case("amethystora")),
    # "ublue-os/bluefin" style names collapse into one
    (re.compile(r"(amethystora)[-_ ]amethystora", re.I), r"\1"),
]

URL_TAIL = r"[^\s\"'<>)\]}`]*"


def github_url(match):
    url = match.group(0)
    if "/discussions" in url:
        return f"{REPO_URL}/discussions"
    if "/issues/new" in url:
        return f"{REPO_URL}/issues/new"
    if "/issues" in url:
        return f"{REPO_URL}/issues"
    return REPO_URL


# Links and repository names, applied to file contents before WORDS
LINKS = [
    (re.compile(rf"https?://docs\.projectbluefin\.io{URL_TAIL}"), f"{REPO_URL}#readme"),
    (re.compile(rf"https?://ask\.projectbluefin\.io{URL_TAIL}"), f"{REPO_URL}/discussions"),
    (re.compile(rf"https?://issues\.projectbluefin\.io{URL_TAIL}"), f"{REPO_URL}/issues"),
    (re.compile(rf"https?://(?:[\w-]+\.)*(?:projectbluefin\.io|ublue\.it|universal-blue\.org){URL_TAIL}"), REPO_URL),
    (re.compile(rf"https?://github\.com/(?:ublue-os|projectbluefin)\b{URL_TAIL}"), github_url),
    (re.compile(rf"https?://raw\.githubusercontent\.com/(?:ublue-os|projectbluefin)/{URL_TAIL}"), REPO_URL),
    (re.compile(r"ghcr\.io/(?:ublue-os|projectbluefin)\b"), f"ghcr.io/{VENDOR}"),
    # Upstream issue numbers ("ublue-os/bluefin#1328") mean nothing on Amethystora's tracker
    (re.compile(r"(?<![\w./-])(?:projectbluefin|ublue-os)/[\w.-]+#\d+"), REPO),
    (re.compile(
        r"(?<![\w./-])(?:projectbluefin|ublue-os)/(?:bluefin(?:-lts|-dx)?|aurora|bazzite|common|dakota|main"
        r"|config|packages|staging|akmods|bling|brew|uupd|umotd|uwelcome|legacy-rechunk|image-template)\b"
    ), REPO),
    # Bluefin's blueberry emoji
    (re.compile("\U0001FAD0"), "\U0001F49C"),
]


# Copyright and licence lines keep upstream's names: the attribution must stay intact
LEGAL_LINE = re.compile(r"copyright|\(c\)\s|©|spdx-license|licen[cs]ed under|all rights reserved", re.I)


def rename_text(text):
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if LEGAL_LINE.search(line):
            continue
        for pattern, replacement in LINKS + WORDS:
            line = pattern.sub(replacement, line)
        lines[i] = line
    return "".join(lines)


def rename_name(name):
    for pattern, replacement in WORDS:
        name = pattern.sub(replacement, name)
    return name


# --- Scope --------------------------------------------------------------------------------------

def pruned(relative):
    return any(relative == p or relative.startswith(p + "/") for p in PRUNE)


def walk():
    """Yield (directory, dirnames, filenames) under the scanned directories, minus PRUNE."""
    for top in SCAN_DIRS:
        for directory, dirnames, filenames in os.walk(path(top)):
            dirnames[:] = [d for d in dirnames if not pruned(rel(os.path.join(directory, d)))]
            yield directory, dirnames, filenames


def rpm_owned():
    """Files that other RPMs own. Files of packages built by Universal Blue stay in scope."""
    if ROOT != "/" or not shutil.which("rpm"):
        return set()

    def rpm(*args):
        return subprocess.run(["rpm", *args], check=True, capture_output=True, text=True).stdout.splitlines()

    owned = set(rpm("-qal"))
    for line in rpm("-qa", "--qf", "%{NAME}\t%{VENDOR}\t%{PACKAGER}\t%{URL}\n"):
        if TRACE.search(line):
            owned.difference_update(rpm("-ql", line.split("\t")[0]))
    return owned


def files_in_scope(owned):
    for directory, _, filenames in walk():
        for name in filenames:
            full = os.path.join(directory, name)
            if os.path.islink(full) or LEGAL.match(name) or "/" + rel(full) in owned:
                continue
            yield full


# --- Removals ahead of the rename ------------------------------------------------------------------

def is_brew_entry(line):
    return re.match(r"\s*(tap|brew|cask|flatpak|mas|vscode|go|cargo|uv|whalebrew)\s", line) is not None


def strip_brewfiles():
    """Drop every package from Universal Blue's Homebrew taps."""
    for directory, _, filenames in walk():
        for name in filenames:
            if not name.endswith(".Brewfile"):
                continue
            full = os.path.join(directory, name)
            with open(full, encoding="utf-8", newline="") as f:
                lines = f.readlines()
            kept = [line for line in lines if not TAP.search(line)]
            if kept == lines:
                continue
            if any(is_brew_entry(line) for line in kept) or "/oem/" in rel(full):
                # The OEM setup hook installs its vendor's Brewfile unconditionally: keep it, even empty
                with open(full, "w", encoding="utf-8", newline="") as f:
                    f.writelines(kept)
                log(f"removed Universal Blue tap packages from {rel(full)}")
            else:
                os.remove(full)
                log(f"removed {rel(full)}, it only listed Universal Blue tap packages")


RECIPE = re.compile(r"^@?([A-Za-z_][\w-]*)\b[^:\n]*:(?!=)")
NOT_RECIPE = re.compile(r"^(#|\[|import\b|mod\b|alias\b|set\b|export\b)")


def recipes(lines):
    """Split a justfile into recipes: yield (name, start, header, end).

    start is the first of the comment and attribute lines above the recipe, header its name line.
    """
    i = 0
    while i < len(lines):
        match = RECIPE.match(lines[i])
        if not match or NOT_RECIPE.match(lines[i]):
            i += 1
            continue
        start = i
        while start > 0 and re.match(r"^(#|\[)", lines[start - 1]):
            start -= 1
        end = i + 1
        while end < len(lines) and (not lines[end].strip() or lines[end][0] in " \t"):
            end += 1
        yield match.group(1), start, i, end
        i = end


def drop_tap_installers(text):
    """Remove menu entries whose install command uses a Universal Blue tap (ujust devmode)."""
    labels = set()
    kept = []
    for line in text.splitlines(keepends=True):
        if TAP.search(line):
            added = re.search(r'_dx_add\s+"([^"]+)"', line)
            if added:
                labels.add(added.group(1))
                continue
            if re.match(r"\s*brew (tap|trust) ", line):
                continue
        kept.append(line)
    text = "".join(kept)
    text = re.sub(r"(?m)^[ \t]*if [^\n]*; then\n(?:[ \t]*\n)*[ \t]*fi\n", "", text)
    for label in labels:
        escaped = re.escape(label)
        text = re.sub(rf'(?m)^[ \t]*"\s*{escaped}"\s*\\\n', "", text)
        text = re.sub(rf'(?m)^[ \t]*_dx_wants\b[^\n]*WILL_INSTALL\+=\("{escaped}"\)\n', "", text)
    # Menu section headers ("── IDE ──") left without entries
    text = re.sub(r'(?m)^[ \t]*"── [^"\n]*"\s*\\\n(?=[ \t]*(?:"── |[^"\s]))', "", text)
    return text


# Upstream recipes replaced by Amethystora's own (60-custom.just) or that only work for Bluefin:
# bluespeed duplicates install-ai-tools, bazaar-preview needs a checkout of projectbluefin/common
DROP_RECIPES = {"bazaar-preview", "bluespeed", "toggle-user-motd"}
OWN_JUST = "usr/share/amethystora/just"


def patch_justfiles():
    """Drop upstream ujust recipes that install from Universal Blue taps, and the aliases pointing to them."""
    for directory, _, filenames in walk():
        if rel(directory) == OWN_JUST:
            continue
        for name in filenames:
            if not name.endswith(".just"):
                continue
            full = os.path.join(directory, name)
            with open(full, encoding="utf-8", newline="") as f:
                original = f.read()
            lines = drop_tap_installers(original).splitlines(keepends=True)
            dropped = set()
            for recipe, start, _, end in recipes(lines):
                if recipe in DROP_RECIPES or TAP.search("".join(lines[start:end])):
                    dropped.add(recipe)
            # Aliases and one-line wrappers of dropped recipes go too
            for recipe, _, header, end in recipes(lines):
                body = "".join(line for line in lines[header + 1:end] if line.strip())
                target = re.fullmatch(r"\s*@?ujust\s+([\w-]+)\s*", body)
                if target and target.group(1) in dropped:
                    dropped.add(recipe)
            for recipe, start, _, end in reversed(list(recipes(lines))):
                if recipe in dropped:
                    del lines[start:end]
            if dropped:
                alias = re.compile(rf"^alias\s+[\w-]+\s*:=\s*(?:{'|'.join(map(re.escape, dropped))})\s*$")
                lines = [line for line in lines if not alias.match(line)]
            text = "".join(lines)
            if text != original:
                with open(full, "w", encoding="utf-8", newline="") as f:
                    f.write(text)
                log(f"{rel(full)}: dropped {', '.join(sorted(dropped)) or 'Universal Blue tap installs'}")


def drop_tap_hooks():
    """Setup hooks that install from Universal Blue taps."""
    for directory, _, filenames in walk():
        if not directory.endswith(".hooks.d"):
            continue
        for name in filenames:
            full = os.path.join(directory, name)
            with open(full, encoding="utf-8", errors="replace") as f:
                if TAP.search(f.read()):
                    os.remove(full)
                    log(f"removed {rel(full)}, it installs from Universal Blue taps")


def drop_upstream_trust():
    """Universal Blue's image signing keys, registries and package repositories."""
    policy = path("etc/containers/policy.json")
    if os.path.isfile(policy):
        with open(policy, encoding="utf-8") as f:
            data = json.load(f)
        docker = data.get("transports", {}).get("docker", {})
        for registry in [r for r in docker if TRACE.search(r)]:
            del docker[registry]
            log(f"removed {registry} from {rel(policy)}")
        with open(policy, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4)
            f.write("\n")
    for directory in ("etc/containers/registries.d", "etc/pki/containers", "usr/lib/pki/containers",
                      "etc/yum.repos.d"):
        if not os.path.isdir(path(directory)):
            continue
        for name in os.listdir(path(directory)):
            if TRACE.search(name):
                os.remove(path(f"{directory}/{name}"))
                log(f"removed {directory}/{name}")


# --- Rename --------------------------------------------------------------------------------------

def merge(source, target):
    """Move source to target. Where both exist, what is already at target (Amethystora's file) wins."""
    if os.path.lexists(target) and not (os.path.isdir(source) and not os.path.islink(source)
                                         and os.path.isdir(target) and not os.path.islink(target)):
        log(f"kept {rel(target)} over {rel(source)}")
        if os.path.isdir(source) and not os.path.islink(source):
            shutil.rmtree(source)
        else:
            os.remove(source)
    elif os.path.lexists(target):
        for name in os.listdir(source):
            merge(os.path.join(source, name), os.path.join(target, name))
        os.rmdir(source)
    else:
        os.rename(source, target)


def rename_paths():
    found = []
    for directory, dirnames, filenames in walk():
        found += [os.path.join(directory, name) for name in dirnames + filenames if TRACE.search(name)]
    # Deepest first, so a directory's contents are renamed before the directory itself
    for full in sorted(found, key=lambda p: p.count(os.sep), reverse=True):
        directory, name = os.path.split(full)
        merge(full, os.path.join(directory, rename_name(name)))
    log(f"renamed {len(found)} files and directories")


def retarget_symlinks():
    for directory, dirnames, filenames in walk():
        for name in dirnames + filenames:
            full = os.path.join(directory, name)
            if os.path.islink(full) and TRACE.search(os.readlink(full)):
                target = rename_name(os.readlink(full))
                os.remove(full)
                os.symlink(target, full)


def rewrite_files(owned):
    count = 0
    for full in files_in_scope(owned):
        if os.path.getsize(full) > MAX_TEXT_SIZE:
            continue
        with open(full, "rb") as f:
            data = f.read()
        if not TRACE_BYTES.search(data) and "\U0001FAD0".encode() not in data:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if "\0" in text:
            continue
        new = rename_text(text)
        if new != text:
            with open(full, "w", encoding="utf-8", newline="") as f:
                f.write(new)
            count += 1
    log(f"rewrote {count} files")


# --- Check ---------------------------------------------------------------------------------------

def check(owned):
    """Fail on any upstream name left in a path or text file; list compiled files that keep one."""
    problems, compiled = [], []
    for directory, dirnames, filenames in walk():
        for name in dirnames + filenames:
            full = os.path.join(directory, name)
            if TRACE.search(name):
                problems.append(f"path: /{rel(full)}")
            elif os.path.islink(full) and TRACE.search(os.readlink(full)):
                problems.append(f"link: /{rel(full)} -> {os.readlink(full)}")
    for full in files_in_scope(owned):
        if os.path.getsize(full) > MAX_TEXT_SIZE:
            continue
        with open(full, "rb") as f:
            data = f.read()
        if not TRACE_BYTES.search(data):
            continue
        try:
            text = data.decode("utf-8")
            binary = "\0" in text
        except UnicodeDecodeError:
            binary = True
        if binary:
            compiled.append(f"/{rel(full)}")
            continue
        line = next((line for line in text.splitlines() if TRACE.search(line) and not LEGAL_LINE.search(line)), None)
        if line is not None:
            problems.append(f"text: /{rel(full)}: {line.strip()[:160]}")
    for item in compiled:
        log(f"compiled file keeps an upstream name (expected): {item}")
    for item in problems:
        print(f"::error::upstream name left in the image, {item}", flush=True)
    return 1 if problems else 0


def main():
    owned = rpm_owned()
    if sys.argv[1:] == ["--check"]:
        return check(owned)
    strip_brewfiles()
    patch_justfiles()
    drop_tap_hooks()
    drop_upstream_trust()
    # An install left behind by the steps above would end up pointing at a tap that does not exist
    for full in files_in_scope(owned):
        with open(full, "rb") as f:
            for number, raw in enumerate(f, 1):
                line = raw.decode("utf-8", "replace")
                if TAP.search(line) and re.search(r"\b(brew|cask)\b", line):
                    print(f"::warning::/{rel(full)}:{number} installs from a Universal Blue tap: {line.strip()}",
                          flush=True)
    rename_paths()
    retarget_symlinks()
    rewrite_files(owned)
    return 0


if __name__ == "__main__":
    sys.exit(main())
