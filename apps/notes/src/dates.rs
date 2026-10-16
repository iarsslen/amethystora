//! Days as notes.js counted them: ISO dates (`2026-10-16`) on the session's own calendar, a task's time as
//! `HH:MM`, and what the page calls each in the language's words. The arithmetic is on the civil calendar,
//! which is what JavaScript's Date did with setDate and setMonth on a date at midnight.

use amethystora_ui::i18n::{self, DateStyle};
use amethystora_ui::glib;

/// Days since 1970-01-01 of a civil date (Howard Hinnant's days_from_civil)
pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let yoe = year - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// The civil date of a number of days since 1970-01-01
pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    (if month <= 2 { yoe + era * 400 + 1 } else { yoe + era * 400 }, month, day)
}

pub fn iso(year: i64, month: i64, day: i64) -> String {
    format!("{year:04}-{month:02}-{day:02}")
}

/// parseDate: the parts of an ISO date, None when it is not one
pub fn parse(text: &str) -> Option<(i64, i64, i64)> {
    let mut parts = text.split('-');
    let year = parts.next()?.parse().ok()?;
    let month = parts.next()?.parse().ok()?;
    let day = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((year, month, day))
}

/// A date's days since the epoch, leniently as JavaScript's Date takes a month or day past its end
fn days_of(text: &str) -> Option<i64> {
    let (year, month, day) = parse(text)?;
    // new Date(year, month - 1, day): a month past December is the next year's
    let months = year * 12 + (month - 1);
    Some(days_from_civil(months.div_euclid(12), months.rem_euclid(12) + 1, 1) + day - 1)
}

/// /^\d{4}-\d{2}-\d{2}$/
pub fn is_iso(text: &str) -> bool {
    let bytes = text.as_bytes();
    bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes.iter().enumerate().all(|(at, b)| at == 4 || at == 7 || b.is_ascii_digit())
}

/// /^\d{2}:\d{2}$/
pub fn is_time(text: &str) -> bool {
    let bytes = text.as_bytes();
    bytes.len() == 5 && bytes[2] == b':' && bytes.iter().enumerate().all(|(at, b)| at == 2 || b.is_ascii_digit())
}

/// The moment, in milliseconds, broken down in the session's time zone
pub fn local_ms(ms: f64) -> Option<glib::DateTime> {
    glib::DateTime::from_unix_local((ms / 1000.0).floor() as i64).ok()
}

/// isoDate(new Date(ms))
pub fn iso_of_ms(ms: f64) -> String {
    match local_ms(ms) {
        Some(when) => iso(when.year() as i64, when.month() as i64, when.day_of_month() as i64),
        None => String::new(),
    }
}

/// today(): the session's date now
pub fn today() -> String {
    iso_of_ms(crate::data::now_ms())
}

pub fn add_days(text: &str, days: i64) -> String {
    match days_of(text) {
        Some(at) => {
            let (year, month, day) = civil_from_days(at + days);
            iso(year, month, day)
        }
        None => "NaN-NaN-NaN".into(),
    }
}

/// 0 for Sunday, as Date.getDay()
pub fn weekday(text: &str) -> Option<i64> {
    days_of(text).map(|at| (at + 4).rem_euclid(7))
}

/// The day of the week now, 0 for Sunday
pub fn weekday_now() -> i64 {
    weekday(&today()).unwrap_or(0)
}

/// `new Date().toTimeString().slice(0, 5)`: the time now, as HH:MM
pub fn time_now() -> String {
    match local_ms(crate::data::now_ms()) {
        Some(when) => format!("{:02}:{:02}", when.hour(), when.minute()),
        None => String::new(),
    }
}

/// The days in a month of a year
fn month_length(year: i64, month: i64) -> i64 {
    let next = if month == 12 { days_from_civil(year + 1, 1, 1) } else { days_from_civil(year, month + 1, 1) };
    next - days_from_civil(year, month, 1)
}

/// The next date of a repeating task. A month that has no such day ends on its last one.
pub fn add_interval(text: &str, every: i64, unit: &str) -> String {
    let Some(at) = days_of(text) else { return "NaN-NaN-NaN".into() };
    let every = every.max(1);
    let (year, month, day) = civil_from_days(at);
    match unit {
        "day" => add_days(text, every),
        "week" => add_days(text, every * 7),
        "month" | "year" => {
            let months = year * 12 + (month - 1) + if unit == "month" { every } else { every * 12 };
            let (year, month) = (months.div_euclid(12), months.rem_euclid(12) + 1);
            iso(year, month, day.min(month_length(year, month)))
        }
        _ => iso(year, month, day),
    }
}

