//! Translations for the Amethystora apps: i18n.js, which the Electron windows shared, in Rust.
//!
//! The English text in the code is the key. `t!("Update now")` is looked up in the app's catalog for the
//! session's language, `locale/<language>.json`, and is its own English when the catalog has nothing for
//! it. A message carries its values by name, `{name}`, and its plurals and variants in ICU MessageFormat:
//!
//! ```text
//! t!("Last updated {when}", when = when)
//! t!("{count, plural, one {# file} other {# files}}", count = files.len())
//! t!("{state, select, on {On} other {Off}}", state = "on")
//! ```
//!
//! Braces are always syntax: there is no quoting. A number is written the language's way, with its
//! separators; pass a string for a number that is a name, such as a process number. `t_markup!` gives Pango
//! markup, with the message's own text escaped and the values made with `Arg::markup` left as they are,
//! for a sentence with code or a link in it; `t_parts!` gives the pieces, for one with a widget in it.
//!
//! The catalogs are flat JSON keyed by the English, in `/usr/lib/amethystora-<app>/resources/app/locale`,
//! where Weblate writes them. `build_files/shared/check-translations.js` reads the first string of every
//! `t!`, `t_parts!` and `t_markup!` in the apps' sources, writes `locale/en.json` from them and checks every
//! catalog against it, so the first argument is always a plain string literal.

use std::cell::OnceCell;
use std::collections::HashMap;
use std::path::Path;

use fixed_decimal::{Decimal, FloatPrecision, UnsignedRoundingMode};
use icu_collator::options::{CollatorOptions, Strength};
use icu_collator::preferences::CollationNumericOrdering;
use icu_collator::{Collator, CollatorBorrowed, CollatorPreferences};
use icu_datetime::fieldsets;
use icu_datetime::input::{Date, DateTime, Time};
use icu_datetime::options::{Alignment, TimePrecision};
use icu_datetime::preferences::HourCycle;
use icu_datetime::{DateTimeFormatter, DateTimeFormatterPreferences, NoCalendarFormatter};
use icu_decimal::DecimalFormatter;
use icu_experimental::relativetime::{RelativeTimeFormatter, RelativeTimeFormatterOptions, options::Numeric};
use icu_list::options::{ListFormatterOptions, ListLength};
use icu_list::ListFormatter;
use icu_locale_core::Locale;
use icu_plurals::{PluralCategory, PluralRules};

/// Languages written from right to left, by their ISO 639 codes
const RTL: &[&str] = &["ar", "arc", "ckb", "dv", "fa", "he", "ks", "ps", "sd", "ug", "ur", "yi"];

/// The folder an app's catalogs are in
pub fn catalogs(app: &str) -> std::path::PathBuf {
    Path::new("/usr/lib").join(format!("amethystora-{app}")).join("resources/app/locale")
}

fn is_tag(tag: &str) -> bool {
    let mut parts = tag.split('-');
    let first = parts.next().unwrap_or("");
    (2..=3).contains(&first.len())
        && first.chars().all(|c| c.is_ascii_alphabetic())
        && parts.all(|part| (2..=8).contains(&part.len()) && part.chars().all(|c| c.is_ascii_alphanumeric()))
}

/// The session's languages, best first, the way gettext reads them: LANGUAGE is a list (fr:en), and
/// LC_ALL, LC_MESSAGES or LANG one locale (fr_FR.UTF-8). LANGUAGE counts only under a real locale: C and
/// POSIX mean English whatever it says.
pub fn wanted(env: &dyn Fn(&str) -> Option<String>) -> Vec<String> {
    let locale = ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .find_map(|name| env(name).filter(|value| !value.is_empty()))
        .unwrap_or_default();
    let c = |value: &str| {
        value
            .strip_prefix('C')
            .or_else(|| value.strip_prefix("POSIX"))
            .is_some_and(|rest| rest.is_empty() || rest.starts_with(['.', '_', '@']))
    };
    if locale.is_empty() || c(&locale) {
        return Vec::new();
    }
    let languages = env("LANGUAGE").unwrap_or_default();
    languages
        .split(':')
        .chain(std::iter::once(locale.as_str()))
        .map(|tag| tag.split(['.', '@']).next().unwrap_or("").replace('_', "-"))
        .filter(|tag| is_tag(tag))
        .collect()
}

/// The language to show, of those a catalog exists for: the first wanted one, by its whole tag or by its
/// language alone (pt-BR, then pt). English is the code's own and needs no catalog.
pub fn choose(available: &[String], wanted: &[String]) -> String {
    let lower: Vec<String> = available.iter().map(|tag| tag.to_lowercase()).collect();
    for tag in wanted {
        let language = tag.split('-').next().unwrap_or("").to_lowercase();
        if language == "en" {
            return "en".into();
        }
        if let Some(at) = lower.iter().position(|other| *other == tag.to_lowercase()) {
            return available[at].clone();
        }
        if let Some(at) = lower.iter().position(|other| *other == language) {
            return available[at].clone();
        }
    }
    "en".into()
}

pub fn is_rtl(lang: &str) -> bool {
    RTL.contains(&lang.split('-').next().unwrap_or("").to_lowercase().as_str())
}

