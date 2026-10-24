#!/usr/bin/env bash
#
# Hand an account over from GSConnect to Amethystora Connect, which took its place in the image
# (plans/PLAN-amethystora-connect.md). The new program starts clean: it keeps its own certificate and its own
# pairings (~/.config/amethystora/connect), and takes nothing from GSConnect's. So an account that used GSConnect
# has the phone link on again, and is told once, a minute into the login, to pair its phone again. 22-retire-extensions.sh
# then resets GSConnect's own folder. Not while the account's own copy of GSConnect is installed, which is still
# running there.
#
# "Used" means a phone was paired in it, not that the extension was enabled: GSConnect was in the image's default list
# of extensions until October 2026, and 15-extensions.sh copied that default into each account's own list, so being
# there says nothing about a choice. The phone link opens ports on the home networks, so it is never turned on for an
# account that did not pair a phone.

source /usr/lib/amethystora/setup-services/libsetup.sh

[[ -e "${XDG_DATA_HOME:-${HOME}/.local/share}/gnome-shell/extensions/gsconnect@andyholmes.github.io" ]] && exit 0
command -v dconf >/dev/null && command -v gsettings >/dev/null || exit 0

version-script phone-link user 1 || exit 0

# GSConnect's schema left the image with it, so its devices are read from dconf: a list of the paired phones' ids
[[ "$(dconf read /org/gnome/shell/extensions/gsconnect/devices 2>/dev/null)" == *"'"* ]] || exit 0

# Outside a session there is no manager to start it: the next login does
systemctl --user enable --now amethystora-connect.service 2>/dev/null || systemctl --user enable amethystora-connect.service 2>/dev/null

systemd-run --user --collect --quiet --on-active=60 -- /usr/libexec/amethystora-phone-link-notice

exit 0
