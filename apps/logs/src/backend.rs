//! What Amethystora Logs reads, and how: what main.js did for the Electron window. Everything is read with
//! journalctl, as the person at the machine: the members of wheel see the whole machine, anyone else their
//! own session and apps. Nothing here writes to the journal or changes what it keeps. What the page picks, a
//! view, a source, a time range, a level and a search, is turned into journalctl's arguments here, from
//! known choices: an app has to be one this window found in the journal itself, a service or program is
//! only ever the value of --unit, --user-unit or --identifier, and the search only ever the value of --grep.
//!
//! The journal can hold far more than a window should hold at once, so a page of entries is read as
//! journalctl writes it, a chunk at a time on the main loop, and each entry keeps only what its row shows
//! and the line it came from, which is read whole only when the entry is opened.

use std::borrow::Cow;
use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, HashMap};
use std::fmt;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::OnceLock;
use std::time::Duration;

use amethystora_ui::process::{self, Options, Output};
use amethystora_ui::{gio, glib, t};
use gio::prelude::*;
use regex::Regex;
use serde::de::{self, Deserializer, IgnoredAny, MapAccess, SeqAccess, Visitor};
use serde::Deserialize;
use serde_json::Value;

pub const IN_TERMINAL: &str = process::IN_TERMINAL;
/// The AI agent, which a crash or a service's errors can be handed to, unless the account turned it off
pub const AGENT: &str = "/usr/bin/amethystora-agent";
/// Entries read at a time, newest first; "Show older" reads the next as many
pub const PAGE: usize = 400;
/// An export keeps the newest this many entries of what is shown
pub const EXPORT_LINES: usize = 250000;
/// The badges count up to here and then say "999+"
pub const COUNT_CAP: usize = 1000;
/// What systemd-coredump logs a crash under
pub const COREDUMP: &str = "fc2e22bc6ee647b6b90729ab34a250b1";

/// The views of the sidebar, in its order
pub const CATEGORIES: [&str; 7] = ["important", "all", "session", "system", "kernel", "security", "crashes"];

/// Each view's own arguments. Security is the audit log and the auth and authpriv syslog facilities.
pub fn category_args(category: &str) -> Option<Vec<String>> {
    let args: &[&str] = match category {
        "important" | "all" => &[],
        "session" => &["--user"],
        "system" => &["--system"],
        "kernel" => &["_TRANSPORT=kernel"],
        "security" => &["_TRANSPORT=audit", "+", "SYSLOG_FACILITY=4", "+", "SYSLOG_FACILITY=10"],
        "crashes" => return Some(vec![format!("MESSAGE_ID={COREDUMP}")]),
        _ => return None,
    };
    Some(args.iter().map(|arg| arg.to_string()).collect())
}

/// The time ranges the page offers by name
pub fn range_args(range: &str) -> Option<&'static [&'static str]> {
    Some(match range {
        "boot" => &["--boot=0"],
        "previous" => &["--boot=-1"],
        "hour" => &["--since=-1h"],
        "day" => &["--since=-24h"],
        "week" => &["--since=-7d"],
        "all" => &[],
        _ => return None,
    })
}

/// The view to open: `amethystora-logs crashes` opens on the crashes, and so on
pub fn view_argument(args: &[String]) -> String {
    let view = args.iter().find(|arg| !arg.starts_with('-')).map(String::as_str).unwrap_or("");
    if view == "sources" || CATEGORIES.contains(&view) { view.to_string() } else { String::new() }
}

/// An argument as a shell would need it, for the command the page shows beside each view
pub fn quote(arg: &str) -> String {
    let plain = !arg.is_empty() && arg.chars().all(|c| c.is_ascii_alphanumeric() || "_@%+=:,./-".contains(c));
    if plain { arg.to_string() } else { format!("'{}'", arg.replace('\'', "'\\''")) }
}

// --- Apps and services -----------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    App,
    Unit,
    Identifier,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    User,
    System,
}

/// What a view can be narrowed to: an app, a service of the session or the system, or the name a program
/// logs under. `label` is what the page calls it.
#[derive(Debug, Clone, PartialEq)]
pub struct Source {
    pub kind: Kind,
    pub id: String,
    pub scope: Scope,
    pub label: String,
}

/// A service as the list of them shows it: templates with more than a few instances are listed once
#[derive(Debug, Clone, PartialEq)]
pub struct UnitItem {
    pub name: String,
    pub label: String,
    pub instances: Option<usize>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AppItem {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, Default)]
pub struct Sources {
    pub apps: Vec<AppItem>,
    pub user: Vec<UnitItem>,
    pub system: Vec<UnitItem>,
}

/// Apps and units found in the journal: the only sources a view can be narrowed to
#[derive(Debug, Clone, Default)]
struct Known {
    /// Each app's id and the patterns of the units it ran in, in the order they were found
    apps: Vec<(String, Vec<String>)>,
    user: Vec<UnitItem>,
    system: Vec<UnitItem>,
}

/// systemd writes "-" inside a name as \x2d, and anything else unusual the same way
pub fn unescape(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut at = 0;
    while at < text.len() {
        if bytes[at] == b'\\'
            && at + 3 < text.len()
            && bytes[at + 1] == b'x'
            && bytes[at + 2].is_ascii_hexdigit()
            && bytes[at + 3].is_ascii_hexdigit()
        {
            let value = u8::from_str_radix(&text[at + 2..at + 4], 16).unwrap_or(0);
            // String.fromCharCode: the byte as a character of its own
            out.push(char::from(value));
            at += 4;
            continue;
        }
        let c = text[at..].chars().next().unwrap_or(' ');
        out.push(c);
        at += c.len_utf8();
    }
    out
}

fn regex(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pattern).expect("a valid expression"))
}

// GNOME and Flatpak start every app in a unit of its own: app-gnome-org.gnome.Nautilus-4242.scope,
// app-flatpak-com.brave.Browser-1234.scope, and app-org.gnome.Evolution\x2dalarm\x2dnotify@autostart.service
// for what starts at login. One app has one such unit for each time it was started, and the pattern
// that matches all of them is what its logs are read by. journalctl matches the patterns against the
// journal's own unit names with FNM_NOESCAPE, so the backslash in \x2d stays one: doubled, it finds no
// unit and journalctl fails with "No data available".
fn app_unit() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    regex(&CELL, r"^app-(?:([a-z]+)-)?(.+?)(?:-[0-9]+\.scope|@[^/]*\.service)$")
}

/// The app a unit of the session ran, and the pattern every run of it matches
pub fn app_of(unit: &str) -> Option<(String, String)> {
    let captures = app_unit().captures(unit)?;
    let launcher = captures.get(1).map(|m| m.as_str());
    let escaped = captures.get(2)?.as_str();
    let prefix = format!("app-{}{}", launcher.map(|l| format!("{l}-")).unwrap_or_default(), escaped);
    let pattern = if unit.ends_with(".scope") { format!("{prefix}-*.scope") } else { format!("{prefix}@*.service") };
    let id = unescape(escaped);
    let id = id.strip_suffix(".desktop").map(str::to_string).unwrap_or(id);
    Some((id, pattern))
}

/// Units that only ever run once, and the scopes of login sessions and terminals: not worth listing
pub fn transient(unit: &str) -> bool {
    unit.starts_with("run-")
        || unit.strip_prefix("session-").is_some_and(|rest| rest.starts_with(|c: char| c.is_ascii_digit()))
        || unit.starts_with("vte-spawn-")
        || unit == "init.scope"
        || unit.starts_with("dbus-:")
}

