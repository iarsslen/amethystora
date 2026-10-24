//! What the window shows, as plain data: a phone, its battery, a transfer, a conversation and its messages, and
//! how the words of a phone are made safe to show. Nothing here talks to the bus or draws: link.rs fills these
//! from what the program amethystora-connect says, and the pages draw them, so that everything that can be
//! tested without a display is tested here.
//!
//! Everything a phone says (its name, a text, a notification) is somebody else's text. It is shown as text in a
//! widget, never as markup (`linkify_markup` escapes all of it and adds only the anchors it makes itself), and it
//! is cleaned of control and direction-overriding characters first (`clean`).

use amethystora_ui::glib;
use amethystora_ui::i18n::{self, DateStyle, Unit, Width};
use amethystora_ui::t;

// --- Text from a phone -----------------------------------------------------------------------------------------

/// The longest name of a phone or contact, and the longest text of a message or notification, shown
pub const MOST_NAME: usize = 128;
pub const MOST_TEXT: usize = 16 * 1024;

/// `text` fit to show: control characters other than a line feed and a tab are gone (a carriage return goes with
/// them), and so are the characters that make text read the other way round (U+202A to U+202E, U+2066 to U+2069)
/// and the zero-width ones that only hide (U+200B, U+2060, U+FEFF). The joiners and the left and right marks stay,
/// since emoji and Arabic, Persian and Hebrew are written with them. Past `most` characters it is cut, and says so.
pub fn clean(text: &str, most: usize) -> String {
    let mut out = String::with_capacity(text.len().min(most * 4));
    let mut count = 0;
    for c in text.chars() {
        let c = match c {
            '\u{2028}' | '\u{2029}' => '\n',
            c => c,
        };
        let hidden = matches!(c, '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}' | '\u{200B}' | '\u{2060}' | '\u{FEFF}');
        if hidden || (c.is_control() && c != '\n' && c != '\t') {
            continue;
        }
        if count == most {
            out.push('\u{2026}');
            break;
        }
        out.push(c);
        count += 1;
    }
    out
}

/// A piece of a text: words, or a web address in it
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Segment {
    Text(String),
    /// As it was written, and the address it stands for (an address that starts "www." gets "https://")
    Link { shown: String, url: String },
}

/// The longest web address made a link: a longer one is only text
const MOST_LINK: usize = 2048;

fn starts_with_ignore_case(text: &str, prefix: &str) -> bool {
    text.get(..prefix.len()).is_some_and(|start| start.eq_ignore_ascii_case(prefix))
}

/// Where a web address starting at the beginning of `rest` ends, in bytes, or None if none starts there
fn link_len(rest: &str) -> Option<usize> {
    let after = if starts_with_ignore_case(rest, "https://") {
        8
    } else if starts_with_ignore_case(rest, "http://") {
        7
    } else if starts_with_ignore_case(rest, "www.") {
        4
    } else {
        return None;
    };
    // The address runs to the first space or quote or angle bracket
    let mut end = rest.find(|c: char| c.is_whitespace() || c.is_control() || matches!(c, '<' | '>' | '"')).unwrap_or(rest.len());
    // ...less the punctuation a sentence puts after it, and a closing bracket nothing in it opened
    loop {
        let Some(last) = rest[..end].chars().next_back() else { break };
        let opener = match last {
            ')' => Some('('),
            ']' => Some('['),
            '}' => Some('{'),
            _ => None,
        };
        let drop = match opener {
            Some(open) => rest[..end].matches(last).count() > rest[..end].matches(open).count(),
            None => matches!(last, '.' | ',' | ';' | ':' | '!' | '?' | '\'' | '\u{2026}' | '\u{201D}' | '\u{2019}'),
        };
        if !drop {
            break;
        }
        end -= last.len_utf8();
    }
    // A host has to start it
    if end <= after || !rest[after..end].chars().next().is_some_and(char::is_alphanumeric) || end > MOST_LINK {
        return None;
    }
    Some(end)
}

/// `text` as words and web addresses (http, https, and www. which is taken as https)
pub fn segments(text: &str) -> Vec<Segment> {
    let mut out = Vec::new();
    let mut plain = String::new();
    let mut at = 0;
    let mut previous: Option<char> = None;
    while at < text.len() {
        let rest = &text[at..];
        let boundary = previous.is_none_or(|c| !c.is_alphanumeric());
        let found = boundary.then(|| link_len(rest)).flatten();
        if let Some(len) = found {
            if !plain.is_empty() {
                out.push(Segment::Text(std::mem::take(&mut plain)));
            }
            let shown = &rest[..len];
            let url = if starts_with_ignore_case(shown, "www.") { format!("https://{shown}") } else { shown.to_string() };
            out.push(Segment::Link { shown: shown.to_string(), url });
            previous = shown.chars().next_back();
            at += len;
            continue;
        }
        let c = rest.chars().next().expect("not at the end");
        plain.push(c);
        previous = Some(c);
        at += c.len_utf8();
    }
    if !plain.is_empty() {
        out.push(Segment::Text(plain));
    }
    out
}

/// `text` as Pango markup for a label: all of it escaped, and an anchor round each web address, which the label
/// shows with its address as a tooltip and which a click opens (the window asks the browser, never by itself)
pub fn linkify_markup(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 16);
    for segment in segments(text) {
        match segment {
            Segment::Text(plain) => out.push_str(&glib::markup_escape_text(&plain)),
            Segment::Link { shown, url } => {
                out.push_str("<a href=\"");
                out.push_str(&glib::markup_escape_text(&url));
                out.push_str("\">");
                out.push_str(&glib::markup_escape_text(&shown));
                out.push_str("</a>");
            }
        }
    }
    out
}

