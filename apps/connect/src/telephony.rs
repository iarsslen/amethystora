//! Calls: what the phone says is ringing or going on (spec-plugins.md 9). Parsing only; the notification and
//! the mute button are the service's.

use serde_json::{Map, Value};

use crate::limits;
use crate::packet;
use crate::text;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Ringing,
    Talking,
    Missed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Event {
    pub kind: Kind,
    /// The event has stopped
    pub cancel: bool,
    pub name: String,
    pub number: String,
    /// A JPEG as base64 text, if it is not too long; decoded by the service in a bounded way
    pub photo: Option<String>,
}

/// The event of a `kdeconnect.telephony` body, or `None` for one that is not handled (`sms`, unknown ones)
pub fn parse(body: &Map<String, Value>) -> Option<Event> {
    let kind = match packet::str_of(body, "event")? {
        "ringing" => Kind::Ringing,
        "talking" => Kind::Talking,
        "missedCall" => Kind::Missed,
        _ => return None,
    };
    let shown = |key: &str| packet::str_of(body, key).map(|s| text::shorten(&text::clean_line(s), limits::NAME_SHOWN)).unwrap_or_default();
    Some(Event {
        kind,
        cancel: packet::bool_of(body, "isCancel").unwrap_or(false),
        name: shown("contactName"),
        number: shown("phoneNumber"),
        photo: packet::str_of(body, "phoneThumbnail").filter(|p| !p.is_empty() && p.len() <= limits::PHOTO_TEXT).map(str::to_string),
    })
}

impl Event {
    /// Who is calling, for a person: the name, else the number, else a word of ours
    pub fn label(&self) -> String {
        if !self.name.trim().is_empty() {
            self.name.clone()
        } else if !self.number.trim().is_empty() {
            self.number.clone()
        } else {
            text::tr("Unknown caller")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn body(v: Value) -> Map<String, Value> {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn the_spec_events() {
        let ringing = parse(&body(json!({ "event": "ringing", "contactName": "Alex Example", "phoneNumber": "+15550100" }))).unwrap();
        assert_eq!((ringing.kind, ringing.cancel), (Kind::Ringing, false));
        assert_eq!(ringing.label(), "Alex Example");
        let ended = parse(&body(json!({ "event": "talking", "contactName": "Alex Example", "phoneNumber": "+15550100", "isCancel": true }))).unwrap();
        assert_eq!((ended.kind, ended.cancel), (Kind::Talking, true));
        let missed = parse(&body(json!({ "event": "missedCall", "phoneNumber": "+15550100" }))).unwrap();
        assert_eq!(missed.kind, Kind::Missed);
        assert_eq!(missed.label(), "+15550100");
    }

    #[test]
    fn what_is_not_handled() {
        assert_eq!(parse(&body(json!({ "event": "sms", "messageBody": "hi" }))), None);
        assert_eq!(parse(&body(json!({ "event": "other" }))), None);
        assert_eq!(parse(&body(json!({}))), None);
        assert_eq!(parse(&body(json!({ "event": 5 }))), None);
    }

    #[test]
    fn a_hidden_number_has_a_word_and_text_is_clean() {
        let hidden = parse(&body(json!({ "event": "ringing" }))).unwrap();
        assert_eq!(hidden.label(), text::tr("Unknown caller"));
        let odd = parse(&body(json!({ "event": "ringing", "contactName": "A\u{202E}B\nC", "isCancel": "yes" }))).unwrap();
        assert_eq!(odd.name, "AB C");
        assert!(!odd.cancel, "a string is not a boolean");
        let long = parse(&body(json!({ "event": "ringing", "contactName": "x".repeat(500) }))).unwrap();
        assert_eq!(long.name.chars().count(), limits::NAME_SHOWN);
        let big_photo = parse(&body(json!({ "event": "ringing", "phoneThumbnail": "A".repeat(limits::PHOTO_TEXT + 1) }))).unwrap();
        assert_eq!(big_photo.photo, None);
    }
}