/// A unit worth naming as where an entry came from
fn listed_service(unit: &str) -> bool {
    unit.ends_with(".service") && !transient(unit)
}

/// name@instance.type: the template and the type
fn template_of(unit: &str) -> Option<(&str, &str)> {
    let (name, rest) = unit.split_once('@')?;
    if name.is_empty() || rest.contains('@') {
        return None;
    }
    let dot = rest.rfind('.')?;
    let kind = &rest[dot..];
    (kind.len() > 1 && kind[1..].chars().all(|c| c.is_ascii_lowercase())).then_some((name, kind))
}

/// Sorted by name the way the page sorted them (localeCompare), with the language's own collation
fn sort_by_name<T>(list: &mut [T], name: impl Fn(&T) -> &str) {
    let collator = amethystora_ui::i18n::with(|i18n| i18n.collator());
    list.sort_by(|a, b| match &collator {
        Some(collator) => collator.compare(name(a), name(b)).then_with(|| name(a).cmp(name(b))),
        None => name(a).cmp(name(b)),
    });
}

/// Templates with more than a few instances, such as systemd-coredump@, listed once for all of them
pub fn collapse(units: &[String]) -> Vec<UnitItem> {
    let mut templates: HashMap<String, usize> = HashMap::new();
    for unit in units {
        if let Some((name, kind)) = template_of(unit) {
            *templates.entry(format!("{name}@*{kind}")).or_default() += 1;
        }
    }
    let mut listed: Vec<UnitItem> = Vec::new();
    let mut seen: HashMap<String, usize> = HashMap::new();
    for unit in units {
        let item = match template_of(unit) {
            Some((name, kind)) if templates[&format!("{name}@*{kind}")] > 3 => {
                let key = format!("{name}@*{kind}");
                UnitItem { label: format!("{name}@{kind}"), instances: Some(templates[&key]), name: key }
            }
            _ => UnitItem { name: unit.clone(), label: unit.clone(), instances: None },
        };
        match seen.get(&item.name) {
            Some(&at) => listed[at] = item,
            None => {
                seen.insert(item.name.clone(), listed.len());
                listed.push(item);
            }
        }
    }
    sort_by_name(&mut listed, |unit| &unit.label);
    listed
}

/// Where launchers are, the Flatpaks' among them, for the names of the apps
fn application_dirs() -> Vec<PathBuf> {
    let home = amethystora_ui::palette::home();
    let data = std::env::var_os("XDG_DATA_HOME").filter(|v| !v.is_empty()).map(PathBuf::from).unwrap_or_else(|| home.join(".local/share"));
    let dirs = std::env::var("XDG_DATA_DIRS").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    let mut list = vec![data.clone(), data.join("flatpak/exports/share"), PathBuf::from("/var/lib/flatpak/exports/share")];
    list.extend(dirs.split(':').filter(|dir| !dir.is_empty()).map(PathBuf::from));
    list.into_iter().map(|dir| dir.join("applications")).collect()
}

/// The Name= of a launcher's [Desktop Entry], or '' for one without
fn desktop_name(text: &str) -> String {
    // text.split(/^\[/m): a section begins with a line that starts with [
    let mut sections = Vec::new();
    let mut start = 0;
    for (at, _) in text.match_indices('[') {
        if at == 0 || text.as_bytes()[at - 1] == b'\n' {
            sections.push(&text[start..at]);
            start = at + 1;
        }
    }
    sections.push(&text[start..]);
    let entry = sections.into_iter().find(|part| part.starts_with("Desktop Entry]")).unwrap_or("");
    entry
        .lines()
        .find_map(|line| line.strip_prefix("Name=").filter(|rest| !rest.is_empty()))
        .map(|name| name.trim().to_string())
        .unwrap_or_default()
}

// --- One entry -------------------------------------------------------------------------------------

/// One entry of the journal, with what its row shows; every other field stays in the line journalctl wrote
#[derive(Debug, Clone)]
pub struct Entry {
    pub cursor: Rc<str>,
    /// Milliseconds since the epoch
    pub time: i64,
    pub priority: u8,
    pub source: String,
    pub message: String,
    pub from: Option<Source>,
    raw: Box<str>,
}

impl Entry {
    /// An entry with only a cursor and a time, for the list's tests
    #[cfg(test)]
    pub fn at(cursor: &str, time: i64) -> Entry {
        Entry { cursor: cursor.into(), time, priority: 6, source: String::new(), message: String::new(), from: None, raw: "{}".into() }
    }

    /// Every field of the entry, by name, as text
    pub fn fields(&self) -> BTreeMap<String, String> {
        match serde_json::from_str::<serde_json::Map<String, Value>>(&self.raw) {
            Ok(map) => map.into_iter().map(|(key, value)| (key, text(&value))).collect(),
            Err(_) => BTreeMap::new(),
        }
    }
}

/// A field as journalctl --output=json writes it: a string, the bytes of one that is not text, or a list
/// of either for a field an entry has more than once
pub fn text(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(text) => text.clone(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::Array(list) => {
            let integers: Option<Vec<u8>> = list.iter().map(|v| v.as_i64().map(|n| n as u8)).collect();
            match integers {
                Some(bytes) => String::from_utf8_lossy(&bytes).into_owned(),
                None => list.iter().map(text).collect::<Vec<_>>().join("\n"),
            }
        }
        Value::Object(_) => "[object Object]".into(),
    }
}

/// A field's value read straight into text, for the few fields a row needs
struct Text(String);

impl<'de> Deserialize<'de> for Text {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct TextVisitor;
        impl<'de> Visitor<'de> for TextVisitor {
            type Value = Text;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("a journal field")
            }
            fn visit_str<E: de::Error>(self, v: &str) -> Result<Text, E> {
                Ok(Text(v.to_string()))
            }
            fn visit_string<E: de::Error>(self, v: String) -> Result<Text, E> {
                Ok(Text(v))
            }
            fn visit_unit<E: de::Error>(self) -> Result<Text, E> {
                Ok(Text(String::new()))
            }
            fn visit_none<E: de::Error>(self) -> Result<Text, E> {
                Ok(Text(String::new()))
            }
            fn visit_bool<E: de::Error>(self, v: bool) -> Result<Text, E> {
                Ok(Text(v.to_string()))
            }
            fn visit_i64<E: de::Error>(self, v: i64) -> Result<Text, E> {
                Ok(Text(v.to_string()))
            }
            fn visit_u64<E: de::Error>(self, v: u64) -> Result<Text, E> {
                Ok(Text(v.to_string()))
            }
            fn visit_f64<E: de::Error>(self, v: f64) -> Result<Text, E> {
                Ok(Text(Value::from(v).to_string()))
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Text, A::Error> {
                let mut list = Vec::new();
                while let Some(value) = seq.next_element::<Value>()? {
                    list.push(value);
                }
                Ok(Text(text(&Value::Array(list))))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Text, A::Error> {
                while map.next_entry::<IgnoredAny, IgnoredAny>()?.is_some() {}
                Ok(Text("[object Object]".into()))
            }
        }
        deserializer.deserialize_any(TextVisitor)
    }
}

/// The fields a row is made of, read from an entry's line; the rest are skipped over
#[derive(Default)]
struct RowFields {
    cursor: Option<String>,
    realtime: String,
    priority: String,
    identifier: String,
    comm: String,
    transport: String,
    user_unit: String,
    unit: String,
    message: String,
}