/// Whether a word is a single web address (and nothing else), for a text a phone shares
pub fn only_link(text: &str) -> Option<String> {
    match segments(text.trim()).as_slice() {
        [Segment::Link { url, .. }] => Some(url.clone()),
        _ => None,
    }
}

/// The scheme and the whole of an address that a click may open: only http and https
pub fn openable(url: &str) -> bool {
    (starts_with_ignore_case(url, "https://") || starts_with_ignore_case(url, "http://")) && !url.chars().any(|c| c.is_whitespace() || c.is_control())
}

/// The longest link sent, as the program takes them
const MOST_SENT_LINK: usize = 8 * 1024;

/// What a person typed as a link to send, as the address to send, or None if it is none: a web, mail or telephone
/// address, or something that reads like the name of a site, which gets https:// as a browser would give it
pub fn sendable_link(typed: &str) -> Option<String> {
    let typed = typed.trim();
    if typed.is_empty() || typed.len() > MOST_SENT_LINK || typed.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return None;
    }
    let scheme_end = typed.find(':').filter(|&at| at > 0 && typed[..at].chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '.' | '-')) && typed.as_bytes()[0].is_ascii_alphabetic());
    match scheme_end {
        Some(at) => {
            let scheme = typed[..at].to_ascii_lowercase();
            let host_follows = typed[at..].starts_with("://") && typed.len() > at + 3;
            match scheme.as_str() {
                "http" | "https" if host_follows => Some(typed.to_string()),
                "mailto" | "tel" if typed.len() > at + 1 => Some(typed.to_string()),
                // "example.org:8080/x" has a colon and no scheme
                _ if !typed[at + 1..].starts_with("//") && typed[at + 1..].chars().next().is_some_and(|c| c.is_ascii_digit()) && typed[..at].contains('.') => Some(format!("https://{typed}")),
                _ => None,
            }
        }
        None => {
            let host = typed.split(['/', '?', '#']).next().unwrap_or("");
            (host.contains('.') && !host.starts_with('.') && !host.ends_with('.') && !host.contains('@')).then(|| format!("https://{typed}"))
        }
    }
}

/// A letter of a script written right to left: Hebrew, Arabic, Syriac, Thaana and their presentation forms
fn rtl_letter(c: char) -> bool {
    matches!(c, '\u{0590}'..='\u{08ff}' | '\u{fb1d}'..='\u{fdff}' | '\u{fe70}'..='\u{feff}')
}

/// A name put into a sentence, isolated from it so that its direction does not reorder the words round it
pub fn bdi(text: &str) -> String {
    if text.chars().any(rtl_letter) || i18n::is_rtl_now() { format!("\u{2068}{text}\u{2069}") } else { text.to_string() }
}

// --- Variants ---------------------------------------------------------------------------------------------------

/// The entries of an `a{sv}`, each value as the variant inside the box
pub fn entries(dict: &glib::Variant) -> Vec<(String, glib::Variant)> {
    if !dict.is_type(glib::VariantTy::VARDICT) {
        return Vec::new();
    }
    (0..dict.n_children())
        .filter_map(|at| {
            let entry = dict.child_value(at);
            let key = entry.child_value(0).str()?.to_string();
            let value = entry.child_value(1).as_variant()?;
            Some((key, value))
        })
        .collect()
}

fn string(value: &glib::Variant) -> Option<String> {
    value.str().map(str::to_string)
}

// --- A phone ----------------------------------------------------------------------------------------------------

/// A phone, or another computer or tablet that speaks the protocol, as the program describes it
#[derive(Debug, Clone, PartialEq)]
pub struct Device {
    pub path: String,
    pub id: String,
    pub name: String,
    pub kind: String,
    pub paired: bool,
    pub connected: bool,
    /// "none", "incoming" or "outgoing"
    pub pairing: String,
    pub pairing_key: String,
    /// When the request lapses, in seconds since the epoch
    pub pairing_deadline: i64,
    pub address: String,
    pub battery: i32,
    pub charging: bool,
    pub features: Vec<String>,
}

impl Device {
    pub fn new(path: &str) -> Device {
        Device {
            path: path.to_string(),
            id: String::new(),
            name: String::new(),
            kind: "phone".into(),
            paired: false,
            connected: false,
            pairing: "none".into(),
            pairing_key: String::new(),
            pairing_deadline: 0,
            address: String::new(),
            battery: -1,
            charging: false,
            features: Vec::new(),
        }
    }

    /// One property, as the program sent it; one of a type no phone has is left as it was
    pub fn set(&mut self, name: &str, value: &glib::Variant) {
        match name {
            "Id" => self.id = string(value).unwrap_or_default().chars().take(MOST_NAME).collect(),
            "Name" => self.name = string(value).map(|name| clean(&name, MOST_NAME).replace('\n', " ")).unwrap_or_default(),
            "Type" => self.kind = string(value).unwrap_or_default(),
            "Paired" => self.paired = value.get::<bool>().unwrap_or(self.paired),
            "Connected" => self.connected = value.get::<bool>().unwrap_or(self.connected),
            "Pairing" => self.pairing = string(value).unwrap_or_else(|| "none".into()),
            "PairingKey" => self.pairing_key = string(value).map(|key| clean(&key, 32).replace('\n', " ")).unwrap_or_default(),
            "PairingDeadline" => self.pairing_deadline = value.get::<i64>().unwrap_or(0),
            "Address" => self.address = string(value).map(|address| clean(&address, 80).replace('\n', " ")).unwrap_or_default(),
            "BatteryLevel" => self.battery = value.get::<i32>().unwrap_or(-1),
            "BatteryCharging" => self.charging = value.get::<bool>().unwrap_or(false),
            "Features" => self.features = value.get::<Vec<String>>().unwrap_or_default(),
            _ => {}
        }
    }

