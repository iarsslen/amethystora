//! Meaning, from a static embedding model (Model2Vec's potion-base-8M, MIT): every token of its vocabulary has
//! a vector, and a text's vector is the mean of its tokens', normalised. No neural network runs: a query costs
//! a tokenizer pass and a few additions. The tokenizer is BERT's WordPiece, as the model's tokenizer.json
//! describes it, written here rather than taken from the `tokenizers` crate, and the weights are read from the
//! model's safetensors file directly. What Model2Vec does is followed exactly: no special tokens, unknown
//! tokens left out, at most 512 tokens a text, and the mean normalised.

use std::collections::HashMap;
use std::path::Path;

use icu_normalizer::DecomposingNormalizerBorrowed;
use icu_properties::props::{GeneralCategory, GeneralCategoryGroup};
use icu_properties::CodePointMapData;
use serde_json::Value;

/// The most tokens of a text that count, as Model2Vec's encode has it
const MAX_TOKENS: usize = 512;

pub struct Tokenizer {
    vocab: HashMap<String, u32>,
    unknown: Option<u32>,
    prefix: String,
    max_chars: usize,
    lowercase: bool,
}

fn chinese(c: char) -> bool {
    matches!(c as u32, 0x4E00..=0x9FFF | 0x3400..=0x4DBF | 0x20000..=0x2A6DF | 0x2A700..=0x2B73F | 0x2B740..=0x2B81F
        | 0x2B820..=0x2CEAF | 0xF900..=0xFAFF | 0x2F800..=0x2FA1F)
}

fn category(c: char) -> GeneralCategory {
    CodePointMapData::<GeneralCategory>::new().get(c)
}

/// BERT's punctuation: ASCII's symbols as well as Unicode's punctuation
fn punctuation(c: char) -> bool {
    c.is_ascii_punctuation() || GeneralCategoryGroup::Punctuation.contains(category(c))
}

fn control(c: char) -> bool {
    if matches!(c, '\t' | '\n' | '\r') {
        return false;
    }
    let group = category(c);
    GeneralCategoryGroup::Control.contains(group)
        || GeneralCategoryGroup::Format.contains(group)
        || GeneralCategoryGroup::Unassigned.contains(group)
        || GeneralCategoryGroup::PrivateUse.contains(group)
}

impl Tokenizer {
    /// From a tokenizer.json that is BERT's: a WordPiece model behind BERT's normaliser and pre-tokeniser.
    /// Anything else is refused, rather than tokenised differently from how the model was made.
    pub fn from_json(text: &str) -> Result<Tokenizer, String> {
        let json: Value = serde_json::from_str(text).map_err(|error| format!("tokenizer.json: {error}"))?;
        let model = &json["model"];
        if model["type"] != "WordPiece" || json["normalizer"]["type"] != "BertNormalizer" || json["pre_tokenizer"]["type"] != "BertPreTokenizer" {
            return Err("tokenizer.json is not BERT's WordPiece".into());
        }
        let normalizer = &json["normalizer"];
        // Accents are taken off when lowercasing, unless the normaliser says otherwise
        if normalizer["strip_accents"].as_bool().is_some_and(|strip| strip != normalizer["lowercase"].as_bool().unwrap_or(true)) {
            return Err("tokenizer.json strips accents in a way this does not".into());
        }
        let vocab: HashMap<String, u32> = model["vocab"]
            .as_object()
            .ok_or("tokenizer.json has no vocabulary")?
            .iter()
            .filter_map(|(token, id)| Some((token.clone(), u32::try_from(id.as_u64()?).ok()?)))
            .collect();
        let unknown = model["unk_token"].as_str().and_then(|token| vocab.get(token).copied());
        Ok(Tokenizer {
            unknown,
            prefix: model["continuing_subword_prefix"].as_str().unwrap_or("##").to_string(),
            max_chars: model["max_input_chars_per_word"].as_u64().unwrap_or(100) as usize,
            lowercase: normalizer["lowercase"].as_bool().unwrap_or(true),
            vocab,
        })
    }

    /// BERT's normaliser: control characters out, white space as spaces, Chinese characters apart, accents
    /// off and lower case
    fn normalise(&self, text: &str) -> String {
        let mut clean = String::with_capacity(text.len());
        for c in text.chars() {
            if c == '\0' || c == '\u{fffd}' || control(c) {
                continue;
            }
            if c.is_whitespace() {
                clean.push(' ');
            } else if chinese(c) {
                clean.push(' ');
                clean.push(c);
                clean.push(' ');
            } else {
                clean.push(c);
            }
        }
        if !self.lowercase {
            return clean;
        }
        let decomposed = DecomposingNormalizerBorrowed::new_nfd().normalize(&clean);
        decomposed
            .chars()
            .filter(|c| !GeneralCategoryGroup::NonspacingMark.contains(category(*c)))
            .flat_map(char::to_lowercase)
            .collect()
    }

