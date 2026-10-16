//! "3 hours ago", "in 5 minutes", "this minute": a time relative to now in minutes or hours, as
//! Intl.RelativeTimeFormat(locale, { numeric: "auto" }) wrote it for the Electron window, in the languages the
//! window is translated into. amethystora_ui has the days only (i18n::days); these are Chromium's own patterns
//! for the other two units, written out from Intl itself: (language, unit, form, pattern), the form an exact
//! value ("-1", "0") or "past-" or "future-" and a plural category. Another language falls back to English.

use amethystora_ui::i18n::{self, Arg};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Unit {
    Minute,
    Hour,
}

const PATTERNS: &[(&str, &str, &str, &str)] = &[
    ("en", "minute", "0", "this minute"),
    ("en", "minute", "past-one", "{0} minute ago"),
    ("en", "minute", "future-one", "in {0} minute"),
    ("en", "minute", "past-other", "{0} minutes ago"),
    ("en", "minute", "future-other", "in {0} minutes"),
    ("en", "hour", "0", "this hour"),
    ("en", "hour", "past-one", "{0} hour ago"),
    ("en", "hour", "future-one", "in {0} hour"),
    ("en", "hour", "past-other", "{0} hours ago"),
    ("en", "hour", "future-other", "in {0} hours"),
    ("ar", "minute", "-2", "قبل دقيقتين"),
    ("ar", "minute", "-1", "قبل دقيقة واحدة"),
    ("ar", "minute", "0", "هذه الدقيقة"),
    ("ar", "minute", "1", "خلال دقيقة واحدة"),
    ("ar", "minute", "2", "خلال دقيقتين"),
    ("ar", "minute", "past-few", "قبل {0} دقائق"),
    ("ar", "minute", "future-few", "خلال {0} دقائق"),
    ("ar", "minute", "past-many", "قبل {0} دقيقة"),
    ("ar", "minute", "future-many", "خلال {0} دقيقة"),
    ("ar", "minute", "past-other", "قبل {0} دقيقة"),
    ("ar", "minute", "future-other", "خلال {0} دقيقة"),
    ("ar", "hour", "-2", "قبل ساعتين"),
    ("ar", "hour", "-1", "قبل ساعة واحدة"),
    ("ar", "hour", "0", "الساعة الحالية"),
    ("ar", "hour", "1", "خلال ساعة واحدة"),
    ("ar", "hour", "2", "خلال ساعتين"),
    ("ar", "hour", "past-few", "قبل {0} ساعات"),
    ("ar", "hour", "future-few", "خلال {0} ساعات"),
    ("ar", "hour", "past-many", "قبل {0} ساعة"),
    ("ar", "hour", "future-many", "خلال {0} ساعة"),
    ("ar", "hour", "past-other", "قبل {0} ساعة"),
    ("ar", "hour", "future-other", "خلال {0} ساعة"),
    ("de", "minute", "0", "in dieser Minute"),
    ("de", "minute", "past-one", "vor {0} Minute"),
    ("de", "minute", "future-one", "in {0} Minute"),
    ("de", "minute", "past-other", "vor {0} Minuten"),
    ("de", "minute", "future-other", "in {0} Minuten"),
    ("de", "hour", "0", "in dieser Stunde"),
    ("de", "hour", "past-one", "vor {0} Stunde"),
    ("de", "hour", "future-one", "in {0} Stunde"),
    ("de", "hour", "past-other", "vor {0} Stunden"),
    ("de", "hour", "future-other", "in {0} Stunden"),
    ("es", "minute", "0", "este minuto"),
    ("es", "minute", "past-one", "hace {0} minuto"),
    ("es", "minute", "future-one", "dentro de {0} minuto"),
    ("es", "minute", "past-other", "hace {0} minutos"),
    ("es", "minute", "future-other", "dentro de {0} minutos"),
    ("es", "hour", "0", "esta hora"),
    ("es", "hour", "past-one", "hace {0} hora"),
    ("es", "hour", "future-one", "dentro de {0} hora"),
    ("es", "hour", "past-other", "hace {0} horas"),
    ("es", "hour", "future-other", "dentro de {0} horas"),
    ("fr", "minute", "0", "cette minute-ci"),
    ("fr", "minute", "past-one", "il y a {0} minute"),
    ("fr", "minute", "future-one", "dans {0} minute"),
    ("fr", "minute", "past-other", "il y a {0} minutes"),
    ("fr", "minute", "future-other", "dans {0} minutes"),
    ("fr", "hour", "0", "cette heure-ci"),
    ("fr", "hour", "past-one", "il y a {0} heure"),
    ("fr", "hour", "future-one", "dans {0} heure"),
    ("fr", "hour", "past-other", "il y a {0} heures"),
    ("fr", "hour", "future-other", "dans {0} heures"),
];

