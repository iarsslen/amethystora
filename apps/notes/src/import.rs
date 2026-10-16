//! Bringing notes and tasks in, as main.js did: Joplin's export (a .jex, which is a tar of its own
//! serialisation), Planify's backup (its JSON), Markdown files, and a Notes backup. What comes from another
//! app gets a stable id, so that importing the same file twice updates rather than duplicates.

use std::collections::{HashMap, HashSet};
use std::io::Read;

use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

use amethystora_ui::t;

use crate::data::{self, Fields, Kind, Store};
use crate::vault::{self, Key};

/// What an import brought in, by the kinds main.js counted
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Counts {
    pub notes: u64,
    pub notebooks: u64,
    pub tasks: u64,
    pub projects: u64,
    pub attachments: u64,
}

impl Counts {
    /// In main.js's order: notes, notebooks, tasks, projects, attachments
    pub fn list(&self) -> [(&'static str, u64); 5] {
        [("notes", self.notes), ("notebooks", self.notebooks), ("tasks", self.tasks), ("projects", self.projects), ("attachments", self.attachments)]
    }

    fn add(&mut self, kind: Kind) {
        match kind {
            Kind::Notes => self.notes += 1,
            Kind::Notebooks => self.notebooks += 1,
            Kind::Tasks => self.tasks += 1,
            Kind::Projects => self.projects += 1,
            _ => {}
        }
    }
}

/// Where an attachment goes as it is imported: written, sealed if need be, and listed in the store
pub type AddResource<'a> = dyn FnMut(&mut Store, &str, &str, &[u8], &str) -> Result<(), String> + 'a;

/// A stable id for something from another app
pub fn id_for(source: &str, id: &str) -> String {
    if data::is_id(id) {
        return id.to_string();
    }
    let digest = Sha256::digest(format!("{source}:{id}").as_bytes());
    data::hex(&digest)[..32].to_string()
}

/// Number(value), as JavaScript converts: NaN for what is not a number
pub fn js_to_number(value: Option<&Value>) -> f64 {
    match value {
        None => f64::NAN,
        Some(Value::Null) => 0.0,
        Some(Value::Bool(b)) => f64::from(u8::from(*b)),
        Some(Value::Number(n)) => n.as_f64().unwrap_or(f64::NAN),
        Some(Value::String(s)) => {
            let trimmed = s.trim();
            if trimmed.is_empty() {
                0.0
            } else if let Some(hex) = trimmed.strip_prefix("0x").or_else(|| trimmed.strip_prefix("0X")) {
                i64::from_str_radix(hex, 16).map(|n| n as f64).unwrap_or(f64::NAN)
            } else {
                match trimmed {
                    "Infinity" | "+Infinity" => f64::INFINITY,
                    "-Infinity" => f64::NEG_INFINITY,
                    _ if trimmed.chars().all(|c| c.is_ascii_digit() || matches!(c, '.' | '-' | '+' | 'e' | 'E')) => trimmed.parse().unwrap_or(f64::NAN),
                    _ => f64::NAN,
                }
            }
        }
        Some(Value::Array(items)) => match items.len() {
            0 => 0.0,
            1 => js_to_number(items.first()),
            _ => f64::NAN,
        },
        Some(Value::Object(_)) => f64::NAN,
    }
}

/// `Number(value) || fallback`
fn number_or(value: Option<&Value>, fallback: f64) -> f64 {
    let n = js_to_number(value);
    if n == 0.0 || n.is_nan() { fallback } else { n }
}

/// Date.parse for what Joplin and Planify write: the ISO forms. A date alone is UTC, a date and time
/// without a zone the session's own time, as JavaScript reads them.
pub fn date_parse(text: &str) -> f64 {
    let text = text.trim();
    let digits = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit());
    let (date, rest) = match text.find(['T', 't', ' ']) {
        Some(at) => (&text[..at], Some(&text[at + 1..])),
        None => (text, None),
    };
    let parts: Vec<&str> = date.split('-').collect();
    let (year, month, day) = match parts.as_slice() {
        [y] if y.len() == 4 && digits(y) => (y.parse::<i64>().unwrap_or(0), 1, 1),
        [y, m] if y.len() == 4 && m.len() == 2 && digits(y) && digits(m) => (y.parse().unwrap_or(0), m.parse().unwrap_or(0), 1),
        [y, m, d] if y.len() == 4 && m.len() == 2 && d.len() == 2 && digits(y) && digits(m) && digits(d) => {
            (y.parse().unwrap_or(0), m.parse().unwrap_or(0), d.parse().unwrap_or(0))
        }
        _ => return f64::NAN,
    };
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return f64::NAN;
    }
    let days = crate::dates::days_from_civil(year, month, day);
    let Some(rest) = rest else { return days as f64 * 86400000.0 };
    // HH:mm[:ss[.sss]] then Z, ±HH:mm or nothing
    let (clock, zone) = match rest.find(['Z', 'z', '+', '-']) {
        Some(at) => (&rest[..at], Some(&rest[at..])),
        None => (rest, None),
    };
    let pieces: Vec<&str> = clock.split(':').collect();
    if pieces.len() < 2 || pieces.len() > 3 || !digits(pieces[0]) || !digits(pieces[1]) || pieces[0].len() != 2 || pieces[1].len() != 2 {
        return f64::NAN;
    }
    let (hour, minute): (i64, i64) = (pieces[0].parse().unwrap_or(0), pieces[1].parse().unwrap_or(0));
    let seconds: f64 = match pieces.get(2) {
        Some(s) => {
            let (whole, fraction) = s.split_once('.').unwrap_or((s, ""));
            if whole.len() != 2 || !digits(whole) || (!fraction.is_empty() && !digits(fraction)) {
                return f64::NAN;
            }
            let ms = if fraction.is_empty() { 0.0 } else { format!("0.{fraction}").parse::<f64>().unwrap_or(0.0) };
            whole.parse::<f64>().unwrap_or(0.0) + (ms * 1000.0).floor() / 1000.0
        }
        None => 0.0,
    };
    if hour > 24 || minute > 59 || seconds >= 60.0 {
        return f64::NAN;
    }
    let local = (days * 86400 + hour * 3600 + minute * 60) as f64 * 1000.0 + seconds * 1000.0;
    match zone {
        Some("Z" | "z") => local,
        Some(zone) => {
            let sign = if zone.starts_with('-') { -1.0 } else { 1.0 };
            let offset = &zone[1..];
            let (h, m) = offset.split_once(':').unwrap_or((offset.get(..2).unwrap_or(""), offset.get(2..).unwrap_or("")));
            if !digits(h) || !digits(m) {
                return f64::NAN;
            }
            local - sign * (h.parse::<f64>().unwrap_or(0.0) * 3600000.0 + m.parse::<f64>().unwrap_or(0.0) * 60000.0)
        }
        None => {
            // The session's own time: the offset it has at that moment
            match amethystora_ui::glib::DateTime::from_local(year as i32, month as i32, day as i32, hour as i32, minute as i32, seconds) {
                Ok(when) => when.to_unix() as f64 * 1000.0 + (seconds.fract() * 1000.0).round(),
                Err(_) => f64::NAN,
            }
        }
    }
}

