#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Beta Updates Testing Repo...
if [[ "${UBLUE_IMAGE_TAG}" == "beta" ]]; then
    dnf5 config-manager setopt updates-testing.enabled=1
fi

# Remove Existing Kernel
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    rpm --erase $pkg --nodeps
done

# Fetch Common AKMODS & Kernel RPMS
skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods:"${AKMODS_FLAVOR}"-"$(rpm -E %fedora)"-"${KERNEL}" dir:/tmp/akmods
AKMODS_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods/manifest.json | cut -d : -f 2)
tar -xvzf /tmp/akmods/"$AKMODS_TARGZ" -C /tmp/
mv /tmp/rpms/* /tmp/akmods/
# NOTE: kernel-rpms should auto-extract into correct location

# Install Kernel
dnf5 -y install \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

# TODO: Figure out why akmods cache is pulling in akmods/kernel-devel
dnf5 -y install \
    /tmp/kernel-rpms/kernel-devel-*.rpm

dnf5 versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra

# Everyone
# NOTE: we won't use dnf5 copr plugin for ublue-os/akmods until our upstream provides the COPR standard naming
sed -i 's@enabled=0@enabled=1@g' /etc/yum.repos.d/_copr_ublue-os-akmods.repo

# RPMFUSION Dependent AKMODS
if [[ "${UBLUE_IMAGE_TAG}" == "beta" ]]; then
    dnf5 -y install \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm || true
    dnf5 -y install \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm || true
    dnf5 -y install \
        v4l2loopback /tmp/akmods/kmods/*v4l2loopback*.rpm || true
    dnf5 -y remove rpmfusion-free-release || true
    dnf5 -y remove rpmfusion-nonfree-release || true
else
    dnf5 -y install \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm
    dnf5 -y install \
        v4l2loopback /tmp/akmods/kmods/*v4l2loopback*.rpm
    dnf5 -y remove rpmfusion-free-release rpmfusion-nonfree-release
fi

# DisplayLink (USB docks and adapters): the prebuilt evdi kmod is only published in akmods-extra, which is
# not built for the main or coreos-stable kernels. Build it here against the image kernel from negativo17's
# akmod, the same way akmods-extra does, then drop the build tooling.
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
dnf5 -y install akmods
dnf5 -y mark dependency akmods
# Without scriptlets: akmod-evdi's %post (akmods-ostree-post, run because os-release has OSTREE_VERSION) builds
# as root, which akmodsbuild refuses when /var is writable as it is here, and fails the transaction.
# akmods below builds as its own user instead. displaylink requires the kmod, so it goes in the same transaction.
dnf5 -y install --enablerepo=fedora-multimedia --setopt=tsflags=noscripts \
    akmod-evdi \
    displaylink \
    libevdi
# Secure Boot only loads evdi when it is signed with a key enrolled in MOK (ujust enroll-secure-boot-key).
# akmods signs with the key found at these paths; without one it makes a throwaway key, and evdi is then
# rejected by any machine with Secure Boot on.
AKMODS_CERT=/etc/pki/akmods/certs/amethystora-modules.der
if [[ -s /run/secrets/AKMODS_PRIVKEY ]]; then
    install -Dm644 /run/secrets/AKMODS_PRIVKEY /etc/pki/akmods/private/private_key.priv
    install -Dm644 "${AKMODS_CERT}" /etc/pki/akmods/certs/public_key.der
else
    echo "WARNING: no AKMODS_PRIVKEY secret, evdi will not load with Secure Boot on"
fi
CFLAGS="-fno-pie -no-pie" akmods --force --kernels "${KERNEL_VERSION}" --kmod evdi
EVDI_KO="/usr/lib/modules/${KERNEL_VERSION}/extra/evdi/evdi.ko.xz"
modinfo "${EVDI_KO}" >/dev/null ||
    { find /var/cache/akmods/evdi/ -name '*.log' -print -exec cat {} \; && exit 1; }
if [[ -s /run/secrets/AKMODS_PRIVKEY ]]; then
    # sign-file names the signing certificate by its serial number, which modinfo reports as sig_key
    # (colon separated, where openssl prints plain hex; both may differ by leading zeros)
    [[ "$(modinfo -F sig_key "${EVDI_KO}" | tr -d ':' | sed 's/^0*//')" == \
        "$(openssl x509 -inform DER -in "${AKMODS_CERT}" -noout -serial | cut -d= -f2 | sed 's/^0*//')" ]]
fi
dnf5 -y remove akmod-evdi
# The signing key used for the build (and any akmods generated): never ship it
find /etc/pki/akmods -type f -o -type l 2>/dev/null | while read -r file; do
    [[ "${file}" == "${AKMODS_CERT}" ]] || rpm -qf "${file}" >/dev/null 2>&1 || rm -f "${file}"
done
# DisplayLinkManager runs from boot, as the package preset (skipped above with the scriptlets) and Bazzite have it:
# the udev rule that would start it on plug only matches docks whose USB manufacturer string is "DisplayLink",
# and most rebranded docks report their own.
systemctl enable displaylink.service

# Nvidia AKMODS
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    # Fetch Nvidia RPMs
    skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods-nvidia-open:"${AKMODS_FLAVOR}"-"$(rpm -E %fedora)"-"${KERNEL}" dir:/tmp/akmods-rpms
    NVIDIA_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods-rpms/manifest.json | cut -d : -f 2)
    tar -xvzf /tmp/akmods-rpms/"$NVIDIA_TARGZ" -C /tmp/
    mv /tmp/rpms/* /tmp/akmods-rpms/

    # Exclude the Golang Nvidia Container Toolkit in Fedora Repo
    # Exclude for non-beta.... doesn't appear to exist for F42 yet?
    if [[ "${UBLUE_IMAGE_TAG}" != "beta" ]]; then
        dnf5 config-manager setopt excludepkgs=golang-github-nvidia-container-toolkit
    else
        # Monkey patch right now...
        if ! grep -q negativo17 <(rpm -qi mesa-dri-drivers); then
            dnf5 -y swap --repo=updates-testing \
                mesa-dri-drivers mesa-dri-drivers
        fi
    fi

    # Install Nvidia RPMs
    IMAGE_NAME="${BASE_IMAGE_NAME}" AKMODNV_PATH="/tmp/akmods-rpms" MULTILIB=0 /tmp/akmods-rpms/ublue-os/nvidia-install.sh
    rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
    ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
    tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF
fi

# ZFS for stable
if [[ ${AKMODS_FLAVOR} =~ coreos ]]; then
    # Fetch ZFS RPMs
    skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods-zfs:"${AKMODS_FLAVOR}"-"$(rpm -E %fedora)"-"${KERNEL}" dir:/tmp/akmods-zfs
    ZFS_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods-zfs/manifest.json | cut -d : -f 2)
    tar -xvzf /tmp/akmods-zfs/"$ZFS_TARGZ" -C /tmp/
    mv /tmp/rpms/* /tmp/akmods-zfs/

    # Declare ZFS RPMs
    ZFS_RPMS=(
        /tmp/akmods-zfs/kmods/zfs/kmod-zfs-"${KERNEL}"-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libnvpair[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libuutil[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libzfs[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libzpool[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/python3-pyzfs-*.rpm
        /tmp/akmods-zfs/kmods/zfs/zfs-*.rpm
        pv
    )

    # Install
    dnf5 -y install "${ZFS_RPMS[@]}"

    # Depmod and autoload
    depmod -a -v "${KERNEL}"
    echo "zfs" >/usr/lib/modules-load.d/zfs.conf
fi

echo "::endgroup::"
