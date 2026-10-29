// SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause)
/*
 * The kernel side of amethystora-sensor: what the audit rules record, recorded where it happens instead of at
 * every system call. Audit's per-task context makes every system call of every process slower once a single
 * rule is loaded; these are tracing programs on the functions that do the operations themselves, so a process
 * that touches nothing watched pays for a trampoline and a hash lookup on its opens and changes, and nothing
 * on anything else. Never a syscall tracepoint: those put every thread on the slow path too.
 *
 * What is watched is in the maps, by the kernel's own inode of each folder, which the daemon holds open:
 *   - dirs: every folder of a watched tree (writes, or reads), a folder holding single watched files, and the
 *     root of each folder programs are watched being run from
 *   - files: single files, by their folder and name, so that a file replaced by a rename, or not there yet,
 *     is still the one watched
 * Each operation on one of them becomes an event in the ring buffer, with who did it, read from the acting task
 * as audit reads it: login uid and session, every uid and gid, the program and its terminal. The daemon writes
 * it out as audit's own records.
 *
 * Attempts the file permissions refuse are recorded as audit recorded them: the VFS functions return the final
 * result, refusals included, and an open refused before any LSM hook is seen as it returns, by its name.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include "sensor.h"

char LICENSE[] SEC("license") = "Dual BSD/GPL";

#define S_IFMT 00170000
#define S_IFDIR 0040000
#define S_IFCHR 0020000
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#define S_ISCHR(m) (((m) & S_IFMT) == S_IFCHR)
#define MINORBITS 20
#define MAJOR(dev) ((unsigned int)((dev) >> MINORBITS))
#define INPUT_MAJOR 13
#define O_TRUNC 01000
#define FMODE_READ 0x1
#define FMODE_WRITE 0x2
#define FMODE_CREATED (1 << 20)
#define PF_KTHREAD 0x00200000
#define ATTR_SIZE (1 << 3)
#define ATTR_OPEN (1 << 15)
#define AUID_UNSET 0xffffffffu
#define MAX_ERRNO 4095
#define IS_ERR_VALUE(x) ((unsigned long)(x) >= (unsigned long)-MAX_ERRNO)

#define PATHBUF 4096
#define PATH_DEPTH 40
#define EXEC_DEPTH 16

/* The x86-64 system calls an event may come from, as the record names them */
#define NR_TRUNCATE 76
#define NR_RENAME 82
#define NR_LINK 86
#define NR_RENAMEAT 264
#define NR_LINKAT 265
#define NR_RENAMEAT2 316
#define NR_INIT_MODULE 175
#define NR_DELETE_MODULE 176
#define NR_FINIT_MODULE 313

/* Set by the daemon before loading: the keys it asked for. A key that is off leaves its code out (the verifier
 * prunes it), and the programs only it needs are not loaded at all. */
const volatile __u32 enabled_keys = 0;

/* Set by the daemon after loading: its own process, which is never recorded, and the slot its own opens write
 * the opened folder's inode to, which is how it learns what to put in the maps */
struct sensor_globals {
	__u32 self_tgid;
	__u32 pad;
	__u64 registered_inode;
};
struct sensor_globals globals = {};

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(map_flags, BPF_F_NO_PREALLOC);
	__uint(max_entries, 65536);
	__type(key, __u64);
	__type(value, struct dir_info);
} dirs SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(map_flags, BPF_F_NO_PREALLOC);
	__uint(max_entries, 16384);
	__type(key, struct file_key);
	__type(value, struct file_info);
} files SEC(".maps");

/* The events, which the daemon drains while it runs. It is not pinned, by the maintainer's choice: a signal
 * that kills the daemon takes the buffered records with it, and what happens until systemd has started it
 * again goes unrecorded; the watcher says every such restart (NRestarts, per boot). Non-fatal signals and
 * link-detach attempts are recorded live (PLAN-audit-cost.md section 4.7). */
struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 1 << 20);
} events SEC(".maps");

/* The sensor's own programs, by id, which a bpf() call aimed at their links is checked against */
struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 64);
	__type(key, __u32);
	__type(value, __u8);
} own_progs SEC(".maps");

/* Events not written: the ring buffer was full, or both scratch slots were in use on the CPU */
struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} dropped SEC(".maps");

/* Where an event is put together, two to a CPU: a program preempted while it builds one leaves the slot busy, and
 * another on the same CPU takes the second */
struct scratch {
	__u32 busy;
	__u32 pad;
	struct sensor_event e;
	char path[PATHBUF * 2];
};

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 2);
	__type(key, __u32);
	__type(value, struct scratch);
} scratch SEC(".maps");

/* What a task carries from one hook to the next: a rename's names, which the rename itself swaps, a program
 * matched before it ran, and the module being loaded */
struct stash {
	__u64 bprm;
	__u32 exec_keys;
	__u32 exec_dir;
	__u32 exec_len;
	__u32 rename_keys;
	__u32 rename_dir;
	__u32 rename_dir2;
	__u32 module_set;
	__u32 pad;
	char exec_path[SENSOR_PATH2_MAX];
	char old_name[SENSOR_NAME_MAX];
	char new_name[SENSOR_NAME_MAX];
	char module[SENSOR_NAME_MAX];
};

struct {
	__uint(type, BPF_MAP_TYPE_TASK_STORAGE);
	__uint(map_flags, BPF_F_NO_PREALLOC);
	__type(key, int);
	__type(value, struct stash);
} stash SEC(".maps");

/* __weak so the object still loads on a kernel whose BTF does not carry this symbol (it is static in the
 * kernel and not always emitted): there it resolves to 0 and the bpf() tamper check below becomes a no-op,
 * rather than failing the whole load. Where it is present, the check works. */
extern const struct file_operations bpf_link_fops __ksym __weak;

static __always_inline void count_drop(void)
{
	__u32 zero = 0;
	__u64 *count = bpf_map_lookup_elem(&dropped, &zero);

	if (count)
		*count += 1;
}

static __always_inline struct scratch *grab(void)
{
	__u32 slot = 0;
	struct scratch *s = bpf_map_lookup_elem(&scratch, &slot);

	if (s && !s->busy) {
		s->busy = 1;
		return s;
	}
	slot = 1;
	s = bpf_map_lookup_elem(&scratch, &slot);
	if (s && !s->busy) {
		s->busy = 1;
		return s;
	}
	count_drop();
	return NULL;
}

/* Whether the task is one the image records at all: not the sensor, and not a kernel thread */
static __always_inline bool recorded(struct task_struct *task)
{
	if ((__u32)(bpf_get_current_pid_tgid() >> 32) == globals.self_tgid)
		return false;
	return !(BPF_CORE_READ(task, flags) & PF_KTHREAD);
}

/* The keys that apply to what this task did: those of a login's own only when it is one (auid>=1000, set) */
static __always_inline __u32 applying(__u32 keys, struct task_struct *task)
{
	__u32 auid;

	keys &= enabled_keys;
	if (!(keys & LOGIN_KEYS))
		return keys;
	auid = BPF_CORE_READ(task, loginuid.val);
	if (auid < 1000 || auid == AUID_UNSET)
		keys &= ~LOGIN_KEYS;
	return keys;
}