/// A time from another app, or the fallback when it is none
pub fn time_of(value: Option<&Value>, fallback: f64) -> f64 {
    let time = match value {
        Some(Value::Number(n)) => n.as_f64().unwrap_or(f64::NAN),
        Some(Value::String(s)) => date_parse(s),
        _ => f64::NAN,
    };
    if time.is_finite() && time > 0.0 { time } else { fallback }
}

// --- Joplin -------------------------------------------------------------------------------------------------

/// A ustar archive, which is what a Joplin export (.jex) is: its files in order, by name
pub fn untar(buffer: &[u8]) -> Vec<(String, Vec<u8>)> {
    let mut files: Vec<(String, Vec<u8>)> = Vec::new();
    let mut offset = 0;
    let mut long_name: Option<String> = None;
    while offset + 512 <= buffer.len() {
        let header = &buffer[offset..offset + 512];
        if header.iter().all(|&b| b == 0) {
            break;
        }
        let field = |start: usize, length: usize| {
            let text = String::from_utf8_lossy(&header[start..start + length]).into_owned();
            match text.find('\0') {
                Some(at) => text[..at].to_string(),
                None => text,
            }
        };
        let prefix = field(345, 155);
        let name = if prefix.is_empty() { field(0, 100) } else { format!("{prefix}/{}", field(0, 100)) };
        let size_field = field(124, 12);
        let size_text = size_field.trim();
        let size = size_text.chars().take_while(|c| ('0'..='7').contains(c)).collect::<String>();
        let size = usize::from_str_radix(&size, 8).unwrap_or(0);
        let kind = if header[156] != 0 { header[156] as char } else { '0' };
        let end = (offset + 512 + size).min(buffer.len());
        let body = &buffer[(offset + 512).min(buffer.len())..end];
        match kind {
            'x' => {
                let text = String::from_utf8_lossy(body);
                long_name = pax_path(&text);
            }
            'L' => {
                let text = String::from_utf8_lossy(body).into_owned();
                long_name = Some(match text.find('\0') {
                    Some(at) => text[..at].to_string(),
                    None => text,
                });
            }
            _ => {
                if kind == '0' || kind == '7' {
                    let key = long_name.take().filter(|n| !n.is_empty()).unwrap_or(name);
                    match files.iter_mut().find(|(n, _)| *n == key) {
                        Some(entry) => entry.1 = body.to_vec(),
                        None => files.push((key, body.to_vec())),
                    }
                }
                long_name = None;
            }
        }
        offset += 512 + size.div_ceil(512) * 512;
    }
    files
}

