//! Every note as a Markdown file in a folder per notebook, every project's tasks as a checklist, and the
//! attachments in _resources, which the notes link to relatively, as main.js's exportMarkdown wrote them.
//! What it writes of its own, the folders Notes, Tasks and _resources and the words in the checklists, is
//! English in every language.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::data::{self, Fields, Kind, Store};

/// A name any file system takes
pub fn file_name(name: &str, fallback: &str) -> String {
    let mut clean = String::new();
    let mut run = false;
    for c in name.chars() {
        let bad = (c as u32) < 0x20 || matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|');
        if bad {
            if !run {
                clean.push('-');
            }
            run = true;
        } else {
            clean.push(c);
            run = false;
        }
    }
    let trimmed = clean.trim_matches(|c: char| c == '.' || c.is_whitespace());
    let cut = data::js_slice(trimmed, 120);
    if cut.is_empty() { fallback.to_string() } else { cut }
}

/// The name, or the name with " 2", " 3" and so on, that is not taken yet, case aside
pub fn unique(taken: &mut HashSet<String>, base: &str, extension: &str) -> String {
    let mut name = format!("{base}{extension}");
    let mut count = 2;
    while taken.contains(&name.to_lowercase()) {
        name = format!("{base} {count}{extension}");
        count += 1;
    }
    taken.insert(name.to_lowercase());
    name
}

/// What the export wrote: where, and how many notes and tasks
#[derive(Debug, Clone, PartialEq)]
pub struct Exported {
    pub path: PathBuf,
    pub notes: usize,
    pub tasks: usize,
}

/// path.relative(from, to), with forward slashes, for two folders under the same root
fn relative(from: &Path, to: &Path) -> String {
    let from: Vec<_> = from.components().collect();
    let to: Vec<_> = to.components().collect();
    let common = from.iter().zip(&to).take_while(|(a, b)| a == b).count();
    let mut parts: Vec<String> = Vec::new();
    for _ in common..from.len() {
        parts.push("..".into());
    }
    for part in &to[common..] {
        parts.push(part.as_os_str().to_string_lossy().into_owned());
    }
    parts.join("/")
}

/// Everything into a new folder in `into`, named for today; the attachments read with `read`
pub fn export_markdown(store: &Store, into: &Path, read: &dyn Fn(&str) -> Option<Vec<u8>>) -> std::io::Result<Exported> {
    let mut existing: HashSet<String> = HashSet::new();
    for entry in std::fs::read_dir(into)?.flatten() {
        existing.insert(entry.file_name().to_string_lossy().to_lowercase());
    }
    let root = into.join(unique(&mut existing, &format!("Notes {}", crate::dates::today()), ""));
    let mut folders: HashMap<String, PathBuf> = HashMap::new();
    let mut taken_in: HashMap<PathBuf, HashSet<String>> = HashMap::new();
    fn folder_of(
        store: &Store,
        id: Option<&str>,
        depth: usize,
        root: &Path,
        folders: &mut HashMap<String, PathBuf>,
        taken_in: &mut HashMap<PathBuf, HashSet<String>>,
    ) -> PathBuf {
        let Some(id) = id else { return root.to_path_buf() };
        let Some(notebook) = store.get(Kind::Notebooks, id) else { return root.to_path_buf() };
        if depth > 32 {
            return root.to_path_buf();
        }
        if let Some(folder) = folders.get(id) {
            return folder.clone();
        }
        let parent_id = notebook.opt("parent").map(str::to_string);
        let parent = folder_of(store, parent_id.as_deref(), depth + 1, root, folders, taken_in);
        let taken = taken_in.entry(parent.clone()).or_default();
        let folder = parent.join(unique(taken, &file_name(&data::text(notebook.get("title")), "Untitled"), ""));
        folders.insert(id.to_string(), folder.clone());
        folder
    }
    let resource_dir = root.join("_resources");
    let mut used: Vec<String> = Vec::new();
    let mut notes = 0;
    for note in store.values(Kind::Notes).filter(|note| !note.is("trashed")) {
        let notebook = note.opt("notebook").map(str::to_string);
        let folder = folder_of(store, notebook.as_deref(), 0, &root, &mut folders, &mut taken_in);
        std::fs::create_dir_all(&folder)?;
        let link = relative(&folder, &resource_dir);
        let body = linked(&data::text(note.get("body")), store, &link, &mut used);
        let tags: Vec<String> =
            note.list("tags").iter().filter_map(|id| store.get(Kind::Tags, id).map(|tag| data::text(tag.get("title")))).filter(|t| !t.is_empty()).collect();
        let time = |name: &str| {
            let value = note.num(name).filter(|n| *n != 0.0).unwrap_or_else(data::now_ms);
            crate::import::iso_string(value)
        };
        let mut front = vec![
            "---".to_string(),
            format!("title: {}", Value::String(data::text(note.get("title"))).to_string()),
            format!("created: {}", time("created")),
            format!("updated: {}", time("updated")),
        ];
        if !tags.is_empty() {
            front.push(format!("tags: {}", Value::from(tags.clone())));
        }
        front.push("---".into());
        front.push(String::new());
        let taken = taken_in.entry(folder.clone()).or_default();
        let name = unique(taken, &file_name(&data::text(note.get("title")), "Untitled"), ".md");
        std::fs::write(folder.join(name), format!("{}\n{body}\n", front.join("\n")))?;
        notes += 1;
    }
    if !used.is_empty() {
        std::fs::create_dir_all(&resource_dir)?;
        for id in &used {
            let Some(resource) = store.resources.get(id) else { continue };
            if let Some(bytes) = read(id) {
                let extension = crate::backend::extension_of(&data::text(resource.get("mime")), &data::text(resource.get("name")));
                std::fs::write(resource_dir.join(format!("{id}.{extension}")), bytes)?;
            }
        }
    }
    // Tasks: a checklist per project, the inbox first, sections as headings, subtasks indented
    let tasks: Vec<&Value> = store.values(Kind::Tasks).collect();
    let mut lists: Vec<(Option<String>, String)> = vec![(None, "Inbox".into())];
    for project in store.values(Kind::Projects) {
        lists.push((Some(project.id().to_string()), data::text(project.get("title"))));
    }
    let mut taken_tasks = HashSet::new();
    let mut exported_tasks = 0;
    for (project, title) in lists {
        let own: Vec<&Value> = tasks.iter().copied().filter(|task| task.opt("project").map(str::to_string) == project && !task.is("parent")).collect();
        if own.is_empty() {
            continue;
        }
        let shown_title = if title.is_empty() { "Untitled".to_string() } else { title.clone() };
        let mut rows = vec![format!("# {shown_title}"), String::new()];
        let mut sections: Vec<&Value> =
            store.values(Kind::Sections).filter(|section| section.opt("project").map(str::to_string) == project).collect();
        sections.sort_by(|a, b| a.num_or_zero("order").partial_cmp(&b.num_or_zero("order")).unwrap_or(std::cmp::Ordering::Equal));
        for task in own.iter().filter(|task| task.opt("section").is_none_or(|s| !store.has(Kind::Sections, s))) {
            rows.extend(line(task, 0, &tasks, store));
        }
        for section in sections {
            let heading = data::text(section.get("title"));
            rows.push(String::new());
            rows.push(format!("## {}", if heading.is_empty() { "Untitled" } else { &heading }));
            rows.push(String::new());
            for task in own.iter().filter(|task| task.str("section") == section.id()) {
                rows.extend(line(task, 0, &tasks, store));
            }
        }
        std::fs::create_dir_all(root.join("Tasks"))?;
        let mut text = rows.join("\n");
        while text.contains("\n\n\n") {
            text = text.replace("\n\n\n", "\n\n");
        }
        std::fs::write(root.join("Tasks").join(unique(&mut taken_tasks, &file_name(&title, "Untitled"), ".md")), format!("{text}\n"))?;
        exported_tasks += own.len();
    }
    std::fs::create_dir_all(&root)?;
    Ok(Exported { path: root, notes, tasks: exported_tasks })
}

