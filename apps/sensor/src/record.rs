//! Writing an operation as the kernel's own audit records, so that the watcher's ausearch reads it exactly
//! as it reads what auditd logs. Nothing here decides a verb or a sentence: it writes faithful SYSCALL,
//! CWD, PATH, EXECVE, KERN_MODULE, OBJ_PID and EOE records, and ausearch does the interpreting. That is the
//! whole point of the format — the findings keep their shape by construction (PLAN-audit-cost.md section 4.4).
//! OBJ_PID carries two fields audit's own does not, the mount namespaces of the target (omnt) and of the
//! acting task (mnt), which ausearch passes on as they are.

use std::io::{self, Write};

use crate::event::*;
use crate::keys;

/// One operation to write out, with who did it and what it touched, already resolved to real paths. The run
/// loop builds this from a ring-buffer event and the folders it has open; `--records` builds it from JSON.
#[derive(Default)]
pub struct Record {
    pub op: u32,
    pub syscall: u32,
    pub result: i64,
    pub keys: u32,
    pub args: [u64; 4],
    pub pid: u32,
    pub ppid: u32,
    pub auid: u32,
    pub ses: u32,
    pub uid: u32,
    pub gid: u32,
    pub euid: u32,
    pub suid: u32,
    pub fsuid: u32,
    pub egid: u32,
    pub sgid: u32,
    pub fsgid: u32,
    pub comm: Vec<u8>,
    pub tty: Vec<u8>,
    pub exe: Vec<u8>,
    pub cwd: Vec<u8>,
    pub flags: u32,
    pub obj_mode: u32,
    pub obj_ino: u64,
    pub obj_ouid: u32,
    pub obj_ogid: u32,
    pub obj_dev: String,
    pub obj_rdev: String,
    pub parent_mode: u32,
    pub dir: Vec<u8>,
    pub name: Vec<u8>,
    pub dir2: Vec<u8>,
    pub name2: Vec<u8>,
    pub path2: Vec<u8>,
    pub argv: Vec<Vec<u8>>,
    pub argc: u32,
    pub module: Vec<u8>,
    /// The process whose memory was reached (SOP_MEMORY): its pid, login uid, uid, name and mount namespace,
    /// and the acting task's mount namespace beside it
    pub target: u32,
    pub target_auid: u32,
    pub target_uid: u32,
    pub target_comm: Vec<u8>,
    pub target_mnt: u32,
    pub own_mnt: u32,
    /// Wall-clock time of the event, in nanoseconds since the epoch.
    pub time_ns: u128,
}

struct PathItem {
    name: Vec<u8>,
    nametype: &'static str,
    mode: u32,
    object: bool,
}

/// A string as the kernel writes an untrusted one: quoted when every byte is printable ASCII and not a
/// quote, hex otherwise. This is audit_string_contains_control's rule, which is what ausearch decodes by.
fn enc(out: &mut Vec<u8>, prefix: &str, bytes: &[u8]) {
    out.extend_from_slice(prefix.as_bytes());
    out.push(b'=');
    let special = bytes.iter().any(|&b| b == b'"' || b < 0x21 || b > 0x7e);
    if special {
        for &b in bytes {
            out.extend_from_slice(format!("{b:02X}").as_bytes());
        }
    } else {
        out.push(b'"');
        out.extend_from_slice(bytes);
        out.push(b'"');
    }
}

fn parent_name(dir: &[u8]) -> Vec<u8> {
    let mut v = dir.to_vec();
    v.push(b'/');
    v
}

fn child(dir: &[u8], name: &[u8]) -> Vec<u8> {
    let mut v = dir.to_vec();
    v.push(b'/');
    v.extend_from_slice(name);
    v
}

/// A path the kernel recorded as the caller gave it: absolute as it is, else joined with the working folder,
/// the way the watcher joins PATH item 0 with CWD.
fn absolute(path2: &[u8], cwd: &[u8]) -> Vec<u8> {
    if path2.first() == Some(&b'/') || cwd.is_empty() {
        path2.to_vec()
    } else {
        child(cwd, path2)
    }
}

/// The object's path for an operation on a single named thing: in the folder the daemon knows, else as the
/// caller gave it.
fn object_path(r: &Record) -> Vec<u8> {
    if r.dir.is_empty() {
        absolute(&r.path2, &r.cwd)
    } else {
        child(&r.dir, &r.name)
    }
}

