//! What the shelf holds, as plain data, and the drop the shell hands over on the standard input: the parts here have
//! no GTK, so that they are tried by `cargo test` alone.
//!
//! The hand-off (plans/beyond/spec-r4-shelf.md, R4-08 section 2) is one line of JSON, then the bytes of each picture
//! it names, in order:
//!
//! ```text
//! {"items": [{"kind": "files", "uris": ["file:///..."]}, {"kind": "text", "text": "..."},
//!            {"kind": "picture", "mime": "image/png", "length": N}]}\n<N bytes>
//! ```
//!
//! Anything else is refused whole: a drop is what one person let go of, and half of it would be a surprise.

use serde_json::Value;

// The limits, the same for a drop the shell hands over and one made on the window; the shell's module reads at most
// MOST_TEXT and MOST_PICTURE too (shelf/drop.js; 20-tests.sh holds the two to the same numbers)
/// The most things the shelf holds
pub const MOST_ITEMS: usize = 32;
/// The most bytes of a dropped list of files or piece of text (UTF-8)
pub const MOST_TEXT: usize = 1 << 20;
/// The most bytes one dropped picture may be, and the most pixels it may have once decoded (64 MP, 256 MB)
pub const MOST_PICTURE: usize = 32 << 20;
pub const MOST_PIXELS: u64 = 64_000_000;
/// The most the JSON line may be: the shell's most text, every character of it escaped as JSON does a control
/// character (\u0000, six bytes), and room for the rest
pub const MOST_HEADER: usize = 6 * MOST_TEXT + 4096;
/// The most the whole hand-off may be: the line and one picture
pub const MOST_HANDOFF: usize = MOST_HEADER + MOST_PICTURE;
/// The characters of a piece of text its name shows before the ellipsis
const NAME_CHARS: usize = 14;

/// One thing in a drop
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Incoming {
    /// A file of this computer, by its URI
    File(String),
    Text(String),
    /// A PNG picture's bytes
    Picture(Vec<u8>),
}

/// Whether a URI names a file of this computer: GIO would keep the path of another host's address, which would name a
/// file here that the address did not
pub fn is_local_uri(uri: &str) -> bool {
    let lower = uri.get(..17).unwrap_or(uri).to_ascii_lowercase();
    (lower.starts_with("file:///") || lower.starts_with("file://localhost/"))
        && !uri.chars().any(|c| c.is_control())
}

/// The drop the shell handed over, or why it was refused
pub fn parse_handoff(bytes: &[u8]) -> Result<Vec<Incoming>, String> {
    if bytes.len() > MOST_HANDOFF {
        return Err("too large".into());
    }
    let end = bytes.iter().position(|&b| b == b'\n').ok_or("no line")?;
    if end > MOST_HEADER {
        return Err("the line is too long".into());
    }
    let header: Value = serde_json::from_slice(&bytes[..end]).map_err(|e| format!("not JSON: {e}"))?;
    let items = header.get("items").and_then(Value::as_array).ok_or("no items")?;
    let mut rest = &bytes[end + 1..];
    let mut out = Vec::new();
    for item in items {
        match item.get("kind").and_then(Value::as_str) {
            Some("files") => {
                let uris = item.get("uris").and_then(Value::as_array).ok_or("files without uris")?;
                for uri in uris {
                    let uri = uri.as_str().ok_or("a uri that is not text")?;
                    if !is_local_uri(uri) {
                        return Err("a file of another computer".into());
                    }
                    out.push(Incoming::File(uri.to_string()));
                }
            }
            Some("text") => {
                let text = item.get("text").and_then(Value::as_str).ok_or("text without text")?;
                if text.len() > MOST_TEXT {
                    return Err("too much text".into());
                }
                if text.trim().is_empty() {
                    return Err("empty text".into());
                }
                out.push(Incoming::Text(text.to_string()));
            }
            Some("picture") => {
                if item.get("mime").and_then(Value::as_str) != Some("image/png") {
                    return Err("a picture that is not PNG".into());
                }
                let length = item.get("length").and_then(Value::as_u64).ok_or("a picture without its length")? as usize;
                if length == 0 || length > MOST_PICTURE || length > rest.len() {
                    return Err("a picture of the wrong length".into());
                }
                if !picture_ok(&rest[..length]) {
                    return Err("a picture too large to hold".into());
                }
                out.push(Incoming::Picture(rest[..length].to_vec()));
                rest = &rest[length..];
            }
            _ => return Err("something the shelf does not hold".into()),
        }
    }
    if !rest.is_empty() {
        return Err("bytes after the pictures".into());
    }
    if out.is_empty() {
        return Err("nothing in it".into());
    }
    Ok(out)
}

/// A PNG's width and height, from its header, before anything is decoded
pub fn png_size(bytes: &[u8]) -> Option<(u32, u32)> {
    if bytes.len() < 24 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" || &bytes[12..16] != b"IHDR" {
        return None;
    }
    let number = |at: usize| u32::from_be_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]);
    Some((number(16), number(20)))
}

/// Whether a picture is a PNG the shelf may decode: within its bytes and its pixels
pub fn picture_ok(bytes: &[u8]) -> bool {
    bytes.len() <= MOST_PICTURE
        && png_size(bytes).is_some_and(|(w, h)| w > 0 && h > 0 && u64::from(w) * u64::from(h) <= MOST_PIXELS)
}

/// The files of this computer a text/uri-list names, in order, each once
pub fn local_uris(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for line in text.lines().map(str::trim) {
        if !line.is_empty() && !line.starts_with('#') && is_local_uri(line) && !out.iter().any(|u| u == line) {
            out.push(line.to_string());
        }
    }
    out
}

