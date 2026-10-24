//! Clipboard sync as pure rules (spec-plugins.md 6). The computer's clipboard is one thing, kept here as text
//! and the time it last changed; what each phone last sent or was sent is kept for each. The echo ends because
//! a text equal to the other side's is never sent: nothing here knows about sockets or the shell.

use std::collections::{HashMap, VecDeque};

use crate::limits;

#[derive(Debug, Default)]
pub struct Clipboard {
    text: String,
    /// Milliseconds since the epoch of the last change, 0 when it has not changed since the program started
    stamp: i64,
    remote: HashMap<String, String>,
    recent: VecDeque<i64>,
    /// When a phone's text was last put on the computer's clipboard
    applied: VecDeque<i64>,
}

impl Clipboard {
    pub fn stamp(&self) -> i64 {
        self.stamp
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    /// The computer's clipboard changed to `text` (the module says so). Returns the devices among `targets`
    /// that should be sent it. Too large, empty and too fast changes are not sent.
    pub fn local_changed(&mut self, text: &str, now_ms: i64, targets: &[String]) -> Vec<String> {
        self.text = text.to_string();
        self.stamp = now_ms;
        if text.is_empty() || text.len() > limits::CLIPBOARD_TEXT {
            return Vec::new();
        }
        while self.recent.front().is_some_and(|t| now_ms - t >= 1000) {
            self.recent.pop_front();
        }
        if self.recent.len() >= limits::CLIPBOARD_PER_SECOND {
            return Vec::new();
        }
        self.recent.push_back(now_ms);
        let mut send = Vec::new();
        for id in targets {
            if self.remote.get(id).map(String::as_str) != Some(text) {
                self.remote.insert(id.clone(), text.to_string());
                send.push(id.clone());
            }
        }
        send
    }

    /// A `kdeconnect.clipboard` from a phone. The text to put on the computer's clipboard, when receiving is on
    /// and it is news.
    pub fn remote_changed(&mut self, device: &str, text: &str, receive: bool, now_ms: i64) -> Option<String> {
        if text.len() > limits::CLIPBOARD_TEXT {
            return None;
        }
        self.remote.insert(device.to_string(), text.to_string());
        self.apply(text, receive, now_ms)
    }

    /// A `kdeconnect.clipboard.connect`: only if it is newer than the computer's own
    pub fn remote_connected(&mut self, device: &str, text: &str, stamp: i64, receive: bool, now_ms: i64) -> Option<String> {
        if stamp <= self.stamp || stamp <= 0 {
            return None;
        }
        self.remote_changed(device, text, receive, now_ms)
    }

    fn apply(&mut self, text: &str, receive: bool, now_ms: i64) -> Option<String> {
        if !receive || text.is_empty() || text == self.text {
            return None;
        }
        // A phone that sends them as fast as it can does not get to set the clipboard as fast as it can
        while self.applied.front().is_some_and(|t| now_ms - t >= 1000) {
            self.applied.pop_front();
        }
        if self.applied.len() >= limits::CLIPBOARD_PER_SECOND {
            return None;
        }
        self.applied.push_back(now_ms);
        self.text = text.to_string();
        self.stamp = now_ms;
        Some(text.to_string())
    }

    pub fn forget(&mut self, device: &str) {
        self.remote.remove(device);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn a_local_change_goes_to_the_phones_that_do_not_have_it() {
        let mut c = Clipboard::default();
        assert_eq!(c.local_changed("one", 1000, &ids(&["a", "b"])), ids(&["a", "b"]));
        assert_eq!(c.local_changed("one", 1001, &ids(&["a", "b"])), Vec::<String>::new(), "equal to what they hold");
        assert_eq!(c.local_changed("two", 1002, &ids(&["a"])), ids(&["a"]));
        assert_eq!(c.local_changed("two", 1003, &ids(&["a", "b"])), ids(&["b"]));
    }

    #[test]
    fn nothing_empty_or_huge_is_sent() {
        let mut c = Clipboard::default();
        assert!(c.local_changed("", 1, &ids(&["a"])).is_empty());
        assert!(c.local_changed(&"x".repeat(limits::CLIPBOARD_TEXT + 1), 2, &ids(&["a"])).is_empty());
        assert_eq!(c.stamp(), 2, "the change is still a change");
    }

    #[test]
    fn a_phone_clipboard_is_applied_once_and_not_echoed() {
        let mut c = Clipboard::default();
        assert_eq!(c.remote_changed("a", "from phone", true, 5000), Some("from phone".to_string()));
        // The module sets the clipboard and says so: the text is the phone's, so it goes nowhere
        assert!(c.local_changed("from phone", 5001, &ids(&["a"])).is_empty());
        // But another phone is offered it
        let mut c = Clipboard::default();
        c.remote_changed("a", "x", true, 1);
        assert_eq!(c.local_changed("x", 2, &ids(&["a", "b"])), ids(&["b"]));
    }

    #[test]
    fn receiving_off_keeps_the_text_but_applies_nothing() {
        let mut c = Clipboard::default();
        assert_eq!(c.remote_changed("a", "secret", false, 1), None);
        assert_eq!(c.text(), "");
        assert!(c.local_changed("secret", 2, &ids(&["a"])).is_empty(), "the phone has it already");
    }

    #[test]
    fn empty_and_equal_phone_texts_are_ignored() {
        let mut c = Clipboard::default();
        assert_eq!(c.remote_changed("a", "", true, 1), None);
        c.local_changed("same", 2, &[]);
        assert_eq!(c.remote_changed("a", "same", true, 3), None);
    }

    #[test]
    fn a_phone_cannot_set_the_clipboard_faster_than_five_times_a_second() {
        let mut c = Clipboard::default();
        let applied = (0..50).filter(|i| c.remote_changed("a", &format!("text {i}"), true, 1000 + i).is_some()).count();
        assert_eq!(applied, limits::CLIPBOARD_PER_SECOND);
        assert!(c.remote_changed("a", "later", true, 2500).is_some());
    }

    #[test]
    fn the_connect_packet_needs_a_newer_stamp() {
        let mut c = Clipboard::default();
        assert_eq!(c.remote_connected("a", "x", 0, true, 10), None, "a stamp of 0 is never applied");
        c.local_changed("mine", 5000, &[]);
        assert_eq!(c.remote_connected("a", "older", 4000, true, 6000), None);
        assert_eq!(c.remote_connected("a", "equal", 5000, true, 6000), None);
        assert_eq!(c.remote_connected("a", "newer", 5001, true, 6000), Some("newer".to_string()));
    }

    #[test]
    fn at_most_five_changes_a_second() {
        let mut c = Clipboard::default();
        let sent = (0..10).filter(|i| !c.local_changed(&format!("t{i}"), 1000 + i, &ids(&["a"])).is_empty()).count();
        assert_eq!(sent, limits::CLIPBOARD_PER_SECOND);
        assert!(!c.local_changed("later", 2500, &ids(&["a"])).is_empty());
    }
}
