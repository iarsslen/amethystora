//! The local index the `search` and `read` tools answer from: the manual, the skills, the knowledge written
//! for agents and the reference generated from the image itself, cut into passages of at most about 300
//! tokens. Two rankings are fused: words (BM25F) and meaning (a static embedding model), each list's ranks
//! joined by reciprocal rank fusion. The files are in /usr/share/amethystora/agents/knowledge, written by
//! `amethystora-agent-tools index --write` when the image is built: index.jsonl (the passages, in order),
//! vectors.f16 (one vector a passage, in half precision), meta.json, and the model under model/. Nothing is
//! kept on disk at run time, and nothing personal is ever indexed.

pub mod build;
pub mod cut;
pub mod embed;
pub mod words;

use std::path::{Path, PathBuf};

use serde_json::{Value, json};

use embed::Model;
use words::{Aliases, Bm25};

pub const DIR: &str = "/usr/share/amethystora/agents/knowledge";
/// Reciprocal rank fusion's constant, the usual one
const RRF: f32 = 60.0;
/// How many of each list take part in the fusion
const DEPTH: usize = 50;

#[derive(Debug, Clone, PartialEq)]
pub struct Passage {
    /// `source#anchor`, as the manual links: `manual/updates#rolling-back`
    pub id: String,
    /// Where it is, as a breadcrumb: "Updates › Rolling back"
    pub title: String,
    /// manual, knowledge, playbook, skill, command, helper, unit, setting or control
    pub kind: String,
    /// The file it was cut from, when there is one
    pub path: String,
    pub text: String,
}

impl Passage {
    pub fn json(&self) -> Value {
        let mut value = json!({"id": self.id, "title": self.title, "kind": self.kind, "text": self.text});
        if !self.path.is_empty() {
            value["path"] = json!(self.path);
        }
        value
    }

    pub fn from_json(value: &Value) -> Option<Passage> {
        Some(Passage {
            id: value["id"].as_str()?.to_string(),
            title: value["title"].as_str()?.to_string(),
            kind: value["kind"].as_str()?.to_string(),
            path: value["path"].as_str().unwrap_or("").to_string(),
            text: value["text"].as_str()?.to_string(),
        })
    }

    /// About how many tokens it takes, at four characters a token
    pub fn tokens(&self) -> usize {
        (self.title.len() + self.text.len()).div_ceil(4)
    }

    /// What its meaning is computed from
    pub fn embedded_text(&self) -> String {
        format!("{}\n{}", self.title, self.text)
    }
}

/// Which ranking found a passage, for measuring each against the golden set
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Ranking {
    Words,
    Meaning,
    Fused,
}

pub struct Index {
    pub passages: Vec<Passage>,
    bm25: Bm25,
    aliases: Aliases,
    vectors: Option<Vec<f32>>,
    model_dir: PathBuf,
    model: std::sync::OnceLock<Option<Model>>,
    dims: usize,
}

impl Index {
    /// The index in `dir`. Its meaning is used only when its vectors fit its passages and the model loads.
    pub fn load(dir: &Path) -> Result<Index, String> {
        let text = std::fs::read_to_string(dir.join("index.jsonl")).map_err(|error| format!("{}: {error}", dir.join("index.jsonl").display()))?;
        let passages: Vec<Passage> =
            text.lines().filter_map(|line| serde_json::from_str::<Value>(line).ok()).filter_map(|value| Passage::from_json(&value)).collect();
        let aliases = Aliases::parse(&std::fs::read_to_string(dir.join("aliases.tsv")).unwrap_or_default());
        let meta: Value = std::fs::read(dir.join("meta.json")).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or(Value::Null);
        let dims = meta["dims"].as_u64().unwrap_or(0) as usize;
        let vectors = std::fs::read(dir.join("vectors.f16"))
            .ok()
            .filter(|bytes| dims > 0 && bytes.len() == passages.len() * dims * 2)
            .map(|bytes| bytes.chunks_exact(2).map(|b| embed::from_f16(u16::from_le_bytes([b[0], b[1]]))).collect());
        Ok(Index::new(passages, aliases, vectors, dims, dir.join("model")))
    }

    pub fn new(passages: Vec<Passage>, aliases: Aliases, vectors: Option<Vec<f32>>, dims: usize, model_dir: PathBuf) -> Index {
        let bm25 = Bm25::new(passages.iter().map(|p| [p.title.clone(), words::code_of(&p.text), p.text.clone()]));
        Index { passages, bm25, aliases, vectors, model_dir, model: std::sync::OnceLock::new(), dims }
    }

    /// The model, loaded the first time meaning is asked for
    fn model(&self) -> Option<&Model> {
        self.model.get_or_init(|| Model::load(&self.model_dir).ok().filter(|model| model.dims == self.dims)).as_ref()
    }

    pub fn has_meaning(&self) -> bool {
        self.vectors.is_some() && self.model().is_some()
    }

    fn by_words(&self, query: &str) -> Vec<usize> {
        self.bm25.rank(&self.aliases.expand(query)).into_iter().map(|(index, _)| index).collect()
    }

    fn by_meaning(&self, query: &str) -> Vec<usize> {
        let (Some(vectors), Some(model)) = (&self.vectors, self.model()) else {
            return Vec::new();
        };
        let wanted = model.embed(query);
        if wanted.iter().all(|v| *v == 0.0) {
            return Vec::new();
        }
        let mut scores: Vec<(usize, f32)> =
            vectors.chunks_exact(self.dims).enumerate().map(|(index, vector)| (index, embed::dot(&wanted, vector))).collect();
        scores.sort_by(|a, b| b.1.total_cmp(&a.1));
        scores.into_iter().map(|(index, _)| index).collect()
    }

