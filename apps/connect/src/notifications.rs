//! A phone's notifications (spec-plugins.md 4): what a `kdeconnect.notification` packet says, what the
//! desktop notification for it holds, and the table that finds a phone's notification again when the phone
//! updates it, cancels it, or the person answers it. The ids are the phone's own, kept for each device, so
//! that a cancel always finds what it cancels.

use std::collections::HashMap;

use serde_json::{Map, Value};
use sha2::{Digest, Sha256};

use crate::limits;
use crate::packet::{self, Packet, Payload};
use crate::text;

// Whether the phone's own marks decide what is shown: a notification it marks silent is one it had before we
// connected, and a notification it will not let a person clear is an ongoing one (a player, a download). The image's
// decision is to show neither (`Table::show_silent` and `show_ongoing` are false); the program's options
// --show-silent and --show-ongoing change it for a lab, or for a phone that marks too much.

/// Android's own messaging apps: a click on their notification opens the texts
const SMS_APPS: &[&str] = &["com.google.android.apps.messaging", "com.android.mms", "com.android.messaging", "com.samsung.android.messaging", "com.oneplus.mms", "com.miui.mms"];
/// Chat apps, only to arrange their words as a person's name and what they said
const CHAT_APPS: &[&str] = &[
    "org.thoughtcrime.securesms",
    "org.telegram.messenger",
    "org.telegram.messenger.web",
    "com.whatsapp",
    "com.whatsapp.w4b",
    "com.facebook.orca",
    "com.discord",
    "com.Slack",
    "ch.threema.app",
    "im.vector.app",
    "com.viber.voip",
    "jp.naver.line.android",
    "org.signal.messenger",
    "com.google.android.apps.dynamite",
    "com.microsoft.teams",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Plain,
    MissedCall,
    /// A chat, arranged as a name and what they said
    Chat,
    /// A text message: the same, and a click opens the texts
    Sms,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Incoming {
    pub id: String,
    pub app: String,
    pub title: String,
    pub text: String,
    pub ticker: String,
    pub clearable: bool,
    pub silent: bool,
    pub actions: Vec<String>,
    pub reply_id: Option<String>,
    pub icon_hash: Option<String>,
    pub payload: Option<Payload>,
    pub kind: Kind,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Parsed {
    /// The phone closed it
    Cancel(String),
    Show(Box<Incoming>),
    /// No id, or not a notification
    Ignore,
}

/// The package part of a phone notification id (`0|org.example.mail|1042|null|10123`)
fn package_of(id: &str) -> Option<&str> {
    id.split('|').nth(1).filter(|p| !p.is_empty())
}

fn kind_of(id: &str) -> Kind {
    let package = package_of(id);
    let lower = id.to_ascii_lowercase();
    if id.contains("MissedCall") {
        Kind::MissedCall
    } else if lower.contains("sms") || package.is_some_and(|p| SMS_APPS.contains(&p)) {
        Kind::Sms
    } else if package.is_some_and(|p| CHAT_APPS.contains(&p)) {
        Kind::Chat
    } else {
        Kind::Plain
    }
}

/// A hash as the phone names an icon with: 32 hexadecimal characters, and nothing else
pub fn valid_hash(hash: &str) -> bool {
    hash.len() == 32 && hash.bytes().all(|b| b.is_ascii_hexdigit())
}

pub fn parse(p: &Packet) -> Parsed {
    let Some(id) = p.str("id").filter(|id| !id.is_empty()) else { return Parsed::Ignore };
    if p.bool("isCancel") == Some(true) {
        return Parsed::Cancel(id.to_string());
    }
    let shown = |key: &str, max: usize| text::shorten(&text::clean(p.str(key).unwrap_or("")), max);
    let mut actions: Vec<String> = Vec::new();
    for action in packet::strings_of(&p.body, "actions").unwrap_or_default() {
        let action = text::clean_line(&action);
        if !action.trim().is_empty() && !actions.contains(&action) && action.len() <= 128 {
            actions.push(action);
        }
    }
    Parsed::Show(Box::new(Incoming {
        id: id.to_string(),
        app: text::clean_line(p.str("appName").unwrap_or("")),
        title: shown("title", limits::NOTIFICATION_TITLE),
        text: shown("text", limits::NOTIFICATION_BODY),
        ticker: shown("ticker", limits::NOTIFICATION_BODY),
        // Not clearable only when the phone says so
        clearable: p.bool("isClearable").unwrap_or(true),
        silent: p.bool("silent").unwrap_or(false),
        actions,
        reply_id: p.str("requestReplyId").filter(|r| !r.is_empty() && r.len() <= 128 && !r.chars().any(char::is_control)).map(str::to_string),
        icon_hash: p.str("payloadHash").filter(|h| valid_hash(h)).map(str::to_ascii_lowercase),
        payload: p.payload().ok().flatten(),
        kind: kind_of(id),
    }))
}

/// A notification for the person: a heading and a body, as plain text
pub struct Words {
    pub heading: String,
    pub body: String,
}

pub fn words(n: &Incoming, device_name: &str) -> Words {
    let app = if n.app.trim().is_empty() { device_name.to_string() } else { n.app.clone() };
    match n.kind {
        // A name and what they said (or the number and "missed call")
        Kind::MissedCall | Kind::Chat | Kind::Sms if !n.title.trim().is_empty() => Words { heading: n.title.clone(), body: n.text.clone() },
        _ => {
            let body = match (n.title.trim().is_empty(), n.text.trim().is_empty()) {
                (false, false) if n.title == app => n.text.clone(),
                (false, false) => format!("{}: {}", n.title, n.text),
                (false, true) => n.title.clone(),
                (true, false) => n.text.clone(),
                (true, true) => n.ticker.clone(),
            };
            Words { heading: app, body }
        }
    }
}

/// An id for a notification that fits a command line and a bus message: the phone's own, or a hash of it
pub fn local_id(phone_id: &str) -> String {
    // One that starts with a hyphen would be an option on the app's command line
    if phone_id.len() <= 200 && !phone_id.starts_with('-') && !phone_id.chars().any(char::is_control) {
        phone_id.to_string()
    } else {
        let digest = Sha256::digest(phone_id.as_bytes());
        format!("h-{}", digest.iter().take(16).map(|b| format!("{b:02x}")).collect::<String>())
    }
}

/// What the table keeps of a notification that is on screen
#[derive(Debug, Clone)]
pub struct Entry {
    pub phone_id: String,
    pub id: String,
    pub app: String,
    pub title: String,
    pub text: String,
    pub actions: Vec<String>,
    pub reply_id: Option<String>,
    pub clearable: bool,
    pub kind: Kind,
    /// The phone's name for its icon (32 hexadecimal characters), which the program keeps as a PNG of its own
    pub icon_hash: Option<String>,
    signature: String,
    seq: u64,
}

#[derive(Debug, Default)]
pub struct Table {
    entries: HashMap<String, Entry>,
    next: u64,
    pub show_silent: bool,
    pub show_ongoing: bool,
}

pub enum Outcome {
    /// New, or changed: raise or replace the notification, with these words
    Show { id: String },
    /// Already on screen and unchanged: nothing to do
    Same,
    /// Not to be shown
    Skip,
}

/// What a person sees of a notification, for telling whether it changed
fn signature(n: &Incoming) -> String {
    format!("{}\u{1}{}\u{1}{}\u{1}{}\u{1}{}", n.app, n.title, n.text, n.actions.join("\u{2}"), n.icon_hash.as_deref().unwrap_or(""))
}

impl Table {
    pub fn with_policy(show_silent: bool, show_ongoing: bool) -> Table {
        Table { show_silent, show_ongoing, ..Table::default() }
    }

    /// The phone sent a notification
    pub fn incoming(&mut self, n: &Incoming) -> Outcome {
        if (n.silent && !self.show_silent) || (!n.clearable && !self.show_ongoing) {
            return Outcome::Skip;
        }
        let sig = signature(n);
        // The newest reply handle is the one that works, whether or not anything else changed
        if let Some(entry) = self.entries.get_mut(&n.id) {
            entry.reply_id = n.reply_id.clone();
            if entry.signature == sig {
                return Outcome::Same;
            }
        }
        self.next += 1;
        let id = local_id(&n.id);
        self.entries.insert(
            n.id.clone(),
            Entry {
                phone_id: n.id.clone(),
                id: id.clone(),
                app: n.app.clone(),
                title: n.title.clone(),
                text: n.text.clone(),
                actions: n.actions.clone(),
                reply_id: n.reply_id.clone(),
                clearable: n.clearable,
                kind: n.kind,
                icon_hash: n.icon_hash.clone(),
                signature: sig,
                seq: self.next,
            },
        );
        // A table that grows without end is a phone's way to fill memory: the oldest go
        if self.entries.len() > 300 {
            if let Some(oldest) = self.entries.values().min_by_key(|e| e.seq).map(|e| e.phone_id.clone()) {
                self.entries.remove(&oldest);
            }
        }
        Outcome::Show { id }
    }

    /// The phone closed the notification: its entry, if we had one
    pub fn cancelled(&mut self, phone_id: &str) -> Option<Entry> {
        self.entries.remove(phone_id)
    }

    pub fn by_id(&self, id: &str) -> Option<&Entry> {
        self.entries.values().find(|e| e.id == id)
    }

    pub fn by_phone_id(&self, phone_id: &str) -> Option<&Entry> {
        self.entries.get(phone_id)
    }

    /// The person dismissed it here: forget it, and say what the phone should be asked, if anything
    pub fn dismissed(&mut self, id: &str) -> Option<Entry> {
        let phone_id = self.by_id(id)?.phone_id.clone();
        self.entries.remove(&phone_id)
    }

    /// The notifications that can be answered, newest first
    pub fn repliable(&self) -> Vec<&Entry> {
        let mut list: Vec<&Entry> = self.entries.values().filter(|e| e.reply_id.is_some()).collect();
        list.sort_by_key(|e| std::cmp::Reverse(e.seq));
        list
    }

    /// Every notification: the phone went away
    pub fn clear(&mut self) -> Vec<Entry> {
        self.entries.drain().map(|(_, e)| e).collect()
    }
}

/// The `kdeconnect.notification.request` body that asks the phone to close one of its notifications
pub fn cancel_request(phone_id: &str) -> Value {
    serde_json::json!({ "cancel": phone_id })
}

/// The phone asking us to close one of ours (an id we gave): which
pub fn cancel_from_phone(body: &Map<String, Value>) -> Option<&str> {
    packet::str_of(body, "cancel")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn packet(v: Value) -> Packet {
        Packet::parse(v.to_string().as_bytes()).unwrap()
    }

    fn incoming(v: Value) -> Incoming {
        match parse(&packet(v)) {
            Parsed::Show(n) => *n,
            other => panic!("{other:?}"),
        }
    }

    fn mail() -> Value {
        json!({ "type": "kdeconnect.notification", "body": { "id": "0|org.example.mail|1042|null|10123", "appName": "Example Mail", "title": "Weekly report", "text": "Your report is ready.", "ticker": "Weekly report: Your report is ready.", "isClearable": true, "silent": false, "time": "1761253199000" } })
    }

    #[test]
    fn the_spec_notifications() {
        let n = incoming(mail());
        let w = words(&n, "Sam phone");
        assert_eq!((w.heading.as_str(), w.body.as_str()), ("Example Mail", "Weekly report: Your report is ready."));
        assert_eq!(n.kind, Kind::Plain);

        let player = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "0|org.example.player|7|null|10123", "appName": "Example Player", "title": "Now playing", "text": "Side A, track 1", "isClearable": false, "actions": ["Pause", "Next", "Pause", "", " "], "payloadHash": "0123456789abcdef0123456789abcdef" }, "payloadSize": 2314, "payloadTransferInfo": { "port": 1739 } }));
        assert_eq!(player.actions, vec!["Pause".to_string(), "Next".to_string()]);
        assert_eq!(player.payload, Some(Payload { size: 2314, port: 1739 }));
        assert_eq!(player.icon_hash.as_deref(), Some("0123456789abcdef0123456789abcdef"));
        assert!(!player.clearable);

        let chat = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "0|org.example.chat|55|null|10123", "appName": "Example Chat", "title": "Sam", "text": "Are you coming tonight?", "isClearable": true, "requestReplyId": "5b1c2f9e-3d44-4a0a-9c53-0a5d0f6a7e11" } }));
        assert_eq!(chat.reply_id.as_deref(), Some("5b1c2f9e-3d44-4a0a-9c53-0a5d0f6a7e11"));
        assert_eq!(parse(&packet(json!({ "type": "kdeconnect.notification", "body": { "id": "0|org.example.chat|55|null|10123", "isCancel": true } }))), Parsed::Cancel("0|org.example.chat|55|null|10123".into()));
    }

    #[test]
    fn arranging_the_words() {
        let mut n = incoming(mail());
        n.title = "Example Mail".into();
        assert_eq!(words(&n, "x").body, "Your report is ready.", "the app's own name is not said twice");
        n.title.clear();
        assert_eq!(words(&n, "x").body, "Your report is ready.");
        n.text.clear();
        assert_eq!(words(&n, "x").body, "Weekly report: Your report is ready.", "the ticker is the last resort");
        n.app.clear();
        assert_eq!(words(&n, "Sam phone").heading, "Sam phone");

        let sms = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "0|com.google.android.apps.messaging|3|null|1", "appName": "Messages", "title": "Alex", "text": "Dinner?" } }));
        assert_eq!(sms.kind, Kind::Sms);
        let w = words(&sms, "x");
        assert_eq!((w.heading.as_str(), w.body.as_str()), ("Alex", "Dinner?"));
        let chat = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "0|org.telegram.messenger|3|null|1", "appName": "Telegram", "title": "Alex", "text": "Dinner?" } }));
        assert_eq!(chat.kind, Kind::Chat);
        let missed = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "0|com.android.server.telecom|MissedCall|+1555|1", "appName": "Phone", "title": "Alex", "text": "Missed call" } }));
        assert_eq!(missed.kind, Kind::MissedCall);
        let by_word = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "0|org.example.smsapp|3|null|1", "appName": "X" } }));
        assert_eq!(by_word.kind, Kind::Sms, "the word sms in the id");
    }

    #[test]
    fn bad_packets() {
        assert_eq!(parse(&packet(json!({ "type": "kdeconnect.notification", "body": {} }))), Parsed::Ignore);
        assert_eq!(parse(&packet(json!({ "type": "kdeconnect.notification", "body": { "id": 5 } }))), Parsed::Ignore);
        assert_eq!(parse(&packet(json!({ "type": "kdeconnect.notification", "body": { "id": "" } }))), Parsed::Ignore);
        // A cancel is a boolean true; the string is nothing of the sort
        assert!(matches!(parse(&packet(json!({ "type": "kdeconnect.notification", "body": { "id": "a", "isCancel": "true" } }))), Parsed::Show(_)));
        let odd = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "a", "requestReplyId": 7, "payloadHash": "not-a-hash", "actions": "Pause", "title": "<b>x</b>\u{202E}" } }));
        assert_eq!((odd.reply_id, odd.icon_hash, odd.actions), (None, None, vec![]));
        assert_eq!(odd.title, "<b>x</b>", "markup is the notification's escaping to do, bidi overrides are gone");
    }

    #[test]
    fn the_hash_shape() {
        assert!(valid_hash("0123456789abcdef0123456789ABCDEF"));
        assert!(!valid_hash("0123456789abcdef0123456789abcde"));
        assert!(!valid_hash("../../../../etc/passwd/../../.."));
        assert!(!valid_hash("0123456789abcdef0123456789abcdeg"));
    }

    #[test]
    fn duplicates_replace_and_do_not_ring_twice() {
        let mut table = Table::default();
        let n = incoming(mail());
        assert!(matches!(table.incoming(&n), Outcome::Show { .. }));
        assert!(matches!(table.incoming(&n), Outcome::Same), "the catch-up burst at connection");
        let mut changed = n.clone();
        changed.text = "Your report is late.".into();
        assert!(matches!(table.incoming(&changed), Outcome::Show { .. }));
        assert_eq!(table.by_phone_id(&n.id).unwrap().text, "Your report is late.");
        // The cancel finds it by the phone's id
        assert!(table.cancelled(&n.id).is_some());
        assert!(table.cancelled(&n.id).is_none());
    }

    #[test]
    fn the_newest_reply_handle_wins_even_when_nothing_else_changed() {
        let mut table = Table::default();
        let mut n = incoming(json!({ "type": "kdeconnect.notification", "body": { "id": "chat1", "title": "Sam", "text": "hi", "requestReplyId": "first" } }));
        table.incoming(&n);
        n.reply_id = Some("second".into());
        assert!(matches!(table.incoming(&n), Outcome::Same));
        assert_eq!(table.by_phone_id("chat1").unwrap().reply_id.as_deref(), Some("second"));
        assert_eq!(table.repliable().len(), 1);
    }

    #[test]
    fn silent_and_ongoing_are_not_shown() {
        let mut table = Table::default();
        let mut n = incoming(mail());
        n.silent = true;
        assert!(matches!(table.incoming(&n), Outcome::Skip));
        n.silent = false;
        n.clearable = false;
        assert!(matches!(table.incoming(&n), Outcome::Skip));
        assert!(table.cancelled(&n.id).is_none());
    }

    #[test]
    fn dismissing_here_forgets_it() {
        let mut table = Table::default();
        let n = incoming(mail());
        let Outcome::Show { id } = table.incoming(&n) else { panic!() };
        let entry = table.dismissed(&id).unwrap();
        assert_eq!(entry.phone_id, n.id);
        assert!(table.dismissed(&id).is_none());
    }

    #[test]
    fn long_ids_are_hashed_and_the_table_is_bounded() {
        let long = format!("0|org.example|{}", "x".repeat(300));
        let id = local_id(&long);
        assert!(id.starts_with("h-") && id.len() < 40);
        assert_eq!(local_id("0|org.example.mail|1042|null|10123"), "0|org.example.mail|1042|null|10123");
        assert!(local_id("a\nb").starts_with("h-"));
        assert!(local_id("--gapplication-service").starts_with("h-"), "never an option for the app");
        assert_eq!(local_id("0|a|-b"), "0|a|-b");
        let mut table = Table::default();
        for i in 0..400 {
            let mut n = incoming(mail());
            n.id = format!("id{i}");
            table.incoming(&n);
        }
        assert!(table.entries.len() <= 300);
        assert!(table.by_phone_id("id399").is_some());
        assert!(table.by_phone_id("id0").is_none());
    }

    #[test]
    fn requests_to_the_phone() {
        assert_eq!(cancel_request("0|a|1"), json!({ "cancel": "0|a|1" }));
        assert_eq!(cancel_from_phone(&packet(json!({ "type": "kdeconnect.notification.request", "body": { "cancel": "x" } })).body), Some("x"));
        assert_eq!(cancel_from_phone(&packet(json!({ "type": "kdeconnect.notification.request", "body": { "request": true } })).body), None);
    }
}