    /// A phone from all its properties (`GetAll`)
    pub fn from_properties(path: &str, properties: &glib::Variant) -> Device {
        let mut device = Device::new(path);
        for (name, value) in entries(properties) {
            device.set(&name, &value);
        }
        device
    }

    pub fn has(&self, feature: &str) -> bool {
        self.features.iter().any(|f| f == feature)
    }

    /// What is asked of the person, or what can be done with it now
    pub fn situation(&self) -> Situation {
        match self.pairing.as_str() {
            "incoming" => Situation::Asked,
            "outgoing" => Situation::Asking,
            _ if self.paired && self.connected => Situation::Ready,
            _ if self.paired => Situation::Away,
            _ => Situation::Nearby,
        }
    }

    /// The name to show: the phone's, or its kind when it gave none
    pub fn title(&self) -> String {
        if self.name.trim().is_empty() { kind_word(&self.kind) } else { self.name.clone() }
    }

    /// Seconds left before a request lapses, never negative
    pub fn seconds_left(&self, now: f64) -> i64 {
        (self.pairing_deadline as f64 - now).ceil().max(0.0) as i64
    }
}

/// Where a phone is in being paired and connected, in the order the page lists them
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Situation {
    /// The phone asked to pair: the person decides
    Asked,
    /// This computer asked, and waits for the phone
    Asking,
    /// Paired and connected
    Ready,
    /// Paired and out of reach
    Away,
    /// Seen, not paired
    Nearby,
}

/// "Phone", "Tablet" and the rest, for a phone that gave no name
pub fn kind_word(kind: &str) -> String {
    match kind {
        "tablet" => t!("Tablet"),
        "laptop" => t!("Laptop"),
        "desktop" => t!("Computer"),
        "tv" => t!("Television"),
        _ => t!("Phone"),
    }
}

/// The phones to list, in order: those that ask something first, then the paired ones that are here, the paired
/// ones that are away, and the rest; by name within each. A phone neither paired nor reachable has nothing to
/// offer and is left out.
pub fn listed(devices: &[Device]) -> Vec<Device> {
    let mut list: Vec<Device> = devices
        .iter()
        .filter(|d| d.paired || d.connected || d.pairing != "none")
        .cloned()
        .collect();
    list.sort_by(|a, b| {
        a.situation()
            .cmp(&b.situation())
            .then_with(|| a.title().to_lowercase().cmp(&b.title().to_lowercase()))
            .then_with(|| a.id.cmp(&b.id))
    });
    list
}

/// The phones whose texts can be read now
pub fn texting(devices: &[Device]) -> Vec<Device> {
    listed(devices).into_iter().filter(|d| d.paired && d.connected && d.has("sms")).collect()
}

/// The phones a file or a link can be sent to now
pub fn sendable(devices: &[Device]) -> Vec<Device> {
    listed(devices).into_iter().filter(|d| d.paired && d.connected && d.has("share")).collect()
}

/// The charge as a percentage, or None while the phone has not said
pub fn battery_text(device: &Device) -> Option<String> {
    (device.battery >= 0).then(|| i18n::percent(f64::from(device.battery.min(100)) / 100.0))
}

/// Low enough to say so, and not on the charger
pub fn battery_low(device: &Device) -> bool {
    (0..=15).contains(&device.battery) && !device.charging
}

// --- Sizes and times ---------------------------------------------------------------------------------------------

/// A size in bytes as people read them: "812 kB", "4.2 MB"
pub fn size(bytes: i64) -> String {
    let bytes = bytes.max(0) as f64;
    let (value, unit) = if bytes < 1000.0 {
        (bytes, Unit::Byte)
    } else if bytes < 1e6 {
        (bytes / 1e3, Unit::Kilobyte)
    } else if bytes < 1e9 {
        (bytes / 1e6, Unit::Megabyte)
    } else if bytes < 1e12 {
        (bytes / 1e9, Unit::Gigabyte)
    } else {
        (bytes / 1e12, Unit::Terabyte)
    };
    let decimals = if unit == Unit::Byte || value >= 100.0 { 0 } else { 1 };
    i18n::unit(value, unit, Width::Short, 0, decimals)
}

/// A time of day, then a weekday within the last week, then a date: "14:05", "Tue", "3 Oct", "3 Oct 2025", with
/// "now" and "N min" for the last hour. `date` is in milliseconds since the epoch.
pub fn stamp(date: i64, now: f64) -> String {
    let seconds = date as f64 / 1000.0;
    let ago = now - seconds;
    if (0.0..60.0).contains(&ago) {
        return t!("Now");
    }
    if (60.0..3600.0).contains(&ago) {
        return t!("{count, plural, one {# min} other {# min}}", count = (ago / 60.0).floor() as i64);
    }
    let days = i18n::days_from_today(seconds);
    if days == 0 {
        i18n::date(seconds, DateStyle::Time)
    } else if (-6..0).contains(&days) {
        i18n::capital(&i18n::date(seconds, DateStyle::Weekday))
    } else if same_year(seconds, now) {
        i18n::date(seconds, DateStyle::DayMonthShort)
    } else {
        i18n::date(seconds, DateStyle::DayMonthYearShort)
    }
}

fn same_year(seconds: f64, now: f64) -> bool {
    matches!((i18n::local(seconds), i18n::local(now)), (Some(a), Some(b)) if a.year == b.year)
}

