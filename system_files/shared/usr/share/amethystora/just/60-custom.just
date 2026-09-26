# vim: set ft=make :

# Pick the desktop theme: colours, terminal palette, prompt and wallpaper (Super+Ctrl+Shift+Space)
theme THEME="":
    #!/usr/bin/bash
    set -euo pipefail
    if [[ -n "{{ THEME }}" ]]; then
        amethystora-theme set "{{ THEME }}"
        exit 0
    fi
    current="$(amethystora-theme current 2>/dev/null || true)"
    choice="$(amethystora-theme list | sed 's/^[*] /  /' | awk '{ print $1 }' |
        gum choose --header "Theme (current: ${current:-none})" --height 14 --selected "${current}")"
    amethystora-theme set "${choice}"

# Cycle the wallpaper of the current theme (Super+Ctrl+Space)
background:
    @amethystora-theme bg next

# Show the tiling, workspace and launcher keybindings (Super+Alt+Space, then Keybindings)
keybindings:
    @glow --pager /usr/share/amethystora/keybindings.md

# Put the Amethystora artwork on the GRUB boot menu, or take it off again
setup-grub-theme ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    action="{{ ACTION }}"
    amethystora-grub-theme status
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Boot menu" "Turn on" "Turn off" "Cancel")"
    fi
    case "${action}" in
        "Turn on" | install | on) sudo amethystora-grub-theme install ;;
        "Turn off" | remove | off) sudo amethystora-grub-theme remove ;;
        *) exit 0 ;;
    esac

# Toggle the logo and system summary shown in new terminals
toggle-user-motd:
    #!/usr/bin/bash
    FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/no-greeting"
    if [ -e "${FLAG}" ]; then
        rm -f "${FLAG}"
        echo "Terminal greeting enabled"
    else
        mkdir -p "$(dirname "${FLAG}")"
        touch "${FLAG}"
        echo "Terminal greeting disabled"
    fi

# Toggle the AI agent: its menu entry, Super+Ctrl+Shift+A, and the skill that tells it about this system
toggle-agentic:
    #!/usr/bin/bash
    if amethystora-agent status >/dev/null; then
        amethystora-agent off
    else
        amethystora-agent on
    fi

# Log in, unlock the screen and approve sudo with a FIDO2 security key (YubiKey, Thetis, and their fingerprint models)
setup-security-key ACTION="":
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
            echo "The key needs a PIN and an enrolled fingerprint. Enroll one in Brave at brave://settings/securityKeys,"
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
enroll-secure-boot-key:
    #!/usr/bin/bash
    set -euo pipefail
    ENROLLMENT_PASSWORD="amethystora"
    # One check, shared with `ujust security-status` (/usr/libexec/amethystora-mok-status). A missing
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

