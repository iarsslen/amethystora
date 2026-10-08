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

# The fingerprint of each primary key in an OpenPGP key file, one per line
key_fingerprints() {
    gpg --homedir "$(mktemp -d)" --show-keys --with-colons "$1" |
        awk -F: '$1 == "pub" { pub = 1; next } pub && $1 == "fpr" { print $10; pub = 0 }'
}

# A repository that is not Fedora's serves its signing key from its own server, beside the packages the
# key signs, and dnf imports whatever key is there on first use. pin_repo_key fetches the one key a
# repository file names, refuses it unless it is exactly the key with the fingerprint pinned here, keeps
# it in /etc/pki/rpm-gpg and points the file at that copy, so that dnf never takes another key from the
# server. Run it after the repository file is written and before anything is installed from it.
pin_repo_key() {
    local repo_file="$1" fingerprint="$2" url key
    url="$(sed -n 's/^gpgkey[[:space:]]*=[[:space:]]*//p' "${repo_file}" | sort -u)"
    if [[ -z "${url}" || "${url}" == *[[:space:]]* ]]; then
        echo "ERROR: ${repo_file} does not name exactly one key: ${url}"
        return 1
    fi
    key="/etc/pki/rpm-gpg/$(basename "${repo_file}" .repo).gpg"
    curl --fail --retry 3 -sSL -o "${key}" "${url}"
    if [[ "$(key_fingerprints "${key}")" != "${fingerprint}" ]]; then
        echo "ERROR: the key ${url} serves is not the one pinned for ${repo_file} (${fingerprint})"
        return 1
    fi
    sed -i "s|^gpgkey[[:space:]]*=.*|gpgkey=file://${key}|" "${repo_file}"
}

# The Copr projects' signing keys, by fingerprint, as served on 2026-10-08. A project that changes its
# key fails the build here until the new one is checked and pinned.
declare -A COPR_KEYS=(
    [che/nerd-fonts]=EA77065A73609F55594296A87F576A671C010B19
    [ublue-os/packages]=AB4670779555943799BE7ED916BC8535A444A78A
    [bieszczaders/kernel-cachyos-addons]=A98571785D3845AEF14B16B1CDD249F6F4033A98
)

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
    pin_repo_key "/etc/yum.repos.d/_${repo_id}.repo" "${COPR_KEYS[${copr_name}]:?no key pinned for ${copr_name}}"
    dnf_install_retry --enablerepo="$repo_id" "${packages[@]}"

    echo "Installed ${packages[*]} from $copr_name"
}
