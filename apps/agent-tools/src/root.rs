//! The tool server's side of the agent's root commands: amethystora-agent-root, started with pkexec in the mode
//! the administrator chose (agent.conf's ROOT), and talked to over a socket pair on its stdin and stdout. A
//! pipe would not do: any process of the account could open it through /proc/PID/fd. A socket cannot be
//! opened that way, and pkexec closes every other descriptor.
//!
//! In the `session` mode one helper, behind one password, serves every root command of this server until the
//! agent ends, the screen locks, an hour passes without one, or agent.conf changes; then the next command asks
//! again. In `minutes` and `each` a helper is started for each command, and polkit's keep (five minutes, for
//! this process alone) or no keep decides whether the password is asked again.

use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;

use serde_json::{Value, json};

use crate::policy::RootMode;

pub const HELPER: &str = "/usr/libexec/amethystora-agent-root";
const PKEXEC: &str = "/usr/bin/pkexec";
/// The helper's own limit is ten minutes a command; the password can take as long again
const PATIENCE: Duration = Duration::from_secs(1500);

struct Helper {
    child: Child,
    reader: BufReader<UnixStream>,
    writer: UnixStream,
}

impl Helper {
    fn start(mode: RootMode) -> Result<Helper, String> {
        if !std::path::Path::new(HELPER).exists() {
            return Err("the root helper is not installed on this image".into());
        }
        let (ours, theirs) = UnixStream::pair().map_err(|error| error.to_string())?;
        let input = theirs.try_clone().map_err(|error| error.to_string())?;
        let child = Command::new(PKEXEC)
            .arg(HELPER)
            .arg(mode.word())
            .stdin(Stdio::from(OwnedFd::from(input)))
            .stdout(Stdio::from(OwnedFd::from(theirs)))
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|error| format!("{PKEXEC}: {error}"))?;
        ours.set_read_timeout(Some(PATIENCE)).map_err(|error| error.to_string())?;
        let writer = ours.try_clone().map_err(|error| error.to_string())?;
        Ok(Helper { child, reader: BufReader::new(ours), writer })
    }

    /// One request and its answer. None when the helper ended first: the password was not given, or it ended
    /// its session.
    fn ask(&mut self, request: &Value) -> Option<Value> {
        writeln!(self.writer, "{request}").ok()?;
        self.writer.flush().ok()?;
        let mut line = String::new();
        match self.reader.read_line(&mut line) {
            Ok(n) if n > 0 => serde_json::from_str(&line).ok(),
            _ => None,
        }
    }

    /// Why it ended, from what pkexec said
    fn ended(mut self) -> String {
        // Both halves of the socket close, or the helper would wait for a request forever
        drop(self.writer);
        drop(self.reader);
        let status = self.child.wait().ok().and_then(|status| status.code());
        let mut said = String::new();
        if let Some(mut stderr) = self.child.stderr.take() {
            let _ = stderr.read_to_string(&mut said);
        }
        match status {
            Some(126) => "The administrator's password was not given: it was not run.".into(),
            Some(127) => "Not allowed: the password was refused, or polkit does not allow it.".into(),
            _ => {
                let said = crate::text::field(said.trim(), 300);
                if said.is_empty() { "The root helper ended without an answer.".into() } else { format!("The root helper ended: {said}") }
            }
        }
    }
}

#[derive(Default)]
pub struct Root {
    session: Mutex<Option<Helper>>,
}

impl Root {
    /// Runs `argv` as root in `mode` and gives the helper's answer: {status, output} or {refused}
    pub fn run(&self, mode: RootMode, id: &str, argv: &[String], reason: &str) -> Result<Value, String> {
        let request = json!({"id": id, "argv": argv, "reason": reason});
        match mode {
            RootMode::Terminal => Err("root commands open in a terminal in this mode".into()),
            RootMode::Session => {
                let mut session = self.session.lock().expect("not poisoned");
                // A helper that ended its session (the screen locked, an hour passed) is started again, which asks
                // for the password again
                for _ in 0..2 {
                    if session.as_mut().is_none_or(|helper| helper.child.try_wait().ok().flatten().is_some()) {
                        if let Some(old) = session.take() {
                            let _ = old.ended();
                        }
                        *session = Some(Helper::start(mode)?);
                    }
                    let helper = session.as_mut().expect("started");
                    if let Some(answer) = helper.ask(&request) {
                        return Ok(answer);
                    }
                    let ended = session.take().expect("there").ended();
                    if ended.contains("password") || ended.contains("Not allowed") {
                        return Err(ended);
                    }
                }
                Err("The root helper could not be started.".into())
            }
            RootMode::Minutes | RootMode::Each => {
                let mut helper = Helper::start(mode)?;
                match helper.ask(&request) {
                    Some(answer) => {
                        let _ = helper.ended();
                        Ok(answer)
                    }
                    None => Err(helper.ended()),
                }
            }
        }
    }

    /// Ends the session's helper, as when the server ends
    pub fn close(&self) {
        if let Some(helper) = self.session.lock().expect("not poisoned").take() {
            let _ = helper.ended();
        }
    }
}
