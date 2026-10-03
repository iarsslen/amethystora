# vim: set ft=make :

set default-list

# Log in, unlock the screen and approve sudo with a FIDO2 security key (YubiKey, Thetis, and their fingerprint models)
key ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    # Keys are bound to the origin set in /etc/security/pam_u2f.conf, not to the hostname
    origin="pam://amethystora"
    keys="${HOME}/.config/Yubico/u2f_keys"
    action="{{ ACTION }}"
    if [[ -z "${action}" ]]; then
        registered="$(awk -F: -v user="${USER}" '$1 == user { print NF - 1 }' "${keys}" 2>/dev/null || true)"
        echo "Security keys registered for ${USER}: ${registered:-0}"
        action="$(gum choose --header "Security key login" "Add a key" "Add a fingerprint key" "Remove all keys" "Cancel")"
    fi
    case "${action}" in
        "Add a key" | add)
            flags=()
            ;;
        "Add a fingerprint key" | add-fingerprint)
            # The key checks the fingerprint itself (FIDO2 user verification), a touch alone is not enough
            flags=(--user-verification)
            echo "The key needs a PIN and an enrolled fingerprint. Enroll one in Firefox at about:webauthn,"
            echo "or on a YubiKey Bio with: ykman fido fingerprints add <name>"
            ;;
        "Remove all keys" | remove)
            rm -f "${keys}"
            echo "Security keys removed, sign in with your password"
            exit 0
            ;;
        *)
            exit 0
            ;;
    esac
    echo "Insert the key, then touch it when it blinks (fingerprint keys: with an enrolled finger)"
    credential="$(pamu2fcfg --nouser --origin="${origin}" --appid="${origin}" "${flags[@]}")"
    # One line per user: user:credential1:credential2...
    mkdir -p "$(dirname "${keys}")"
    line="$(grep "^${USER}:" "${keys}" 2>/dev/null || echo "${USER}")"
    (umask 077 && printf '%s%s\n' "${line}" "${credential}" >"${keys}.new")
    mv "${keys}.new" "${keys}"
    # The login screen and sudo may only read it with its SELinux label (auth_home_t)
    restorecon -R "$(dirname "${keys}")"
    echo "Security key added. Touch it to sign in, to unlock the screen and to approve sudo."
    echo "Your password keeps working."

