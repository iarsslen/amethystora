#!/usr/bin/bash
#
# Pick a look, once, for a new account: Control's welcome page (theme, style, dock, pointer, windows), a few seconds
# after the Manual's welcome page (17-welcome.sh) so that it opens on top of it. An account that existed before this
# hook came is left alone: its look is already its own. The page writes first-look.json when it shows, and the offer
# of classic windows 17-welcome.sh makes steps aside for it, since the page's Windows row asks the same.
#
# Once.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script first-look user 1 || exit 0

# Shown already (a home restored or brought along, an image's own seed): never again over the person's own record
[[ -e "${XDG_STATE_HOME:-${HOME}/.local/state}/amethystora/first-look.json" ]] && exit 0

# A home folder whose birth the file system does not keep (0) counts as an existing account
born="$(stat -c %W -- "${HOME}" 2>/dev/null || echo 0)"
[[ "${born}" =~ ^[0-9]+$ ]] || born=0
((born > 0 && $(date +%s) - born < 86400)) || exit 0

systemd-run --user --collect --quiet --on-active=3 -- /usr/bin/amethystora-control welcome
exit 0