// --- Messages -------------------------------------------------------------------------------------------

/// A message as parts: text, the # of a plural, and a value with its plural or select options
#[derive(Debug, Clone, PartialEq)]
pub enum Node {
    Text(String),
    Hash,
    Value { name: String, kind: Kind, options: Vec<(String, Vec<Node>)> },
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Kind {
    Plain,
    Plural,
    Select,
}

/// Why a message does not parse, with where in it
#[derive(Debug)]
pub struct ParseError(pub String);

struct Parser<'a> {
    chars: Vec<char>,
    at: usize,
    message: &'a str,
}

impl Parser<'_> {
    fn fail<T>(&self, what: &str) -> Result<T, ParseError> {
        Err(ParseError(format!("{what} at {} in \"{}\"", self.at, self.message)))
    }

    fn rest(&self) -> String {
        self.chars[self.at..].iter().collect()
    }

    fn skip_space(&mut self) {
        while self.at < self.chars.len() && self.chars[self.at].is_whitespace() {
            self.at += 1;
        }
    }

    fn word(&mut self) -> Option<String> {
        let start = self.at;
        while self.at < self.chars.len() && (self.chars[self.at].is_alphanumeric() || self.chars[self.at] == '_') {
            self.at += 1;
        }
        (self.at > start).then(|| self.chars[start..self.at].iter().collect())
    }

    fn parts(&mut self, in_plural: bool, nested: bool) -> Result<Vec<Node>, ParseError> {
        let mut list = Vec::new();
        let mut text = String::new();
        while self.at < self.chars.len() {
            let c = self.chars[self.at];
            if c == '}' {
                if !nested {
                    return self.fail("a } that closes nothing");
                }
                break;
            }
            if c == '{' {
                if !text.is_empty() {
                    list.push(Node::Text(std::mem::take(&mut text)));
                }
                list.push(self.argument(in_plural)?);
            } else if c == '#' && in_plural {
                if !text.is_empty() {
                    list.push(Node::Text(std::mem::take(&mut text)));
                }
                list.push(Node::Hash);
                self.at += 1;
            } else {
                text.push(c);
                self.at += 1;
            }
        }
        if !text.is_empty() {
            list.push(Node::Text(text));
        }
        Ok(list)
    }

    // { name } or { name, plural|select, key {...} ... other {...} }, as i18n.js's regular expressions
    // read it: spaces are allowed around every part
    fn argument(&mut self, in_plural: bool) -> Result<Node, ParseError> {
        self.at += 1;
        self.skip_space();
        let Some(name) = self.word() else {
            return self.fail("a value without a name");
        };
        self.skip_space();
        let mut kind = Kind::Plain;
        if self.chars.get(self.at) == Some(&',') {
            let back = self.at;
            self.at += 1;
            self.skip_space();
            match self.word().as_deref() {
                Some("plural") => kind = Kind::Plural,
                Some("select") => kind = Kind::Select,
                _ => {
                    self.at = back;
                }
            }
            if kind != Kind::Plain {
                self.skip_space();
                if self.chars.get(self.at) != Some(&',') {
                    self.at = back;
                    kind = Kind::Plain;
                } else {
                    self.at += 1;
                    self.skip_space();
                }
            }
        }
        if kind == Kind::Plain {
            if self.chars.get(self.at) == Some(&'}') {
                self.at += 1;
                return Ok(Node::Value { name, kind, options: Vec::new() });
            }
            return self.fail(&format!("a value {name} that is not closed"));
        }
        let mut options = Vec::new();
        loop {
            let back = self.at;
            self.skip_space();
            let key = if self.chars.get(self.at) == Some(&'=') {
                self.at += 1;
                let start = self.at;
                while self.at < self.chars.len() && self.chars[self.at].is_ascii_digit() {
                    self.at += 1;
                }
                if self.at == start {
                    self.at = back;
                    break;
                }
                format!("={}", self.chars[start..self.at].iter().collect::<String>())
            } else if let Some(word) = self.word() {
                word
            } else {
                self.at = back;
                break;
            };
            self.skip_space();
            if self.chars.get(self.at) != Some(&'{') {
                self.at = back;
                break;
            }
            self.at += 1;
            let body = self.parts(kind == Kind::Plural || in_plural, true)?;
            if self.chars.get(self.at) != Some(&'}') {
                return self.fail(&format!("the option {key} of {name} is not closed"));
            }
            self.at += 1;
            options.push((key, body));
        }
        self.skip_space();
        if self.chars.get(self.at) != Some(&'}') || !options.iter().any(|(key, _)| key == "other") {
            return self.fail(&format!("{name} needs an \"other\" option and a closing }}"));
        }
        self.at += 1;
        let _ = self.rest();
        Ok(Node::Value { name, kind, options })
    }
}

pub fn parse(message: &str) -> Result<Vec<Node>, ParseError> {
    let mut parser = Parser { chars: message.chars().collect(), at: 0, message };
    parser.parts(false, false)
}

