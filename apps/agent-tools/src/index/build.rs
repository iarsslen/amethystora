//! `amethystora-agent-tools index --write DIR`: the index, written once when the image is built, after
//! 07-debrand.sh has given everything its final name. It cuts the manual (English) and keybindings.md, the
//! skills and their references, and the knowledge written for agents into passages, and adds a reference
//! generated from the image itself, so that it is right by construction: every `ame` command (just's own
//! dump of the recipes), the header of every Amethystora helper, every Amethystora unit with what starts it
//! and whether the image enables it, the security switches with their values, and Control's entries.
//!
//! Nothing about the duress finger or password goes in: no passage that names it.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde_json::{Value, json};

use super::cut::{cut, slug, split};
use super::embed::{self, Model};
use super::{Index, Passage, Ranking};
use crate::run;

/// What to read, and from where
pub struct Sources {
    /// The tree the image's files are under: / in the build, system_files/shared for a test
    pub root: PathBuf,
    /// Add the reference made from the running image: its commands, helpers, units and settings
    pub generated: bool,
}

impl Sources {
    fn path(&self, path: &str) -> PathBuf {
        self.root.join(path.trim_start_matches('/'))
    }
}

fn markdown(passages: &mut Vec<Passage>, source: &str, kind: &str, path: &Path) {
    if let Ok(text) = std::fs::read_to_string(path) {
        passages.extend(cut(source, kind, &path.to_string_lossy(), &text));
    }
}

fn sorted(dir: &Path, extension: &str) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .map(|entries| entries.filter_map(|entry| entry.ok().map(|entry| entry.path())).collect())
        .unwrap_or_default();
    files.retain(|path| path.is_file() && path.extension().is_some_and(|e| e == extension));
    files.sort();
    files
}

fn stem(path: &Path) -> String {
    path.file_stem().map(|stem| stem.to_string_lossy().into_owned()).unwrap_or_default()
}

/// The pages written for people and agents: the manual, the skills, the knowledge and its playbooks
pub fn written(sources: &Sources) -> Vec<Passage> {
    let mut passages = Vec::new();
    for path in sorted(&sources.path("/usr/share/amethystora/manual"), "md") {
        markdown(&mut passages, &format!("manual/{}", stem(&path)), "manual", &path);
    }
    markdown(&mut passages, "manual/keybindings", "manual", &sources.path("/usr/share/amethystora/keybindings.md"));
    let skills = sources.path("/usr/share/amethystora/agents/skills");
    let mut names: Vec<PathBuf> = std::fs::read_dir(&skills).map(|e| e.filter_map(|e| e.ok().map(|e| e.path())).collect()).unwrap_or_default();
    names.sort();
    for dir in names.iter().filter(|dir| dir.is_dir()) {
        let name = dir.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
        markdown(&mut passages, &format!("skill/{name}"), "skill", &dir.join("SKILL.md"));
        for path in sorted(&dir.join("references"), "md") {
            markdown(&mut passages, &format!("skill/{name}/{}", stem(&path)), "skill", &path);
        }
    }
    let knowledge = sources.path(super::DIR);
    for path in sorted(&knowledge, "md") {
        markdown(&mut passages, &format!("knowledge/{}", stem(&path)), "knowledge", &path);
    }
    for path in sorted(&knowledge.join("playbooks"), "md") {
        markdown(&mut passages, &format!("playbook/{}", stem(&path)), "playbook", &path);
    }
    passages
}

fn add(passages: &mut Vec<Passage>, id: String, title: String, kind: &str, path: &str, text: &str) {
    for (n, part) in split(text.trim()).into_iter().enumerate() {
        let id = if n == 0 { id.clone() } else { format!("{id}~{}", n + 1) };
        passages.push(Passage { id, title: title.clone(), kind: kind.into(), path: path.into(), text: part });
    }
}

