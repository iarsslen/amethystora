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

/// The absolute path a refused open names: the system call's path as given, joined to the acting process's
/// working folder when it is relative, as open_refused leaves for the daemon to do.
pub fn refused_path(path2: &[u8], cwd: &[u8]) -> Vec<u8> {
    if path2.first() == Some(&b'/') {
        path2.to_vec()
    } else if !cwd.is_empty() {
        let mut v = cwd.to_vec();
        if v.last() != Some(&b'/') {
            v.push(b'/');
        }
        v.extend_from_slice(path2);
        v
    } else {
        path2.to_vec()
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
}
