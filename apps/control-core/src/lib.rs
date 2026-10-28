//! Amethystora's own settings outside security, as /usr/libexec/amethystora-control-list gives them, and the
//! one way to change one: what Amethystora Control and the agent's tools (amethystora-agent-tools) share.
//!
//! What runs is only ever the argument vector the list has for an entry's id and one of the values it gave
//! for it, never through a shell. The few things a caller types are checked here first: a slider's number
//! against the list's range, a new widget's name against the rule amethystora-widgets keeps for names, and
//! a repository to trust against the rule amethystora-trust-image keeps. A refusal says which of these it
//! was, and the caller puts it in its own words.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::sync::OnceLock;

use regex::Regex;
use serde_json::Value;

pub const LIST: &str = "/usr/libexec/amethystora-control-list";
/// A widget's name, as amethystora-widgets new takes it
const WIDGET_ID: &str = r"^[a-z0-9][a-z0-9-]*$";
/// A repository as amethystora-trust-image takes it: a registry with a dot or a port, a path in lower
/// case, no tag and no digest. The helper's own expression, letter for letter, and it checks it again.
const REPOSITORY: &str = r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(\.[a-z0-9-]+|:[0-9]+)(/[a-z0-9]+(([._]|__|-+)[a-z0-9]+)*)+$";

fn regex(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pattern).expect("a valid expression"))
}

// --- The list ---------------------------------------------------------------------------------------------

/// A command of the list, and whether it opens in a terminal. `command` is None unless it is a list of
/// words, which is all that is ever run.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Command {
    pub terminal: bool,
    pub command: Option<Vec<String>>,
}

#[derive(Debug, Clone, Default)]
pub struct Choice {
    pub value: String,
    pub title: String,
    pub text: Option<String>,
    pub terminal: bool,
    pub command: Option<Vec<String>>,
    /// A theme's palette, which its swatch is drawn in
    pub colors: BTreeMap<String, String>,
    /// A font's family, which its name is drawn in
    pub font: Option<String>,
    /// A colour the choice is (an accent), which its dot is drawn in
    pub color: Option<String>,
    /// Whether a theme is light, for its preview
    pub light: bool,
    /// A theme's opening picture, which its preview stands on
    pub picture: Option<String>,
    /// The picture a wallpaper's tile shows, when it is not the wallpaper itself (Daylight's picture of the hour)
    pub thumbnail: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct Widget {
    pub id: String,
    pub name: Option<String>,
    pub on: bool,
    pub broken: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Webapp {
    pub name: String,
    pub address: String,
}

/// One of the actions the list gives a pool of disks
#[derive(Debug, Clone, Default)]
pub struct PoolAction {
    pub id: String,
    pub title: String,
    pub terminal: bool,
    pub command: Option<Vec<String>>,
}

#[derive(Debug, Clone, Default)]
pub struct Disk {
    pub id: String,
    pub title: String,
    pub text: Option<String>,
    pub state: String,
    pub actions: Vec<PoolAction>,
}

/// An entry of the list, as amethystora-control-list's item() makes it, with what its kind adds
#[derive(Debug, Clone, Default)]
pub struct Item {
    pub page: String,
    pub id: String,
    pub kind: String,
    pub group: Option<String>,
    pub title: String,
    pub text: Option<String>,
    pub state: Option<String>,
    pub detail: Option<String>,
    pub available: bool,
    pub reason: Option<String>,
    pub manual: Option<String>,
    pub usage: Option<String>,
    pub choices: Vec<Choice>,
    pub terminal: bool,
    pub command: Option<Vec<String>>,
    pub button: Option<String>,
    pub danger: bool,
    // A slider's
    pub min: Option<f64>,
    pub max: Option<f64>,
    pub step: Option<f64>,
    pub unit: Option<String>,
    // The widgets', the web apps' and the setup file's
    pub widgets: Vec<Widget>,
    pub bar: bool,
    pub examples: Vec<String>,
    pub agentic: bool,
    pub commands: HashMap<String, Command>,
    pub webapps: Vec<Webapp>,
    pub file: Option<String>,
    pub saved: Option<f64>,
    // The pools of disks
    pub disks: Vec<Disk>,
}

/// The list as the script gave it: {version, sealed, elsewhere, items}, of which the page uses the last two
#[derive(Debug, Clone, Default)]
pub struct List {
    /// Whether the Updates window's automatic updates are on, "on" or "off"
    pub automatic_updates: Option<String>,
    /// Whether the Backups window is installed
    pub backups: bool,
    pub items: Vec<Item>,
}

// Read leniently, as the page read the parsed JSON: a field that is missing or of another type is as if
// it were not there, and only a command that is a list of words is ever run

/// Text, or None for nothing or an empty string, which the page treated alike
pub fn text(value: Option<&Value>) -> Option<String> {
    match value {
        Some(Value::String(s)) if !s.is_empty() => Some(s.clone()),
        Some(Value::Number(n)) => Some(n.to_string()),
        _ => None,
    }
}

fn string(value: Option<&Value>) -> String {
    text(value).unwrap_or_default()
}

/// JavaScript's truthiness, for the flags the page tested as `if (item.agentic)`
fn truthy(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().is_some_and(|n| n != 0.0 && !n.is_nan()),
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(_) | Value::Object(_)) => true,
        _ => false,
    }
}