/* --- Matching ------------------------------------------------------------------------------------------- */

static __always_inline struct dir_info *folder(struct inode *dir)
{
	__u64 key = (__u64)dir;

	return bpf_map_lookup_elem(&dirs, &key);
}

/* A single file's watch, by its folder and its name */
static __always_inline struct file_info *single(struct inode *dir, const unsigned char *name, __u32 len)
{
	struct file_key key = {};

	if (len == 0 || len >= SENSOR_FILE_NAME)
		return NULL;
	key.parent = (__u64)dir;
	bpf_probe_read_kernel(key.name, len & (SENSOR_FILE_NAME - 1), name);
	return bpf_map_lookup_elem(&files, &key);
}

/* The keys watching writes to NAME in DIR, and the folder's id */
static __always_inline __u32 write_keys(struct inode *dir, const unsigned char *name, __u32 len, __u32 *id)
{
	struct dir_info *d = folder(dir);
	struct file_info *f;
	__u32 keys;

	if (!d)
		return 0;
	keys = d->write_keys;
	*id = d->id;
	if (d->flags & SDIR_HAS_FILES) {
		f = single(dir, name, len);
		if (f)
			keys |= f->write_keys;
	}
	return keys;
}

static __always_inline __u32 read_keys(struct inode *dir, const unsigned char *name, __u32 len, __u32 *id)
{
	struct dir_info *d = folder(dir);
	struct file_info *f;
	__u32 keys;

	if (!d)
		return 0;
	keys = d->read_keys;
	*id = d->id;
	if (d->flags & SDIR_HAS_FILES) {
		f = single(dir, name, len);
		if (f)
			keys |= f->read_keys;
	}
	return keys;
}

/* --- Paths ---------------------------------------------------------------------------------------------- */

/* A path, from the end: each name before the last, up through the mounts, to the acting task's root or the
 * filesystem's. Written into the scratch's path buffer, which it ends at PATHBUF - 1; start is where it begins. */
struct walk {
	struct scratch *s;
	struct dentry *dentry;
	struct vfsmount *vfsmnt;
	struct mount *mnt;
	struct dentry *root_dentry;
	struct vfsmount *root_mnt;
	int off;
};

static long walk_step(__u64 index, struct walk *w)
{
	/* The kernel pointers are read out of the local walk struct plainly first: BPF_CORE_READ must only ever
	 * see a kernel type, or libbpf tries to relocate `struct walk`'s own fields against the kernel's BTF. */
	struct dentry *dentry = w->dentry;
	struct vfsmount *vfsmnt = w->vfsmnt;
	struct mount *mnt = w->mnt;
	struct dentry *parent, *mnt_root;
	struct mount *up;
	const unsigned char *name;
	__u32 len;

	if (dentry == w->root_dentry && vfsmnt == w->root_mnt)
		return 1;
	parent = BPF_CORE_READ(dentry, d_parent);
	mnt_root = BPF_CORE_READ(vfsmnt, mnt_root);
	if (dentry == mnt_root || dentry == parent) {
		/* The top of a mount: on to where it is mounted, or done at the top of the tree */
		up = BPF_CORE_READ(mnt, mnt_parent);
		if (!mnt || up == mnt)
			return 1;
		w->dentry = BPF_CORE_READ(mnt, mnt_mountpoint);
		w->mnt = up;
		w->vfsmnt = (struct vfsmount *)((char *)up + bpf_core_field_offset(struct mount, mnt));
		return 0;
	}
	len = BPF_CORE_READ(dentry, d_name.len) & 255;
	name = BPF_CORE_READ(dentry, d_name.name);
	/* No room: the path loses its front */
	if (w->off < (int)len + 1)
		return 1;
	w->off -= len;
	bpf_probe_read_kernel(&w->s->path[w->off & (PATHBUF - 1)], len, name);
	w->off -= 1;
	w->s->path[w->off & (PATHBUF - 1)] = '/';
	w->dentry = parent;
	return 0;
}

/* A global function, as put_program is: the verifier checks it once, on its own, rather than again for every
 * state a caller reaches it in. Inline, each string an event carries split the caller's states and every one
 * walked the path again, which was most of a load (6.7 million instructions verified, 14 s in the lab). So the
 * kernel pointers come as plain values, read only through BPF_CORE_READ, and the task is the current one, as it
 * is at every call. */
__noinline int walk_path(struct scratch *s, __u64 dentry, __u64 vfsmnt)
{
	struct task_struct *task = bpf_get_current_task_btf();
	struct walk w = {};

	if (!s)
		return -1;
	w.s = s;
	w.dentry = (struct dentry *)dentry;
	w.vfsmnt = (struct vfsmount *)vfsmnt;
	w.mnt = vfsmnt ? (struct mount *)((char *)vfsmnt - bpf_core_field_offset(struct mount, mnt)) : NULL;
	w.root_dentry = BPF_CORE_READ(task, fs, root.dentry);
	w.root_mnt = BPF_CORE_READ(task, fs, root.mnt);
	w.off = PATHBUF - 1;
	s->path[PATHBUF - 1] = 0;
	if (w.dentry)
		bpf_loop(PATH_DEPTH, walk_step, &w, 0);
	if (w.off == PATHBUF - 1) {
		w.off = PATHBUF - 2;
		s->path[PATHBUF - 2] = '/';
	}
	return w.off;
}

/* --- Putting an event together --------------------------------------------------------------------------- */

static __always_inline struct scratch *begin(__u32 op, int result, __u32 keys)
{
	struct scratch *s = grab();

	if (!s)
		return NULL;
	__builtin_memset(&s->e, 0, __builtin_offsetof(struct sensor_event, data));
	s->e.header = __builtin_offsetof(struct sensor_event, data);
	s->e.op = op;
	s->e.result = result;
	s->e.keys = keys;
	s->e.time = bpf_ktime_get_boot_ns();
	s->e.syscall = ~0u;
	return s;
}

/* The object's inode, as the PATH record gives it */
static __always_inline void object(struct sensor_event *e, struct inode *inode)
{
	if (!inode)
		return;
	e->ino = BPF_CORE_READ(inode, i_ino);
	e->mode = BPF_CORE_READ(inode, i_mode);
	e->ouid = BPF_CORE_READ(inode, i_uid.val);
	e->ogid = BPF_CORE_READ(inode, i_gid.val);
	e->dev = BPF_CORE_READ(inode, i_sb, s_dev);
	e->rdev = BPF_CORE_READ(inode, i_rdev);
}

static __always_inline __u32 put_empty(struct sensor_event *e, __u32 pos, int slot)
{
	if (pos > SENSOR_DATA - 1)
		return pos;
	e->data[pos & (SENSOR_DATA - 1)] = 0;
	/* slot is a compile-time constant at every call site, so the index needs no mask (and a mask by
	 * SSTR_COUNT, which is not a power of two, would alias slots 2 and 3 onto 0 and 1) */
	e->len[slot] = 0;
	return pos + 1;
}

