# Fedora's libfprint (https://src.fedoraproject.org/rpms/libfprint, the same spec on f43, f44, f45 and
# rawhide on 2026-10-18) with the FocalTech FT9201 readers, built in the Containerfile's libfprint stage
# (build_files/shared/build-libfprint.sh) and installed in place of Fedora's by 05-override-install.sh.
# Only Release, the patches, the check and the changelog differ from Fedora's; Fedora's %%autorelease and
# %%autochangelog only work in Fedora's own tree. Release is Fedora's (1.94.100-1 everywhere) with
# ".1.amethystora" after it, so that it replaces Fedora's build; when Fedora's passes it, the image build
# fails until this file takes Fedora's change. Renovate looks for a new libfprint release every week
# (.github/renovate.json5).
#
# Patches 1 to 15 are the focaltech_moh driver of libfprint merge requests !572 (0xCoDSnet) and !646
# (dgmtnz), for 2808:9338 and 2808:9348; 16 to 19 are Amethystora's, written for upstream: 2808:93a9, a
# matcher that decides on minutiae, which the earlier ones' correlation matcher could not do safely, and a
# test recorded on 2808:93a9; 20 is Amethystora's alone: it drives 2808:93a9 only, the 64x80 sensors
# falling short with that matcher. The patches are LGPL-2.1-or-later, as libfprint is. README.md says where
# they come from, how to make them again, and what does not work yet.
Name:           libfprint

Version:        1.94.100
Release:        1.1.amethystora%{?dist}
Summary:        Toolkit for fingerprint scanner

# Automatically converted from old format: LGPLv2+ - review is highly recommended.
# Most of the code is LGPL-2.1-or-later
# libfprint/nbis is NIST-PD
License:        LGPL-2.1-or-later AND NIST-PD
URL:            http://www.freedesktop.org/wiki/Software/fprint/libfprint
Source0:        https://gitlab.freedesktop.org/libfprint/libfprint/-/archive/v%{version}/libfprint-v%{version}.tar.gz

Patch:          0001-Add-FocalTech-FT9201-fingerprint-sensor-driver.patch
Patch:          0002-focaltech_moh-add-finger-detection-via-INT_STATUS-po.patch
Patch:          0003-focaltech_moh-implement-multi-stage-enrollment.patch
Patch:          0004-focaltech_moh-switch-to-custom-NCC-matching-for-veri.patch
Patch:          0005-focaltech_moh-add-umockdev-test-for-enroll-and-verif.patch
Patch:          0006-focaltech_moh-update-udev-hwdb-for-supported-device.patch
Patch:          0007-focaltech_moh-retune-matcher-parameters-against-meas.patch
Patch:          0008-focaltech_moh-add-raw-image-capture.patch
Patch:          0009-focaltech_moh-implement-identify.patch
Patch:          0010-focaltech_moh-address-review-add-2808-9348.patch
Patch:          0011-focaltech_moh-satisfy-uncrustify.patch
Patch:          0012-focaltech_moh-drain-stale-INT_STATUS-speed-up-matchi.patch
Patch:          0013-focaltech_moh-require-corroboration-instead-of-a-sin.patch
Patch:          0014-focaltech_moh-confirm-by-counting-templates-not-by-s.patch
Patch:          0015-focaltech_moh-honour-cancellation-on-long-running-op.patch
Patch:          0016-focaltech_moh-support-the-old-SIU-bridge-of-2808-93a.patch
Patch:          0017-focaltech_moh-add-a-matcher-that-decides-on-minutiae.patch
Patch:          0018-focaltech_moh-match-with-the-minutiae-matcher-in-a-t.patch
Patch:          0019-focaltech_moh-add-a-test-recorded-on-2808-93a9.patch
Patch:          0020-focaltech_moh-drive-2808-93a9-alone-for-Amethystora.patch

BuildRequires:  meson
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  git
BuildRequires:  openssl-devel
BuildRequires:  pkgconfig(glib-2.0) >= 2.50
BuildRequires:  pkgconfig(gio-2.0) >= 2.44.0
BuildRequires:  pkgconfig(gusb) >= 0.3.0
BuildRequires:  pkgconfig(nss)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  gtk-doc
BuildRequires:  libgudev-devel
# For the udev.pc to install the rules
BuildRequires:  systemd
BuildRequires:  gobject-introspection-devel
# For internal CI tests; umockdev 0.13.2 has an important locking fix
BuildRequires:  python3-cairo python3-gobject cairo-devel
BuildRequires:  umockdev >= 0.13.2

%description
libfprint offers support for consumer fingerprint reader devices.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description    devel
The %{name}-devel package contains libraries and header files for
developing applications that use %{name}.

%package        tests
Summary:        Tests for the %{name} package
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description tests
The %{name}-tests package contains tests that can be used to verify
the functionality of the installed %{name} package.

%prep
%autosetup -S git -n libfprint-v%{version}

%build
# Include the virtual image driver for integration tests
%meson -Ddrivers=all
%meson_build

%install
%meson_install

%check
# The FT9201 matcher on synthetic presses: genuine accepted, impostors and
# parallel ridges refused, malformed prints refused, corrupted ones survived;
# then the driver against the USB traffic recorded on a real 2808:93a9.
%meson_test focaltech-moh-match focaltech_moh-93a9

%ldconfig_scriptlets

# TODO: The test can't run with the recent pygobject3.52.
# So, skip the test until the issue of pygobject is fixed.

%files
%license COPYING
%doc NEWS THANKS AUTHORS README.md
%{_libdir}/*.so.*
%{_libdir}/girepository-1.0/*.typelib
%{_udevhwdbdir}/60-autosuspend-libfprint-2.hwdb
%{_udevrulesdir}/70-libfprint-2.rules
%{_datadir}/metainfo/org.freedesktop.libfprint.metainfo.xml

%files devel
%doc HACKING.md
%{_includedir}/*
%{_libdir}/*.so
%{_libdir}/pkgconfig/%{name}-2.pc
%{_datadir}/gir-1.0/*.gir
%{_datadir}/gtk-doc/html/libfprint-2/

%files tests
%{_libexecdir}/installed-tests/libfprint-2/
%{_datadir}/installed-tests/libfprint-2/

%changelog
* Sun Oct 18 2026 Arsslen Idadi <arsslens021@gmail.com> - 1.94.100-1.1.amethystora
- Add the focaltech_moh driver for the FocalTech FT9201 readers 2808:9338
  and 2808:9348 (libfprint merge requests !572 and !646)
- Support 2808:93a9, behind the FT9201's older USB bridge, once FocalTech's
  Windows driver has set it up since power-on
- Match on minutiae at the pose masked correlation finds, in a thread
- Add a test recorded on 2808:93a9
- Drive 2808:93a9 alone: the 64x80 sensors fall short with this matcher
- Run the matcher's tests and the 2808:93a9 recording in %%check
- Fedora's changelog is in Fedora's tree, which %%autochangelog reads
