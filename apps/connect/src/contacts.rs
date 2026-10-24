//! Contacts, only as far as texts and calls need them: a name for a number (spec-plugins.md 7). The phone's
//! address book is asked for the ids and times of its contacts, then for the cards that changed; each card is
//! somebody else's text, parsed with limits, and only names and numbers are kept (no photos). The book is kept
//! in the account's state folder (0600) and deleted when the phone is unpaired.

use std::collections::BTreeMap;
use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::limits;
use crate::packet;
use crate::store;
use crate::text;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Contact {
    pub name: String,
    pub numbers: Vec<String>,
    pub timestamp: i64,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Book {
    contacts: BTreeMap<String, Contact>,
}

// --- vCard 2.1 --------------------------------------------------------------------------------------------

fn quoted_printable(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut at = 0;
    while at < bytes.len() {
        // `get` and not an index: the two bytes after `=` may be the middle of a character
        if bytes[at] == b'=' {
            if let Some(hex) = value.get(at + 1..at + 3).and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(hex);
                at += 3;
                continue;
            }
        }
        out.push(bytes[at]);
        at += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// The unfolded lines of a card: a line that starts with a space or tab continues the one before, and a
/// quoted-printable line that ends in `=` continues on the next
fn lines(card: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut soft = false;
    for raw in card.split('\n') {
        let raw = raw.strip_suffix('\r').unwrap_or(raw);
        if let Some(last) = out.last_mut() {
            if soft {
                last.push_str(raw);
                soft = last.ends_with('=');
                if soft {
                    last.pop();
                }
                continue;
            }
            if raw.starts_with(' ') || raw.starts_with('\t') {
                last.push_str(raw.trim_start_matches([' ', '\t']));
                continue;
            }
        }
        let mut line = raw.to_string();
        let quoted = line.to_ascii_uppercase().contains("QUOTED-PRINTABLE");
        soft = quoted && line.ends_with('=');
        if soft {
            line.pop();
        }
        out.push(line);
    }
    out
}

/// A card as a contact (name, numbers, time); `None` if it holds neither a name nor a number. Photos and every
/// other property are ignored.
pub fn parse_vcard(card: &str) -> Option<Contact> {
    if card.len() > limits::CONTACT_CARD {
        return None;
    }
    let mut name = None;
    let mut numbers: Vec<String> = Vec::new();
    let mut timestamp = 0;
    for line in lines(card).iter().take(limits::CONTACT_PROPERTIES * 4).filter(|l| !l.is_empty()).take(limits::CONTACT_PROPERTIES) {
        let Some((head, value)) = line.split_once(':') else { continue };
        let mut parts = head.split(';');
        let property = parts.next().unwrap_or("").to_ascii_uppercase();
        let params = parts.map(str::to_ascii_uppercase).collect::<Vec<_>>();
        let value = if params.iter().any(|p| p.contains("QUOTED-PRINTABLE")) { quoted_printable(value) } else { value.to_string() };
        match property.as_str() {
            "FN" if name.is_none() => name = Some(text::shorten(text::clean_line(&value).trim(), limits::NAME_SHOWN)),
            "TEL" if numbers.len() < limits::CONTACT_NUMBERS => {
                let number = text::shorten(text::clean_line(&value).trim(), 64);
                if !number.is_empty() {
                    numbers.push(number);
                }
            }
            "X-KDECONNECT-TIMESTAMP" => timestamp = value.trim().parse().unwrap_or(0),
            _ => {}
        }
    }
    let name = name.filter(|n| !n.is_empty());
    if name.is_none() && numbers.is_empty() {
        return None;
    }
    Some(Contact { name: name.unwrap_or_else(|| text::tr("Unknown")), numbers, timestamp })
}

// --- Numbers ----------------------------------------------------------------------------------------------

/// A number without spaces, brackets, plus signs and hyphens, and without leading zeros; the text as it was
/// when that leaves nothing
fn normalise(number: &str) -> String {
    let stripped: String = number.chars().filter(|c| !matches!(c, ' ' | '(' | ')' | '+' | '-')).collect();
    let trimmed = stripped.trim_start_matches('0');
    if trimmed.is_empty() { number.to_string() } else { trimmed.to_string() }
}

/// Whether two numbers are the same. Loose on purpose, so that a number typed without its country code finds
/// its contact: one is the end of the other, as long as that end is at least four characters. An address with
/// a letter or an `@` is compared whole.
pub fn same_number(a: &str, b: &str) -> bool {
    if a.chars().any(|c| c.is_alphabetic() || c == '@') || b.chars().any(|c| c.is_alphabetic() || c == '@') {
        return a.eq_ignore_ascii_case(b);
    }
    let (a, b) = (normalise(a), normalise(b));
    if a == b {
        return true;
    }
    let (short, long) = if a.len() <= b.len() { (&a, &b) } else { (&b, &a) };
    short.len() >= 4 && long.ends_with(short.as_str())
}

// --- The book ---------------------------------------------------------------------------------------------

impl Book {
    pub fn len(&self) -> usize {
        self.contacts.len()
    }

    pub fn is_empty(&self) -> bool {
        self.contacts.is_empty()
    }

    /// The phone's list of ids and times. Returns the ids to ask the cards of. An empty list changes nothing
    /// (a refused permission looks like that); contacts the phone no longer lists are dropped.
    pub fn on_timestamps(&mut self, body: &Map<String, Value>) -> Vec<String> {
        let Some(uids) = packet::strings_of(body, "uids").filter(|u| !u.is_empty()) else { return Vec::new() };
        // A contact id that is "uids" collides with the list's own member
        let uids: Vec<String> = uids.into_iter().filter(|u| u != "uids").take(limits::CONTACTS_KEPT).collect();
        self.contacts.retain(|id, _| uids.contains(id));
        uids.into_iter().filter(|id| packet::int_of(body, id).is_some_and(|t| self.contacts.get(id).map(|c| c.timestamp) != Some(t)) || !self.contacts.contains_key(id)).collect()
    }

    /// The phone's cards. A card that does not parse leaves the contact as it was.
    pub fn on_vcards(&mut self, body: &Map<String, Value>) {
        let Some(uids) = packet::strings_of(body, "uids") else { return };
        for uid in uids.into_iter().filter(|u| u != "uids") {
            let Some(card) = packet::str_of(body, &uid) else { continue };
            if let Some(contact) = parse_vcard(card) {
                if self.contacts.contains_key(&uid) || self.contacts.len() < limits::CONTACTS_KEPT {
                    self.contacts.insert(uid, contact);
                }
            }
        }
    }

    /// The name of the contact that has this number
    pub fn name_of(&self, number: &str) -> Option<&str> {
        self.contacts.values().find(|c| c.numbers.iter().any(|n| same_number(n, number))).map(|c| c.name.as_str())
    }

    pub fn load(path: &Path) -> Book {
        std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        let text = serde_json::to_string(self).map_err(std::io::Error::other)?;
        store::write_private(path, text.as_bytes())
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
    fn the_spec_card() {
        let card = "BEGIN:VCARD\nVERSION:2.1\nFN:Alex Example\nTEL;CELL:+1 555 0100\nTEL;WORK:555-0101\nX-KDECONNECT-ID-DEV-0a1b2c3d:205\nX-KDECONNECT-TIMESTAMP:1761000000000\nEND:VCARD";
        let c = parse_vcard(card).unwrap();
        assert_eq!(c.name, "Alex Example");
        assert_eq!(c.numbers, vec!["+1 555 0100".to_string(), "555-0101".to_string()]);
        assert_eq!(c.timestamp, 1761000000000);
        // Carriage return and line feed parse too
        assert_eq!(parse_vcard(&card.replace('\n', "\r\n")).unwrap(), c);
    }

    #[test]
    fn folded_and_quoted_printable_lines() {
        let card = "BEGIN:VCARD\r\nVERSION:2.1\r\nFN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=C3=89lodie =\r\n=C3=89mile\r\nTEL;TYPE=cell:+33\r\n 612345678\r\nEND:VCARD";
        let c = parse_vcard(card).unwrap();
        assert_eq!(c.name, "\u{c9}lodie \u{c9}mile");
        assert_eq!(c.numbers, vec!["+33612345678".to_string()]);
    }

    #[test]
    fn photos_and_other_properties_are_ignored_and_a_card_with_nothing_is_none() {
        let card = "BEGIN:VCARD\nVERSION:2.1\nFN:Sam\nPHOTO;ENCODING=BASE64;JPEG:/9j/4AAQSkZJRgABAQ\n AAAA\nEND:VCARD";
        let c = parse_vcard(card).unwrap();
        assert_eq!(c.name, "Sam");
        assert!(c.numbers.is_empty());
        assert_eq!(parse_vcard("BEGIN:VCARD\nVERSION:2.1\nEND:VCARD"), None);
        assert_eq!(parse_vcard(&"x".repeat(limits::CONTACT_CARD + 1)), None);
        let many: String = (0..100).map(|i| format!("TEL:{i:08}\n")).collect();
        assert!(parse_vcard(&format!("BEGIN:VCARD\nFN:Many\n{many}END:VCARD")).unwrap().numbers.len() <= limits::CONTACT_NUMBERS);
    }

    #[test]
    fn numbers_match_loosely() {
        assert!(same_number("+1 555 0100", "555-0100"));
        assert!(same_number("(0044) 7700 900123", "07700900123"));
        assert!(same_number("+15550100", "15550100"));
        assert!(!same_number("+15550100", "+15550101"));
        assert!(!same_number("123", "9123"), "too short to be the end of anything");
        assert!(same_number("Bank@Example.org", "bank@example.org"));
        assert!(!same_number("Bank", "12345678"));
        assert!(same_number("000", "000"), "nothing left after the zeros: compared as they were");
    }

    #[test]
    fn the_sync_follows_the_spec() {
        let mut book = Book::default();
        // An empty list wipes nothing
        book.contacts.insert("1".into(), Contact { name: "Old".into(), numbers: vec![], timestamp: 5 });
        assert!(book.on_timestamps(&body(json!({ "uids": [] }))).is_empty());
        assert_eq!(book.len(), 1);
        assert!(book.on_timestamps(&body(json!({}))).is_empty());
        assert_eq!(book.len(), 1);

        // 101 is new, 205 is new, 1 is gone
        let ask = book.on_timestamps(&body(json!({ "uids": ["101", "205"], "101": 1760000000000i64, "205": 1761000000000i64 })));
        assert_eq!(ask, vec!["101".to_string(), "205".to_string()]);
        assert_eq!(book.len(), 0);

        book.on_vcards(&body(json!({ "uids": ["205"], "205": "BEGIN:VCARD\nVERSION:2.1\nFN:Alex Example\nTEL;CELL:+1 555 0100\nX-KDECONNECT-TIMESTAMP:1761000000000\nEND:VCARD" })));
        assert_eq!(book.name_of("5550100"), Some("Alex Example"));
        assert_eq!(book.name_of("+99 123 4567"), None);

        // Nothing changed for 205: only 101 is asked for again
        let ask = book.on_timestamps(&body(json!({ "uids": ["101", "205"], "101": 1760000000000i64, "205": 1761000000000i64 })));
        assert_eq!(ask, vec!["101".to_string()]);
        // 205 changed
        let ask = book.on_timestamps(&body(json!({ "uids": ["205"], "205": 1762000000000i64 })));
        assert_eq!(ask, vec!["205".to_string()]);
        assert_eq!(book.len(), 1, "101 was never fetched and is not listed now");
    }

    #[test]
    fn a_bad_card_keeps_the_old_contact() {
        let mut book = Book::default();
        book.on_vcards(&body(json!({ "uids": ["7"], "7": "BEGIN:VCARD\nFN:Kept\nTEL:5551234\nEND:VCARD" })));
        book.on_vcards(&body(json!({ "uids": ["7"], "7": "garbage" })));
        book.on_vcards(&body(json!({ "uids": ["7", "uids"], "uids": "BEGIN:VCARD\nFN:Collides\nEND:VCARD" })));
        assert_eq!(book.name_of("5551234"), Some("Kept"));
    }

    #[test]
    fn the_book_is_kept_privately() {
        let dir = std::env::temp_dir().join(format!("amethystora-connect-book-{}", std::process::id()));
        store::private_dir(&dir).unwrap();
        let mut book = Book::default();
        book.on_vcards(&body(json!({ "uids": ["7"], "7": "BEGIN:VCARD\nFN:Kept\nTEL:5551234\nEND:VCARD" })));
        let path = dir.join("contacts.json");
        book.save(&path).unwrap();
        assert_eq!(Book::load(&path).name_of("5551234"), Some("Kept"));
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        assert!(Book::load(&dir.join("missing.json")).is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
