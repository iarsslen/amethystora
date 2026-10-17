#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# The Amethystora apps: the Manual (Super+F1), Security, Updates, Notes, Logs, Backups and Control. They are
# one program, written in Rust with GTK 4 and libadwaita (apps/), which the Containerfile's apps stage built
# on this same base, and which picks the app by the name it is started as: each app's own path is a hard
# link to it, so that /usr/bin/amethystora-<app>, the process names and the launchers stay as they were.
# What else the apps need is in system_files already: each app's translations in
# /usr/lib/amethystora-<app>/resources/app/locale, where Weblate writes them (CONTRIBUTING.md), the manual's
# pages in /usr/share/amethystora/manual, and the launchers.
#
#   - Quicksand, the face of the Amethystora wordmark, which the windows draw it in. The image has no system
#     copy of it; the Containerfile brings branding/fonts into the build context.
#   - The licences of the Rust crates built into the program, beside the list of them (CRATES).

APPS_DIR=/usr/lib/amethystora-apps
LICENSE_DIR=/usr/share/licenses/amethystora-apps

install -Dpm0755 /apps-stage/out/amethystora-apps "${APPS_DIR}/amethystora-apps"
for app in manual security update notes logs backups control; do
    install -d "/usr/lib/amethystora-${app}"
    ln -f "${APPS_DIR}/amethystora-apps" "/usr/lib/amethystora-${app}/amethystora-${app}"
done

# The file-watch sensor is a binary of its own (no GTK), not one of the windowed apps: it loads a BPF object
# and writes audit records for the security watcher (plans/security/PLAN-audit-cost.md). Its BPF object is
# Amethystora's own code, dual-licensed so it may use the kernel's GPL-only BPF helpers; the Rust crates
# built into it are listed with the apps' in ${LICENSE_DIR}/crates.
install -Dpm0755 /apps-stage/out/amethystora-sensor /usr/libexec/amethystora-sensor
install -Dpm0644 /ctx/apps/sensor/src/bpf/COPYING /usr/share/licenses/amethystora-sensor/COPYING

install -Dpm0644 /ctx/branding/fonts/QuicksandVariable.ttf "${APPS_DIR}/fonts/QuicksandVariable.ttf"
install -Dpm0644 /ctx/branding/fonts/Quicksand-OFL.txt "${LICENSE_DIR}/Quicksand-OFL.txt"
install -d "${LICENSE_DIR}/crates"
cp -a /apps-stage/out/licenses/. "${LICENSE_DIR}/crates/"

# The apps' launchers in the languages the apps are translated into: their names, what they are and what
# to find them by, from the same catalogs as the windows' own words
python3 /ctx/build_files/shared/translate-desktop.py /

echo "::endgroup::"
