//! The phone's mobile signal, from its connectivity report (spec-phone-files-first.md 2.1). The phone sends one entry
//! per SIM; the bar shows the strongest. Everything in the report is the phone's word: a level is kept only when it is
//! a whole number from 0 to 4, and a network type only when it is a short plain word, so that nothing it says can be
//! drawn as anything but a number of bars and a few letters.

use serde_json::{Map, Value};

/// A phone has a few SIMs at most: a report with more entries is read no further than this
const MOST_ENTRIES: usize = 8;
/// The longest network type kept ("CDMA2000" is the longest the phones document)
const LONGEST_NETWORK: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Signal {
    /// 0 (none) to 4 (full)
    pub strength: i32,
    /// "LTE", "5G", ... or "Unknown"
    pub network: String,
}

/// Whether the body is a report at all: one without an object `signalStrengths` changes nothing
pub fn is_report(body: &Map<String, Value>) -> bool {
    body.get("signalStrengths").is_some_and(Value::is_object)
}

/// The strongest valid entry of a report, or `None` when it has none (no SIM left, or nothing that could be read)
pub fn parse(body: &Map<String, Value>) -> Option<Signal> {
    let entries = body.get("signalStrengths")?.as_object()?;
    // The phone's keys are subscription ids written in decimal: in their order as numbers, the others after them
    let mut keys: Vec<&String> = entries.keys().collect();
    keys.sort_by(|a, b| match (a.parse::<i64>(), b.parse::<i64>()) {
        (Ok(x), Ok(y)) => x.cmp(&y),
        (Ok(_), Err(_)) => std::cmp::Ordering::Less,
        (Err(_), Ok(_)) => std::cmp::Ordering::Greater,
        (Err(_), Err(_)) => a.cmp(b),
    });
    let mut best: Option<Signal> = None;
    for key in keys.into_iter().take(MOST_ENTRIES) {
        let Some(entry) = entry(&entries[key]) else { continue };
        // A tie keeps the entry that came first
        if best.as_ref().is_none_or(|b| entry.strength > b.strength) {
            best = Some(entry);
        }
    }
    best
}

fn entry(value: &Value) -> Option<Signal> {
    let strength = value.get("signalStrength")?.as_f64()?;
    if strength.fract() != 0.0 || !(0.0..=4.0).contains(&strength) {
        return None;
    }
    let network = value.get("networkType")?.as_str()?;
    Some(Signal { strength: strength as i32, network: network_word(network) })
}

/// The network type as the phone named it, when it is 1 to 16 letters, digits, spaces, dots or hyphens
fn network_word(said: &str) -> String {
    let plain = |c: char| c.is_ascii_alphanumeric() || matches!(c, ' ' | '.' | '-');
    let count = said.chars().count();
    if (1..=LONGEST_NETWORK).contains(&count) && said.chars().all(plain) && !said.trim().is_empty() { said.to_string() } else { "Unknown".to_string() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn read(body: Value) -> Option<(i32, String)> {
        let body = body.as_object().unwrap();
        assert!(is_report(body));
        parse(body).map(|s| (s.strength, s.network))
    }

    #[test]
    fn one_sim() {
        // V-CR-1
        assert_eq!(read(json!({"signalStrengths": {"6": {"networkType": "LTE", "signalStrength": 3}}})), Some((3, "LTE".into())));
    }

    #[test]
    fn two_sims_give_the_strongest() {
        // V-CR-2
        let body = json!({"signalStrengths": {"1": {"networkType": "5G", "signalStrength": 2}, "2": {"networkType": "LTE", "signalStrength": 4}}});
        assert_eq!(read(body), Some((4, "LTE".into())));
        // A tie keeps the first by number: "2" comes before "10", which a string order would not say
        let body = json!({"signalStrengths": {"10": {"networkType": "5G", "signalStrength": 3}, "2": {"networkType": "LTE", "signalStrength": 3}}});
        assert_eq!(read(body), Some((3, "LTE".into())));
        // Numbers first, then the other keys as strings
        let body = json!({"signalStrengths": {"b": {"networkType": "GSM", "signalStrength": 1}, "a": {"networkType": "EDGE", "signalStrength": 1}, "9": {"networkType": "UMTS", "signalStrength": 1}}});
        assert_eq!(read(body), Some((1, "UMTS".into())));
    }

    #[test]
    fn no_sim() {
        // V-CR-3
        assert_eq!(read(json!({"signalStrengths": {}})), None);
    }

    #[test]
    fn a_level_out_of_range_or_of_the_wrong_type_is_ignored() {
        // V-CR-4, V-CR-5
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "LTE", "signalStrength": 7}}})), None);
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "LTE", "signalStrength": "3"}}})), None);
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "LTE", "signalStrength": -1}}})), None);
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "LTE", "signalStrength": 2.5}}})), None);
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "LTE"}}})), None);
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": 4, "signalStrength": 2}}})), None);
        assert_eq!(read(json!({"signalStrengths": {"1": "LTE"}})), None);
        // One bad entry leaves the good one
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "LTE", "signalStrength": 9}, "2": {"networkType": "GSM", "signalStrength": 1}}})), Some((1, "GSM".into())));
    }

    #[test]
    fn a_network_type_that_is_not_a_plain_word_is_unknown() {
        // V-CR-6
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "\u{202e}ETL\u{0007}", "signalStrength": 2}}})), Some((2, "Unknown".into())));
        for bad in ["", " ", "<b>LTE</b>", "LTE\n", "abcdefghijklmnopq", "LTE&amp;"] {
            assert_eq!(network_word(bad), "Unknown", "{bad:?}");
        }
        for good in ["LTE", "5G", "CDMA2000", "iDEN", "4G", "HSPA", "NR 5G-SA", "abcdefghijklmnop"] {
            assert_eq!(network_word(good), good);
        }
    }

    #[test]
    fn a_whole_number_written_with_a_point_counts() {
        // V-CR-7
        assert_eq!(read(json!({"signalStrengths": {"1": {"networkType": "4G", "signalStrength": 2.0}}})), Some((2, "4G".into())));
    }

    #[test]
    fn a_body_without_the_map_is_no_report() {
        // V-CR-8
        assert!(!is_report(&Map::new()));
        assert!(!is_report(json!({"signalStrengths": [1, 2]}).as_object().unwrap()));
        assert!(!is_report(json!({"signalStrengths": "LTE"}).as_object().unwrap()));
        assert!(!is_report(json!({"signalStrengths": null}).as_object().unwrap()));
    }

    #[test]
    fn only_the_first_eight_entries_are_read() {
        // V-CR-9: entries 1..=20, the strongest at 9 and beyond, are not reached
        let mut map = serde_json::Map::new();
        for i in 1..=20 {
            let level = if i <= 8 { 1 } else { 4 };
            map.insert(i.to_string(), json!({"networkType": format!("N{i}"), "signalStrength": level}));
        }
        assert_eq!(read(json!({ "signalStrengths": map })), Some((1, "N1".into())));
    }
}
