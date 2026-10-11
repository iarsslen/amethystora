#!/usr/bin/bash
# A machine with no account yet, as an installer leaves one that did not make it: GNOME's first-run setup
# starts on its own account, and none of Amethystora's per-account setup runs in it (the Manual's welcome page
# once opened behind it).
source "$(dirname "$0")/lib.sh"

if getent passwd "${TEST_USER}" >/dev/null; then
    skip "an account exists already, so there is no first run to look at"
    finish
fi
# By its path: pgrep -x sees only the first 15 characters of a process's name
if wait_for 180 pgrep -u gnome-initial-setup -f /usr/libexec/gnome-initial-setup; then
    ok "GNOME's first-run setup started"
    sleep 60
    check "no Amethystora setup ran for the first-run account" sh -c '! pgrep -u gnome-initial-setup -f "amethystora-manual|amethystora-layout-offer"'
else
    not_ok "GNOME's first-run setup did not start" "$(loginctl list-sessions --no-legend)"
fi
finish