/* A string from the kernel's memory, at most MAX bytes with its NUL */
#define PUT_KSTR(e, pos, slot, src, max)                                               \
	({                                                                              \
		__u32 _pos = (pos);                                                     \
		long _n = 0;                                                            \
		if (_pos <= SENSOR_DATA - (max)) {                                      \
			_n = (src) ? bpf_probe_read_kernel_str(&(e)->data[_pos], (max), (src)) : 0; \
			if (_n <= 0) {                                                  \
				(e)->data[_pos] = 0;                                    \
				_n = 1;                                                 \
			}                                                               \
			(e)->len[(slot)] = _n - 1;                                      \
			_pos += _n;                                                     \
		}                                                                       \
		_pos;                                                                   \
	})

/* ...and from the acting task's memory */
#define PUT_USTR(e, pos, slot, src, max)                                               \
	({                                                                              \
		__u32 _pos = (pos);                                                     \
		long _n = 0;                                                            \
		if (_pos <= SENSOR_DATA - (max)) {                                      \
			_n = (src) ? bpf_probe_read_user_str(&(e)->data[_pos], (max), (src)) : 0; \
			if (_n <= 0) {                                                  \
				(e)->data[_pos] = 0;                                    \
				_n = 1;                                                 \
			}                                                               \
			(e)->len[(slot)] = _n - 1;                                      \
			_pos += _n;                                                     \
		}                                                                       \
		_pos;                                                                   \
	})

/* A path from the scratch's path buffer, whose front goes when it is longer than MAX (a power of two) */
static __always_inline __u32 put_path(struct scratch *s, __u32 pos, int slot, int start, __u32 max)
{
	__u32 len;

	if (start < 0 || start > PATHBUF - 1)
		return put_empty(&s->e, pos, slot);
	len = PATHBUF - 1 - start;
	if (len > max - 1) {
		start += len - (max - 1);
		len = max - 1;
	}
	if (pos > SENSOR_DATA - max)
		return pos;
	len &= max - 1;
	bpf_probe_read_kernel(&s->e.data[pos], len, &s->path[start & (PATHBUF - 1)]);
	s->e.data[(pos + len) & (SENSOR_DATA - 1)] = 0;
	/* slot is a compile-time constant here; no mask (see put_empty) */
	s->e.len[slot] = len;
	return pos + len + 1;
}

/* Who did it, as audit's SYSCALL record says it, and the system call it was in */
static __always_inline void actor(struct sensor_event *e, struct task_struct *task)
{
	const struct cred *cred = BPF_CORE_READ(task, cred);
	struct tty_struct *tty = BPF_CORE_READ(task, signal, tty);
	struct pt_regs *regs = (struct pt_regs *)bpf_task_pt_regs(task);

	e->pid = BPF_CORE_READ(task, tgid);
	e->ppid = BPF_CORE_READ(task, real_parent, tgid);
	e->auid = BPF_CORE_READ(task, loginuid.val);
	e->ses = BPF_CORE_READ(task, sessionid);
	e->uid = BPF_CORE_READ(cred, uid.val);
	e->gid = BPF_CORE_READ(cred, gid.val);
	e->euid = BPF_CORE_READ(cred, euid.val);
	e->suid = BPF_CORE_READ(cred, suid.val);
	e->fsuid = BPF_CORE_READ(cred, fsuid.val);
	e->egid = BPF_CORE_READ(cred, egid.val);
	e->sgid = BPF_CORE_READ(cred, sgid.val);
	e->fsgid = BPF_CORE_READ(cred, fsgid.val);
	bpf_get_current_comm(e->comm, sizeof(e->comm));
	if (tty)
		bpf_probe_read_kernel_str(e->tty, sizeof(e->tty), &tty->name);
	if (regs) {
		e->syscall = BPF_CORE_READ(regs, orig_ax);
		e->args[0] = BPF_CORE_READ(regs, di);
		e->args[1] = BPF_CORE_READ(regs, si);
		e->args[2] = BPF_CORE_READ(regs, dx);
		e->args[3] = BPF_CORE_READ(regs, r10);
	}
}

/* The program and the working folder, after the names: EXE and CWD. Global, as walk_path is, and for the same
 * reason: pos comes as any value, which every put checks. */
__noinline __u32 put_program(struct scratch *s, __u32 pos)
{
	struct task_struct *task = bpf_get_current_task_btf();
	struct file *exe = BPF_CORE_READ(task, mm, exe_file);
	int start;

	if (!s)
		return pos;
	if (exe) {
		start = walk_path(s, (__u64)BPF_CORE_READ(exe, f_path.dentry), (__u64)BPF_CORE_READ(exe, f_path.mnt));
		pos = put_path(s, pos, SSTR_EXE, start, SENSOR_EXE_MAX);
	} else {
		pos = put_empty(&s->e, pos, SSTR_EXE);
	}
	start = walk_path(s, (__u64)BPF_CORE_READ(task, fs, pwd.dentry), (__u64)BPF_CORE_READ(task, fs, pwd.mnt));
	return put_path(s, pos, SSTR_CWD, start, SENSOR_CWD_MAX);
}

static __always_inline void submit(struct scratch *s, __u32 pos)
{
	__u64 size = __builtin_offsetof(struct sensor_event, data) + pos;

	if (size > sizeof(s->e))
		size = sizeof(s->e);
	if (bpf_ringbuf_output(&events, &s->e, size, 0))
		count_drop();
	s->busy = 0;
}

/* The common case: NAME in a folder the daemon knows, NAME2 when there is one, no whole path and no arguments */
static __always_inline void emit_named(__u32 op, int result, __u32 keys, __u32 id, struct inode *dir,
				       struct dentry *dentry, const char *name2, struct task_struct *task)
{
	struct scratch *s = begin(op, result, keys);
	__u32 pos = 0;

	if (!s)
		return;
	s->e.dir = id;
	s->e.parent_mode = BPF_CORE_READ(dir, i_mode);
	object(&s->e, BPF_CORE_READ(dentry, d_inode));
	actor(&s->e, task);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME, BPF_CORE_READ(dentry, d_name.name), SENSOR_NAME_MAX);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME2, name2, SENSOR_NAME2_MAX);
	pos = put_program(s, pos);
	pos = put_empty(&s->e, pos, SSTR_PATH2);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
}

/* --- Opens --------------------------------------------------------------------------------------------- */

/* Every open the kernel lets through, or an LSM refuses: written to, made, truncated or, for the keys that watch
 * reads, read, in a watched folder; and an input device opened by a login. Also how the daemon learns the inode
 * of each folder it opens to watch. */