/// A piece of text as the shelf names it: its first words in curly quotes, on one line, with an ellipsis when cut
pub fn text_name(text: &str) -> String {
    let words: Vec<&str> = text.split_whitespace().collect();
    let flat: String = words.join(" ").chars().filter(|c| !c.is_control()).collect();
    let mut chars = flat.chars();
    let head: String = chars.by_ref().take(NAME_CHARS).collect();
    if chars.next().is_some() {
        format!("\u{201c}{}\u{2026}\u{201d}", head.trim_end())
    } else {
        format!("\u{201c}{head}\u{201d}")
    }
}

/// How many of `incoming` fit beside `held` things
pub fn room(held: usize, incoming: usize) -> usize {
    incoming.min(MOST_ITEMS.saturating_sub(held))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn handoff(header: &str, pictures: &[&[u8]]) -> Vec<u8> {
        let mut bytes = header.as_bytes().to_vec();
        bytes.push(b'\n');
        for picture in pictures {
            bytes.extend_from_slice(picture);
        }
        bytes
    }

    /// The start of a PNG of that size: what the shelf reads before it decodes anything
    fn png(width: u32, height: u32) -> Vec<u8> {
        let mut bytes = b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR".to_vec();
        bytes.extend_from_slice(&width.to_be_bytes());
        bytes.extend_from_slice(&height.to_be_bytes());
        bytes
    }

    #[test]
    fn takes_files_text_and_pictures_in_order() {
        let picture = png(120, 80);
        let bytes = handoff(
            &r#"{"items": [{"kind": "files", "uris": ["file:///home/a/b.jpg", "file://localhost/tmp/c"]},
                {"kind": "text", "text": "Flight LH 1173 leaves at 9"},
                {"kind": "picture", "mime": "image/png", "length": 24}]}"#.replace('\n', " "),
            &[&picture],
        );
        assert_eq!(
            parse_handoff(&bytes).unwrap(),
            vec![
                Incoming::File("file:///home/a/b.jpg".into()),
                Incoming::File("file://localhost/tmp/c".into()),
                Incoming::Text("Flight LH 1173 leaves at 9".into()),
                Incoming::Picture(picture.clone()),
            ]
        );
    }

    #[test]
    fn refuses_what_is_not_a_drop() {
        for header in [
            r#"{"items": [{"kind": "files", "uris": ["https://example.org/a"]}]}"#,
            r#"{"items": [{"kind": "files", "uris": ["file://elsewhere/a"]}]}"#,
            r#"{"items": [{"kind": "files", "uris": ["file:///a\u0007"]}]}"#,
            r#"{"items": [{"kind": "text", "text": "   "}]}"#,
            r#"{"items": [{"kind": "run", "argv": ["sh"]}]}"#,
            r#"{"items": []}"#,
            r#"{"things": []}"#,
            r#"not json"#,
        ] {
            assert!(parse_handoff(&handoff(header, &[])).is_err(), "{header}");
        }
        // No line at all
        assert!(parse_handoff(br#"{"items": []}"#).is_err());
    }

    #[test]
    fn pictures_are_counted_exactly() {
        let picture = png(10, 10);
        let one = r#"{"items": [{"kind": "picture", "mime": "image/png", "length": 24}]}"#;
        assert!(parse_handoff(&handoff(one, &[&picture[..23]])).is_err(), "short");
        assert!(parse_handoff(&handoff(one, &[&picture, b"x"])).is_err(), "bytes left over");
        assert!(parse_handoff(&handoff(one, &[&picture])).is_ok());
        let jpeg = r#"{"items": [{"kind": "picture", "mime": "image/jpeg", "length": 24}]}"#;
        assert!(parse_handoff(&handoff(jpeg, &[&picture])).is_err());
        // A few bytes that would decode to more pixels than the shelf holds, and bytes that are no PNG
        assert!(parse_handoff(&handoff(one, &[&png(20000, 20000)])).is_err(), "too many pixels");
        assert!(parse_handoff(&handoff(one, &[&[b'x'; 24]])).is_err(), "not a PNG");
        let huge = format!(r#"{{"items": [{{"kind": "picture", "mime": "image/png", "length": {}}}]}}"#, MOST_PICTURE + 1);
        assert!(parse_handoff(&handoff(&huge, &[])).is_err());
    }

    #[test]
    fn text_is_limited() {
        let text = "x".repeat(MOST_TEXT + 1);
        let header = serde_json::json!({"items": [{"kind": "text", "text": text}]}).to_string();
        assert!(parse_handoff(&handoff(&header, &[])).is_err());
    }

    #[test]
    fn names_text_by_its_first_words() {
        assert_eq!(text_name("Flight LH 1173\nleaves at 9"), "\u{201c}Flight LH 1173\u{2026}\u{201d}");
        assert_eq!(text_name("  short  "), "\u{201c}short\u{201d}");
        assert_eq!(text_name("a\u{0}b"), "\u{201c}ab\u{201d}");
    }

    #[test]
    fn local_uris_only() {
        assert!(is_local_uri("file:///x"));
        assert!(is_local_uri("FILE:///x"));
        assert!(!is_local_uri("file://host/x"));
        assert!(!is_local_uri("smb://x/y"));
    }

    #[test]
    fn reads_a_uri_list_as_files_of_this_computer() {
        assert_eq!(
            local_uris("# a comment\r\nfile:///a/b\r\nhttps://x/y\r\nfile:///a/b\r\n\r\nfile://localhost/c\n"),
            vec!["file:///a/b".to_string(), "file://localhost/c".to_string()]
        );
    }

    #[test]
    fn keeps_to_the_most() {
        assert_eq!(room(0, 5), 5);
        assert_eq!(room(30, 5), 2);
        assert_eq!(room(MOST_ITEMS, 1), 0);
    }
}
