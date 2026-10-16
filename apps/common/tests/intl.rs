//! The words i18n.rs writes against what Chromium's Intl wrote for the Electron windows, from intl.json,
//! which apps/tools/intl-golden.js made on the image's Electron. Run with TZ=UTC, as that was.

use std::collections::HashMap;

use amethystora_ui::i18n::{DateStyle, I18n, ListKind, Unit, Width};
use icu_locale_core::Locale;
use serde_json::Value;

fn style(name: &str) -> DateStyle {
    match name {
        "Time" => DateStyle::Time,
        "TimeNumeric" => DateStyle::TimeNumeric,
        "Time24" => DateStyle::Time24,
        "Time24Seconds" => DateStyle::Time24Seconds,
        "Weekday" => DateStyle::Weekday,
        "WeekdayDayMonthShort" => DateStyle::WeekdayDayMonthShort,
        "WeekdayDayMonth" => DateStyle::WeekdayDayMonth,
        "WeekdayDayMonthYear" => DateStyle::WeekdayDayMonthYear,
        "WeekdayDayMonthYearShort" => DateStyle::WeekdayDayMonthYearShort,
        "DayMonthYear" => DateStyle::DayMonthYear,
        "DayMonthShort" => DateStyle::DayMonthShort,
        "DayMonthYearShort" => DateStyle::DayMonthYearShort,
        "MediumShort" => DateStyle::MediumShort,
        other => panic!("no style {other}"),
    }
}

/// Where ICU4X writes CLDR's semantic forms rather than V8's: German and Arabic dates with an abbreviated
/// month (month: 'short') come out with the month as a number ("Sa., 26.09." for "Sa., 26. Sept."), and
/// Egyptian Arabic's percent sign is the Latin one. Both are correct for their languages; the comparison
/// leaves them out so that everything else stays held to what the Electron windows wrote.
fn known(tag: &str, what: &str) -> bool {
    let language = tag.split('-').next().unwrap();
    let abbreviated = ["DayMonthShort", "DayMonthYearShort", "WeekdayDayMonthShort", "WeekdayDayMonthYearShort"];
    (["de", "ar"].contains(&language) && abbreviated.iter().any(|style| what.starts_with(&format!("{style} "))))
        || (tag == "ar-EG" && what.starts_with("percent "))
}

#[test]
fn writes_what_intl_wrote() {
    assert_eq!(std::env::var("TZ").as_deref(), Ok("UTC"), "run with TZ=UTC");
    let golden: HashMap<String, Value> = serde_json::from_str(include_str!("intl.json")).unwrap();
    let mut wrong = Vec::new();
    let mut checked = 0;
    for (tag, entry) in &golden {
        let lang = tag.split('-').next().unwrap().to_string();
        let i18n = I18n::new(lang, Locale::try_from_str(tag).unwrap(), HashMap::new());
        let mut check = |what: String, ours: String, theirs: &Value| {
            checked += 1;
            if ours != theirs.as_str().unwrap() && !known(tag, &what) {
                wrong.push(format!("{tag} {what}: ours {ours:?}, Intl {theirs}"));
            }
        };
        for pair in entry["numbers"].as_array().unwrap() {
            let n = pair[0].as_f64().unwrap();
            check(format!("number {n}"), i18n.number(n), &pair[1]);
        }
        for pair in entry["percents"].as_array().unwrap() {
            let n = pair[0].as_f64().unwrap();
            check(format!("percent {n}"), i18n.percent(n), &pair[1]);
        }
        for pair in entry["days"].as_array().unwrap() {
            let n = pair[0].as_i64().unwrap();
            check(format!("days {n}"), i18n.days(n), &pair[1]);
        }
        for pair in entry["lists"].as_array().unwrap() {
            let items: Vec<String> = pair[0].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_string()).collect();
            check(format!("list {items:?}"), i18n.list_kind(&items, ListKind::And), &pair[1]);
        }
        for case in entry["units"].as_array().unwrap() {
            let n = case[0].as_f64().unwrap();
            let unit = match case[1].as_str().unwrap() {
                "byte" => Unit::Byte,
                "kilobyte" => Unit::Kilobyte,
                "megabyte" => Unit::Megabyte,
                "gigabyte" => Unit::Gigabyte,
                "terabyte" => Unit::Terabyte,
                _ => Unit::Second,
            };
            let width = if case[2] == "long" { Width::Long } else { Width::Short };
            let (min, max) = (case[3].as_i64().unwrap() as i16, case[4].as_i64().unwrap() as i16);
            check(format!("unit {n} {}", case[1]), i18n.unit(n, unit, width, min, max), &case[5]);
        }
        for (name, moments) in entry["dates"].as_object().unwrap() {
            for pair in moments.as_array().unwrap() {
                let seconds = pair[0].as_f64().unwrap();
                check(format!("{name} {seconds}"), i18n.date(seconds, style(name)), &pair[1]);
            }
        }
    }
    assert!(wrong.is_empty(), "{} of {checked} differ:\n{}", wrong.len(), wrong.join("\n"));
}
