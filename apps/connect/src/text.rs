//! Words: the program's own, through gettext, and a phone's, which are somebody else's text.
//!
//! Everything a person reads that this program wrote goes through `tr` or `trf` (text domain `amethystora`,
//! the catalogs of the shell programs). Everything a phone wrote goes through `clean` before it is shown,
//! stored or passed on, and through `escape_markup` before a notification server may read it as markup.

use std::path::{Path, PathBuf};

use crate::limits;

/// The program's own sentence in the person's language. The English is the key, as in the shell programs.
pub fn tr(msgid: &str) -> String {
    glib::dgettext(Some("amethystora"), msgid).to_string()
}

/// `tr` with `{name}` placeholders filled in. A value is put in as it is, once: a `{` inside a value is not read
/// as another placeholder.
pub fn trf(msgid: &str, values: &[(&str, &str)]) -> String {
    fill(&tr(msgid), values)
}

fn fill(template: &str, values: &[(&str, &str)]) -> String {
    let mut out = String::with_capacity(template.len() + 16);
    let mut rest = template;
    while let Some(open) = rest.find('{') {
        out.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        match after.find('}') {
            Some(close) => match values.iter().find(|(name, _)| *name == &after[..close]) {
                Some((_, value)) => {
                    out.push_str(value);
                    rest = &after[close + 1..];
                }
                None => {
                    out.push('{');
                    rest = after;
                }
            },
            None => {
                out.push('{');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

fn is_hidden_control(c: char) -> bool {
    match c {
        '\n' | '\t' => false,
        // Controls, and the bidirectional overrides and isolates that make text read as something else
        c if c.is_control() => true,
        '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}' | '\u{200E}' | '\u{200F}' | '\u{061C}' => true,
        // Zero-width space, word joiner and the byte order mark. The joiner and non-joiner stay: emoji
        // sequences and several scripts need them
        '\u{200B}' | '\u{2060}' | '\u{FEFF}' => true,
        // The line and paragraph separators, and the tag characters (invisible text)
        '\u{2028}' | '\u{2029}' | '\u{E0000}'..='\u{E007F}' => true,
        _ => false,
    }
}

/// A phone's text as it may be shown: no control characters but the line feed and the tab, no bidirectional
/// overrides, no zero-width characters
pub fn clean(text: &str) -> String {
    text.chars().filter(|c| !is_hidden_control(*c)).collect()
}

/// The same, on one line: line feeds and tabs become spaces
pub fn clean_line(text: &str) -> String {
    clean(text).replace(['\n', '\t'], " ")
}

/// At most `max` characters; a cut text ends in an ellipsis
pub fn shorten(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let mut out: String = text.chars().take(max.saturating_sub(1)).collect();
    out.push('\u{2026}');
    out
}

/// Text for a notification body that the server reads as markup: the three characters that mean something
pub fn escape_markup(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            c => out.push(c),
        }
    }
    out
}

/// A name from a phone made safe as a file name: what follows the last `/` or `\`, no control characters,
/// no leading or trailing spaces and dots, at most 255 bytes with the extension kept. Never empty, never `.`
/// or `..`.
pub fn file_name(name: &str) -> String {
    let last = name.rsplit(['/', '\\']).next().unwrap_or("");
    // The slashes of other scripts that look like the real one become underscores: a name is not to read as a path
    let cleaned: String = clean(last).chars().filter(|c| !c.is_control() && *c != '\0').map(|c| if matches!(c, '\u{FF0F}' | '\u{2215}' | '\u{2044}' | '\u{29F8}' | '\u{FF3C}') { '_' } else { c }).collect();
    let trimmed = cleaned.trim_matches(|c: char| c == ' ' || c == '.');
    if trimmed.is_empty() {
        return tr("unnamed file");
    }
    if trimmed.len() <= limits::FILE_NAME {
        return trimmed.to_string();
    }
    // Too long: cut the part before the extension, never in the middle of a character
    let (stem, extension) = match trimmed.rfind('.') {
        Some(dot) if dot > 0 && trimmed.len() - dot <= 32 => (&trimmed[..dot], &trimmed[dot..]),
        _ => (trimmed, ""),
    };
    let room = limits::FILE_NAME - extension.len();
    let mut end = room.min(stem.len());
    while !stem.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}{}", &stem[..end], extension)
}

/// `name`, or `name (1).ext`, `name (2).ext`: the number goes before the extension
pub fn numbered(name: &str, n: u32) -> String {
    if n == 0 {
        return name.to_string();
    }
    let (stem, extension) = match name.rfind('.') {
        Some(dot) if dot > 0 && name.len() - dot <= 32 => (&name[..dot], &name[dot..]),
        _ => (name, ""),
    };
    let suffix = format!(" ({n}){extension}");
    // A name that is as long as a name may be loses the end of its stem to the number, so that it can be had
    let mut end = stem.len().min(limits::FILE_NAME.saturating_sub(suffix.len()));
    while !stem.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}{suffix}", &stem[..end])
}

/// A folder name from a device name: the name has none of `/` and `.` already (the protocol forbids the dot),
/// but this does not rely on it
pub fn folder_name(name: &str) -> String {
    let cleaned: String = clean_line(name).chars().filter(|c| *c != '/' && *c != '\\').collect();
    let trimmed = cleaned.trim_matches(|c: char| c == ' ' || c == '.');
    if trimmed.is_empty() { tr("Phone") } else { shorten(trimmed, 64) }
}