# Everything this machine's security settings are actually doing, in one screen, and what to do about
# anything that is off. Nothing here changes anything, and it asks for no password.
security-status:
    #!/usr/bin/bash
    set -uo pipefail

    ok()   { printf '   \033[1;32mok\033[0m     %s\n' "$1"; }
    note() { printf '   \033[1;33mcheck\033[0m  %s\n' "$1"; shift; for l in "$@"; do printf '          %s\n' "$l"; done; }
    bad()  { printf '   \033[1;31moff\033[0m    %s\n' "$1"; shift; for l in "$@"; do printf '          %s\n' "$l"; done; }
    info() { echo "   ---    $1"; }

    # rpm-ostree, not bootc: `bootc status` needs root, and without it this reported every machine as
    # running "unknown" with unchecked updates. The image reference is prefixed ostree-image-signed:
    # exactly when bootc would report the containerPolicy signature.
    STATUS="$(rpm-ostree status --json 2>/dev/null || true)"
    ref() { jq -r "[.deployments[] | select(.$1)][0][\"container-image-reference\"] // \"\"" <<<"${STATUS:-null}" 2>/dev/null; }
    sig() { [[ "$1" == ostree-image-signed:* ]] && echo containerPolicy || echo none; }
    BOOTED_REF="$(ref booted)"
    IMAGE="$(sed -E 's|^[^:]+:(docker://)?||' <<<"${BOOTED_REF}")"
    IMAGE="${IMAGE:-unknown}"
    SIGNED="$(sig "${BOOTED_REF}")"
    STAGED="$(sig "$(ref staged)")"
    # Packages layered on with rpm-ostree. They decide which command follows a stream below: bootc
    # builds the next deployment from the image alone and would drop them, rpm-ostree carries them over.
    LAYERED="$(jq -r '[.deployments[] | select(.booted)][0] | ((.packages // []) + (."requested-local-packages" // [])) | length' <<<"${STATUS:-null}" 2>/dev/null)"
    LAYERED="${LAYERED:-0}"

    echo
    echo "  This machine is running ${IMAGE}"
    echo
    echo "  Updates and boot"
    if [[ "${SIGNED}" == "containerPolicy" ]]; then
        ok "Updates are refused unless they carry this image's signature"
    elif [[ "${STAGED}" == "containerPolicy" ]]; then
        note "Signature checking is staged, and turns on at the next restart"
    else
        bad "Updates are not signature-checked" \
            "Anything that can answer for the registry could replace this machine's whole system." \
            "Fix it with: sudo systemctl start amethystora-signed-updates.service, then restart"
    fi
    # A dated tag names one build, not a stream: every update re-pulls that same build, forever
    TAG="${IMAGE##*:}"
    if [[ "${TAG}" =~ ^([a-z]+)-[0-9]+\.[0-9]{8} ]]; then
        STREAM="${BASH_REMATCH[1]}"
        if [[ "${LAYERED}" != "0" ]]; then
            FOLLOW="sudo rpm-ostree rebase ostree-image-signed:docker://${IMAGE%:*}:${STREAM}"
        else
            FOLLOW="sudo bootc switch --enforce-container-sigpolicy ${IMAGE%:*}:${STREAM}"
        fi
        note "This machine follows a single build (${TAG}) and will not receive updates" \
             "Follow the ${STREAM} stream again with:" \
             "${FOLLOW}"
    fi
    if [[ "${LAYERED}" != "0" ]]; then
        info "${LAYERED} package(s) are layered on this image with rpm-ostree"
        info "Updates keep them, but each one slows every update; the image is the better place"
    fi

    # What the signature buys is a trusted image at the moment it is pulled. Whether /usr is still
    # checked afterwards is composefs's job, and that comes from the base image rather than from
    # anything set here, so this reports what is actually mounted rather than what was intended.
    if grep -q composefs /proc/mounts 2>/dev/null; then
        ok "The running system is on composefs: /usr is verified as it is read, not only when pulled"
    else
        info "/usr is read-only and replaced whole by each update, but is not re-verified as it is read"
    fi

    SB="$(mokutil --sb-state 2>/dev/null || true)"
    if grep -qi "enabled" <<<"${SB}"; then
        ok "Secure Boot is on: this machine boots only a kernel it has checked"
    elif grep -qi "disabled" <<<"${SB}"; then
        note "Secure Boot is off" \
             "The kernel protections below rest on it. Without it, anything that reaches root can" \
             "boot a different kernel and step around them." \
             "Turn Secure Boot on in this machine's firmware, then run: ujust enroll-secure-boot-key"
    else
        note "Secure Boot state unknown (no EFI on this machine, or its firmware will not say)"
    fi

    # The same check `ujust enroll-secure-boot-key` uses, so the two can no longer disagree
    MOK="$(/usr/libexec/amethystora-mok-status)"
    if ! grep -qv "^enrolled " <<<"${MOK}"; then
        ok "This image's signing keys are enrolled"
    elif grep -qi "enabled" <<<"${SB}"; then
        while read -r state cert rest; do
            case "${state}" in
                not-enrolled)
                    note "Not enrolled: ${cert##*/}" \
                         "What it signs, such as evdi for DisplayLink docks, will not load." \
                         "Enroll it with: ujust enroll-secure-boot-key" ;;
                pending)
                    note "Enrollment of ${cert##*/} is waiting for the next restart" \
                         "Finish it in the blue MOK manager screen that appears during boot." ;;
                missing)
                    note "${cert} is not on this machine" \
                         "Whether its key is enrolled cannot be checked without it." ;;
                unknown)
                    note "Could not tell whether ${cert##*/} is enrolled" "mokutil said: ${rest}" ;;
            esac
        done <<<"${MOK}"
    fi

    LOCKDOWN=""
    [[ -r /sys/kernel/security/lockdown ]] &&
        LOCKDOWN="$(sed -n 's/.*\[\([a-z]*\)\].*/\1/p' /sys/kernel/security/lockdown 2>/dev/null)"
    [[ -n "${LOCKDOWN}" ]] || { grep -qw "lockdown=integrity" /proc/cmdline && LOCKDOWN=integrity; }
    case "${LOCKDOWN}" in
        integrity | confidentiality)
            ok "Kernel lockdown is on (${LOCKDOWN}): root cannot rewrite the running kernel" ;;
        *)
            if [[ "${IMAGE}" == *nvidia* ]]; then
                note "Kernel lockdown is off, as it is on every NVIDIA image" \
                     "The NVIDIA driver is a module signed with this machine's own key, and lockdown" \
                     "would leave a machine without Secure Boot with no graphics driver at all."
            else
                note "Kernel lockdown is off" \
                     "Turn it back on with: sudo rpm-ostree kargs --append=lockdown=integrity"
            fi ;;
    esac

    echo
    echo "  Watching"
    [[ "$(systemctl is-active auditd.service)" == "active" ]] &&
        ok "The audit log is recording" ||
        bad "The audit log is not recording" "Start it with: sudo systemctl start auditd.service"
    [[ -f /etc/audit/rules.d/99-amethystora-finalize.rules ]] &&
        ok "Audit rules are immutable until the next reboot"
    [[ "$(systemctl is-active fail2ban.service)" == "active" ]] &&
        ok "Repeated failed logins get the address blocked (ujust blocked-addresses)" ||
        note "fail2ban is not running" "Start it with: sudo systemctl start fail2ban.service"
    ZONE="$(firewall-cmd --get-default-zone 2>/dev/null || echo unknown)"
    [[ "${ZONE}" == "amethystora" ]] &&
        ok "Firewall is on the amethystora zone: nothing incoming that a desktop does not need" ||
        note "Firewall default zone is ${ZONE}, not amethystora" \
             "Put it back with: sudo firewall-cmd --set-default-zone=amethystora"

    echo
    echo "  Scans"
    LAST_SCAN="$(systemctl show -p InactiveEnterTimestamp --value amethystora-clamav-scan.service)"
    # /var/log is traversable, so the size of the root-owned 0600 findings file is visible here
    # even though its contents are not, and this recipe never asks for a password
    if [[ -s /var/log/amethystora-clamav-findings.log ]]; then
        bad "The last virus scan found something" "See it with: ujust virus-scan"
    else
        ok "Weekly virus scan, Sundays. Last run: ${LAST_SCAN:-not yet}"
    fi
    AGE="$(/usr/libexec/amethystora-clamav-signature-age)" && SIG=0 || SIG=$?
    case "${SIG}" in
        0) ok "Virus signatures updated ${AGE} days ago" ;;
        2) note "Virus signatures are ${AGE} days old" \
                "A clean scan proves little with signatures this old. Check this machine's network." ;;
        *) note "No virus signatures yet" \
                "clamav-freshclam.service has not finished its first download." ;;
    esac
    LAST_AUDIT="$(systemctl show -p InactiveEnterTimestamp --value amethystora-lynis-audit.service)"
    ok "Monthly settings audit. Last run: ${LAST_AUDIT:-not yet}, or run it now with: ujust security-audit"

    echo
    echo "  Off unless you turned it on"
    systemctl is-enabled --quiet usbguard.service 2>/dev/null &&
        echo "   USB protection is on (ujust setup-usb-protection)" ||
        echo "   USB protection: ujust setup-usb-protection"
    systemctl is-enabled --quiet input-remapper.service 2>/dev/null &&
        echo "   Key remapping is on, and it reads every input device (ujust setup-input-remapper)" ||
        echo "   Key remapping, which reads every input device: ujust setup-input-remapper"
    echo "   Security key for login and sudo: ujust setup-security-key"
    echo "   Unlock the disk with the TPM: ujust setup-disk-unlock"
    echo "   Backups: ujust setup-backup"
    echo