impl<'de> Deserialize<'de> for RowFields {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Key(u8);
        impl<'de> Deserialize<'de> for Key {
            fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
                struct KeyVisitor;
                impl Visitor<'_> for KeyVisitor {
                    type Value = Key;
                    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                        f.write_str("a field name")
                    }
                    fn visit_str<E: de::Error>(self, v: &str) -> Result<Key, E> {
                        Ok(Key(match v {
                            "__CURSOR" => 1,
                            "__REALTIME_TIMESTAMP" => 2,
                            "PRIORITY" => 3,
                            "SYSLOG_IDENTIFIER" => 4,
                            "_COMM" => 5,
                            "_TRANSPORT" => 6,
                            "_SYSTEMD_USER_UNIT" => 7,
                            "_SYSTEMD_UNIT" => 8,
                            "MESSAGE" => 9,
                            _ => 0,
                        }))
                    }
                }
                deserializer.deserialize_identifier(KeyVisitor)
            }
        }
        struct RowVisitor;
        impl<'de> Visitor<'de> for RowVisitor {
            type Value = RowFields;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("an entry of the journal")
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<RowFields, A::Error> {
                let mut row = RowFields::default();
                while let Some(Key(key)) = map.next_key::<Key>()? {
                    if key == 0 {
                        map.next_value::<IgnoredAny>()?;
                        continue;
                    }
                    let Text(value) = map.next_value::<Text>()?;
                    match key {
                        1 => row.cursor = Some(value),
                        2 => row.realtime = value,
                        3 => row.priority = value,
                        4 => row.identifier = value,
                        5 => row.comm = value,
                        6 => row.transport = value,
                        7 => row.user_unit = value,
                        8 => row.unit = value,
                        _ => row.message = value,
                    }
                }
                Ok(row)
            }
        }
        deserializer.deserialize_map(RowVisitor)
    }
}

/// Terminal colour codes some programs write into their messages, \u001b[...m and the like
pub fn strip_ansi(text: &str) -> Cow<'_, str> {
    if !text.contains('\u{1b}') {
        return Cow::Borrowed(text);
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find("\u{1b}[") {
        out.push_str(&rest[..at]);
        let after = &rest[at + 2..];
        let params = after.find(|c: char| !(c.is_ascii_digit() || c == ';' || c == '?')).unwrap_or(after.len());
        match after[params..].chars().next() {
            Some(c) if c.is_ascii_alphabetic() => rest = &after[params + 1..],
            _ => {
                out.push_str("\u{1b}[");
                rest = after;
            }
        }
    }
    out.push_str(rest);
    Cow::Owned(out)
}

/// What journalctl said when it could not read, without its hints about what this account may see
pub fn complaint(stderr: &str) -> String {
    stderr
        .split('\n')
        .filter(|line| {
            !line.trim().is_empty()
                && !line.starts_with("Hint:")
                && !line.contains("not seeing messages")
                && !line.contains("Users in groups")
                && !line.contains("-- No entries --")
        })
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string()
}

// --- What the page asks for ------------------------------------------------------------------------

/// What is shown, as the page asks for it
#[derive(Debug, Clone, PartialEq)]
pub struct Request {
    pub category: String,
    pub source: Option<Source>,
    pub range: String,
    pub level: i32,
    pub search: String,
    pub regex: bool,
}

/// One page of entries, newest first
#[derive(Debug, Default)]
pub struct Page {
    pub entries: Vec<Rc<Entry>>,
    pub more: bool,
    pub command: String,
    pub error: String,
    /// Another read took its place
    pub stopped: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Boot {
    pub index: i64,
    pub id: String,
    /// Milliseconds since the epoch
    pub first: Option<i64>,
    pub last: Option<i64>,
}

#[derive(Debug, Clone, Default)]
pub struct Overview {
    pub readable: bool,
    pub usage: String,
    pub important: usize,
    pub crashes: usize,
    pub boots: Vec<Boot>,
    pub user: String,
}

pub enum Exported {
    Canceled,
    Saved { file: String, folder: String },
    Failed(String),
}

/// A program that reads the journal, which another read stops: the page only ever wants the newest
struct Reading {
    process: gio::Subprocess,
    stopped: Rc<Cell<bool>>,
}

impl Reading {
    fn stop(&self) {
        self.stopped.set(true);
        self.process.send_signal(libc::SIGTERM);
    }
}

/// The journal being followed while the page is live: stopped when this is dropped
pub struct Follower {
    process: gio::Subprocess,
    stopped: Rc<Cell<bool>>,
}

impl Drop for Follower {
    fn drop(&mut self) {
        self.stopped.set(true);
        self.process.send_signal(libc::SIGTERM);
    }
}

/// How a program that was read a chunk at a time ended
struct Ended {
    code: i32,
    stderr: String,
    stopped: bool,
}

/// The journal, as this window reads it: what main.js kept between the page's requests
#[derive(Default)]
pub struct Journal {
    known: RefCell<Option<Known>>,
    names: RefCell<HashMap<String, String>>,
    reading: RefCell<Option<Reading>>,
}

/// Runs a program the way main.js's run() did: a minute at most
async fn run(program: &str, args: &[&str]) -> Output {
    process::run_with(program, args, Options { timeout: Duration::from_secs(60), ..Default::default() }).await
}

/// journalctl, with its output to be read a chunk at a time
fn spawn_reader(args: &[String]) -> Option<gio::Subprocess> {
    let mut argv: Vec<&std::ffi::OsStr> = vec![std::ffi::OsStr::new("journalctl")];
    argv.extend(args.iter().map(std::ffi::OsStr::new));
    gio::Subprocess::newv(&argv, gio::SubprocessFlags::STDOUT_PIPE | gio::SubprocessFlags::STDERR_PIPE).ok()
}

async fn read_all(stream: gio::InputStream) -> Vec<u8> {
    let mut out = Vec::new();
    while let Ok(chunk) = stream.read_bytes_future(16384, glib::Priority::DEFAULT).await {
        if chunk.is_empty() {
            break;
        }
        out.extend_from_slice(&chunk);
    }
    out
}

/// Reads what a program writes a chunk at a time, handing over each whole line as it comes, so that a page
/// of the journal is never one blocking read and the window draws between chunks
async fn read_lines(process: &gio::Subprocess, stopped: &Rc<Cell<bool>>, timeout: Option<Duration>, mut on_line: impl FnMut(&[u8])) -> Ended {
    let stderr = process.stderr_pipe().map(|pipe| glib::spawn_future_local(read_all(pipe)));
    let reading = async {
        if let Some(stdout) = process.stdout_pipe() {
            let mut pending: Vec<u8> = Vec::new();
            loop {
                let chunk = match stdout.read_bytes_future(65536, glib::Priority::DEFAULT).await {
                    Ok(chunk) if !chunk.is_empty() => chunk,
                    _ => break,
                };
                if stopped.get() {
                    break;
                }
                let mut start = 0;
                if pending.is_empty() {
                    // Whole lines straight from the chunk, and only the last part kept for the next
                    while let Some(end) = chunk[start..].iter().position(|&b| b == b'\n') {
                        on_line(&chunk[start..start + end]);
                        start += end + 1;
                    }
                    pending.extend_from_slice(&chunk[start..]);
                } else {
                    pending.extend_from_slice(&chunk);
                    while let Some(end) = pending[start..].iter().position(|&b| b == b'\n') {
                        on_line(&pending[start..start + end]);
                        start += end + 1;
                    }
                    pending.drain(..start);
                }
            }
            if !pending.is_empty() && !stopped.get() {
                on_line(&pending);
            }
        }
        let _ = process.wait_future().await;
    };
    let timed_out = match timeout {
        Some(timeout) => glib::future_with_timeout(timeout, reading).await.is_err(),
        None => {
            reading.await;
            false
        }
    };
    if timed_out {
        process.force_exit();
    }
    let stderr = match stderr {
        Some(handle) => handle.await.unwrap_or_default(),
        None => Vec::new(),
    };
    let code = if timed_out || !process.has_exited() { -1 } else { process.exit_status() };
    Ended { code, stderr: String::from_utf8_lossy(&stderr).into_owned(), stopped: stopped.get() }
}

impl Journal {
    // --- Apps and services -------------------------------------------------------------------------

