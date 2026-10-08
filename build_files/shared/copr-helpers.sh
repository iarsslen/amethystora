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

# RPM Fusion's release packages, which add its repositories, come from a redirector that hands out
# volunteer mirrors, and dnf checks no signature on a package given as a file or URL unless told to.
# RPM Fusion's keys are taken from Fedora's own signed distribution-gpg-keys package instead, and the
# release packages are installed only with a valid signature from them. Takes free, nonfree or both.
rpmfusion_release_install() {
    local fedora repo packages=()
    fedora="$(rpm -E %fedora)"
    rpm -q distribution-gpg-keys >/dev/null ||
        dnf5 -y install --repo=fedora --repo=updates distribution-gpg-keys
    for repo in "$@"; do
        rpm --import "/usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-${repo}-fedora-${fedora}"
        packages+=("https://mirrors.rpmfusion.org/${repo}/fedora/rpmfusion-${repo}-release-${fedora}.noarch.rpm")
    done
    dnf5 -y install --setopt=localpkg_gpgcheck=1 "${packages[@]}"
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
