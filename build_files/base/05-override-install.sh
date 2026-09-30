#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# We do not need anything here at all
rm -rf /usr/src
rm -rf /usr/share/doc
# Remove kernel-devel from rpmdb because all package files are removed from /usr/src
rpm --erase --nodeps kernel-devel

# Multimedia: FFmpeg from Fedora, with RPM Fusion's libavcodec-freeworld for the codecs Fedora leaves
# out, in place of the negativo17 build the base image installs. That build is configured with
# --enable-nonfree, linking GPL encoders with CUDA and the Fraunhofer libraries, and FFmpeg itself
# labels it "nonfree and unredistributable"; Fedora's and RPM Fusion's are GPL-3.0-or-later.
# negativo17's pipewire-libs-extra goes too: its LC3plus plugin links liblc3plus, whose code comes with
# no licence to redistribute it. aptX comes from RPM Fusion instead, and Fedora's own PipeWire carries
# the other Bluetooth codecs (AAC, LDAC, LC3, Opus). negativo17's packages claim Fedora's names at the
# same or higher versions, so they are taken out first, and the replacements come only from the
# repositories named, never from negativo17's (fedora-multimedia, which outranks Fedora's).
NEGATIVO17_MULTIMEDIA=(
    ffmpeg ffmpeg-libs libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale
    libfdk-aac mpeghdec liblc3plus libfreeaptx pipewire-libs-extra
    davs2-libs kvazaar-libs LCEVCdec libquirc librtmp libxavs svt-jpeg-xs uavs3d-libs vvenc-libs
    x264-libs x265-libs xavs2-libs xevd-libs xeve-libs
)
readarray -t NEGATIVO17_INSTALLED < <(rpm -qa --queryformat '%{NAME}\t%{VENDOR}\n' "${NEGATIVO17_MULTIMEDIA[@]}" |
    awk -F'\t' '$2 == "negativo17.org" { print $1 }')
MULTIMEDIA_DEPENDENTS=()
if ((${#NEGATIVO17_INSTALLED[@]})); then
    # Whatever needs them now has to be satisfied by the replacements, which is checked below
    readarray -t MULTIMEDIA_DEPENDENTS < <(rpm -q --provides "${NEGATIVO17_INSTALLED[@]}" | awk '{ print $1 }' |
        sort -u | xargs -d '\n' rpm -q --whatrequires --queryformat '%{NAME}\n' | grep -v '^no package requires' |
        sort -u | grep -vxF -f <(printf '%s\n' "${NEGATIVO17_INSTALLED[@]}"))
    rpm --erase --nodeps "${NEGATIVO17_INSTALLED[@]}"
fi
dnf -y install --repo=fedora --repo=updates \
    ffmpeg-free fdk-aac-free libavcodec-free libavfilter-free libavformat-free libavutil-free \
    libswresample-free libswscale-free
dnf -y install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_MAJOR_VERSION}.noarch.rpm"
sed -i 's@^enabled=1@enabled=0@' /etc/yum.repos.d/rpmfusion-free*.repo
dnf -y install --repo=fedora --repo=updates --repo=rpmfusion-free --repo=rpmfusion-free-updates \
    libavcodec-freeworld pipewire-codec-aptx
if ((${#MULTIMEDIA_DEPENDENTS[@]})); then
    rpm --verify --nofiles --noscripts "${MULTIMEDIA_DEPENDENTS[@]}"
fi

# Starship Shell Prompt
ghcurl "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz" --retry 3 -o /tmp/starship.tar.gz
tar -xzf /tmp/starship.tar.gz -C /tmp
install -c -m 0755 /tmp/starship /usr/bin

# Remove desktop entries
if [[ -f /usr/share/applications/gnome-system-monitor.desktop ]]; then
    sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/gnome-system-monitor.desktop
fi
if [[ -f /usr/share/applications/org.gnome.SystemMonitor.desktop ]]; then
    sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/org.gnome.SystemMonitor.desktop
fi

# Add Mutter experimental-features
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    sed -i "/experimental-features/ s/\]/, 'kms-modifiers'&/" /usr/share/glib-2.0/schemas/zz0-amethystora-modifications.gschema.override
    echo "Compiling gschema to include the kms-modifiers override"
    glib-compile-schemas /usr/share/glib-2.0/schemas
fi

echo "::endgroup::"