# Audit this machine's security settings with Lynis and say what to do about each finding
security-audit:
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

# Addresses fail2ban has blocked for too many failed logins, and how to let one back in
blocked-addresses ADDRESS="":
    #!/usr/bin/bash
    set -euo pipefail
    if [[ -n "{{ ADDRESS }}" ]]; then
        sudo fail2ban-client set sshd unbanip "{{ ADDRESS }}"
        exit 0
    fi
    sudo fail2ban-client status sshd
    echo
    echo "Let one back in with: ujust blocked-addresses <address>"
    echo "Blocking is set up in /etc/fail2ban/jail.d/10-amethystora.conf."

# Turn key remapping on or off. It is off by default: the service reads every key pressed on the machine
setup-input-remapper ACTION="":
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
setup-usb-protection ACTION="":
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

# Unlock the encrypted disk with this machine's TPM instead of typing the passphrase at every boot
setup-disk-unlock ACTION="":
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
        echo "The TPM already holds a key for it."
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
        echo "Turn Secure Boot on and run \`ujust enroll-secure-boot-key\` first."
        gum confirm "Enrol anyway?" || exit 0
    fi
    echo "Type the disk passphrase when asked. It keeps working afterwards: this adds a second way in,"
    echo "not a replacement, so a cleared TPM or a replaced board does not lock you out of your disk."
    sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7+14 "${FLAGS[@]}" "${DEVICE}"
    # The initramfs is built without this machine's own settings in it, so the instruction to ask the
    # TPM has to come from the kernel command line. Without it the enrolled key is never used.
    sudo rpm-ostree kargs --append-if-missing=rd.luks.options=tpm2-device=auto
    echo
    echo "Done. It takes effect at the next boot."

