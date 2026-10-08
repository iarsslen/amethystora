#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# System hardening that needs more than the files in system_files (sysctl.d, modprobe.d, bootc kargs.d,
# sshd_config.d). Runs after 07-debrand.sh, which gives the kernel's certificate its Amethystora name.

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

# Root's sudo PATH: ublue-os/main appends /home/linuxbrew/.linuxbrew/bin to secure_path in /etc/sudoers,
# and brew-setup.service gives that directory to the first user. Anything they put there would run as root
# from `sudo <name>`. Drop it; `sudo /home/linuxbrew/.linuxbrew/bin/<name>` still works.
if grep -qE "^Defaults[[:space:]]+secure_path.*linuxbrew" /etc/sudoers; then
    sed -i -E '/^Defaults[[:space:]]+secure_path/ s|:?/home/linuxbrew/\.linuxbrew/bin||' /etc/sudoers
    grep -qE "^Defaults[[:space:]]+secure_path.*linuxbrew" /etc/sudoers && false
    visudo -c -q -f /etc/sudoers
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

# Fingerprint login, which the installer turns on wherever pam_fprintd is installed. authselect.conf lists
# features in the order they were turned on and the installer's comes after the image's, so it has to be the
# image's last too: then an installed machine's /etc/authselect is the image's own to the byte, and not five
# settings the security report calls changed on this machine.
test -e /usr/lib64/security/pam_fprintd.so
authselect enable-feature with-fingerprint

# Parental Controls' allowed hours at the text consoles and over SSH. GNOME Shell locks a child's desktop
# when its time runs out and will not unlock it until the time comes round again, but a text console or an
# SSH login never meets that lock. There pam_malcontent refuses the account outside its hours, and hands
# what is left to pam_systemd, whose session is closed when that runs out. GDM's own services are left
# out on purpose: there it would close the desktop, unsaved work and all, where GNOME's lock keeps it.
#
# Only its verdict, "no time left" (auth_err), refuses. Its errors, no system bus or an account
# accountsservice does not know, let the login through, and the leading - skips the line if the module is
# ever missing. Administrators skip it: they can lift their own limits, and the module tells every account
# without any that it has none. Both lines go before the include, because the sssd and winbind profiles
# end the account stack early for every local account (pam_localuser.so is sufficient there), so a line
# after it would stop running once the machine joined a domain.
test -e /usr/lib64/security/pam_malcontent.so
for service in login sshd; do
    awk '!done && /^account[[:space:]]+include[[:space:]]/ {
            print "account    [success=1 default=ignore]                  pam_succeed_if.so quiet user ingroup wheel"
            print "-account   [success=ok auth_err=die default=ignore]    pam_malcontent.so"
            done = 1
        }
        { print }
        END { exit !done }' "/etc/pam.d/${service}" >"/tmp/${service}.pam"
    # Written over rather than moved, so that the file keeps its mode and label
    cat "/tmp/${service}.pam" >"/etc/pam.d/${service}"
    rm "/tmp/${service}.pam"
done

# Audit: the rule set has to be the last word, and it has to survive a full disk.
#
# augenrules concatenates /etc/audit/rules.d/*.rules in name order and loads the result. The file the
# audit package ships is called audit.rules, and a letter sorts after a digit, so it lands after every
# numbered file in the directory. Its first rule is -D, "delete every rule loaded so far", which would
# quietly erase the watches in 60-amethystora.rules and everything the boot-time generator adds after
# them. Give it a name that sorts first, which is where its buffer settings belong anyway.
if [[ -f /etc/audit/rules.d/audit.rules ]]; then
    mv /etc/audit/rules.d/audit.rules /etc/audit/rules.d/10-base.rules
fi
# Nothing may sort after the file that closes the rule set with -e 2. C collation, because that is what
# augenrules sorts with in a service that has no locale of its own.
LAST_RULES="$(find /etc/audit/rules.d -name '*.rules' -printf '%f\n' | LC_ALL=C sort | tail -n1)"
[[ "${LAST_RULES}" == "99-amethystora-finalize.rules" ]]
# A watch needs its path to exist when the rules load, and one that does not stops the rest loading.
# Quadlets are the one watched directory nothing is guaranteed to have created.
install -d -m 0755 /etc/containers/systemd

