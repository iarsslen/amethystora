#!/usr/bin/env python3
"""List the packages of the installer on the ISO, and refuse Fedora's logo and release packages.

    installer-packages.py output/manifest-anaconda-iso.json > INSTALLER-PACKAGES

The image an ISO installs lists its own packages in /usr/share/licenses/amethystora/SOURCES. The
installer that carries it there is a second, smaller system, built by bootc-image-builder from Fedora's
packages, and nothing else says what is in it. The builder leaves the manifest it built from beside
the ISO; the installer is that manifest's anaconda-tree pipeline. The list goes on the ISO beside
NOTICE, whose written offer covers it.

Fedora's trademark guidelines ask a system built from Fedora to leave fedora-logos and fedora-release
out, and build-iso.yml asks the builder for generic-logos and generic-release in their place. If one of
Fedora's is in the installer all the same, this fails, and the ISO is not uploaded.
"""

import json
import os
import sys

FORBIDDEN = ("fedora-logos", "fedora-release")

with open(sys.argv[1], encoding="utf-8") as f:
    manifest = json.load(f)

# Where each package comes from, by checksum: an address, or a path on a mirror
files = {}
for source in manifest["sources"].values():
    for checksum, item in source.get("items", {}).items():
        files[checksum] = item if isinstance(item, str) else item.get("url") or item.get("path") or ""

packages = set()
for pipeline in manifest["pipelines"]:
    if pipeline["name"] != "anaconda-tree":
        continue
    for stage in pipeline["stages"]:
        if stage["type"] != "org.osbuild.rpm":
            continue
        # Keyed by checksum, or a list of them, depending on the builder's version
        for reference in stage["inputs"]["packages"]["references"]:
            checksum = reference if isinstance(reference, str) else reference["id"]
            packages.add(os.path.basename(files[checksum]).removesuffix(".rpm"))

if len(packages) < 100:
    sys.exit(f"Only {len(packages)} packages found for the installer: the manifest is not laid out as expected")

branded = sorted(p for p in packages if p.startswith(FORBIDDEN))
if branded:
    sys.exit("The installer carries Fedora's branding packages: " + ", ".join(branded))

print("""\
The installer on this ISO is made of the packages below, each as Fedora built it. Fedora publishes the
source package of each with the build it came from, in its build system:

    https://koji.fedoraproject.org/koji/search?type=rpm&match=exact&terms=<name below>.rpm

The image the installer installs lists its own packages, with their licences and sources, in
/usr/share/licenses/amethystora/SOURCES. NOTICE, beside this file, carries the written offer for the
source of everything on the ISO.
""")
print("\n".join(sorted(packages)))