# Let Secure Boot load the kernel modules shipped in the image (DisplayLink, v4l2loopback, ...)
secure-boot:
    #!/usr/bin/bash
    set -euo pipefail
    ENROLLMENT_PASSWORD="amethystora"
    # One check, shared with `ame security status` (/usr/libexec/amethystora-mok-status). A missing
    # certificate is reported as missing, never counted as enrolled.
    MOK="$(/usr/libexec/amethystora-mok-status)"
    certs=()
    while read -r state cert rest; do
        case "${state}" in
            not-enrolled) certs+=("${cert}") ;;
            pending) echo "${cert} is waiting for the next boot: finish it in the blue MOK manager screen." ;;
            missing) echo "${cert} is not on this machine, so it can be neither checked nor enrolled." ;;
            unknown) echo "Could not tell whether ${cert} is enrolled. mokutil said: ${rest}" ;;
        esac
    done <<<"${MOK}"
    if [[ ${#certs[@]} -eq 0 ]]; then
        grep -qv "^enrolled " <<<"${MOK}" || echo "The Secure Boot keys are already enrolled."
        exit 0
    fi
    sudo mokutil --timeout -1
    printf '%s\n%s\n' "${ENROLLMENT_PASSWORD}" "${ENROLLMENT_PASSWORD}" | sudo mokutil --import "${certs[@]}"
    echo "At next reboot, the blue MOK manager screen appears (QWERTY keyboard layout)."
    echo "Select \"Enroll MOK\", then \"Continue\", \"Yes\", and type \"${ENROLLMENT_PASSWORD}\" as the password."

# What the security settings are actually doing, and what to do about anything off. Changes nothing
status:
    @/usr/libexec/amethystora-security-status

# Audit this machine's security settings with Lynis and say what to do about each finding
audit:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Auditing this machine. It takes a few minutes and changes nothing."
    echo "Settings for the audit are in /etc/lynis/custom.prf."
    echo
    # Lynis reads files only root can read; without sudo it silently skips those tests
    sudo lynis audit system
    echo
    echo "Full output: /var/log/lynis.log"
    echo "Findings, one per line: /var/log/lynis-report.dat"
    echo
    echo "The monthly audit compares each run with the one before and reports only what is new."
    echo "What it said last time: journalctl -u amethystora-lynis-audit.service"

# What happens to files a virus scan finds, real-time watching and network protection (security.conf)
settings SETTING="" VALUE="":
    #!/usr/bin/bash
    set -euo pipefail
    config=/usr/libexec/amethystora-security-config
    detection="$(${config} ON_DETECTION)"
    realtime="$(${config} REALTIME)"
    network="$(${config} NETWORK)"
    echo "Files a virus scan finds:  ${detection}"
    echo "Real-time watching:        ${realtime}"
    echo "Network protection:        ${network}"
    echo
    setting="{{ SETTING }}"
    value="{{ VALUE }}"
    if [[ -z "${setting}" ]]; then
        setting="$(gum choose --header "Security settings" "on-detection" "realtime" "network" "Cancel")"
    fi
    case "${setting}" in
        on-detection)
            if [[ -z "${value}" ]]; then
                echo "report      Say so, and leave the file where it is (the default)."
                echo "quarantine  Move it where nothing can open it. ame security scan restore puts it back."
                echo "delete      Delete it. A match can be a false positive, and this cannot be undone."
                value="$(gum choose --header "Files a virus scan finds" report quarantine delete)"
            fi
            if [[ "${value}" == delete ]]; then
                gum confirm "Delete what scans find, with no way to get it back?" || exit 0
            fi
            sudo "${config}" set ON_DETECTION "${value}"
            echo "Files a virus scan finds: ${value}. This applies to the weekly scan, the scans you start"
            echo "in the Security app, and real-time scanning."
            ;;
        realtime)
            if [[ -z "${value}" ]]; then
                echo "on   Read each change as the audit log records it, and scan every file written in a"
                echo "     home folder as it is closed. Costs some CPU while files are being written."
                echo "off  Look every 15 minutes, and scan weekly (the default)."
                value="$(gum choose --header "Real-time watching" on off)"
            fi
            sudo "${config}" set REALTIME "${value}"
            # The units check the setting as they start (ExecCondition), so a restart applies it either
            # way. The real-time watcher goes on following network protection's alerts while that is on.
            sudo systemctl restart amethystora-security-realtime.service amethystora-clamav-onaccess.service
            if [[ "${value}" == on ]]; then
                echo "On. Real-time scanning starts once clamd has its virus signatures."
            else
                echo "Off."
            fi
            ;;
        network)
            if [[ -z "${value}" ]]; then
                echo "off    Nothing is inspected (the default)."
                echo "watch  Suricata inspects every connection this machine makes and receives, and says"
                echo "       what it recognises. Nothing is blocked. Start here: a week of it shows what"
                echo "       blocking would get in the way of."
                echo "block  As watch, and connections to known malware, command servers and exploits are"
                echo "       cut off. Each one is a notification, and ame security connections allows it again."
                echo "Whatever goes wrong with it, connections go on uninspected rather than stop."
                value="$(gum choose --header "Network protection" off watch block)"
            fi
            sudo "${config}" set NETWORK "${value}"
            if [[ "${value}" == off ]]; then
                sudo systemctl stop amethystora-ips.service
                echo "Off. Nothing is inspected."
            else
                echo "Getting the rules for ${value}. The first download takes a minute or two."
                if ! sudo /usr/libexec/amethystora-ips rules; then
                    echo "The rules could not be downloaded now. They are tried again every day, and until"
                    echo "then Suricata inspects with whatever rules it had, or none."
                fi
                # Already running, the rules step reloaded it; this starts it when it was off
                sudo systemctl start amethystora-ips.service
                echo "On: ${value}. See what it blocks and notices with: ame security connections"
            fi
            # The real-time watcher follows Suricata's alerts while this is on, and the report's view of
            # it is the security watcher's to write
            sudo systemctl restart amethystora-security-realtime.service
            sudo systemctl start --no-block amethystora-security-watch.service
            ;;
        *) exit 0 ;;
    esac