/// /\d+ path=([^\n]*)\n/: the path a pax header gives
fn pax_path(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut at = 0;
    while let Some(found) = text[at..].find(" path=") {
        let start = at + found;
        let digits_before = start > 0 && bytes[start - 1].is_ascii_digit();
        let value_start = start + 6;
        if digits_before {
            if let Some(end) = text[value_start..].find('\n') {
                return Some(text[value_start..value_start + end].to_string());
            }
            return None;
        }
        at = start + 1;
    }
    None
}

/// Joplin's own serialisation, read the way it reads it: properties from the end up to the first blank
/// line, then the title on the first line and the body after the line below it
pub fn joplin_item(text: &str) -> Option<HashMap<String, String>> {
    let text = text.replace("\r\n", "\n");
    let lines: Vec<&str> = text.split('\n').collect();
    let mut item: HashMap<String, String> = HashMap::new();
    let mut body: Vec<&str> = Vec::new();
    let mut reading_props = true;
    for line in lines.iter().rev() {
        if reading_props {
            if line.trim().is_empty() {
                if !item.is_empty() {
                    reading_props = false;
                }
                continue;
            }
            let at = line.find(':')?;
            item.insert(line[..at].trim().to_string(), line[at + 1..].trim().to_string());
        } else {
            body.insert(0, line);
        }
    }
    let title = if body.is_empty() {
        String::new()
    } else {
        let title = body[0].to_string();
        body.drain(..body.len().min(2));
        title
    };
    item.insert("title".into(), title);
    item.insert("body".into(), body.join("\n"));
    Some(item)
}

fn prop<'a>(item: &'a HashMap<String, String>, name: &str) -> &'a str {
    item.get(name).map(String::as_str).unwrap_or("")
}