/// Whether `child` is directly inside `folder`, as paths with the links resolved say
pub fn directly_in(folder: &Path, child: &Path) -> bool {
    match (folder.canonicalize(), child.parent().map(Path::canonicalize)) {
        (Ok(folder), Some(Ok(parent))) => folder == parent,
        _ => false,
    }
}

/// `$HOME`, or the account's home folder when it is not set
pub fn home() -> PathBuf {
    glib::home_dir()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn placeholders_are_filled_once() {
        assert_eq!(fill("Hello {name}, {n} new", &[("name", "{n}"), ("n", "3")]), "Hello {n}, 3 new");
        assert_eq!(fill("{unknown} {", &[]), "{unknown} {");
        assert_eq!(fill("no braces", &[]), "no braces");
    }

    #[test]
    fn cleaning_removes_what_hides_text() {
        assert_eq!(clean("a\u{0}b\u{7}c\u{202E}d\u{200B}e\u{FEFF}f\u{2066}g"), "abcdefg");
        assert_eq!(clean("line\nfeed\ttab"), "line\nfeed\ttab");
        assert_eq!(clean_line("one\ntwo\tthree"), "one two three");
        // The joiner stays: it is part of emoji sequences
        assert_eq!(clean("\u{1F468}\u{200D}\u{1F469}"), "\u{1F468}\u{200D}\u{1F469}");
        assert_eq!(clean("\u{1b}[31mred"), "[31mred");
    }

    #[test]
    fn markup_is_escaped() {
        assert_eq!(escape_markup("<b>x</b> & <a href=\"y\">"), "&lt;b&gt;x&lt;/b&gt; &amp; &lt;a href=\"y\"&gt;");
    }

    #[test]
    fn shortening_says_so() {
        assert_eq!(shorten("abcdef", 6), "abcdef");
        assert_eq!(shorten("abcdefg", 6), "abcde\u{2026}");
        assert_eq!(shorten("\u{e9}\u{e9}\u{e9}\u{e9}", 3), "\u{e9}\u{e9}\u{2026}");
    }

    #[test]
    fn file_names_cannot_leave_their_folder() {
        assert_eq!(file_name("..\\..\\.config/autostart/evil.sh"), "evil.sh");
        assert_eq!(file_name("/etc/passwd"), "passwd");
        assert_eq!(file_name("holiday photo.jpg"), "holiday photo.jpg");
        assert_eq!(file_name("  ..hidden. "), "hidden");
        assert_eq!(file_name("a\u{0}b\u{202E}c.txt"), "abc.txt");
        for bad in ["", ".", "..", "dir/", "dir\\", "...", " "] {
            let name = file_name(bad);
            assert!(!name.is_empty() && name != "." && name != ".." && !name.contains(['/', '\\']), "{bad:?} -> {name:?}");
        }
    }

    #[test]
    fn long_file_names_keep_their_extension() {
        let long = format!("{}.tar.gz", "\u{e9}".repeat(300));
        let name = file_name(&long);
        assert!(name.len() <= limits::FILE_NAME);
        assert!(name.ends_with(".gz"));
        assert!(std::str::from_utf8(name.as_bytes()).is_ok());
        let no_extension = file_name(&"x".repeat(400));
        assert_eq!(no_extension.len(), limits::FILE_NAME);
    }

    #[test]
    fn numbers_go_before_the_extension() {
        assert_eq!(numbered("report.pdf", 0), "report.pdf");
        assert_eq!(numbered("report.pdf", 2), "report (2).pdf");
        assert_eq!(numbered("archive.tar.gz", 1), "archive.tar (1).gz");
        assert_eq!(numbered("README", 1), "README (1)");
        assert_eq!(numbered(".bashrc", 1), ".bashrc (1)");
    }

    #[test]
    fn a_name_that_fills_the_limit_can_still_be_numbered() {
        let full = file_name(&format!("{}.jpg", "x".repeat(300)));
        assert_eq!(full.len(), limits::FILE_NAME);
        for n in [1, 2, 10, 12345] {
            let numbered = numbered(&full, n);
            assert!(numbered.len() <= limits::FILE_NAME, "{} bytes", numbered.len());
            assert!(numbered.ends_with(&format!(" ({n}).jpg")));
        }
        let accented = file_name(&"\u{e9}".repeat(200));
        assert!(numbered(&accented, 3).len() <= limits::FILE_NAME);
        assert!(numbered(&accented, 3).ends_with(" (3)"));
    }

    #[test]
    fn look_alikes_of_the_slash_and_hidden_text_do_not_survive() {
        assert_eq!(file_name("\u{FF0F}etc\u{FF0F}passwd"), "_etc_passwd");
        assert_eq!(file_name("a\u{2215}b"), "a_b");
        assert_eq!(clean("a\u{E0041}\u{E0042}b\u{2028}c\u{2029}d"), "abcd");
        assert_eq!(file_name("tag\u{E0061}.txt"), "tag.txt");
    }

    #[test]
    fn folder_names() {
        assert_eq!(folder_name("Sam phone"), "Sam phone");
        assert!(!folder_name("a/b\\c").contains(['/', '\\']));
        assert_eq!(folder_name(".."), "Phone");
    }
}
