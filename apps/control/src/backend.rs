//! What Amethystora Control runs: what main.js did for the Electron window.
//!
//! Amethystora's own settings outside security, in a window of their own, for what is otherwise only in
//! `ame`. What each setting is now, and the command that changes it, come from one script,
//! /usr/libexec/amethystora-control-list, which `ame control` prints too. This window shows that list and
//! runs its commands, and nothing of its own.
//!
//! The page only ever sends back an entry's id and one of the values the list gave for it, and what runs
//! is the argument vector the list has for that, never through a shell. The few things the page does type
//! are checked here first: a slider's number against the list's range, a new widget's name against the
//! rule amethystora-widgets keeps for names, and a repository to trust against the rule
//! amethystora-trust-image keeps. The key to trust is picked in the window's own file dialog, and the page
//! never names it. A command that asks something, explains a risk or needs a password opens in a terminal
//! (amethystora-in-terminal), and the page reads the list again when the window has the focus back.
//!
//! Security's settings are not here: they are Amethystora Security's, which this window only opens.

use std::path::Path;
use std::sync::OnceLock;
use std::time::Duration;

use amethystora_ui::process::{self, Options, Output};
use amethystora_ui::t;
use regex::Regex;
use serde_json::Value;

pub use amethystora_control_core::{Item, List, Refusal, Run, LIST};
use amethystora_control_core as core;

pub const SETUP: &str = "/usr/libexec/amethystora-setup";
pub const IMAGE_INFO: &str = "/usr/share/amethystora/image-info.json";
/// The pages of the sidebar, in its order
pub const PAGES: [&str; 6] = ["appearance", "desktop", "apps", "agent", "system", "setup"];
/// The pictures a wallpaper can be, by their extension
pub const PICTURES: [&str; 5] = ["jpg", "jpeg", "png", "webp", "svg"];
/// Terminal colour codes some commands write into what they say
const ANSI: &str = r"\x1b\[[0-9;?]*[A-Za-z]";

fn ansi() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(ANSI).expect("a valid expression"))
}

/// The page to open: `amethystora-control system` opens on the system's settings
pub fn page_argument(args: &[String]) -> Option<&'static str> {
    let page = args.iter().find(|arg| !arg.starts_with('-'))?;
    PAGES.iter().find(|known| *known == page).copied()
}

// --- The list ---------------------------------------------------------------------------------------------
//
// What the list holds and how an entry's id and value become a command are amethystora-control-core's,
// which the agent's tools share, so that both change a setting the same way. What it says when it refuses
// is said here, in the window's own words.

/// What to say when the list does not offer what was asked, or what was typed is not taken
fn words(refusal: Refusal) -> String {
    match refusal {
        Refusal::Refused => refused(),
        Refusal::WidgetName => t!("A widget's name is lower case letters, digits and dashes, and not the name of one you have."),
        Refusal::Repository => t!("That is not a repository such as ghcr.io/you/your-image: lower case, and no tag."),
        Refusal::OwnRepository => t!("Amethystora's own images are checked against Amethystora's key, and that stays as it is."),
        Refusal::NoKey => t!("Choose the key first: the cosign.pub of your repository."),
    }
}

/// The list from what the script printed, or None when that was not JSON
pub fn parse_list(stdout: &str) -> Option<List> {
    core::parse_list(stdout)
}

/// The list, read again, or what to say when it could not be read
pub async fn read_list() -> Result<List, String> {
    let result = process::run_with(LIST, &["--json"], Options { timeout: Duration::from_secs(60), ..Default::default() }).await;
    parse_list(&result.stdout).ok_or_else(|| {
        let error = ansi().replace_all(&result.stderr, "").trim().to_string();
        if error.is_empty() { t!("The settings could not be read.") } else { error }
    })
}

// --- Running what the list says ---------------------------------------------------------------------------

/// What came of a command: it opened in a terminal, it could not be run, or it ran here and said this
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    Terminal,
    Error(String),
    Ran { ok: bool, output: String },
}

fn refused() -> String {
    t!("That cannot be done from here now. Read the settings again and try once more.")
}

/// What a command run here printed, as the page shows it under its card: the last lines, without colours
pub fn said(result: &Output) -> String {
    let all = format!("{}\n{}", result.stdout, result.stderr);
    let plain = ansi().replace_all(&all, "");
    let lines: Vec<&str> = plain.trim().split('\n').collect();
    lines[lines.len().saturating_sub(12)..].join("\n")
}

/// A command from the list, in a terminal when it asks for one, and otherwise here, with what it said
pub async fn perform(plan: Result<Run, String>) -> Outcome {
    let run = match plan {
        Ok(run) => run,
        Err(error) => return Outcome::Error(error),
    };
    if run.terminal {
        process::launch_owned(process::IN_TERMINAL, &run.argv);
        return Outcome::Terminal;
    }
    let args: Vec<&str> = run.argv[1..].iter().map(String::as_str).collect();
    let result = process::run_with(&run.argv[0], &args, Options { timeout: Duration::from_secs(300), ..Default::default() }).await;
    Outcome::Ran { ok: result.code == 0, output: said(&result) }
}