pub fn import_jex(store: &mut Store, buffer: &[u8], counts: &mut Counts, add: &mut AddResource) -> Result<(), String> {
    let files = untar(buffer);
    let mut items: Vec<HashMap<String, String>> = Vec::new();
    for (name, bytes) in &files {
        let is_item = name.len() == 35 && name.ends_with(".md") && data::is_id(&name[..32]);
        if is_item {
            if let Some(item) = joplin_item(&String::from_utf8_lossy(bytes)) {
                if !prop(&item, "id").is_empty() && !prop(&item, "type_").is_empty() {
                    items.push(item);
                }
            }
        }
    }
    let of = |kind: &'static str| items.iter().filter(move |item| prop(item, "type_") == kind);
    let now = data::now_ms();
    let time = |item: &HashMap<String, String>, name: &str| {
        let value = item.get(name).map(|s| Value::String(s.clone()));
        data::ms(time_of(value.as_ref(), now))
    };
    for folder in of("2") {
        let parent = prop(folder, "parent_id");
        upsert(store, Kind::Notebooks, json!({
            "id": id_for("joplin", prop(folder, "id")),
            "title": if prop(folder, "title").is_empty() { t!("Untitled") } else { prop(folder, "title").to_string() },
            "parent": if parent.is_empty() { Value::Null } else { Value::String(id_for("joplin", parent)) },
            "created": time(folder, "created_time"),
            "updated": time(folder, "updated_time"),
        }));
        counts.notebooks += 1;
    }
    for resource in of("4") {
        let id = prop(resource, "id");
        let prefix = format!("resources/{id}");
        let file = files.iter().find(|(name, _)| name.starts_with(&prefix));
        if let (Some((_, bytes)), true) = (file, data::is_id(id)) {
            let name = [prop(resource, "filename"), prop(resource, "title")].into_iter().find(|n| !n.is_empty()).map(str::to_string).unwrap_or_else(|| {
                let extension = prop(resource, "file_extension");
                format!("{id}.{}", if extension.is_empty() { "bin" } else { extension })
            });
            add(store, &name, prop(resource, "mime"), bytes, id)?;
            counts.attachments += 1;
        }
    }
    for tag in of("5") {
        upsert(store, Kind::Tags, json!({
            "id": id_for("joplin", prop(tag, "id")),
            "title": if prop(tag, "title").is_empty() { t!("tag") } else { prop(tag, "title").to_string() },
        }));
    }
    let mut tags_of: HashMap<String, Vec<String>> = HashMap::new();
    for link in of("6") {
        tags_of.entry(prop(link, "note_id").to_string()).or_default().push(id_for("joplin", prop(link, "tag_id")));
    }
    let mut fallback: Option<String> = None;
    for note in of("1") {
        let id = id_for("joplin", prop(note, "id"));
        if prop(note, "is_todo") == "1" {
            let due_ms = js_to_number(Some(&Value::String(prop(note, "todo_due").to_string())));
            let due = (due_ms > 0.0).then(|| crate::dates::local_ms(due_ms)).flatten();
            let completed = js_to_number(Some(&Value::String(prop(note, "todo_completed").to_string())));
            upsert(store, Kind::Tasks, json!({
                "id": id,
                "title": if prop(note, "title").is_empty() { t!("Untitled") } else { prop(note, "title").to_string() },
                "notes": prop(note, "body"),
                "project": null, "section": null, "parent": null,
                "due": due.as_ref().map(|d| crate::dates::iso(d.year() as i64, d.month() as i64, d.day_of_month() as i64)),
                "time": due.as_ref().map(|d| format!("{:02}:{:02}", d.hour(), d.minute())),
                "reminder": if due.is_some() { json!(0) } else { Value::Null },
                "priority": 4, "labels": [], "pinned": false, "repeat": null,
                "done": if completed > 0.0 { data::ms(completed) } else { Value::Null },
                "created": time(note, "created_time"),
                "order": time(note, "created_time"),
            }));
            counts.tasks += 1;
            continue;
        }
        let parent = prop(note, "parent_id");
        let mut notebook = (!parent.is_empty()).then(|| id_for("joplin", parent));
        if notebook.as_ref().is_none_or(|id| !store.has(Kind::Notebooks, id)) {
            if fallback.is_none() {
                fallback = Some(import_notebook(store));
            }
            notebook = fallback.clone();
        }
        upsert(store, Kind::Notes, json!({
            "id": id, "notebook": notebook, "title": prop(note, "title"), "body": prop(note, "body"),
            "tags": tags_of.get(prop(note, "id")).cloned().unwrap_or_default(),
            "created": time(note, "created_time"), "updated": time(note, "updated_time"), "trashed": null,
        }));
        counts.notes += 1;
    }
    Ok(())
}

fn upsert(store: &mut Store, kind: Kind, item: Value) {
    if let Value::Object(item) = item {
        store.upsert(kind, item);
    }
}

// --- Planify ------------------------------------------------------------------------------------------------

