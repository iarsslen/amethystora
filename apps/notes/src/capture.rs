//! The quick note (`amethystora-notes capture`, Super+Alt+N): what is typed becomes a task in the inbox. The first
//! line is read as the task box reads it (quick.rs: its title, and the dates and the rest it understands); the rest of
//! the text, trimmed, is the task's notes. The window is page/capture.rs; the text lives in its buffer only until it
//! is saved, and nowhere else.

/// The first line and the rest, each trimmed: ("first", "second") for "first\n\n second \n"
pub fn split(text: &str) -> (String, String) {
    let text = text.trim_start();
    match text.split_once('\n') {
        Some((first, rest)) => (first.trim().to_string(), rest.trim().to_string()),
        None => (text.trim().to_string(), String::new()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_line_and_the_rest() {
        assert_eq!(split("first\n\n second \n"), ("first".to_string(), "second".to_string()));
        assert_eq!(split("only"), ("only".to_string(), String::new()));
        assert_eq!(split("\n\n  late start\nmore\nlines "), ("late start".to_string(), "more\nlines".to_string()));
        assert_eq!(split("   \n  "), (String::new(), String::new()));
    }
}
