// Compiles src/bpf/sensor.bpf.c into the BPF object the daemon embeds with include_bytes! and loads with
// libbpf (ObjectBuilder::open_memory). A prebuilt object rather than a bpftool skeleton, so the crate needs
// no libbpf-cargo and its own libbpf copy: the one object is CO-RE, relocated against the running kernel's
// BTF at load, so the vmlinux.h it compiles against only has to define the types, not match the kernel.
//
// Needs clang, and a vmlinux.h: SENSOR_VMLINUX_DIR if set, else kernel-devel's copy, else a bpftool dump of
// the running kernel's BTF. The apps stage (build-apps.sh) installs clang and kernel-devel for this; a plain
// `cargo build` on a machine without them fails here, which is correct: the sensor builds only in that stage
// or the dev container.
use std::path::{Path, PathBuf};
use std::process::Command;
use std::{env, fs};

fn main() {
    let src = "src/bpf/sensor.bpf.c";
    println!("cargo:rerun-if-changed={src}");
    println!("cargo:rerun-if-changed=src/bpf/sensor.h");
    println!("cargo:rerun-if-env-changed=SENSOR_VMLINUX_DIR");
    println!("cargo:rerun-if-env-changed=CLANG");

    let out = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR"));
    let inc = vmlinux_dir(&out);
    let clang = env::var("CLANG").unwrap_or_else(|_| "clang".to_string());
    let obj = out.join("sensor.bpf.o");

    let status = Command::new(&clang)
        .args([
            "-target",
            "bpf",
            "-O2",
            "-g",
            "-Wall",
            // vmlinux.h uses Microsoft-style anonymous members; the kernel's own BPF build sets these too
            "-fms-extensions",
            "-Wno-microsoft-anon-tag",
            "-Wno-unused-variable",
            "-D__TARGET_ARCH_x86",
        ])
        .arg("-I")
        .arg(&inc)
        .arg("-I")
        .arg("src/bpf")
        .arg("-c")
        .arg(src)
        .arg("-o")
        .arg(&obj)
        .status()
        .unwrap_or_else(|e| panic!("could not run {clang}: {e}"));
    assert!(status.success(), "{clang} failed to build {src}");
}

// The directory holding vmlinux.h, which the object includes.
fn vmlinux_dir(out: &Path) -> PathBuf {
    if let Some(dir) = env::var_os("SENSOR_VMLINUX_DIR") {
        return PathBuf::from(dir);
    }
    // kernel-devel installs one per kernel under /usr/src/kernels; any recent one does, since the object
    // is CO-RE
    if let Ok(entries) = fs::read_dir("/usr/src/kernels") {
        for entry in entries.flatten() {
            let header = entry.path().join("vmlinux.h");
            if header.is_file() {
                return entry.path();
            }
        }
    }
    // Last resort: dump the running kernel's BTF, where there is one
    let header = out.join("vmlinux.h");
    let dump = Command::new("bpftool")
        .args(["btf", "dump", "file", "/sys/kernel/btf/vmlinux", "format", "c"])
        .output();
    if let Ok(dump) = dump {
        if dump.status.success() && !dump.stdout.is_empty() {
            fs::write(&header, dump.stdout).expect("write vmlinux.h");
            return out.to_path_buf();
        }
    }
    panic!(
        "no vmlinux.h: set SENSOR_VMLINUX_DIR, install kernel-devel, or provide /sys/kernel/btf/vmlinux"
    );
}
