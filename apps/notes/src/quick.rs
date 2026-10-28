//! The quick add: what the task box (and the quick note, capture.rs) takes out of what is typed, the dates,
//! times, repeats, priorities, labels and project, leaving the title. The page asks it with its own store
//! (page/tasks.rs); it knows nothing of the window, so that it can be tested on its own.

use regex::Regex;
use serde_json::{json, Map, Value};

use crate::dates;

/// The day, the weekday (Sunday 0) and the time the words are read against
#[derive(Debug, Clone)]
pub struct Now {
    pub today: String,
    pub weekday: i64,
    pub time: String,
}

impl Now {
    pub fn current() -> Now {
        Now { today: dates::today(), weekday: dates::weekday_now(), time: dates::time_now() }
    }
}

/// The words of the quick add taken out of the title, as a ` text ` with every match replaced by a space
struct Taking {
    title: String,
}

impl Taking {
    /// The first match of `pattern` (which starts with \s) followed by white space, given to `use_it`; when
    /// it answers false the match stays, as String.replace did with the match given back
    fn take(&mut self, pattern: &Regex, global: bool, mut use_it: impl FnMut(&regex::Captures) -> bool) {
        let mut at = 0;
        loop {
            let Some(found) = pattern.captures_at(&self.title, at) else { return };
            let whole = found.get(0).expect("a match");
            // (?=\s): what follows the match has to be white space
            if !self.title[whole.end()..].starts_with(char::is_whitespace) {
                // Not here: try again from the next character
                at = whole.start() + self.title[whole.start()..].chars().next().map(char::len_utf8).unwrap_or(1);
                continue;
            }
            let (start, end) = (whole.start(), whole.end());
            if use_it(&found) {
                self.title.replace_range(start..end, " ");
                at = start + 1;
            } else {
                at = end;
            }
            if !global {
                return;
            }
        }
    }
}