/// A setting set to one of its choices, or a slider to a number in its range
pub fn change(list: Option<&List>, id: &str, value: &str) -> Result<Run, String> {
    core::change(list, id, value).map_err(words)
}

pub fn act(list: Option<&List>, id: &str) -> Result<Run, String> {
    core::act(list, id).map_err(words)
}

/// The rule amethystora-widgets has for a widget's name, as the page checks it before it sends one
pub fn valid_widget_name(item: &Item, name: &str) -> bool {
    core::valid_widget_name(item, name)
}

/// A widget the list named: on, off, fix or remove; or restart and make, which name none
pub fn widget(list: Option<&List>, action: &str, id: &str) -> Result<Run, String> {
    core::widget(list, action, id).map_err(words)
}

/// A new widget from one of the examples, under a name of its own
pub fn new_widget(list: Option<&List>, id: &str, example: &str) -> Result<Run, String> {
    core::new_widget(list, id, example).map_err(words)
}

/// A web app the list named, removed; or a new one, added in a terminal
pub fn webapp(list: Option<&List>, action: &str, name: &str) -> Result<Run, String> {
    core::webapp(list, action, name).map_err(words)
}

/// One of the actions the list gave a pool of disks
pub fn pool(list: Option<&List>, action: &str, id: &str) -> Result<Run, String> {
    core::pool(list, action, id).map_err(words)
}

// --- An image of one's own --------------------------------------------------------------------------------

/// The rule amethystora-trust-image has for a repository
pub fn valid_repository(repository: &str) -> bool {
    core::valid_repository(repository)
}

/// Amethystora's own repositories, which keep Amethystora's key, as amethystora-trust-image has them
pub fn own_repository(image_info: &str) -> Option<String> {
    core::own_repository(image_info)
}

/// Trusting a repository with the key picked in the file dialog. `own` is Amethystora's own repository.
pub fn trust_image(list: Option<&List>, repository: &str, own: Option<&str>, key: Option<&Path>) -> Result<Run, String> {
    core::trust_image(list, repository, own, key).map_err(words)
}

// --- The setup file ---------------------------------------------------------------------------------------

/// The setup file saved here, or applied in a terminal, where `ame setup apply` shows what it adds first
pub fn setup(list: Option<&List>, action: &str) -> Result<Run, String> {
    core::setup(list, action).map_err(words)
}

/// What the machine and the setup file disagree on, which `ame setup diff` works out and changes nothing
pub async fn setup_diff() -> Result<Vec<Value>, String> {
    let result = process::run_with(SETUP, &["diff", "--json"], Options { timeout: Duration::from_secs(120), ..Default::default() }).await;
    parse_diff(&result).ok_or_else(|| {
        let said = said(&result);
        if said.is_empty() { t!("Your setup file could not be compared with this machine.") } else { said }
    })
}

/// The changes, or None when what it printed was not JSON. Anything but a list of them is as if it had
/// found none, as the page took it.
pub fn parse_diff(result: &Output) -> Option<Vec<Value>> {
    let value: Value = serde_json::from_str(&result.stdout).ok()?;
    Some(match value {
        Value::Array(changes) => changes,
        _ => Vec::new(),
    })
}

// --- Elsewhere --------------------------------------------------------------------------------------------