SEC("fexit/security_file_open")
int BPF_PROG(file_open, struct file *file, int ret)
{
	struct task_struct *task = bpf_get_current_task_btf();
	struct dentry *dentry;
	struct inode *inode, *dir;
	struct scratch *s;
	__u32 keys, id = 0, fmode, fflags, pos = 0, len;
	bool write;

	if ((__u32)(bpf_get_current_pid_tgid() >> 32) == globals.self_tgid) {
		globals.registered_inode = (__u64)BPF_CORE_READ(file, f_inode);
		return 0;
	}
	/* Input-device opens are a program of their own (file_open_input), so this one stays within the
	 * verifier's complexity limit: it walks the program and the working folder once, in the path below. */
	if (!(enabled_keys & (WRITE_KEYS | READ_KEYS)))
		return 0;
	if (BPF_CORE_READ(task, flags) & PF_KTHREAD)
		return 0;
	inode = BPF_CORE_READ(file, f_inode);
	fmode = BPF_CORE_READ(file, f_mode);
	fflags = BPF_CORE_READ(file, f_flags);

	write = (fmode & (FMODE_WRITE | FMODE_CREATED)) || (fflags & O_TRUNC);
	if (!write && !((enabled_keys & READ_KEYS) && (fmode & FMODE_READ)))
		return 0;
	dentry = BPF_CORE_READ(file, f_path.dentry);
	dir = BPF_CORE_READ(dentry, d_parent, d_inode);
	len = BPF_CORE_READ(dentry, d_name.len);
	if (write)
		keys = write_keys(dir, BPF_CORE_READ(dentry, d_name.name), len, &id);
	else
		keys = read_keys(dir, BPF_CORE_READ(dentry, d_name.name), len, &id);
	if (!keys)
		return 0;
	keys = applying(keys, task);
	if (!keys)
		return 0;
	s = begin(SOP_OPEN, ret, keys);
	if (!s)
		return 0;
	s->e.flags = fflags | ((fmode & FMODE_CREATED) ? SOPEN_CREATED : 0) | (write ? 0 : SOPEN_READ);
	s->e.dir = id;
	s->e.parent_mode = BPF_CORE_READ(dir, i_mode);
	object(&s->e, inode);
	actor(&s->e, task);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME, BPF_CORE_READ(dentry, d_name.name), SENSOR_NAME_MAX);
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	pos = put_empty(&s->e, pos, SSTR_PATH2);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

/* Opening an input device, by a login: the one system call a software keylogger cannot avoid. A program of
 * its own, not part of file_open, so neither grows past the verifier's complexity limit; loaded only while
 * input-capture is on. */
SEC("fexit/security_file_open")
int BPF_PROG(file_open_input, struct file *file, int ret)
{
	struct task_struct *task;
	struct inode *inode;
	struct dentry *dentry;
	struct scratch *s;
	__u32 keys, pos = 0;
	int start;

	if (ret != 0 || !(enabled_keys & (1 << SKEY_INPUT_CAPTURE)))
		return 0;
	if ((__u32)(bpf_get_current_pid_tgid() >> 32) == globals.self_tgid)
		return 0;
	inode = BPF_CORE_READ(file, f_inode);
	if (!S_ISCHR(BPF_CORE_READ(inode, i_mode)) || MAJOR(BPF_CORE_READ(inode, i_rdev)) != INPUT_MAJOR)
		return 0;
	task = bpf_get_current_task_btf();
	if (BPF_CORE_READ(task, flags) & PF_KTHREAD)
		return 0;
	keys = applying(1 << SKEY_INPUT_CAPTURE, task);
	if (!keys)
		return 0;
	s = begin(SOP_OPEN, ret, keys);
	if (!s)
		return 0;
	s->e.flags = BPF_CORE_READ(file, f_flags) | SOPEN_INPUT;
	object(&s->e, inode);
	actor(&s->e, task);
	dentry = BPF_CORE_READ(file, f_path.dentry);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME, BPF_CORE_READ(dentry, d_name.name), SENSOR_NAME_MAX);
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	start = walk_path(s, (__u64)dentry, (__u64)BPF_CORE_READ(file, f_path.mnt));
	pos = put_path(s, pos, SSTR_PATH2, start, SENSOR_PATH2_MAX);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

/* An open the file permissions refused, which no LSM hook sees, by the name the system call gave: the daemon
 * matches it against the paths it watches, joined with the working folder when it is relative. Only a refusal
 * (EACCES, EPERM), and a read only while a key watches reads: every other open costs one comparison here.
 * Measured on 7.2: inode_permission, where the check itself fails, is called hundreds of thousands of times in
 * one `find /usr` and costs a fifth of every stat; do_filp_open is called once an open. */
#define EACCES 13
#define EPERM 1
#define O_ACCMODE 3
#define O_CREAT 0100
#define O_DIRECTORY 0200000

SEC("fexit/do_filp_open")
int BPF_PROG(open_refused, int dfd, struct filename *pathname, const struct open_flags *op, struct file *ret)
{
	struct task_struct *task;
	struct scratch *s;
	__u32 keys, flags, pos = 0;
	long err;
	bool write;

	if (!IS_ERR_VALUE(ret))
		return 0;
	err = (long)ret;
	if (err != -EACCES && err != -EPERM)
		return 0;
	flags = BPF_CORE_READ(op, open_flag);
	write = (flags & O_ACCMODE) || (flags & (O_CREAT | O_TRUNC));
	keys = write ? (enabled_keys & WRITE_KEYS) : (enabled_keys & READ_KEYS);
	if (!keys || (!write && (flags & O_DIRECTORY)))
		return 0;
	task = bpf_get_current_task_btf();
	if (!recorded(task))
		return 0;
	keys = applying(keys, task);
	if (!keys)
		return 0;
	/* Which of these keys watch the path is the daemon's to say */
	s = begin(SOP_OPEN, err, keys);
	if (!s)
		return 0;
	s->e.flags = flags | SOPEN_REFUSED | (write ? 0 : SOPEN_READ);
	actor(&s->e, task);
	pos = put_empty(&s->e, pos, SSTR_NAME);
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	pos = PUT_KSTR(&s->e, pos, SSTR_PATH2, BPF_CORE_READ(pathname, name), SENSOR_PATH2_MAX);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

/* --- Folders and attributes, with their final result --------------------------------------------------- */

static __always_inline int named_op(__u32 op, struct inode *dir, struct dentry *dentry, int ret, const char *name2)
{
	struct task_struct *task;
	__u32 keys, id = 0;

	if (!(enabled_keys & WRITE_KEYS))
		return 0;
	keys = write_keys(dir, BPF_CORE_READ(dentry, d_name.name), BPF_CORE_READ(dentry, d_name.len), &id);
	if (!keys)
		return 0;
	task = bpf_get_current_task_btf();
	if (!recorded(task))
		return 0;
	keys = applying(keys, task);
	if (keys)
		emit_named(op, ret, keys, id, dir, dentry, name2, task);
	return 0;
}

/* A change to the file itself: its folder is its parent's */
static __always_inline int attr_op(__u32 op, struct dentry *dentry, int ret, const char *name2, struct iattr *attr)
{
	struct task_struct *task;
	struct inode *dir;
	struct scratch *s;
	__u32 keys, id = 0, pos = 0;

	if (!(enabled_keys & WRITE_KEYS))
		return 0;
	dir = BPF_CORE_READ(dentry, d_parent, d_inode);
	keys = write_keys(dir, BPF_CORE_READ(dentry, d_name.name), BPF_CORE_READ(dentry, d_name.len), &id);
	if (!keys)
		return 0;
	task = bpf_get_current_task_btf();
	if (!recorded(task))
		return 0;
	keys = applying(keys, task);
	if (!keys)
		return 0;
	s = begin(op, ret, keys);
	if (!s)
		return 0;
	s->e.dir = id;
	s->e.parent_mode = BPF_CORE_READ(dir, i_mode);
	if (attr) {
		s->e.flags = BPF_CORE_READ(attr, ia_valid);
		s->e.attr_mode = BPF_CORE_READ(attr, ia_mode);
		s->e.attr_uid = BPF_CORE_READ(attr, ia_uid.val);
		s->e.attr_gid = BPF_CORE_READ(attr, ia_gid.val);
	}
	object(&s->e, BPF_CORE_READ(dentry, d_inode));
	actor(&s->e, task);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME, BPF_CORE_READ(dentry, d_name.name), SENSOR_NAME_MAX);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME2, name2, SENSOR_NAME2_MAX);
	pos = put_program(s, pos);
	pos = put_empty(&s->e, pos, SSTR_PATH2);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