/// The PATH items for the operation, in the kernel's order.
fn path_items(r: &Record) -> Vec<PathItem> {
    let obj = |name: Vec<u8>, nt: &'static str, mode: u32| PathItem { name, nametype: nt, mode, object: true };
    let dir_item = |dir: &[u8], nt: &'static str, mode: u32| PathItem { name: dir.to_vec(), nametype: nt, mode, object: false };
    match r.op {
        SOP_OPEN => {
            if r.flags & SOPEN_INPUT != 0 {
                vec![obj(if r.path2.is_empty() { object_path(r) } else { r.path2.clone() }, "NORMAL", r.obj_mode)]
            } else if r.flags & SOPEN_REFUSED != 0 {
                vec![obj(absolute(&r.path2, &r.cwd), "NORMAL", 0)]
            } else if r.flags & SOPEN_CREATED != 0 {
                vec![dir_item(&parent_name(&r.dir), "PARENT", r.parent_mode), obj(child(&r.dir, &r.name), "CREATE", r.obj_mode)]
            } else {
                vec![obj(object_path(r), "NORMAL", r.obj_mode)]
            }
        }
        SOP_UNLINK | SOP_RMDIR => {
            vec![dir_item(&parent_name(&r.dir), "PARENT", r.parent_mode), obj(child(&r.dir, &r.name), "DELETE", r.obj_mode)]
        }
        SOP_MKDIR | SOP_MKNOD | SOP_SYMLINK => {
            vec![dir_item(&parent_name(&r.dir), "PARENT", r.parent_mode), obj(child(&r.dir, &r.name), "CREATE", r.obj_mode)]
        }
        SOP_LINK => {
            let old = if r.dir2.is_empty() { absolute(&r.path2, &r.cwd) } else { child(&r.dir2, &r.name2) };
            let mut items = vec![PathItem { name: old, nametype: "UNKNOWN", mode: 0, object: false }];
            if r.dir.is_empty() {
                items.push(obj(absolute(&r.path2, &r.cwd), "CREATE", r.obj_mode));
            } else {
                items.push(dir_item(&parent_name(&r.dir), "PARENT", r.parent_mode));
                items.push(obj(child(&r.dir, &r.name), "CREATE", r.obj_mode));
            }
            items
        }
        SOP_RENAME => {
            let old = if r.dir.is_empty() { absolute(&r.path2, &r.cwd) } else { child(&r.dir, &r.name) };
            let new = if r.dir2.is_empty() { absolute(&r.path2, &r.cwd) } else { child(&r.dir2, &r.name2) };
            let mut items = Vec::new();
            if !r.dir.is_empty() {
                items.push(dir_item(&parent_name(&r.dir), "PARENT", r.parent_mode));
            }
            if !r.dir2.is_empty() {
                items.push(dir_item(&parent_name(&r.dir2), "PARENT", r.parent_mode));
            }
            items.push(PathItem { name: old, nametype: "DELETE", mode: r.obj_mode, object: true });
            items.push(PathItem { name: new, nametype: "CREATE", mode: r.obj_mode, object: true });
            items
        }
        SOP_SETATTR | SOP_TRUNCATE | SOP_SETXATTR | SOP_REMOVEXATTR | SOP_SET_ACL | SOP_REMOVE_ACL => {
            vec![obj(object_path(r), "NORMAL", r.obj_mode)]
        }
        SOP_EXEC => vec![obj(if r.path2.is_empty() { object_path(r) } else { r.path2.clone() }, "NORMAL", r.obj_mode)],
        // The program of the process whose memory was reached, as the one thing it touched
        SOP_MEMORY => vec![obj(r.path2.clone(), "UNKNOWN", 0)],
        // Modules carry a KERN_MODULE record instead of a PATH, and the tamper events (kill, bpf) no path.
        SOP_MODULE_LOAD | SOP_MODULE_DELETE | SOP_KILL | SOP_BPF => Vec::new(),
        _ => Vec::new(),
    }
}