/// The heading over a run of messages: "Today, 14:05", "Yesterday, 09:12", "Tue, 18:30", "3 Oct, 18:30"
pub fn moment(date: i64, now: f64) -> String {
    let seconds = date as f64 / 1000.0;
    let time = i18n::date(seconds, DateStyle::Time);
    let days = i18n::days_from_today(seconds);
    let day = if days == 0 {
        t!("Today")
    } else if days == -1 {
        t!("Yesterday")
    } else if (-6..0).contains(&days) {
        i18n::capital(&i18n::date(seconds, DateStyle::Weekday))
    } else if same_year(seconds, now) {
        i18n::date(seconds, DateStyle::DayMonthShort)
    } else {
        i18n::date(seconds, DateStyle::DayMonthYearShort)
    };
    t!("{day}, {time}", day = day, time = time)
}

// --- Transfers ---------------------------------------------------------------------------------------------------

/// A file on its way, as the Transfer signal last said
#[derive(Debug, Clone, PartialEq)]
pub struct Transfer {
    pub id: String,
    pub device: String,
    pub name: String,
    pub incoming: bool,
    pub done: i64,
    pub total: i64,
    /// "started", "progress", "finished", "failed" or "cancelled"
    pub state: String,
}

impl Transfer {
    pub fn running(&self) -> bool {
        matches!(self.state.as_str(), "started" | "progress")
    }

    /// How far along, 0 to 1, or None while the size is not known
    pub fn fraction(&self) -> Option<f64> {
        if self.state == "finished" {
            return Some(1.0);
        }
        (self.total > 0).then(|| (self.done as f64 / self.total as f64).clamp(0.0, 1.0))
    }

    /// One line: "Sending…", "4.2 MB of 12 MB", "Sent", "Did not arrive"
    pub fn status(&self) -> String {
        match (self.state.as_str(), self.incoming) {
            ("finished", false) => t!("Sent"),
            ("finished", true) => t!("Received"),
            ("failed", false) => t!("Could not be sent"),
            ("failed", true) => t!("Could not be received"),
            ("cancelled", _) => t!("Cancelled"),
            _ if self.total > 0 => t!("{done} of {total}", done = size(self.done), total = size(self.total)),
            ("started", false) | ("progress", false) => t!("Sending…"),
            _ => t!("Receiving…"),
        }
    }
}

// --- Texts -------------------------------------------------------------------------------------------------------

/// A conversation, as the phone's digest of it
#[derive(Debug, Clone, PartialEq)]
pub struct Conversation {
    pub thread: i64,
    pub addresses: Vec<String>,
    pub name: String,
    pub snippet: String,
    pub date: i64,
    pub unread: bool,
    pub group: bool,
}

impl Conversation {
    /// From one `a{sv}` of ListConversations; None without a thread to name it by
    pub fn from_dict(dict: &glib::Variant) -> Option<Conversation> {
        let mut c = Conversation { thread: -1, addresses: Vec::new(), name: String::new(), snippet: String::new(), date: 0, unread: false, group: false };
        let mut found = false;
        for (key, value) in entries(dict) {
            match key.as_str() {
                "thread_id" => {
                    if let Some(thread) = value.get::<i64>() {
                        c.thread = thread;
                        found = true;
                    }
                }
                "addresses" => c.addresses = value.get::<Vec<String>>().unwrap_or_default().iter().map(|a| clean(a, MOST_NAME).replace('\n', " ")).collect(),
                "name" => c.name = string(&value).map(|n| clean(&n, MOST_NAME).replace('\n', " ")).unwrap_or_default(),
                "snippet" => c.snippet = string(&value).map(|s| clean(&s, 512)).unwrap_or_default(),
                "date" => c.date = value.get::<i64>().unwrap_or(0),
                "unread" => c.unread = value.get::<bool>().unwrap_or(false),
                "group" => c.group = value.get::<bool>().unwrap_or(false),
                _ => {}
            }
        }
        found.then_some(c)
    }

    /// The name to show: the contact's, else the numbers
    pub fn title(&self) -> String {
        if !self.name.trim().is_empty() { self.name.clone() } else { self.addresses.join(", ") }
    }

    /// The snippet's first line, for a row
    pub fn first_line(&self) -> String {
        self.snippet.lines().find(|line| !line.trim().is_empty()).unwrap_or("").trim().to_string()
    }
}

/// A message of a conversation
#[derive(Debug, Clone, PartialEq)]
pub struct Message {
    pub id: i64,
    pub thread: i64,
    pub address: String,
    pub name: String,
    pub body: String,
    pub date: i64,
    pub outgoing: bool,
    pub read: bool,
}

impl Message {
    pub fn from_dict(dict: &glib::Variant) -> Option<Message> {
        let mut m = Message { id: 0, thread: -1, address: String::new(), name: String::new(), body: String::new(), date: 0, outgoing: false, read: true };
        let mut found = false;
        for (key, value) in entries(dict) {
            match key.as_str() {
                "id" => m.id = value.get::<i64>().unwrap_or(0),
                "thread_id" => {
                    if let Some(thread) = value.get::<i64>() {
                        m.thread = thread;
                        found = true;
                    }
                }
                "address" => m.address = string(&value).map(|a| clean(&a, MOST_NAME).replace('\n', " ")).unwrap_or_default(),
                "name" => m.name = string(&value).map(|n| clean(&n, MOST_NAME).replace('\n', " ")).unwrap_or_default(),
                "body" => m.body = string(&value).map(|b| clean(&b, MOST_TEXT)).unwrap_or_default(),
                "date" => m.date = value.get::<i64>().unwrap_or(0),
                "outgoing" => m.outgoing = value.get::<bool>().unwrap_or(false),
                "read" => m.read = value.get::<bool>().unwrap_or(true),
                _ => {}
            }
        }
        found.then_some(m)
    }