SEC("fexit/vfs_unlink")
int BPF_PROG(vfs_unlink_exit, struct mnt_idmap *idmap, struct inode *dir, struct dentry *dentry,
	     struct delegated_inode *delegated, int ret)
{
	return named_op(SOP_UNLINK, dir, dentry, ret, NULL);
}

SEC("fexit/vfs_rmdir")
int BPF_PROG(vfs_rmdir_exit, struct mnt_idmap *idmap, struct inode *dir, struct dentry *dentry,
	     struct delegated_inode *delegated, int ret)
{
	return named_op(SOP_RMDIR, dir, dentry, ret, NULL);
}

SEC("fexit/vfs_mkdir")
int BPF_PROG(vfs_mkdir_exit, struct mnt_idmap *idmap, struct inode *dir, struct dentry *dentry, umode_t mode,
	     struct delegated_inode *delegated, struct dentry *ret)
{
	long result = IS_ERR_VALUE(ret) ? (long)ret : 0;

	return named_op(SOP_MKDIR, dir, (result || !ret) ? dentry : ret, result, NULL);
}

SEC("fexit/vfs_mknod")
int BPF_PROG(vfs_mknod_exit, struct mnt_idmap *idmap, struct inode *dir, struct dentry *dentry, umode_t mode,
	     dev_t dev, struct delegated_inode *delegated, int ret)
{
	return named_op(SOP_MKNOD, dir, dentry, ret, NULL);
}

SEC("fexit/vfs_symlink")
int BPF_PROG(vfs_symlink_exit, struct mnt_idmap *idmap, struct inode *dir, struct dentry *dentry,
	     const char *target, struct delegated_inode *delegated, int ret)
{
	return named_op(SOP_SYMLINK, dir, dentry, ret, target);
}

/* A hard link: a new name for a watched file is as much a change as a new file in a watched folder. The side the
 * daemon does not know is named as the system call gave it. */
SEC("fexit/vfs_link")
int BPF_PROG(vfs_link_exit, struct dentry *old_dentry, struct mnt_idmap *idmap, struct inode *dir,
	     struct dentry *new_dentry, struct delegated_inode *delegated, int ret)
{
	struct task_struct *task;
	struct inode *old_dir;
	struct scratch *s;
	__u32 keys, keys_old, id = 0, id_old = 0, pos = 0, nr;
	const char *given = NULL;

	if (!(enabled_keys & WRITE_KEYS))
		return 0;
	keys = write_keys(dir, BPF_CORE_READ(new_dentry, d_name.name), BPF_CORE_READ(new_dentry, d_name.len), &id);
	old_dir = BPF_CORE_READ(old_dentry, d_parent, d_inode);
	keys_old = write_keys(old_dir, BPF_CORE_READ(old_dentry, d_name.name), BPF_CORE_READ(old_dentry, d_name.len),
			      &id_old);
	if (!(keys | keys_old))
		return 0;
	task = bpf_get_current_task_btf();
	if (!recorded(task))
		return 0;
	keys = applying(keys | keys_old, task);
	if (!keys)
		return 0;
	s = begin(SOP_LINK, ret, keys);
	if (!s)
		return 0;
	s->e.dir = id;
	s->e.dir2 = id_old;
	s->e.parent_mode = BPF_CORE_READ(dir, i_mode);
	object(&s->e, BPF_CORE_READ(old_dentry, d_inode));
	actor(&s->e, task);
	nr = s->e.syscall;
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME, BPF_CORE_READ(new_dentry, d_name.name), SENSOR_NAME_MAX);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME2, BPF_CORE_READ(old_dentry, d_name.name), SENSOR_NAME2_MAX);
	pos = put_program(s, pos);
	/* The unknown side as given: link(old, new), linkat(olddfd, old, newdfd, new) */
	if (!id)
		given = (const char *)(nr == NR_LINK ? s->e.args[1] : nr == NR_LINKAT ? s->e.args[3] : 0);
	else if (!id_old)
		given = (const char *)(nr == NR_LINK ? s->e.args[0] : nr == NR_LINKAT ? s->e.args[1] : 0);
	pos = PUT_USTR(&s->e, pos, SSTR_PATH2, given, SENSOR_PATH2_MAX);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

/* A rename moves the names it is given, so they are kept on the way in */
SEC("fentry/vfs_rename")
int BPF_PROG(vfs_rename_entry, struct renamedata *rd)
{
	struct task_struct *task;
	struct dentry *old_dentry, *new_dentry;
	struct inode *old_dir, *new_dir;
	struct stash *st;
	__u32 keys, id = 0, id2 = 0;

	if (!(enabled_keys & WRITE_KEYS))
		return 0;
	old_dentry = BPF_CORE_READ(rd, old_dentry);
	new_dentry = BPF_CORE_READ(rd, new_dentry);
	old_dir = BPF_CORE_READ(rd, old_parent, d_inode);
	new_dir = BPF_CORE_READ(rd, new_parent, d_inode);
	keys = write_keys(old_dir, BPF_CORE_READ(old_dentry, d_name.name), BPF_CORE_READ(old_dentry, d_name.len), &id) |
	       write_keys(new_dir, BPF_CORE_READ(new_dentry, d_name.name), BPF_CORE_READ(new_dentry, d_name.len), &id2);
	if (!keys)
		return 0;
	task = bpf_get_current_task_btf();
	if (!recorded(task))
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, BPF_LOCAL_STORAGE_GET_F_CREATE);
	if (!st)
		return 0;
	st->rename_keys = keys;
	st->rename_dir = id;
	st->rename_dir2 = id2;
	bpf_probe_read_kernel_str(st->old_name, sizeof(st->old_name), BPF_CORE_READ(old_dentry, d_name.name));
	bpf_probe_read_kernel_str(st->new_name, sizeof(st->new_name), BPF_CORE_READ(new_dentry, d_name.name));
	return 0;
}

