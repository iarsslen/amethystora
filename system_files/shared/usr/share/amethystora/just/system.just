# vim: set ft=make :

set default-list

# Rebase assistant: another image or stream, signed images only (IMAGE and STREAM preselect them)
rebase IMAGE="" STREAM="":
    @/usr/bin/amethystora-rollback-helper {{ IMAGE }} {{ STREAM }}

# Take an image of your own from REPOSITORY only when KEY, its cosign.pub, checks its signature
[no-cd]
[no-exit-message]
[positional-arguments]
trust-image REPOSITORY KEY:
    @sudo /usr/libexec/amethystora-trust-image "$1" "$2"

# Turn automatic updates on or off (ACTION: on or off; without it, you are asked)
auto-updates ACTION="prompt":
    #!/usr/bin/bash
    CURRENT_STATE="disabled"
    if systemctl is-enabled -q rpm-ostreed-automatic.timer; then
        CURRENT_STATE="enabled"
    elif systemctl is-enabled -q uupd.timer; then
        CURRENT_STATE="enabled"
    fi

    echo "Automatic updates are currently ${CURRENT_STATE}"
    case "{{ ACTION }}" in
        on | enable) SELECTED_OPTION="Enable" ;;
        off | disable) SELECTED_OPTION="Disable" ;;
        *) SELECTED_OPTION="$(gum choose --header="Toggle automatic updates?" "Enable" "Disable" "Cancel")" ;;
    esac
    [[ "${SELECTED_OPTION}" == "Cancel" || "${SELECTED_OPTION}" == "" ]] && exit 0

    if systemctl cat -- uupd.timer &> /dev/null; then
        TIMER="uupd.timer"
    else
        TIMER="rpm-ostreed-automatic.timer"
    fi
    if [ "${SELECTED_OPTION}" == "Enable" ] ; then
        sudo systemctl enable --now "$TIMER"
        echo "Updates have been enabled"
    elif [ "${SELECTED_OPTION}" == "Disable" ] ; then
        sudo systemctl disable --now "$TIMER"
        echo "Updates have been disabled"
    fi

# Switch between Amethystora and the Developer Experience (ACTION: on or off; without it, it flips)
devmode ACTION="":
    #!/usr/bin/env bash
    set -e
    IMAGE_INFO_FILE="${IMAGE_INFO_FILE:-/usr/share/amethystora/image-info.json}"
    IMAGE_NAME="$(jq -rc '."image-name"' "${IMAGE_INFO_FILE}")"
    IMAGE_REF="$(jq -rc '."image-ref"' "${IMAGE_INFO_FILE}" | sed "s/.*ghcr/ghcr/")"
    CURRENT_IMAGE="${IMAGE_REF}:$(jq -rc '."image-tag"' "${IMAGE_INFO_FILE}")"
    IMAGE_BASE_NAME="$(cut -f1 -d\- <<< "${IMAGE_NAME}")"
    set +e

    # amethystora-dx and amethystora-dx-nvidia-open are the developer images
    DX=false
    if grep -q -E -e "-dx(-|$)" <<< "${IMAGE_NAME}" ; then
        DX=true
    fi
    case "{{ ACTION }}" in
        on)
            if [[ "${DX}" == true ]]; then
                echo "Developer mode is already on: this is ${IMAGE_NAME}."
                exit 0
            fi
            ;;
        off)
            if [[ "${DX}" != true ]]; then
                echo "Developer mode is already off: this is ${IMAGE_NAME}."
                exit 0
            fi
            ;;
        "") ;;
        *)
            echo "usage: ame system devmode [on|off]"
            exit 64
            ;;
    esac

    if [[ "${DX}" == true ]] ; then
        gum confirm "Would you like to disable developer mode?" || exit 0
        echo "Rebasing to a non developer image"
        NEW_IMAGE="$(sed "s/\-dx//" <<< $CURRENT_IMAGE)"
        pkexec bootc switch --enforce-container-sigpolicy "${NEW_IMAGE}"
        exit 0
    fi

    gum confirm "Would you like to enable developer mode?" || exit 0
    echo "Rebasing to a developer image"
    NEW_IMAGE="$(sed "s/${IMAGE_BASE_NAME}/${IMAGE_BASE_NAME}-dx/" <<< "${CURRENT_IMAGE}")"
    pkexec bootc switch --enforce-container-sigpolicy "${NEW_IMAGE}"
    echo "The development apps install by themselves once the development image has started"
    if gum confirm "Do you want to install extra monospace fonts?" ; then
        brew bundle install --file=/usr/share/amethystora/homebrew/fonts.Brewfile
    fi
    echo "After the restart, ame system dx-group lets your account use Docker, Incus and virtual machines"
    echo "without sudo, and says what that costs."

