//! The generator's two files under /run/amethystora/sensor, read by the daemon:
//!   - `plan`: one line per wanted key, `KEY sensor` or `KEY audit`. The keys marked sensor are the ones
//!     the daemon loads programs for; the rest stay on auditd's rules.
//!   - `watch.list`: the folders and files to register, one `KIND KEY PATH` a line, from the same shipped
//!     *.rules the audit generator uses, so the rules remain the single source of what is watched.

use std::fs;
use std::path::PathBuf;

use crate::keys;

/// The run directory, which the generator writes and the daemon reads. Overridable for the tests.
pub fn run_dir() -> PathBuf {
    PathBuf::from(std::env::var("AMETHYSTORA_SENSOR_RUN").unwrap_or_else(|_| "/run/amethystora/sensor".to_string()))
}

/// The keys the plan gives to the sensor, as a bitmask in the BPF object's bits.
pub fn sensor_keys() -> u32 {
    let mut mask = 0;
    let Ok(text) = fs::read_to_string(run_dir().join("plan")) else {
        return 0;
    };
    for line in text.lines() {
        let mut parts = line.split_whitespace();
        let (Some(name), Some(where_)) = (parts.next(), parts.next()) else {
            continue;
        };
        if where_ == "sensor" {
            if let Some(bit) = keys::bit_of(name) {
                mask |= 1 << bit;
            }
        }
    }
    mask
}

/// Whether the plan gives the sensor at least one key.
pub fn any_sensor_key() -> bool {
    sensor_keys() != 0
}

/// What a watch.list line asks the daemon to register.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    /// A folder and every folder below it, for writes (`-w DIR/`).
    Tree,
    /// A single file, by its folder and name, for writes (`-w FILE`).
    File,
    /// A folder tree for reads (credentials, decoy).
    ReadTree,
    /// A single file for reads.
    ReadFile,
    /// The root a program is watched being run from (`-F dir=` on execve).
    ExecTree,
}

impl Kind {
    fn parse(s: &str) -> Option<Kind> {
        Some(match s {
            "tree" => Kind::Tree,
            "file" => Kind::File,
            "read-tree" => Kind::ReadTree,
            "read-file" => Kind::ReadFile,
            "exec-tree" => Kind::ExecTree,
            _ => return None,
        })
    }
}

pub struct Watch {
    pub kind: Kind,
    pub key_bit: u32,
    pub path: PathBuf,
}

/// The watches the generator wrote, for the keys the sensor covers. A line for an unknown key or kind is
/// skipped.
pub fn watches(sensor_keys: u32) -> Vec<Watch> {
    let mut list = Vec::new();
    let Ok(text) = fs::read_to_string(run_dir().join("watch.list")) else {
        return list;
    };
    for line in text.lines() {
        let line = line.trim_end_matches('\n');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        // KIND KEY PATH, where PATH is the rest of the line and may hold a space (a credential file).
        let mut it = line.splitn(3, ' ');
        let (Some(kind), Some(key), Some(path)) = (it.next(), it.next(), it.next()) else {
            continue;
        };
        let (Some(kind), Some(bit)) = (Kind::parse(kind), keys::bit_of(key)) else {
            continue;
        };
        if sensor_keys & (1 << bit) == 0 {
            continue;
        }
        list.push(Watch { kind, key_bit: bit, path: PathBuf::from(path) });
    }
    list
}
