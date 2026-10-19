//! The golden questions (golden.tsv) asked of an index of the source tree's own pages: the manual, the skills
//! and the knowledge. Questions whose passage is only in the reference generated from a built image are left to
//! 20-tests.sh, which asks all of them of the image's index. The fused ranking has to find a question's passage
//! in its first three at least nine times in ten; words alone and meaning alone are reported beside it, so that
//! the fusion can be seen to earn its place.
//!
//! AMETHYSTORA_ROOT is system_files/shared (the default, from this crate), AMETHYSTORA_MODEL the model's folder.

use std::path::PathBuf;

use amethystora_agent_tools::index::build::{self, Sources};
use amethystora_agent_tools::index::{Index, Ranking};

#[test]
fn golden_questions_find_their_passage() {
    let root = std::env::var_os("AMETHYSTORA_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../system_files/shared"));
    if !root.join("usr/share/amethystora/manual").exists() {
        eprintln!("no manual under {}: the golden questions are not asked", root.display());
        return;
    }
    let out = std::env::temp_dir().join(format!("amethystora-golden-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&out);
    let model = std::env::var_os("AMETHYSTORA_MODEL").map(PathBuf::from).unwrap_or_else(|| out.join("no-model"));
    let meta = build::write(&Sources { root, generated: false }, &out, &model).expect("the index is written");
    std::os::unix::fs::symlink(&model, out.join("model")).expect("the model is linked");
    let index = Index::load(&out).expect("the index loads");
    let set = build::golden(include_str!("golden.tsv"));
    let (hits, asked, missed) = build::recall(&index, &set);
    let rate = |ranking: Ranking| hits.iter().find(|(r, _)| *r == ranking).map(|(_, n)| *n as f32 / asked.max(1) as f32).unwrap_or(0.0);
    eprintln!(
        "golden: {asked} of {} questions asked of {} passages; recall@3 words {:.2}, meaning {:.2}, fused {:.2}",
        set.len(),
        meta["passages"],
        rate(Ranking::Words),
        rate(Ranking::Meaning),
        rate(Ranking::Fused)
    );
    for miss in &missed {
        eprintln!("missed: {miss}");
    }
    let _ = std::fs::remove_dir_all(&out);
    assert!(asked >= 40, "only {asked} golden questions have their passage in the source tree");
    assert!(rate(Ranking::Fused) >= 0.9, "fused recall@3 is {:.2}", rate(Ranking::Fused));
}