fn number(value: Option<&Value>) -> Option<f64> {
    match value {
        Some(Value::Number(n)) => n.as_f64(),
        _ => None,
    }
}

fn words(value: Option<&Value>) -> Option<Vec<String>> {
    let list = value?.as_array()?;
    list.iter().map(|word| word.as_str().map(str::to_string)).collect()
}

fn array(value: Option<&Value>) -> &[Value] {
    value.and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[])
}

fn command(value: &Value) -> Command {
    Command { terminal: truthy(value.get("terminal")), command: words(value.get("command")) }
}

fn choice(value: &Value) -> Choice {
    let colors = value
        .get("colors")
        .and_then(Value::as_object)
        .map(|colors| colors.iter().filter_map(|(key, value)| Some((key.clone(), value.as_str()?.to_string()))).collect())
        .unwrap_or_default();
    Choice {
        value: string(value.get("value")),
        title: string(value.get("title")),
        text: text(value.get("text")),
        terminal: truthy(value.get("terminal")),
        command: words(value.get("command")),
        colors,
        font: text(value.get("font")),
        color: text(value.get("color")),
        light: truthy(value.get("light")),
        picture: text(value.get("picture")),
        thumbnail: text(value.get("thumbnail")),
    }
}

fn item(value: &Value) -> Item {
    let field = |name: &str| value.get(name);
    Item {
        page: string(field("page")),
        id: string(field("id")),
        kind: string(field("kind")),
        group: text(field("group")),
        title: string(field("title")),
        text: text(field("text")),
        state: text(field("state")),
        detail: text(field("detail")),
        available: truthy(field("available")),
        reason: text(field("reason")),
        manual: text(field("manual")),
        usage: text(field("usage")),
        choices: array(field("choices")).iter().map(choice).collect(),
        terminal: truthy(field("terminal")),
        command: words(field("command")),
        button: text(field("button")),
        danger: truthy(field("danger")),
        min: number(field("min")),
        max: number(field("max")),
        step: number(field("step")),
        unit: text(field("unit")),
        widgets: array(field("widgets"))
            .iter()
            .map(|widget| Widget {
                id: string(widget.get("id")),
                name: text(widget.get("name")),
                on: truthy(widget.get("on")),
                broken: truthy(widget.get("broken")),
            })
            .collect(),
        bar: truthy(field("bar")),
        examples: array(field("examples")).iter().filter_map(|example| example.as_str().map(str::to_string)).collect(),
        agentic: truthy(field("agentic")),
        commands: field("commands")
            .and_then(Value::as_object)
            .map(|commands| commands.iter().map(|(name, value)| (name.clone(), command(value))).collect())
            .unwrap_or_default(),
        webapps: array(field("webapps"))
            .iter()
            .map(|webapp| Webapp { name: string(webapp.get("name")), address: string(webapp.get("address")) })
            .collect(),
        file: text(field("file")),
        saved: number(field("saved")),
        disks: array(field("disks"))
            .iter()
            .map(|disk| Disk {
                id: string(disk.get("id")),
                title: string(disk.get("title")),
                text: text(disk.get("text")),
                state: string(disk.get("state")),
                actions: array(disk.get("actions"))
                    .iter()
                    .map(|action| PoolAction {
                        id: string(action.get("id")),
                        title: string(action.get("title")),
                        terminal: truthy(action.get("terminal")),
                        command: words(action.get("command")),
                    })
                    .collect(),
            })
            .collect(),
    }
}

