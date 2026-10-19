//! The tokenizer and the embeddings against the model's own: model-reference.jsonl holds, for a few texts,
//! the ids Hugging Face's `tokenizers` gives with the model's tokenizer.json (no special tokens) and the
//! vector Model2Vec's StaticModel.encode gives. AMETHYSTORA_MODEL is the model's folder, which the apps stage
//! downloads before the tests run (build-apps.sh); without it there is nothing to compare with.

use std::path::PathBuf;

use amethystora_agent_tools::index::embed::{Model, dot};
use serde_json::Value;

#[test]
fn tokens_and_vectors_are_the_models_own() {
    let Some(dir) = std::env::var_os("AMETHYSTORA_MODEL").map(PathBuf::from) else {
        eprintln!("AMETHYSTORA_MODEL is not set: the model is not compared");
        return;
    };
    let model = Model::load(&dir).expect("the model loads");
    let reference = include_str!("model-reference.jsonl");
    let mut count = 0;
    for line in reference.lines() {
        let case: Value = serde_json::from_str(line).unwrap();
        let text = case["text"].as_str().unwrap();
        let ids: Vec<u32> = case["ids"].as_array().unwrap().iter().map(|id| id.as_u64().unwrap() as u32).collect();
        assert_eq!(model.tokenizer.ids(text), ids, "the tokens of {text:?}");
        let want: Vec<f32> = case["vector"].as_array().unwrap().iter().map(|v| v.as_f64().unwrap() as f32).collect();
        let got = model.embed(text);
        assert_eq!(got.len(), want.len());
        let worst = got.iter().zip(&want).map(|(a, b)| (a - b).abs()).fold(0f32, f32::max);
        assert!(worst < 1e-4 && dot(&got, &want) > 0.9999, "the vector of {text:?} is off by up to {worst}");
        count += 1;
    }
    assert!(count >= 10);
}