/// Writes the operation as one audit event ending in EOE, with the given serial number.
pub fn write_event(out: &mut impl Write, r: &Record, serial: u64) -> io::Result<()> {
    let sec = (r.time_ns / 1_000_000_000) as u64;
    let ms = ((r.time_ns % 1_000_000_000) / 1_000_000) as u64;
    let id = format!("{sec}.{ms:03}:{serial}");
    let items = path_items(r);
    let success = if r.result >= 0 { "yes" } else { "no" };

    // SYSCALL: who did it, in which call, with its first four arguments as the kernel records them.
    let mut line = Vec::new();
    line.extend_from_slice(
        format!(
            "type=SYSCALL msg=audit({id}): arch=c000003e syscall={} success={success} exit={} \
a0={:x} a1={:x} a2={:x} a3={:x} items={} ppid={} pid={} auid={} uid={} gid={} euid={} suid={} fsuid={} \
egid={} sgid={} fsgid={} tty=",
            r.syscall, r.result, r.args[0], r.args[1], r.args[2], r.args[3], items.len(), r.ppid, r.pid,
            r.auid, r.uid, r.gid, r.euid, r.suid, r.fsuid, r.egid, r.sgid, r.fsgid,
        )
        .as_bytes(),
    );
    // tty is written plain, control bytes dropped, as audit writes it.
    for &b in &r.tty {
        if (0x21..=0x7e).contains(&b) {
            line.push(b);
        }
    }
    if r.tty.is_empty() {
        line.extend_from_slice(b"(none)");
    }
    line.extend_from_slice(format!(" ses={} ", r.ses).as_bytes());
    enc(&mut line, "comm", &r.comm);
    line.push(b' ');
    enc(&mut line, "exe", &r.exe);
    line.extend_from_slice(b" subj=? ");
    let key_names = keys::names_of(r.keys);
    enc(&mut line, "key", key_names.join("\x01").as_bytes());
    line.push(b'\n');
    out.write_all(&line)?;

    // The program's arguments, for an exec that ran; a refused one has none, as audit writes it.
    if r.op == SOP_EXEC && r.result >= 0 {
        let mut ex = Vec::new();
        ex.extend_from_slice(format!("type=EXECVE msg=audit({id}): argc={}", r.argc).as_bytes());
        for (i, arg) in r.argv.iter().enumerate() {
            ex.push(b' ');
            enc(&mut ex, &format!("a{i}"), arg);
        }
        ex.push(b'\n');
        out.write_all(&ex)?;
    }

    // The process whose memory was reached, as audit writes one a ptrace attach reached
    if r.op == SOP_MEMORY {
        let mut obj = Vec::new();
        obj.extend_from_slice(
            format!(
                "type=OBJ_PID msg=audit({id}): opid={} oauid={} ouid={} oses=-1 obj=? ",
                r.target, r.target_auid as i32, r.target_uid
            )
            .as_bytes(),
        );
        enc(&mut obj, "ocomm", &r.target_comm);
        obj.extend_from_slice(format!(" omnt={} mnt={}\n", r.target_mnt, r.own_mnt).as_bytes());
        out.write_all(&obj)?;
    }

    // The module's name, for a load or an unload.
    if r.op == SOP_MODULE_LOAD || r.op == SOP_MODULE_DELETE {
        let mut km = Vec::new();
        km.extend_from_slice(format!("type=KERN_MODULE msg=audit({id}): ").as_bytes());
        enc(&mut km, "name", &r.module);
        km.push(b'\n');
        out.write_all(&km)?;
    }

    // The working folder, which the watcher joins a relative path with.
    let mut cwd = Vec::new();
    cwd.extend_from_slice(format!("type=CWD msg=audit({id}): ").as_bytes());
    enc(&mut cwd, "cwd", if r.cwd.is_empty() { b"/" } else { &r.cwd });
    cwd.push(b'\n');
    out.write_all(&cwd)?;

    // The paths it touched, in the kernel's order.
    for (i, item) in items.iter().enumerate() {
        let mut path = Vec::new();
        path.extend_from_slice(format!("type=PATH msg=audit({id}): item={i} ").as_bytes());
        enc(&mut path, "name", &item.name);
        let (ino, dev, ouid, ogid, rdev) = if item.object {
            (r.obj_ino, r.obj_dev.as_str(), r.obj_ouid, r.obj_ogid, r.obj_rdev.as_str())
        } else {
            (0, r.obj_dev.as_str(), 0, 0, "00:00")
        };
        path.extend_from_slice(
            format!(
                " inode={ino} dev={dev} mode=0{:o} ouid={ouid} ogid={ogid} rdev={rdev} nametype={}",
                item.mode, item.nametype
            )
            .as_bytes(),
        );
        path.push(b'\n');
        out.write_all(&path)?;
    }

    // The end of the event: ausearch holds the last event back until it sees this or a later one.
    out.write_all(format!("type=EOE msg=audit({id}): \n").as_bytes())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn written(r: &Record) -> String {
        let mut out = Vec::new();
        write_event(&mut out, r, 7).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn encodes_plain_and_special() {
        let mut out = Vec::new();
        enc(&mut out, "name", b"/etc/passwd");
        assert_eq!(out, b"name=\"/etc/passwd\"");
        let mut out = Vec::new();
        enc(&mut out, "name", b"a file");
        assert_eq!(out, b"name=612066696C65"); // a space forces hex, as the kernel does
    }

    #[test]
    fn created_file_has_parent_then_create() {
        let r = Record {
            op: SOP_OPEN,
            syscall: 257,
            flags: SOPEN_CREATED,
            keys: 1 << 1, // privilege
            dir: b"/etc/sudoers.d".to_vec(),
            name: b"x".to_vec(),
            obj_mode: 0o100644,
            parent_mode: 0o040750,
            exe: b"/usr/bin/tee".to_vec(),
            obj_dev: "00:2a".into(),
            obj_rdev: "00:00".into(),
            ..Default::default()
        };
        let text = written(&r);
        assert!(text.contains("key=\"privilege\""), "{text}");
        assert!(text.contains("items=2"));
        assert!(text.contains("name=\"/etc/sudoers.d/\" inode=0 dev=00:2a mode=040750"));
        assert!(text.contains("nametype=PARENT"));
        assert!(text.contains("name=\"/etc/sudoers.d/x\""));
        assert!(text.contains("nametype=CREATE"));
        assert!(text.contains("type=EOE msg=audit(0.000:7):"));
    }

    #[test]
    fn module_has_kern_module_and_no_path() {
        let r = Record {
            op: SOP_MODULE_LOAD,
            syscall: 313,
            keys: 1 << 4, // modules
            module: b"v4l2loopback".to_vec(),
            exe: b"/usr/bin/kmod".to_vec(),
            ..Default::default()
        };
        let text = written(&r);
        assert!(text.contains("type=KERN_MODULE msg=audit(0.000:7): name=\"v4l2loopback\""));
        assert!(text.contains("items=0"));
        assert!(!text.contains("type=PATH"));
    }

    #[test]
    fn memory_has_the_target_and_its_program() {
        let r = Record {
            op: SOP_MEMORY,
            syscall: 311, // process_vm_writev
            result: -1,
            keys: 1 << 11, // injection
            args: [0x4d2, 0, 0, 0],
            target: 1234,
            target_auid: 1000,
            target_uid: 1000,
            target_comm: b"sleep".to_vec(),
            target_mnt: 4026531841,
            own_mnt: 4026531841,
            path2: b"/usr/bin/sleep".to_vec(),
            exe: b"/tmp/x".to_vec(),
            obj_dev: "00:00".into(),
            obj_rdev: "00:00".into(),
            ..Default::default()
        };
        let text = written(&r);
        assert!(text.contains("syscall=311 success=no exit=-1 a0=4d2"), "{text}");
        assert!(text.contains("key=\"injection\""), "{text}");
        assert!(text.contains("type=OBJ_PID msg=audit(0.000:7): opid=1234 oauid=1000 ouid=1000 oses=-1 obj=? ocomm=\"sleep\" omnt=4026531841 mnt=4026531841"), "{text}");
        assert!(text.contains("item=0 name=\"/usr/bin/sleep\""), "{text}");
        assert!(text.contains("nametype=UNKNOWN"), "{text}");
    }

    #[test]
    fn two_keys_are_joined_and_hex() {
        let r = Record { op: SOP_OPEN, syscall: 257, keys: (1 << 0) | (1 << 3), ..Default::default() };
        // identity\x01hardening, hex-encoded because of the separator byte
        let text = written(&r);
        assert!(text.contains("key=6964656E746974790168617264656E696E67"), "{text}");
    }
}
