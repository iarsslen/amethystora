#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eou pipefail

# Only Fedora's own repositories may be enabled in the image, updates-testing on beta alone: an enabled COPR
# or third-party repository can put its own versions of Fedora's packages on a machine. dnf5 is asked, not
# the repository files, since it and rpm-ostree also read /usr/share/dnf5/repos.d (Fedora's own from 45) and
# /etc/dnf/repos.override.d (where the base image turns negativo17's fedora-multimedia on)
FEDORA_OWN_REPOS=(fedora updates updates-archive)
[[ "${UBLUE_IMAGE_TAG:-stable}" == beta ]] && FEDORA_OWN_REPOS+=(updates-testing)

dnf5 repo list --enabled
REPO_IDS="$(dnf5 repo list --enabled --json | jq -r '.[].id')"
readarray -t ENABLED_REPOS < <(grep -vxF -f <(printf '%s\n' "${FEDORA_OWN_REPOS[@]}") <<<"${REPO_IDS}")
if ((${#ENABLED_REPOS[@]})); then
    echo "VALIDATION FAILED: these repositories are still enabled:"
    printf '  • %s\n' "${ENABLED_REPOS[@]}"
    exit 1
fi
echo "Only Fedora's own repositories are enabled"

echo "::endgroup::"
