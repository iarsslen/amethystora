# vim: set ft=make :

# Back up this account to a repository that ransomware on this machine cannot delete from
[positional-arguments]
backup ACTION="":
    #!/usr/bin/bash
    set -euo pipefail
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/amethystora"
    ENV_FILE="${CONFIG_DIR}/backup.env"
    PASSWORD_FILE="${CONFIG_DIR}/backup-password"
    action="${1:-}"
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
        daily="Turn off the daily run"
        systemctl --user is-enabled --quiet amethystora-backup.timer 2>/dev/null || daily="Turn on the daily run"
        action="$(gum choose --header "Backups (restic)" \
            "Set up" "Back up now" "Show snapshots" "${daily}" "Cancel")"
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
                "# Written by ame backup, read by /usr/libexec/amethystora-backup." \
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
            echo "Set up, and running once a day. Files come back from it in Backups, in the app grid."
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
            # Every point there is to go back to, the backup's and the hourly snapshots', as Backups shows them
            /usr/libexec/amethystora-restore points
            ;;
        "Turn on the daily run" | on)
            if [[ ! -r "${ENV_FILE}" ]]; then
                echo "No backup is set up. Set one up with: ame backup setup"
                exit 1
            fi
            systemctl --user enable --now amethystora-backup.timer
            echo "On, once a day."
            ;;
        "Turn off the daily run" | off)
            systemctl --user disable --now amethystora-backup.timer
            echo "Off. The settings and the repository itself are left alone."
            ;;
        *) exit 0 ;;
    esac

# Make this account's setup again from a backup, on a new machine: the image, apps, containers, theme
[positional-arguments]
restore-setup SNAPSHOT="":
    @/usr/libexec/amethystora-restore-setup ${1:+"$1"}