# What the security watcher noticed: accounts, what starts by itself, settings, keyboard readers
events ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    if [[ "{{ ACTION }}" == now ]]; then
        echo "Looking now..."
        sudo systemctl start --wait amethystora-security-watch.service || true
    fi
    sudo /usr/libexec/amethystora-security-watch --show
    echo
    echo "Each line is something that changed, with the program that changed it. If you did it, or"
    echo "installed something that did, there is nothing to do. The full audit record of one kind:"
    echo "sudo ausearch -i -k <identity|privilege|persistence|hardening|modules|input-capture|user-programs>"
    # Seen is seen: what was just shown stops being new, for the report and the next login
    sudo /usr/libexec/amethystora-security-watch --seen

# Connections network protection blocked or noticed, and how to allow one again
connections ACTION="" RULE="":
    #!/usr/bin/bash
    set -euo pipefail
    ips=/usr/libexec/amethystora-ips
    case "{{ ACTION }}" in
        allow | block)
            if [[ -z "{{ RULE }}" ]]; then
                echo "usage: ame security connections {{ ACTION }} <rule number>"
                exit 64
            fi
            sudo "${ips}" "{{ ACTION }}" "{{ RULE }}"
            ;;
        "")
            echo "Network protection: $(/usr/libexec/amethystora-security-config NETWORK) (ame security settings network)"
            echo
            # The watcher is what reads Suricata's log, so what it saw a moment ago is shown too
            sudo systemctl start --wait amethystora-security-watch.service || true
            sudo "${ips}" blocked
            echo
            echo "If a connection was yours and wanted, allow its rule again with:"
            echo "  ame security connections allow <rule number>"
            echo "That leaves the one rule out on this machine; ame security connections block <rule number>"
            echo "puts it back. The rules allowed here are listed in /etc/amethystora/ips-allowed."
            ;;
        *)
            echo "usage: ame security connections [allow <rule number> | block <rule number>]"
            exit 64
            ;;
    esac

# Addresses fail2ban has blocked for too many failed logins, and how to let one back in
addresses ADDRESS="":
    #!/usr/bin/bash
    set -euo pipefail
    if [[ -n "{{ ADDRESS }}" ]]; then
        sudo fail2ban-client set sshd unbanip "{{ ADDRESS }}"
        exit 0
    fi
    sudo fail2ban-client status sshd
    echo
    echo "Let one back in with: ame security addresses <address>"
    echo "Blocking is set up in /etc/fail2ban/jail.d/10-amethystora.conf."

# Turn key remapping on or off. It is off by default: the service reads every key pressed on the machine
input-remapper ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    action="{{ ACTION }}"
    if systemctl is-enabled --quiet input-remapper.service 2>/dev/null; then
        echo "Key remapping is on."
    else
        echo "Key remapping is off. Input Remapper's window still opens, but cannot apply a mapping."
    fi
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Key remapping (Input Remapper)" "Turn on" "Turn off" "Cancel")"
    fi
    case "${action}" in
        "Turn on" | on)
            echo
            echo "The service runs as root and reads every input device on this machine, which is every"
            echo "key typed into every application, password prompts included. That is what remapping a"
            echo "key needs, and it is why this is off unless you ask for it."
            gum confirm "Turn key remapping on?" || exit 0
            sudo systemctl enable --now input-remapper.service
            echo "On. Map keys in the Input Remapper application."
            ;;
        "Turn off" | off)
            sudo systemctl disable --now input-remapper.service
            echo "Off. Saved mappings stay on disk and come back if you turn it on again."
            ;;
        *) exit 0 ;;
    esac

