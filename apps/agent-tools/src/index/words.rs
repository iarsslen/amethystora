//! Words, as the word ranking counts them, and the ranking itself: BM25F over a passage's title (weight 3),
//! its commands and paths (2) and its text (1). A command or path is kept whole and also split, so that
//! `uupd-manual.service` is found by itself and by "manual". Words lose their common endings, so that
//! "updates", "updated" and "updating" are one word. A small table of aliases (aliases.tsv) bridges how
//! people say things and how the pages say them: "wifi" also looks for "network".

use std::collections::HashMap;

const STOP: &[&str] = &[
    "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "is", "are", "was", "were", "be", "been", "it", "its",
    "this", "that", "these", "those", "with", "as", "at", "by", "from", "i", "my", "me", "you", "your", "we", "our", "how",
    "do", "does", "did", "what", "why", "when", "where", "which", "who", "can", "could", "should", "would", "will", "not",
    "no", "t", "s", "won", "don", "doesn", "isn", "aren", "didn", "cannot", "if", "then", "so", "but", "there", "here",
    "has", "have", "had", "just", "any", "all", "some", "into", "out", "up", "about", "than", "too", "very", "also", "get",
    "gets", "got", "make", "makes", "want", "need", "use", "using", "one", "only", "each",
];

/// A word without its common endings: plurals, -ing and -ed
pub fn stem(word: &str) -> String {
    let chars: Vec<char> = word.chars().collect();
    let n = chars.len();
    let ends = |suffix: &str| word.ends_with(suffix);
    let cut = |count: usize| chars[..n - count].iter().collect::<String>();
    let undouble = |stem: String| {
        let c: Vec<char> = stem.chars().collect();
        if c.len() > 3 && c[c.len() - 1] == c[c.len() - 2] && !matches!(c[c.len() - 1], 'l' | 's' | 'z') {
            c[..c.len() - 1].iter().collect()
        } else {
            stem
        }
    };
    if n <= 3 || !chars.iter().all(|c| c.is_alphabetic()) {
        return word.to_string();
    }
    if ends("ies") && n > 4 {
        return format!("{}y", cut(3));
    }
    if ends("sses") {
        return cut(2);
    }
    if ends("ing") && n > 5 {
        return undouble(cut(3));
    }
    if ends("ed") && n > 4 && !ends("eed") {
        return undouble(cut(2));
    }
    if ends("s") && !ends("ss") && !ends("us") && !ends("is") {
        return cut(1);
    }
    word.to_string()
}

fn code_char(c: char) -> bool {
    c.is_alphanumeric() || matches!(c, '_' | '.' | '/' | '@' | ':' | '+' | '-' | '~')
}

/// The words of a text, for counting: code-like runs whole as well as split, words stemmed, small words out
pub fn tokens(text: &str) -> Vec<String> {
    let lower = text.to_lowercase();
    let mut out = Vec::new();
    for run in lower.split(|c: char| !code_char(c)) {
        // A path keeps its leading slash; what ends a sentence or a list goes
        let run = run.trim_end_matches(|c: char| matches!(c, '.' | ':' | '-' | '/' | '~')).trim_start_matches(|c: char| matches!(c, '.' | ':' | '-' | '~'));
        if run.is_empty() {
            continue;
        }
        let parts: Vec<&str> = run.split(|c: char| !c.is_alphanumeric()).filter(|part| !part.is_empty()).collect();
        if parts.len() > 1 && run.chars().any(|c| c.is_alphabetic()) {
            out.push(run.to_string());
        }
        for part in parts {
            if !STOP.contains(&part) {
                out.push(stem(part));
            }
        }
    }
    out
}

/// What is written as code in a passage: `spans` and fenced blocks, which count twice a word of prose
pub fn code_of(text: &str) -> String {
    let mut out = String::new();
    let mut fenced = false;
    for line in text.lines() {
        if line.trim_start().starts_with("```") {
            fenced = !fenced;
            continue;
        }
        if fenced {
            out.push_str(line);
            out.push('\n');
            continue;
        }
        for (n, piece) in line.split('`').enumerate() {
            if n % 2 == 1 {
                out.push_str(piece);
                out.push('\n');
            }
        }
    }
    out
}

/// How people say things, and the words the pages use: "phrase<TAB>words", the words added to a query that
/// holds the phrase
pub struct Aliases(Vec<(String, String)>);

impl Aliases {
    pub fn parse(text: &str) -> Aliases {
        Aliases(
            text.lines()
                .filter(|line| !line.starts_with('#') && !line.trim().is_empty())
                .filter_map(|line| line.split_once('\t'))
                .map(|(phrase, words)| (phrase.trim().to_lowercase(), words.trim().to_string()))
                .collect(),
        )
    }