    /// The name an app's launcher gives it, or '' for an app without one
    pub fn app_name(&self, id: &str) -> String {
        if let Some(name) = self.names.borrow().get(id) {
            return name.clone();
        }
        let mut name = String::new();
        for dir in application_dirs() {
            let Ok(text) = std::fs::read_to_string(dir.join(format!("{id}.desktop"))) else { continue };
            name = desktop_name(&text);
            if !name.is_empty() {
                break;
            }
        }
        self.names.borrow_mut().insert(id.to_string(), name.clone());
        name
    }

    /// Every app and service that has written to the journal this account can read
    pub async fn sources(&self) -> Sources {
        let system = glib::spawn_future_local(async { run("journalctl", &["--system", "--quiet", "--field=_SYSTEMD_UNIT"]).await });
        let user = glib::spawn_future_local(async { run("journalctl", &["--user", "--quiet", "--field=_SYSTEMD_USER_UNIT"]).await });
        let (system, user) = (system.await.unwrap_or_default(), user.await.unwrap_or_default());
        let known = known_of(&system.stdout, &user.stdout);
        let mut apps: Vec<AppItem> = known
            .apps
            .iter()
            .map(|(id, _)| {
                let name = self.app_name(id);
                AppItem { id: id.clone(), name: if name.is_empty() { id.clone() } else { name } }
            })
            .collect();
        sort_by_name(&mut apps, |app| &app.name);
        let found = Sources { apps, user: known.user.clone(), system: known.system.clone() };
        self.known.replace(Some(known));
        found
    }

    /// The arguments that narrow the journal to one source, which has to be one found above. A program is
    /// narrowed to by the identifier it logs under, which the page has from an entry of the journal.
    pub async fn source_args(&self, source: Option<&Source>) -> Result<Vec<String>, String> {
        let Some(source) = source else { return Ok(Vec::new()) };
        if source.kind == Kind::Identifier {
            let name = &source.id;
            if name.is_empty() || name.encode_utf16().count() > 200 || name.contains(['\n', '=']) {
                return Err(t!("That program cannot be picked out of the journal."));
            }
            return Ok(vec![format!("--identifier={name}")]);
        }
        if self.known.borrow().is_none() {
            self.sources().await;
        }
        let known = self.known.borrow();
        let known = known.as_ref().expect("read just now");
        match source.kind {
            Kind::App => match known.apps.iter().find(|(id, _)| *id == source.id) {
                Some((_, patterns)) => Ok(patterns.iter().map(|pattern| format!("--user-unit={pattern}")).collect()),
                None => Err(t!("That app has not written anything to the journal.")),
            },
            Kind::Unit => {
                let list = if source.scope == Scope::User { &known.user } else { &known.system };
                // A unit named by an entry the page has open, which has not been listed yet
                if !list.iter().any(|unit| unit.name == source.id) && !named_unit(&source.id) {
                    return Err(t!("That service has not written anything to the journal."));
                }
                Ok(vec![if source.scope == Scope::User { format!("--user-unit={}", source.id) } else { format!("--unit={}", source.id) }])
            }
            // A program was narrowed to above; anything else is nothing this window found
            Kind::Identifier => Err(t!("Unknown source.")),
        }
    }

    // --- The journal -------------------------------------------------------------------------------

    /// journalctl's arguments for what the page asked for, without what it is to be printed as
    pub async fn filters(&self, query: &Request, range: bool) -> Result<Vec<String>, String> {
        let category = if category_args(&query.category).is_some() { query.category.as_str() } else { "all" };
        let mut args = category_args(category).unwrap_or_default();
        if range {
            args.extend(range_filter(&query.range));
        }
        let level = if (0..=7).contains(&query.level) { query.level } else { 7 };
        let priority = if category == "important" { level.min(3) } else { level };
        if priority < 7 {
            args.push(format!("--priority={priority}"));
        }
        args.extend(self.source_args(query.source.as_ref()).await?);
        args.extend(search_args(&query.search, query.regex));
        Ok(args)
    }

    /// Where an entry came from, as a source the page can narrow the view to
    fn origin(&self, row: &RowFields) -> Option<Source> {
        if let Some((id, _)) = app_of(&row.user_unit) {
            let name = self.app_name(&id);
            return Some(Source { kind: Kind::App, label: if name.is_empty() { id.clone() } else { name }, id, scope: Scope::User });
        }
        if listed_service(&row.user_unit) {
            return Some(Source { kind: Kind::Unit, id: row.user_unit.clone(), scope: Scope::User, label: row.user_unit.clone() });
        }
        if listed_service(&row.unit) {
            return Some(Source { kind: Kind::Unit, id: row.unit.clone(), scope: Scope::System, label: row.unit.clone() });
        }
        (!row.identifier.is_empty()).then(|| Source { kind: Kind::Identifier, id: row.identifier.clone(), scope: Scope::System, label: row.identifier.clone() })
    }

    /// One line of journalctl's JSON as an entry, or None for one without a cursor
    pub fn entry_of(&self, line: &[u8]) -> Option<Entry> {
        let line = std::str::from_utf8(line).ok()?.trim_end_matches('\r');
        let row: RowFields = serde_json::from_str(line).ok()?;
        let cursor = row.cursor.clone().filter(|cursor| !cursor.is_empty())?;
        let kernel = row.transport == "kernel";
        let priority = match row.priority.as_bytes() {
            [digit @ b'0'..=b'7'] => digit - b'0',
            _ => 6,
        };
        let source = [&row.identifier, &row.comm].into_iter().find(|s| !s.is_empty()).cloned().unwrap_or_else(|| {
            if kernel { "kernel".into() } else if !row.user_unit.is_empty() { row.user_unit.clone() } else { row.unit.clone() }
        });
        let time = row.realtime.trim().parse::<i64>().map(|us| us.div_euclid(1000)).unwrap_or(0);
        Some(Entry {
            cursor: cursor.into(),
            time,
            priority,
            source,
            message: strip_ansi(&row.message).into_owned(),
            from: self.origin(&row),
            raw: line.into(),
        })
    }

    /// One page of entries, newest first, starting after the last one the page has. Another query stops
    /// this one: the page only ever wants the newest.
    pub async fn query(&self, request: &Request, after: Option<&str>) -> Page {
        if let Some(reading) = self.reading.take() {
            reading.stop();
        }
        let args = match self.filters(request, true).await {
            Ok(args) => args,
            Err(error) => return Page { error, ..Default::default() },
        };
        let command = std::iter::once("journalctl".to_string()).chain(args.iter().cloned()).map(|arg| quote(&arg)).collect::<Vec<_>>().join(" ");
        let read = read_args(&args, after);
        let Some(process) = spawn_reader(&read) else {
            return Page { command, error: String::new(), ..Default::default() };
        };
        let stopped = Rc::new(Cell::new(false));
        self.reading.replace(Some(Reading { process: process.clone(), stopped: stopped.clone() }));
        let mut found: Vec<Rc<Entry>> = Vec::new();
        let ended = read_lines(&process, &stopped, Some(Duration::from_secs(120)), |line| {
            if let Some(entry) = self.entry_of(line) {
                found.push(Rc::new(entry));
            }
        })
        .await;
        if self.reading.borrow().as_ref().is_some_and(|reading| reading.process == process) {
            self.reading.take();
        }
        if ended.stopped {
            return Page { stopped: true, ..Default::default() };
        }
        let said = complaint(&ended.stderr);
        Page {
            more: found.len() >= PAGE,
            error: if found.is_empty() && ended.code != 0 && !said.is_empty() { said } else { String::new() },
            entries: found,
            command,
            stopped: false,
        }
    }

