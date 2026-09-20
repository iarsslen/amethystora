#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# System hardening that needs more than the files in system_files (sysctl.d, modprobe.d, bootc kargs.d,
# sshd_config.d). Runs after 07-debrand.sh, which removes the upstream entries from policy.json.

# Signed updates: images from ghcr.io/iarsslen are only accepted with a cosign signature made with the key
# CI signs them with (cosign.pub, installed as /etc/pki/containers/amethystora.pub by the Containerfile).
# The sigstore attachments are looked up as set in /etc/containers/registries.d/amethystora.yaml.
# Other registries keep Fedora's default, so pulling other container images works as before.
test -s /etc/pki/containers/amethystora.pub
jq '.transports.docker["ghcr.io/iarsslen"] = [{
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/containers/amethystora.pub",
        "signedIdentity": {"type": "matchRepository"}
    }]' /etc/containers/policy.json >/tmp/policy.json
mv /tmp/policy.json /etc/containers/policy.json
chmod 0644 /etc/containers/policy.json

# Root without a password: projectbluefin/common lets *any* user run the privileged setup helper as root
# through polkit (allow_any=yes), which includes inactive and remote sessions. Keep it for the user sitting
# at the machine, whose first login runs the hooks in /usr/share/amethystora/privileged-setup.hooks.d,
# and refuse it to everyone else.
POLICY=(/usr/share/polkit-1/actions/*privileged.user.setup.policy)
if [[ -f "${POLICY[0]}" ]]; then
    sed -i -E \
        -e 's|<allow_any>[^<]*</allow_any>|<allow_any>no</allow_any>|' \
        -e 's|<allow_inactive>[^<]*</allow_inactive>|<allow_inactive>no</allow_inactive>|' \
        "${POLICY[0]}"
    grep -q "<allow_any>no</allow_any>" "${POLICY[0]}"
else
    echo "::warning::privileged setup polkit action not found, check build_files/base/08-hardening.sh"
fi

# Root's sudo PATH: ublue-os/main appends /home/linuxbrew/.linuxbrew/bin to secure_path in /etc/sudoers,
# and brew-setup.service gives that directory to the first user. Anything they put there would run as root
# from `sudo <name>`. Drop it; `sudo /home/linuxbrew/.linuxbrew/bin/<name>` still works.
if grep -qE "^Defaults[[:space:]]+secure_path.*linuxbrew" /etc/sudoers; then
    sed -i -E '/^Defaults[[:space:]]+secure_path/ s|:?/home/linuxbrew/\.linuxbrew/bin||' /etc/sudoers
    grep -qE "^Defaults[[:space:]]+secure_path.*linuxbrew" /etc/sudoers && false
    visudo -c -q -f /etc/sudoers
fi

# USB devices readable and writable by everyone: the ZSA keyboard flashing rules hand out MODE 0666 on
# whole vendor IDs shared by many hobby devices. uaccess gives the same access to the user at the seat only.
if [[ -f /usr/lib/udev/rules.d/50-zsa.rules ]]; then
    sed -i 's|MODE:="0666"|MODE="0660", TAG+="uaccess"|g' /usr/lib/udev/rules.d/50-zsa.rules
    grep -q 'MODE:="0666"' /usr/lib/udev/rules.d/50-zsa.rules && false
fi

# Firewall: Fedora Workstation's default zone accepts incoming connections on every port from 1025 up.
# The Amethystora zone (/usr/lib/firewalld/zones/amethystora.xml) only lets in what a desktop needs.
# Tailscale traffic is trusted: who may reach this machine over the tailnet is set by the tailnet's ACLs,
# and Taildrop and Tailscale SSH need incoming connections.
firewall-offline-cmd --set-default-zone=amethystora
firewall-offline-cmd --zone=trusted --add-interface=tailscale0

# Repeated failed logins from one address: fail2ban watches the journal and has firewalld reject that
# address for a while (/etc/fail2ban/jail.d/10-amethystora.conf, enabled in 17-cleanup.sh).
# Its firewalld action bans in the zone named in that file, and that has to be the zone set above:
# a rich rule in a zone no interface uses never matches anything, so the ban would do nothing at all.
test -f /etc/fail2ban/action.d/firewallcmd-rich-rules.conf
F2B_ZONE="$(sed -n 's/^banaction[a-z_]* = firewallcmd-rich-rules\[.*zone=\([^]]*\)\]$/\1/p' \
    /etc/fail2ban/jail.d/10-amethystora.conf | sort -u)"
[[ "${F2B_ZONE}" == "$(firewall-offline-cmd --get-default-zone)" ]]

# Lock an account for 10 minutes after 10 wrong passwords in a row, against guessing at the login and lock
# screens, sudo and polkit prompts. Settings in /etc/security/faillock.conf.
authselect enable-feature with-faillock

echo "::endgroup::"