/// The list from what the script printed, or None when that was not JSON
pub fn parse_list(stdout: &str) -> Option<List> {
    let value: Value = serde_json::from_str(stdout).ok()?;
    let elsewhere = value.get("elsewhere");
    Some(List {
        automatic_updates: text(elsewhere.and_then(|e| e.get("automatic_updates"))),
        backups: truthy(elsewhere.and_then(|e| e.get("backups"))),
        items: array(value.get("items")).iter().map(item).collect(),
    })
}

impl List {
    pub fn find(&self, id: &str) -> Option<&Item> {
        self.items.iter().find(|item| item.id == id)
    }

    pub fn first_of_kind(&self, kind: &str) -> Option<&Item> {
        self.items.iter().find(|item| item.kind == kind)
    }
}

// --- Running what the list says ---------------------------------------------------------------------------

/// Why something is not run. Refused is anything the list does not offer now; the rest are what was typed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    /// Not offered by the list, or not available here now
    Refused,
    /// A new widget's name that amethystora-widgets would not take, or one taken already
    WidgetName,
    /// A repository amethystora-trust-image would not take
    Repository,
    /// One of Amethystora's own repositories, which keep Amethystora's key
    OwnRepository,
    /// No key, or one that is not there
    NoKey,
}

/// A command of the list with values checked here in the place of its placeholders, {value} and the like,
/// each of which stands for a whole argument
fn fill(command: &[String], values: &[(&str, &str)]) -> Vec<String> {
    command
        .iter()
        .map(|arg| values.iter().find(|(key, _)| key == arg).map(|(_, value)| value.to_string()).unwrap_or_else(|| arg.clone()))
        .collect()
}

/// What to run, once everything about it has been checked: an argument vector, in a terminal or here
#[derive(Debug, Clone, PartialEq)]
pub struct Run {
    pub argv: Vec<String>,
    pub terminal: bool,
}

/// Only a command that is a list of words, at least one, is ever run
fn runnable(command: Option<&Vec<String>>, terminal: bool) -> Result<Run, Refusal> {
    match command {
        Some(argv) if !argv.is_empty() => Ok(Run { argv: argv.clone(), terminal }),
        _ => Err(Refusal::Refused),
    }
}

fn filled(command: Option<&Vec<String>>, terminal: bool, values: &[(&str, &str)]) -> Result<Run, Refusal> {
    runnable(command, terminal).map(|run| Run { argv: fill(&run.argv, values), terminal })
}

/// A slider's number as the page sends it: one to nine digits, inside the list's range
pub fn range_value(item: &Item, value: &str) -> Option<String> {
    if value.is_empty() || value.len() > 9 || !value.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let number: u64 = value.parse().ok()?;
    let n = number as f64;
    // A bound the list does not give holds nothing back, as a comparison with undefined did
    if item.min.is_some_and(|min| n < min) || item.max.is_some_and(|max| n > max) {
        return None;
    }
    Some(number.to_string())
}

/// A setting set to one of its choices, or a slider to a number in its range
pub fn change(list: Option<&List>, id: &str, value: &str) -> Result<Run, Refusal> {
    let item = list.and_then(|list| list.find(id)).filter(|item| item.available).ok_or(Refusal::Refused)?;
    if item.kind == "range" {
        let number = range_value(item, value).ok_or(Refusal::Refused)?;
        return filled(item.command.as_ref(), item.terminal, &[("{value}", &number)]);
    }
    let choice = item.choices.iter().find(|choice| choice.value == value).ok_or(Refusal::Refused)?;
    runnable(choice.command.as_ref(), choice.terminal)
}