/// The names of the values a message takes, and of those its plurals and selects choose by
pub fn names(message: &str) -> Result<Vec<String>, ParseError> {
    fn walk(list: &[Node], found: &mut Vec<String>) {
        for node in list {
            if let Node::Value { name, options, .. } = node {
                if !found.contains(name) {
                    found.push(name.clone());
                }
                for (_, body) in options {
                    walk(body, found);
                }
            }
        }
    }
    let mut found = Vec::new();
    walk(&parse(message)?, &mut found);
    Ok(found)
}

// --- Values ---------------------------------------------------------------------------------------------

/// A value a message is given
#[derive(Debug, Clone)]
pub enum Arg {
    /// Text, shown as it is (escaped in markup)
    Text(String),
    /// A number, written the language's way
    Number(f64),
    /// Pango markup, for t_markup!, kept as it is
    Markup(String),
}

impl Arg {
    /// Markup to put in a sentence as it is: code, a link
    pub fn markup(markup: impl Into<String>) -> Self {
        Arg::Markup(markup.into())
    }

    /// Text in the monospace face, as `<code>` was
    pub fn code(text: &str) -> Self {
        Arg::Markup(format!("<span font_family=\"monospace\">{}</span>", glib_escape(text)))
    }

    fn number(&self) -> f64 {
        match self {
            Arg::Number(n) => *n,
            Arg::Text(text) | Arg::Markup(text) => text.trim().parse().unwrap_or(f64::NAN),
        }
    }

    fn select_key(&self) -> String {
        match self {
            Arg::Number(n) => js_number(*n),
            Arg::Text(text) | Arg::Markup(text) => text.clone(),
        }
    }
}

/// How JavaScript's String() writes a number, which is what a select is matched by
fn js_number(n: f64) -> String {
    if n.fract() == 0.0 && n.abs() < 1e21 { format!("{}", n as i64) } else { format!("{n}") }
}

macro_rules! from_text {
    ($($t:ty),*) => { $(impl From<$t> for Arg { fn from(value: $t) -> Self { Arg::Text(value.to_string()) } })* };
}
from_text!(&str, String, &String, char);

macro_rules! from_number {
    ($($t:ty),*) => { $(impl From<$t> for Arg { fn from(value: $t) -> Self { Arg::Number(value as f64) } })* };
}
from_number!(i8, i16, i32, i64, u8, u16, u32, u64, usize, isize, f32, f64);

impl From<&Arg> for Arg {
    fn from(value: &Arg) -> Self {
        value.clone()
    }
}

fn glib_escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(c),
        }
    }
    out
}

/// A piece of a message given as parts: its own text, or one of the values it was given, by name
#[derive(Debug, Clone, PartialEq)]
pub enum Piece {
    Text(String),
    Value(String),
}

// --- One language ---------------------------------------------------------------------------------------

/// The language the windows speak, read once at start: the session's language does not change under it
pub struct I18n {
    /// The catalog's language: "fr"
    pub lang: String,
    /// The session's own tag in that language, which dates, numbers and lists are written for: en-US and
    /// en-GB share the English, not the order of a date
    pub locale: Locale,
    pub rtl: bool,
    strings: HashMap<String, String>,
    plurals: PluralRules,
    decimals: DecimalFormatter,
}

thread_local! {
    static CURRENT: OnceCell<I18n> = const { OnceCell::new() };
}

