//! The `logs` tool: the journal, as the Logs app reads it (apps/logs), as the user. A unit, program or search
//! only ever reaches journalctl as the value of its own option, --unit=, --user-unit=, --identifier= or
//! --grep=, and never as a pattern: what the agent sends cannot become an option or match every unit.
//! Repeated lines are collapsed (×N), times are made relative, and every line is handed on marked as data,
//! since anything running here can write anything to the journal.

use std::time::Duration;

use serde_json::Value;

use crate::history::ago;
use crate::run;
use crate::state::unit_name;
use crate::text;

#[derive(Debug, Default, Clone)]
pub struct Request {
    pub unit: Option<String>,
    pub user_unit: Option<String>,
    pub identifier: Option<String>,
    pub priority: Option<String>,
    pub boot: Option<i64>,
    pub since: Option<String>,
    pub grep: Option<String>,
    pub lines: usize,
}

const PRIORITIES: [&str; 8] = ["emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"];

/// A time journalctl takes for --since, in the few forms the tool allows: -2h, today, 2026-10-19 08:00
fn since_ok(since: &str) -> bool {
    let relative = since.strip_prefix('-').is_some_and(|rest| {
        rest.len() >= 2 && rest[..rest.len() - 1].chars().all(|c| c.is_ascii_digit()) && rest.ends_with(['s', 'm', 'h', 'd'])
    });
    relative
        || matches!(since, "today" | "yesterday")
        || (since.len() <= 19 && !since.is_empty() && since.chars().all(|c| c.is_ascii_digit() || matches!(c, '-' | ':' | ' ')) && since.starts_with(|c: char| c.is_ascii_digit()))
}

/// The journalctl arguments for a request, or why it cannot be made
pub fn arguments(request: &Request) -> Result<Vec<String>, String> {
    let mut args = vec!["--no-pager".to_string(), "-o".into(), "json".into(), "--output-fields=MESSAGE,SYSLOG_IDENTIFIER,_COMM,PRIORITY".into()];
    let lines = request.lines.clamp(1, 50);
    // Read more than is shown, so that collapsed repeats still leave as many lines
    args.push(format!("--lines={}", lines * 4));
    for (value, option) in [(&request.unit, "--unit"), (&request.user_unit, "--user-unit"), (&request.identifier, "--identifier")] {
        if let Some(value) = value {
            if !unit_name(value) {
                return Err(format!("{option} takes a name such as NetworkManager.service, with no pattern"));
            }
            args.push(format!("{option}={value}"));
        }
    }
    if let Some(priority) = &request.priority {
        let known = PRIORITIES.contains(&priority.as_str()) || (priority.len() == 1 && priority.chars().all(|c| ('0'..='7').contains(&c)));
        if !known {
            return Err(format!("priority is one of {}", PRIORITIES.join(", ")));
        }
        args.push(format!("--priority={priority}"));
    }
    match request.boot {
        Some(boot) if (-20..=0).contains(&boot) => args.push(format!("--boot={boot}")),
        Some(_) => return Err("boot is 0 (this one) to -20".into()),
        None if request.since.is_none() => args.push("--boot=0".into()),
        None => {}
    }
    if let Some(since) = &request.since {
        if !since_ok(since) {
            return Err("since is like -2h, -30m, -1d, today, yesterday or 2026-10-19 08:00".into());
        }
        args.push(format!("--since={since}"));
    }
    if let Some(grep) = &request.grep {
        if grep.is_empty() || grep.len() > 200 {
            return Err("grep is 1 to 200 characters".into());
        }
        args.push(format!("--grep={grep}"));
        args.push("--case-sensitive=false".into());
    }
    Ok(args)
}

/// A journal field, which is a string, or bytes when it is not UTF-8
fn field(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Array(bytes) => String::from_utf8_lossy(&bytes.iter().filter_map(|b| b.as_u64().map(|b| b as u8)).collect::<Vec<_>>()).into_owned(),
        _ => String::new(),
    }
}