pub fn act(list: Option<&List>, id: &str) -> Result<Run, Refusal> {
    match list.and_then(|list| list.find(id)) {
        Some(item) if item.available && item.kind == "action" => runnable(item.command.as_ref(), item.terminal),
        _ => Err(Refusal::Refused),
    }
}

/// The rule amethystora-widgets has for a widget's name, as the page checks it before it sends one
pub fn valid_widget_name(item: &Item, name: &str) -> bool {
    static CELL: OnceLock<Regex> = OnceLock::new();
    regex(&CELL, WIDGET_ID).is_match(name) && name.len() <= 40 && !item.widgets.iter().any(|widget| widget.id == name)
}

/// A widget the list named: on, off, fix or remove; or restart and make, which name none
pub fn widget(list: Option<&List>, action: &str, id: &str) -> Result<Run, Refusal> {
    let item = list.and_then(|list| list.find("widgets")).ok_or(Refusal::Refused)?;
    let command = item.commands.get(action);
    let Some(command) = command.filter(|_| item.available && action != "new") else {
        return Err(Refusal::Refused);
    };
    if (action == "make" || action == "fix") && !item.agentic {
        return Err(Refusal::Refused);
    }
    let names_one = command.command.as_ref().is_some_and(|words| words.iter().any(|word| word == "{id}"));
    if names_one && !item.widgets.iter().any(|widget| widget.id == id) {
        return Err(Refusal::Refused);
    }
    filled(command.command.as_ref(), command.terminal, &[("{id}", id)])
}

/// A new widget from one of the examples, under a name of its own
pub fn new_widget(list: Option<&List>, id: &str, example: &str) -> Result<Run, Refusal> {
    let item = list.and_then(|list| list.find("widgets")).ok_or(Refusal::Refused)?;
    if !item.available || !item.examples.iter().any(|known| known == example) {
        return Err(Refusal::Refused);
    }
    if !valid_widget_name(item, id) {
        return Err(Refusal::WidgetName);
    }
    let command = item.commands.get("new").ok_or(Refusal::Refused)?;
    filled(command.command.as_ref(), command.terminal, &[("{id}", id), ("{example}", example)])
}

/// A web app the list named, removed; or a new one, added in a terminal
pub fn webapp(list: Option<&List>, action: &str, name: &str) -> Result<Run, Refusal> {
    let item = list.and_then(|list| list.find("webapps")).ok_or(Refusal::Refused)?;
    let Some(command) = item.commands.get(action).filter(|_| item.available) else {
        return Err(Refusal::Refused);
    };
    let names_one = command.command.as_ref().is_some_and(|words| words.iter().any(|word| word == "{name}"));
    if names_one && !item.webapps.iter().any(|webapp| webapp.name == name) {
        return Err(Refusal::Refused);
    }
    filled(command.command.as_ref(), command.terminal, &[("{name}", name)])
}

/// One of the actions the list gave a pool of disks
pub fn pool(list: Option<&List>, action: &str, id: &str) -> Result<Run, Refusal> {
    let item = list.and_then(|list| list.first_of_kind("disks")).ok_or(Refusal::Refused)?;
    let found = item.disks.iter().find(|disk| disk.id == id).and_then(|disk| disk.actions.iter().find(|candidate| candidate.id == action));
    match found {
        Some(found) if item.available => runnable(found.command.as_ref(), found.terminal),
        _ => Err(Refusal::Refused),
    }
}

// --- An image of one's own --------------------------------------------------------------------------------

/// The rule amethystora-trust-image has for a repository
pub fn valid_repository(repository: &str) -> bool {
    static CELL: OnceLock<Regex> = OnceLock::new();
    regex(&CELL, REPOSITORY).is_match(repository)
}

/// Amethystora's own repositories, which keep Amethystora's key, as amethystora-trust-image has them
pub fn own_repository(image_info: &str) -> Option<String> {
    let info: Value = serde_json::from_str(image_info).ok()?;
    let vendor = text(info.get("image-vendor"))?;
    Some(format!("ghcr.io/{vendor}"))
}

