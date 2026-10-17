//! The fixed head of a ring-buffer event, field for field as `struct sensor_event` in src/bpf/sensor.h,
//! and how to read the strings that follow it. The kernel side writes it; here it is read back.

/// Operations, matching `enum sensor_op`.
pub const SOP_OPEN: u32 = 1;
pub const SOP_UNLINK: u32 = 2;
pub const SOP_RMDIR: u32 = 3;
pub const SOP_MKDIR: u32 = 4;
pub const SOP_MKNOD: u32 = 5;
pub const SOP_SYMLINK: u32 = 6;
pub const SOP_LINK: u32 = 7;
pub const SOP_RENAME: u32 = 8;
pub const SOP_SETATTR: u32 = 9;
pub const SOP_TRUNCATE: u32 = 10;
pub const SOP_SETXATTR: u32 = 11;
pub const SOP_REMOVEXATTR: u32 = 12;
pub const SOP_SET_ACL: u32 = 13;
pub const SOP_REMOVE_ACL: u32 = 14;
pub const SOP_MODULE_LOAD: u32 = 15;
pub const SOP_MODULE_DELETE: u32 = 16;
pub const SOP_EXEC: u32 = 17;
pub const SOP_KILL: u32 = 18;
pub const SOP_BPF: u32 = 19;

/// The strings in an event's data, in order, each NUL-terminated (`enum sensor_string`).
pub const SSTR_NAME: usize = 0;
pub const SSTR_NAME2: usize = 1;
pub const SSTR_EXE: usize = 2;
pub const SSTR_CWD: usize = 3;
pub const SSTR_PATH2: usize = 4;
pub const SSTR_ARGV: usize = 5;
pub const SSTR_COUNT: usize = 6;

/// Flags of SOP_OPEN, besides the open's own f_flags.
pub const SOPEN_CREATED: u32 = 0x8000_0000;
pub const SOPEN_REFUSED: u32 = 0x4000_0000;
pub const SOPEN_INPUT: u32 = 0x2000_0000;
/// Set by the BPF side on a read rather than a write; the record reads the same either way, so userspace
/// does not branch on it. Kept so the flag's meaning stays defined beside the others.
#[allow(dead_code)]
pub const SOPEN_READ: u32 = 0x0800_0000;

/// Everything of an event before its string data, laid out exactly as the kernel wrote it. The `header`
/// field is the kernel's offsetof(data), which is where the strings begin and which the daemon checks.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct EventHeader {
    pub header: u32,
    pub op: u32,
    pub time: u64,
    pub args: [u64; 4],
    pub ino: u64,
    pub result: i32,
    pub keys: u32,
    pub syscall: u32,
    pub dir: u32,
    pub dir2: u32,
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
    pub mode: u32,
    pub ouid: u32,
    pub ogid: u32,
    pub dev: u32,
    pub rdev: u32,
    pub flags: u32,
    pub attr_mode: u32,
    pub attr_uid: u32,
    pub attr_gid: u32,
    pub argc: u32,
    pub parent_mode: u32,
    pub len: [u16; SSTR_COUNT],
    pub comm: [u8; 16],
    pub tty: [u8; 64],
}

/// Where the strings begin: the kernel's offsetof(struct sensor_event, data). The Rust struct rounds its
/// size up to its 8-byte alignment (264), but the data in the byte stream starts at 260, which is what the
/// kernel puts in `header` and what this must equal.
pub const DATA_OFFSET: usize = 260;

// The layout has to match the kernel's, or every field is read wrong.
const _: () = assert!(core::mem::offset_of!(EventHeader, len) == 168);
const _: () = assert!(core::mem::offset_of!(EventHeader, comm) == 180);
const _: () = assert!(core::mem::offset_of!(EventHeader, tty) == 196);
const _: () = assert!(core::mem::size_of::<EventHeader>() == 264);

/// An event read from the ring buffer: its head, and the six strings as byte slices into the record.
pub struct Event<'a> {
    pub head: EventHeader,
    pub strings: [&'a [u8]; SSTR_COUNT],
}

impl<'a> Event<'a> {
    /// Reads one ring-buffer record. None when it is too short or its header is not the sensor's own.
    pub fn parse(bytes: &'a [u8]) -> Option<Event<'a>> {
        if bytes.len() < DATA_OFFSET {
            return None;
        }
        // The record is 8-aligned in the ring buffer, but read unaligned to be safe either way.
        let head: EventHeader = unsafe { core::ptr::read_unaligned(bytes.as_ptr() as *const EventHeader) };
        if head.header as usize != DATA_OFFSET {
            return None;
        }
        let data = &bytes[DATA_OFFSET..];
        let mut strings: [&[u8]; SSTR_COUNT] = [b""; SSTR_COUNT];
        let mut pos = 0usize;
        for slot in 0..SSTR_COUNT {
            let len = head.len[slot] as usize;
            if pos + len > data.len() {
                return None;
            }
            strings[slot] = &data[pos..pos + len];
            // Each string is followed by its NUL, which the kernel always wrote.
            pos += len + 1;
            if pos > data.len() {
                pos = data.len();
            }
        }
        Some(Event { head, strings })
    }
}