    /// The query with the words its phrases stand for
    pub fn expand(&self, query: &str) -> String {
        let lower = format!(" {} ", query.to_lowercase().replace(|c: char| !c.is_alphanumeric() && c != '\'', " "));
        let mut out = query.to_string();
        for (phrase, words) in &self.0 {
            if lower.contains(&format!(" {phrase} ")) {
                out.push(' ');
                out.push_str(words);
            }
        }
        out
    }
}

const K1: f32 = 1.2;
/// Each field's weight and length normalisation: title, code, text
const FIELDS: [(f32, f32); 3] = [(3.0, 0.4), (2.0, 0.6), (1.0, 0.75)];

/// The counts BM25F ranks with, made once when the index loads
pub struct Bm25 {
    /// For each passage, each field's term counts and length
    docs: Vec<[(HashMap<String, u32>, f32); 3]>,
    average: [f32; 3],
    frequency: HashMap<String, u32>,
}

impl Bm25 {
    /// From each passage's title, code and text
    pub fn new(fields: impl Iterator<Item = [String; 3]>) -> Bm25 {
        let mut docs = Vec::new();
        let mut total = [0f32; 3];
        let mut frequency: HashMap<String, u32> = HashMap::new();
        for passage in fields {
            let counted: [(HashMap<String, u32>, f32); 3] = std::array::from_fn(|f| {
                let words = tokens(&passage[f]);
                let mut counts = HashMap::new();
                for word in &words {
                    *counts.entry(word.clone()).or_insert(0) += 1;
                }
                (counts, words.len() as f32)
            });
            let mut seen: Vec<&String> = counted.iter().flat_map(|(counts, _)| counts.keys()).collect();
            seen.sort();
            seen.dedup();
            for word in seen {
                *frequency.entry(word.clone()).or_insert(0) += 1;
            }
            for f in 0..3 {
                total[f] += counted[f].1;
            }
            docs.push(counted);
        }
        let n = docs.len().max(1) as f32;
        Bm25 { average: total.map(|sum| (sum / n).max(1.0)), docs, frequency }
    }

    /// Every passage with a score above nothing, best first, as (index, score)
    pub fn rank(&self, query: &str) -> Vec<(usize, f32)> {
        let mut words = tokens(query);
        words.sort();
        words.dedup();
        let n = self.docs.len() as f32;
        let mut scores: Vec<(usize, f32)> = Vec::new();
        for (index, fields) in self.docs.iter().enumerate() {
            let mut score = 0.0;
            for word in &words {
                let Some(&df) = self.frequency.get(word) else { continue };
                let idf = (1.0 + (n - df as f32 + 0.5) / (df as f32 + 0.5)).ln();
                let mut tf = 0.0;
                for (f, (counts, length)) in fields.iter().enumerate() {
                    if let Some(&count) = counts.get(word) {
                        let (weight, b) = FIELDS[f];
                        tf += weight * count as f32 / (1.0 - b + b * length / self.average[f]);
                    }
                }
                if tf > 0.0 {
                    score += idf * tf / (K1 + tf);
                }
            }
            if score > 0.0 {
                scores.push((index, score));
            }
        }
        scores.sort_by(|a, b| b.1.total_cmp(&a.1));
        scores
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stems_and_keeps_code_whole() {
        assert_eq!(stem("updates"), "update");
        assert_eq!(stem("running"), "run");
        assert_eq!(stem("failed"), "fail");
        assert_eq!(stem("libraries"), "library");
        assert_eq!(stem("status"), "status");
        assert_eq!(stem("access"), "access");
        let words = tokens("Restart `uupd-manual.service` and read /etc/flatpak/overrides/global.");
        for word in ["uupd-manual.service", "uupd", "manual", "service", "/etc/flatpak/overrides/global", "flatpak", "override", "global", "restart", "read"] {
            assert!(words.contains(&word.to_string()), "{word} in {words:?}");
        }
        assert!(!words.contains(&"and".to_string()));
        assert_eq!(code_of("Run `ame update`.\n```\nflatpak list\n```\n"), "ame update\nflatpak list\n");
    }

    #[test]
    fn aliases_add_the_pages_words() {
        let aliases = Aliases::parse("# comment\nwifi\tnetwork wireless\nwon't open\tstart crash\n");
        assert_eq!(aliases.expand("WiFi drops"), "WiFi drops network wireless");
        assert_eq!(aliases.expand("the app won't open"), "the app won't open start crash");
        assert_eq!(aliases.expand("wifinder"), "wifinder");
    }

    #[test]
    fn ranks_titles_above_text() {
        let fields = vec![
            ["Sound".to_string(), String::new(), "Nothing about networks here.".to_string()],
            ["Networks".to_string(), "nmcli".to_string(), "Wi-Fi and wired networks.".to_string()],
            ["Other".to_string(), String::new(), "A network is mentioned once.".to_string()],
        ];
        let bm25 = Bm25::new(fields.into_iter());
        let ranked = bm25.rank("network");
        assert_eq!(ranked[0].0, 1);
        assert_eq!(ranked.len(), 3);
        assert!(bm25.rank("nothingatall").is_empty());
    }
}
