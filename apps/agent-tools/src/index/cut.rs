//! Passages from Markdown: a page cut at its `##` and `###` headings, each piece at most about 300 tokens
//! (split again at paragraphs when longer). A passage's id is the page's source and the heading's id, which
//! is the id the Manual gives the heading, so that an id is also a link (`manual/updates#rolling-back`).
//! What comes before the first heading has the page's own id; the second and later parts of a long section
//! add `~2`, `~3`.

use super::Passage;

/// About 300 tokens, at about four characters a token
pub const MAX_CHARS: usize = 1200;

/// The id the Manual gives a heading, from the heading's text as it shows it (apps/common's markdown::slug)
pub fn slug(text: &str) -> String {
    let mut out = String::new();
    let mut dash = false;
    for c in plain(text).chars().filter(|c| !matches!(c, '&' | '<' | '>' | '"' | '\'')).flat_map(char::to_lowercase) {
        if c.is_alphanumeric() {
            if dash && !out.is_empty() {
                out.push('-');
            }
            dash = false;
            out.push(c);
        } else {
            dash = true;
        }
    }
    out
}

/// A heading's text as shown: without code marks, emphasis, link targets or entities
pub fn plain(text: &str) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(c) = rest.chars().next() {
        if c == '[' {
            // [words](target): the words
            if let Some(close) = rest.find("](") {
                if let Some(end) = rest[close..].find(')') {
                    out.push_str(&rest[1..close]);
                    rest = &rest[close + end + 1..];
                    continue;
                }
            }
        }
        if c == '&' {
            if let Some(end) = rest.find(';').filter(|end| *end <= 8 && rest[1..*end].chars().all(|c| c.is_ascii_alphanumeric() || c == '#')) {
                rest = &rest[end + 1..];
                continue;
            }
        }
        if !matches!(c, '`' | '*') {
            out.push(c);
        }
        rest = &rest[c.len_utf8()..];
    }
    out
}

struct Section {
    anchor: Option<String>,
    trail: Vec<String>,
    body: Vec<String>,
}

/// The passages of one page. `source` is the id's first part (`manual/updates`), `kind` what it is, and
/// `path` the file it came from.
pub fn cut(source: &str, kind: &str, path: &str, markdown: &str) -> Vec<Passage> {
    let mut text = markdown.replace("\r\n", "\n");
    // A skill's front matter: its description is said in its first passage
    let mut description = None;
    if let Some(rest) = text.strip_prefix("---\n") {
        if let Some(end) = rest.find("\n---\n") {
            description = rest[..end].lines().find_map(|line| line.strip_prefix("description: ")).map(str::to_string);
            text = rest[end + 5..].to_string();
        }
    }
    let mut title = String::new();
    let mut sections = vec![Section { anchor: None, trail: Vec::new(), body: Vec::new() }];
    let mut h2 = String::new();
    let mut fenced = false;
    for line in text.lines() {
        if line.trim_start().starts_with("```") {
            fenced = !fenced;
        }
        if !fenced {
            if let Some(heading) = line.strip_prefix("# ") {
                if title.is_empty() {
                    title = plain(heading.trim());
                    continue;
                }
            }
            let level = if line.starts_with("## ") { 2 } else if line.starts_with("### ") { 3 } else { 0 };
            if level > 0 {
                let heading = plain(line[level + 1..].trim());
                let trail = if level == 2 {
                    h2 = heading.clone();
                    vec![heading.clone()]
                } else if h2.is_empty() {
                    vec![heading.clone()]
                } else {
                    vec![h2.clone(), heading.clone()]
                };
                sections.push(Section { anchor: Some(slug(line[level + 1..].trim())), trail, body: Vec::new() });
                continue;
            }
        }
        sections.last_mut().expect("one at least").body.push(line.to_string());
    }
    if let Some(description) = description {
        sections[0].body.insert(0, description);
    }
    let mut passages = Vec::new();
    for section in sections {
        let body = section.body.join("\n").trim().to_string();
        if body.is_empty() {
            continue;
        }
        let id = match &section.anchor {
            Some(anchor) => format!("{source}#{anchor}"),
            None => source.to_string(),
        };
        let mut breadcrumb = vec![if title.is_empty() { source.to_string() } else { title.clone() }];
        breadcrumb.extend(section.trail.iter().cloned());
        let title = breadcrumb.join(" › ");
        for (n, part) in split(&body).into_iter().enumerate() {
            let id = if n == 0 { id.clone() } else { format!("{id}~{}", n + 1) };
            passages.push(Passage { id, title: title.clone(), kind: kind.to_string(), path: path.to_string(), text: part });
        }
    }
    passages
}