    /// Who wrote it, for a group: the contact, else the number
    pub fn sender(&self) -> &str {
        if self.name.trim().is_empty() { &self.address } else { &self.name }
    }
}

/// The conversations of an `aa{sv}`, in the order they came (newest first)
pub fn conversations(list: &glib::Variant) -> Vec<Conversation> {
    (0..list.n_children()).filter_map(|at| Conversation::from_dict(&list.child_value(at))).collect()
}

/// The messages of an `aa{sv}`, oldest first whatever order they came in
pub fn messages(list: &glib::Variant) -> Vec<Message> {
    let mut all: Vec<Message> = (0..list.n_children()).filter_map(|at| Message::from_dict(&list.child_value(at))).collect();
    all.sort_by_key(|m| (m.date, m.id));
    all
}

/// The letters in a round avatar: the first of the first two words, or None for a number or a name that starts
/// with something that is no letter
pub fn initials(name: &str) -> Option<String> {
    let letters: String = name
        .split_whitespace()
        .filter(|word| word.chars().next().is_some_and(char::is_alphabetic))
        .take(2)
        .filter_map(|word| word.chars().next())
        .flat_map(char::to_uppercase)
        .collect();
    (!letters.is_empty() && name.trim().chars().next().is_some_and(char::is_alphabetic)).then_some(letters)
}

/// A number with the punctuation, the plus and the leading zeros taken off, as contacts are matched; an address
/// with a letter or an @ in it (a name, a mail address) is kept whole in lower case
fn normalised(address: &str) -> String {
    if address.chars().any(|c| c.is_alphabetic() || c == '@') {
        return address.trim().to_lowercase();
    }
    let digits: String = address.chars().filter(char::is_ascii_digit).collect();
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() { address.trim().to_string() } else { trimmed.to_string() }
}

/// Two numbers are the same when one ends with the other, so that a number typed without its country code finds
/// the conversation with it; addresses with letters have to be the same whole
pub fn same_number(a: &str, b: &str) -> bool {
    let (a, b) = (normalised(a), normalised(b));
    if a.is_empty() || b.is_empty() {
        return false;
    }
    let letters = |s: &str| s.chars().any(|c| c.is_alphabetic() || c == '@');
    if letters(&a) || letters(&b) {
        return a == b;
    }
    a.ends_with(&b) || b.ends_with(&a)
}

/// The conversation with one person at this number, if the phone has one
pub fn find_thread(list: &[Conversation], address: &str) -> Option<i64> {
    list.iter().find(|c| !c.group && c.addresses.len() == 1 && same_number(&c.addresses[0], address)).map(|c| c.thread)
}

/// An address a message can be sent to: some digits, or a short sender name or mail address; nothing that is
/// only punctuation, and nothing a person could not have typed
pub fn valid_address(address: &str) -> bool {
    let address = address.trim();
    !address.is_empty()
        && address.chars().count() <= 64
        && !address.chars().any(char::is_control)
        && address.chars().any(|c| c.is_alphanumeric())
}

/// What the chat is made of, oldest first
#[derive(Debug, PartialEq)]
pub enum Row {
    /// A heading with the time, when more than an hour passed
    Time(i64),
    /// The message at this place of the list; whether it starts and ends a run of one sender's messages
    Bubble { at: usize, first: bool, last: bool },
}

/// More than this between two messages puts a time between them
pub const GAP_MS: i64 = 3_600_000;

/// The rows of a chat from its messages (oldest first)
pub fn rows(messages: &[Message]) -> Vec<Row> {
    let mut out = Vec::with_capacity(messages.len() + 4);
    for (at, message) in messages.iter().enumerate() {
        let gap = at == 0 || message.date - messages[at - 1].date > GAP_MS;
        if gap {
            out.push(Row::Time(message.date));
        }

        let same = |other: &Message| other.outgoing == message.outgoing && (message.outgoing || other.address == message.address);
        let first = gap || !same(&messages[at - 1]);
        let last = messages.get(at + 1).is_none_or(|next| next.date - message.date > GAP_MS || !same(next));
        out.push(Row::Bubble { at, first, last });
    }
    out
}

/// A message sent from here that the phone has not shown yet
#[derive(Debug, Clone, PartialEq)]
pub struct Pending {
    pub body: String,
    pub since: f64,
    /// How many outgoing messages with this body the phone had when it was sent
    pub seen: usize,
}

fn outgoing_with(messages: &[Message], body: &str) -> usize {
    messages.iter().filter(|m| m.outgoing && m.body == body).count()
}

impl Pending {
    pub fn new(body: &str, now: f64, messages: &[Message], pending: &[Pending]) -> Pending {
        let waiting = pending.iter().filter(|p| p.body == body).count();
        Pending { body: body.to_string(), since: now, seen: outgoing_with(messages, body) + waiting }
    }

    /// The phone has it, going by how many messages with this body it holds now
    pub fn settled(&self, messages: &[Message]) -> bool {
        outgoing_with(messages, &self.body) > self.seen
    }

    /// Nothing from the phone for this long: say it was not confirmed
    pub fn overdue(&self, now: f64) -> bool {
        now - self.since > 30.0
    }
}