/// journalctl's JSON lines as the tool shows them: oldest first, repeats collapsed, at most `lines`
pub fn collapse(json_lines: &str, lines: usize) -> Vec<String> {
    let mut out: Vec<(String, u64, usize)> = Vec::new();
    for line in json_lines.lines() {
        let Ok(entry) = serde_json::from_str::<Value>(line) else { continue };
        let who = [&entry["SYSLOG_IDENTIFIER"], &entry["_COMM"]].into_iter().map(field).find(|who| !who.is_empty()).unwrap_or_default();
        let level = field(&entry["PRIORITY"]).parse::<usize>().ok().and_then(|p| PRIORITIES.get(p)).map(|p| format!(" {p}")).unwrap_or_default();
        let text = format!("[{}{level}] {}", text::field(&who, 60), text::field(&field(&entry["MESSAGE"]), 500));
        let time = field(&entry["__REALTIME_TIMESTAMP"]).parse::<u64>().unwrap_or(0) / 1_000_000;
        match out.last_mut() {
            Some((last, at, count)) if *last == text => {
                *count += 1;
                *at = time;
            }
            _ => out.push((text, time, 1)),
        }
    }
    let start = out.len().saturating_sub(lines);
    out[start..]
        .iter()
        .map(|(text, time, count)| {
            let repeat = if *count > 1 { format!(" ×{count}") } else { String::new() };
            format!("{} ago {text}{repeat}", ago(*time))
        })
        .collect()
}

pub fn read(request: &Request) -> Result<String, String> {
    let args = arguments(request)?;
    let mut argv: Vec<&str> = vec!["journalctl"];
    argv.extend(args.iter().map(String::as_str));
    let output = run::run(&argv, Duration::from_secs(30));
    if !output.ok() && output.stdout.is_empty() {
        let said = text::field(output.stderr.trim(), 300);
        return Err(if said.is_empty() { "journalctl found nothing it could read".into() } else { said });
    }
    let lines = collapse(&output.stdout, request.lines.clamp(1, 50));
    if lines.is_empty() {
        return Ok("No journal lines match.".into());
    }
    Ok(text::data_block("Journal, oldest first", &lines))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn values_never_become_options() {
        let request = Request { unit: Some("NetworkManager.service".into()), grep: Some("--all".into()), lines: 10, ..Default::default() };
        let args = arguments(&request).unwrap();
        assert!(args.contains(&"--unit=NetworkManager.service".to_string()));
        assert!(args.contains(&"--grep=--all".to_string()));
        assert!(args.contains(&"--boot=0".to_string()));
        assert!(arguments(&Request { unit: Some("*".into()), ..Default::default() }).is_err());
        assert!(arguments(&Request { unit: Some("-a".into()), ..Default::default() }).is_err());
        assert!(arguments(&Request { priority: Some("loud".into()), ..Default::default() }).is_err());
        assert!(arguments(&Request { since: Some("-2h".into()), ..Default::default() }).unwrap().contains(&"--since=-2h".to_string()));
        assert!(arguments(&Request { since: Some("$(id)".into()), ..Default::default() }).is_err());
        assert!(arguments(&Request { boot: Some(5), ..Default::default() }).is_err());
        assert!(arguments(&Request { lines: 500, ..Default::default() }).unwrap().contains(&"--lines=200".to_string()));
    }

    #[test]
    fn collapses_repeats_and_cleans_lines() {
        let now = crate::history::now() * 1_000_000;
        let line = |message: &str| format!("{{\"__REALTIME_TIMESTAMP\":\"{now}\",\"SYSLOG_IDENTIFIER\":\"app\",\"PRIORITY\":\"3\",\"MESSAGE\":\"{message}\"}}");
        let journal = [line("same"), line("same"), line("same"), line("other\\u001b[31m")].join("\n");
        let shown = collapse(&journal, 50);
        assert_eq!(shown, ["0s ago [app err] same ×3", "0s ago [app err] other[31m"]);
        assert_eq!(collapse(&journal, 1).len(), 1);
        let bytes = format!("{{\"__REALTIME_TIMESTAMP\":\"{now}\",\"_COMM\":\"x\",\"MESSAGE\":[104,105]}}");
        assert_eq!(collapse(&bytes, 5), ["0s ago [x] hi"]);
    }
}