    /// Stops the read of a page that the page no longer wants, as the window closes
    pub fn stop_reading(&self) {
        if let Some(reading) = self.reading.take() {
            reading.stop();
        }
    }

    // --- Following ---------------------------------------------------------------------------------

    /// New entries as they are written, handed to the page a few times a second; `on_end` when journalctl
    /// stops by itself
    pub async fn follow(
        self: &Rc<Self>,
        request: &Request,
        on_entries: impl Fn(Vec<Rc<Entry>>) + 'static,
        on_end: impl FnOnce() + 'static,
    ) -> Result<Follower, String> {
        // Whatever the time range, what is new is now
        let mut args = self.filters(request, false).await?;
        args.extend(["--quiet", "--no-pager", "--output=json", "--follow", "--lines=0"].map(String::from));
        let process = spawn_reader(&args).ok_or_default()?;
        let stopped = Rc::new(Cell::new(false));
        let batch: Rc<RefCell<Vec<Rc<Entry>>>> = Rc::new(RefCell::new(Vec::new()));
        let timer: Rc<Cell<bool>> = Rc::new(Cell::new(false));
        let on_entries = Rc::new(on_entries);
        let journal = Rc::downgrade(self);
        let (reader, flag) = (process.clone(), stopped.clone());
        glib::spawn_future_local(async move {
            let ended = read_lines(&reader, &flag, None, |line| {
                let Some(journal) = journal.upgrade() else { return };
                let Some(entry) = journal.entry_of(line) else { return };
                if flag.get() {
                    return;
                }
                batch.borrow_mut().push(Rc::new(entry));
                if !timer.get() {
                    timer.set(true);
                    let (batch, timer, flag, on_entries) = (batch.clone(), timer.clone(), flag.clone(), on_entries.clone());
                    glib::timeout_add_local_once(Duration::from_millis(250), move || {
                        timer.set(false);
                        let list = std::mem::take(&mut *batch.borrow_mut());
                        if !flag.get() {
                            on_entries(list);
                        }
                    });
                }
            })
            .await;
            if !ended.stopped {
                on_end();
            }
        });
        Ok(Follower { process, stopped })
    }

    // --- What the sidebar shows --------------------------------------------------------------------

    /// How many entries of this boot match, up to COUNT_CAP
    async fn count(args: &[&str]) -> usize {
        let lines = format!("--lines={COUNT_CAP}");
        let mut all: Vec<&str> = args.to_vec();
        all.extend(["--boot=0", "--quiet", "--no-pager", "--output=json", "--output-fields=PRIORITY", lines.as_str()]);
        run("journalctl", &all).await.stdout.split('\n').filter(|line| !line.is_empty()).count()
    }

    /// The boots the journal remembers, newest first
    async fn boots() -> Vec<Boot> {
        let mut result = run("journalctl", &["--list-boots", "--quiet", "--no-pager", "--output=json", "--lines=40"]).await;
        if result.code != 0 {
            result = run("journalctl", &["--list-boots", "--quiet", "--no-pager", "--output=json"]).await;
        }
        parse_boots(&result.stdout)
    }

    pub async fn overview() -> Overview {
        let access = glib::spawn_future_local(async { run("journalctl", &["--system", "--lines=0", "--no-pager"]).await });
        let usage = glib::spawn_future_local(async { run("journalctl", &["--disk-usage"]).await });
        let important = glib::spawn_future_local(async { Journal::count(&["--priority=3"]).await });
        let crashes = glib::spawn_future_local(async { Journal::count(&[&format!("MESSAGE_ID={COREDUMP}")]).await });
        let boots = glib::spawn_future_local(Journal::boots());
        let access = access.await.unwrap_or_default();
        let usage = usage.await.unwrap_or_default();
        Overview {
            // Outside wheel, journalctl can open nothing of the system's and says so
            readable: access.code == 0 && !denied(&access.stderr),
            usage: disk_usage(&usage.stdout),
            important: important.await.unwrap_or(0),
            crashes: crashes.await.unwrap_or(0),
            boots: boots.await.unwrap_or_default(),
            user: glib::user_name().to_string_lossy().into_owned(),
        }
    }

    // --- Export and the terminal -------------------------------------------------------------------

    /// What is shown, oldest first, into a file of the person's choosing: text as a terminal shows it, or
    /// journalctl's JSON. Logs name people, places and machines, so the file is theirs alone.
    pub async fn export(&self, request: &Request, window: &amethystora_ui::gtk::Window) -> Exported {
        use amethystora_ui::gtk;
        let args = match self.filters(request, true).await {
            Ok(args) => args,
            Err(error) => return Exported::Failed(error),
        };
        let text = gtk::FileFilter::new();
        text.set_name(Some(&t!("Text")));
        text.add_suffix("txt");
        text.add_suffix("log");
        let json = gtk::FileFilter::new();
        json.set_name(Some(&t!("JSON, one entry a line")));
        json.add_suffix("json");
        let filters = gio::ListStore::new::<gtk::FileFilter>();
        filters.append(&text);
        filters.append(&json);
        // ~/Documents where the account has no folders of its own named, as Electron took it
        let documents = glib::user_special_dir(glib::UserDirectory::Documents).unwrap_or_else(|| amethystora_ui::palette::home().join("Documents"));
        let dialog = gtk::FileDialog::builder()
            .title(t!("Export logs"))
            .accept_label(t!("Export"))
            .modal(true)
            .initial_name(format!("logs-{}.txt", stamp()))
            .filters(&filters)
            .default_filter(&text)
            .build();
        dialog.set_initial_folder(Some(&gio::File::for_path(&documents)));
        let Ok(file) = dialog.save_future(Some(window)).await else { return Exported::Canceled };
        let Some(path) = file.path() else { return Exported::Canceled };
        let json = path.to_string_lossy().ends_with(".json");
        write_export(&args, &path, json).await
    }