# Back up this account to a repository that ransomware on this machine cannot delete from
setup-backup ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora"
    ENV_FILE="${CONFIG_DIR}/backup.env"
    PASSWORD_FILE="${CONFIG_DIR}/backup-password"
    action="{{ ACTION }}"
    if [[ -r "${ENV_FILE}" ]]; then
        echo "Backing up to: $(sed -n 's/^RESTIC_REPOSITORY=//p' "${ENV_FILE}")"
        if systemctl --user is-enabled --quiet amethystora-backup.timer 2>/dev/null; then
            systemctl --user list-timers --no-pager amethystora-backup.timer
        else
            echo "The daily run is off."
        fi
    else
        echo "No backup is set up for this account."
    fi
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Backups (restic)" \
            "Set up" "Back up now" "Show snapshots" "Turn off the daily run" "Cancel")"
    fi
    case "${action}" in
        "Set up" | setup)
            echo
            echo "Ransomware encrypts everything it can reach, and a backup this machine can delete from"
            echo "is something it can reach. An append-only repository is one this machine may add"
            echo "snapshots to and read its own back from, and nothing else, so what was backed up before"
            echo "the machine was taken over is still there afterwards. Set that up at the other end:"
            echo
            echo "  rest-server   run it with --append-only, then use  rest:https://user:pass@host:8000/"
            echo "  Borg or SSH   set  append_only = yes  in the repository's config on the server"
            echo "  Object store  turn on object lock or immutability, then use  rclone:remote:path"
            echo "  A USB drive   unplug it between backups; unplugged is the oldest append-only there is"
            echo
            current="$(sed -n 's/^RESTIC_REPOSITORY=//p' "${ENV_FILE}" 2>/dev/null || true)"
            repository="$(gum input --header "Repository" \
                --placeholder "rest:https://user:pass@host:8000/" --value "${current}")"
            [[ -n "${repository}" ]] || exit 0
            password="$(gum input --password \
                --header "Repository password (keep a copy elsewhere: without it the backup cannot be read)")"
            [[ -n "${password}" ]] || exit 0
            paths="$(gum input --header "What to back up, separated by spaces" --value "${HOME}")"
            [[ -n "${paths}" ]] || exit 0
            mkdir -p "${CONFIG_DIR}"
            (umask 077 && printf '%s' "${password}" >"${PASSWORD_FILE}")
            (umask 077 && printf '%s\n' \
                "# Written by ujust setup-backup, read by /usr/libexec/amethystora-backup." \
                "RESTIC_REPOSITORY=${repository}" \
                "RESTIC_PASSWORD_FILE=${PASSWORD_FILE}" \
                "AMETHYSTORA_BACKUP_PATHS=${paths}" >"${ENV_FILE}")
            set -a && source "${ENV_FILE}" && set +a
            # An append-only repository refuses `restic init`, so finding one already there is normal
            if restic cat config >/dev/null 2>&1; then
                echo "Using the repository that is already there."
            else
                echo "Nothing there yet, creating the repository."
                restic init
            fi
            systemctl --user enable --now amethystora-backup.timer
            echo
            echo "Set up, and running once a day."
            echo
            echo "Nothing on this machine ever deletes from the repository, which is the point, so old"
            echo "snapshots build up. Thin them out from somewhere else, with credentials this machine"
            echo "does not hold:"
            echo "  restic -r <repository> forget --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune"
            ;;
        "Back up now" | now)
            systemctl --user start --wait amethystora-backup.service || true
            journalctl --user -u amethystora-backup.service -n 30 --no-pager
            ;;
        "Show snapshots" | snapshots)
            if [[ ! -r "${ENV_FILE}" ]]; then
                echo "No backup is set up. Set one up with: ujust setup-backup"
                exit 1
            fi
            set -a && source "${ENV_FILE}" && set +a
            restic snapshots --compact
            ;;
        "Turn off the daily run" | off)
            systemctl --user disable --now amethystora-backup.timer
            echo "Off. The settings and the repository itself are left alone."
            ;;
        *) exit 0 ;;
    esac

