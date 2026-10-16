//! The notes and tasks as main.js kept them: one JSON document, `{ version, settings, resources, notebooks,
//! notes, tags, revisions, projects, sections, tasks, labels }`, each kind an object of items by their id.
//!
//! The items stay JSON values, exactly as they were read: whatever the Electron window, an import or a
//! backup put in one is written back as it was, so that a file goes back and forth between the two windows
//! (an image rolled back, then forward again) and loses nothing. The page reads them through the accessors
//! below, which read them the way JavaScript did: a missing field, `null`, `0` and `""` all count as not set.

use serde_json::{Map, Value};

/// The kinds of item, in main.js's order (KINDS)
pub const KINDS: [&str; 8] = ["notebooks", "notes", "tags", "revisions", "projects", "sections", "tasks", "labels"];

/// The settings the page may change, and what each may be (SETTINGS in main.js)
pub fn valid_setting(name: &str, value: &Value) -> bool {
    match name {
        "autoLock" => value.as_i64().is_some_and(|n| (0..=1440).contains(&n)) && is_integer(value),
        "background" => value.is_boolean(),
        "layout" => matches!(value.as_str(), Some("edit" | "split" | "preview")),
        "noteSort" => matches!(value.as_str(), Some("updated" | "created" | "title")),
        _ => false,
    }
}

fn is_integer(value: &Value) -> bool {
    value.as_f64().is_some_and(|n| n.fract() == 0.0)
}

/// main.js's ID: 32 lower-case hexadecimal digits
pub fn is_id(text: &str) -> bool {
    text.len() == 32 && text.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

pub fn value_is_id(value: &Value) -> bool {
    value.as_str().is_some_and(is_id)
}

/// A new id: 16 random bytes in hexadecimal, as crypto.randomBytes(16).toString('hex')
pub fn new_id() -> String {
    let mut bytes = [0u8; 16];
    crate::vault::random(&mut bytes);
    hex(&bytes)
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Milliseconds since the epoch, as Date.now()
pub fn now_ms() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as f64).unwrap_or(0.0)
}

/// A number of milliseconds as JSON writes it: a whole number without a point
pub fn ms(value: f64) -> Value {
    if value.fract() == 0.0 && value.abs() < 9.0e15 { Value::from(value as i64) } else { Value::from(value) }
}

// --- Reading values as JavaScript did ------------------------------------------------------------------------

/// JavaScript's truthiness: everything but null, false, 0, NaN and ""
pub fn truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().is_some_and(|n| n != 0.0 && !n.is_nan()),
        Some(Value::String(s)) => !s.is_empty(),
        Some(_) => true,
    }
}

/// What String() made of a value: a string as it is, a number written out, null and missing as ""
pub fn text(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => js_number(n.as_f64().unwrap_or(0.0)),
        Some(Value::Bool(b)) => b.to_string(),
        Some(other) => other.to_string(),
    }
}

pub fn js_number(n: f64) -> String {
    if n.fract() == 0.0 && n.abs() < 1e21 { format!("{}", n as i64) } else { format!("{n}") }
}

/// The fields of one item
pub trait Fields {
    fn field(&self, name: &str) -> Option<&Value>;

    /// A string field, "" when it is not a string
    fn str(&self, name: &str) -> &str {
        self.field(name).and_then(Value::as_str).unwrap_or("")
    }

    /// A string field that is set (`item.x` truthy and a string)
    fn opt(&self, name: &str) -> Option<&str> {
        self.field(name).and_then(Value::as_str).filter(|s| !s.is_empty())
    }

    fn num(&self, name: &str) -> Option<f64> {
        self.field(name).and_then(Value::as_f64)
    }

    /// `item.x || 0`
    fn num_or_zero(&self, name: &str) -> f64 {
        self.num(name).filter(|n| !n.is_nan()).unwrap_or(0.0)
    }

    fn is(&self, name: &str) -> bool {
        truthy(self.field(name))
    }

    /// The strings of a list field, such as a note's tags
    fn list(&self, name: &str) -> Vec<String> {
        match self.field(name) {
            Some(Value::Array(items)) => items.iter().map(|item| text(Some(item))).collect(),
            _ => Vec::new(),
        }
    }

    fn id(&self) -> &str {
        self.str("id")
    }

    fn title(&self) -> &str {
        self.str("title")
    }
}

impl Fields for Value {
    fn field(&self, name: &str) -> Option<&Value> {
        self.get(name)
    }
}

impl Fields for Map<String, Value> {
    fn field(&self, name: &str) -> Option<&Value> {
        self.get(name)
    }
}