/// Every public `ame` command, from just's dump of the recipes, module by module
fn commands(sources: &Sources, passages: &mut Vec<Passage>) {
    let justfile = sources.path("/usr/share/amethystora/just/00-entry.just");
    let justfile = justfile.to_string_lossy();
    let output = run::run(&["just", "--justfile", &justfile, "--dump", "--dump-format", "json"], Duration::from_secs(60));
    let Ok(dump) = serde_json::from_str::<Value>(&output.stdout) else {
        eprintln!("index: just could not list the commands: {}", output.stderr.trim());
        return;
    };
    fn walk(module: &Value, path: &[String], passages: &mut Vec<Passage>) {
        let mut recipes: Vec<(&String, &Value)> = module["recipes"].as_object().map(|r| r.iter().collect()).unwrap_or_default();
        recipes.sort_by(|a, b| a.0.cmp(b.0));
        for (name, recipe) in recipes {
            if recipe["private"].as_bool().unwrap_or(false) || name.starts_with('_') {
                continue;
            }
            let mut words: Vec<String> = path.to_vec();
            words.push(name.clone());
            let parameters: Vec<String> = recipe["parameters"]
                .as_array()
                .map(|list| {
                    list.iter()
                        .map(|p| {
                            let name = p["name"].as_str().unwrap_or("ARG");
                            let more = if p["kind"] == "plus" || p["kind"] == "star" { "..." } else { "" };
                            if p["default"].is_null() && p["kind"] != "star" { format!("{name}{more}") } else { format!("[{name}{more}]") }
                        })
                        .collect()
                })
                .unwrap_or_default();
            let command = format!("ame {}", words.join(" "));
            let usage = if parameters.is_empty() { command.clone() } else { format!("{command} {}", parameters.join(" ")) };
            let doc = recipe["doc"].as_str().unwrap_or("");
            let text = format!("`{usage}`: {doc}");
            add(passages, format!("ame/{}", words.join("/")), command, "command", "", &text);
        }
        let mut modules: Vec<(&String, &Value)> = module["modules"].as_object().map(|m| m.iter().collect()).unwrap_or_default();
        modules.sort_by(|a, b| a.0.cmp(b.0));
        for (name, sub) in modules {
            let mut deeper = path.to_vec();
            deeper.push(name.clone());
            walk(sub, &deeper, passages);
        }
    }
    walk(&dump, &[], passages);
}

/// A script's header: the comment lines after its first line, up to the first line of code
pub fn header(text: &str) -> String {
    let mut out = Vec::new();
    for line in text.lines().skip(usize::from(text.starts_with("#!"))) {
        let Some(comment) = line.strip_prefix('#') else { break };
        if comment.trim_start().starts_with("shellcheck") || comment.starts_with('!') {
            continue;
        }
        out.push(comment.strip_prefix(' ').unwrap_or(comment).to_string());
    }
    out.join("\n").trim().to_string()
}

/// Every Amethystora helper that says what it does in a header
fn helpers(sources: &Sources, passages: &mut Vec<Passage>) {
    for dir in ["/usr/libexec", "/usr/bin"] {
        let mut files: Vec<PathBuf> = std::fs::read_dir(sources.path(dir)).map(|e| e.filter_map(|e| e.ok().map(|e| e.path())).collect()).unwrap_or_default();
        files.retain(|path| path.file_name().is_some_and(|name| name.to_string_lossy().starts_with("amethystora-")) || path.ends_with("ame"));
        files.sort();
        for path in files {
            let Ok(bytes) = std::fs::read(&path) else { continue };
            if !bytes.starts_with(b"#!") {
                continue;
            }
            let text = header(&String::from_utf8_lossy(&bytes));
            if text.is_empty() {
                continue;
            }
            let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            let shown = format!("{dir}/{name}");
            add(passages, format!("helper/{name}"), shown.clone(), "helper", &shown, &text);
        }
    }
}

/// One unit: what it is, what starts it and when, and whether the image enables it
fn unit_text(text: &str, enabled: Option<&str>) -> String {
    let mut comments = Vec::new();
    let mut fields: BTreeMap<&str, Vec<String>> = BTreeMap::new();
    let keys = ["Description", "ExecStart", "ExecCondition", "OnCalendar", "OnBootSec", "OnUnitActiveSec", "OnActiveSec", "PathChanged",
        "PathModified", "PathExists", "ListenStream", "User", "WantedBy", "Unit"];
    // A line that ends in a backslash goes on in the next
    let joined = text.replace("\\\n", " ");
    for line in joined.lines() {
        if let Some(comment) = line.strip_prefix('#') {
            if fields.is_empty() {
                comments.push(comment.trim().to_string());
            }
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            let value = value.split_whitespace().collect::<Vec<_>>().join(" ");
            let value = value.as_str();
            if let Some(key) = keys.iter().find(|known| **known == key.trim()) {
                fields.entry(key).or_default().push(value.trim().to_string());
            }
        }
    }
    let mut out = String::new();
    if let Some(description) = fields.get("Description") {
        out.push_str(&format!("{}.\n", description.join(" ")));
    }
    let comments = comments.join(" ").trim().to_string();
    if !comments.is_empty() {
        out.push_str(&comments);
        out.push('\n');
    }
    for (key, words) in [("ExecStart", "Runs"), ("ExecCondition", "Only while"), ("User", "As"), ("OnCalendar", "When"), ("OnBootSec", "After boot"),
        ("OnUnitActiveSec", "Every"), ("OnActiveSec", "After"), ("PathChanged", "When it changes"), ("PathModified", "When it changes"),
        ("PathExists", "When it exists"), ("ListenStream", "Listens on"), ("Unit", "Starts"), ("WantedBy", "Wanted by")]
    {
        if let Some(values) = fields.get(key) {
            out.push_str(&format!("{words}: `{}`\n", values.join("`, `")));
        }
    }
    if let Some(enabled) = enabled {
        out.push_str(&format!("The image ships it {enabled}.\n"));
    }
    out
}

