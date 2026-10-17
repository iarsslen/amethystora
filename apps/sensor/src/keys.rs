//! The audit keys the sensor covers, as bits, in amethystora-security-watch's AUDIT_KEYS order. The same
//! order and names as `enum sensor_key` in src/bpf/sensor.h: event.rs and the BPF object agree on the bits.

/// A switchable key and the bit the BPF object uses for it.
pub struct Key {
    pub name: &'static str,
    pub bit: u32,
}

/// The eleven keys a user can switch, which the sensor can take from auditd, in AUDIT_KEYS order.
pub const KEYS: [Key; 11] = [
    Key { name: "identity", bit: 0 },
    Key { name: "privilege", bit: 1 },
    Key { name: "persistence", bit: 2 },
    Key { name: "hardening", bit: 3 },
    Key { name: "modules", bit: 4 },
    Key { name: "input-capture", bit: 5 },
    Key { name: "user-programs", bit: 6 },
    Key { name: "exec-watch", bit: 7 },
    Key { name: "agent-clis", bit: 8 },
    Key { name: "credentials", bit: 9 },
    Key { name: "decoy", bit: 10 },
];

/// Not a switch: what was done to the sensor itself, recorded under its own key while it runs.
pub const SENSOR_BIT: u32 = 15;
pub const SENSOR_NAME: &str = "sensor";

/// The keys that watch writes and attribute changes to folders and files (`-w ... -p wa`), the same as
/// WRITE_KEYS in src/bpf/sensor.h.
pub const WRITE_KEYS: u32 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 6);
/// ...and reads of files (credentials, decoy).
pub const READ_KEYS: u32 = (1 << 9) | (1 << 10);
/// ...and programs run from a watched folder (exec-watch, agent-clis).
pub const EXEC_KEYS: u32 = (1 << 7) | (1 << 8);
/// ...opening an input device. The BPF side gates on this bit itself; file_open is always loaded, so the
/// daemon needs no separate autoload rule for it, but the bit is named here beside the rest.
#[allow(dead_code)]
pub const INPUT_BIT: u32 = 1 << 5;
/// ...loading or removing a kernel module.
pub const MODULES_BIT: u32 = 1 << 4;

/// The key's bit, or None for a name the sensor does not know.
pub fn bit_of(name: &str) -> Option<u32> {
    KEYS.iter().find(|k| k.name == name).map(|k| k.bit)
}

/// The names of the keys a bitmask holds, in KEYS order, the sensor's own key last.
pub fn names_of(mask: u32) -> Vec<&'static str> {
    let mut names: Vec<&'static str> = KEYS.iter().filter(|k| mask & (1 << k.bit) != 0).map(|k| k.name).collect();
    if mask & (1 << SENSOR_BIT) != 0 {
        names.push(SENSOR_NAME);
    }
    names
}
