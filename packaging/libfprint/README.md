# libfprint with the FocalTech FT9201 reader

Fedora's libfprint package with nineteen patches, for a FocalTech FT9201 reader that libfprint does not
support yet: USB `2808:93a9`, an inexpensive press sensor sold as a USB key. Its 64x80 siblings `2808:9338`
and `2808:9348`, which the patches also cover, are left out (0019). Each image build makes it in the
Containerfile's `libfprint` stage
(`build_files/shared/build-libfprint.sh`), on the same pinned base image, and
`build_files/base/05-override-install.sh` installs it in place of Fedora's and puts its source package in
`/usr/src/amethystora`. fprintd, Fedora's or `packaging/fprintd`'s, links against it unchanged: the patches
add a driver and change no interface.

- **0001 to 0015** are libfprint merge requests
  [!572](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/572) (0xCoDSnet: the
  `focaltech_moh` driver for `2808:9338`, its USB protocol reverse engineered) and
  [!646](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/646) (dgmtnz: `2808:9348`,
  identify, a retuned matcher), as they stood on 2026-10-17, neither merged.
- **0016 to 0018** are Amethystora's, written to be proposed upstream on top of them:
  - 0016: `2808:93a9`, whose FT9201 sits behind an older USB bridge (AFE registers through request `0x3A`,
    the frame through `0x35`), with a 96x96 sensor that captures by itself when touched;
  - 0017: a matcher that decides on minutiae. The correlation matcher of 0004 to 0014 accepts a wrong finger
    about once in 550 presses, because parallel ridges of different fingers line up once angle, spacing and
    phase are tuned. This one aligns by masked correlation over rotations and shifts, then counts minutiae
    that agree at that pose in two enrolled presses;
  - 0018: the driver uses it, in a thread, enrols by groups of presses that link up, and asks again for a
    press it cannot decide on. Prints made with 0004 to 0015 are not read.
- **0019** is Amethystora's alone, not for upstream: the driver claims `2808:93a9` only, and `2808:9338` and
  `2808:9348` go back to libfprint's list of unsupported devices, as in its releases. On their 64x80 sensor
  the matcher was measured at one false accept in 39848 usable presses of another finger (a 95% upper bound
  of 1 in 8400), with 60% of presses asked for again: short of what signing in and `sudo` need. Drop it once
  a matcher is shown safe on them.

The spec is Fedora's (MIT, as Fedora's spec files are) with `Release`, the patches, a `%check` and the
changelog changed. The patches are LGPL-2.1-or-later, as libfprint is. `sources` pins the release tarball's
SHA-512, Fedora's own. The stage takes the tarball from Fedora's lookaside cache, or from libfprint's GitLab
for a release Fedora does not have, and checks it against that.

## What is known about the matcher, and what is not

It was chosen and measured on synthetic fingerprints, generated after SFinGe, never on anyone's: on 2200
fingers it was not tuned on, of 246753 usable presses of another finger (148086 of them another finger of
the same person) none was accepted, a 95% upper bound of one in 82000; a usable press of the right finger is
accepted 73% of the time, and 18% of presses are asked for again. The tools and how to reproduce this are in
the lab repository that goes with the merge request (`ft9201-lab`). Its `%check` runs the matcher's own tests
on every image build.

What that does not show: how real skin on a real FT9201 does. The `2808:93a9` protocol was worked out and
tested on a real reader with knuckles, which carry no fingerprint; the matcher has not met a real finger.

## Making the patches again

From a clone of `https://gitlab.freedesktop.org/libfprint/libfprint.git` with LF line endings
(`git clone -c core.autocrlf=false`):

```sh
git fetch origin refs/merge-requests/646/head:mr646
git checkout -b amethystora v1.94.100
git cherry-pick $(git merge-base master mr646)..mr646   # !572's six commits and !646's nine
# ...then Amethystora's three for upstream, then 0019
git format-patch --no-signature --zero-commit v1.94.100..HEAD -o <this folder>
```

Then build with every driver and run the whole suite, and the matcher's test under Valgrind:

```sh
meson setup build -Ddrivers=all -Ddoc=false && ninja -C build && meson test -C build
G_TEST_SRCDIR=$PWD/tests valgrind --error-exitcode=9 build/tests/test-focaltech-moh-match
```

## When libfprint makes a release

Renovate looks for one every Monday and opens a pull request that changes `Version`. That pull request's build
fails, because `sources` still names the old tarball, so the update is made on main by hand, and Renovate then
closes it:

1. Put the new tarball's SHA-512 in `sources`.
2. Drop the patches the release carries, and rebase the rest on it.
3. Run the whole test suite, as above.
4. Set `Release` to Fedora's for that version (or `1` if Fedora has none yet) with `.1.amethystora`.

## When Fedora changes libfprint

`05-override-install.sh` refuses a base image whose libfprint has another version, or a release above the one
`Release` starts with. Take Fedora's spec into this one then, keeping the header, `Release`, the `Patch`
lines, `%check` and the changelog, and raise `Release` past Fedora's.