impl I18n {
    /// The language and catalog of an app whose catalogs are in `folder`
    pub fn load(folder: &Path, env: &dyn Fn(&str) -> Option<String>) -> I18n {
        let mut available = Vec::new();
        if let Ok(entries) = std::fs::read_dir(folder) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().into_owned();
                if let Some(tag) = name.strip_suffix(".json") {
                    if is_tag(tag) && tag != "en" {
                        available.push(tag.to_string());
                    }
                }
            }
        }
        available.sort();
        let wanted = wanted(env);
        let mut lang = choose(&available, &wanted);
        let mut strings = HashMap::new();
        if lang != "en" {
            match std::fs::read_to_string(folder.join(format!("{lang}.json")))
                .ok()
                .and_then(|text| serde_json::from_str::<HashMap<String, serde_json::Value>>(&text).ok())
            {
                Some(catalog) => {
                    strings = catalog
                        .into_iter()
                        .filter_map(|(key, value)| value.as_str().map(|value| (key, value.to_string())))
                        .collect();
                }
                None => lang = "en".into(),
            }
        }
        let language = lang.split('-').next().unwrap_or("").to_lowercase();
        // The session's own tag in the chosen language, when it has one: fr-CA for fr, en-US for English
        let own = wanted.iter().find(|tag| tag.split('-').next().unwrap_or("").to_lowercase() == language);
        let locale = own
            .and_then(|tag| Locale::try_from_str(tag).ok())
            .or_else(|| Locale::try_from_str(&lang).ok())
            .unwrap_or_else(|| Locale::try_from_str("en").expect("en is a locale"));
        I18n::new(lang, locale, strings)
    }

    pub fn new(lang: String, locale: Locale, strings: HashMap<String, String>) -> I18n {
        let plurals = PluralRules::try_new_cardinal((&locale).into())
            .or_else(|_| PluralRules::try_new_cardinal(Default::default()))
            .expect("the root locale has plural rules");
        let decimals = DecimalFormatter::try_new((&locale).into(), Default::default())
            .or_else(|_| DecimalFormatter::try_new(Default::default(), Default::default()))
            .expect("the root locale has decimal symbols");
        I18n { rtl: is_rtl(&lang), lang, locale, strings, plurals, decimals }
    }

    /// Makes this the language of everything on this thread, which is the app's main thread
    pub fn install(self) {
        CURRENT.with(|cell| {
            let _ = cell.set(self);
        });
    }

    /// What the English message is in this language
    fn translated<'a>(&'a self, message: &'a str) -> &'a str {
        match self.strings.get(message) {
            Some(own) if !own.is_empty() => own,
            _ => message,
        }
    }

    fn render(&self, list: &[Node], values: &[(&str, Arg)], count: f64, out: &mut Vec<Out>) {
        let find = |name: &str| values.iter().find(|(key, _)| key.trim_start_matches("r#") == name).map(|(_, value)| value);
        for node in list {
            match node {
                Node::Text(text) => out.push(Out::Text(text.clone())),
                Node::Hash => out.push(Out::Text(self.number(count))),
                Node::Value { name, kind: Kind::Plural, options } => {
                    let n = find(name).map(Arg::number).unwrap_or(f64::NAN);
                    let exact = format!("={}", js_number(n));
                    let category = self.plural_category(n);
                    let option = options
                        .iter()
                        .find(|(key, _)| *key == exact)
                        .or_else(|| options.iter().find(|(key, _)| key == category))
                        .or_else(|| options.iter().find(|(key, _)| key == "other"));
                    if let Some((_, body)) = option {
                        self.render(body, values, n, out);
                    }
                }
                Node::Value { name, kind: Kind::Select, options } => {
                    let key = find(name).map(Arg::select_key).unwrap_or_else(|| "undefined".into());
                    let option = options
                        .iter()
                        .find(|(option, _)| *option == key)
                        .or_else(|| options.iter().find(|(option, _)| option == "other"));
                    if let Some((_, body)) = option {
                        self.render(body, values, count, out);
                    }
                }
                Node::Value { name, .. } => match find(name) {
                    None => out.push(Out::Text(format!("{{{name}}}"))),
                    Some(Arg::Number(n)) => out.push(Out::Text(self.number(*n))),
                    Some(Arg::Text(text)) => out.push(Out::Value(name.clone(), text.clone(), false)),
                    Some(Arg::Markup(markup)) => out.push(Out::Value(name.clone(), markup.clone(), true)),
                },
            }
        }
    }

    fn plural_category(&self, n: f64) -> &'static str {
        if !n.is_finite() {
            return "other";
        }
        let decimal = Decimal::try_from_f64(n.abs(), FloatPrecision::RoundTrip).unwrap_or_default();
        match self.plurals.category_for(&decimal) {
            PluralCategory::Zero => "zero",
            PluralCategory::One => "one",
            PluralCategory::Two => "two",
            PluralCategory::Few => "few",
            PluralCategory::Many => "many",
            PluralCategory::Other => "other",
        }
    }

    fn rendered(&self, message: &str, values: &[(&str, Arg)]) -> Vec<Out> {
        self.rendered_text(self.translated(message), values)
    }

    fn rendered_text(&self, text: &str, values: &[(&str, Arg)]) -> Vec<Out> {
        let list = parse(text).unwrap_or_else(|_| vec![Node::Text(text.to_string())]);
        let mut out = Vec::new();
        self.render(&list, values, 0.0, &mut out);
        out
    }

    pub fn tr(&self, message: &str, values: &[(&str, Arg)]) -> String {
        let mut text = String::new();
        for piece in self.rendered(message, values) {
            match piece {
                Out::Text(part) | Out::Value(_, part, _) => text.push_str(&part),
            }
        }
        text
    }

    /// A text rendered as it is, with no catalog: for the tests, which hand it the translation itself
    pub fn format(&self, text: &str, values: &[(&str, Arg)]) -> String {
        let mut out = String::new();
        for piece in self.rendered_text(text, values) {
            match piece {
                Out::Text(part) | Out::Value(_, part, _) => out.push_str(&part),
            }
        }
        out
    }

    /// The message as Pango markup: its text and its text values escaped, its markup values as they are
    pub fn markup(&self, message: &str, values: &[(&str, Arg)]) -> String {
        let mut text = String::new();
        for piece in self.rendered(message, values) {
            match piece {
                Out::Text(part) | Out::Value(_, part, false) => text.push_str(&glib_escape(&part)),
                Out::Value(_, part, true) => text.push_str(&part),
            }
        }
        text
    }

    /// The message as its text and the values it places, by name, for a sentence with a widget in it
    pub fn parts(&self, message: &str, values: &[(&str, Arg)]) -> Vec<Piece> {
        let mut joined: Vec<Piece> = Vec::new();
        for piece in self.rendered(message, values) {
            match piece {
                Out::Text(part) => match joined.last_mut() {
                    Some(Piece::Text(last)) => last.push_str(&part),
                    _ => joined.push(Piece::Text(part)),
                },
                Out::Value(name, _, _) => joined.push(Piece::Value(name)),
            }
        }
        joined
    }

    // --- Numbers, lists, days and dates --------------------------------------------------------------

    /// A number as Intl.NumberFormat writes it by default: the language's digits and separators, and at
    /// most three decimals, rounded half away from zero
    pub fn number(&self, n: f64) -> String {
        self.number_with(n, 0, 3, 1)
    }

    /// With at least `min` and at most `max` decimals, and at least `integer` digits before the point
    pub fn number_with(&self, n: f64, min: i16, max: i16, integer: i16) -> String {
        if n.is_nan() {
            return "NaN".into();
        }
        if n.is_infinite() {
            return if n > 0.0 { "∞".into() } else { "-∞".into() };
        }
        let mut decimal = Decimal::try_from_f64(n, FloatPrecision::RoundTrip).unwrap_or_default();
        decimal.round_with_mode(-max, fixed_decimal::SignedRoundingMode::Unsigned(UnsignedRoundingMode::HalfExpand));
        decimal.trim_end();
        decimal.absolute.pad_end(-min);
        decimal.absolute.pad_start(integer);
        if decimal.absolute.is_zero() {
            decimal.sign = fixed_decimal::Sign::None;
        }
        self.decimals.format(&decimal).to_string()
    }

    /// A fraction as a percentage with no decimals: 0.5 is "50%", "50 %", "٥٠٪؜"
    pub fn percent(&self, fraction: f64) -> String {
        use icu_experimental::dimension::percent::formatter::PercentFormatter;
        let mut decimal = Decimal::try_from_f64(fraction * 100.0, FloatPrecision::RoundTrip).unwrap_or_default();
        decimal.round_with_mode(0, fixed_decimal::SignedRoundingMode::Unsigned(UnsignedRoundingMode::HalfExpand));
        decimal.trim_end();
        match PercentFormatter::try_new((&self.locale).into(), Default::default()) {
            Ok(formatter) => formatter.format(&decimal).to_string(),
            Err(_) => format!("{}%", self.number(fraction * 100.0)),
        }
    }

    /// A number with a unit, as Intl.NumberFormat with style: 'unit' wrote it: "1.4 MB", "512 bytes", "3 s",
    /// with at least `min` and at most `max` decimals
    pub fn unit(&self, value: f64, unit: Unit, width: Width, min: i16, max: i16) -> String {
        let mut decimal = Decimal::try_from_f64(value, FloatPrecision::RoundTrip).unwrap_or_default();
        decimal.round_with_mode(-max, fixed_decimal::SignedRoundingMode::Unsigned(UnsignedRoundingMode::HalfExpand));
        decimal.trim_end();
        decimal.absolute.pad_end(-min);
        let category = match self.plurals.category_for(&decimal) {
            PluralCategory::Zero => "zero",
            PluralCategory::One => "one",
            PluralCategory::Two => "two",
            PluralCategory::Few => "few",
            PluralCategory::Many => "many",
            PluralCategory::Other => "other",
        };
        let number = self.decimals.format(&decimal).to_string();
        let (unit, width) = (unit.name(), if width == Width::Long { "long" } else { "short" });
        let language = self.locale.id.language.as_str().to_string();
        let regional = match self.locale.id.region {
            Some(region) => format!("{language}-{}", region.as_str()),
            None => language.clone(),
        };
        let find = |language: &str, category: &str| {
            crate::units::PATTERNS.iter().find(|(l, u, w, c, _)| *l == language && *u == unit && *w == width && *c == category).map(|p| p.4)
        };
        let pattern = find(&regional, category)
            .or_else(|| find(&language, category))
            .or_else(|| find(&language, "other"))
            .or_else(|| find("en", if category == "one" { "one" } else { "other" }))
            .unwrap_or("{0}");
        pattern.replace("{0}", &number)
    }

    /// "a, b and c" the way the language joins them
    pub fn list(&self, items: &[String]) -> String {
        self.list_kind(items, ListKind::And)
    }

    pub fn list_kind(&self, items: &[String], kind: ListKind) -> String {
        let options = ListFormatterOptions::default().with_length(match kind {
            ListKind::Unit => ListLength::Narrow,
            _ => ListLength::Wide,
        });
        let formatter = match kind {
            ListKind::And => ListFormatter::try_new_and((&self.locale).into(), options),
            ListKind::Or => ListFormatter::try_new_or((&self.locale).into(), options),
            ListKind::Unit => ListFormatter::try_new_unit((&self.locale).into(), ListFormatterOptions::default().with_length(ListLength::Wide)),
        };
        match formatter {
            Ok(formatter) => formatter.format(items.iter().map(String::as_str)).to_string(),
            Err(_) => items.join(", "),
        }
    }

    /// "yesterday", "today", "tomorrow", "in 3 days": a day relative to today, in the language's words
    pub fn days(&self, days: i64) -> String {
        let mut options = RelativeTimeFormatterOptions::default();
        options.numeric = Numeric::Auto;
        match RelativeTimeFormatter::try_new_long_day((&self.locale).into(), options) {
            Ok(formatter) => formatter.format(Decimal::from(days)).to_string(),
            Err(_) => format!("{days}"),
        }
    }

    fn datetime_prefs(&self, hour_cycle: Option<HourCycle>) -> DateTimeFormatterPreferences {
        let mut prefs: DateTimeFormatterPreferences = (&self.locale).into();
        if hour_cycle.is_some() {
            prefs.hour_cycle = hour_cycle;
        }
        prefs
    }

    /// A moment, in seconds since the epoch, in the session's time zone, in one of the forms the apps write
    pub fn date(&self, seconds: f64, style: DateStyle) -> String {
        let Some(local) = local(seconds) else {
            return String::new();
        };
        let date = Date::try_new_iso(local.year, local.month, local.day).ok();
        let time = Time::try_new(local.hour, local.minute, local.second, 0).ok();
        let (Some(date), Some(time)) = (date, time) else {
            return String::new();
        };
        let datetime = DateTime { date, time };
        macro_rules! with {
            ($prefs:expr, $fieldset:expr, $input:expr) => {
                match DateTimeFormatter::try_new($prefs, $fieldset) {
                    Ok(formatter) => formatter.format($input).to_string(),
                    Err(_) => String::new(),
                }
            };
        }
        macro_rules! time_only {
            ($prefs:expr, $fieldset:expr) => {
                match NoCalendarFormatter::try_new($prefs, $fieldset) {
                    Ok(formatter) => formatter.format(&time).to_string(),
                    Err(_) => String::new(),
                }
            };
        }
        let prefs = self.datetime_prefs(None);
        let column = Alignment::Column;
        let text = match style {
            // { hour: '2-digit', minute: '2-digit' }
            DateStyle::Time => time_only!(prefs, fieldsets::T::hm().with_alignment(column)),
            // { hour: 'numeric', minute: '2-digit' }
            DateStyle::TimeNumeric => time_only!(prefs, fieldsets::T::hm()),
            // { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }
            DateStyle::Time24 => time_only!(self.datetime_prefs(Some(HourCycle::H23)), fieldsets::T::hm().with_alignment(column)),
            // { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }
            DateStyle::Time24Seconds => time_only!(self.datetime_prefs(Some(HourCycle::H23)), fieldsets::T::hms().with_alignment(column)),
            // { weekday: 'long' }
            DateStyle::Weekday => with!(prefs, fieldsets::E::long(), &date),
            // { weekday: 'short', day: 'numeric', month: 'short' }
            DateStyle::WeekdayDayMonthShort => with!(prefs, fieldsets::MDE::medium(), &date),
            // { weekday: 'long', day: 'numeric', month: 'long' }
            DateStyle::WeekdayDayMonth => with!(prefs, fieldsets::MDE::long(), &date),
            // { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }
            DateStyle::WeekdayDayMonthYear => with!(prefs, fieldsets::YMDE::long(), &date),
            // { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }
            DateStyle::WeekdayDayMonthYearShort => with!(prefs, fieldsets::YMDE::medium(), &date),
            // { day: 'numeric', month: 'long', year: 'numeric' }
            DateStyle::DayMonthYear => with!(prefs, fieldsets::YMD::long(), &date),
            // { day: 'numeric', month: 'short' }
            DateStyle::DayMonthShort => with!(prefs, fieldsets::MD::medium(), &date),
            // { day: 'numeric', month: 'short', year: 'numeric' }
            DateStyle::DayMonthYearShort => with!(prefs, fieldsets::YMD::medium(), &date),
            // { dateStyle: 'medium', timeStyle: 'short' }
            DateStyle::MediumShort => with!(prefs, fieldsets::YMD::medium().with_time(TimePrecision::Minute), &datetime),
        };
        // V8 writes a plain space where CLDR has a narrow no-break one, as before "PM"
        let text = text.replace('\u{202f}', " ");
        // hour: 'numeric' is never padded, where ICU4X's semantic skeletons pad it in the locales that
        // write the time as HH:mm; Spanish's short time is H:mm, which ICU4X pads too
        match style {
            DateStyle::TimeNumeric => unpad_hour(&text, false),
            DateStyle::MediumShort if self.lang == "es" => unpad_hour(&text, true),
            _ => text,
        }
    }

    /// A comparison of names the way people sort them: case and accents aside, numbers by their value
    pub fn collator(&self) -> Option<CollatorBorrowed<'static>> {
        let mut prefs: CollatorPreferences = (&self.locale).into();
        prefs.numeric_ordering = Some(CollationNumericOrdering::True);
        let mut options = CollatorOptions::default();
        options.strength = Some(Strength::Primary);
        Collator::try_new(prefs, options).ok()
    }
}

