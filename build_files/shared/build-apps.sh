#!/usr/bin/bash
# The Containerfile's apps stage: the Amethystora apps (apps/, a Cargo workspace), built with Fedora's Rust
# on the same base image they run on, so that they link against the GTK and libadwaita the image has. The
# tests run first: the shared crate's, which hold every date, number and list to what the Electron windows
# wrote, and every app's, Notes' among them reading and writing the Electron window's own files. Only the
# program and the licences of the crates built into it leave the stage, in /out (13-apps.sh installs them):
# the toolchain and the crates' sources stay here, and the build itself is cleared away once done. The
# stage's Node runs Notes' tests of the Electron side, and the checks written in JavaScript in 20-tests.sh.
#
# Cargo.lock pins every crate by version and checksum (--locked), and the crates come from crates.io, which
# serves them by that checksum.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The toolchain and the libraries' headers from Fedora's own repositories alone (build-fprintd.sh says why)
dnf5 -y install --repo=fedora --repo=updates --setopt=install_weak_deps=False \
    rust cargo gcc gtk4-devel libadwaita-devel jq nodejs

# The workspace is copied out of the read-only context, and built outside it
cp -a /ctx/apps /tmp/apps
cd /tmp/apps
export CARGO_TARGET_DIR=/tmp/target CARGO_HOME=/tmp/cargo CARGO_TERM_COLOR=never
cargo fetch --locked

# The golden tests of the shared crate compare with what Chromium wrote in UTC. One thread: Notes' tests
# run its timers on GLib's default main context, which only one thread may own
TZ=UTC cargo test --release --locked --workspace -- --test-threads=1
cargo build --release --locked -p amethystora-apps

mkdir -p /out/licenses
install -Dpm0755 "${CARGO_TARGET_DIR}/release/amethystora-apps" /out/amethystora-apps

# Every crate built into the program (its normal dependencies: build tools and test-only crates are not in
# it), with its licence, and the licence and notice files it ships: most are MIT or Apache-2.0, whose
# terms ask for their notices to travel with the program
cargo tree --locked -p amethystora-apps -e normal --prefix none --format '{p}' |
    sed -n 's/^\([^ ]*\) v\([^ ]*\)\( (\*)\)\{0,1\}$/\1\t\2/p' | sort -u >/tmp/built.tsv
cargo metadata --locked --format-version 1 >/tmp/metadata.json
jq -r '.packages[] | select(.source != null)
    | [.name, .version, (.license // "see its licence file"), (.repository // ""), (.manifest_path | sub("/Cargo.toml$"; ""))]
    | @tsv' /tmp/metadata.json | sort -u >/tmp/packages.tsv
printf '# The Rust crates built into /usr/lib/amethystora-apps/amethystora-apps: name, version, licence, source\n' \
    >/out/licenses/CRATES
missing=()
while IFS=$'\t' read -r name version licence repository folder; do
    grep -qxF "${name}"$'\t'"${version}" /tmp/built.tsv || continue
    printf '%s\t%s\t%s\t%s\n' "${name}" "${version}" "${licence}" "${repository}" >>/out/licenses/CRATES
    mkdir -p "/out/licenses/${name}-${version}"
    find "${folder}" -maxdepth 1 -type f \( -iname 'LICEN[CS]E*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'COPYRIGHT*' -o -iname 'UNLICENSE*' \) \
        -exec install -pm0644 -t "/out/licenses/${name}-${version}" {} +
    rmdir "/out/licenses/${name}-${version}" 2>/dev/null && missing+=("${name}-${version}")
done </tmp/packages.tsv
# Every crate in the program is listed, and one that ships no licence file of its own stops the build, so
# that its licence is looked at before it reaches the image
[[ "$(($(wc -l </out/licenses/CRATES) - 1))" == "$(wc -l </tmp/built.tsv)" ]]
if ((${#missing[@]})); then
    echo "::error::crates with no licence file of their own: ${missing[*]}"
    exit 1
fi
ls -l /out
echo "$(($(wc -l </out/licenses/CRATES) - 1)) crates, each with its licence"

cd /
rm -rf /tmp/apps /tmp/target /tmp/cargo /tmp/built.tsv /tmp/packages.tsv /tmp/metadata.json /tmp/amethystora-notes-test-*

echo "::endgroup::"
