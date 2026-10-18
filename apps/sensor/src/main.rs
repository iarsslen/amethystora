//! amethystora-sensor: watches the files and operations the audit rules watch, recorded where they happen
//! rather than at every system call (PLAN-audit-cost.md). It loads a small set of BPF tracing programs on
//! the kernel's LSM entry points and a couple of tracepoints, matches by the inode of each watched folder,
//! and writes what it finds as the kernel's own audit records, which the security watcher reads with the
//! same ausearch code it uses for auditd.
//!
//!   amethystora-sensor              run (the service)
//!   amethystora-sensor --check      exit 0 when it is wanted: AUDIT_LOG and WATCHER on, and the plan gives
//!                                   it at least one key (ExecCondition=)
//!   amethystora-sensor --keys       the audit keys it can cover, one a line (20-tests.sh checks these)
//!   amethystora-sensor --probe      load and attach every program, then stop; for the generator to learn
//!                                   whether this kernel takes the sensor before it writes the plan
//!   amethystora-sensor --records    read JSON events on stdin and write their audit records to stdout, with
//!                                   no BPF, so the record writer can be tested against ausearch

mod config;
mod event;
mod keys;
mod plan;
mod record;
mod refused;

#[cfg(not(test))]
mod bpf;
#[cfg(not(test))]
mod run;

use std::io::{self, Read, Write};
use std::process::ExitCode;

fn main() -> ExitCode {
    let arg = std::env::args().nth(1);
    match arg.as_deref() {
        Some("--keys") => {
            let out = keys::KEYS.iter().map(|k| k.name).collect::<Vec<_>>().join("\n");
            println!("{out}");
            ExitCode::SUCCESS
        }
        Some("--check") => {
            if check() {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        Some("--records") => match records() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("amethystora-sensor --records: {e}");
                ExitCode::FAILURE
            }
        },
        Some("--probe") => run_mode(true),
        None => run_mode(false),
        Some(other) => {
            eprintln!("usage: amethystora-sensor [--check | --keys | --probe | --records]");
            eprintln!("  (unknown argument {other})");
            ExitCode::from(64)
        }
    }
}

/// Whether the sensor is wanted now: the audit log and the watcher on, and at least one key given to it.
fn check() -> bool {
    config::is("AUDIT_LOG", "on") && config::is("WATCHER", "on") && plan::any_sensor_key()
}

#[cfg(not(test))]
fn run_mode(probe: bool) -> ExitCode {
    match run::run(probe) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("amethystora-sensor: {e}");
            ExitCode::FAILURE
        }
    }
}

// Under `cargo test` the BPF object is not built, so run is not compiled; the record writer and the parsers
// are what the unit tests exercise.
#[cfg(test)]
fn run_mode(_probe: bool) -> ExitCode {
    ExitCode::FAILURE
}

/// Reads JSON events, one per line, and writes their audit records. For build_files/shared/test-sensor-records.sh.
fn records() -> io::Result<()> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let stdout = io::stdout();
    let mut out = stdout.lock();
    let mut serial = 1u64;
    for line in input.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let value: serde_json::Value =
            serde_json::from_str(line).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;
        let mut rec = record_from_json(&value);
        if rec.time_ns == 0 {
            rec.time_ns = now;
        }
        record::write_event(&mut out, &rec, serial)?;
        serial += 1;
    }
    out.flush()
}

/// Builds a `Record` from a JSON event. Lenient: anything missing is a zero or an empty string, so a test
/// gives only the fields its case needs.
fn record_from_json(v: &serde_json::Value) -> record::Record {
    use serde_json::Value;
    let u32f = |name: &str| v.get(name).and_then(Value::as_u64).unwrap_or(0) as u32;
    let bytes = |name: &str| v.get(name).and_then(Value::as_str).unwrap_or("").as_bytes().to_vec();
    // An octal string like "040755", or a number.
    let octal = |name: &str| match v.get(name) {
        Some(Value::String(s)) => u32::from_str_radix(s.trim_start_matches("0o"), 8).unwrap_or(0),
        Some(Value::Number(n)) => n.as_u64().unwrap_or(0) as u32,
        _ => 0,
    };
    let mut keys_mask = 0u32;
    if let Some(Value::Array(names)) = v.get("keys") {
        for name in names {
            if let Some(name) = name.as_str() {
                if name == keys::SENSOR_NAME {
                    keys_mask |= 1 << keys::SENSOR_BIT;
                } else if let Some(bit) = keys::bit_of(name) {
                    keys_mask |= 1 << bit;
                }
            }
        }
    }
    let mut args = [0u64; 4];
    if let Some(Value::Array(a)) = v.get("args") {
        for (i, arg) in a.iter().take(4).enumerate() {
            args[i] = match arg {
                Value::String(s) => u64::from_str_radix(s.trim_start_matches("0x"), 16).unwrap_or(0),
                Value::Number(n) => n.as_u64().unwrap_or(0),
                _ => 0,
            };
        }
    }
    let argv = v
        .get("argv")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|x| x.as_str()).map(|s| s.as_bytes().to_vec()).collect::<Vec<_>>())
        .unwrap_or_default();
    record::Record {
        op: u32f("op"),
        syscall: u32f("syscall"),
        result: v.get("result").and_then(Value::as_i64).unwrap_or(0),
        keys: keys_mask,
        args,
        pid: v.get("pid").and_then(Value::as_u64).map_or(11, |x| x as u32),
        ppid: v.get("ppid").and_then(Value::as_u64).map_or(10, |x| x as u32),
        auid: v.get("auid").and_then(Value::as_u64).map_or(1000, |x| x as u32),
        ses: u32f("ses"),
        uid: u32f("uid"),
        gid: u32f("gid"),
        euid: u32f("euid"),
        suid: u32f("suid"),
        fsuid: u32f("fsuid"),
        egid: u32f("egid"),
        sgid: u32f("sgid"),
        fsgid: u32f("fsgid"),
        comm: if v.get("comm").is_some() { bytes("comm") } else { b"x".to_vec() },
        tty: bytes("tty"),
        exe: bytes("exe"),
        cwd: bytes("cwd"),
        flags: u32f("flags"),
        obj_mode: octal("mode"),
        obj_ino: v.get("ino").and_then(Value::as_u64).unwrap_or(0),
        obj_ouid: u32f("ouid"),
        obj_ogid: u32f("ogid"),
        obj_dev: v.get("dev").and_then(Value::as_str).unwrap_or("00:2a").to_string(),
        obj_rdev: v.get("rdev").and_then(Value::as_str).unwrap_or("00:00").to_string(),
        parent_mode: octal("parent_mode"),
        dir: bytes("dir"),
        name: bytes("name"),
        dir2: bytes("dir2"),
        name2: bytes("name2"),
        path2: bytes("path2"),
        argc: v.get("argc").and_then(Value::as_u64).map_or(argv.len() as u32, |x| x as u32),
        argv,
        module: bytes("module"),
        time_ns: v.get("time").and_then(Value::as_u64).map(|s| s as u128 * 1_000_000_000).unwrap_or(0),
    }
}