/// What is still waiting for the phone, in the order sent: those it has shown since are dropped
pub fn still_pending(pending: Vec<Pending>, messages: &[Message]) -> Vec<Pending> {
    pending.into_iter().filter(|p| !p.settled(messages)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use amethystora_ui::glib::prelude::ToVariant;

    fn vardict(entries: &[(&str, glib::Variant)]) -> glib::Variant {
        let dict = glib::VariantDict::new(None);
        for (key, value) in entries {
            dict.insert_value(key, value);
        }
        dict.end()
    }

    fn message(id: i64, address: &str, body: &str, date: i64, outgoing: bool) -> Message {
        Message { id, thread: 7, address: address.into(), name: String::new(), body: body.into(), date, outgoing, read: true }
    }

    #[test]
    fn clean_keeps_text_and_drops_what_hides_it() {
        assert_eq!(clean("plain \u{1F600} text\twith\nlines", 100), "plain \u{1F600} text\twith\nlines");
        assert_eq!(clean("a\u{0}b\u{7}c\u{1b}[31md\r\ne", 100), "abc[31md\ne");
        // The characters that turn text round, and the invisible ones
        assert_eq!(clean("gpj.\u{202E}exe", 100), "gpj.exe");
        assert_eq!(clean("a\u{2066}b\u{2069}c\u{200B}d\u{FEFF}e\u{2060}f", 100), "abcdef");
        // ...but not the ones that emoji and right-to-left scripts are written with
        assert_eq!(clean("\u{1F468}\u{200D}\u{1F469}", 100), "\u{1F468}\u{200D}\u{1F469}");
        assert_eq!(clean("\u{200F}\u{0645}", 100), "\u{200F}\u{0645}");
        assert_eq!(clean("a\u{2028}b", 100), "a\nb");
    }

    #[test]
    fn clean_cuts_and_says_so() {
        assert_eq!(clean("abcdef", 6), "abcdef");
        assert_eq!(clean("abcdefg", 6), "abcdef\u{2026}");
        assert_eq!(clean("\u{e9}\u{e9}\u{e9}", 2), "\u{e9}\u{e9}\u{2026}");
    }

    #[test]
    fn links_are_found_in_sentences() {
        let found = segments("See https://example.org/a?b=1&c=2, and (http://x.example/p_(q)) or www.rust-lang.org.");
        let links: Vec<&str> = found.iter().filter_map(|s| if let Segment::Link { shown, .. } = s { Some(shown.as_str()) } else { None }).collect();
        assert_eq!(links, ["https://example.org/a?b=1&c=2", "http://x.example/p_(q)", "www.rust-lang.org"]);
        let Segment::Link { url, .. } = &found[found.len() - 2] else { panic!("a link") };
        assert_eq!(url, "https://www.rust-lang.org");
    }

    #[test]
    fn links_need_a_host_and_a_boundary() {
        for text in ["https://", "http://.", "https:// x", "xhttps://example.org", "see www.", "ahttp://a.b", "https://\u{200b}"] {
            assert!(segments(text).iter().all(|s| matches!(s, Segment::Text(_))), "{text}");
        }
        assert_eq!(segments("(www.example.org)").len(), 3);
        assert_eq!(only_link("  https://example.org/x  "), Some("https://example.org/x".into()));
        assert_eq!(only_link("https://example.org/x and more"), None);
        assert_eq!(only_link("no link"), None);
    }

    #[test]
    fn a_very_long_address_is_only_text() {
        let long = format!("https://example.org/{}", "a".repeat(3000));
        assert!(segments(&long).iter().all(|s| matches!(s, Segment::Text(_))));
    }

    #[test]
    fn markup_escapes_everything_a_phone_wrote() {
        let hostile = "<b>bold</b> <a href=\"javascript:x\">x</a> &amp; <span foreground='red'>";
        let markup = linkify_markup(hostile);
        assert!(!markup.contains("<b>") && !markup.contains("<span") && !markup.contains("<a "));
        assert!(markup.contains("&lt;b&gt;bold&lt;/b&gt;"));
        assert!(markup.contains("&amp;amp;"));
        // The one anchor there can be is the one made here, with the address escaped
        let with_link = linkify_markup("go to https://example.org/?a=1&b=2'\"");
        assert!(with_link.contains("<a href=\"https://example.org/?a=1&amp;b=2\">https://example.org/?a=1&amp;b=2</a>"), "{with_link}");
        assert_eq!(with_link.matches("<a ").count(), 1);
        // And it parses as markup, whatever it was given
        for text in [hostile, &with_link, "a < b > c", "https://a.example/\"onmouseover=\"x"] {
            assert!(gtk_parses(&linkify_markup(text)), "{text}");
        }
    }

    /// Whether the markup is well formed: Pango's own parser takes it, once the anchors this module makes (which a
    /// label reads and Pango does not) are taken out, each with an address that holds no quote of its own
    fn gtk_parses(markup: &str) -> bool {
        let mut rest = markup.to_string();
        while let Some(start) = rest.find("<a href=\"") {
            let Some(len) = rest[start + 9..].find("\">") else { return false };
            if rest[start + 9..start + 9 + len].contains(['"', '<', '>']) {
                return false;
            }
            rest.replace_range(start..start + 9 + len + 2, "");
        }
        amethystora_ui::pango::parse_markup(&rest.replace("</a>", ""), '\0').is_ok()
    }

    #[test]
    fn a_typed_link_is_a_web_mail_or_telephone_address() {
        assert_eq!(sendable_link(" https://example.org/a?b=1 ").as_deref(), Some("https://example.org/a?b=1"));
        assert_eq!(sendable_link("HTTP://example.org").as_deref(), Some("HTTP://example.org"));
        assert_eq!(sendable_link("example.org/page").as_deref(), Some("https://example.org/page"));
        assert_eq!(sendable_link("example.org:8080/x").as_deref(), Some("https://example.org:8080/x"));
        assert_eq!(sendable_link("mailto:ada@example.org").as_deref(), Some("mailto:ada@example.org"));
        assert_eq!(sendable_link("tel:+15550100").as_deref(), Some("tel:+15550100"));
        for no in ["", "   ", "hello", "javascript:alert(1)", "file:///etc/passwd", "ftp://example.org", "https://", "mailto:", "a b.org", "https://exa mple.org", "ada@example.org", ".org", "intent://x"] {
            assert_eq!(sendable_link(no), None, "{no}");
        }
        assert_eq!(sendable_link(&format!("https://example.org/{}", "a".repeat(9000))), None);
    }

    #[test]
    fn only_web_addresses_open() {
        assert!(openable("https://example.org/a"));
        assert!(openable("HTTP://example.org"));
        assert!(!openable("javascript:alert(1)"));
        assert!(!openable("file:///etc/passwd"));
        assert!(!openable("https://a b"));
    }

    #[test]
    fn a_device_is_read_from_its_properties() {
        let all = vardict(&[
            ("Id", "abc_123".to_variant()),
            ("Name", "Ada's \u{202E}phone\u{7}".to_variant()),
            ("Type", "phone".to_variant()),
            ("Paired", true.to_variant()),
            ("Connected", true.to_variant()),
            ("Pairing", "none".to_variant()),
            ("BatteryLevel", 87i32.to_variant()),
            ("BatteryCharging", true.to_variant()),
            ("Features", vec!["ping", "sms"].to_variant()),
            ("Surprise", 1u8.to_variant()),
        ]);
        let device = Device::from_properties("/org/amethystora/Connect/Device/abc_123", &all);
        assert_eq!(device.name, "Ada's phone");
        assert_eq!((device.paired, device.connected, device.battery, device.charging), (true, true, 87, true));
        assert!(device.has("sms") && !device.has("share"));
        assert_eq!(device.situation(), Situation::Ready);
        assert_eq!(battery_text(&device).as_deref(), Some("87%"));
        // A wrong type leaves the value as it was
        let mut changed = device.clone();
        changed.set("Paired", &"yes".to_variant());
        changed.set("BatteryLevel", &"87".to_variant());
        assert_eq!((changed.paired, changed.battery), (true, -1));
    }

    #[test]
    fn situations_are_told_apart() {
        let mut d = Device::new("/p");
        d.id = "a".into();
        assert_eq!(d.situation(), Situation::Nearby);
        d.paired = true;
        assert_eq!(d.situation(), Situation::Away);
        d.connected = true;
        assert_eq!(d.situation(), Situation::Ready);
        d.pairing = "incoming".into();
        assert_eq!(d.situation(), Situation::Asked);
        d.pairing = "outgoing".into();
        assert_eq!(d.situation(), Situation::Asking);
    }

    #[test]
    fn the_list_puts_what_asks_first_and_leaves_out_the_unreachable() {
        let make = |id: &str, name: &str, paired: bool, connected: bool, pairing: &str| {
            let mut d = Device::new(id);
            d.id = id.into();
            d.name = name.into();
            d.paired = paired;
            d.connected = connected;
            d.pairing = pairing.into();
            d
        };
        let all = vec![
            make("away", "Zed", true, false, "none"),
            make("near", "Mia", false, true, "none"),
            make("here2", "bob", true, true, "none"),
            make("here1", "Ann", true, true, "none"),
            make("asks", "Kim", false, true, "incoming"),
            make("gone", "Old", false, false, "none"),
        ];
        let ids: Vec<String> = listed(&all).into_iter().map(|d| d.id).collect();
        assert_eq!(ids, ["asks", "here1", "here2", "away", "near"]);
    }

    #[test]
    fn a_pairing_runs_out() {
        let mut d = Device::new("/p");
        d.pairing_deadline = 1000;
        assert_eq!(d.seconds_left(970.2), 30);
        assert_eq!(d.seconds_left(1000.0), 0);
        assert_eq!(d.seconds_left(1500.0), 0);
    }

    #[test]
    fn sizes_and_progress_read_plainly() {
        assert_eq!(size(0), "0 byte");
        assert_eq!(size(999), "999 byte");
        assert_eq!(size(4_200_000), "4.2 MB");
        assert_eq!(size(812_000), "812 kB");
        assert_eq!(size(150_000_000), "150 MB");
        let mut t = Transfer { id: "1".into(), device: "d".into(), name: "a.jpg".into(), incoming: false, done: 2_100_000, total: 4_200_000, state: "progress".into() };
        assert_eq!(t.fraction(), Some(0.5));
        assert_eq!(t.status(), "2.1 MB of 4.2 MB");
        assert!(t.running());
        t.total = 0;
        assert_eq!(t.fraction(), None);
        assert_eq!(t.status(), "Sending\u{2026}");
        t.state = "finished".into();
        assert_eq!((t.fraction(), t.status().as_str(), t.running()), (Some(1.0), "Sent", false));
        t.state = "failed".into();
        t.incoming = true;
        assert_eq!(t.status(), "Could not be received");
    }

    #[test]
    fn conversations_are_read_from_the_phone_s_digest() {
        let dict = vardict(&[
            ("thread_id", 12i64.to_variant()),
            ("addresses", vec!["+1 555 0100"].to_variant()),
            ("name", "Grace \u{202E}Hopper".to_variant()),
            ("snippet", "\n  On my way \n and more".to_variant()),
            ("date", 1_760_000_000_000i64.to_variant()),
            ("unread", true.to_variant()),
            ("group", false.to_variant()),
        ]);
        let c = Conversation::from_dict(&dict).expect("a conversation");
        assert_eq!((c.thread, c.title().as_str(), c.first_line().as_str(), c.unread), (12, "Grace Hopper", "On my way", true));
        assert!(Conversation::from_dict(&vardict(&[("name", "x".to_variant())])).is_none());
        let nameless = vardict(&[("thread_id", 1i64.to_variant()), ("addresses", vec!["111", "222"].to_variant())]);
        assert_eq!(Conversation::from_dict(&nameless).unwrap().title(), "111, 222");
    }

    #[test]
    fn messages_come_out_oldest_first() {
        let make = |id: i64, date: i64| {
            vardict(&[("id", id.to_variant()), ("thread_id", 7i64.to_variant()), ("address", "555".to_variant()), ("body", "hi".to_variant()), ("date", date.to_variant()), ("outgoing", false.to_variant())])
        };
        let list = glib::Variant::array_from_iter_with_type(glib::VariantTy::VARDICT, [make(3, 300), make(1, 100), make(2, 200)]);
        let all = messages(&list);
        assert_eq!(all.iter().map(|m| m.id).collect::<Vec<_>>(), [1, 2, 3]);
    }

    #[test]
    fn initials_come_from_names_only() {
        assert_eq!(initials("Grace Hopper").as_deref(), Some("GH"));
        assert_eq!(initials("grace").as_deref(), Some("G"));
        assert_eq!(initials("Ada B. Lovelace").as_deref(), Some("AB"));
        assert_eq!(initials("+1 555 0100"), None);
        assert_eq!(initials("5555"), None);
        assert_eq!(initials(""), None);
        assert_eq!(initials("\u{e9}lodie").as_deref(), Some("\u{c9}"));
    }

    #[test]
    fn numbers_match_by_their_ends() {
        assert!(same_number("+1 555 0100", "555-0100"));
        assert!(same_number("(555) 0100", "0015550100"));
        assert!(!same_number("555 0100", "555 0101"));
        assert!(same_number("Bank", "bank"));
        assert!(!same_number("Bank", "Bank2"));
        assert!(same_number("a@example.org", "A@EXAMPLE.ORG"));
        assert!(!same_number("", "555"));
        assert!(!same_number("000", ""));
        let list = vec![
            Conversation { thread: 1, addresses: vec!["+15550100".into(), "+15550101".into()], name: String::new(), snippet: String::new(), date: 0, unread: false, group: true },
            Conversation { thread: 2, addresses: vec!["+15550100".into()], name: String::new(), snippet: String::new(), date: 0, unread: false, group: false },
        ];
        assert_eq!(find_thread(&list, "555 0100"), Some(2));
        assert_eq!(find_thread(&list, "555 0199"), None);
    }

    #[test]
    fn addresses_are_something_a_person_typed() {
        assert!(valid_address("+1 555 0100"));
        assert!(valid_address("BANK"));
        assert!(!valid_address("   "));
        assert!(!valid_address("+ - ()"));
        assert!(!valid_address("a\u{0}b"));
        assert!(!valid_address(&"1".repeat(65)));
    }

    #[test]
    fn a_chat_has_times_and_runs() {
        let hour = GAP_MS;
        let all = vec![
            message(1, "555", "a", 0, false),
            message(2, "555", "b", 1000, false),
            message(3, "", "c", 2000, true),
            message(4, "666", "d", 3000, false),
            message(5, "666", "e", 3000 + hour + 1, false),
        ];
        assert_eq!(
            rows(&all),
            [
                Row::Time(0),
                Row::Bubble { at: 0, first: true, last: false },
                Row::Bubble { at: 1, first: false, last: true },
                Row::Bubble { at: 2, first: true, last: true },
                Row::Bubble { at: 3, first: true, last: true },
                Row::Time(3000 + hour + 1),
                Row::Bubble { at: 4, first: true, last: true },
            ]
        );
        assert!(rows(&[]).is_empty());
    }

    #[test]
    fn what_was_sent_waits_for_the_phone_to_show_it() {
        let sent = |body: &str| message(9, "", body, 5, true);
        let before = vec![sent("ok")];
        let first = Pending::new("ok", 100.0, &before, &[]);
        assert!(!first.settled(&before));
        // A second one with the same words waits for a second message
        let second = Pending::new("ok", 101.0, &before, std::slice::from_ref(&first));
        let after_one = vec![sent("ok"), sent("ok")];
        assert!(first.settled(&after_one));
        assert!(!second.settled(&after_one));
        assert!(second.settled(&[sent("ok"), sent("ok"), sent("ok")]));
        // Incoming words are no confirmation
        let mut incoming = sent("ok");
        incoming.outgoing = false;
        assert!(!first.settled(&[sent("ok"), incoming]));
        assert!(!first.overdue(120.0) && first.overdue(131.0));
    }

    #[test]
    fn still_pending_drops_the_settled() {
        let sent = |body: &str| message(9, "", body, 5, true);
        let a = Pending::new("a", 1.0, &[], &[]);
        let b = Pending::new("b", 2.0, &[], &[]);
        let left = still_pending(vec![a, b.clone()], &[sent("a")]);
        assert_eq!(left, vec![b]);
    }

    #[test]
    fn today_reads_as_a_time_and_the_last_hour_as_minutes() {
        let now = i18n::now();
        let ms = |ago: f64| ((now - ago) * 1000.0) as i64;
        assert_eq!(stamp(ms(5.0), now), "Now");
        assert_eq!(stamp(ms(5.0 * 60.0 + 1.0), now), "5 min");
        // Further back is a date, not minutes
        assert!(!stamp(ms(40.0 * 86400.0), now).contains("min"));
    }
}
