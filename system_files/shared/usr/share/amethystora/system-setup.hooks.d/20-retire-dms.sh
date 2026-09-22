#!/usr/bin/env bash
#
# Remove what the Hyprland era left on the machine itself.
#
# From commits 44a4524a to 0e3e0cbf the image shipped Hyprland, DankMaterialShell and its login
# screen (greetd with dms-greeter). A new image replaces /usr, and /etc loses every file nobody
# changed, but three things outlive it: /var, accounts in /etc/passwd, and whatever in /etc was
# edited on the machine. The greeter left something in all three - its home and cache under /var,
# its own `greeter` account, greetd's config - and enabling its services left links in /etc.
#
# The account's own leftovers are for user-setup.hooks.d/09-retire-dms.sh, which runs as each user.

source /usr/lib/amethystora/setup-services/libsetup.sh

version-script retire-dms system 1 || exit 0

set -x

# None of these are in the image any more. A machine that has layered one back on is using it, and is
# left exactly as it is.
for package in greetd dms-greeter dms quickshell hyprland; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        echo "${package} is installed on this machine, leaving the Hyprland era's files alone"
        exit 0
    fi
done

rm -rf /var/cache/dms-greeter /var/lib/greeter /etc/greetd /etc/dms

# The greeter's account, recognised by the home dms-greeter gave it, so no other account called
# `greeter` is ever touched. userdel takes its group with it when nothing else is in it.
if [[ "$(getent passwd greeter | cut -d: -f6)" == /var/lib/greeter ]]; then
    userdel greeter
fi

# Links left by enabling greetd and DMS, pointing at units that left with the image. Only links that
# resolve to nothing: display-manager.service is not among them, and GDM keeps it.
find /etc/systemd/system /etc/systemd/user \( -name 'greetd.service' -o -name 'dms.service' \) \
    -xtype l -delete 2>/dev/null

# The labels 04-hyprland.sh gave the greeter's directories, on a machine where they were kept
if grep -qsE 'dms-greeter|/var/lib/greeter' /etc/selinux/targeted/contexts/files/file_contexts.local; then
    semanage fcontext -d '/var/cache/dms-greeter(/.*)?'
    semanage fcontext -d '/var/lib/greeter(/.*)?'
fi

exit 0