/// "Call Sam tomorrow 5pm p1 @phone #Work every week": the words it knows are taken out of the title.
/// They are English whatever the window's language is. `project` finds a project by its name in lower case
/// without spaces; `label` finds or makes the label of a name.
pub fn parse(text: &str, clock: &Now, project: impl Fn(&str) -> Option<String>, mut label: impl FnMut(&str) -> String) -> Map<String, Value> {
    thread_local! {
        static PATTERNS: [Regex; 7] = [
            Regex::new(r"\s[pP]([1-4])").expect("a pattern"),
            Regex::new(r"\s(?:(?:[eE][vV][eE][rR][yY])\s+([0-9]+\s+)?((?:[dD][aA][yY])|(?:[wW][eE][eE][kK])|(?:[mM][oO][nN][tT][hH])|(?:[yY][eE][aA][rR]))[sS]?|((?:[dD][aA][iI][lL][yY])|(?:[wW][eE][eE][kK][lL][yY])|(?:[mM][oO][nN][tT][hH][lL][yY])|(?:[yY][eE][aA][rR][lL][yY])))").expect("a pattern"),
            Regex::new(r"\s#([\w-]+)").expect("a pattern"),
            Regex::new(r"\s@([\w-]+)").expect("a pattern"),
            Regex::new(r"\s((?i-u:today|tod|tonight|tomorrow|tmr|next week)|(?i-u:(?:on\s+)?(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*)|[0-9]{4}-[0-9]{2}-[0-9]{2})").expect("a pattern"),
            Regex::new(r"\s(?:(?i-u:at)\s+)?([0-9]{1,2})(?::([0-9]{2}))?\s*((?i-u:am|pm))").expect("a pattern"),
            Regex::new(r"\s(?:at\s+)?([01]?[0-9]|2[0-3]):([0-5][0-9])").expect("a pattern"),
        ];
    }
    let mut taking = Taking { title: format!(" {text} ") };
    let mut found = Map::new();
    let now = clock.today.clone();
    PATTERNS.with(|p| {
        taking.take(&p[0], false, |m| {
            found.insert("priority".into(), Value::from(m[1].parse::<i64>().unwrap_or(4)));
            true
        });
        taking.take(&p[1], false, |m| {
            let every = m.get(1).and_then(|c| c.as_str().trim().parse::<i64>().ok()).filter(|n| *n != 0).unwrap_or(1);
            let unit = match (m.get(2), m.get(3)) {
                (Some(unit), _) => unit.as_str().to_lowercase(),
                (None, Some(adverb)) => match adverb.as_str().to_lowercase().as_str() {
                    "daily" => "day".into(),
                    "weekly" => "week".into(),
                    "monthly" => "month".into(),
                    _ => "year".into(),
                },
                _ => "day".into(),
            };
            found.insert("repeat".into(), json!({ "every": every, "unit": unit }));
            true
        });
        taking.take(&p[2], false, |m| {
            let key = m[1].to_lowercase();
            match project(&key) {
                Some(project) => {
                    found.insert("project".into(), Value::from(project));
                    found.insert("section".into(), Value::Null);
                    true
                }
                None => false,
            }
        });
        let mut labels: Vec<Value> = Vec::new();
        taking.take(&p[3], true, |m| {
            labels.push(Value::from(label(&m[1])));
            true
        });
        if !labels.is_empty() {
            found.insert("labels".into(), Value::Array(labels));
        }
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
        taking.take(&p[4], false, |m| {
            let lower = m[1].to_lowercase();
            let lower = match lower.strip_prefix("on") {
                Some(rest) if rest.starts_with(char::is_whitespace) => rest.trim_start().to_string(),
                _ => lower,
            };
            let due = if dates::is_iso(&lower) {
                lower.clone()
            } else if ["today", "tod", "tonight"].contains(&lower.as_str()) {
                now.clone()
            } else if ["tomorrow", "tmr"].contains(&lower.as_str()) {
                dates::add_days(&now, 1)
            } else if lower == "next week" {
                dates::add_days(&now, 7 - ((clock.weekday + 6) % 7))
            } else {
                let three: String = lower.chars().take(3).collect();
                let Some(day) = weekdays.iter().position(|name| name.starts_with(&three)) else { return false };
                if lower.len() > 3 && !weekdays[day].starts_with(&lower) {
                    return false;
                }
                let ahead = (day as i64 - clock.weekday + 7) % 7;
                dates::add_days(&now, if ahead == 0 { 7 } else { ahead })
            };
            found.insert("due".into(), Value::from(due));
            true
        });
        taking.take(&p[5], false, |m| {
            let hours = m[1].parse::<i64>().unwrap_or(0);
            let hour = hours % 12 + if m[3].to_lowercase() == "pm" { 12 } else { 0 };
            let minutes = m.get(2).map(|c| c.as_str().to_string()).unwrap_or_else(|| "00".into());
            found.insert("time".into(), Value::from(format!("{hour:02}:{minutes}")));
            true
        });
        taking.take(&p[6], false, |m| {
            let hours = m[1].parse::<i64>().unwrap_or(0);
            found.insert("time".into(), Value::from(format!("{hours:02}:{}", &m[2])));
            true
        });
    });
    if (found.contains_key("time") || found.contains_key("repeat")) && !found.contains_key("due") {
        let late = found.get("time").and_then(Value::as_str).is_some_and(|time| time < clock.time.as_str());
        let due = if late && !found.contains_key("repeat") { dates::add_days(&clock.today, 1) } else { clock.today.clone() };
        found.insert("due".into(), Value::from(due));
    }
    if found.contains_key("time") {
        found.insert("reminder".into(), Value::from(0));
    }
    let title = taking.title.split_whitespace().collect::<Vec<_>>().join(" ");
    found.insert("title".into(), Value::from(if title.is_empty() { text.trim().to_string() } else { title }));
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    // Wednesday 28 October 2026, a quarter past ten in the morning
    fn clock() -> Now {
        Now { today: "2026-10-28".into(), weekday: 3, time: "10:15".into() }
    }

    fn parsed(text: &str) -> Map<String, Value> {
        let mut made = Vec::new();
        let found = parse(text, &clock(), |key| (key == "work").then(|| "p-work".to_string()), |name| {
            made.push(name.to_string());
            format!("l-{}", name.to_lowercase())
        });
        found
    }

    #[test]
    fn takes_every_word_it_knows() {
        let found = parsed("Call Sam tomorrow 5pm p1 @phone #Work every week");
        assert_eq!(found["title"], "Call Sam");
        assert_eq!(found["due"], "2026-10-29");
        assert_eq!(found["time"], "17:00");
        assert_eq!(found["reminder"], 0);
        assert_eq!(found["priority"], 1);
        assert_eq!(found["labels"], json!(["l-phone"]));
        assert_eq!(found["project"], "p-work");
        assert_eq!(found["section"], Value::Null);
        assert_eq!(found["repeat"], json!({ "every": 1, "unit": "week" }));
    }

    #[test]
    fn a_project_it_does_not_know_stays_in_the_title() {
        let found = parsed("Plan #Garden trip");
        assert_eq!(found["title"], "Plan #Garden trip");
        assert!(!found.contains_key("project"));
    }

    #[test]
    fn days_and_times() {
        assert_eq!(parsed("x today")["due"], "2026-10-28");
        assert_eq!(parsed("x next week")["due"], "2026-11-02");
        assert_eq!(parsed("x friday")["due"], "2026-10-30");
        assert_eq!(parsed("x wed")["due"], "2026-11-04");
        assert_eq!(parsed("x 2026-12-24")["due"], "2026-12-24");
        // A time already past today is tomorrow's; one still to come is today's
        assert_eq!(parsed("x 9:00")["due"], "2026-10-29");
        assert_eq!(parsed("x at 18:30")["due"], "2026-10-28");
        assert_eq!(parsed("x at 18:30")["time"], "18:30");
        assert_eq!(parsed("x every 2 days")["repeat"], json!({ "every": 2, "unit": "day" }));
        assert_eq!(parsed("x daily")["due"], "2026-10-28");
    }

    #[test]
    fn nothing_but_words_it_knows_keeps_the_text() {
        assert_eq!(parsed("tomorrow")["title"], "tomorrow");
        assert_eq!(parsed("  ask sam about trains tomorrow ")["title"], "ask sam about trains");
    }
}