/// Sets a field of an item, which is always an object
pub fn set(item: &mut Value, name: &str, value: impl Into<Value>) {
    if let Some(object) = item.as_object_mut() {
        object.insert(name.to_string(), value.into());
    }
}

/// `Object.assign(item, changes)`
pub fn assign(item: &mut Value, changes: &Map<String, Value>) {
    if let Some(object) = item.as_object_mut() {
        for (name, value) in changes {
            object.insert(name.clone(), value.clone());
        }
    }
}

// --- The store ---------------------------------------------------------------------------------------------

/// The whole of the notes and tasks while they are open
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Store {
    pub settings: Map<String, Value>,
    pub resources: Map<String, Value>,
    /// The eight kinds, in KINDS' order
    pub kinds: [Map<String, Value>; 8],
}

/// One of the kinds, by its place in KINDS
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Kind {
    Notebooks = 0,
    Notes = 1,
    Tags = 2,
    Revisions = 3,
    Projects = 4,
    Sections = 5,
    Tasks = 6,
    Labels = 7,
}

impl Kind {
    pub const ALL: [Kind; 8] =
        [Kind::Notebooks, Kind::Notes, Kind::Tags, Kind::Revisions, Kind::Projects, Kind::Sections, Kind::Tasks, Kind::Labels];

    pub fn name(self) -> &'static str {
        KINDS[self as usize]
    }

    pub fn from_name(name: &str) -> Option<Kind> {
        KINDS.iter().position(|kind| *kind == name).map(|at| Kind::ALL[at])
    }
}

impl Store {
    /// emptyStore()
    pub fn empty() -> Store {
        Store::default()
    }

    /// normalise(data): every kind that is an object, the settings if they are one, and nothing else
    pub fn normalise(data: &Value) -> Store {
        let mut store = Store::empty();
        let object = |name: &str| data.get(name).and_then(Value::as_object).cloned();
        for kind in Kind::ALL {
            if let Some(items) = object(kind.name()) {
                store.kinds[kind as usize] = items;
            }
        }
        if let Some(resources) = object("resources") {
            store.resources = resources;
        }
        if let Some(settings) = object("settings") {
            store.settings = settings;
        }
        store
    }

    /// JSON.stringify(store)
    pub fn to_json(&self) -> String {
        self.to_value().to_string()
    }

    pub fn to_value(&self) -> Value {
        let mut out = Map::new();
        out.insert("version".into(), Value::from(1));
        out.insert("settings".into(), Value::Object(self.settings.clone()));
        out.insert("resources".into(), Value::Object(self.resources.clone()));
        for kind in Kind::ALL {
            out.insert(kind.name().into(), Value::Object(self.kinds[kind as usize].clone()));
        }
        Value::Object(out)
    }

    pub fn kind(&self, kind: Kind) -> &Map<String, Value> {
        &self.kinds[kind as usize]
    }

    pub fn kind_mut(&mut self, kind: Kind) -> &mut Map<String, Value> {
        &mut self.kinds[kind as usize]
    }

    pub fn get(&self, kind: Kind, id: &str) -> Option<&Value> {
        self.kind(kind).get(id)
    }

    pub fn get_mut(&mut self, kind: Kind, id: &str) -> Option<&mut Value> {
        self.kind_mut(kind).get_mut(id)
    }

    pub fn has(&self, kind: Kind, id: &str) -> bool {
        !id.is_empty() && self.kind(kind).contains_key(id)
    }

    /// store[kind][item.id] = item
    pub fn put(&mut self, kind: Kind, item: Value) {
        let id = item.id().to_string();
        if is_id(&id) {
            self.kind_mut(kind).insert(id, item);
        }
    }

    /// `{ ...store[kind][item.id], ...item }`
    pub fn upsert(&mut self, kind: Kind, item: Map<String, Value>) {
        let id = item.get("id").and_then(Value::as_str).unwrap_or("").to_string();
        let entry = self.kind_mut(kind).entry(id).or_insert_with(|| Value::Object(Map::new()));
        if !entry.is_object() {
            *entry = Value::Object(Map::new());
        }
        assign(entry, &item);
    }

    pub fn values(&self, kind: Kind) -> impl Iterator<Item = &Value> {
        self.kind(kind).values()
    }

    /// A setting, if it is one the page may have set
    pub fn setting(&self, name: &str) -> Option<&Value> {
        self.settings.get(name)
    }
}

// --- Reading JSON that JavaScript wrote ------------------------------------------------------------------

