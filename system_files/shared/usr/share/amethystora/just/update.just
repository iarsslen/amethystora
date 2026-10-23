# vim: set ft=make :

# Update system, flatpaks and homebrew packages all at once; restart to finish, in seconds when the kernel stays
[positional-arguments]
update ACTION="":
    #!/usr/bin/bash
    # shellcheck source=/dev/null
    source gettext.sh
    # A soft reboot: only the system starts again, not the computer (amethystora-soft-reboot)
    if [[ "$1" == restart ]]; then
        /usr/libexec/amethystora-soft-reboot restart && exit 0
        status=$?
        [[ ${status} == 1 ]] && echo "$(gettext "To restart as usual: systemctl reboot")" >&2
        exit "${status}"
    elif [[ -n "$1" ]]; then
        echo "Usage: ame update [restart]" >&2
        exit 2
    fi
    if systemctl cat -- uupd.timer &> /dev/null; then
        SERVICE="uupd.service"
    else
        SERVICE="rpm-ostreed-automatic.service"
    fi
    if systemctl is-active --quiet "$SERVICE"; then
        echo "$(eval_gettext "automatic updates are currently running, use \`journalctl -fexu \${SERVICE}\` to see logs")"
        exit 1
    fi
    if grep -q -E -e "LockLayering=false" /etc/rpm-ostreed.conf ; then
        rpm-ostree upgrade
    else
        sudo bootc upgrade
    fi
    # rpm-ostree used due to bootc upgrade not supporting local layered packages
    # Updates system Flatpaks
    if flatpak remotes | grep -q system; then
        flatpak update -y
    fi
    # Update user Flatpaks
    if flatpak remotes | grep -q user; then
        flatpak update --user -y
    fi
    # Guard Brew if the user does not own brew/doesn't exist
    if [[ -O /var/home/linuxbrew/.linuxbrew/bin/brew ]]; then
        # Upgrade will run brew update if needed
        /var/home/linuxbrew/.linuxbrew/bin/brew upgrade
    fi