    /// The same view in journalctl in a terminal, where less can page through all of it
    pub async fn terminal(&self, request: &Request, live: bool) -> Result<(), String> {
        let args = self.filters(request, !live).await?;
        let mut all = vec!["journalctl".to_string()];
        all.extend(args);
        all.push(if live { "--follow" } else { "--pager-end" }.into());
        process::launch_owned(IN_TERMINAL, &all);
        Ok(())
    }
}

trait OkOrDefault<T> {
    fn ok_or_default(self) -> Result<T, String>;
}

impl<T> OkOrDefault<T> for Option<T> {
    fn ok_or_default(self) -> Result<T, String> {
        self.ok_or_else(String::new)
    }
}

/// The apps and units of the two lists journalctl --field printed
fn known_of(system: &str, user: &str) -> Known {
    let lines = |text: &str| text.split('\n').map(str::trim).filter(|line| !line.is_empty()).map(str::to_string).collect::<Vec<_>>();
    let mut apps: Vec<(String, Vec<String>)> = Vec::new();
    let mut user_units = Vec::new();
    for unit in lines(user) {
        if let Some((id, pattern)) = app_of(&unit) {
            match apps.iter_mut().find(|(known, _)| *known == id) {
                Some((_, patterns)) => {
                    if !patterns.contains(&pattern) {
                        patterns.push(pattern);
                    }
                }
                None => apps.push((id, vec![pattern])),
            }
        } else if listed_service(&unit) {
            user_units.push(unit);
        }
    }
    let system_units: Vec<String> = lines(system).into_iter().filter(|unit| listed_service(unit)).collect();
    Known { apps, user: collapse(&user_units), system: collapse(&system_units) }
}

/// main.js's /^[\w@.:\\-]+\.[a-z]+$/: a unit's name as it can only be
fn named_unit(name: &str) -> bool {
    let Some(dot) = name.rfind('.') else { return false };
    let (stem, kind) = (&name[..dot], &name[dot + 1..]);
    !stem.is_empty()
        && stem.chars().all(|c| c.is_ascii_alphanumeric() || "_@.:\\-".contains(c))
        && !kind.is_empty()
        && kind.chars().all(|c| c.is_ascii_lowercase())
}

/// A service a crash or an entry is handed to the agent by: /^[\w@.:\\-]+\.service$/
pub fn agent_unit(name: &str) -> bool {
    name.strip_suffix(".service").is_some_and(|stem| !stem.is_empty() && stem.chars().all(|c| c.is_ascii_alphanumeric() || "_@.:\\-".contains(c)))
}

/// A crashed process's number, as the agent takes it: /^\d{1,10}$/
pub fn agent_pid(value: &str) -> bool {
    (1..=10).contains(&value.len()) && value.chars().all(|c| c.is_ascii_digit())
}

/// The time range's arguments: a boot by its id, the two minutes around an entry, or one of the names
pub fn range_filter(value: &str) -> Vec<String> {
    let value = if value.is_empty() { "boot" } else { value };
    if let Some(id) = value.strip_prefix("b:").filter(|id| id.len() == 32 && id.chars().all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c))) {
        return vec![format!("--boot={id}")];
    }
    if let Some(second) = value.strip_prefix("around:").filter(|s| (1..=12).contains(&s.len()) && s.chars().all(|c| c.is_ascii_digit())) {
        let second: i64 = second.parse().unwrap_or(0);
        return vec![format!("--since=@{}", second - 60), format!("--until=@{}", second + 60)];
    }
    range_args(value).or_else(|| range_args("boot")).unwrap_or(&[]).iter().map(|arg| arg.to_string()).collect()
}

/// The search: taken as it is typed, unless the page says it is a regular expression
pub fn search_args(search: &str, regex: bool) -> Vec<String> {
    let search = first_units(search, 500);
    if search.is_empty() {
        return Vec::new();
    }
    let pattern = if regex { search.to_string() } else { escape(search) };
    vec!["--case-sensitive=false".into(), format!("--grep={pattern}")]
}

/// At most `count` UTF-16 units, as String.slice counted them
fn first_units(text: &str, count: usize) -> &str {
    let mut units = 0;
    for (at, c) in text.char_indices() {
        units += c.len_utf16();
        if units > count {
            return &text[..at];
        }
    }
    text
}

/// What a regular expression treats as syntax, escaped: /[.*+?^${}()|[\]\\]/g
pub fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        if ".*+?^${}()|[]\\".contains(c) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

fn read_args(args: &[String], after: Option<&str>) -> Vec<String> {
    let mut read = args.to_vec();
    read.extend(["--quiet", "--no-pager", "--output=json", "--reverse"].map(String::from));
    read.push(format!("--lines={PAGE}"));
    if let Some(after) = after.filter(|after| !after.is_empty()) {
        read.push(format!("--after-cursor={after}"));
    }
    read
}

fn denied(stderr: &str) -> bool {
    let lower = stderr.to_lowercase();
    lower.contains("insufficient permissions") || lower.contains("not seeing messages")
}

/// "... take up 1.2G in the file system.": the size
fn disk_usage(stdout: &str) -> String {
    stdout
        .find("take up ")
        .map(|at| &stdout[at + 8..])
        .and_then(|rest| rest.split_whitespace().next().filter(|_| !rest.starts_with(char::is_whitespace)))
        .unwrap_or("")
        .to_string()
}

pub fn parse_boots(stdout: &str) -> Vec<Boot> {
    let Ok(Value::Array(list)) = serde_json::from_str::<Value>(stdout) else { return Vec::new() };
    let number = |value: Option<&Value>| -> f64 {
        match value {
            Some(Value::Number(n)) => n.as_f64().unwrap_or(f64::NAN),
            Some(Value::String(s)) => s.trim().parse().unwrap_or(f64::NAN),
            _ => f64::NAN,
        }
    };
    let millis = |value: Option<&Value>| {
        let n = (number(value) / 1000.0).floor();
        (n.is_finite() && n != 0.0).then_some(n as i64)
    };
    let mut boots: Vec<Boot> = list
        .iter()
        .map(|boot| Boot {
            index: number(boot.get("index")) as i64,
            id: boot.get("boot_id").map(text).unwrap_or_default(),
            first: millis(boot.get("first_entry")),
            last: millis(boot.get("last_entry")),
        })
        .filter(|boot| boot.id.len() == 32 && boot.id.chars().all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c)))
        .collect();
    boots.sort_by_key(|boot| std::cmp::Reverse(boot.index));
    boots
}

/// yyyymmdd-hhmm, now
fn stamp() -> String {
    glib::DateTime::now_local().ok().and_then(|now| now.format("%Y%m%d-%H%M").ok()).map(|s| s.to_string()).unwrap_or_default()
}

async fn write_export(args: &[String], path: &Path, json: bool) -> Exported {
    use std::os::unix::fs::OpenOptionsExt;
    let file = match std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(path) {
        Ok(file) => file,
        Err(error) => return Exported::Failed(error.to_string()),
    };
    let mut argv: Vec<String> = vec!["journalctl".into()];
    argv.extend(args.iter().cloned());
    argv.extend(["--quiet".into(), "--no-pager".into(), if json { "--output=json" } else { "--output=short-iso-precise" }.into()]);
    argv.push(format!("--lines={EXPORT_LINES}"));
    let launcher = gio::SubprocessLauncher::new(gio::SubprocessFlags::STDERR_PIPE);
    launcher.take_stdout_fd(Some(std::os::fd::OwnedFd::from(file)));
    let argv: Vec<&std::ffi::OsStr> = argv.iter().map(std::ffi::OsStr::new).collect();
    let process = match launcher.spawn(&argv) {
        Ok(process) => process,
        Err(error) => return Exported::Failed(error.message().to_string()),
    };
    let stderr = match process.stderr_pipe() {
        Some(pipe) => read_all(pipe).await,
        None => Vec::new(),
    };
    let _ = process.wait_future().await;
    let code = if process.has_exited() { process.exit_status() } else { -1 };
    let said = complaint(&String::from_utf8_lossy(&stderr));
    if code != 0 && !said.is_empty() {
        return Exported::Failed(said);
    }
    Exported::Saved {
        file: path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default(),
        folder: path.parent().map(|folder| folder.to_string_lossy().into_owned()).unwrap_or_default(),
    }
}

// --- The AI agent ----------------------------------------------------------------------------------

/// Whether the agentic features are on for this account (`ame agent toggle`)
pub async fn agent_on() -> bool {
    run(AGENT, &["status"]).await.code == 0
}

/// What an entry is handed to the agent as: a crash's process number, or the service it came from
#[derive(Debug, Clone, PartialEq)]
pub enum Target {
    Crash(String),
    Unit(String),
}

