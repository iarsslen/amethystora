# Fedora's fprintd (https://src.fedoraproject.org/rpms/fprintd, the same spec on f44, f45 and rawhide on
# 2026-10-11) with Amethystora's duress finger, built in the Containerfile's fprintd stage
# (build_files/shared/build-fprintd.sh) and installed in place of Fedora's by 05-override-install.sh. Only
# Release, the patches and the changelog differ from Fedora's. Release is Fedora's highest (1.94.5-6 on
# rawhide) with ".1.amethystora" after it, so that it replaces Fedora's build on every release; when
# Fedora's passes it, the image build fails until this file takes Fedora's change. Renovate looks for a new
# fprintd release every week (.github/renovate.json5).
#
# Patches 1 to 6 are upstream's, from fprintd's master after 1.94.5: the signals go to the client that
# claimed the reader alone, the VerifyFingerMatched signal, and the test mock's support for it. Patch 7 is
# Amethystora's: pam_fprintd's duress=allow|deny options (pam_fprintd(8)). The patches are GPL-2.0-or-later,
# as fprintd is. README.md says how to make them again.
Name:		fprintd
Version:	1.94.5
Release:	6.1.amethystora%{?dist}
Summary:	D-Bus service for Fingerprint reader access

# man page is GFDL-1.1-or-later
License:	GPL-2.0-or-later AND GFDL-1.1-or-later
Source0:	https://gitlab.freedesktop.org/libfprint/fprintd/-/archive/v%{version}/fprintd-v%{version}.tar.gz
Url:		http://www.freedesktop.org/wiki/Software/fprint/fprintd

Patch:		0001-device-Emit-signals-only-to-the-claiming-clients.patch
Patch:		0002-device-Add-VerifyFingerMatched-signal-to-notify-the-.patch
Patch:		0003-tests-dbusmock-fprintd-Save-enrolling-finger.patch
Patch:		0004-tests-dbusmock-fprintd-Cleanup-the-emission-code.patch
Patch:		0005-tests-dbusmock-fprintd-Add-VerifyFingerMatched-signa.patch
Patch:		0006-tests-dbusmock-fprintd-Report-an-enrolled-finger-on-.patch
Patch:		0007-pam-Start-Amethystora-s-duress-action-on-the-duress-.patch

BuildRequires:	meson
BuildRequires:	gcc
BuildRequires:	gcc-c++
BuildRequires:	git
BuildRequires:	pam-devel
BuildRequires:	libfprint-devel >= 1.94.0
BuildRequires:	polkit-devel
BuildRequires:	gtk-doc
BuildRequires:	gettext
BuildRequires:	perl-podlators
BuildRequires:	pkgconfig(libsystemd)
BuildRequires:	pkgconfig(systemd)
BuildRequires:	python3-dbusmock
BuildRequires:	python3-libpamtest


%description
D-Bus service to access fingerprint readers.

%package pam
Summary:	PAM module for fingerprint authentication
Requires:	%{name} = %{version}-%{release}
# Note that we obsolete pam_fprint, but as the configuration
# is different, it will be mentioned in the release notes
Provides:	pam_fprint = %{version}-%{release}
Obsoletes:	pam_fprint < 0.2-3
Requires(postun): authselect >= 0.3

License:	GPL-2.0-or-later

%description pam
PAM module that uses the fprintd D-Bus service for fingerprint
authentication.

%package devel
Summary:	Development files for %{name}
Requires:	%{name} = %{version}-%{release}
# dbus interfaces are GPL-2.0-or-later
# documentation is GFDL-1.1-or-later
License:	GPL-2.0-or-later AND GFDL-1.1-or-later
BuildArch:	noarch

%description devel
Development documentation for fprintd, the D-Bus service for
fingerprint readers access.

%prep
%autosetup -S git -n %{name}-v%{version}

%build
%meson -Dgtk_doc=true -Dpam=true -Dpam_modules_dir=%{_libdir}/security
%meson_build

%install
%meson_install
mkdir -p $RPM_BUILD_ROOT/%{_localstatedir}/lib/fprint

%find_lang %{name}

%postun pam
if [ $1 -eq 0 ]; then
  /bin/authselect disable-feature with-fingerprint || :
fi

%files -f %{name}.lang
%doc README COPYING AUTHORS TODO
%{_bindir}/fprintd-*
%{_libexecdir}/fprintd
# FIXME This file should be marked as config when it does something useful
%{_sysconfdir}/fprintd.conf
%{_datadir}/dbus-1/system.d/net.reactivated.Fprint.conf
%{_datadir}/dbus-1/system-services/net.reactivated.Fprint.service
%{_unitdir}/fprintd.service
%{_datadir}/polkit-1/actions/net.reactivated.fprint.device.policy
%attr(0700, -, -) %{_localstatedir}/lib/fprint
%{_mandir}/man1/fprintd.1.gz

%files pam
%doc pam/README
%{_libdir}/security/pam_fprintd.so
%{_mandir}/man8/pam_fprintd.8.gz

%files devel
%{_datadir}/gtk-doc/
%{_datadir}/dbus-1/interfaces/net.reactivated.Fprint.Device.xml
%{_datadir}/dbus-1/interfaces/net.reactivated.Fprint.Manager.xml

%changelog
* Sun Oct 11 2026 Arsslen Idadi <arsslens021@gmail.com> - 1.94.5-6.1.amethystora
- Send the device's signals to the claiming client alone (upstream 6396302)
- Add the VerifyFingerMatched signal (upstream 38f1104)
- pam_fprintd: Amethystora's duress finger, duress=allow|deny