/// Planify's colours are Todoist's; each goes to the nearest of the few here
const PLANIFY_COLOURS: &[(&str, &str)] = &[
    ("berry_red", "pink"),
    ("red", "red"),
    ("orange", "orange"),
    ("yellow", "yellow"),
    ("olive_green", "green"),
    ("lime_green", "green"),
    ("green", "green"),
    ("mint_green", "teal"),
    ("teal", "teal"),
    ("sky_blue", "blue"),
    ("light_blue", "blue"),
    ("blue", "blue"),
    ("grape", "violet"),
    ("violet", "violet"),
    ("lavender", "violet"),
    ("magenta", "pink"),
    ("salmon", "orange"),
    ("charcoal", "slate"),
    ("grey", "slate"),
    ("taupe", "slate"),
];

fn colour(value: Option<&Value>) -> &'static str {
    let name = value.and_then(Value::as_str).unwrap_or("");
    PLANIFY_COLOURS.iter().find(|(planify, _)| *planify == name).map(|(_, own)| *own).unwrap_or("violet")
}

fn list<'a>(data: &'a Value, name: &str) -> Vec<&'a Value> {
    data.get(name).and_then(Value::as_array).map(|items| items.iter().collect()).unwrap_or_default()
}

/// String(value || fallback)
fn text_or(value: Option<&Value>, fallback: String) -> String {
    if data::truthy(value) { data::text(value) } else { fallback }
}

/// Planify's backup (Preferences, Backups): its own JSON, with the due date as JSON inside a string
pub fn import_planify(store: &mut Store, planify: &Value, counts: &mut Counts) {
    let mut label_of: HashMap<String, String> =
        store.values(Kind::Labels).map(|label| (data::text(label.get("title")).to_lowercase(), label.id().to_string())).collect();
    for label in list(planify, "labels").into_iter().filter(|item| !item.is("is_deleted")) {
        let name = data::text(label.get("name"));
        if let std::collections::hash_map::Entry::Vacant(slot) = label_of.entry(name.to_lowercase()) {
            let id = id_for("planify", &data::text(label.get("id")));
            upsert(store, Kind::Labels, json!({ "id": id, "title": name, "color": colour(label.get("color")) }));
            slot.insert(id);
        }
    }
    let mut inbox: HashSet<String> = HashSet::new();
    for project in list(planify, "projects").into_iter().filter(|item| !item.is("is_deleted")) {
        if project.is("inbox_project") {
            inbox.insert(data::text(project.get("id")));
            continue;
        }
        upsert(store, Kind::Projects, json!({
            "id": id_for("planify", &data::text(project.get("id"))),
            "title": text_or(project.get("name"), t!("Untitled")),
            "color": colour(project.get("color")),
            "order": data::ms(number_or(project.get("child_order"), 0.0)),
            "created": data::ms(data::now_ms()),
        }));
        counts.projects += 1;
    }
    let project_of = |store: &Store, id: Option<&Value>| -> Value {
        if !data::truthy(id) || inbox.contains(&data::text(id)) {
            return Value::Null;
        }
        let own = id_for("planify", &data::text(id));
        if store.has(Kind::Projects, &own) { Value::String(own) } else { Value::Null }
    };
    for section in list(planify, "sections").into_iter().filter(|item| !item.is("is_deleted") && !item.is("is_archived")) {
        let project = project_of(store, section.get("project_id"));
        if !project.is_null() {
            upsert(store, Kind::Sections, json!({
                "id": id_for("planify", &data::text(section.get("id"))),
                "project": project,
                "title": text_or(section.get("name"), t!("Untitled")),
                "order": data::ms(number_or(section.get("section_order"), 0.0)),
            }));
        }
    }
    let unit_of = |kind: f64| match kind as i64 {
        _ if kind.fract() != 0.0 => None,
        2 => Some("day"),
        3 => Some("week"),
        4 => Some("month"),
        5 => Some("year"),
        _ => None,
    };
    let now = data::now_ms();
    for item in list(planify, "items").into_iter().filter(|entry| !entry.is("is_deleted")) {
        let due: Value = match item.get("due") {
            Some(Value::String(text)) => data::parse_json(text).ok().filter(|v| !v.is_null()).unwrap_or_else(|| json!({})),
            Some(other) if data::truthy(Some(other)) => other.clone(),
            _ => json!({}),
        };
        let date_text = if data::truthy(due.get("date")) { data::text(due.get("date")) } else { String::new() };
        let (date, clock) = planify_date(&date_text);
        let unit = if due.is("is_recurring") { unit_of(js_to_number(due.get("recurrency_type"))) } else { None };
        let section_id = id_for("planify", &data::text(item.get("section_id")));
        let section = if item.is("section_id") && store.has(Kind::Sections, &section_id) { Value::String(section_id) } else { Value::Null };
        let labels: Vec<Value> = item
            .get("labels")
            .and_then(Value::as_array)
            .map(|names| {
                names.iter().filter_map(|name| label_of.get(&data::text(Some(name)).to_lowercase()).cloned()).map(Value::String).collect()
            })
            .unwrap_or_default();
        let priority = (5.0 - number_or(item.get("priority"), 1.0)).clamp(1.0, 4.0);
        let project = project_of(store, item.get("project_id"));
        upsert(store, Kind::Tasks, json!({
            "id": id_for("planify", &data::text(item.get("id"))),
            "title": text_or(item.get("content"), t!("Untitled")),
            "notes": text_or(item.get("description"), String::new()),
            "project": project,
            "section": section,
            "parent": if item.is("parent_id") { Value::String(id_for("planify", &data::text(item.get("parent_id")))) } else { Value::Null },
            "due": date.clone(),
            "time": clock,
            "reminder": null,
            "repeat": match (unit, &date) {
                (Some(unit), Some(_)) => json!({ "every": data::ms(number_or(due.get("recurrency_interval"), 1.0).max(1.0)), "unit": unit }),
                _ => Value::Null,
            },
            // Planify counts priority the Todoist way, 4 being the highest
            "priority": data::ms(if priority.is_nan() { 1.0 } else { priority }),
            "labels": labels,
            "pinned": item.is("pinned"),
            "done": if item.is("checked") { data::ms(time_of(item.get("completed_at"), now)) } else { Value::Null },
            "created": data::ms(time_of(item.get("added_at"), now)),
            "order": data::ms(number_or(item.get("child_order"), 0.0)),
        }));
        counts.tasks += 1;
    }
}

