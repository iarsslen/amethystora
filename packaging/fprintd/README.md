# fprintd with the duress finger

Fedora's fprintd package with seven patches, for the duress finger (`ame security duress`). Each image build
makes it in the Containerfile's `fprintd` stage (`build_files/shared/build-fprintd.sh`), on the same pinned
base image, and `build_files/base/05-override-install.sh` installs it in place of Fedora's and puts its
source package in `/usr/src/amethystora`.

- **0001 to 0006** are fprintd's own, from its master after 1.94.5, which no release carries yet:
  - 6396302 sends the device's signals to the client that claimed the reader, where 1.94.5 sends them to
    every client on the bus;
  - 38f1104 adds `VerifyFingerMatched`, which names the finger a reader that identifies matched;
  - four commits to the test mock let it send that signal.
- **0007** is Amethystora's. pam_fprintd takes `duress=allow` or `duress=deny`, reads the account's duress
  finger from `/etc/amethystora/duress.d/fingers`, and on a match with it calls `Run` on
  `org.amethystora.Duress`. `pam_fprintd(8)` describes it.

The spec is Fedora's (MIT, as Fedora's spec files are) with its `Release`, patches and changelog changed. The
patches are GPL-2.0-or-later, as fprintd is. `sources` pins the release tarball's SHA-512, Fedora's own. The
stage takes the tarball from Fedora's lookaside cache, or from fprintd's GitLab for a release Fedora does not
have, and checks it against that.

## Making the patches again

Work on a clone of `https://gitlab.freedesktop.org/libfprint/fprintd.git` with LF line endings
(`git clone -c core.autocrlf=false`):

```sh
git checkout -b amethystora-duress v1.94.5
git cherry-pick 6396302 38f1104   # the test file of each conflicts: take 1.94.5's
git cherry-pick 4a56a53 635d255 bc00667 c9cf263
# ...then the duress change, with its tests in tests/pam
git format-patch --no-signature --zero-commit v1.94.5..HEAD -o <this folder>
```

Then run the PAM tests as root, so that the duress tests run rather than skip. They read the duress file only
when it is root's:

```sh
meson setup build -Dpam=true -Dgtk_doc=false -Dpam_modules_dir=/usr/lib64/security --werror
ninja -C build && meson test -C build --suite PAM
```

## When fprintd makes a release

Renovate looks for one every Monday and opens a pull request that changes `Version`. That pull request's build
fails, because `sources` still names the old tarball, so the update is made on main by hand, and Renovate then
closes it:

1. Put the new tarball's SHA-512 in `sources`.
2. Drop each patch the release already carries. A release with 6396302 and 38f1104 leaves 0007 alone.
3. Rebase 0007 on the release and run the PAM tests.
4. Set `Release` to Fedora's for that version (or `1` if Fedora has none yet) with `.1.amethystora`.

## When Fedora changes fprintd

`05-override-install.sh` refuses a base image whose fprintd has another version, or a release above the one
`Release` starts with. Take Fedora's spec into this one then, keeping the header, `Release`, the `Patch`
lines and the changelog, and raise `Release` past Fedora's.