/// The hour without its leading zero: the first run of digits, or with `from_end` the one before the last
/// (the minutes), in any script's digits
fn unpad_hour(text: &str, from_end: bool) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut runs = Vec::new();
    let mut at = 0;
    while at < chars.len() {
        if chars[at].is_numeric() {
            let start = at;
            while at < chars.len() && chars[at].is_numeric() {
                at += 1;
            }
            runs.push((start, at));
        } else {
            at += 1;
        }
    }
    let run = if from_end { runs.len().checked_sub(2).map(|i| runs[i]) } else { runs.first().copied() };
    match run {
        Some((start, end)) if end - start == 2 && is_zero(chars[start]) => {
            chars.iter().enumerate().filter(|(i, _)| *i != start).map(|(_, c)| c).collect()
        }
        _ => text.to_string(),
    }
}

/// A zero in any of the scripts' digits the apps' languages use
fn is_zero(c: char) -> bool {
    matches!(c, '0' | '٠' | '۰' | '०' | '০')
}

/// The units the apps write numbers in
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Unit {
    Byte,
    Kilobyte,
    Megabyte,
    Gigabyte,
    Terabyte,
    Second,
}

impl Unit {
    fn name(self) -> &'static str {
        match self {
            Unit::Byte => "byte",
            Unit::Kilobyte => "kilobyte",
            Unit::Megabyte => "megabyte",
            Unit::Gigabyte => "gigabyte",
            Unit::Terabyte => "terabyte",
            Unit::Second => "second",
        }
    }
}

