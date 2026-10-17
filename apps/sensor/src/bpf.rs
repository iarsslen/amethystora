//! Loading the BPF object: patch the keys it should run for into its read-only data, load only the programs
//! the enabled keys need, tell it its own pid, record its programs' ids for the tamper check, and attach.
//! The object is embedded, built by build.rs, and loaded from memory, so the binary needs no skeleton and
//! no second copy of libbpf.

use std::ffi::OsStr;
use std::os::fd::AsFd;

use libbpf_rs::{Link, MapCore, MapFlags, Object, ObjectBuilder, Program};

use crate::keys;

/// The compiled BPF object, built by build.rs against the kernel's types (CO-RE).
static OBJECT: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/sensor.bpf.o"));

/// The programs that are only loaded when a group of keys is on, by their C function names. file_open is
/// always loaded (registration learns each folder's inode through it); the two tamper programs always are.
fn required_mask(prog: &str) -> u32 {
    match prog {
        "file_open" | "task_kill" | "bpf_call" => u32::MAX,
        "open_refused" => keys::WRITE_KEYS | keys::READ_KEYS,
        "vfs_unlink_exit" | "vfs_rmdir_exit" | "vfs_mkdir_exit" | "vfs_mknod_exit" | "vfs_symlink_exit"
        | "vfs_link_exit" | "vfs_rename_entry" | "vfs_rename_exit" | "notify_change_exit" | "vfs_truncate_exit"
        | "vfs_setxattr_exit" | "vfs_removexattr_exit" | "vfs_set_acl_exit" | "vfs_remove_acl_exit" => keys::WRITE_KEYS,
        "bprm_check" | "process_exec" => keys::EXEC_KEYS,
        "module_file" | "module_loaded" | "finit_module_exit" | "init_module_exit" | "delete_module_exit" => {
            keys::MODULES_BIT
        }
        // An unknown name: load it, so a program added later is not silently left off.
        _ => u32::MAX,
    }
}

/// A loaded, attached object. The links keep the programs attached while this is alive; dropping it detaches
/// everything and the sensor stops.
pub struct Loaded {
    pub object: Object,
    _links: Vec<Link>,
}

fn name_is(name: &OsStr, needle: &str) -> bool {
    name.to_str().map(|s| s.contains(needle)).unwrap_or(false)
}

/// Opens the object, runs only the programs the enabled keys need (every one when probing), loads and
/// attaches it, and records its own pid and program ids.
pub fn load(enabled_keys: u32, probe: bool) -> libbpf_rs::Result<Loaded> {
    let mut open = ObjectBuilder::default().open_memory(OBJECT)?;

    // The keys it runs for, into .rodata, before load: a key that is off leaves its code out, pruned by the
    // verifier. Its own pid goes into .bss the same way, so no window exists where it does not know itself.
    let self_tgid = std::process::id();
    for mut map in open.maps_mut() {
        if name_is(map.name(), "rodata") {
            if let Some(buf) = map.initial_value_mut() {
                if buf.len() >= 4 {
                    buf[0..4].copy_from_slice(&enabled_keys.to_ne_bytes());
                }
            }
        } else if name_is(map.name(), "bss") {
            if let Some(buf) = map.initial_value_mut() {
                if buf.len() >= 4 {
                    buf[0..4].copy_from_slice(&self_tgid.to_ne_bytes());
                }
            }
        }
    }

    // Load only the programs the keys need; probing loads them all, to see the kernel takes every one.
    for mut prog in open.progs_mut() {
        let name = prog.name().to_str().unwrap_or("").to_string();
        let mask = required_mask(&name);
        let wanted = probe || mask == u32::MAX || (mask & enabled_keys) != 0;
        prog.set_autoload(wanted);
    }

    let object = open.load()?;

    // Record the sensor's own program ids, which the bpf() tamper check compares a detach or replace against.
    // A program that was not loaded (its key off) has no fd, so id_from_fd fails and it is skipped.
    if let Some(own) = object.maps().find(|m| name_is(m.name(), "own_progs")) {
        for prog in object.progs() {
            if let Ok(id) = Program::id_from_fd(prog.as_fd()) {
                if id != 0 {
                    let _ = own.update(&id.to_ne_bytes(), &[1u8], MapFlags::ANY);
                }
            }
        }
    }

    // Attach every program that was loaded. A program left out (its key off) is not loaded and attach would
    // fail for it, so those are skipped unless we are probing, where every program must take.
    let mut links = Vec::new();
    for prog in object.progs_mut() {
        match prog.attach() {
            Ok(link) => links.push(link),
            Err(e) => {
                if probe {
                    return Err(e);
                }
            }
        }
    }

    Ok(Loaded { object, _links: links })
}