fn units(sources: &Sources, passages: &mut Vec<Passage>) {
    for (dir, user) in [("/usr/lib/systemd/system", false), ("/usr/lib/systemd/user", true)] {
        let mut files: Vec<PathBuf> = std::fs::read_dir(sources.path(dir)).map(|e| e.filter_map(|e| e.ok().map(|e| e.path())).collect()).unwrap_or_default();
        files.retain(|path| path.is_file() && path.file_name().is_some_and(|name| name.to_string_lossy().starts_with("amethystora-")));
        files.sort();
        for path in files {
            let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            let Ok(text) = std::fs::read_to_string(&path) else { continue };
            let enabled = (sources.root == Path::new("/")).then(|| {
                let scope = if user { "--global" } else { "--system" };
                let state = run::run(&["systemctl", scope, "is-enabled", &name], Duration::from_secs(10)).stdout.trim().to_string();
                if state.is_empty() { "without an install state".to_string() } else { state }
            });
            let scope = if user { "user unit (systemctl --user)" } else { "system unit" };
            let shown = format!("{dir}/{name}");
            add(passages, format!("unit/{name}"), format!("{name}, {scope}"), "unit", &shown, &unit_text(&text, enabled.as_deref()));
        }
    }
}

/// The security switches: the detection ones in security.conf, and those the image enforces
fn settings(sources: &Sources, passages: &mut Vec<Passage>) {
    let config = sources.path("/usr/libexec/amethystora-security-config");
    let output = run::run(&[&config.to_string_lossy(), "--list", "--json"], Duration::from_secs(60));
    if let Ok(list) = serde_json::from_str::<Value>(&output.stdout) {
        for setting in list["settings"].as_array().into_iter().flatten() {
            let key = setting["key"].as_str().unwrap_or("");
            let values: Vec<&str> = setting["allowed"].as_array().map(|a| a.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
            let mut text = format!(
                "{} ({key} in /etc/amethystora/security.conf, group {}). Values: {}. Change it with `ame security settings {} VALUE`.",
                setting["text"].as_str().unwrap_or(""),
                setting["group"].as_str().unwrap_or(""),
                values.join(", "),
                setting["setting"].as_str().unwrap_or(""),
            );
            if setting["sends"] != "none" && setting["sends"] != "downloads" {
                text.push_str(" It sends something away from this machine, so only the user turns it on.");
            }
            add(passages, format!("setting/{key}"), format!("Security setting: {}", setting["title"].as_str().unwrap_or(key)), "setting", "", &text);
        }
    }
    let hardening = sources.path("/usr/libexec/amethystora-hardening");
    let output = run::run(&[&hardening.to_string_lossy(), "status", "--json"], Duration::from_secs(60));
    if let Ok(list) = serde_json::from_str::<Value>(&output.stdout) {
        for switch in list.as_array().into_iter().flatten() {
            let name = switch["name"].as_str().unwrap_or("");
            let text = format!(
                "{} `ame security {name} on|off` switches it; the image ships it {}.{}",
                switch["text"].as_str().unwrap_or(""),
                switch["default"].as_str().unwrap_or(""),
                switch["levels"].as_array().map(|l| format!(" Levels: {}.", l.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", "))).unwrap_or_default()
            );
            add(passages, format!("setting/{name}"), format!("Security switch: {}", switch["title"].as_str().unwrap_or(name)), "setting", "", &text);
        }
    }
}

/// Control's entries, so that "how do I change X" leads to an entry's id, which `change` takes
fn control(sources: &Sources, passages: &mut Vec<Passage>) {
    let list = sources.path(amethystora_control_core::LIST);
    let output = run::run(&[&list.to_string_lossy(), "--json"], Duration::from_secs(90));
    let Some(list) = amethystora_control_core::parse_list(&output.stdout) else {
        eprintln!("index: Control's list could not be read: {}", output.stderr.trim());
        return;
    };
    for item in &list.items {
        if item.kind == "link" {
            continue;
        }
        let mut text = item.text.clone().unwrap_or_default();
        if !item.choices.is_empty() {
            let values: Vec<String> = item.choices.iter().map(|c| format!("{} ({})", c.value, c.title)).collect();
            text.push_str(&format!("\nValues: {}.", values.join(", ")));
        }
        if let Some(usage) = &item.usage {
            text.push_str(&format!("\nIn a terminal: `{usage}`."));
        }
        text.push_str(&format!("\nThe agent's tools change it as entry `{}` (state settings shows it now).", item.id));
        if let Some(manual) = &item.manual {
            text.push_str(&format!(" The manual: {manual}."));
        }
        add(passages, format!("control/{}", item.id), format!("Control › {} › {}", item.page, item.title), "control", "", &text);
    }
}