SEC("fexit/vfs_rename")
int BPF_PROG(vfs_rename_exit, struct renamedata *rd, int ret)
{
	struct task_struct *task = bpf_get_current_task_btf();
	struct stash *st;
	struct scratch *s;
	__u32 keys, pos = 0, nr;
	const char *given = NULL;

	if (!(enabled_keys & WRITE_KEYS))
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, 0);
	if (!st || !st->rename_keys)
		return 0;
	keys = applying(st->rename_keys, task);
	st->rename_keys = 0;
	if (!keys)
		return 0;
	s = begin(SOP_RENAME, ret, keys);
	if (!s)
		return 0;
	s->e.dir = st->rename_dir;
	s->e.dir2 = st->rename_dir2;
	s->e.parent_mode = BPF_CORE_READ(rd, old_parent, d_inode, i_mode);
	/* After the rename the moved dentry has the new name, and its inode */
	object(&s->e, BPF_CORE_READ(rd, old_dentry, d_inode));
	actor(&s->e, task);
	nr = s->e.syscall;
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME, st->old_name, SENSOR_NAME_MAX);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME2, st->new_name, SENSOR_NAME2_MAX);
	pos = put_program(s, pos);
	/* The side the daemon does not know, as given: rename(old, new), renameat(2)(olddfd, old, newdfd, new) */
	if (!st->rename_dir2)
		given = (const char *)(nr == NR_RENAME ? s->e.args[1] :
				       (nr == NR_RENAMEAT || nr == NR_RENAMEAT2) ? s->e.args[3] : 0);
	else if (!st->rename_dir)
		given = (const char *)(nr == NR_RENAME ? s->e.args[0] :
				       (nr == NR_RENAMEAT || nr == NR_RENAMEAT2) ? s->e.args[1] : 0);
	pos = PUT_USTR(&s->e, pos, SSTR_PATH2, given, SENSOR_PATH2_MAX);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

/* Mode, owner, times and size. open(O_TRUNC) is the open's (ATTR_OPEN) and truncate(2) vfs_truncate's. */
SEC("fexit/notify_change")
int BPF_PROG(notify_change_exit, struct mnt_idmap *idmap, struct dentry *dentry, struct iattr *attr,
	     struct delegated_inode *delegated, int ret)
{
	__u32 valid = BPF_CORE_READ(attr, ia_valid);
	struct pt_regs *regs;

	if (valid & ATTR_OPEN)
		return 0;
	if (valid & ATTR_SIZE) {
		regs = (struct pt_regs *)bpf_task_pt_regs(bpf_get_current_task_btf());
		if (regs && BPF_CORE_READ(regs, orig_ax) == NR_TRUNCATE)
			return 0;
	}
	return attr_op(SOP_SETATTR, dentry, ret, NULL, attr);
}

/* truncate(2), whose permission check comes before notify_change */
SEC("fexit/vfs_truncate")
int BPF_PROG(vfs_truncate_exit, const struct path *path, loff_t length, int ret)
{
	return attr_op(SOP_TRUNCATE, BPF_CORE_READ(path, dentry), ret, NULL, NULL);
}

SEC("fexit/vfs_setxattr")
int BPF_PROG(vfs_setxattr_exit, struct mnt_idmap *idmap, struct dentry *dentry, const char *name, const void *value,
	     size_t size, int flags, int ret)
{
	return attr_op(SOP_SETXATTR, dentry, ret, name, NULL);
}

SEC("fexit/vfs_removexattr")
int BPF_PROG(vfs_removexattr_exit, struct mnt_idmap *idmap, struct dentry *dentry, const char *name, int ret)
{
	return attr_op(SOP_REMOVEXATTR, dentry, ret, name, NULL);
}

SEC("fexit/vfs_set_acl")
int BPF_PROG(vfs_set_acl_exit, struct mnt_idmap *idmap, struct dentry *dentry, const char *acl_name,
	     struct posix_acl *kacl, int ret)
{
	return attr_op(SOP_SET_ACL, dentry, ret, acl_name, NULL);
}

SEC("fexit/vfs_remove_acl")
int BPF_PROG(vfs_remove_acl_exit, struct mnt_idmap *idmap, struct dentry *dentry, const char *acl_name, int ret)
{
	return attr_op(SOP_REMOVE_ACL, dentry, ret, acl_name, NULL);
}

/* --- Programs run ------------------------------------------------------------------------------------------ */

/* The folder a program is run from, at most EXEC_DEPTH folders up from it, among the roots watched */
struct exec_walk {
	struct dentry *dentry;
	__u32 keys;
	__u32 id;
};

static long exec_step(__u64 index, struct exec_walk *w)
{
	/* The kernel dentry out of the local struct first, so BPF_CORE_READ relocates only kernel types */
	struct dentry *dentry = w->dentry;
	struct inode *inode = BPF_CORE_READ(dentry, d_inode);
	struct dentry *parent = BPF_CORE_READ(dentry, d_parent);
	struct dir_info *d = folder(inode);

	if (d && d->exec_keys) {
		w->keys = d->exec_keys;
		w->id = d->id;
		return 1;
	}
	if (!parent || parent == dentry)
		return 1;
	w->dentry = parent;
	return 0;
}

/* The first check of an exec is for the file it names (audit's PATH item 0), later ones for its interpreter */
SEC("fentry/security_bprm_check")
int BPF_PROG(bprm_check, struct linux_binprm *bprm)
{
	struct task_struct *task;
	struct exec_walk w = {};
	struct stash *st;
	struct scratch *s;
	struct file *file;
	__u32 keys;
	int start;

	if (!(enabled_keys & EXEC_KEYS))
		return 0;
	task = bpf_get_current_task_btf();
	if (!applying(EXEC_KEYS, task) || !recorded(task))
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, 0);
	if (st && st->bprm == (__u64)bprm)
		return 0;
	file = BPF_CORE_READ(bprm, file);
	w.dentry = BPF_CORE_READ(file, f_path.dentry);
	bpf_loop(EXEC_DEPTH, exec_step, &w, 0);
	keys = applying(w.keys, task);
	if (!keys)
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, BPF_LOCAL_STORAGE_GET_F_CREATE);
	if (!st)
		return 0;
	s = grab();
	if (!s)
		return 0;
	st->bprm = (__u64)bprm;
	st->exec_keys = keys;
	st->exec_dir = w.id;
	start = walk_path(s, (__u64)BPF_CORE_READ(file, f_path.dentry), (__u64)BPF_CORE_READ(file, f_path.mnt));
	if (start >= 0 && start <= PATHBUF - 1) {
		__u32 len = PATHBUF - 1 - start;

		if (len > SENSOR_PATH2_MAX - 1)
			len = SENSOR_PATH2_MAX - 1;
		len &= SENSOR_PATH2_MAX - 1;
		bpf_probe_read_kernel(st->exec_path, len, &s->path[start & (PATHBUF - 1)]);
		st->exec_len = len;
	}
	s->busy = 0;
	return 0;
}