/// /^(\d{4}-\d{2}-\d{2})(?:T(\d{2}):(\d{2}))?/: the date, and the time when there is one
fn planify_date(text: &str) -> (Option<String>, Option<String>) {
    let bytes = text.as_bytes();
    let digit = |at: usize| bytes.get(at).is_some_and(u8::is_ascii_digit);
    let is_date = (0..4).all(digit) && bytes.get(4) == Some(&b'-') && digit(5) && digit(6) && bytes.get(7) == Some(&b'-') && digit(8) && digit(9);
    if !is_date {
        return (None, None);
    }
    let date = text[..10].to_string();
    let has_time = bytes.get(10) == Some(&b'T') && digit(11) && digit(12) && bytes.get(13) == Some(&b':') && digit(14) && digit(15);
    (Some(date), has_time.then(|| format!("{}:{}", &text[11..13], &text[14..16])))
}

// --- Markdown -----------------------------------------------------------------------------------------------

/// Found again by its name, which is why that is the same in every language
pub fn import_notebook(store: &mut Store) -> String {
    if let Some(found) = store.values(Kind::Notebooks).find(|notebook| notebook.str("title") == "Imported" && !notebook.is("parent")) {
        return found.id().to_string();
    }
    let id = data::new_id();
    let now = data::ms(data::now_ms());
    store.put(Kind::Notebooks, json!({ "id": id, "title": "Imported", "parent": null, "created": now, "updated": now }));
    id
}

/// What JSON.parse makes of a front matter value, or the text itself
fn front_value(raw: &str) -> Value {
    data::parse_json(raw).unwrap_or_else(|_| Value::String(raw.to_string()))
}

