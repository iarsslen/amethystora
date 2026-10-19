//! The hand-off to a terminal: a command the agent cannot run itself (one that asks questions, or a root
//! command in the `terminal` mode) opens in a terminal for the person at the machine, through
//! amethystora-in-terminal --agent --report, which shows it and the agent's reason and runs it only after a
//! yes. How it ended comes back through a folder of the account's own: the call returns at once with an id,
//! and `history` with that id waits for the result.

use std::os::unix::fs::DirBuilderExt;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::history::Jobs;
use crate::{run, text};

pub const IN_TERMINAL: &str = "/usr/libexec/amethystora-in-terminal";
/// How long a hand-off waits for the person at the machine
const PATIENCE: Duration = Duration::from_secs(3600);

/// The folder a hand-off's result comes back through
pub fn dir(id: &str) -> PathBuf {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })));
    runtime.join("amethystora/agent-tools").join(id)
}

/// Whether there is a desktop to open a terminal on
pub fn graphical() -> bool {
    ["WAYLAND_DISPLAY", "DISPLAY"].iter().any(|name| std::env::var_os(name).is_some_and(|value| !value.is_empty()))
}

/// How a finished hand-off ended, in words for the agent, or None while it still waits
pub fn result(id: &str) -> Option<String> {
    let dir = dir(id);
    let status = std::fs::read_to_string(dir.join("status")).ok()?;
    let status = status.trim();
    if status == "declined" {
        return Some("The user declined: it was not run.".into());
    }
    let output = std::fs::read(dir.join("output")).unwrap_or_default();
    let output = run::strip_ansi(&String::from_utf8_lossy(&output));
    let lines: Vec<String> = run::tail(&output, 4096).lines().map(str::to_string).collect();
    let mut said = format!("It ran in the terminal and exited with {status}.");
    if !lines.is_empty() {
        said.push('\n');
        said.push_str(&text::data_block("What it printed, last 4 KB", &lines));
    }
    Some(said)
}

/// Opens `argv` in a terminal with the agent's reason, and starts a job that ends when the person has
/// answered and it has run. The id is the job's and the record's; `ended` is told how it ended, first.
pub fn open(jobs: &Jobs, id: &str, argv: &[String], reason: &str, ended: Box<dyn FnOnce(&str) + Send>) -> Result<(), String> {
    if !graphical() {
        return Err("There is no desktop session to open a terminal in: the user runs it themselves.".into());
    }
    let dir = dir(id);
    std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&dir)
        .map_err(|error| format!("{}: {error}", dir.display()))?;
    let mut child = Command::new(IN_TERMINAL)
        .arg("--agent")
        .arg(text::field(reason, 600))
        .arg("--report")
        .arg(&dir)
        .arg("--")
        .args(argv)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .map_err(|error| format!("{IN_TERMINAL}: {error}"))?;
    jobs.start(id);
    let jobs = jobs.clone();
    let id = id.to_string();
    std::thread::spawn(move || {
        // The terminal launcher returns at once; the command's result comes through the folder
        let _ = child.wait();
        let started = Instant::now();
        let said = loop {
            if let Some(said) = result(&id) {
                break said;
            }
            if started.elapsed() > PATIENCE {
                break "Nobody answered in the terminal within an hour.".to_string();
            }
            std::thread::sleep(Duration::from_millis(500));
        };
        ended(&said);
        jobs.finish(&id, said);
    });
    Ok(())
}