    /// The token ids of a text, without special tokens, as many as there are
    pub fn ids(&self, text: &str) -> Vec<u32> {
        let normal = self.normalise(text);
        let mut ids = Vec::new();
        for word in normal.split_whitespace() {
            // Each punctuation character is a word of its own
            let mut start = 0;
            for (at, c) in word.char_indices() {
                if punctuation(c) {
                    if start < at {
                        self.wordpiece(&word[start..at], &mut ids);
                    }
                    self.wordpiece(&word[at..at + c.len_utf8()], &mut ids);
                    start = at + c.len_utf8();
                }
            }
            if start < word.len() {
                self.wordpiece(&word[start..], &mut ids);
            }
        }
        ids
    }

    /// The longest pieces of the vocabulary, first to last; a word that cannot be cut into them is unknown
    fn wordpiece(&self, word: &str, ids: &mut Vec<u32>) {
        let chars: Vec<char> = word.chars().collect();
        if chars.len() > self.max_chars {
            ids.extend(self.unknown);
            return;
        }
        let mut pieces = Vec::new();
        let mut start = 0;
        while start < chars.len() {
            let mut end = chars.len();
            let mut found = None;
            while start < end {
                let mut piece: String = chars[start..end].iter().collect();
                if start > 0 {
                    piece.insert_str(0, &self.prefix);
                }
                if let Some(&id) = self.vocab.get(&piece) {
                    found = Some(id);
                    break;
                }
                end -= 1;
            }
            match found {
                Some(id) => pieces.push(id),
                None => {
                    ids.extend(self.unknown);
                    return;
                }
            }
            start = end;
        }
        ids.extend(pieces);
    }

    pub fn unknown(&self) -> Option<u32> {
        self.unknown
    }
}

/// The model: the tokenizer and one vector a token
pub struct Model {
    pub tokenizer: Tokenizer,
    pub dims: usize,
    weights: Vec<f32>,
    normalize: bool,
}

/// A safetensors file's one F32 tensor named `embeddings`, as rows × columns
fn embeddings(bytes: &[u8]) -> Result<(Vec<f32>, usize, usize), String> {
    let size = u64::from_le_bytes(bytes.get(..8).ok_or("model.safetensors is too short")?.try_into().expect("eight bytes")) as usize;
    let header: Value = serde_json::from_slice(bytes.get(8..8 + size).ok_or("model.safetensors has no header")?)
        .map_err(|error| format!("model.safetensors: {error}"))?;
    let tensor = &header["embeddings"];
    if tensor["dtype"] != "F32" {
        return Err("model.safetensors: embeddings are not F32".into());
    }
    let shape: Vec<usize> = tensor["shape"].as_array().ok_or("no shape")?.iter().filter_map(|n| n.as_u64().map(|n| n as usize)).collect();
    let offsets: Vec<usize> = tensor["data_offsets"].as_array().ok_or("no offsets")?.iter().filter_map(|n| n.as_u64().map(|n| n as usize)).collect();
    let [rows, columns] = shape[..] else { return Err("model.safetensors: embeddings are not a matrix".into()) };
    let [begin, end] = offsets[..] else { return Err("model.safetensors: bad offsets".into()) };
    let data = bytes.get(8 + size + begin..8 + size + end).ok_or("model.safetensors is cut short")?;
    if data.len() != rows * columns * 4 {
        return Err("model.safetensors: the embeddings' size does not match their shape".into());
    }
    let weights = data.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
    Ok((weights, rows, columns))
}

impl Model {
    /// The model in `dir`: model.safetensors, tokenizer.json and config.json, as the Hugging Face repository has
    /// them
    pub fn load(dir: &Path) -> Result<Model, String> {
        let read = |name: &str| std::fs::read(dir.join(name)).map_err(|error| format!("{}: {error}", dir.join(name).display()));
        let tokenizer = Tokenizer::from_json(&String::from_utf8_lossy(&read("tokenizer.json")?))?;
        let config: Value = serde_json::from_slice(&read("config.json")?).map_err(|error| format!("config.json: {error}"))?;
        let (weights, rows, dims) = embeddings(&read("model.safetensors")?)?;
        if tokenizer.vocab.values().any(|id| *id as usize >= rows) {
            return Err("the tokenizer names tokens the model has no vector for".into());
        }
        Ok(Model { tokenizer, dims, weights, normalize: config["normalize"].as_bool().unwrap_or(true) })
    }