/// A section's text in pieces of at most MAX_CHARS, cut between paragraphs (never inside a code block), or
/// between lines when one paragraph is longer than that
pub fn split(body: &str) -> Vec<String> {
    if body.len() <= MAX_CHARS {
        return vec![body.to_string()];
    }
    // Paragraphs, a code block kept whole with what it is in
    let mut paragraphs: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut fenced = false;
    for line in body.lines() {
        if line.trim_start().starts_with("```") {
            fenced = !fenced;
        }
        if line.trim().is_empty() && !fenced {
            if !current.is_empty() {
                paragraphs.push(std::mem::take(&mut current));
            }
            continue;
        }
        if !current.is_empty() {
            current.push('\n');
        }
        current.push_str(line);
    }
    if !current.is_empty() {
        paragraphs.push(current);
    }
    let mut parts: Vec<String> = Vec::new();
    let mut part = String::new();
    for paragraph in paragraphs {
        let pieces: Vec<String> = if paragraph.len() > MAX_CHARS { by_lines(&paragraph) } else { vec![paragraph] };
        for piece in pieces {
            if !part.is_empty() && part.len() + piece.len() + 2 > MAX_CHARS {
                parts.push(std::mem::take(&mut part));
            }
            if !part.is_empty() {
                part.push_str("\n\n");
            }
            part.push_str(&piece);
        }
    }
    if !part.is_empty() {
        parts.push(part);
    }
    parts
}

fn by_lines(paragraph: &str) -> Vec<String> {
    let mut pieces = Vec::new();
    let mut piece = String::new();
    for line in paragraph.lines() {
        if !piece.is_empty() && piece.len() + line.len() + 1 > MAX_CHARS {
            pieces.push(std::mem::take(&mut piece));
        }
        if !piece.is_empty() {
            piece.push('\n');
        }
        piece.push_str(line);
    }
    if !piece.is_empty() {
        pieces.push(piece);
    }
    pieces
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_the_manuals_own() {
        assert_eq!(slug("Rolling back"), "rolling-back");
        assert_eq!(slug("Don't panic & relax"), "dont-panic-relax");
        assert_eq!(slug("The `ame` command"), "the-ame-command");
        assert_eq!(slug("Été — déjà vu"), "été-déjà-vu");
        assert_eq!(slug("  Spaces, then 1.2!  "), "spaces-then-1-2");
        assert_eq!(slug("[Widgets](widgets.md) and **more**"), "widgets-and-more");
    }

    #[test]
    fn cuts_at_headings() {
        let page = "# Updates\n\nIntro text.\n\n## Rolling back\n\nUse `rpm-ostree rollback`.\n\n### On a sealed image\n\nbootc.\n\n## Empty\n\n## Code\n\n```\n## not a heading\n```\n";
        let passages = cut("manual/updates", "manual", "/m/updates.md", page);
        let ids: Vec<&str> = passages.iter().map(|p| p.id.as_str()).collect();
        assert_eq!(ids, ["manual/updates", "manual/updates#rolling-back", "manual/updates#on-a-sealed-image", "manual/updates#code"]);
        assert_eq!(passages[2].title, "Updates › Rolling back › On a sealed image");
        assert!(passages[3].text.contains("## not a heading"));
    }

    #[test]
    fn long_sections_split_at_paragraphs() {
        let paragraph = "word ".repeat(100);
        let body = format!("## Long\n\n{paragraph}\n\n{paragraph}\n\n{paragraph}\n");
        let passages = cut("x", "manual", "", &format!("# T\n\n{body}"));
        assert!(passages.len() >= 2);
        assert_eq!(passages[1].id, "x#long~2");
        assert!(passages.iter().all(|p| p.text.len() <= MAX_CHARS));
        let skill = "---\nname: s\ndescription: Does a thing.\n---\n\n# S\n\nBody.\n";
        assert!(cut("skill/s", "skill", "", skill)[0].text.starts_with("Does a thing."));
    }
}