/// The note's links to attachments pointed at the files in _resources
fn linked(body: &str, store: &Store, link: &str, used: &mut Vec<String>) -> String {
    let mut out = String::with_capacity(body.len());
    let bytes = body.as_bytes();
    let mut at = 0;
    let mut last = 0;
    while at + 34 <= bytes.len() {
        if bytes[at] == b':' && bytes[at + 1] == b'/' && data::is_id(&body[at + 2..at + 34]) {
            let id = &body[at + 2..at + 34];
            if let Some(resource) = store.resources.get(id) {
                out.push_str(&body[last..at]);
                if !used.iter().any(|u| u == id) {
                    used.push(id.to_string());
                }
                let extension = crate::backend::extension_of(&data::text(resource.get("mime")), &data::text(resource.get("name")));
                out.push_str(&format!("{link}/{id}.{extension}"));
                last = at + 34;
            }
            at += 34;
        } else {
            at += 1;
        }
    }
    out.push_str(&body[last..]);
    out
}

/// A task and its subtasks as lines of a checklist, with what is set on it in brackets
fn line(task: &Value, depth: usize, tasks: &[&Value], store: &Store) -> Vec<String> {
    let mut details: Vec<String> = Vec::new();
    if task.is("due") {
        let time = if task.is("time") { format!(" {}", data::text(task.get("time"))) } else { String::new() };
        details.push(format!("due {}{time}", data::text(task.get("due"))));
    }
    if let Some(repeat) = task.get("repeat").filter(|r| data::truthy(Some(r))) {
        let every = repeat.num_or_zero("every");
        let unit = data::text(repeat.get("unit"));
        let count = if every > 1.0 { format!("{} ", data::js_number(every)) } else { String::new() };
        details.push(format!("every {count}{unit}{}", if every > 1.0 { "s" } else { "" }));
    }
    let priority = task.num_or_zero("priority");
    if priority != 0.0 && priority < 4.0 {
        details.push(format!("p{}", data::js_number(priority)));
    }
    for id in task.list("labels") {
        if let Some(label) = store.get(Kind::Labels, &id) {
            details.push(format!("@{}", data::text(label.get("title"))));
        }
    }
    let title = if task.is("title") { data::text(task.get("title")) } else { "Untitled".into() };
    let suffix = if details.is_empty() { String::new() } else { format!(" ({})", details.join(", ")) };
    let mut rows = vec![format!("{}- [{}] {title}{suffix}", "  ".repeat(depth), if task.is("done") { "x" } else { " " })];
    for child in tasks.iter().filter(|item| item.opt("parent") == Some(task.id())) {
        rows.extend(line(child, depth + 1, tasks, store));
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_any_file_system_takes() {
        assert_eq!(file_name("a/b:c", "Untitled"), "a-b-c");
        assert_eq!(file_name("  ..hidden. ", "Untitled"), "hidden");
        assert_eq!(file_name("", "Untitled"), "Untitled");
        assert_eq!(file_name("x\u{1}\u{2}y", "Untitled"), "x-y");
        let mut taken = HashSet::new();
        assert_eq!(unique(&mut taken, "Note", ".md"), "Note.md");
        assert_eq!(unique(&mut taken, "note", ".md"), "note 2.md");
        assert_eq!(relative(Path::new("/r/Notes/Work"), Path::new("/r/_resources")), "../../_resources");
        assert_eq!(relative(Path::new("/r"), Path::new("/r/_resources")), "_resources");
    }
}
