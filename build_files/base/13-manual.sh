#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The Amethystora Manual (amethystora-manual, Super+F1): the Markdown pages in
# /usr/share/amethystora/manual, shown by an Electron app in /usr/lib/amethystora-manual. The app
# itself (main.js, its page, script and stylesheet) comes from system_files and is already in place;
# this adds the two things it runs on. Both are pinned, and Renovate bumps them (.github/renovate.json5):
#
#   - Electron, from its GitHub release. Fedora does not package it, and npm is kept out of the image
#     build (build-gnome-extensions.sh), so the release archive is used, checked against the
#     checksum Electron publishes beside it.
#   - marked, which renders the Markdown, from the npm registry's tarball, checked against the
#     integrity the registry states for it.
#
# The window only ever loads the manual's own pages (main.js), so the Chromium inside it never renders
# anything from the web. It still takes every Electron release, security fixes included.

ELECTRON_VERSION="44.4.5"
MARKED_VERSION="18.0.14"
MANUAL_DIR=/usr/lib/amethystora-manual
LICENSE_DIR=/usr/share/licenses/amethystora-manual

case "$(uname -m)" in
    x86_64) ELECTRON_ARCH=x64 ;;
    aarch64) ELECTRON_ARCH=arm64 ;;
esac
ELECTRON_ZIP="electron-v${ELECTRON_VERSION}-linux-${ELECTRON_ARCH}.zip"
ELECTRON_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}"

ghcurl "${ELECTRON_URL}/${ELECTRON_ZIP}" --fail --retry 3 -o "/tmp/${ELECTRON_ZIP}"
ghcurl "${ELECTRON_URL}/SHASUMS256.txt" --fail --retry 3 -o /tmp/electron-SHASUMS256.txt
grep -F " *${ELECTRON_ZIP}" /tmp/electron-SHASUMS256.txt | (cd /tmp && sha256sum -c -)

# The app is already in resources/app, which Electron runs in preference to its default app
unzip -q -o "/tmp/${ELECTRON_ZIP}" -d "${MANUAL_DIR}"
mv "${MANUAL_DIR}/electron" "${MANUAL_DIR}/amethystora-manual"
rm -f "${MANUAL_DIR}/resources/default_app.asar"
# Chromium sandboxes the page with user namespaces, which 60-amethystora-hardening.conf leaves on for
# exactly this. The setuid helper it would otherwise fall back to is one more root-owned binary for
# nothing, and it is not setuid in the archive anyway.
rm -f "${MANUAL_DIR}/chrome-sandbox"
# The manual is in English, and so is the little of Chromium's own text it can show
find "${MANUAL_DIR}/locales" -name '*.pak' ! -name 'en-US.pak' -delete
install -Dpm0644 -t "${LICENSE_DIR}" "${MANUAL_DIR}/LICENSE" "${MANUAL_DIR}/LICENSES.chromium.html"
rm -f "${MANUAL_DIR}/LICENSE" "${MANUAL_DIR}/LICENSES.chromium.html" \
    "/tmp/${ELECTRON_ZIP}" /tmp/electron-SHASUMS256.txt

curl --fail --retry 3 -sSL -o /tmp/marked.tgz "https://registry.npmjs.org/marked/-/marked-${MARKED_VERSION}.tgz"
MARKED_INTEGRITY="$(curl --fail --retry 3 -sSL "https://registry.npmjs.org/marked/${MARKED_VERSION}" | jq -r .dist.integrity)"
[[ "${MARKED_INTEGRITY}" == "$(python3 -c 'import base64, hashlib, sys
print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1], "rb").read()).digest()).decode())' /tmp/marked.tgz)" ]]
tar -xzf /tmp/marked.tgz -C /tmp package/lib/marked.umd.js package/LICENSE
install -Dpm0644 /tmp/package/lib/marked.umd.js "${MANUAL_DIR}/resources/app/marked.umd.js"
install -Dpm0644 /tmp/package/LICENSE "${LICENSE_DIR}/marked/LICENSE"
rm -rf /tmp/marked.tgz /tmp/package

echo "::endgroup::"