/// JSON as JSON.parse reads it. JavaScript's strings may hold half of a pair of surrogates (a name cut at 200
/// characters in the middle of an emoji), which JSON.stringify writes as `\ud83d` and serde refuses: such a
/// half is read as U+FFFD, the replacement character, rather than the whole file being refused.
pub fn parse_json(text: &str) -> Result<Value, serde_json::Error> {
    match serde_json::from_str(text) {
        Ok(value) => Ok(value),
        Err(error) => match without_lone_surrogates(text) {
            Some(fixed) => serde_json::from_str(&fixed),
            None => Err(error),
        },
    }
}

/// The text with every escaped surrogate that is not half of a pair replaced, or None when there is none
fn without_lone_surrogates(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let hex4 = |at: usize| -> Option<u16> {
        let digits = text.get(at..at + 4)?;
        u16::from_str_radix(digits, 16).ok().filter(|_| digits.bytes().all(|b| b.is_ascii_hexdigit()))
    };
    let mut out = String::with_capacity(text.len());
    let mut changed = false;
    let mut in_string = false;
    let mut at = 0;
    let mut last = 0;
    while at < bytes.len() {
        match bytes[at] {
            b'"' => {
                in_string = !in_string;
                at += 1;
            }
            b'\\' if in_string => {
                if bytes.get(at + 1) == Some(&b'u') {
                    if let Some(unit) = hex4(at + 2) {
                        if (0xd800..0xdc00).contains(&unit) {
                            let low = (bytes.get(at + 6) == Some(&b'\\') && bytes.get(at + 7) == Some(&b'u'))
                                .then(|| hex4(at + 8))
                                .flatten()
                                .filter(|low| (0xdc00..0xe000).contains(low));
                            if low.is_some() {
                                at += 12;
                                continue;
                            }
                        }
                        if (0xd800..0xe000).contains(&unit) {
                            out.push_str(&text[last..at]);
                            out.push_str("\\ufffd");
                            at += 6;
                            last = at;
                            changed = true;
                            continue;
                        }
                        at += 6;
                        continue;
                    }
                }
                at += 2;
            }
            _ => at += 1,
        }
    }
    if !changed {
        return None;
    }
    out.push_str(&text[last..]);
    Some(out)
}

/// String.prototype.slice(0, n): the first n UTF-16 code units, never half of a pair
pub fn js_slice(text: &str, units: usize) -> String {
    let mut count = 0;
    let mut out = String::new();
    for c in text.chars() {
        count += c.len_utf16();
        if count > units {
            break;
        }
        out.push(c);
    }
    out
}

/// The length JavaScript gives a string, in UTF-16 code units
pub fn js_len(text: &str) -> usize {
    text.chars().map(char::len_utf16).sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalises_as_main_js_did() {
        let data: Value = serde_json::from_str(r#"{"version":7,"notes":{"a":{"id":"a"}},"tags":[1],"settings":{"layout":"edit"},"extra":1}"#).unwrap();
        let store = Store::normalise(&data);
        assert_eq!(store.kind(Kind::Notes).len(), 1);
        assert!(store.kind(Kind::Tags).is_empty());
        assert_eq!(store.settings.get("layout").and_then(Value::as_str), Some("edit"));
        let back: Value = serde_json::from_str(&store.to_json()).unwrap();
        assert_eq!(back["version"], 1);
        assert!(back.get("extra").is_none());
        assert!(back["labels"].as_object().unwrap().is_empty());
    }

    #[test]
    fn reads_what_javascript_wrote() {
        // A name cut in the middle of an emoji, as JSON.stringify writes it
        let value = parse_json(r#"{"name":"pan \ud83e","pair":"🥞","slash":"\\ud83e"}"#).unwrap();
        assert_eq!(value["name"], "pan \u{fffd}");
        assert_eq!(value["pair"], "🥞");
        assert_eq!(value["slash"], "\\ud83e");
        assert_eq!(js_slice("ab🥞cd", 3), "ab");
        assert_eq!(js_slice("ab🥞cd", 4), "ab🥞");
        assert_eq!(js_len("ab🥞"), 4);
    }

    #[test]
    fn truthiness_as_javascript() {
        let item: Value = serde_json::from_str(r#"{"a":0,"b":"","c":null,"d":1,"e":"x","f":[],"g":false}"#).unwrap();
        assert!(!item.is("a") && !item.is("b") && !item.is("c") && !item.is("missing") && !item.is("g"));
        assert!(item.is("d") && item.is("e") && item.is("f"));
        assert_eq!(text(Some(&Value::from(3))), "3");
        assert!(valid_setting("autoLock", &Value::from(10)));
        assert!(!valid_setting("autoLock", &Value::from(10.5)));
        assert!(!valid_setting("autoLock", &Value::from(2000)));
        assert!(valid_setting("layout", &Value::from("preview")));
        assert!(!valid_setting("other", &Value::from(true)));
    }
}
