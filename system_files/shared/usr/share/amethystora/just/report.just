# vim: set ft=make :

# Gather what a bug report needs, show you all of it, and open a pre-filled issue: nothing is posted by itself
report:
    #!/usr/bin/bash
    set -euo pipefail
    REPO="$(/usr/libexec/amethystora-image-repo)"
    FILE="${HOME}/amethystora-report-$(date +%Y%m%d-%H%M%S).md"
    echo "Gathering what a bug report needs. It stays on this machine until you choose otherwise."
    echo
    # A sealed image has no rpm-ostree: its deployments come from bootc, through amethystora-deployments
    if [[ -e /usr/share/amethystora/sealed ]]; then
        status="$({ /usr/libexec/amethystora-deployments | jq .; } 2>&1 || true)"
    else
        status="$(rpm-ostree status 2>&1 || true)"
    fi
    groups="$(groups 2>&1 || true)"
    hardware="$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null | paste -sd " " || true)"
    failed="$({ systemctl --failed --no-legend --plain; systemctl --user --failed --no-legend --plain; } 2>/dev/null | head -20 || true)"
    # Administrators read the whole machine's log, anyone else their own session's
    errors="$(journalctl -b -p err --no-pager -n 40 -o short-monotonic 2>/dev/null || true)"
    context="$(printf '%s\n' \
        "Image: $(. /usr/lib/os-release && echo "${PRETTY_NAME}")" \
        "Kernel: $(uname -r)" \
        "Hardware: ${hardware:-unknown}" \
        "Failed units:" "${failed:-none}")"
    (umask 077 && {
        printf '## Deployments\n\n```\n%s\n```\n\n' "${status}"
        printf '## groups\n\n```\n%s\n```\n\n' "${groups}"
        printf '## This machine\n\n```\n%s\n```\n\n' "${context}"
        printf '## Errors logged since this boot (the last 40)\n\n```\n%s\n```\n' "${errors:-none}"
    } >"${FILE}")
    cat "${FILE}"
    echo
    echo "That is all of it, kept in ${FILE}. Read it for anything you would rather not post:"
    echo "lines from the log can name your files, networks and devices."
    gum confirm "Open a new issue in the browser, with everything but the errors filled in?" || exit 0
    uri() { jq -rn --arg v "$1" '$v | @uri'; }
    url="https://github.com/${REPO}/issues/new?template=bug-report.yml&groups=$(uri "${groups}")"
    # A link longer than GitHub takes would open nothing: a field that does not fit is left to the file
    for field in "version=$(uri "${status}")" "extra-context=$(uri $'```\n'"${context}"$'\n```')"; do
        if (( ${#url} + ${#field} < 8000 )); then url+="&${field}"; fi
    done
    echo "The browser sends what it fills in to GitHub. Nothing is posted until you submit the issue."
    xdg-open "${url}" >/dev/null 2>&1 || echo "Open this link yourself: ${url}"
    echo "Say what you did and what happened. If the errors help, drag ${FILE} into the issue."