/// Never in the index: anything that names the duress feature
fn kept(passage: &Passage) -> bool {
    let all = format!("{} {} {} {}", passage.id, passage.title, passage.path, passage.text).to_lowercase();
    !all.contains("duress")
}

/// The tools amethystora-pkg does the work of, which only the manual's software page names, once (20-tests.sh)
fn names_other_tools(text: &str) -> bool {
    static CELL: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();
    CELL.get_or_init(|| regex::Regex::new(r"(?i)\b(vanilla[ -]?os|apx|vso|sideload)\b").expect("a valid expression")).is_match(text)
}

/// A passage's text without the sentences that name them; the page itself still says it
fn unnamed(text: &str) -> String {
    if !names_other_tools(text) {
        return text.to_string();
    }
    let mut lines = Vec::new();
    for line in text.lines() {
        if !names_other_tools(line) {
            lines.push(line.to_string());
            continue;
        }
        // Its sentences, each ending at a full stop, a question or an exclamation mark before a space
        let mut kept = String::new();
        let mut sentence = String::new();
        let mut chars = line.chars().peekable();
        while let Some(c) = chars.next() {
            sentence.push(c);
            if matches!(c, '.' | '?' | '!') && chars.peek().is_none_or(|next| next.is_whitespace()) {
                if !names_other_tools(&sentence) {
                    kept.push_str(&sentence);
                }
                sentence.clear();
            }
        }
        if !names_other_tools(&sentence) {
            kept.push_str(&sentence);
        }
        let kept = kept.trim().to_string();
        if !kept.is_empty() {
            lines.push(kept);
        }
    }
    lines.join("\n").trim().to_string()
}

/// Every passage, in the order the index keeps them
pub fn passages(sources: &Sources) -> Vec<Passage> {
    let mut passages = written(sources);
    if sources.generated {
        commands(sources, &mut passages);
        helpers(sources, &mut passages);
        units(sources, &mut passages);
        settings(sources, &mut passages);
        control(sources, &mut passages);
    }
    passages.retain(kept);
    for passage in &mut passages {
        passage.text = unnamed(&passage.text);
    }
    passages.retain(|passage| !passage.text.is_empty() && !names_other_tools(&passage.title));
    // An id once: a second heading of the same name in a page keeps the first's
    let mut seen = std::collections::HashSet::new();
    passages.retain(|passage| seen.insert(passage.id.clone()));
    passages
}

/// Writes index.jsonl, vectors.f16 (when the model in `model` loads) and meta.json into `out`
pub fn write(sources: &Sources, out: &Path, model: &Path) -> Result<Value, String> {
    let passages = passages(sources);
    std::fs::create_dir_all(out).map_err(|error| format!("{}: {error}", out.display()))?;
    let mut lines = String::new();
    for passage in &passages {
        lines.push_str(&passage.json().to_string());
        lines.push('\n');
    }
    std::fs::write(out.join("index.jsonl"), lines).map_err(|error| error.to_string())?;
    // The aliases are a source file of the knowledge folder; a test writes the index elsewhere
    let aliases = sources.path(super::DIR).join("aliases.tsv");
    if aliases.exists() && aliases != out.join("aliases.tsv") {
        std::fs::copy(&aliases, out.join("aliases.tsv")).map_err(|error| error.to_string())?;
    }
    let mut dims = 0;
    match Model::load(model) {
        Ok(model) => {
            dims = model.dims;
            let mut bytes = Vec::with_capacity(passages.len() * dims * 2);
            for passage in &passages {
                for value in model.embed(&passage.embedded_text()) {
                    bytes.extend_from_slice(&embed::to_f16(value).to_le_bytes());
                }
            }
            std::fs::write(out.join("vectors.f16"), bytes).map_err(|error| error.to_string())?;
        }
        Err(error) => {
            eprintln!("index: no meaning, only words: {error}");
            let _ = std::fs::remove_file(out.join("vectors.f16"));
        }
    }
    let mut kinds: BTreeMap<String, usize> = BTreeMap::new();
    for passage in &passages {
        *kinds.entry(passage.kind.clone()).or_insert(0) += 1;
    }
    let meta = json!({
        "passages": passages.len(),
        "dims": dims,
        "kinds": kinds,
        "tokens": passages.iter().map(Passage::tokens).sum::<usize>(),
    });
    std::fs::write(out.join("meta.json"), format!("{meta}\n")).map_err(|error| error.to_string())?;
    Ok(meta)
}