# How much log is kept and what happens when the disk fills. Deliberately not the answer the hardening
# guides give: space_left_action = halt, and the rest of that family, turn a full disk into a laptop
# that stops in the middle of what somebody was doing, or will not boot at all. A gap in the audit log
# is the lesser loss by a wide margin. So: rotate, keep about 250MB of history, and say so in the
# journal rather than stopping the machine.
sed -i -E \
    -e 's|^max_log_file[[:space:]]*=.*|max_log_file = 32|' \
    -e 's|^num_logs[[:space:]]*=.*|num_logs = 8|' \
    -e 's|^max_log_file_action[[:space:]]*=.*|max_log_file_action = ROTATE|' \
    -e 's|^space_left_action[[:space:]]*=.*|space_left_action = SYSLOG|' \
    -e 's|^admin_space_left_action[[:space:]]*=.*|admin_space_left_action = SYSLOG|' \
    -e 's|^disk_full_action[[:space:]]*=.*|disk_full_action = ROTATE|' \
    -e 's|^disk_error_action[[:space:]]*=.*|disk_error_action = SYSLOG|' \
    /etc/audit/auditd.conf
grep -q "^max_log_file = 32$" /etc/audit/auditd.conf
grep -qiE "^(space_left_action|admin_space_left_action|disk_full_action|disk_error_action) = (halt|single|suspend)$" \
    /etc/audit/auditd.conf && false

# Secure Boot certificates, readable by everyone. akmods keeps /etc/pki/akmods/certs at 0750
# root:akmods because the private keys go beside them, and that leaves a normal user unable to see the
# public certificates are there at all: every "is this key enrolled" check run without sudo concluded
# the files did not exist. They are public by definition, so a copy goes where anyone can read it,
# and /usr/libexec/amethystora-mok-status and `ame security secure-boot` work from the copy.
# After 07-debrand.sh, which gives the kernel's certificate its Amethystora name.
SB_CERTS=/usr/share/amethystora/secure-boot
install -Dpm0644 /etc/pki/akmods/certs/amethystora-modules.der "${SB_CERTS}/amethystora-modules.der"
if [[ -f /etc/pki/akmods/certs/akmods-amethystora.der ]]; then
    install -Dpm0644 /etc/pki/akmods/certs/akmods-amethystora.der "${SB_CERTS}/akmods-amethystora.der"
else
    echo "::warning::no akmods-amethystora.der, the kernel's certificate is left out of ${SB_CERTS}"
fi

# Kernel lockdown. In integrity mode the kernel refuses the operations that let root rewrite the kernel
# it is running: loading a module without a signature it trusts, opening /dev/mem, kexec of an unsigned
# image, and BPF that writes into a running program's memory. A root compromise then ends at the next
# reboot instead of moving into the kernel, where nothing running on the machine can find it. BPF that
# only reads, as bpftrace and eBPF security sensors do, is refused by confidentiality mode alone.
#
# Fedora's x86 kernel locks itself down in integrity mode whenever it starts with Secure Boot
# (CONFIG_LOCK_DOWN_IN_EFI_SECURE_BOOT, which 20-tests.sh checks), whatever the arguments say. So this
# argument only decides it on a machine with Secure Boot off, and there it has a real cost: modules
# signed with the machine owner key rather than Fedora's are only trusted once Secure Boot is on and the
# key is enrolled, so such a machine loses the modules built with the image (evdi, for DisplayLink
# docks). Run `ame security secure-boot` and turn Secure Boot on, or, on a machine where that is not
# possible, `ame security lockdown off`, which takes the argument off that machine for good.
# Hibernation is also refused under lockdown; this image does not set it up (swap is zram, and no
# resume= argument is set), so nothing here depends on it.
#
# Not applied to the NVIDIA images at all: their driver is an akmods build signed with the same machine
# owner key, and a machine that booted without a graphics driver would have no way to read this comment.
# With Secure Boot on they are locked down all the same, by the kernel itself.
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    echo "NVIDIA image: leaving kernel lockdown off, the driver is a machine-owner-key module"
else
    tee /usr/lib/bootc/kargs.d/11-amethystora-lockdown.toml >/dev/null <<'KARGS'
# Kernel lockdown, set in build_files/base/08-hardening.sh. See the comment there before changing it.
kargs = ["lockdown=integrity"]
KARGS
    grep -q '"lockdown=integrity"' /usr/lib/bootc/kargs.d/11-amethystora-lockdown.toml
fi

# The image has no cron, so nothing runs what packages leave in /etc/cron.daily. Root's only, as the
# other cron directories are expected to be (Lynis FILE-7524).
if [[ -d /etc/cron.daily ]]; then
    chmod 0700 /etc/cron.daily
fi

# Lynis knows a system by the ID in /etc/os-release and reports every ID it has no case for as an
# exception, at the top of each audit. This one is Fedora underneath, so it gets Fedora's case.
sed -i 's/^\([[:space:]]*\)"fedora")$/\1"fedora" | "amethystora")/' /usr/share/lynis/include/osdetection
grep -q '"fedora" | "amethystora")' /usr/share/lynis/include/osdetection

echo "::endgroup::"