pub fn import_markdown(store: &mut Store, file: &str, text: &str, counts: &mut Counts) {
    let mut body = text.replace("\r\n", "\n");
    let mut title = String::new();
    let mut tags: Vec<String> = Vec::new();
    // /^---\n([\s\S]*?)\n---\n?/
    if let Some(rest) = body.strip_prefix("---\n") {
        let end = rest.find("\n---").filter(|_| true);
        let front = end.map(|at| (rest[..at].to_string(), at));
        if let Some((front, at)) = front {
            let mut cut = 4 + at + 4;
            if body[cut..].starts_with('\n') {
                cut += 1;
            }
            body = body[cut..].to_string();
            let value = |name: &str| {
                front.lines().find_map(|line| line.strip_prefix(&format!("{name}:")).map(|v| v.trim().to_string()))
            };
            let title_value = front_value(&value("title").unwrap_or_default());
            title = if data::truthy(Some(&title_value)) { data::text(Some(&title_value)) } else { String::new() };
            if let Value::Array(list) = front_value(&value("tags").unwrap_or_default()) {
                tags = list.iter().map(|tag| data::text(Some(tag))).collect();
            }
        }
    }
    if title.is_empty() {
        // /^#\s+(.+)$/m, or the file's name without its extension
        title = body
            .lines()
            .find_map(|line| {
                let rest = line.strip_prefix('#')?;
                let trimmed = rest.trim_start();
                (trimmed.len() < rest.len() && !trimmed.is_empty()).then(|| trimmed.to_string())
            })
            .unwrap_or_else(|| {
                let base = file.rsplit('/').next().unwrap_or(file);
                match base.rfind('.') {
                    Some(at) if at + 1 < base.len() => base[..at].to_string(),
                    _ => base.to_string(),
                }
            });
    }
    let tag_ids: Vec<Value> = tags
        .iter()
        .map(|name| {
            if let Some(found) = store.values(Kind::Tags).find(|tag| data::text(tag.get("title")).to_lowercase() == name.to_lowercase()) {
                return Value::String(found.id().to_string());
            }
            let id = data::new_id();
            store.put(Kind::Tags, json!({ "id": id, "title": name }));
            Value::String(id)
        })
        .collect();
    let id = data::new_id();
    let notebook = import_notebook(store);
    let now = data::ms(data::now_ms());
    store.put(Kind::Notes, json!({
        "id": id, "notebook": notebook, "title": title, "body": body.trim_start_matches('\n'), "tags": tag_ids,
        "created": now, "updated": now, "trashed": null,
    }));
    counts.notes += 1;
}

// --- A Notes backup ---------------------------------------------------------------------------------------------

/// No larger than the longest text there can be, which is all a backup unpacked to in V8
pub const MAX_STRING_LENGTH: u64 = (1 << 29) - 24;

/// What a backup holds, unsealed (with the key its passphrase gave, when it is encrypted) and unpacked
pub fn open_backup(file: &Value, backup_key: Option<&Key>) -> Result<Value, String> {
    let packed = vault::unbase64(file.get("data").and_then(Value::as_str).unwrap_or(""));
    let packed = match backup_key {
        // Node's own words for a backup the key does not open
        Some(key) => vault::unseal(key, &packed, "backup").map_err(|_| String::from("Unsupported state or unable to authenticate data"))?,
        None => packed,
    };
    let damaged = || t!("This backup is damaged or too large to open.");
    let mut unpacked = Vec::new();
    flate2::read::GzDecoder::new(&packed[..]).take(MAX_STRING_LENGTH + 1).read_to_end(&mut unpacked).map_err(|_| damaged())?;
    if unpacked.len() as u64 > MAX_STRING_LENGTH {
        return Err(damaged());
    }
    data::parse_json(&String::from_utf8_lossy(&unpacked)).map_err(|error| error.to_string())
}

/// What a backup holds, added to what is here: its attachments, then every item with an id
pub fn import_backup(store: &mut Store, unpacked: &Value, counts: &mut Counts, add: &mut AddResource) -> Result<(), String> {
    let saved = Store::normalise(unpacked.get("store").unwrap_or(&Value::Null));
    if let Some(resources) = unpacked.get("resources").and_then(Value::as_object) {
        for (id, bytes) in resources {
            if let (true, Some(resource)) = (data::is_id(id), saved.resources.get(id)) {
                let name = data::text(resource.get("name"));
                let mime = if data::truthy(resource.get("mime")) { data::text(resource.get("mime")) } else { String::new() };
                add(store, &name, &mime, &vault::unbase64(&data::text(Some(bytes))), id)?;
                counts.attachments += 1;
            }
        }
    }
    for kind in Kind::ALL {
        for item in saved.values(kind) {
            if data::value_is_id(item.get("id").unwrap_or(&Value::Null)) {
                store.put(kind, item.clone());
                counts.add(kind);
            }
        }
    }
    Ok(())
}