/// unitDisplay: short ("kB") or long ("kilobytes")
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Width {
    Short,
    Long,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ListKind {
    And,
    Or,
    Unit,
}

/// The forms of a date the apps write, each named for the Intl options it stands for in the comment
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DateStyle {
    Time,
    TimeNumeric,
    Time24,
    Time24Seconds,
    Weekday,
    WeekdayDayMonthShort,
    WeekdayDayMonth,
    WeekdayDayMonthYear,
    WeekdayDayMonthYearShort,
    DayMonthYear,
    DayMonthShort,
    DayMonthYearShort,
    MediumShort,
}

enum Out {
    Text(String),
    /// A value by name, its text, and whether that text is markup
    Value(String, String, bool),
}

/// A moment broken down in the session's time zone
pub struct Local {
    pub year: i32,
    pub month: u8,
    pub day: u8,
    pub hour: u8,
    pub minute: u8,
    pub second: u8,
    /// 0 for Sunday, as Date.getDay()
    pub weekday: u8,
}

pub fn local(seconds: f64) -> Option<Local> {
    let when = gtk::glib::DateTime::from_unix_local(seconds.floor() as i64).ok()?;
    Some(Local {
        year: when.year(),
        month: when.month() as u8,
        day: when.day_of_month() as u8,
        hour: when.hour() as u8,
        minute: when.minute() as u8,
        second: when.second() as u8,
        weekday: (when.day_of_week() % 7) as u8,
    })
}

/// Seconds since the epoch, now
pub fn now() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

/// Midnight of the day a moment falls on, in the session's time zone, in seconds since the epoch
pub fn midnight(seconds: f64) -> f64 {
    local(seconds)
        .and_then(|l| gtk::glib::DateTime::from_local(l.year, l.month as i32, l.day as i32, 0, 0, 0.0).ok())
        .map(|d| d.to_unix() as f64)
        .unwrap_or(seconds)
}

/// The number of days between today and the day a moment falls on: -1 for yesterday
pub fn days_from_today(seconds: f64) -> i64 {
    ((midnight(seconds) - midnight(now())) / 86400.0).round() as i64
}

// --- The thread's language ------------------------------------------------------------------------------

/// Runs `f` with the app's language; English, with no catalog, before the app loaded one
pub fn with<R>(f: impl FnOnce(&I18n) -> R) -> R {
    CURRENT.with(|cell| {
        let current = cell.get_or_init(|| I18n::new("en".into(), Locale::try_from_str("en").expect("en"), HashMap::new()));
        f(current)
    })
}

pub fn tr(message: &str, values: &[(&str, Arg)]) -> String {
    with(|i18n| i18n.tr(message, values))
}

pub fn markup(message: &str, values: &[(&str, Arg)]) -> String {
    with(|i18n| i18n.markup(message, values))
}

pub fn parts(message: &str, values: &[(&str, Arg)]) -> Vec<Piece> {
    with(|i18n| i18n.parts(message, values))
}

/// A message that is not written in the code but read from data the catalog lists as well, such as the
/// section names in the Manual's pages.json, which check-translations.js reads for it
pub fn dynamic(message: &str) -> String {
    tr(message, &[])
}

pub fn number(n: f64) -> String {
    with(|i18n| i18n.number(n))
}

pub fn percent(fraction: f64) -> String {
    with(|i18n| i18n.percent(fraction))
}

pub fn list(items: &[String]) -> String {
    with(|i18n| i18n.list(items))
}

pub fn days(days: i64) -> String {
    with(|i18n| i18n.days(days))
}

pub fn unit(value: f64, unit: Unit, width: Width, min: i16, max: i16) -> String {
    with(|i18n| i18n.unit(value, unit, width, min, max))
}

pub fn date(seconds: f64, style: DateStyle) -> String {
    with(|i18n| i18n.date(seconds, style))
}

pub fn is_rtl_now() -> bool {
    with(|i18n| i18n.rtl)
}

/// Capitalises the first letter, as the apps do with a weekday some languages write in lower case
pub fn capital(text: &str) -> String {
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => {
            let mut out: String = first.to_uppercase().collect();
            out.push_str(chars.as_str());
            out
        }
        None => String::new(),
    }
}