    /// The passages that answer `query` best, best first
    pub fn ranked(&self, query: &str, ranking: Ranking) -> Vec<usize> {
        match ranking {
            Ranking::Words => self.by_words(query),
            Ranking::Meaning => self.by_meaning(query),
            Ranking::Fused => {
                let words = self.by_words(query);
                let meaning = self.by_meaning(query);
                let mut scores: Vec<(usize, f32)> = Vec::new();
                for list in [&words, &meaning] {
                    for (rank, index) in list.iter().take(DEPTH).enumerate() {
                        let add = 1.0 / (RRF + rank as f32 + 1.0);
                        match scores.iter_mut().find(|(seen, _)| seen == index) {
                            Some((_, score)) => *score += add,
                            None => scores.push((*index, add)),
                        }
                    }
                }
                scores.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.cmp(&b.0)));
                scores.into_iter().map(|(index, _)| index).collect()
            }
        }
    }

    pub fn search(&self, query: &str, k: usize) -> Vec<&Passage> {
        self.ranked(query, Ranking::Fused).into_iter().take(k).map(|index| &self.passages[index]).collect()
    }

    pub fn find(&self, id: &str) -> Option<usize> {
        self.passages.iter().position(|passage| passage.id == id).or_else(|| {
            // A link to a page's heading reads that heading's first part
            let id = id.trim_start_matches('/');
            self.passages.iter().position(|passage| passage.id == id || passage.id == format!("manual/{id}"))
        })
    }

    /// Every passage of one source (`playbook/no-sound`), in order, as one text of at most `max` characters
    pub fn whole(&self, source: &str, max: usize) -> String {
        let prefix = format!("{}#", source.trim_end_matches('#'));
        let mut out = String::new();
        for passage in self.passages.iter().filter(|passage| passage.id.starts_with(&prefix)) {
            let part = format!("## {} ({})\n{}\n\n", passage.title.rsplit(" › ").next().unwrap_or(""), passage.id, passage.text);
            if out.len() + part.len() > max {
                out.push_str(&format!("(more: read {} by part)\n", passage.id));
                break;
            }
            if out.is_empty() {
                out.push_str(&format!("{}\n\n", passage.title.split(" › ").next().unwrap_or(source)));
            }
            out.push_str(&part);
        }
        out
    }

    /// One passage, with the ids before and after it in the same source
    pub fn read(&self, id: &str) -> Option<(&Passage, Option<&str>, Option<&str>)> {
        let at = self.find(id)?;
        let source = |index: usize| self.passages[index].id.split('#').next().unwrap_or("").to_string();
        let here = source(at);
        let before = at.checked_sub(1).filter(|before| source(*before) == here).map(|before| self.passages[before].id.as_str());
        let after = Some(at + 1).filter(|after| *after < self.passages.len() && source(*after) == here).map(|after| self.passages[after].id.as_str());
        Some((&self.passages[at], before, after))
    }
}

/// The first sentence or two of a passage, for a search hit: about 200 characters, cut at a word
pub fn snippet(text: &str) -> String {
    let flat: String = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with("```") && !line.starts_with('|') && !line.starts_with('#'))
        .collect::<Vec<_>>()
        .join(" ");
    let mut end = 0;
    for (at, c) in flat.char_indices() {
        if at > 220 {
            break;
        }
        end = at + c.len_utf8();
        if matches!(c, '.' | ':') && at > 40 && flat[end..].starts_with(' ') {
            return flat[..end].to_string();
        }
    }
    if end < flat.len() {
        let cut = flat[..end].rfind(' ').unwrap_or(end);
        format!("{}…", &flat[..cut])
    } else {
        flat
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn passage(id: &str, title: &str, text: &str) -> Passage {
        Passage { id: id.into(), title: title.into(), kind: "manual".into(), path: String::new(), text: text.into() }
    }

    #[test]
    fn searches_and_reads_neighbours() {
        let index = Index::new(
            vec![
                passage("manual/updates", "Updates", "Updates arrive by themselves."),
                passage("manual/updates#rolling-back", "Updates › Rolling back", "Use `rpm-ostree rollback` to go back."),
                passage("manual/sound", "Sound", "No sound? Check the output device with wpctl."),
            ],
            Aliases::parse("no sound\taudio speaker\n"),
            None,
            0,
            PathBuf::from("/nonexistent"),
        );
        assert_eq!(index.search("roll back an update", 1)[0].id, "manual/updates#rolling-back");
        assert_eq!(index.search("my audio is silent no sound", 1)[0].id, "manual/sound");
        let (passage, before, after) = index.read("manual/updates#rolling-back").unwrap();
        assert_eq!(passage.title, "Updates › Rolling back");
        assert_eq!(before, Some("manual/updates"));
        assert_eq!(after, None);
        assert_eq!(index.read("updates#rolling-back").unwrap().0.id, "manual/updates#rolling-back");
        assert!(index.read("nothing").is_none());
        assert!(!index.has_meaning());
    }

    #[test]
    fn snippets_are_short() {
        assert_eq!(snippet("Short one."), "Short one.");
        let long = "This is a sentence that goes on for quite a while, well past eighty characters. And then another one.";
        assert_eq!(snippet(long), "This is a sentence that goes on for quite a while, well past eighty characters.");
        let words = "word ".repeat(80);
        assert!(snippet(&words).ends_with('…') && snippet(&words).len() < 240);
    }
}