# Refuse USB devices that were not plugged in when this was set up, against keyloggers and keystroke injectors
usb ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    action="{{ ACTION }}"
    if systemctl is-enabled --quiet usbguard.service 2>/dev/null; then
        echo "USB protection is on. Devices allowed so far:"
        sudo usbguard list-devices --allowed | sed 's/^/  /'
    else
        echo "USB protection is off: any USB device plugged in is trusted."
    fi
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "USB protection (USBGuard)" \
            "Turn on" "Allow a blocked device" "Turn off" "Cancel")"
    fi
    case "${action}" in
        "Turn on" | on)
            echo
            echo "A USB device can say it is a keyboard and type by itself, and a keylogger can sit"
            echo "between a real keyboard and this machine. USBGuard blocks anything that was not"
            echo "already plugged in, until you allow it by hand."
            echo
            echo "Plug in everything you use first - keyboard, mouse, dock, webcam, headset, security"
            echo "keys. What is connected now is what gets allowed."
            gum confirm "Everything plugged in?" || exit 0
            # Built from what is connected right now, so the keyboard running this command is allowed
            usbguard generate-policy | sudo tee /etc/usbguard/rules.conf >/dev/null
            sudo chmod 0600 /etc/usbguard/rules.conf
            # Without this only root could list or allow a device, and the prompt below would not work
            sudo sed -i -E 's|^#?IPCAllowedGroups=.*|IPCAllowedGroups=wheel|' /etc/usbguard/usbguard-daemon.conf
            sudo systemctl enable --now usbguard.service
            echo
            echo "On. A USB device plugged in from now on is blocked until you allow it here."
            ;;
        "Allow a blocked device" | allow)
            if ! systemctl is-active --quiet usbguard.service; then
                echo "USB protection is off, so nothing is being blocked."
                exit 1
            fi
            blocked="$(sudo usbguard list-devices --blocked)"
            if [[ -z "${blocked}" ]]; then
                echo "Nothing is blocked."
                exit 0
            fi
            choice="$(gum choose --header "Allow which device?" --height 12 <<<"${blocked}")"
            [[ -n "${choice}" ]] || exit 0
            # -p writes it into the rules, so the device is still allowed after a reboot
            sudo usbguard allow-device -p "${choice%%:*}"
            echo "Allowed, now and after a reboot."
            ;;
        "Turn off" | off)
            sudo systemctl disable --now usbguard.service
            echo "Off. Every USB device is trusted again."
            ;;
        *) exit 0 ;;
    esac

# Let browsers install only the extensions on a list, and keep web pages from USB, serial, HID and Bluetooth devices
browser ACTION="" ID="":
    #!/usr/bin/bash
    set -euo pipefail
    action="{{ ACTION }}"
    policy=/usr/libexec/amethystora-browser-policy
    if [[ "$("${policy}" status)" == on ]]; then
        echo "Browser protection is on: browsers install only the extensions on the list."
    else
        echo "Browser protection is off: a browser installs any extension you let it."
    fi
    allowed="$("${policy}" allowed)"
    if [[ -n "${allowed}" ]]; then
        echo "Allowed on this machine, as well as the password managers:"
        sed 's/^/  /' <<<"${allowed}"
    fi
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Browser protection" \
            "Turn on" "Allow an extension" "Turn off" "Cancel")"
    fi
    case "${action}" in
        "Turn on" | on)
            echo
            echo "An extension sees every page you open, which is how most password stealers arrive."
            echo "With this on, browsers install only the Bitwarden, 1Password, Proton Pass and KeePassXC"
            echo "password managers and the extensions you allow here, and web pages are kept from USB,"
            echo "serial, HID and Bluetooth devices."
            echo
            echo "It covers Firefox, Brave, Chrome, Chromium and Edge, for every account on this machine."
            echo "Extensions that are not on the list go: Firefox removes them, with their settings, the"
            echo "next time it starts, and the others turn theirs off. Allow the ones you use first."
            gum confirm "Turn browser protection on?" || exit 0
            sudo "${policy}" on
            echo "On. Each browser takes it up the next time it starts."
            ;;
        "Allow an extension" | allow)
            id="{{ ID }}"
            if [[ -z "${id}" ]]; then
                echo "Firefox lists each extension's ID in about:support, under Add-ons. The others show"
                echo "it on their extensions page with developer mode on."
                id="$(gum input --prompt "Extension ID> " --placeholder "uBlock0@raymondhill.net")"
            fi
            [[ -n "${id}" ]] || exit 0
            sudo "${policy}" allow "${id}"
            echo "Allowed. To take one back, remove its line from /etc/amethystora/browser-extensions"
            echo "and run: ame security browser on"
            ;;
        "Turn off" | off)
            sudo "${policy}" off
            echo "Off. Browsers install any extension again; the ones Firefox removed do not come back."
            ;;
        *) exit 0 ;;
    esac