/* ...and it ran: who ran it, with its arguments, as the new program */
SEC("tp_btf/sched_process_exec")
int BPF_PROG(process_exec, struct task_struct *p, pid_t old_pid, struct linux_binprm *bprm)
{
	struct task_struct *task = bpf_get_current_task_btf();
	struct stash *st;
	struct scratch *s;
	unsigned long arg_start, arg_end;
	__u32 pos = 0, len;

	if (!(enabled_keys & EXEC_KEYS))
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, 0);
	if (!st || st->bprm != (__u64)bprm)
		return 0;
	st->bprm = 0;
	s = begin(SOP_EXEC, 0, st->exec_keys);
	if (!s)
		return 0;
	s->e.dir = st->exec_dir;
	s->e.argc = BPF_CORE_READ(bprm, argc);
	object(&s->e, BPF_CORE_READ(bprm, file, f_inode));
	actor(&s->e, task);
	pos = put_empty(&s->e, pos, SSTR_NAME);
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	len = st->exec_len & (SENSOR_PATH2_MAX - 1);
	if (pos <= SENSOR_DATA - SENSOR_PATH2_MAX) {
		bpf_probe_read_kernel(&s->e.data[pos], len, st->exec_path);
		s->e.data[(pos + len) & (SENSOR_DATA - 1)] = 0;
		s->e.len[SSTR_PATH2] = len;
		pos += len + 1;
	}
	arg_start = BPF_CORE_READ(task, mm, arg_start);
	arg_end = BPF_CORE_READ(task, mm, arg_end);
	len = arg_end > arg_start ? arg_end - arg_start : 0;
	if (len > SENSOR_ARGV_MAX - 1)
		len = SENSOR_ARGV_MAX - 1;
	len &= SENSOR_ARGV_MAX - 1;
	if (pos <= SENSOR_DATA - SENSOR_ARGV_MAX) {
		if (bpf_probe_read_user(&s->e.data[pos], len, (void *)arg_start))
			len = 0;
		s->e.data[(pos + len) & (SENSOR_DATA - 1)] = 0;
		s->e.len[SSTR_ARGV] = len;
		pos += len + 1;
	}
	submit(s, pos);
	return 0;
}

/* ...or it did not run: an exec the file permissions, a noexec mount or an LSM refused, as audit recorded it
 * (success=no, the caller as exe, the name as given). Most refusals come before security_bprm_check, so no
 * folder is matched here: the name goes to the daemon, which keeps it only under a watched folder, as for a
 * refused open. Any failure also ends the exec that bprm_check may have stashed, so that a later exec whose
 * linux_binprm reuses the address is not taken for it. */
#define NR_EXECVE 59
#define NR_EXECVEAT 322

static __always_inline int exec_call(__u32 nr, const struct pt_regs *regs, long ret)
{
	struct task_struct *task;
	struct stash *st;
	struct scratch *s;
	__u32 keys, pos = 0;

	if (ret >= 0 || !(enabled_keys & EXEC_KEYS))
		return 0;
	task = bpf_get_current_task_btf();
	st = bpf_task_storage_get(&stash, task, 0, 0);
	if (st)
		st->bprm = 0;
	if (ret != -EACCES && ret != -EPERM)
		return 0;
	keys = applying(EXEC_KEYS, task);
	if (!keys || !recorded(task))
		return 0;
	s = begin(SOP_EXEC, ret, keys);
	if (!s)
		return 0;
	s->e.flags = SOPEN_REFUSED;
	actor(&s->e, task);
	s->e.syscall = nr;
	s->e.args[0] = BPF_CORE_READ(regs, di);
	s->e.args[1] = BPF_CORE_READ(regs, si);
	s->e.args[2] = BPF_CORE_READ(regs, dx);
	s->e.args[3] = BPF_CORE_READ(regs, r10);
	pos = put_empty(&s->e, pos, SSTR_NAME);
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	/* execve(name, ...), execveat(dfd, name, ...) */
	pos = PUT_USTR(&s->e, pos, SSTR_PATH2, (const char *)s->e.args[nr == NR_EXECVEAT ? 1 : 0], SENSOR_PATH2_MAX);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

SEC("fexit/__x64_sys_execve")
int BPF_PROG(execve_exit, const struct pt_regs *regs, long ret)
{
	return exec_call(NR_EXECVE, regs, ret);
}

SEC("fexit/__x64_sys_execveat")
int BPF_PROG(execveat_exit, const struct pt_regs *regs, long ret)
{
	return exec_call(NR_EXECVEAT, regs, ret);
}

/* --- Kernel modules ---------------------------------------------------------------------------------------- */

/* The module's name, for the record: its file's for finit_module, until the kernel has read its own */
SEC("fentry/security_kernel_read_file")
int BPF_PROG(module_file, struct file *file, enum kernel_read_file_id id, bool contents)
{
	struct task_struct *task;
	struct stash *st;

	if (!(enabled_keys & (1 << SKEY_MODULES)) || (id != bpf_core_enum_value(enum kernel_read_file_id, READING_MODULE) &&
	     id != bpf_core_enum_value(enum kernel_read_file_id, READING_MODULE_COMPRESSED)))
		return 0;
	task = bpf_get_current_task_btf();
	if (!applying(1 << SKEY_MODULES, task))
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, BPF_LOCAL_STORAGE_GET_F_CREATE);
	if (!st)
		return 0;
	bpf_probe_read_kernel_str(st->module, sizeof(st->module), BPF_CORE_READ(file, f_path.dentry, d_name.name));
	st->module_set = 1;
	return 0;
}

SEC("tp_btf/module_load")
int BPF_PROG(module_loaded, struct module *mod)
{
	struct task_struct *task;
	struct stash *st;

	if (!(enabled_keys & (1 << SKEY_MODULES)))
		return 0;
	task = bpf_get_current_task_btf();
	if (!applying(1 << SKEY_MODULES, task))
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, BPF_LOCAL_STORAGE_GET_F_CREATE);
	if (!st)
		return 0;
	bpf_probe_read_kernel_str(st->module, sizeof(st->module), mod->name);
	st->module_set = 1;
	return 0;
}

