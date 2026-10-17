/* SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause) */
/*
 * What the kernel side of amethystora-sensor and its daemon share: the keys, the operations, what the maps hold
 * and the event each recorded operation becomes. src/event.rs mirrors these field for field (#[repr(C)]), and
 * checks the header's size, which every event carries, against its own.
 */
#ifndef AMETHYSTORA_SENSOR_H
#define AMETHYSTORA_SENSOR_H

/* The audit keys, in amethystora-security-watch's AUDIT_KEYS order, as bits */
enum sensor_key {
	SKEY_IDENTITY = 0,
	SKEY_PRIVILEGE = 1,
	SKEY_PERSISTENCE = 2,
	SKEY_HARDENING = 3,
	SKEY_MODULES = 4,
	SKEY_INPUT_CAPTURE = 5,
	SKEY_USER_PROGRAMS = 6,
	SKEY_EXEC_WATCH = 7,
	SKEY_AGENT_CLIS = 8,
	SKEY_CREDENTIALS = 9,
	SKEY_DECOY = 10,
	/* Not a switch: what was done to the sensor itself, always recorded while it runs */
	SKEY_SENSOR = 15,
};

/* The keys whose rules record only what a login did (auid>=1000 -F auid!=unset) */
#define LOGIN_KEYS                                                                                 \
	((1 << SKEY_MODULES) | (1 << SKEY_INPUT_CAPTURE) | (1 << SKEY_EXEC_WATCH) | (1 << SKEY_AGENT_CLIS) | \
	 (1 << SKEY_CREDENTIALS) | (1 << SKEY_DECOY))
/* ...and the keys that watch writes and attribute changes to folders and files (-w ... -p wa) */
#define WRITE_KEYS                                                                                \
	((1 << SKEY_IDENTITY) | (1 << SKEY_PRIVILEGE) | (1 << SKEY_PERSISTENCE) | (1 << SKEY_HARDENING) | \
	 (1 << SKEY_USER_PROGRAMS))
#define READ_KEYS ((1 << SKEY_CREDENTIALS) | (1 << SKEY_DECOY))
#define EXEC_KEYS ((1 << SKEY_EXEC_WATCH) | (1 << SKEY_AGENT_CLIS))

enum sensor_op {
	SOP_OPEN = 1,     /* opened for writing, created, truncated or read; or an input device opened */
	SOP_UNLINK = 2,
	SOP_RMDIR = 3,
	SOP_MKDIR = 4,
	SOP_MKNOD = 5,
	SOP_SYMLINK = 6,
	SOP_LINK = 7,
	SOP_RENAME = 8,
	SOP_SETATTR = 9,  /* mode, owner, times or size: flags holds ia_valid */
	SOP_TRUNCATE = 10,
	SOP_SETXATTR = 11,
	SOP_REMOVEXATTR = 12,
	SOP_SET_ACL = 13,
	SOP_REMOVE_ACL = 14,
	SOP_MODULE_LOAD = 15,
	SOP_MODULE_DELETE = 16,
	SOP_EXEC = 17,
	SOP_KILL = 18,    /* a signal sent to the sensor: flags holds it */
	SOP_BPF = 19,     /* one of the sensor's links detached or replaced: flags holds the bpf() command */
};

/* The folders the maps hold, by the kernel's own inode, which the daemon keeps open */
#define SDIR_HAS_FILES 1 /* single files are watched in it, by name (files) */

struct dir_info {
	__u32 id;          /* the daemon's number for the folder, whose path it knows */
	__u32 write_keys;  /* keys watching writes to what is in it (a folder tree's) */
	__u32 read_keys;   /* keys watching reads of what is in it */
	__u32 exec_keys;   /* keys watching programs run from anywhere below it */
	__u32 flags;
};

#define SENSOR_FILE_NAME 64

struct file_key {
	__u64 parent;                 /* the folder's inode */
	char name[SENSOR_FILE_NAME];  /* the file's name in it, zero-padded */
};

struct file_info {
	__u32 id;
	__u32 write_keys;
	__u32 read_keys;
};

/* Where the strings of an event are in its data, one after another, each followed by a NUL */
enum sensor_string {
	SSTR_NAME = 0,  /* the object's name in its folder; a module's name */
	SSTR_NAME2 = 1, /* a rename's or a link's other name, a symlink's target, an attribute's name */
	SSTR_EXE = 2,   /* the program, as the acting process sees it from its root */
	SSTR_CWD = 3,   /* the acting process's working folder */
	SSTR_PATH2 = 4, /* a whole path the daemon cannot make from a folder it knows: a program run, an input device, the other
	                  side of a rename or link, a name a refused open gave */
	SSTR_ARGV = 5,  /* a program's arguments, each followed by a NUL */
	SSTR_COUNT = 6,
};

#define SENSOR_DATA 8192
#define SENSOR_NAME_MAX 256
#define SENSOR_NAME2_MAX 1024
#define SENSOR_EXE_MAX 1536
#define SENSOR_CWD_MAX 1024
#define SENSOR_PATH2_MAX 1536
#define SENSOR_ARGV_MAX 2048

/* flags of SOP_OPEN, besides the open's own f_flags */
#define SOPEN_CREATED 0x80000000u /* the open made the file */
#define SOPEN_REFUSED 0x40000000u /* the file permissions refused it: result is the error, PATH2 the name given */
#define SOPEN_INPUT 0x20000000u   /* an input device */
#define SOPEN_READ 0x08000000u    /* read rather than written */

struct sensor_event {
	__u32 header;      /* offsetof(struct sensor_event, data): the daemon checks it is its own */
	__u32 op;
	__u64 time;        /* CLOCK_BOOTTIME, in nanoseconds */
	__u64 args[4];     /* the system call's first four arguments, as audit records them */
	__u64 ino;         /* the object's inode number, 0 when unknown */
	__s32 result;      /* 0, or the error */
	__u32 keys;
	__u32 syscall;     /* the system call the acting task is in, ~0 when none */
	__u32 dir;         /* the folder the object is in, as the daemon numbered it; 0 when none */
	__u32 dir2;        /* the other side's folder for a rename or a link; 0 when none */
	__u32 pid, ppid, auid, ses;
	__u32 uid, gid, euid, suid, fsuid, egid, sgid, fsgid;
	__u32 mode;        /* the object's mode */
	__u32 ouid, ogid;  /* the object's owner */
	__u32 dev;         /* the object's filesystem, as the kernel encodes a dev_t */
	__u32 rdev;
	__u32 flags;       /* by operation: the open's flags, setattr's ia_valid, the signal, the bpf() command */
	__u32 attr_mode;   /* setattr: what it set */
	__u32 attr_uid;
	__u32 attr_gid;
	__u32 argc;
	__u32 parent_mode; /* the mode of the folder the object is in */
	__u16 len[SSTR_COUNT];
	char comm[16];
	char tty[64];
	char data[SENSOR_DATA];
};

#endif