fn find(language: &str, unit: &str, form: &str) -> Option<&'static str> {
    PATTERNS.iter().find(|row| row.0 == language && row.1 == unit && row.2 == form).map(|row| row.3)
}

/// `value` minutes or hours from now (negative: ago), in the language `i18n` speaks
pub fn relative_in(i18n: &i18n::I18n, value: i64, unit: Unit) -> String {
    let unit = match unit {
        Unit::Minute => "minute",
        Unit::Hour => "hour",
    };
    let own = i18n.locale.id.language.as_str().to_string();
    let language = if PATTERNS.iter().any(|row| row.0 == own) { own.as_str() } else { "en" };
    if let Some(exact) = find(language, unit, &value.to_string()) {
        return exact.to_string();
    }
    let count = value.unsigned_abs() as f64;
    // The plural form the language's rules give the number, as the catalogs' plurals choose by
    let category = i18n.format("{n, plural, zero {zero} one {one} two {two} few {few} many {many} other {other}}", &[("n", Arg::Number(count))]);
    let kind = if value < 0 { "past" } else { "future" };
    let pattern = find(language, unit, &format!("{kind}-{category}"))
        .or_else(|| find(language, unit, &format!("{kind}-other")))
        .unwrap_or("{0}");
    pattern.replace("{0}", &i18n.number(count))
}

pub fn relative(value: i64, unit: Unit) -> String {
    i18n::with(|i18n| relative_in(i18n, value, unit))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn language(lang: &str, locale: &str) -> i18n::I18n {
        let folder = std::env::temp_dir().join(format!("amethystora-backups-relative-{}-{lang}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(folder.join(format!("{lang}.json")), "{}").unwrap();
        let loaded = i18n::I18n::load(&folder, &|name| (name == "LANG").then(|| locale.to_string()));
        std::fs::remove_dir_all(&folder).unwrap();
        loaded
    }

    #[test]
    fn as_intl_wrote_it() {
        let en = language("fr", "en_US.UTF-8");
        assert_eq!(relative_in(&en, -3, Unit::Hour), "3 hours ago");
        assert_eq!(relative_in(&en, -1, Unit::Hour), "1 hour ago");
        assert_eq!(relative_in(&en, 0, Unit::Minute), "this minute");
        assert_eq!(relative_in(&en, -1, Unit::Minute), "1 minute ago");
        assert_eq!(relative_in(&en, 25, Unit::Minute), "in 25 minutes");
        let fr = language("fr", "fr_FR.UTF-8");
        assert_eq!(relative_in(&fr, -1, Unit::Hour), "il y a 1 heure");
        assert_eq!(relative_in(&fr, -12, Unit::Hour), "il y a 12 heures");
        let ar = language("ar", "ar_EG.UTF-8");
        assert_eq!(relative_in(&ar, -3, Unit::Hour), "قبل ٣ ساعات");
        assert_eq!(relative_in(&ar, -2, Unit::Hour), "قبل ساعتين");
        assert_eq!(relative_in(&ar, -11, Unit::Minute), "قبل ١١ دقيقة");
    }
}