# Unlock the encrypted disk with this machine's TPM instead of typing the passphrase at every boot
disk-unlock ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    action="{{ ACTION }}"
    # The encrypted partition this system boots from
    DEVICE="$(lsblk -rno NAME,FSTYPE | awk '$2 == "crypto_LUKS" { print "/dev/"$1; exit }')"
    if [[ -z "${DEVICE}" ]]; then
        echo "This machine has no encrypted partition, so there is nothing to unlock."
        echo "Disk encryption is chosen while installing and cannot be turned on afterwards."
        exit 1
    fi
    if [[ ! -e /dev/tpmrm0 ]]; then
        echo "This machine has no usable TPM (there is no /dev/tpmrm0), so the key has nowhere to go."
        exit 1
    fi
    echo "Encrypted partition: ${DEVICE}"
    if sudo cryptsetup luksDump "${DEVICE}" | grep -q "systemd-tpm2"; then
        echo "The TPM already holds a key for it. Setting it up again replaces that key."
    else
        echo "The TPM holds no key for it: the passphrase is typed at every boot."
    fi
    echo
    echo "What this does: the TPM hands over the key only while Secure Boot is on and the enrolled"
    echo "signing keys are the ones enrolled now (PCR 7 and 14). Turning Secure Boot off, or adding a"
    echo "key to sign something of your own with, stops the disk opening."
    echo "What it does not do: it does not measure the initramfs, which changes with every kernel"
    echo "update and cannot be pinned without enrolling again each time. Someone who can rewrite the"
    echo "initramfs can still reach the unlocked disk. A PIN below is what closes that off."
    echo
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "TPM disk unlock" \
            "Set up with a PIN" "Set up" "Remove the TPM key" "Cancel")"
    fi
    case "${action}" in
        "Set up with a PIN" | on-pin) FLAGS=(--tpm2-with-pin=yes) ;;
        "Set up" | on) FLAGS=() ;;
        "Remove the TPM key" | off)
            sudo systemd-cryptenroll --wipe-slot=tpm2 "${DEVICE}"
            echo "Removed. The passphrase is asked for at every boot again."
            exit 0
            ;;
        *) exit 0 ;;
    esac
    if ! mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        echo "Secure Boot is off on this machine, and binding to it is the whole of what this protects."
        echo "Turn Secure Boot on and run \`ame security secure-boot\` first."
        gum confirm "Enrol anyway?" || exit 0
    fi
    echo "Type the disk passphrase when asked. It keeps working afterwards: this adds a second way in,"
    echo "not a replacement, so a cleared TPM or a replaced board does not lock you out of your disk."
    # Any key the TPM held before goes once this one is in (never the new one): one enrolled with other
    # PCRs, or none, as an older unlocker did, would otherwise open the disk without these checks
    sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7+14 "${FLAGS[@]}" "${DEVICE}"
    # The initramfs is built without this machine's own settings in it, so the instruction to ask the
    # TPM has to come from the kernel command line. Without it the enrolled key is never used.
    sudo rpm-ostree kargs --append-if-missing=rd.luks.options=tpm2-device=auto
    echo
    echo "Done. It takes effect at the next boot."