/// An entry handed to the agent, which looks into it in a terminal with the diagnose skill and changes
/// nothing until asked. What reaches it is only ever a crash's process number, which it looks up in
/// coredumpctl, or the name of the service the entry came from, which it looks up in systemd: never a
/// message or anything else the page could fill with words of its own.
pub fn diagnose(target: &Target) {
    match target {
        Target::Crash(pid) if agent_pid(pid) => process::launch(AGENT, &["diagnose", pid]),
        Target::Unit(unit) if agent_unit(unit) => process::launch(AGENT, &["diagnose", unit]),
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(category: &str) -> Request {
        Request { category: category.into(), source: None, range: "boot".into(), level: 7, search: String::new(), regex: false }
    }

    fn filters(journal: &Journal, request: &Request, range: bool) -> Result<Vec<String>, String> {
        glib::MainContext::default().block_on(journal.filters(request, range))
    }

    fn with_known(journal: &Journal) {
        journal.known.replace(Some(known_of(
            "NetworkManager.service\nsession-2.scope\nrun-u12.service\ninit.scope\nsshd.service\n",
            "app-gnome-org.gnome.Nautilus-4242.scope\napp-gnome-org.gnome.Nautilus-5120.scope\napp-flatpak-com.brave.Browser-1234.scope\n\
             app-org.gnome.Evolution\\x2dalarm\\x2dnotify@autostart.service\npipewire.service\nvte-spawn-1.scope\ndbus-:1.2-x@0.service\n",
        )));
    }

    #[test]
    fn apps_and_their_patterns() {
        assert_eq!(app_of("app-gnome-org.gnome.Nautilus-4242.scope"), Some(("org.gnome.Nautilus".into(), "app-gnome-org.gnome.Nautilus-*.scope".into())));
        assert_eq!(app_of("app-flatpak-com.brave.Browser-1234.scope"), Some(("com.brave.Browser".into(), "app-flatpak-com.brave.Browser-*.scope".into())));
        assert_eq!(
            app_of("app-org.gnome.Evolution\\x2dalarm\\x2dnotify@autostart.service"),
            Some(("org.gnome.Evolution-alarm-notify".into(), "app-org.gnome.Evolution\\x2dalarm\\x2dnotify@*.service".into()))
        );
        assert_eq!(app_of("app-gnome-firefox.desktop-77.scope").map(|a| a.0), Some("firefox".into()));
        assert_eq!(app_of("pipewire.service"), None);
        assert_eq!(app_of(""), None);
        assert!(transient("session-2.scope") && transient("run-u1.service") && transient("init.scope") && transient("dbus-:1.2-a@0.service"));
        assert!(!transient("session-x.scope") && !transient("sshd.service"));
    }

    #[test]
    fn templates_collapse() {
        let units: Vec<String> = ["b.service", "systemd-coredump@0-1-0.service", "systemd-coredump@0-2-0.service", "systemd-coredump@0-3-0.service",
            "systemd-coredump@0-4-0.service", "getty@tty1.service", "a.service"]
            .map(String::from)
            .to_vec();
        let list = collapse(&units);
        let labels: Vec<&str> = list.iter().map(|u| u.label.as_str()).collect();
        assert_eq!(labels, ["a.service", "b.service", "getty@tty1.service", "systemd-coredump@.service"]);
        assert_eq!(list[3].name, "systemd-coredump@*.service");
        assert_eq!(list[3].instances, Some(4));
        assert_eq!(list[2].instances, None);
    }

    #[test]
    fn known_sources() {
        let journal = Journal::default();
        with_known(&journal);
        let known = journal.known.borrow().clone().unwrap();
        assert_eq!(known.apps.len(), 3);
        assert_eq!(known.apps[0], ("org.gnome.Nautilus".to_string(), vec!["app-gnome-org.gnome.Nautilus-*.scope".to_string()]));
        assert_eq!(known.user.iter().map(|u| u.name.as_str()).collect::<Vec<_>>(), ["pipewire.service"]);
        assert_eq!(known.system.iter().map(|u| u.name.as_str()).collect::<Vec<_>>(), ["NetworkManager.service", "sshd.service"]);
    }

    #[test]
    fn arguments_come_from_known_choices() {
        let journal = Journal::default();
        with_known(&journal);
        assert_eq!(filters(&journal, &request("important"), true).unwrap(), ["--boot=0", "--priority=3"]);
        assert_eq!(filters(&journal, &Request { level: 5, ..request("important") }, true).unwrap(), ["--boot=0", "--priority=3"]);
        assert_eq!(filters(&journal, &Request { level: 4, ..request("all") }, false).unwrap(), ["--priority=4"]);
        assert_eq!(filters(&journal, &Request { level: 9, ..request("session") }, true).unwrap(), ["--user", "--boot=0"]);
        // An unknown view is everything; an unknown range is this boot
        assert_eq!(filters(&journal, &Request { range: "--all".into(), ..request("--system") }, true).unwrap(), ["--boot=0"]);
        assert_eq!(
            filters(&journal, &request("security"), true).unwrap(),
            ["_TRANSPORT=audit", "+", "SYSLOG_FACILITY=4", "+", "SYSLOG_FACILITY=10", "--boot=0"]
        );
        assert_eq!(filters(&journal, &Request { range: "b:0123456789abcdef0123456789abcdef".into(), ..request("all") }, true).unwrap(),
            ["--boot=0123456789abcdef0123456789abcdef"]);
        assert_eq!(filters(&journal, &Request { range: "b:0123; rm".into(), ..request("all") }, true).unwrap(), ["--boot=0"]);
        assert_eq!(filters(&journal, &Request { range: "around:1760000000".into(), ..request("all") }, true).unwrap(),
            ["--since=@1759999940", "--until=@1760000060"]);
        assert_eq!(filters(&journal, &Request { range: "around:-5".into(), ..request("all") }, true).unwrap(), ["--boot=0"]);
        // The search is only ever the value of --grep, escaped unless it is a regular expression
        assert_eq!(filters(&journal, &Request { search: "--since=x (a.b)".into(), ..request("all") }, true).unwrap(),
            ["--boot=0", "--case-sensitive=false", "--grep=--since=x \\(a\\.b\\)"]);
        assert_eq!(filters(&journal, &Request { search: "a.*b".into(), regex: true, ..request("all") }, true).unwrap(),
            ["--boot=0", "--case-sensitive=false", "--grep=a.*b"]);
        assert_eq!(search_args(&"x".repeat(600), true)[1].len(), "--grep=".len() + 500);
        // Sources: an app has to be one found in the journal, a unit or program only ever a value
        let app = Source { kind: Kind::App, id: "org.gnome.Nautilus".into(), scope: Scope::User, label: "Files".into() };
        assert_eq!(filters(&journal, &Request { source: Some(app), ..request("all") }, false).unwrap(), ["--user-unit=app-gnome-org.gnome.Nautilus-*.scope"]);
        let stranger = Source { kind: Kind::App, id: "--system".into(), scope: Scope::User, label: String::new() };
        assert!(filters(&journal, &Request { source: Some(stranger), ..request("all") }, false).is_err());
        let unit = Source { kind: Kind::Unit, id: "sshd.service".into(), scope: Scope::System, label: String::new() };
        assert_eq!(filters(&journal, &Request { source: Some(unit), ..request("all") }, false).unwrap(), ["--unit=sshd.service"]);
        let named = Source { kind: Kind::Unit, id: "foo@bar.service".into(), scope: Scope::User, label: String::new() };
        assert_eq!(filters(&journal, &Request { source: Some(named), ..request("all") }, false).unwrap(), ["--user-unit=foo@bar.service"]);
        for bad in ["a b.service", "x;y.service", "noext", "--x=1.service.", "a.Service"] {
            let unit = Source { kind: Kind::Unit, id: bad.into(), scope: Scope::System, label: String::new() };
            assert!(filters(&journal, &Request { source: Some(unit), ..request("all") }, false).is_err(), "{bad}");
        }
        let identifier = Source { kind: Kind::Identifier, id: "-n gnome-shell".into(), scope: Scope::System, label: String::new() };
        assert_eq!(filters(&journal, &Request { source: Some(identifier), ..request("all") }, false).unwrap(), ["--identifier=-n gnome-shell"]);
        for bad in ["", "a=b", "a\nb"] {
            let identifier = Source { kind: Kind::Identifier, id: bad.into(), scope: Scope::System, label: String::new() };
            assert!(filters(&journal, &Request { source: Some(identifier), ..request("all") }, false).is_err());
        }
        let long = Source { kind: Kind::Identifier, id: "x".repeat(201), scope: Scope::System, label: String::new() };
        assert!(filters(&journal, &Request { source: Some(long), ..request("all") }, false).is_err());
        // Every argument of a page's read is one of these, then the page's own
        let read = read_args(&["--boot=0".into()], Some("s=1;i=2"));
        assert_eq!(read, ["--boot=0", "--quiet", "--no-pager", "--output=json", "--reverse", "--lines=400", "--after-cursor=s=1;i=2"]);
    }

    #[test]
    fn quotes_like_a_shell() {
        assert_eq!(quote("--boot=0"), "--boot=0");
        assert_eq!(quote("--grep=a b"), "'--grep=a b'");
        assert_eq!(quote("--grep=it's"), "'--grep=it'\\''s'");
        assert_eq!(quote("MESSAGE_ID=fc2e"), "MESSAGE_ID=fc2e");
    }

    #[test]
    fn reads_journal_json() {
        let journal = Journal::default();
        let line = br#"{"__CURSOR":"s=1;i=2","__REALTIME_TIMESTAMP":"1760605323123456","PRIORITY":"3","_TRANSPORT":"stdout","_COMM":"nautilus","_SYSTEMD_USER_UNIT":"app-gnome-org.gnome.Nautilus-4242.scope","MESSAGE":"\u001b[1;33mwarn:\u001b[0m bad","_PID":"4242","BIN":[104,105]}"#;
        let entry = journal.entry_of(line).unwrap();
        assert_eq!(&*entry.cursor, "s=1;i=2");
        assert_eq!(entry.time, 1760605323123);
        assert_eq!(entry.priority, 3);
        assert_eq!(entry.source, "nautilus");
        assert_eq!(entry.message, "warn: bad");
        let from = entry.from.clone().unwrap();
        assert_eq!((from.kind, from.id.as_str()), (Kind::App, "org.gnome.Nautilus"));
        let fields = entry.fields();
        assert_eq!(fields["BIN"], "hi");
        assert_eq!(fields["_PID"], "4242");
        // Bytes that are not text, a field written twice, a field too long to print
        let line = br#"{"__CURSOR":"c","MESSAGE":[68,101,118,255,254,33],"PRIORITY":"9","SYSLOG_IDENTIFIER":["a","b"],"X":null,"_TRANSPORT":"kernel"}"#;
        let entry = journal.entry_of(line).unwrap();
        assert_eq!(entry.message, "Dev\u{fffd}\u{fffd}!");
        assert_eq!(entry.priority, 6);
        assert_eq!(entry.source, "a\nb");
        assert_eq!(entry.fields()["X"], "");
        let kernel = journal.entry_of(br#"{"__CURSOR":"c","_TRANSPORT":"kernel","MESSAGE":"usb"}"#).unwrap();
        assert_eq!(kernel.source, "kernel");
        assert!(kernel.from.is_none());
        let unit = journal.entry_of(br#"{"__CURSOR":"c","_SYSTEMD_UNIT":"sshd.service","SYSLOG_IDENTIFIER":"sshd"}"#).unwrap();
        assert_eq!(unit.from.unwrap(), Source { kind: Kind::Unit, id: "sshd.service".into(), scope: Scope::System, label: "sshd.service".into() });
        let program = journal.entry_of(br#"{"__CURSOR":"c","_SYSTEMD_UNIT":"init.scope","SYSLOG_IDENTIFIER":"systemd"}"#).unwrap();
        assert_eq!(program.from.unwrap().kind, Kind::Identifier);
        assert!(journal.entry_of(br#"{"MESSAGE":"no cursor"}"#).is_none());
        assert!(journal.entry_of(b"not json").is_none());
        assert!(journal.entry_of(br#"{"__CURSOR":""}"#).is_none());
    }

    #[test]
    fn reads_what_journalctl_says() {
        assert_eq!(complaint("Hint: You are currently not seeing messages from other users.\n      Users in groups 'adm' can see all.\nFailed to compile pattern\n"), "Failed to compile pattern");
        assert_eq!(complaint("-- No entries --\n"), "");
        assert_eq!(disk_usage("Archived and active journals take up 1.2G in the file system.\n"), "1.2G");
        assert_eq!(disk_usage("nothing"), "");
        assert!(denied("No journal files were opened due to Insufficient permissions."));
        let boots = parse_boots(r#"[{"index":-1,"boot_id":"8c1d2e3f4a5b4c6d9e8f7a6b5c4d3e2f","first_entry":1760000000123456,"last_entry":1760003600000000},
            {"index":0,"boot_id":"3f2a9c4e1b7d4a6f8e5c2b1a0d9e8f7c","first_entry":1760100000000000},{"index":-2,"boot_id":"not a boot"}]"#);
        assert_eq!(boots.len(), 2);
        assert_eq!((boots[0].index, boots[0].first, boots[0].last), (0, Some(1760100000000), None));
        assert_eq!(boots[1].first, Some(1760000000123));
        assert!(parse_boots("no").is_empty());
        assert_eq!(strip_ansi("\u{1b}[0;1;31mred\u{1b}[0m and \u{1b}[?25l"), "red and ");
        assert_eq!(strip_ansi("a\u{1b}[b"), "a");
        assert_eq!(strip_ansi("a\u{1b}[1"), "a\u{1b}[1");
        assert_eq!(unescape("Evolution\\x2dalarm\\x2"), "Evolution-alarm\\x2");
        assert_eq!(desktop_name("[Desktop Action x]\nName=New\n[Desktop Entry]\nName=\nName= Brave \n"), "Brave");
        assert_eq!(view_argument(&["--gapplication-service".into(), "crashes".into()]), "crashes");
        assert_eq!(view_argument(&["nope".into()]), "");
        assert_eq!(view_argument(&["sources".into()]), "sources");
    }

    #[test]
    fn the_agent_gets_only_a_number_or_a_service() {
        assert!(agent_pid("4242") && agent_pid("1234567890"));
        assert!(!agent_pid("12345678901") && !agent_pid("") && !agent_pid("-1") && !agent_pid("4 2"));
        assert!(agent_unit("sshd.service") && agent_unit("systemd-coredump@0-1-0.service") && agent_unit("a\\x2db.service"));
        assert!(!agent_unit(".service") && !agent_unit("sshd.socket") && !agent_unit("--help.service ") && !agent_unit("a b.service"));
        assert!(named_unit("app-a\\x2db@x.service") && !named_unit("a.service;") && !named_unit(".x"));
    }
}