/// One question of the golden set and the ids that answer it, any of them
pub struct Golden {
    pub question: String,
    pub expected: Vec<String>,
}

pub fn golden(text: &str) -> Vec<Golden> {
    text.lines()
        .filter(|line| !line.starts_with('#') && !line.trim().is_empty())
        .filter_map(|line| line.split_once('\t'))
        .map(|(question, ids)| Golden { question: question.trim().to_string(), expected: ids.split('|').map(|id| id.trim().to_string()).collect() })
        .collect()
}

/// For each ranking, how many questions find one of their passages in the first three, out of those whose
/// passages the index has; and the questions the fused ranking missed
pub fn recall(index: &Index, set: &[Golden]) -> (Vec<(Ranking, usize)>, usize, Vec<String>) {
    let mut asked = 0;
    let mut hits = vec![(Ranking::Words, 0), (Ranking::Meaning, 0), (Ranking::Fused, 0)];
    let mut missed = Vec::new();
    for question in set {
        // An id ending in #* is any passage of that page
        let wanted: Vec<usize> = index
            .passages
            .iter()
            .enumerate()
            .filter(|(_, p)| {
                question.expected.iter().any(|id| match id.strip_suffix('*') {
                    Some(prefix) => p.id.starts_with(prefix),
                    None => &p.id == id,
                })
            })
            .map(|(at, _)| at)
            .collect();
        if wanted.is_empty() {
            continue;
        }
        asked += 1;
        for (ranking, count) in hits.iter_mut() {
            let found = index.ranked(&question.question, *ranking).into_iter().take(3).any(|at| wanted.contains(&at));
            if found {
                *count += 1;
            } else if *ranking == Ranking::Fused {
                let got: Vec<&str> = index.ranked(&question.question, Ranking::Fused).into_iter().take(3).map(|at| index.passages[at].id.as_str()).collect();
                missed.push(format!("{} -> {} (got {})", question.question, question.expected.join("|"), got.join(", ")));
            }
        }
    }
    (hits, asked, missed)
}

/// The anchors a page has, for checking a golden id or a link
pub fn anchors(markdown_text: &str) -> Vec<String> {
    markdown_text.lines().filter_map(|line| line.strip_prefix("## ").or_else(|| line.strip_prefix("### "))).map(slug).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_headers_and_units() {
        assert_eq!(header("#!/usr/bin/bash\n# Does a thing.\n#\n# shellcheck disable=SC1\n#   usage\n\nset -e\n# later\n"), "Does a thing.\n\n  usage");
        let unit = "# Checks things\n[Unit]\nDescription=Amethystora check\n[Service]\nExecCondition=/usr/libexec/x KEY\nExecStart=/usr/libexec/y run\n[Timer]\nOnCalendar=daily\n";
        let text = unit_text(unit, Some("enabled"));
        assert!(text.starts_with("Amethystora check.\nChecks things\n"));
        assert!(text.contains("Runs: `/usr/libexec/y run`") && text.contains("When: `daily`") && text.contains("Only while: `/usr/libexec/x KEY`"));
        assert!(text.ends_with("The image ships it enabled.\n"));
    }

    #[test]
    fn leaves_duress_out_and_reads_the_golden_set() {
        let passage = |text: &str| Passage { id: "x".into(), title: "t".into(), kind: "manual".into(), path: String::new(), text: text.into() };
        assert!(!kept(&passage("A Duress finger")));
        assert!(kept(&passage("A finger")));
        // The other tools' names leave with their sentence, and nothing else does
        assert_eq!(unnamed("Templates come first.\n\n`import` also reads the YAML files Apx writes for its stacks.\nThen more."),
            "Templates come first.\n\nThen more.");
        assert_eq!(unnamed("One. Like Vanilla OS does. Two."), "One. Two.");
        assert_eq!(unnamed("Nothing to take out: apex, vsock."), "Nothing to take out: apex, vsock.");
        let set = golden("# q\tids\nno sound\tmanual/hardware#sound|playbook/no-sound\n\n");
        assert_eq!(set.len(), 1);
        assert_eq!(set[0].expected, ["manual/hardware#sound", "playbook/no-sound"]);
    }
}