/// Trusting a repository with the key picked in a file dialog. `own` is Amethystora's own repository.
pub fn trust_image(list: Option<&List>, repository: &str, own: Option<&str>, key: Option<&Path>) -> Result<Run, Refusal> {
    let item = list.and_then(|list| list.find("trust-image")).filter(|item| item.available).ok_or(Refusal::Refused)?;
    if !valid_repository(repository) {
        return Err(Refusal::Repository);
    }
    if own.is_some_and(|own| repository == own || repository.starts_with(&format!("{own}/"))) {
        return Err(Refusal::OwnRepository);
    }
    // A path that is not text cannot be handed on as it is: as if none had been chosen
    let Some(key) = key.filter(|key| key.exists()).and_then(Path::to_str) else {
        return Err(Refusal::NoKey);
    };
    filled(item.command.as_ref(), item.terminal, &[("{repository}", repository), ("{key}", key)])
}

// --- The setup file ---------------------------------------------------------------------------------------

/// The setup file saved here, or applied in a terminal, where `ame setup apply` shows what it adds first
pub fn setup(list: Option<&List>, action: &str) -> Result<Run, Refusal> {
    let item = list.and_then(|list| list.first_of_kind("setup")).ok_or(Refusal::Refused)?;
    match item.commands.get(action) {
        Some(command) if item.available => runnable(command.command.as_ref(), command.terminal),
        _ => Err(Refusal::Refused),
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

    fn argv(run: Result<Run, Refusal>) -> Vec<String> {
        run.expect("allowed").argv
    }

    #[test]
    fn reads_the_list_leniently() {
        let list = list();
        assert_eq!(list.automatic_updates.as_deref(), Some("on"));
        assert!(list.backups);
        assert_eq!(list.items.len(), 10);
        let greeting = list.find("greeting").unwrap();
        assert_eq!(greeting.choices[1].terminal, true);
        assert_eq!(greeting.group, None);
        // A command with something other than words in it is never run
        assert_eq!(list.find("bad").unwrap().command, None);
        let widgets = list.find("widgets").unwrap();
        assert_eq!(widgets.widgets[1].name, None);
        assert!(widgets.widgets[1].broken);
        assert!(!widgets.bar);
        assert_eq!(list.find("setup-file").unwrap().saved, Some(1760000000.0));
        assert!(parse_list("not json").is_none());
        assert!(parse_list("{}").unwrap().items.is_empty());
    }

    #[test]
    fn changes_only_to_what_the_list_offers() {
        let list = list();
        assert_eq!(argv(change(Some(&list), "greeting", "off")), ["ame", "desktop", "greeting", "off"]);
        assert!(change(Some(&list), "greeting", "on").unwrap().terminal == false);
        assert_eq!(change(Some(&list), "greeting", "maybe"), Err(Refusal::Refused));
        // Not available here
        assert!(change(Some(&list), "gaming", "on").is_err());
        assert!(change(Some(&list), "nothing", "on").is_err());
        assert!(change(None, "greeting", "on").is_err());
        assert_eq!(argv(act(Some(&list), "cli")), ["ame", "apps", "cli"]);
        assert!(act(Some(&list), "greeting").is_err());
        assert!(act(Some(&list), "bad").is_err());
    }

    #[test]
    fn sliders_take_numbers_in_range() {
        let list = list();
        assert_eq!(argv(change(Some(&list), "transition-length", "1500")), ["ame", "desktop", "transition", "grow", "1500"]);
        assert_eq!(argv(change(Some(&list), "transition-length", "0300")), ["ame", "desktop", "transition", "grow", "300"]);
        for bad in ["100", "5001", "-300", "1e3", "12.5", "", "1234567890", " 300", "300 "] {
            assert!(change(Some(&list), "transition-length", bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn widgets_by_the_lists_names() {
        let list = list();
        assert_eq!(argv(widget(Some(&list), "on", "pomodoro")), ["ame", "desktop", "widgets", "on", "pomodoro"]);
        assert!(widget(Some(&list), "on", "weather").is_err());
        assert_eq!(argv(widget(Some(&list), "restart", "")), ["ame", "desktop", "widgets", "restart"]);
        // The agent's commands only while the agentic features are on, and new only through new_widget
        assert!(widget(Some(&list), "fix", "pomodoro").is_err());
        assert!(widget(Some(&list), "new", "x").is_err());
        assert!(widget(Some(&list), "off", "pomodoro").is_err());
        assert_eq!(argv(new_widget(Some(&list), "my-clock", "hello")), ["ame", "desktop", "widgets", "new", "my-clock", "hello"]);
        assert_eq!(new_widget(Some(&list), "my-clock", "elsewhere"), Err(Refusal::Refused));
        for bad in ["My-clock", "-clock", "pomodoro", "a b", "", "clock;rm", &"a".repeat(41)] {
            assert_eq!(new_widget(Some(&list), bad, "hello"), Err(Refusal::WidgetName), "{bad}");
        }
        assert!(new_widget(Some(&list), &"a".repeat(40), "hello").is_ok());
    }

    #[test]
    fn web_apps_pools_and_setup() {
        let list = list();
        assert_eq!(argv(webapp(Some(&list), "remove", "Element")), ["ame", "apps", "webapps", "remove", "Element"]);
        assert!(webapp(Some(&list), "remove", "Other").is_err());
        assert!(webapp(Some(&list), "install", "").unwrap().terminal);
        assert!(webapp(Some(&list), "rename", "Element").is_err());
        assert_eq!(argv(pool(Some(&list), "forget", "media")), ["ame", "system", "raid", "forget", "media"]);
        assert!(pool(Some(&list), "forget", "archive").is_err());
        assert!(pool(Some(&list), "erase", "media").is_err());
        assert_eq!(argv(setup(Some(&list), "save")), ["ame", "setup", "save"]);
        assert!(setup(Some(&list), "apply").unwrap().terminal);
        assert!(setup(Some(&list), "remove").is_err());
    }

    #[test]
    fn repositories_as_the_helper_takes_them() {
        for good in ["ghcr.io/you/your-image", "registry.example.com:5000/a/b", "localhost:5000/x", "quay.io/a_b/c__d/e--f"] {
            assert!(valid_repository(good), "{good}");
        }
        for bad in ["ghcr.io/you/image:stable", "ghcr.io/You/image", "ghcr.io", "you/your-image", "ghcr.io/you/image@sha256:00",
            "ghcr.io/you/-image", "ghcr.io//image", "-ghcr.io/you/image"] {
            assert!(!valid_repository(bad), "{bad}");
        }
        assert_eq!(own_repository(r#"{"image-vendor": "iarsslen"}"#).as_deref(), Some("ghcr.io/iarsslen"));
        assert_eq!(own_repository(r#"{"image-vendor": ""}"#), None);
        assert_eq!(own_repository("nope"), None);
    }

    #[test]
    fn trusts_only_with_a_key_and_not_amethystoras_own() {
        let list = list();
        let key = std::env::temp_dir().join("amethystora-control-core-test-cosign.pub");
        std::fs::write(&key, "key").unwrap();
        let own = Some("ghcr.io/iarsslen");
        let run = trust_image(Some(&list), "ghcr.io/you/image", own, Some(&key)).unwrap();
        assert!(run.terminal);
        assert_eq!(run.argv, ["ame", "system", "trust-image", "ghcr.io/you/image", key.to_str().unwrap()]);
        assert_eq!(trust_image(Some(&list), "ghcr.io/iarsslen/amethystora", own, Some(&key)), Err(Refusal::OwnRepository));
        assert!(trust_image(Some(&list), "ghcr.io/iarsslen", own, Some(&key)).is_err());
        assert!(trust_image(Some(&list), "ghcr.io/iarsslenx/image", own, Some(&key)).is_ok());
        assert_eq!(trust_image(Some(&list), "ghcr.io/you/image:tag", own, Some(&key)), Err(Refusal::Repository));
        assert_eq!(trust_image(Some(&list), "ghcr.io/you/image", own, None), Err(Refusal::NoKey));
        assert!(trust_image(Some(&list), "ghcr.io/you/image", own, Some(Path::new("/nonexistent/cosign.pub"))).is_err());
        let _ = std::fs::remove_file(key);
    }
}
