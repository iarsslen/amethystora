#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Where the source of everything in the image is, which the GPL and LGPL ask whoever distributes a
# program to say: every package with its licence, the source package it was built from, and where
# that exact source package is published. Fedora keeps the source of each of its builds in Koji
# for good, at an address the name, version and release give; for the others, the maker named by
# the package's vendor publishes it. NOTICE carries the written offer that covers the rest.
# Runs after dx, so that it lists every package the image ships.

MANIFEST=/usr/share/licenses/amethystora/SOURCES
# shellcheck source=/dev/null
source /usr/lib/os-release

{
    cat <<EOF
# Sources of ${PRETTY_NAME}

Each package in this image, with its licence, the source package it was built from, and where that
source package is published. Everything not installed from a package is built from
https://github.com/iarsslen/amethystora at commit ${BUILD_ID:-unknown}, whose build_files pin each
upstream release they fetch. The written offer for the source of anything under the GPL or LGPL is
in NOTICE, beside this file.

EOF
    printf 'PACKAGE\tLICENCE\tSOURCE PACKAGE\tSOURCE\n'
    rpm -qa --queryformat '%{NAME}\t%{LICENSE}\t%{SOURCERPM}\t%{VENDOR}\n' |
        awk -F'\t' '$3 != "(none)"' | sort |
        awk -F'\t' -v OFS='\t' '{
            source = $4
            if ($4 == "Fedora Project") {
                nvr = $3
                sub(/\.src\.rpm$/, "", nvr)
                n = split(nvr, part, "-")
                name = substr(nvr, 1, length(nvr) - length(part[n - 1]) - length(part[n]) - 2)
                source = "https://kojipkgs.fedoraproject.org/packages/" name "/" part[n - 1] "/" part[n] "/src/" $3
            }
            print $1, $2, $3, source
        }'
} >"${MANIFEST}"

grep -qP '^kernel-core\t' "${MANIFEST}"

echo "::endgroup::"