/// Seconds since the epoch of a local date and time
pub fn local_seconds(year: i64, month: i64, day: i64, hour: i64, minute: i64) -> Option<f64> {
    // Through the days, so that a day past the month's end is the next month's, as Date had it
    let (year, month, day) = civil_from_days(days_from_civil(year, month, 1) + day - 1);
    glib::DateTime::from_local(year as i32, month as i32, day as i32, hour as i32, minute as i32, 0.0).ok().map(|d| d.to_unix() as f64)
}

/// When a task is due, in milliseconds: its date at its time, or at nine
pub fn due_ms(due: &str, time: Option<&str>) -> Option<f64> {
    let (year, month, day) = parse(due)?;
    let (hours, minutes) = time.unwrap_or("09:00").split_once(':')?;
    local_seconds(year, month, day, hours.parse().ok()?, minutes.parse().ok()?).map(|s| s * 1000.0)
}

fn seconds_of(text: &str) -> Option<f64> {
    let (year, month, day) = parse(text)?;
    local_seconds(year, month, day, 0, 0)
}

/// A day as a label, in the language's words: "Today", "Friday", "Mon 12 Oct"
pub fn day_label(text: &str, long: bool) -> String {
    let now = today();
    if let Some(near) = [0, 1, -1].into_iter().find(|days| text == add_days(&now, *days)) {
        return i18n::capital(&i18n::days(near));
    }
    let Some(seconds) = seconds_of(text) else { return String::new() };
    if text > now.as_str() && text <= add_days(&now, 6).as_str() {
        return i18n::capital(&i18n::date(seconds, DateStyle::Weekday));
    }
    let same_year = parse(text).map(|p| p.0) == parse(&now).map(|p| p.0);
    let style = match (long, same_year) {
        (true, true) => DateStyle::WeekdayDayMonth,
        (true, false) => DateStyle::WeekdayDayMonthYear,
        (false, true) => DateStyle::WeekdayDayMonthShort,
        (false, false) => DateStyle::WeekdayDayMonthYearShort,
    };
    i18n::capital(&i18n::date(seconds, style))
}

/// A task's time in the language's way: "5:30 PM", "17:30"
pub fn time_label(time: &str) -> String {
    let Some((hours, minutes)) = time.split_once(':') else { return time.to_string() };
    let (Ok(hours), Ok(minutes)) = (hours.parse::<i64>(), minutes.parse::<i64>()) else { return time.to_string() };
    match local_seconds(2000, 1, 1, hours, minutes) {
        Some(seconds) => i18n::date(seconds, DateStyle::TimeNumeric),
        None => time.to_string(),
    }
}

/// When a note changed: the time today, else the day
pub fn when_label(ms: f64) -> String {
    let seconds = (ms / 1000.0).floor();
    if iso_of_ms(ms) == today() {
        return i18n::date(seconds, DateStyle::TimeNumeric);
    }
    let same_year = local_ms(ms).map(|d| d.year()) == local_ms(crate::data::now_ms()).map(|d| d.year());
    i18n::date(seconds, if same_year { DateStyle::DayMonthShort } else { DateStyle::DayMonthYearShort })
}

/// { dateStyle: 'medium', timeStyle: 'short' }
pub fn stamp(ms: f64) -> String {
    i18n::date((ms / 1000.0).floor(), DateStyle::MediumShort)
}

/// The Today view's subtitle: the date in full, without the year
pub fn today_long() -> String {
    i18n::capital(&i18n::date(i18n::now().floor(), DateStyle::WeekdayDayMonth))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_days_as_date_did() {
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(civil_from_days(days_from_civil(2024, 2, 29)), (2024, 2, 29));
        assert_eq!(add_days("2026-12-31", 1), "2027-01-01");
        assert_eq!(add_days("2026-03-01", -1), "2026-02-28");
        assert_eq!(weekday("2026-10-16"), Some(5));
        // A month that has no such day ends on its last one
        assert_eq!(add_interval("2026-01-31", 1, "month"), "2026-02-28");
        assert_eq!(add_interval("2024-02-29", 1, "year"), "2025-02-28");
        assert_eq!(add_interval("2026-10-16", 2, "week"), "2026-10-30");
        assert_eq!(add_interval("2026-10-16", 0, "day"), "2026-10-17");
        assert_eq!(add_interval("2026-11-30", 3, "month"), "2027-02-28");
        assert!(is_iso("2026-10-16") && !is_iso("2026-1-16") && is_time("09:05") && !is_time("9:05"));
    }
}
