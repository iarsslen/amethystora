//! Narrowing refused opens by path. The BPF's open_refused hook has no inode to match (the open failed, so
//! there is no file to read i_ino from), so it emits every enabled read or write key with the path the
//! system call gave and leaves the matching to the daemon. This holds the watch roots, by direction, so a
//! refused open is kept only for the keys that truly watch its path. Without it, every EACCES/EPERM open an
//! account makes — reading /proc, probing a path it may not read — would be recorded under credentials and
//! the decoy, as if a secret had been read.
//!
//! Pure path logic, no BPF, so it is compiled and unit-tested under `cargo test` (run.rs, which loads the
//! BPF object, is not).

use std::os::unix::ffi::OsStrExt;

use crate::plan::{self, Kind};

/// Which watched paths a refused open falls under, by direction.
#[derive(Default)]
pub struct RefusedMatcher {
    read_trees: Vec<(Vec<u8>, u32)>,
    read_files: Vec<(Vec<u8>, u32)>,
    write_trees: Vec<(Vec<u8>, u32)>,
    write_files: Vec<(Vec<u8>, u32)>,
}

impl RefusedMatcher {
    pub fn add(&mut self, w: &plan::Watch) {
        let bit = 1u32 << w.key_bit;
        let path = w.path.as_os_str().as_bytes().to_vec();
        match w.kind {
            Kind::Tree => self.write_trees.push((path, bit)),
            Kind::File => self.write_files.push((path, bit)),
            Kind::ReadTree => self.read_trees.push((path, bit)),
            Kind::ReadFile => self.read_files.push((path, bit)),
            // A program run from a folder is its own hook; a refused open never matches an exec watch.
            Kind::ExecTree => {}
        }
    }

    /// The keys that watch a refused open of `path` (absolute): a write when `write`, otherwise a read.
    pub fn keys(&self, path: &[u8], write: bool) -> u32 {
        let (trees, files) =
            if write { (&self.write_trees, &self.write_files) } else { (&self.read_trees, &self.read_files) };
        let mut mask = 0;
        for (f, k) in files {
            if path == f.as_slice() {
                mask |= k;
            }
        }
        for (t, k) in trees {
            if under(path, t) {
                mask |= k;
            }
        }
        mask
    }
}

/// Whether `path` is `root` itself or something below it.
fn under(path: &[u8], root: &[u8]) -> bool {
    path == root || (path.len() > root.len() && path.starts_with(root) && path[root.len()] == b'/')
}

/// The absolute path a refused open names, in the spelling the watch list uses. The system call's path as
/// given (open_refused reports it raw, unresolved), joined to the working folder when relative, then
/// collapsed lexically (`.`, `..`, repeated slashes) and with a leading `/home/` folded to `/var/home/` —
/// the generator stores every home watch under its `/var/home` realpath (`/home` is a symlink to it), so a
/// refused open addressed as `/home/<user>/...`, or with `..`, must fold to the same bytes to match. The
/// match stays string-based (the open failed, so there is no inode to match by, unlike an allowed open); a
/// refused path reached through some other symlinked parent is still not matched, a gap only in this
/// secondary net, never in the inode-matched reads of allowed opens.
pub fn refused_path(path2: &[u8], cwd: &[u8]) -> Vec<u8> {
    let joined = if path2.first() == Some(&b'/') || cwd.is_empty() {
        path2.to_vec()
    } else {
        let mut v = cwd.to_vec();
        if v.last() != Some(&b'/') {
            v.push(b'/');
        }
        v.extend_from_slice(path2);
        v
    };
    let mut out = normalize(&joined);
    fold_home(&mut out);
    out
}

/// Collapses `.`, `..` and repeated slashes in an absolute path, lexically (no filesystem access, so no
/// symlink is followed). A `..` at the root stays at the root, as the kernel resolves it. A relative path
/// (no cwd to join) is left as-is: it cannot match an absolute watch anyway.
fn normalize(path: &[u8]) -> Vec<u8> {
    if path.first() != Some(&b'/') {
        return path.to_vec();
    }
    let mut parts: Vec<&[u8]> = Vec::new();
    for comp in path.split(|&b| b == b'/') {
        match comp {
            b"" | b"." => {}
            b".." => {
                parts.pop();
            }
            c => parts.push(c),
        }
    }
    let mut out = Vec::with_capacity(path.len());
    for c in &parts {
        out.push(b'/');
        out.extend_from_slice(c);
    }
    if out.is_empty() {
        out.push(b'/');
    }
    out
}