/// The windows a link opens, each by the one command that opens it
pub fn link_program(link: &str, list: Option<&List>) -> Option<&'static str> {
    match link {
        "security" => Some("amethystora-security"),
        "updates" => Some("amethystora-update"),
        "backups" if list.is_some_and(|list| list.backups) => Some("amethystora-backups"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST_JSON: &str = r#"{"version": 1, "sealed": false, "elsewhere": {"automatic_updates": "on", "backups": true}, "items": [
        {"page": "appearance", "id": "transition-length", "kind": "range", "group": null, "title": "Transition length", "text": "How long",
         "state": "1200", "available": true, "min": 200, "max": 5000, "step": 100, "unit": "ms", "terminal": false,
         "command": ["ame", "desktop", "transition", "grow", "{value}"]},
        {"page": "desktop", "id": "greeting", "kind": "switch", "title": "Terminal greeting", "state": "on", "available": true,
         "choices": [{"value": "on", "title": "On", "text": null, "terminal": false, "command": ["ame", "desktop", "greeting", "on"]},
                     {"value": "off", "title": "Off", "text": null, "terminal": true, "command": ["ame", "desktop", "greeting", "off"]}]},
        {"page": "apps", "id": "gaming", "kind": "switch", "title": "Games", "state": "off", "available": false, "reason": "No",
         "choices": [{"value": "on", "title": "On", "terminal": true, "command": ["ame", "apps", "gaming", "on"]}]},
        {"page": "apps", "id": "cli", "kind": "action", "title": "Tools", "available": true, "terminal": true, "command": ["ame", "apps", "cli"], "button": "Install…"},
        {"page": "apps", "id": "bad", "kind": "action", "title": "Bad", "available": true, "terminal": false, "command": ["ame", 3]},
        {"page": "desktop", "id": "widgets", "kind": "widgets", "title": "Top bar widgets", "available": true, "bar": false, "agentic": false,
         "widgets": [{"id": "pomodoro", "name": "Pomodoro", "on": true, "broken": false}, {"id": "half", "name": null, "on": false, "broken": true}],
         "examples": ["hello", "pomodoro"],
         "commands": {"on": {"terminal": false, "command": ["ame", "desktop", "widgets", "on", "{id}"]},
                      "new": {"terminal": false, "command": ["ame", "desktop", "widgets", "new", "{id}", "{example}"]},
                      "restart": {"terminal": false, "command": ["ame", "desktop", "widgets", "restart"]},
                      "fix": {"terminal": true, "command": ["ame", "desktop", "widgets", "fix", "{id}"]}}},
        {"page": "apps", "id": "webapps", "kind": "webapps", "title": "Web apps", "available": true,
         "webapps": [{"name": "Element", "address": "https://app.element.io"}],
         "commands": {"install": {"terminal": true, "command": ["ame", "apps", "webapps", "install"]},
                      "remove": {"terminal": false, "command": ["ame", "apps", "webapps", "remove", "{name}"]}}},
        {"page": "system", "id": "trust-image", "kind": "trust-image", "title": "Own", "available": true, "terminal": true,
         "command": ["ame", "system", "trust-image", "{repository}", "{key}"]},
        {"page": "system", "id": "disks", "kind": "disks", "title": "Pools", "available": true,
         "disks": [{"id": "media", "title": "media, at /var/mnt/media", "text": "Two copies.", "state": "ok",
                    "actions": [{"id": "forget", "title": "Forget…", "terminal": true, "command": ["ame", "system", "raid", "forget", "media"]}]}]},
        {"page": "setup", "id": "setup-file", "kind": "setup", "title": "Your setup file", "available": true, "file": "/home/a/.config/amethystora/setup.json",
         "saved": 1760000000, "state": "saved",
         "commands": {"save": {"terminal": false, "command": ["ame", "setup", "save"]}, "apply": {"terminal": true, "command": ["ame", "setup", "apply"]}}}
    ]}"#;

    fn list() -> List {
        parse_list(LIST_JSON).expect("the list parses")
    }

    fn argv(run: Result<Run, String>) -> Vec<String> {
        run.expect("allowed").argv
    }

    #[test]
    fn says_what_was_refused_in_the_windows_words() {
        let list = list();
        assert_eq!(argv(change(Some(&list), "greeting", "off")), ["ame", "desktop", "greeting", "off"]);
        assert_eq!(change(Some(&list), "greeting", "maybe"), Err(refused()));
        assert_eq!(new_widget(Some(&list), "My-clock", "hello"), Err(words(Refusal::WidgetName)));
        assert_ne!(words(Refusal::WidgetName), refused());
        assert_eq!(trust_image(Some(&list), "ghcr.io/you/image", Some("ghcr.io/iarsslen"), None), Err(words(Refusal::NoKey)));
    }

    #[test]
    fn says_the_last_lines_without_colours() {
        let output = Output { code: 1, stdout: "one\ntwo\n".into(), stderr: "\u{1b}[31merror:\u{1b}[0m three\n".into() };
        assert_eq!(said(&output), "one\ntwo\n\nerror: three");
        let long: String = (1..=20).map(|n| format!("{n}\n")).collect();
        assert_eq!(said(&Output { code: 0, stdout: long, stderr: String::new() }), (9..=20).map(|n| n.to_string()).collect::<Vec<_>>().join("\n"));
        assert_eq!(said(&Output::default()), "");
    }

    #[test]
    fn diffs_and_pages() {
        let output = |stdout: &str| Output { code: 0, stdout: stdout.into(), stderr: String::new() };
        assert_eq!(parse_diff(&output(r#"[{"area": "theme"}]"#)).unwrap().len(), 1);
        assert!(parse_diff(&output(r#"{"area": "theme"}"#)).unwrap().is_empty());
        assert!(parse_diff(&output("oops")).is_none());
        assert_eq!(page_argument(&["--gapplication-service".into(), "system".into()]), Some("system"));
        assert_eq!(page_argument(&["security".into()]), None);
        assert_eq!(page_argument(&[]), None);
        let list = list();
        assert_eq!(link_program("backups", Some(&list)), Some("amethystora-backups"));
        assert_eq!(link_program("backups", None), None);
        assert_eq!(link_program("manual", Some(&list)), None);
    }
}