# Hourly read-only snapshots of the home folders, which ransomware running as you cannot change or delete
ransomware ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    SNAPSHOTS=/var/home/.snapshots
    action="{{ ACTION }}"
    # Newest first, by name, which is the time each was taken
    mapfile -t TAKEN < <(find "${SNAPSHOTS}" -mindepth 1 -maxdepth 1 -regextype egrep \
        -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}' -printf '%f\n' 2>/dev/null | sort -r)
    if systemctl is-enabled --quiet amethystora-home-snapshot.timer 2>/dev/null; then
        echo "Ransomware protection is on: ${#TAKEN[@]} snapshot(s), the latest ${TAKEN[0]:-not taken yet}."
    else
        echo "Ransomware protection is off."
    fi
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Ransomware protection (snapshots of the home folders)" \
            "Turn on" "Put files back" "Turn off" "Cancel")"
    fi
    case "${action}" in
        "Turn on" | on)
            if [[ "$(stat -f -c %T /var/home)" != btrfs || "$(stat -c %i /var/home)" != 256 ]]; then
                echo "The home folders are not on a btrfs subvolume of their own, so they cannot be"
                echo "snapshotted. The installer sets them up that way unless the disk was partitioned by hand."
                exit 1
            fi
            echo
            echo "Every hour, a read-only snapshot of every home folder on this machine. Ransomware running"
            echo "as you can encrypt everything you can write, and a snapshot is not something you can write:"
            echo "changing or deleting one takes root. Kept: every snapshot from the last day, and one a"
            echo "day for two weeks."
            echo
            echo "The cost is disk space. A snapshot holds on to what was deleted or changed since, so a file"
            echo "you delete to make room frees its space only once the last snapshot that has it is gone,"
            echo "up to two weeks later. Snapshots are never deleted to make room, because ransomware that"
            echo "rewrites every file would then delete the ones from before it."
            echo
            echo "What this does not survive is ransomware that gets root. An append-only backup somewhere"
            echo "else does: ame backup"
            gum confirm "Turn ransomware protection on?" || exit 0
            sudo systemctl enable --now amethystora-home-snapshot.timer
            sudo systemctl start amethystora-home-snapshot.service
            # Real-time scanning lists the folders it leaves out as it starts, and the snapshots are one
            if systemctl is-active --quiet amethystora-clamav-onaccess.service; then
                sudo systemctl restart amethystora-clamav-onaccess.service
            fi
            echo
            echo "On. Put files back with: ame security ransomware restore"
            ;;
        "Put files back" | restore)
            if [[ ${#TAKEN[@]} -eq 0 ]]; then
                echo "There are no snapshots to put files back from."
                exit 1
            fi
            home="$(realpath "${HOME}")"
            if [[ "${home}" != /var/home/* ]]; then
                echo "Your home folder, ${home}, is not one the snapshots cover."
                exit 1
            fi
            snapshot="$(gum choose --header "From which snapshot? (date_time)" --height 16 "${TAKEN[@]}")"
            [[ -n "${snapshot}" ]] || exit 0
            from="${SNAPSHOTS}/${snapshot}/${home#/var/home/}"
            how="$(gum choose --header "Your home folder as it was at ${snapshot}" \
                "Open it in Files" "Put a folder back" "Cancel")"
            case "${how}" in
                "Open it in Files")
                    echo "Read-only: copy what you want back into your home folder."
                    xdg-open "${from}"
                    ;;
                "Put a folder back")
                    folder="$(gum input --header "Which folder, inside your home? (empty for all of it)" \
                        --placeholder "Documents")"
                    folder="${folder#/}"
                    folder="${folder%/}"
                    if [[ ! -d "${from}/${folder}" ]]; then
                        echo "There is no ${folder} in that snapshot."
                        exit 1
                    fi
                    echo "Files in ${home}/${folder} with the same name as one in the snapshot are replaced by the"
                    echo "snapshot's. Files the snapshot does not have, such as what ransomware renamed, stay."
                    gum confirm "Put ${folder:-your home folder} back as it was at ${snapshot}?" || exit 0
                    mkdir -p "${home}/${folder}"
                    # A reflink shares the snapshot's blocks, so this takes no time and no space
                    cp -a --reflink=auto "${from}/${folder}/." "${home}/${folder}/"
                    echo "Put back. Delete what ransomware left next to your files, then check they open."
                    ;;
                *) exit 0 ;;
            esac
            ;;
        "Turn off" | off)
            sudo systemctl disable --now amethystora-home-snapshot.timer
            echo "Off. No more snapshots are taken."
            if [[ ${#TAKEN[@]} -gt 0 ]] && gum confirm "Delete the ${#TAKEN[@]} snapshot(s) already taken, and free their space?"; then
                for snapshot in "${TAKEN[@]}"; do
                    sudo btrfs subvolume delete "${SNAPSHOTS}/${snapshot}"
                done
            fi
            ;;
        *) exit 0 ;;
    esac

# Show what the virus scans found, run one now, or put back a file from quarantine
scan ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    FINDINGS=/var/log/amethystora-clamav-findings.log
    QUARANTINE=/usr/libexec/amethystora-quarantine
    action="{{ ACTION }}"
    if sudo test -s "${FINDINGS}"; then
        echo "The last scan found something:"
        sudo cat "${FINDINGS}" | sed 's/^/  /'
    else
        echo "The last scan found nothing."
    fi
    echo "On detection: $(/usr/libexec/amethystora-security-config ON_DETECTION) (ame security settings on-detection)"
    echo "Last run:    $(systemctl show -p InactiveEnterTimestamp --value amethystora-clamav-scan.service)"
    AGE="$(/usr/libexec/amethystora-clamav-signature-age)" && SIG=0 || SIG=$?
    case "${SIG}" in
        0) echo "Signatures:  updated ${AGE} days ago" ;;
        2) echo "Signatures:  ${AGE} days old. Too old for a clean scan to mean much; check the network." ;;
        *) echo "Signatures:  none yet. clamav-freshclam.service has not finished its first download." ;;
    esac
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Virus scan (ClamAV)" "Scan now" "Show the quarantine" \
            "Put a file back" "Show the full log" "Cancel")"
    fi
    case "${action}" in
        "Scan now" | now)
            echo "Scanning the home and temporary directories. This takes a while."
            sudo systemctl start --wait amethystora-clamav-scan.service || true
            sudo journalctl -u amethystora-clamav-scan.service -n 40 --no-pager
            ;;
        "Show the quarantine" | quarantine)
            list="$(sudo "${QUARANTINE}" list)"
            if [[ -z "${list}" ]]; then
                echo "The quarantine is empty."
            else
                echo "In quarantine (id, when, what it matched, where it was):"
                sed 's/^/  /' <<<"${list}"
                echo "Put one back with: ame security scan restore"
            fi
            ;;
        "Put a file back" | restore)
            list="$(sudo "${QUARANTINE}" list)"
            if [[ -z "${list}" ]]; then
                echo "The quarantine is empty."
                exit 0
            fi
            choice="$(gum choose --header "Put which file back?" <<<"${list}")"
            id="${choice%%$'\t'*}"
            echo "A file is only in quarantine because it matched known malware. Put it back only if you"
            echo "are sure that match is wrong."
            gum confirm "Put ${choice##*$'\t'} back?" || exit 0
            if gum confirm "Tell the scanner to leave this exact file alone from now on?"; then
                sudo "${QUARANTINE}" restore "${id}" trust
            else
                sudo "${QUARANTINE}" restore "${id}"
                echo "The next scan will find it again unless you let the scanner leave it alone."
            fi
            ;;
        "Show the full log" | log)
            sudo journalctl -u amethystora-clamav-scan.service -u amethystora-clamav-onaccess.service --no-pager
            ;;
        *) exit 0 ;;
    esac