/// Folds a leading `/home` to `/var/home`, the symlink the generator resolves away when it stores a watch.
fn fold_home(path: &mut Vec<u8>) {
    if path.starts_with(b"/home/") {
        path.splice(0..5, *b"/var/home");
    } else if path.as_slice() == b"/home" {
        *path = b"/var/home".to_vec();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn watch(kind: Kind, bit: u32, path: &str) -> plan::Watch {
        plan::Watch { kind, key_bit: bit, path: PathBuf::from(path) }
    }

    // credentials is bit 9, decoy bit 10, identity bit 0 (keys.rs).
    const CRED: u32 = 1 << 9;
    const DECOY: u32 = 1 << 10;
    const IDENTITY: u32 = 1 << 0;

    fn matcher() -> RefusedMatcher {
        let mut m = RefusedMatcher::default();
        m.add(&watch(Kind::ReadFile, 9, "/var/home/a/.ssh/id_ed25519"));
        m.add(&watch(Kind::ReadFile, 9, "/var/home/a/.ssh/id_backup"));
        m.add(&watch(Kind::ReadFile, 10, "/var/home/a/.ssh/id_backup"));
        m.add(&watch(Kind::ReadTree, 9, "/var/home/a/.local/share/keyrings"));
        m.add(&watch(Kind::File, 0, "/etc/passwd"));
        m.add(&watch(Kind::Tree, 0, "/etc/sudoers.d"));
        m.add(&watch(Kind::ExecTree, 7, "/var/home/a/Downloads"));
        m
    }

    #[test]
    fn refused_read_of_an_unwatched_path_matches_nothing() {
        // The /proc reads that used to be recorded as "the backup's password".
        assert_eq!(matcher().keys(b"/proc/1/io", false), 0);
        assert_eq!(matcher().keys(b"/proc/1/smaps_rollup", false), 0);
        assert_eq!(matcher().keys(b"/etc/ld.so.cache", false), 0);
    }

    #[test]
    fn refused_read_narrows_to_the_files_own_keys() {
        // id_ed25519 is only a credential; the decoy must not ride along.
        assert_eq!(matcher().keys(b"/var/home/a/.ssh/id_ed25519", false), CRED);
        // id_backup is both.
        assert_eq!(matcher().keys(b"/var/home/a/.ssh/id_backup", false), CRED | DECOY);
        // anything under the keyring tree is a credential.
        assert_eq!(matcher().keys(b"/var/home/a/.local/share/keyrings/login.keyring", false), CRED);
        assert_eq!(matcher().keys(b"/var/home/a/.local/share/keyrings", false), CRED);
    }

    #[test]
    fn refused_write_matches_write_watches_only() {
        assert_eq!(matcher().keys(b"/etc/passwd", true), IDENTITY);
        assert_eq!(matcher().keys(b"/etc/sudoers.d/evil", true), IDENTITY);
        // the same path read, not written, is not a write watch
        assert_eq!(matcher().keys(b"/etc/passwd", false), 0);
        // a read watch is not a write watch
        assert_eq!(matcher().keys(b"/var/home/a/.ssh/id_ed25519", true), 0);
    }

    #[test]
    fn under_needs_a_slash_boundary() {
        assert!(under(b"/etc/sudoers.d", b"/etc/sudoers.d"));
        assert!(under(b"/etc/sudoers.d/x", b"/etc/sudoers.d"));
        assert!(!under(b"/etc/sudoers.d.bak", b"/etc/sudoers.d"));
        assert!(!under(b"/etc/sudoers.db", b"/etc/sudoers.d"));
    }

    #[test]
    fn a_relative_refused_path_joins_the_working_folder() {
        assert_eq!(refused_path(b"id_ed25519", b"/var/home/a/.ssh"), b"/var/home/a/.ssh/id_ed25519".to_vec());
        assert_eq!(refused_path(b"/etc/passwd", b"/home/x"), b"/etc/passwd".to_vec());
        assert_eq!(refused_path(b".ssh/id", b"/var/home/a/"), b"/var/home/a/.ssh/id".to_vec());
    }

    #[test]
    fn refused_path_normalises_and_folds_home() {
        // /home is a symlink to /var/home, which is how the generator stores the watch.
        assert_eq!(refused_path(b"/home/a/.ssh/id_ed25519", b""), b"/var/home/a/.ssh/id_ed25519".to_vec());
        assert_eq!(refused_path(b"/home", b""), b"/var/home".to_vec());
        // but not a path that merely starts with the letters "home".
        assert_eq!(refused_path(b"/homer/x", b""), b"/homer/x".to_vec());
        // lexical collapse of . .. and //.
        assert_eq!(refused_path(b"/etc/../etc/sudoers.d/evil", b""), b"/etc/sudoers.d/evil".to_vec());
        assert_eq!(refused_path(b"//etc///passwd", b""), b"/etc/passwd".to_vec());
        assert_eq!(refused_path(b"/a/b/../../x", b""), b"/x".to_vec());
        assert_eq!(refused_path(b"/../x", b""), b"/x".to_vec());
    }

    #[test]
    fn a_refused_watched_path_still_matches_when_spelled_via_home_or_dotdot() {
        // The cross-user / cross-privilege refused probe the audit fallback catches by inode: the attacker
        // spells the watched path the conventional way, /home not /var/home.
        assert_eq!(matcher().keys(&refused_path(b"/home/a/.ssh/id_backup", b""), false), CRED | DECOY);
        assert_eq!(matcher().keys(&refused_path(b"/home/a/.local/share/keyrings/x", b""), false), CRED);
        assert_eq!(matcher().keys(&refused_path(b"/etc/../etc/passwd", b""), true), IDENTITY);
    }
}
