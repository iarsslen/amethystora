#!/usr/bin/bash
# The Containerfile's libfprint stage: Fedora's libfprint with the FocalTech FT9201 readers
# (packaging/libfprint), built on the same base image it is installed into, so that it links against the
# libraries the image has. Only two packages leave the stage, in /out: libfprint, which
# 05-override-install.sh installs in place of Fedora's, and its source package, which travels in the image
# as the LGPL asks. The build runs the FT9201 matcher's tests (the spec's %check).

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

PACKAGE=/ctx/packaging/libfprint
SPEC="${PACKAGE}/libfprint.spec"
TOP=/tmp/rpmbuild
mkdir -p "${TOP}/SOURCES" /out
cp "${PACKAGE}"/*.patch "${TOP}/SOURCES/"

# The tools and the build dependencies from Fedora's own repositories alone: the base image also has
# negativo17's, which outranks Fedora's (05-override-install.sh)
dnf5 -y install --repo=fedora --repo=updates rpm-build rpmdevtools dnf5-plugins

# The release tarball, checked against the SHA-512 pinned in sources. From Fedora's lookaside cache, which
# keeps every tarball Fedora built from under its SHA-512 and is where Fedora's builders take it from, and
# from libfprint's GitLab, which makes it on demand, for a release Fedora does not have yet
TARBALL="$(spectool --list-files "${SPEC}" | sed -n 's|^Source0: .*/||p')"
SHA512="$(sed -n "s|^SHA512 (${TARBALL}) = \([0-9a-f]\{128\}\)$|\1|p" "${PACKAGE}/sources")"
curl --fail --location --retry 3 -o "${TOP}/SOURCES/${TARBALL}" \
    "https://src.fedoraproject.org/repo/pkgs/rpms/libfprint/${TARBALL}/sha512/${SHA512}/${TARBALL}" ||
    spectool --get-files --directory "${TOP}/SOURCES" "${SPEC}"
(cd "${TOP}/SOURCES" && sha512sum -c "${PACKAGE}/sources")

dnf5 -y builddep --repo=fedora --repo=updates "${SPEC}"
rpmbuild -ba --define "_topdir ${TOP}" "${SPEC}"
cp "${TOP}"/RPMS/*/libfprint-[0-9]*.rpm "${TOP}"/SRPMS/libfprint-*.src.rpm /out/
ls -l /out

echo "::endgroup::"