# Choose your account's developer groups (Docker, Incus, libvirt, serial devices); three of them amount to root
[positional-arguments]
dx-group *GROUPS:
    #!/usr/bin/bash
    set -euo pipefail
    # One list, which Control and the security report read too: group, "root" or "-", what it allows
    list=/usr/share/amethystora/developer-groups
    user="$(id -un)"
    member() { id -nG "${user}" | tr ' ' '\n' | grep -qx "$1"; }
    names=()
    roots=()
    echo "Developer groups for ${user} (* = in it):"
    while read -r group root text; do
        # Only the groups this image has: Docker and Incus come with the developer image
        getent group "${group}" >/dev/null || continue
        names+=("${group}")
        [[ "${root}" == root ]] && roots+=("${group}")
        if member "${group}"; then mark="*"; else mark=" "; fi
        echo " ${mark} ${group}: ${text}"
    done < <(grep -v '^#' "${list}" | awk NF)
    if [[ ${#names[@]} -eq 0 ]]; then
        echo "   None: they come with developer mode (ame system devmode on)."
        exit 0
    fi
    echo
    if [[ ${#roots[@]} -gt 0 ]]; then
        echo "In ${roots[*]}, any program running as you can become root without the sudo password."
    fi
    echo "Podman, and virtual machines on your own connection (qemu:///session), need no group at all."
    echo
    if [[ $# -gt 0 ]]; then
        wanted=("$@")
        [[ "${wanted[*]}" == none ]] && wanted=()
    else
        selected=""
        for group in "${names[@]}"; do
            if member "${group}"; then selected+="${selected:+,}${group}"; fi
        done
        choice="$(gum choose --no-limit --header "Which groups should ${user} be in?" \
            --selected "${selected}" "${names[@]}")" || exit 0
        mapfile -t wanted <<<"${choice}"
    fi
    joins=()
    leaves=()
    for group in "${wanted[@]}"; do
        [[ -n "${group}" ]] || continue
        if [[ " ${names[*]} " != *" ${group} "* ]]; then
            echo "Not a developer group here: ${group}. The ones there are: ${names[*]}"
            exit 64
        fi
        member "${group}" || joins+=("${group}")
    done
    for group in "${names[@]}"; do
        member "${group}" && [[ " ${wanted[*]} " != *" ${group} "* ]] && leaves+=("${group}")
    done
    if [[ ${#joins[@]} -eq 0 && ${#leaves[@]} -eq 0 ]]; then
        echo "Nothing to change."
        exit 0
    fi
    risky=()
    for group in "${joins[@]}"; do
        [[ " ${roots[*]} " == *" ${group} "* ]] && risky+=("${group}")
    done
    if [[ ${#risky[@]} -gt 0 ]]; then
        gum confirm "Join ${risky[*]}, which let any program you run become root without your password?" || exit 0
    fi
    for group in "${joins[@]}"; do
        # The image's own groups are in /usr/lib/group until something copies them into /etc/group, and a
        # group without its /etc/gshadow line is an error to grpck
        grep -q "^${group}:" /etc/group || grep "^${group}:" /usr/lib/group | sudo tee -a /etc/group >/dev/null
        sudo grep -q "^${group}:" /etc/gshadow || echo "${group}:!::" | sudo tee -a /etc/gshadow >/dev/null
        sudo usermod -aG "${group}" "${user}"
        echo "Joined ${group}."
    done
    for group in "${leaves[@]}"; do
        sudo gpasswd -d "${user}" "${group}" >/dev/null
        echo "Left ${group}."
    done
    echo "Log out and back in for it to apply."

# Factory reset this device (experimental)
powerwash:
    #!/usr/bin/bash
    # bootc's own test of this skips the composefs backend a sealed machine runs on
    if [[ -e /usr/share/amethystora/sealed ]]; then
        echo "Starting over has not been tried on a sealed machine yet. Install it again from the ISO instead."
        exit 1
    fi
    FIRST_CONFIRMATION=$(gum choose --header='Warning: This is an experimental feature that will reset this device to its factory state.' "No" "Yes - wipe this machine")
    if [[ "$FIRST_CONFIRMATION" != "Yes - wipe this machine" ]]; then
        echo "Powerwash cancelled."
        exit 0
    fi
    SECOND_CONFIRMATION=$(gum choose --header='Are you sure?' "No" "Yes - wipe this machine")
    if [[ "$SECOND_CONFIRMATION" != "Yes - wipe this machine" ]]; then
        echo "Powerwash cancelled."
        exit 0
    fi
    sudo bootc install reset --experimental

# Boot into this device's BIOS/UEFI screen
bios:
    #!/usr/bin/bash
    if [ ! -d /sys/firmware/efi ]; then
      echo "Rebooting to legacy BIOS from OS is not supported."
      exit 1
    fi

    if gum confirm "Reboot into BIOS?" ; then
      systemctl reboot --firmware-setup
    fi

# Show BIOS info
bios-info:
    #!/usr/bin/bash
    sudo bash <<'EOF'
    echo "Manufacturer: $(dmidecode -s baseboard-manufacturer)"
    echo "Product Name: $(dmidecode -s baseboard-product-name)"
    echo "Version: $(dmidecode -s bios-version)"
    echo "Release Date: $(dmidecode -s bios-release-date)"
    EOF

# Free disk space: unused container images and volumes, Flatpak runtimes, old deployments, Homebrew's cache
clean:
    #!/usr/bin/bash
    if gum confirm "Prune all Podman images and volumes?"; then
        podman image prune -af
        podman volume prune -f
    fi

    if command -v docker >/dev/null 2>&1; then
      if gum confirm "Prune all Docker images and volumes?"; then
        docker image prune -af
        docker volume prune -f
      fi
    fi

    flatpak uninstall --unused
    # A sealed image has no rpm-ostree, nor its caches to clean
    if command -v rpm-ostree >/dev/null; then
        rpm-ostree cleanup -bm
    fi
    if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
        brew autoremove
        brew cleanup
    fi

# Pools of disks (RAID): how they are, then make one from spare disks, or replace or add a disk
[no-cd]
[no-exit-message]
[positional-arguments]
raid *ARGS:
    @/usr/libexec/amethystora-raid "$@"

# Show all messages from this boot
logs-this-boot:
    sudo journalctl --no-hostname -b 0

# Show all messages from last boot
logs-last-boot:
    sudo journalctl --no-hostname -b -1

# Check for local overrides
local-overrides:
    #!/usr/bin/bash
    RESET="\x1b[0m"
    if [ "${NO_COLOR}" == 1 ]; then
        BLUE_COLOR=""
        GREEN_COLOR=""
        YELLOW_COLOR=""
    else
        BLUE_COLOR="${BLUE_COLOR:-\x1b[38;5;117m}"
        GREEN_COLOR="${GREEN_COLOR:-\x1b[38;5;85m}"
        YELLOW_COLOR="${YELLOW_COLOR:-\x1b[93m}"
    fi

    diff -qr \
      --suppress-common-lines \
      --color="always" \
      --exclude "passwd*" \
      --exclude "group*" \
      --exclude="subgid*" \
      --exclude="subuid*" \
      --exclude="machine-id" \
      --exclude="adjtime" \
      --exclude="fstab" \
      --exclude="system-connections" \
      --exclude="shadow*" \
      --exclude="gshadow*" \
      --exclude="ssh_host*" \
      --exclude="cmdline" \
      --exclude="crypttab" \
      --exclude="hostname" \
      --exclude="localtime" \
      --exclude="locale*" \
      --exclude="*lock" \
      --exclude=".updated" \
      --exclude="*LOCK" \
      --exclude="vconsole*" \
      --exclude="00-keyboard.conf" \
      --exclude="grub" \
      --exclude="system.control*" \
      --exclude="cdi" \
      --exclude="default.target" \
      /usr/etc /etc 2>/dev/null | sed \
          -e '/Binary\ files\ /d ; /Common subdirectories/d' \
          -e "/Files/ s/^/${BLUE_COLOR}&/g" \
          -e "/Files/ s/\$/&${RESET}/g" \
          -e "/Only in/ s/^/${GREEN_COLOR}&/g" \
          -e "/Only in/ s/\$/&${RESET}/g" \
          -e "s/\:.*/${RESET}${YELLOW_COLOR}&${RESET}/g"

# Gathering what a bug report needs is `ame report`, which keeps it on this machine until you choose otherwise
[private]
device-info:
    @ame report

# Measure Idle Power Draw
power-draw:
    #!/usr/bin/bash
    if ! command -v powerstat ; then
        echo "Powerstat is not available"
        exit 1
    fi
    sudo powerstat -a -r

# Run a one minute system benchmark
benchmark:
    #!/usr/bin/env bash
    if ! command -v "stress-ng" ; then
        if gum confirm "Stress does not seem to be on your path, do you wish to install it?" ; then
            set -eu
            brew install stress-ng
            brew link stress-ng
            set +eu
        else
            exit 0
        fi
    fi

    echo "Running a 1 minute benchmark ..."
    trap popd EXIT
    pushd "$(mktemp -d)"
    stress-ng --matrix 0 -t 1m --times

# Pick the CPU scheduler: the kernel's own, or a sched-ext one for games (lavd), a busy desktop (bpfland) or audio work (flash)
scheduler NAME="":
    #!/usr/bin/bash
    set -euo pipefail
    # scx_loader starts default_sched at boot while it is enabled (17-cleanup.sh ships it disabled)
    config=/etc/scx_loader/config.toml
    # What the kernel itself says runs: "enabled" with the scheduler's name while a sched-ext one does
    running() {
        [[ "$(cat /sys/kernel/sched_ext/state 2>/dev/null)" == enabled ]] && cat /sys/kernel/sched_ext/root/ops 2>/dev/null
    }
    current="$(running || true)"
    [[ -n "${current}" ]] || current="the kernel's own (EEVDF)"
    echo "Scheduling the CPU now: ${current}"
    name="{{ NAME }}"
    if [[ -z "${name}" ]]; then
        echo
        echo "kernel   The kernel's own, which suits nearly everything (the default)"
        echo "lavd     Keeps games smooth while other work runs, made for gaming handhelds and laptops"
        echo "bpfland  Keeps the desktop responsive while something heavy builds or renders"
        echo "flash    Steady timing, for audio and music work"
        name="$(gum choose --header "CPU scheduler" kernel lavd bpfland flash)"
    fi
    case "${name}" in
        kernel | off)
            sudo systemctl disable --now scx_loader.service
            sudo rm -f "${config}"
            echo "The kernel's own scheduler, now and after every restart."
            ;;
        lavd | bpfland | flash)
            echo "A sched-ext scheduler is a program the kernel hands its scheduling to. If it stops, the"
            echo "kernel takes over again by itself, so the worst it can do is make things slower."
            sudo mkdir -p "${config%/*}"
            printf 'default_sched = "scx_%s"\ndefault_mode = "Auto"\n' "${name}" | sudo tee "${config}" >/dev/null
            sudo systemctl enable scx_loader.service
            sudo systemctl restart scx_loader.service
            # The loader answers before the scheduler is in: give the kernel a moment to say so
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ "$(running || true)" == "${name}"* ]] && break
                sleep 1
            done
            if [[ "$(running || true)" != "${name}"* ]]; then
                echo
                echo "The kernel did not take scx_${name}. What the loader said:"
                journalctl -u scx_loader.service -n 15 --no-pager -q || true
                echo
                echo "A kernel built before Fedora's dwarves 1.32 cannot load the current schedulers, which a"
                echo "later image fixes. Back to the kernel's own scheduler."
                sudo systemctl disable --now scx_loader.service
                sudo rm -f "${config}"
                exit 1
            fi
            echo "scx_${name}, now and after every restart. ame system scheduler kernel puts the kernel's own back."
            ;;
        *) exit 0 ;;
    esac
