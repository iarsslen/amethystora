//! What the tools changed: one JSON line per change in ~/.local/state/amethystora/agent-tools/actions.jsonl
//! (0600), with the state before it and how to undo it, never what a command printed. A change that takes
//! longer than a tool call may (an install, a root command, a terminal the user answers) is a job: the call
//! returns its id at once, and `history` with that id waits for it.

use std::collections::HashMap;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};

use crate::policy;

pub fn state_dir() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| policy::home().join(".local/state"));
    base.join("amethystora/agent-tools")
}

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// A short id nobody else picks: eight hex digits from the kernel's random numbers
pub fn new_id() -> String {
    let mut bytes = [0u8; 4];
    if let Ok(mut random) = std::fs::File::open("/dev/urandom") {
        let _ = std::io::Read::read_exact(&mut random, &mut bytes);
    }
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Adds a record. It is the account's own file, readable by it alone.
pub fn record(entry: &Value) -> Result<(), String> {
    let dir = state_dir();
    std::fs::create_dir_all(&dir).map_err(|error| format!("{}: {error}", dir.display()))?;
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(dir.join("actions.jsonl"))
        .map_err(|error| error.to_string())?;
    writeln!(file, "{entry}").map_err(|error| error.to_string())
}

/// Every record, oldest first
pub fn records() -> Vec<Value> {
    std::fs::read_to_string(state_dir().join("actions.jsonl"))
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

/// The latest record of a change, by its id: a job writes its record again when it ends
pub fn find(id: &str) -> Option<Value> {
    records().into_iter().rev().find(|record| record["id"] == id)
}

/// How long ago, in a few characters: 40s, 5m, 3h, 2d
pub fn ago(seconds: u64) -> String {
    let elapsed = now().saturating_sub(seconds);
    match elapsed {
        0..60 => format!("{elapsed}s"),
        60..3600 => format!("{}m", elapsed / 60),
        3600..86400 => format!("{}h", elapsed / 3600),
        _ => format!("{}d", elapsed / 86400),
    }
}

/// A record as one line for people and agents
pub fn line(record: &Value) -> String {
    let what = match record["tool"].as_str().unwrap_or("") {
        "change" => format!("change {}={} (was {})", record["entry"].as_str().unwrap_or("?"), record["value"].as_str().unwrap_or("?"),
            record["before"].as_str().unwrap_or("?")),
        "software" => format!("software {} {} {}", record["action"].as_str().unwrap_or("?"), record["source"].as_str().unwrap_or("?"),
            record["name"].as_str().unwrap_or("?")),
        "run" => format!("run{} {}", if record["root"] == true { " as root" } else { "" }, words(&record["argv"])),
        "undo" => format!("undo of {}", record["of"].as_str().unwrap_or("?")),
        other => other.to_string(),
    };
    let result = record["result"].as_str().unwrap_or("?");
    let undo = if record["undo"].is_object() { ", can be undone" } else { "" };
    format!("{} {} ago: {what} -> {result}{undo}", record["id"].as_str().unwrap_or("?"), ago(record["time"].as_u64().unwrap_or(0)))
}

/// An argument vector as one line, each word quoted when it needs to be
pub fn words(argv: &Value) -> String {
    argv.as_array()
        .map(|list| list.iter().filter_map(Value::as_str).map(quote).collect::<Vec<_>>().join(" "))
        .unwrap_or_default()
}

/// A word as a shell would need it to be the one word it is
pub fn quote(word: &str) -> String {
    if !word.is_empty() && word.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '/' | ':' | '=' | '@' | '+' | ',')) {
        word.to_string()
    } else {
        format!("'{}'", word.replace('\'', "'\\''"))
    }
}

/// The jobs of this server, by id: running until their result is set
#[derive(Default, Clone)]
pub struct Jobs {
    done: Arc<(Mutex<HashMap<String, Option<String>>>, Condvar)>,
}

impl Jobs {
    pub fn start(&self, id: &str) {
        self.done.0.lock().expect("not poisoned").insert(id.to_string(), None);
    }

    pub fn finish(&self, id: &str, result: String) {
        let (lock, wake) = &*self.done;
        lock.lock().expect("not poisoned").insert(id.to_string(), Some(result));
        wake.notify_all();
    }

    pub fn known(&self, id: &str) -> bool {
        self.done.0.lock().expect("not poisoned").contains_key(id)
    }

    /// The job's result, waiting at most `wait` for it; None while it still runs
    pub fn wait(&self, id: &str, wait: Duration) -> Option<String> {
        let (lock, wake) = &*self.done;
        let jobs = lock.lock().expect("not poisoned");
        let (jobs, _) = wake.wait_timeout_while(jobs, wait, |jobs| matches!(jobs.get(id), Some(None))).expect("not poisoned");
        jobs.get(id).cloned().flatten()
    }
}

/// A record of a change as it starts
pub fn started(id: &str, tool: &str, fields: Value) -> Value {
    let mut entry = json!({"id": id, "time": now(), "tool": tool, "result": "running"});
    if let (Some(entry), Some(fields)) = (entry.as_object_mut(), fields.as_object()) {
        for (key, value) in fields {
            entry.insert(key.clone(), value.clone());
        }
    }
    entry
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_and_says_records() {
        assert_eq!(quote("rpm-ostree"), "rpm-ostree");
        assert_eq!(quote("a b"), "'a b'");
        assert_eq!(quote("it's"), "'it'\\''s'");
        assert_eq!(quote(""), "''");
        let record = json!({"id": "ab12cd34", "time": now(), "tool": "change", "entry": "layout", "value": "classic", "before": "tiling",
            "result": "ok", "undo": {"tool": "change", "entry": "layout", "value": "tiling"}});
        assert_eq!(line(&record), "ab12cd34 0s ago: change layout=classic (was tiling) -> ok, can be undone");
        assert_eq!(words(&json!(["rpm-ostree", "install", "a b"])), "rpm-ostree install 'a b'");
    }

    #[test]
    fn jobs_wait_for_their_result() {
        let jobs = Jobs::default();
        jobs.start("x");
        assert_eq!(jobs.wait("x", Duration::from_millis(20)), None);
        let other = jobs.clone();
        let thread = std::thread::spawn(move || other.finish("x", "done".into()));
        assert_eq!(jobs.wait("x", Duration::from_secs(5)).as_deref(), Some("done"));
        thread.join().unwrap();
        assert!(!jobs.known("y"));
    }
}