static __always_inline int module_call(__u32 op, __u32 nr, const struct pt_regs *regs, long ret)
{
	struct task_struct *task = bpf_get_current_task_btf();
	struct stash *st;
	struct scratch *s;
	__u32 keys, pos = 0;

	keys = applying(1 << SKEY_MODULES, task);
	if (!keys || !recorded(task))
		return 0;
	st = bpf_task_storage_get(&stash, task, 0, 0);
	s = begin(op, ret, keys);
	if (!s)
		return 0;
	actor(&s->e, task);
	s->e.syscall = nr;
	s->e.args[0] = BPF_CORE_READ(regs, di);
	s->e.args[1] = BPF_CORE_READ(regs, si);
	s->e.args[2] = BPF_CORE_READ(regs, dx);
	s->e.args[3] = BPF_CORE_READ(regs, r10);
	if (op == SOP_MODULE_DELETE)
		pos = PUT_USTR(&s->e, pos, SSTR_NAME, (const char *)s->e.args[0], SENSOR_NAME_MAX);
	else if (st && st->module_set)
		pos = PUT_KSTR(&s->e, pos, SSTR_NAME, st->module, SENSOR_NAME_MAX);
	else
		pos = put_empty(&s->e, pos, SSTR_NAME);
	if (st)
		st->module_set = 0;
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	pos = put_empty(&s->e, pos, SSTR_PATH2);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

SEC("fexit/__x64_sys_finit_module")
int BPF_PROG(finit_module_exit, const struct pt_regs *regs, long ret)
{
	return module_call(SOP_MODULE_LOAD, NR_FINIT_MODULE, regs, ret);
}

SEC("fexit/__x64_sys_init_module")
int BPF_PROG(init_module_exit, const struct pt_regs *regs, long ret)
{
	return module_call(SOP_MODULE_LOAD, NR_INIT_MODULE, regs, ret);
}

SEC("fexit/__x64_sys_delete_module")
int BPF_PROG(delete_module_exit, const struct pt_regs *regs, long ret)
{
	return module_call(SOP_MODULE_DELETE, NR_DELETE_MODULE, regs, ret);
}

/* --- Another program's memory ------------------------------------------------------------------------------ */

#define PTRACE_MODE_ATTACH 0x02

/* The number of a task's mount namespace, or 0 on a kernel that names it otherwise */
static __always_inline __u32 mount_ns(struct task_struct *task)
{
	struct mnt_namespace *ns = BPF_CORE_READ(task, nsproxy, mnt_ns);

	if (!ns || !bpf_core_field_exists(ns->ns.inum))
		return 0;
	return BPF_CORE_READ(ns, ns.inum);
}

/* Attaching to another program, or reaching into its memory, by a login. ptrace's attach and seize,
 * process_vm_readv and process_vm_writev, pidfd_getfd and opening /proc/PID/mem each ask the LSMs, Yama among them,
 * with PTRACE_MODE_ATTACH once the checks of who may at all have passed; their answer is the result, so a refusal
 * by Yama is recorded as well. Every read of /proc/PID/stat asks the same hook with PTRACE_MODE_READ, so anything
 * but an attach returns at once. A refusal before the LSMs (another account's process, without the capability)
 * never comes here, nor does a thread of the caller's own. The system call and its arguments, which actor()
 * reads, say which of these it was; the target's program, name and mount namespace say what was reached. */
SEC("fexit/security_ptrace_access_check")
int BPF_PROG(ptrace_access, struct task_struct *child, unsigned int mode, int ret)
{
	const char *comm = child->comm;
	struct task_struct *task;
	struct file *exe;
	struct scratch *s;
	__u32 keys, pos = 0;
	int start;

	if (!(mode & PTRACE_MODE_ATTACH) || !(enabled_keys & (1 << SKEY_INJECTION)))
		return 0;
	task = bpf_get_current_task_btf();
	if (!recorded(task))
		return 0;
	keys = applying(1 << SKEY_INJECTION, task);
	if (!keys)
		return 0;
	s = begin(SOP_MEMORY, ret, keys);
	if (!s)
		return 0;
	s->e.flags = mode;
	s->e.target = BPF_CORE_READ(child, tgid);
	s->e.target_auid = BPF_CORE_READ(child, loginuid.val);
	s->e.target_uid = BPF_CORE_READ(child, real_cred, uid.val);
	s->e.target_mnt = mount_ns(child);
	s->e.own_mnt = mount_ns(task);
	actor(&s->e, task);
	pos = PUT_KSTR(&s->e, pos, SSTR_NAME, comm, 16);
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	exe = BPF_CORE_READ(child, mm, exe_file);
	if (exe) {
		start = walk_path(s, (__u64)BPF_CORE_READ(exe, f_path.dentry), (__u64)BPF_CORE_READ(exe, f_path.mnt));
		pos = put_path(s, pos, SSTR_PATH2, start, SENSOR_PATH2_MAX);
	} else {
		pos = put_empty(&s->e, pos, SSTR_PATH2);
	}
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
	return 0;
}

/* --- What is done to the sensor itself --------------------------------------------------------------------- */

static __always_inline void emit_tamper(__u32 op, __u32 flags, struct task_struct *task)
{
	struct scratch *s = begin(op, 0, 1 << SKEY_SENSOR);
	__u32 pos = 0;

	if (!s)
		return;
	s->e.flags = flags;
	actor(&s->e, task);
	pos = put_empty(&s->e, pos, SSTR_NAME);
	pos = put_empty(&s->e, pos, SSTR_NAME2);
	pos = put_program(s, pos);
	pos = put_empty(&s->e, pos, SSTR_PATH2);
	pos = put_empty(&s->e, pos, SSTR_ARGV);
	submit(s, pos);
}

/* A signal sent to it, from anywhere but itself or the kernel, recorded before it is delivered. While the
 * daemon keeps running (a non-fatal signal, SIGSTOP once it resumes) the record is drained and kept; a signal
 * that kills it is lost with the unpinned ring buffer, and the watcher says the restart instead. */
SEC("fentry/security_task_kill")
int BPF_PROG(task_kill, struct task_struct *p, struct kernel_siginfo *info, int sig, const struct cred *cred)
{
	struct task_struct *task;

	if (!sig || !globals.self_tgid || BPF_CORE_READ(p, tgid) != globals.self_tgid)
		return 0;
	task = bpf_get_current_task_btf();
	if (!recorded(task))
		return 0;
	emit_tamper(SOP_KILL, sig, task);
	return 0;
}

/* bpf() detaching or replacing one of its links, through a descriptor of the caller's own (pidfd_getfd gives
 * one): which program the link holds decides */
SEC("fentry/security_bpf")
int BPF_PROG(bpf_call, int cmd, union bpf_attr *attr, unsigned int size, bool kernel)
{
	struct task_struct *task;
	struct fdtable *fdt;
	struct file **fds;
	struct file *file = NULL;
	struct bpf_link *link;
	unsigned int fd, max;
	__u32 prog_id;

	if (kernel)
		return 0;
	if (cmd == bpf_core_enum_value(enum bpf_cmd, BPF_LINK_DETACH))
		fd = BPF_CORE_READ(attr, link_detach.link_fd);
	else if (cmd == bpf_core_enum_value(enum bpf_cmd, BPF_LINK_UPDATE))
		fd = BPF_CORE_READ(attr, link_update.link_fd);
	else
		return 0;
	task = bpf_get_current_task_btf();
	if (BPF_CORE_READ(task, tgid) == globals.self_tgid)
		return 0;
	/* Without bpf_link_fops there is no way to tell an fd is a BPF link, so this check cannot run here */
	if (!&bpf_link_fops)
		return 0;
	fdt = BPF_CORE_READ(task, files, fdt);
	max = BPF_CORE_READ(fdt, max_fds);
	fds = BPF_CORE_READ(fdt, fd);
	if (fd >= max)
		return 0;
	bpf_probe_read_kernel(&file, sizeof(file), &fds[fd]);
	if (!file || BPF_CORE_READ(file, f_op) != &bpf_link_fops)
		return 0;
	link = BPF_CORE_READ(file, private_data);
	prog_id = BPF_CORE_READ(link, prog, aux, id);
	if (!bpf_map_lookup_elem(&own_progs, &prog_id))
		return 0;
	emit_tamper(SOP_BPF, cmd, task);
	return 0;
}
