#!/usr/bin/bash
set -euo pipefail

# dnf5 install that survives short repository outages. The COPR servers regularly time out or
# answer 504, and dnf then reports the packages as missing: retry with fresh metadata before
# failing the build. Takes the same arguments as `dnf5 install`.
dnf_install_retry() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if dnf5 -y install --refresh "$@"; then
            return 0
        fi
        if [[ $attempt -lt 5 ]]; then
            echo "dnf5 install failed (attempt $attempt/5), retrying in $((attempt * 30))s"
            sleep $((attempt * 30))
        fi
    done
    echo "ERROR: dnf5 install failed after 5 attempts: $*"
    return 1
}

copr_install_isolated() {
    local copr_name="$1"
    shift
    local packages=("$@")

    if [[ ${#packages[@]} -eq 0 ]]; then
        echo "ERROR: No packages specified for copr_install_isolated"
        return 1
    fi

    repo_id="copr:copr.fedorainfracloud.org:${copr_name//\//:}"

    echo "Installing ${packages[*]} from COPR $copr_name (isolated)"

    dnf5 -y copr enable "$copr_name"
    dnf5 -y copr disable "$copr_name"
    dnf_install_retry --enablerepo="$repo_id" "${packages[@]}"

    echo "Installed ${packages[*]} from $copr_name"
}