# Show what the weekly virus scan found, or run one now
virus-scan ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    FINDINGS=/var/log/amethystora-clamav-findings.log
    action="{{ ACTION }}"
    if sudo test -s "${FINDINGS}"; then
        echo "The last scan found something. Nothing was deleted, quarantined or moved:"
        sudo cat "${FINDINGS}" | sed 's/^/  /'
    else
        echo "The last scan found nothing."
    fi
    echo "Last run:    $(systemctl show -p InactiveEnterTimestamp --value amethystora-clamav-scan.service)"
    AGE="$(/usr/libexec/amethystora-clamav-signature-age)" && SIG=0 || SIG=$?
    case "${SIG}" in
        0) echo "Signatures:  updated ${AGE} days ago" ;;
        2) echo "Signatures:  ${AGE} days old. Too old for a clean scan to mean much; check the network." ;;
        *) echo "Signatures:  none yet. clamav-freshclam.service has not finished its first download." ;;
    esac
    if [[ -z "${action}" ]]; then
        action="$(gum choose --header "Virus scan (ClamAV)" "Scan now" "Show the full log" "Cancel")"
    fi
    case "${action}" in
        "Scan now" | now)
            echo "Scanning the home and temporary directories. This takes a while and deletes nothing."
            sudo systemctl start --wait amethystora-clamav-scan.service || true
            sudo journalctl -u amethystora-clamav-scan.service -n 40 --no-pager
            ;;
        "Show the full log" | log)
            sudo journalctl -u amethystora-clamav-scan.service --no-pager
            ;;
        *) exit 0 ;;
    esac