    /// A text's vector: the mean of its known tokens' vectors, normalised; zeros for a text with none
    pub fn embed(&self, text: &str) -> Vec<f32> {
        let unknown = self.tokenizer.unknown();
        let ids: Vec<u32> = self.tokenizer.ids(text).into_iter().filter(|id| Some(*id) != unknown).take(MAX_TOKENS).collect();
        let mut sum = vec![0f32; self.dims];
        for id in &ids {
            let row = &self.weights[*id as usize * self.dims..(*id as usize + 1) * self.dims];
            for (total, value) in sum.iter_mut().zip(row) {
                *total += value;
            }
        }
        if ids.is_empty() {
            return sum;
        }
        let count = ids.len() as f32;
        sum.iter_mut().for_each(|value| *value /= count);
        if self.normalize {
            normalise(&mut sum);
        }
        sum
    }
}

pub fn normalise(vector: &mut [f32]) {
    let norm = vector.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm > 0.0 {
        vector.iter_mut().for_each(|v| *v /= norm);
    }
}

pub fn dot(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

/// A number in half precision, rounded to the nearest
pub fn to_f16(value: f32) -> u16 {
    let bits = value.to_bits();
    let sign = ((bits >> 16) & 0x8000) as u16;
    let exponent = ((bits >> 23) & 0xff) as i32;
    let mantissa = bits & 0x7f_ffff;
    if exponent == 0xff {
        return sign | 0x7c00 | if mantissa != 0 { 0x200 } else { 0 };
    }
    let half_exponent = exponent - 127 + 15;
    if half_exponent >= 0x1f {
        return sign | 0x7c00;
    }
    if half_exponent <= 0 {
        if half_exponent < -10 {
            return sign;
        }
        let mantissa = mantissa | 0x80_0000;
        let shift = (14 - half_exponent) as u32;
        let mut half = (mantissa >> shift) as u16;
        let rest = mantissa & ((1 << shift) - 1);
        let middle = 1 << (shift - 1);
        if rest > middle || (rest == middle && half & 1 == 1) {
            half += 1;
        }
        return sign | half;
    }
    let mut half = ((half_exponent as u32) << 10 | (mantissa >> 13)) as u16;
    let rest = mantissa & 0x1fff;
    if rest > 0x1000 || (rest == 0x1000 && half & 1 == 1) {
        half += 1;
    }
    sign | half
}

pub fn from_f16(half: u16) -> f32 {
    let sign = ((half & 0x8000) as u32) << 16;
    let exponent = ((half >> 10) & 0x1f) as u32;
    let mantissa = (half & 0x3ff) as u32;
    let bits = match (exponent, mantissa) {
        (0, 0) => sign,
        (0, _) => {
            // Subnormal: shift until the leading one is found
            let mut e = 127 - 15 + 1;
            let mut m = mantissa;
            while m & 0x400 == 0 {
                m <<= 1;
                e -= 1;
            }
            sign | (e << 23) | ((m & 0x3ff) << 13)
        }
        (0x1f, 0) => sign | 0x7f80_0000,
        (0x1f, _) => sign | 0x7fc0_0000,
        _ => sign | ((exponent + 127 - 15) << 23) | (mantissa << 13),
    };
    f32::from_bits(bits)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tokenizer() -> Tokenizer {
        let vocab = ["[PAD]", "[UNK]", "the", "update", "##s", "fail", "##ed", "!", "cafe", "un", "##known", "/", "etc"];
        let json = serde_json::json!({
            "normalizer": {"type": "BertNormalizer", "clean_text": true, "handle_chinese_chars": true, "strip_accents": null, "lowercase": true},
            "pre_tokenizer": {"type": "BertPreTokenizer"},
            "model": {"type": "WordPiece", "unk_token": "[UNK]", "continuing_subword_prefix": "##", "max_input_chars_per_word": 100,
                "vocab": vocab.iter().enumerate().map(|(i, t)| (t.to_string(), serde_json::json!(i))).collect::<serde_json::Map<String, Value>>()}
        });
        Tokenizer::from_json(&json.to_string()).unwrap()
    }

    #[test]
    fn tokenizes_as_bert_does() {
        let t = tokenizer();
        assert_eq!(t.ids("The UPDATES failed!"), [2, 3, 4, 5, 6, 7]);
        // Accents off, a word it cannot cut is one unknown token, and punctuation splits
        assert_eq!(t.ids("Café unknownx /etc"), [8, 1, 11, 12]);
        assert_eq!(t.ids("\u{1}the\u{200b}"), [2]);
        assert!(Tokenizer::from_json("{\"model\": {\"type\": \"BPE\"}}").is_err());
    }

    #[test]
    fn half_precision_round_trips() {
        for value in [0.0f32, 1.0, -1.0, 0.5, 0.333_333, 65504.0, 1e-5, -2.5e-7, 0.099_98] {
            let back = from_f16(to_f16(value));
            assert!((back - value).abs() <= value.abs() * 1e-3 + 6e-8, "{value} {back}");
        }
        assert_eq!(to_f16(1.0), 0x3c00);
        assert_eq!(to_f16(f32::INFINITY), 0x7c00);
        assert!(from_f16(to_f16(f32::NAN)).is_nan());
    }
}
