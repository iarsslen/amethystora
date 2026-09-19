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
    # amethystora-modules.der signs the modules built with the image (evdi),
    # akmods-amethystora.der the kernel and the prebuilt modules
    certs=()
    for cert in /etc/pki/akmods/certs/amethystora-modules.der /etc/pki/akmods/certs/akmods-amethystora.der; do
        if [[ -f "${cert}" ]] && ! mokutil --test-key "${cert}" | grep -q "is already enrolled"; then
            certs+=("${cert}")
        fi
    done
    if [[ ${#certs[@]} -eq 0 ]]; then
        echo "The Secure Boot keys are already enrolled."
        exit 0
    fi
    sudo mokutil --timeout -1
    printf '%s\n%s\n' "${ENROLLMENT_PASSWORD}" "${ENROLLMENT_PASSWORD}" | sudo mokutil --import "${certs[@]}"
    echo "At next reboot, the blue MOK manager screen appears (QWERTY keyboard layout)."
    echo "Select \"Enroll MOK\", then \"Continue\", \"Yes\", and type \"${ENROLLMENT_PASSWORD}\" as the password."