/// The record a resource gets as it is added from an import (addResource in main.js)
pub fn record(store: &mut Store, name: &str, mime: &str, size: usize, id: &str) {
    let mime = if mime.is_empty() { crate::backend::type_of(name) } else { mime.to_string() };
    store.resources.insert(id.to_string(), crate::backend::resource_record(id, name, &mime, size));
}

/// The backup file main.js wrote: everything, attachments included, packed, and sealed with the notes' own
/// key, which it carries wrapped under the current passphrase. The passkeys are left out of it.
pub fn backup_file(store: &Store, resources: Map<String, Value>, sealed: Option<(&Key, &Value)>) -> String {
    use std::io::Write;
    let body = json!({ "store": store.to_value(), "resources": resources }).to_string();
    let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    let _ = encoder.write_all(body.as_bytes());
    let packed = encoder.finish().unwrap_or_default();
    let mut file = json!({
        "format": "amethystora-notes-backup",
        "version": 1,
        "created": iso_string(data::now_ms()),
        "encrypted": sealed.is_some(),
    });
    match sealed {
        Some((key, vault_value)) => {
            data::set(&mut file, "cipher", vault_value.get("cipher").cloned().unwrap_or(Value::Null));
            data::set(&mut file, "kdf", vault_value.get("kdf").cloned().unwrap_or(Value::Null));
            data::set(&mut file, "key", vault_value.get("key").cloned().unwrap_or(Value::Null));
            data::set(&mut file, "data", vault::base64(&vault::seal(key, &packed, "backup")));
        }
        None => data::set(&mut file, "data", vault::base64(&packed)),
    }
    file.to_string()
}

/// new Date(ms).toISOString()
pub fn iso_string(ms: f64) -> String {
    let total = ms.floor() as i64;
    let days = total.div_euclid(86400000);
    let rest = total.rem_euclid(86400000);
    let (year, month, day) = crate::dates::civil_from_days(days);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{:03}Z",
        rest / 3600000,
        rest / 60000 % 60,
        rest / 1000 % 60,
        rest % 1000
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_and_times_as_main_js() {
        assert_eq!(id_for("joplin", "f0000000000000000000000000000001"), "f0000000000000000000000000000001");
        // crypto.createHash('sha256').update('planify:P1').digest('hex').slice(0, 32), from the fixture
        assert_eq!(id_for("planify", "P1"), "c5399b131888e8ad4cb4ced5ae5173ed");
        assert_eq!(date_parse("2024-05-01T08:00:00.000Z"), 1714550400000.0);
        assert_eq!(date_parse("2024-05-01"), 1714521600000.0);
        assert_eq!(date_parse("2024-05-01T08:00:00+02:00"), 1714543200000.0);
        assert!(date_parse("").is_nan() && date_parse("soon").is_nan());
        assert_eq!(time_of(Some(&Value::from("")), 5.0), 5.0);
        assert_eq!(js_to_number(Some(&Value::from("3"))), 3.0);
        assert!(js_to_number(Some(&Value::from("x"))).is_nan());
        assert_eq!(number_or(Some(&Value::from(true)), 9.0), 1.0);
        assert_eq!(iso_string(1714550400123.0), "2024-05-01T08:00:00.123Z");
        assert_eq!(planify_date("2024-05-04T08:30:00"), (Some("2024-05-04".into()), Some("08:30".into())));
        assert_eq!(planify_date("2024-05-06"), (Some("2024-05-06".into()), None));
        assert_eq!(planify_date(""), (None, None));
    }

    #[test]
    fn reads_joplin_items() {
        let item = joplin_item("Title\n\nBody line\n\nmore\n\nid: abc\ntype_: 1").unwrap();
        assert_eq!(item["title"], "Title");
        assert_eq!(item["body"], "Body line\n\nmore");
        assert_eq!(item["id"], "abc");
        let folder = joplin_item("Folder\n\nid: x\ntype_: 2").unwrap();
        assert_eq!(folder["title"], "Folder");
        assert_eq!(folder["body"], "");
        assert!(joplin_item("no properties here").is_none());
    }
}
