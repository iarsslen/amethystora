//! Running the helpers the tools read: an argument vector, never through a shell, with nothing on standard
//! input, a time limit, and what it prints capped. Every answer is in English (LANGUAGE=en), so that its ids
//! and words are the same in every session's language. The slow answers are kept for a minute.

use std::collections::HashMap;
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

/// What a program said, and how it ended: its exit code, or None when it was stopped or could not start
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Output {
    pub code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
}

impl Output {
    pub fn ok(&self) -> bool {
        self.code == Some(0)
    }
}

/// The most read from either stream: every JSON helper says far less
const CAP: usize = 8 << 20;

fn read_capped(mut stream: impl Read + Send + 'static) -> thread::JoinHandle<Vec<u8>> {
    thread::spawn(move || {
        let mut kept = Vec::new();
        let mut buffer = [0u8; 65536];
        while let Ok(n) = stream.read(&mut buffer) {
            if n == 0 {
                break;
            }
            if kept.len() < CAP {
                kept.extend_from_slice(&buffer[..n.min(CAP - kept.len())]);
            }
        }
        kept
    })
}

/// Runs `argv` with `extra` added to its environment, for at most `timeout`. It runs in a process group of
/// its own, which is stopped whole when the time is up.
pub fn run_env(argv: &[&str], extra: &[(&str, &str)], timeout: Duration) -> Output {
    let Some((program, args)) = argv.split_first() else {
        return Output::default();
    };
    let mut command = Command::new(program);
    command.args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).env("LANGUAGE", "en").process_group(0);
    for (key, value) in extra {
        command.env(key, value);
    }
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => return Output { code: None, stdout: String::new(), stderr: format!("{program}: {error}"), timed_out: false },
    };
    let stdout = read_capped(child.stdout.take().expect("piped"));
    let stderr = read_capped(child.stderr.take().expect("piped"));
    let deadline = Instant::now() + timeout;
    let mut timed_out = false;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) if Instant::now() >= deadline => {
                timed_out = true;
                // The whole group, so that what it started stops too
                unsafe { libc::kill(-(child.id() as i32), libc::SIGKILL) };
                break child.wait().ok();
            }
            Ok(None) => thread::sleep(Duration::from_millis(15)),
            Err(_) => break None,
        }
    };
    let stdout = String::from_utf8_lossy(&stdout.join().unwrap_or_default()).into_owned();
    let stderr = String::from_utf8_lossy(&stderr.join().unwrap_or_default()).into_owned();
    Output { code: if timed_out { None } else { status.and_then(|status| status.code()) }, stdout, stderr, timed_out }
}

pub fn run(argv: &[&str], timeout: Duration) -> Output {
    run_env(argv, &[], timeout)
}

/// Answers kept for a minute within one server, for the helpers that take seconds to answer
pub struct Cache {
    kept: Mutex<HashMap<Vec<String>, (Instant, Output)>>,
}

const KEPT: Duration = Duration::from_secs(60);

impl Default for Cache {
    fn default() -> Self {
        Cache { kept: Mutex::new(HashMap::new()) }
    }
}

impl Cache {
    pub fn run(&self, argv: &[&str], timeout: Duration) -> Output {
        let key: Vec<String> = argv.iter().map(|arg| arg.to_string()).collect();
        if let Some((when, output)) = self.kept.lock().expect("not poisoned").get(&key) {
            if when.elapsed() < KEPT {
                return output.clone();
            }
        }
        let output = run(argv, timeout);
        if output.ok() {
            self.kept.lock().expect("not poisoned").insert(key, (Instant::now(), output.clone()));
        }
        output
    }

    /// What a change may have changed is read afresh next time
    pub fn forget(&self) {
        self.kept.lock().expect("not poisoned").clear();
    }
}

/// The end of what a command printed, at most `max` bytes, cut at a character
pub fn tail(text: &str, max: usize) -> &str {
    if text.len() <= max {
        return text;
    }
    let mut at = text.len() - max;
    while !text.is_char_boundary(at) {
        at += 1;
    }
    &text[at..]
}

/// Terminal colour codes and the like, which some commands write even into a pipe
pub fn strip_ansi(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            match chars.peek() {
                Some('[') => {
                    chars.next();
                    while let Some(&next) = chars.peek() {
                        chars.next();
                        if ('@'..='~').contains(&next) {
                            break;
                        }
                    }
                }
                Some(']') => {
                    // An operating system command, up to BEL or ESC \
                    chars.next();
                    while let Some(next) = chars.next() {
                        if next == '\u{7}' || (next == '\u{1b}' && chars.peek() == Some(&'\\')) {
                            if next == '\u{1b}' {
                                chars.next();
                            }
                            break;
                        }
                    }
                }
                _ => {
                    chars.next();
                }
            }
            continue;
        }
        if c == '\r' {
            continue;
        }
        out.push(c);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runs_and_stops_in_time() {
        let output = run(&["sh", "-c", "echo hi; echo err >&2; exit 3"], Duration::from_secs(5));
        assert_eq!(output.code, Some(3));
        assert_eq!(output.stdout, "hi\n");
        assert_eq!(output.stderr, "err\n");
        let started = Instant::now();
        let output = run(&["sh", "-c", "sleep 30 & sleep 30"], Duration::from_millis(300));
        assert!(output.timed_out && output.code.is_none());
        assert!(started.elapsed() < Duration::from_secs(5));
        assert!(run(&["/nonexistent/program"], Duration::from_secs(1)).stderr.contains("nonexistent"));
        assert_eq!(run_env(&["sh", "-c", "echo $LANGUAGE $X"], &[("X", "y")], Duration::from_secs(5)).stdout, "en y\n");
    }

    #[test]
    fn keeps_the_tail_and_strips_colours() {
        assert_eq!(tail("abcdef", 3), "def");
        assert_eq!(tail("ab", 3), "ab");
        assert_eq!(tail("aé", 1), "");
        assert_eq!(strip_ansi("\u{1b}[1;31mred\u{1b}[0m\r\n\u{1b}]0;title\u{7}x"), "red\nx");
    }
}