/// The message in English, translated, with its values: `t!("Last updated {when}", when = when)`
#[macro_export]
macro_rules! t {
    ($message:literal) => {
        $crate::i18n::tr($message, &[])
    };
    ($message:literal, $($name:ident = $value:expr),+ $(,)?) => {
        $crate::i18n::tr($message, &[$((stringify!($name), $crate::i18n::Arg::from($value))),+])
    };
}

/// The message as Pango markup, with values made by `Arg::markup` or `Arg::code` kept as they are
#[macro_export]
macro_rules! t_markup {
    ($message:literal) => {
        $crate::i18n::markup($message, &[])
    };
    ($message:literal, $($name:ident = $value:expr),+ $(,)?) => {
        $crate::i18n::markup($message, &[$((stringify!($name), $crate::i18n::Arg::from($value))),+])
    };
}

/// The message as pieces of text and the names of the values it places
#[macro_export]
macro_rules! t_parts {
    ($message:literal) => {
        $crate::i18n::parts($message, &[])
    };
    ($message:literal, $($name:ident = $value:expr),+ $(,)?) => {
        $crate::i18n::parts($message, &[$((stringify!($name), $crate::i18n::Arg::from($value))),+])
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        move |name| map.get(name).cloned()
    }

    #[test]
    fn wanted_reads_gettext_order() {
        assert_eq!(wanted(&env(&[("LANG", "fr_FR.UTF-8")])), vec!["fr-FR"]);
        assert_eq!(wanted(&env(&[("LANG", "de_DE.UTF-8"), ("LANGUAGE", "fr:en")])), vec!["fr", "en", "de-DE"]);
        assert!(wanted(&env(&[("LANG", "C.UTF-8"), ("LANGUAGE", "fr")])).is_empty());
        assert!(wanted(&env(&[("LANG", "POSIX")])).is_empty());
        assert_eq!(wanted(&env(&[("LC_ALL", "ar_EG.UTF-8@latin"), ("LANG", "fr_FR")])), vec!["ar-EG"]);
    }

    #[test]
    fn choose_takes_whole_tag_then_language() {
        let available = vec!["de".to_string(), "fr".to_string(), "pt-BR".to_string()];
        assert_eq!(choose(&available, &["fr-CA".into()]), "fr");
        assert_eq!(choose(&available, &["pt-br".into()]), "pt-BR");
        assert_eq!(choose(&available, &["en-GB".into(), "fr".into()]), "en");
        assert_eq!(choose(&available, &["it".into()]), "en");
    }

    #[test]
    fn parses_like_i18n_js() {
        assert!(parse("a } b").is_err());
        assert!(parse("{count, plural, one {#}}").is_err());
        assert!(parse("{name").is_err());
        assert_eq!(names("{a} {n, plural, one {# {b}} other {{c}}}").unwrap(), vec!["a", "n", "b", "c"]);
        assert_eq!(parse("Tags: #a").unwrap(), vec![Node::Text("Tags: #a".into())]);
    }

    #[test]
    fn renders_plurals_and_selects() {
        let en = I18n::new("en".into(), Locale::try_from_str("en-US").unwrap(), HashMap::new());
        let message = "{count, plural, =0 {No files} one {# file} other {# files}}";
        assert_eq!(en.tr(message, &[("count", 0.into())]), "No files");
        assert_eq!(en.tr(message, &[("count", 1.into())]), "1 file");
        assert_eq!(en.tr(message, &[("count", 1234.into())]), "1,234 files");
        assert_eq!(en.tr("{state, select, on {On} other {Off}}", &[("state", "on".into())]), "On");
        assert_eq!(en.tr("{state, select, on {On} other {Off}}", &[("state", "x".into())]), "Off");
        assert_eq!(en.tr("Hello {name}", &[]), "Hello {name}");
        assert_eq!(en.tr("PID {pid}", &[("pid", "1234".into())]), "PID 1234");
        assert_eq!(en.markup("Run {command} & go", &[("command", Arg::code("a<b"))]),
            "Run <span font_family=\"monospace\">a&lt;b</span> &amp; go");
        let fr = I18n::new("fr".into(), Locale::try_from_str("fr").unwrap(),
            HashMap::from([("{count, plural, one {# file} other {# files}}".to_string(), "{count, plural, one {# fichier} other {# fichiers}}".to_string())]));
        assert_eq!(fr.tr("{count, plural, one {# file} other {# files}}", &[("count", 0.into())]), "0 fichier");
        assert_eq!(fr.tr("{count, plural, one {# file} other {# files}}", &[("count", 2.into())]), "2 fichiers");
    }

    #[test]
    fn parts_join_text() {
        let en = I18n::new("en".into(), Locale::try_from_str("en").unwrap(), HashMap::new());
        assert_eq!(en.parts("Also in a terminal: {command}", &[("command", "ame".into())]),
            vec![Piece::Text("Also in a terminal: ".into()), Piece::Value("command".into())]);
    }
}
