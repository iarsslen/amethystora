//! Loading the BPF object: patch the keys it should run for into its read-only data, load only the programs
//! the enabled keys need, tell it its own pid, record its programs' ids for the tamper check, and attach.
//! The object is embedded, built by build.rs, and loaded from memory, so the binary needs no skeleton and
//! no second copy of libbpf.

use std::ffi::OsStr;
use std::os::fd::AsFd;

use libbpf_rs::btf::types;
use libbpf_rs::{Btf, Link, MapCore, MapFlags, Object, ObjectBuilder, Program};

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
        "file_open_input" => keys::INPUT_BIT,
        "bprm_check" | "process_exec" | "execve_exit" | "execveat_exit" => keys::EXEC_KEYS,
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
pub fn load(enabled_keys: u32, probe: bool) -> Result<Loaded, Box<dyn std::error::Error>> {
    let mut open = ObjectBuilder::default().open_memory(OBJECT)?;

    // The DAC-refused-open hook's kernel function is named do_file_open on the image's kernel and
    // do_filp_open on mainline; point the program at whichever this kernel's BTF has, and skip it if
    // neither (the rest of the sensor still loads, only pre-DAC refusals go unrecorded). The vmlinux BTF
    // this reads is large, so it is dropped before load(), which loads its own copy for CO-RE: the two
    // peaks do not then overlap.
    let open_target: Option<String> = {
        let vmlinux = Btf::from_vmlinux().ok();
        let has_func = |name: &str| vmlinux.as_ref().and_then(|b| b.type_by_name::<types::Func<'_>>(name)).is_some();
        ["do_file_open", "do_filp_open"].into_iter().find(|n| has_func(n)).map(String::from)
    };

    // The keys it runs for, into .rodata, before load: a key that is off leaves its code out, pruned by the
    // verifier. Its own pid goes into .bss the same way, so no window exists where it does not know itself.
    // Both must take, or the sensor would run blind (no keys) or not recognise its own opens (no pid), so a
    // failure here is fatal rather than a silent no-op.
    let self_tgid = std::process::id();
    let mut set_rodata = false;
    let mut set_bss = false;
    for mut map in open.maps_mut() {
        if name_is(map.name(), "rodata") {
            if let Some(buf) = map.initial_value_mut() {
                if buf.len() >= 4 {
                    buf[0..4].copy_from_slice(&enabled_keys.to_ne_bytes());
                    set_rodata = true;
                }
            }
        } else if name_is(map.name(), "bss") {
            if let Some(buf) = map.initial_value_mut() {
                if buf.len() >= 4 {
                    buf[0..4].copy_from_slice(&self_tgid.to_ne_bytes());
                    set_bss = true;
                }
            }
        }
    }
    if !set_rodata || !set_bss {
        return Err(format!("could not set the sensor's keys/pid (rodata={set_rodata}, bss={set_bss})").into());
    }

    // Load only the programs the keys need; probing loads them all, to see the kernel takes every one.
    for mut prog in open.progs_mut() {
        let name = prog.name().to_str().unwrap_or("").to_string();
        let mask = required_mask(&name);
        let mut wanted = probe || mask == u32::MAX || (mask & enabled_keys) != 0;
        // Point the refused-open program at this kernel's function name, or skip it if it has neither.
        if name == "open_refused" {
            match &open_target {
                Some(target) if prog.set_attach_target(0, Some(target.clone())).is_ok() => {}
                _ => wanted = false,
            }
        }
        prog.set_autoload(wanted);
    }

    let object = open.load()?;

    // Record the sensor's own program ids, which the bpf() tamper check compares a detach or replace against.
    // Only loaded programs (autoload on) have an fd and an id; an off key's programs are skipped, so
    // id_from_fd is never asked about an unloaded program.
    if let Some(own) = object.maps().find(|m| name_is(m.name(), "own_progs")) {
        for prog in object.progs() {
            if !prog.autoload() {
                continue;
            }
            if let Ok(id) = Program::id_from_fd(prog.as_fd()) {
                if id != 0 {
                    let _ = own.update(&id.to_ne_bytes(), &[1u8], MapFlags::ANY);
                }
            }
        }
    }

    // Attach every program that was loaded (autoload on). Probing requires each to take; in the run path a
    // failure drops that program's coverage, so it is logged rather than swallowed.
    let mut links = Vec::new();
    for prog in object.progs_mut() {
        if !prog.autoload() {
            continue;
        }
        let name = prog.name().to_str().unwrap_or("?").to_string();
        match prog.attach() {
            Ok(link) => links.push(link),
            Err(e) => {
                if probe {
                    return Err(e.into());
                }
                eprintln!("amethystora-sensor: {name} did not attach, its coverage is lost: {e}");
            }
        }
    }

    Ok(Loaded { object, _links: links })
}
