//! The tasks, as notes.js drew them: the inbox, today, the days to come, the pinned and the completed ones,
//! each project with its sections and each label; the quick add, which takes dates, times, repeats,
//! priorities, labels and projects out of what is typed; and the open task beside the list. The list is a
//! gtk::ListView of the page's rows (heads, tasks and the fields to add one), so that only those in sight are
//! made, however many tasks there are.

use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;
use std::time::Duration;

use regex::Regex;
use serde_json::{json, Map, Value};

use amethystora_ui::{gdk, glib, gtk, i18n, t, ui};
use gtk::prelude::*;

use super::sidebar::sort_by_title;
use super::widgets::{self, button, icon_button, item, link_button, menu, select, toast, Entry};
use super::{color_label, Notes, View, COLORS};
use crate::data::{self, Fields, Kind};
use crate::dates;
use crate::icons::icon;
use crate::layout::{Exact, Flex, Grow};

/// The reminders a task can have: minutes before it is due
fn reminders() -> Vec<(Option<i64>, String)> {
    let mut list = vec![(None, t!("No reminder")), (Some(0), t!("At the time"))];
    for count in [5, 15, 30] {
        list.push((Some(count), t!("{count, plural, one {# minute before} other {# minutes before}}", count = count)));
    }
    list.push((Some(60), t!("{count, plural, one {# hour before} other {# hours before}}", count = 1)));
    list.push((Some(1440), t!("{count, plural, one {# day before} other {# days before}}", count = 1)));
    list
}

/// The units a task repeats in, and what the repeat menu says for each: "Every week", "Every 2 weeks"
fn unit_label(unit: &str, count: f64) -> String {
    match unit {
        "day" => t!("{count, plural, =1 {Every day} other {Every # days}}", count = count),
        "week" => t!("{count, plural, =1 {Every week} other {Every # weeks}}", count = count),
        "month" => t!("{count, plural, =1 {Every month} other {Every # months}}", count = count),
        _ => t!("{count, plural, =1 {Every year} other {Every # years}}", count = count),
    }
}

fn priority_label(level: i64) -> String {
    match level {
        1 => t!("Priority 1"),
        2 => t!("Priority 2"),
        3 => t!("Priority 3"),
        _ => t!("No priority"),
    }
}

/// A group of the view, with what a task added to it gets
#[derive(Clone, Default)]
pub struct Group {
    title: Option<String>,
    tasks: Vec<Value>,
    context: Option<Map<String, Value>>,
    tone: Option<&'static str>,
    section: Option<Value>,
    nest: bool,
    quiet: bool,
}

/// What one place in the list shows
#[derive(Clone)]
enum Slot {
    /// The title, and the field to add a task
    Head,
    GroupHead(usize, usize),
    Task { id: String, depth: usize, group: usize, first: bool },
    Quick(usize),
    DoneToggle(usize),
    Done { id: String, first: bool },
    Empty,
}

/// The panes of the tasks, kept across renders
pub struct Parts {
    pub layout: gtk::Box,
    model: gtk::StringList,
    list: gtk::ListView,
    scroller: gtk::ScrolledWindow,
    slots: Rc<RefCell<Vec<(Slot, bool, bool)>>>,
    groups: RefCell<Vec<Group>>,
    detail_column: Exact,
    detail: gtk::Box,

    /// The quick add to give the focus to once its row is made again: "first", or a group's context
    refocus: RefCell<Option<String>>,
    refresh: RefCell<Option<glib::SourceId>>,
}

/// taskOrder(): by date, time, priority, order and when it was added
pub fn task_order(a: &Value, b: &Value) -> std::cmp::Ordering {
    use std::cmp::Ordering::Equal;
    let text = |v: &Value, name: &str, empty: &str| v.opt(name).map(str::to_string).unwrap_or_else(|| empty.to_string());
    let number = |v: &Value, name: &str, empty: f64| v.num(name).filter(|n| *n != 0.0 && !n.is_nan()).unwrap_or(empty);
    text(a, "due", "9999")
        .cmp(&text(b, "due", "9999"))
        .then_with(|| text(a, "time", "99").cmp(&text(b, "time", "99")))
        .then_with(|| number(a, "priority", 4.0).partial_cmp(&number(b, "priority", 4.0)).unwrap_or(Equal))
        .then_with(|| a.num_or_zero("order").partial_cmp(&b.num_or_zero("order")).unwrap_or(Equal))
        .then_with(|| a.num_or_zero("created").partial_cmp(&b.num_or_zero("created")).unwrap_or(Equal))
}

fn context_key(context: &Map<String, Value>) -> String {
    Value::Object(context.clone()).to_string()
}

/// The words of the quick add taken out of the title, as a ` text ` with every match replaced by a space
struct Taking {
    title: String,
}

impl Taking {
    /// The first match of `pattern` (which starts with \s) followed by white space, given to `use_it`; when
    /// it answers false the match stays, as String.replace did with the match given back
    fn take(&mut self, pattern: &Regex, global: bool, mut use_it: impl FnMut(&regex::Captures) -> bool) {
        let mut at = 0;
        loop {
            let Some(found) = pattern.captures_at(&self.title, at) else { return };
            let whole = found.get(0).expect("a match");
            // (?=\s): what follows the match has to be white space
            if !self.title[whole.end()..].starts_with(char::is_whitespace) {
                // Not here: try again from the next character
                at = whole.start() + self.title[whole.start()..].chars().next().map(char::len_utf8).unwrap_or(1);
                continue;
            }
            let (start, end) = (whole.start(), whole.end());
            if use_it(&found) {
                self.title.replace_range(start..end, " ");
                at = start + 1;
            } else {
                at = end;
            }
            if !global {
                return;
            }
        }
    }
}

impl Notes {
    // --- What is shown -----------------------------------------------------------------------------------

    pub fn open_tasks(&self) -> Vec<Value> {
        self.db(|store| store.values(Kind::Tasks).filter(|t| !t.is("done")).cloned().collect()).unwrap_or_default()
    }

    fn subtasks_of(&self, id: &str) -> Vec<Value> {
        self.db(|store| store.values(Kind::Tasks).filter(|t| t.opt("parent") == Some(id)).cloned().collect()).unwrap_or_default()
    }

    /// The tasks whose parent is not among them
    fn roots(&self, list: &[Value]) -> Vec<Value> {
        let ids: HashSet<&str> = list.iter().map(|t| t.id()).collect();
        list.iter()
            .filter(|task| match task.opt("parent") {
                None => true,
                Some(parent) => !self.db(|s| s.has(Kind::Tasks, parent)).unwrap_or(false) || !ids.contains(parent),
            })
            .cloned()
            .collect()
    }

    fn task_search(&self) -> Vec<Value> {
        let words: Vec<String> = self.ui.borrow().query.to_lowercase().split_whitespace().map(str::to_string).collect();
        self.db(|store| {
            store
                .values(Kind::Tasks)
                .filter(|task| {
                    let labels: Vec<String> = task.list("labels").iter().map(|id| store.get(Kind::Labels, id).map(|l| data::text(l.get("title"))).unwrap_or_default()).collect();
                    let text = format!("{}\n{}\n{}", data::text(task.get("title")), data::text(task.get("notes")), labels.join(" ")).to_lowercase();
                    words.iter().all(|word| text.contains(word.as_str()))
                })
                .cloned()
                .collect()
        })
        .unwrap_or_default()
    }

    fn task_groups(&self, view: &View) -> Vec<Group> {
        let now = dates::today();
        let mut open = self.open_tasks();
        let sorted = |mut list: Vec<Value>| {
            list.sort_by(task_order);
            list
        };
        let by_done = |mut list: Vec<Value>| {
            list.sort_by(|a, b| b.num_or_zero("done").partial_cmp(&a.num_or_zero("done")).unwrap_or(std::cmp::Ordering::Equal));
            list
        };
        let context = |pairs: Value| pairs.as_object().cloned();
        if !self.ui.borrow().query.is_empty() {
            let found = self.task_search();
            return [
                Group { title: Some(t!("To do")), tasks: sorted(found.iter().filter(|t| !t.is("done")).cloned().collect()), ..Default::default() },
                Group { title: Some(t!("Completed")), tasks: by_done(found.iter().filter(|t| t.is("done")).cloned().collect()), ..Default::default() },
            ]
            .into_iter()
            .filter(|group| !group.tasks.is_empty())
            .collect();
        }
        match view.kind.as_str() {
            "inbox" => vec![Group { tasks: sorted(open.into_iter().filter(|t| !t.is("project")).collect()), nest: true, context: context(json!({ "project": null })), ..Default::default() }],
            "today" => {
                let overdue = sorted(open.iter().filter(|t| t.opt("due").is_some_and(|d| d < now.as_str())).cloned().collect());
                let today = sorted(open.into_iter().filter(|t| t.opt("due") == Some(now.as_str())).collect());
                let mut groups = Vec::new();
                let has_overdue = !overdue.is_empty();
                if has_overdue {
                    groups.push(Group { title: Some(t!("Overdue")), tone: Some("bad"), tasks: overdue, ..Default::default() });
                }
                groups.push(Group { title: has_overdue.then(|| dates::day_label(&now, true)), tasks: today, context: context(json!({ "due": now })), ..Default::default() });
                groups
            }
            "upcoming" => {
                let mut days: Vec<(String, Vec<Value>)> = (1..=7).map(|day| (dates::add_days(&now, day), Vec::new())).collect();
                open.sort_by(task_order);
                for task in open.into_iter().filter(|t| t.opt("due").is_some_and(|d| d > now.as_str())) {
                    let due = task.str("due").to_string();
                    match days.iter_mut().find(|(day, _)| *day == due) {
                        Some((_, list)) => list.push(task),
                        None => days.push((due, vec![task])),
                    }
                }
                days.sort_by(|a, b| a.0.cmp(&b.0));
                days.into_iter()
                    .map(|(date, tasks)| Group { title: Some(dates::day_label(&date, true)), quiet: tasks.is_empty(), tasks, context: context(json!({ "due": date })), ..Default::default() })
                    .collect()
            }
            "pinned" => vec![Group { tasks: sorted(open.into_iter().filter(|t| t.is("pinned")).collect()), context: context(json!({ "pinned": true })), ..Default::default() }],
            "completed" => {
                let done = by_done(self.db(|store| store.values(Kind::Tasks).filter(|t| t.is("done")).cloned().collect()).unwrap_or_default());
                let mut days: Vec<(String, Vec<Value>)> = Vec::new();
                for task in done.into_iter().take(300) {
                    let day = dates::iso_of_ms(task.num_or_zero("done"));
                    match days.iter_mut().find(|(d, _)| *d == day) {
                        Some((_, list)) => list.push(task),
                        None => days.push((day, vec![task])),
                    }
                }
                days.into_iter().map(|(day, tasks)| Group { title: Some(dates::day_label(&day, true)), tasks, ..Default::default() }).collect()
            }
            "label" => {
                let id = view.id.clone().unwrap_or_default();
                vec![Group { tasks: sorted(open.into_iter().filter(|t| t.list("labels").contains(&id)).collect()), context: context(json!({ "labels": [id] })), ..Default::default() }]
            }
            "project" => {
                let id = view.id.clone().unwrap_or_default();
                let own: Vec<Value> = open.into_iter().filter(|t| t.opt("project") == Some(id.as_str())).collect();
                let mut sections: Vec<Value> = self.db(|store| store.values(Kind::Sections).filter(|s| s.opt("project") == Some(id.as_str())).cloned().collect()).unwrap_or_default();
                sections.sort_by(|a, b| a.num_or_zero("order").partial_cmp(&b.num_or_zero("order")).unwrap_or(std::cmp::Ordering::Equal));
                let known: HashSet<String> = sections.iter().map(|s| s.id().to_string()).collect();
                let mut groups = vec![Group {
                    tasks: sorted(own.iter().filter(|t| !known.contains(t.str("section"))).cloned().collect()),
                    nest: true,
                    context: context(json!({ "project": id, "section": null })),
                    ..Default::default()
                }];
                for section in sections {
                    let title = if section.title().is_empty() { t!("Untitled") } else { section.title().to_string() };
                    groups.push(Group {
                        title: Some(title),
                        nest: true,
                        tasks: sorted(own.iter().filter(|t| t.str("section") == section.id()).cloned().collect()),
                        context: context(json!({ "project": id, "section": section.id() })),
                        section: Some(section),
                        ..Default::default()
                    });
                }
                groups
            }
            _ => Vec::new(),
        }
    }

    fn tasks_title(&self) -> String {
        if !self.ui.borrow().query.is_empty() {
            return t!("Search");
        }
        let view = self.ui.borrow().tasks_view.clone();
        match view.kind.as_str() {
            "project" => self.item(Kind::Projects, view.id.as_deref().unwrap_or("")).map(|p| p.title().to_string()).filter(|t| !t.is_empty()).unwrap_or_else(|| t!("Untitled")),
            "label" => self.item(Kind::Labels, view.id.as_deref().unwrap_or("")).map(|l| l.title().to_string()).unwrap_or_default(),
            "inbox" => t!("Inbox"),
            "today" => t!("Today"),
            "upcoming" => t!("Upcoming"),
            "pinned" => t!("Pinned"),
            "completed" => t!("Completed"),
            _ => String::new(),
        }
    }

    // --- Changing tasks ----------------------------------------------------------------------------------

    fn new_task(&self, fields: Map<String, Value>) -> String {
        let now = data::ms(data::now_ms());
        let mut task = json!({
            "id": data::new_id(), "title": "", "notes": "", "project": null, "section": null, "parent": null, "due": null, "time": null,
            "repeat": null, "reminder": null, "priority": 4, "labels": [], "pinned": false, "done": null, "created": now, "order": now,
        });
        data::assign(&mut task, &fields);
        let id = task.id().to_string();
        self.insert(Kind::Tasks, task, true);
        id
    }

    /// "Call Sam tomorrow 5pm p1 @phone #Work every week": the words it knows are taken out of the title.
    /// They are English whatever the window's language is.
    pub fn parse_quick(&self, text: &str) -> Map<String, Value> {
        thread_local! {
            static PATTERNS: [Regex; 7] = [
                Regex::new(r"\s[pP]([1-4])").expect("a pattern"),
                Regex::new(r"\s(?:(?:[eE][vV][eE][rR][yY])\s+([0-9]+\s+)?((?:[dD][aA][yY])|(?:[wW][eE][eE][kK])|(?:[mM][oO][nN][tT][hH])|(?:[yY][eE][aA][rR]))[sS]?|((?:[dD][aA][iI][lL][yY])|(?:[wW][eE][eE][kK][lL][yY])|(?:[mM][oO][nN][tT][hH][lL][yY])|(?:[yY][eE][aA][rR][lL][yY])))").expect("a pattern"),
                Regex::new(r"\s#([\w-]+)").expect("a pattern"),
                Regex::new(r"\s@([\w-]+)").expect("a pattern"),
                Regex::new(r"\s((?i-u:today|tod|tonight|tomorrow|tmr|next week)|(?i-u:(?:on\s+)?(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*)|[0-9]{4}-[0-9]{2}-[0-9]{2})").expect("a pattern"),
                Regex::new(r"\s(?:(?i-u:at)\s+)?([0-9]{1,2})(?::([0-9]{2}))?\s*((?i-u:am|pm))").expect("a pattern"),
                Regex::new(r"\s(?:at\s+)?([01]?[0-9]|2[0-3]):([0-5][0-9])").expect("a pattern"),
            ];
        }
        let mut taking = Taking { title: format!(" {text} ") };
        let mut found = Map::new();
        let now = dates::today();
        PATTERNS.with(|p| {
            taking.take(&p[0], false, |m| {
                found.insert("priority".into(), Value::from(m[1].parse::<i64>().unwrap_or(4)));
                true
            });
            taking.take(&p[1], false, |m| {
                let every = m.get(1).and_then(|c| c.as_str().trim().parse::<i64>().ok()).filter(|n| *n != 0).unwrap_or(1);
                let unit = match (m.get(2), m.get(3)) {
                    (Some(unit), _) => unit.as_str().to_lowercase(),
                    (None, Some(adverb)) => match adverb.as_str().to_lowercase().as_str() {
                        "daily" => "day".into(),
                        "weekly" => "week".into(),
                        "monthly" => "month".into(),
                        _ => "year".into(),
                    },
                    _ => "day".into(),
                };
                found.insert("repeat".into(), json!({ "every": every, "unit": unit }));
                true
            });
            taking.take(&p[2], false, |m| {
                let key = m[1].to_lowercase();
                let project = self.db(|store| store.values(Kind::Projects).find(|p| p.title().split_whitespace().collect::<String>().to_lowercase() == key).map(|p| p.id().to_string())).flatten();
                match project {
                    Some(project) => {
                        found.insert("project".into(), Value::from(project));
                        found.insert("section".into(), Value::Null);
                        true
                    }
                    None => false,
                }
            });
            let mut labels: Vec<Value> = Vec::new();
            taking.take(&p[3], true, |m| {
                labels.push(Value::from(self.label_for(&m[1])));
                true
            });
            if !labels.is_empty() {
                found.insert("labels".into(), Value::Array(labels));
            }
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
            taking.take(&p[4], false, |m| {
                let lower = m[1].to_lowercase();
                let lower = match lower.strip_prefix("on") {
                    Some(rest) if rest.starts_with(char::is_whitespace) => rest.trim_start().to_string(),
                    _ => lower,
                };
                let due = if dates::is_iso(&lower) {
                    lower.clone()
                } else if ["today", "tod", "tonight"].contains(&lower.as_str()) {
                    now.clone()
                } else if ["tomorrow", "tmr"].contains(&lower.as_str()) {
                    dates::add_days(&now, 1)
                } else if lower == "next week" {
                    dates::add_days(&now, 7 - ((dates::weekday_now() + 6) % 7))
                } else {
                    let three: String = lower.chars().take(3).collect();
                    let Some(day) = weekdays.iter().position(|name| name.starts_with(&three)) else { return false };
                    if lower.len() > 3 && !weekdays[day].starts_with(&lower) {
                        return false;
                    }
                    let ahead = (day as i64 - dates::weekday_now() + 7) % 7;
                    dates::add_days(&now, if ahead == 0 { 7 } else { ahead })
                };
                found.insert("due".into(), Value::from(due));
                true
            });
            taking.take(&p[5], false, |m| {
                let hours = m[1].parse::<i64>().unwrap_or(0);
                let hour = hours % 12 + if m[3].to_lowercase() == "pm" { 12 } else { 0 };
                let minutes = m.get(2).map(|c| c.as_str().to_string()).unwrap_or_else(|| "00".into());
                found.insert("time".into(), Value::from(format!("{hour:02}:{minutes}")));
                true
            });
            taking.take(&p[6], false, |m| {
                let hours = m[1].parse::<i64>().unwrap_or(0);
                found.insert("time".into(), Value::from(format!("{hours:02}:{}", &m[2])));
                true
            });
        });
        if (found.contains_key("time") || found.contains_key("repeat")) && !found.contains_key("due") {
            let late = found.get("time").and_then(Value::as_str).is_some_and(|time| time < dates::time_now().as_str());
            let due = if late && !found.contains_key("repeat") { dates::add_days(&dates::today(), 1) } else { dates::today() };
            found.insert("due".into(), Value::from(due));
        }
        if found.contains_key("time") {
            found.insert("reminder".into(), Value::from(0));
        }
        let title = taking.title.split_whitespace().collect::<Vec<_>>().join(" ");
        found.insert("title".into(), Value::from(if title.is_empty() { text.trim().to_string() } else { title }));
        found
    }

    /// The label of this name, made when there is none, in the next of the colours
    fn label_for(&self, title: &str) -> String {
        let lower = title.to_lowercase();
        if let Some(found) = self.db(|store| store.values(Kind::Labels).find(|l| data::text(l.get("title")).to_lowercase() == lower).map(|l| l.id().to_string())).flatten() {
            return found;
        }
        let count = self.db(|store| store.kind(Kind::Labels).len()).unwrap_or(0);
        let id = data::new_id();
        self.insert(Kind::Labels, json!({ "id": id, "title": title, "color": COLORS[count % COLORS.len()] }), true);
        id
    }

    /// The next date of a repeating task, past today when it has fallen behind
    fn next_due(task: &Value) -> String {
        let repeat = task.get("repeat").cloned().unwrap_or(Value::Null);
        let every = repeat.num_or_zero("every").max(1.0) as i64;
        let unit = data::text(repeat.get("unit"));
        let today = dates::today();
        let mut due = dates::add_interval(task.str("due"), every, &unit);
        let mut guard = 0;
        while due < today && guard < 1000 {
            due = dates::add_interval(&due, every, &unit);
            guard += 1;
        }
        due
    }

    fn toggle_done(&self, id: &str) {
        let Some(task) = self.item(Kind::Tasks, id) else { return };
        let before = task.as_object().cloned().unwrap_or_default();
        let id = id.to_string();
        if !task.is("done") && task.is("repeat") && task.is("due") {
            let due = Self::next_due(&task);
            let mut changes = Map::new();
            changes.insert("due".into(), Value::from(due.clone()));
            self.save_task(&id, changes, true);
            let weak = self.me.clone();
            toast(&t!("Done. Next on {day}.", day = dates::day_label(&due, false)), Some(Rc::new(move || {
                if let Some(this) = weak.upgrade() {
                    this.save_task(&id, before.clone(), true);
                    this.render_tasks(false);
                }
            })));
        } else if !task.is("done") {
            let changed: Vec<String> = self.subtasks_of(&id).into_iter().filter(|c| !c.is("done")).map(|c| c.id().to_string()).collect();
            for child in &changed {
                let mut changes = Map::new();
                changes.insert("done".into(), data::ms(data::now_ms()));
                self.save_task(child, changes, false);
            }
            let mut changes = Map::new();
            changes.insert("done".into(), data::ms(data::now_ms()));
            self.save_task(&id, changes, true);
            let title = if task.title().is_empty() { t!("Untitled") } else { task.title().to_string() };
            let weak = self.me.clone();
            toast(&t!("Completed “{task}”", task = title), Some(Rc::new(move || {
                if let Some(this) = weak.upgrade() {
                    let mut changes = Map::new();
                    changes.insert("done".into(), Value::Null);
                    this.save_task(&id, changes.clone(), true);
                    for child in &changed {
                        this.save_task(child, changes.clone(), false);
                    }
                    this.render_tasks(false);
                    this.render_nav();
                }
            })));
        } else {
            let mut changes = Map::new();
            changes.insert("done".into(), Value::Null);
            self.save_task(&id, changes, true);
        }
        self.render_nav();
        self.render_tasks(false);
    }

    fn delete_task(&self, id: &str) {
        let Some(task) = self.item(Kind::Tasks, id) else { return };
        let mut gone = vec![task.clone()];
        gone.extend(self.subtasks_of(id));
        let ids: Vec<String> = gone.iter().map(|t| t.id().to_string()).collect();
        self.remove(Kind::Tasks, &ids);
        if self.ui.borrow().task.as_ref().is_some_and(|open| ids.contains(open)) {
            self.ui.borrow_mut().task = None;
        }
        self.render_nav();
        self.render_tasks(true);
        let title = if task.title().is_empty() { t!("Untitled") } else { task.title().to_string() };
        let weak = self.me.clone();
        toast(&t!("Deleted “{task}”", task = title), Some(Rc::new(move || {
            if let Some(this) = weak.upgrade() {
                for item in &gone {
                    this.insert(Kind::Tasks, item.clone(), true);
                }
                this.render_nav();
                this.render_tasks(true);
            }
        })));
    }

    pub(super) fn new_project(&self) {
        self.spawn(async |this| {
            let Some(title) = widgets::ask(&t!("New project"), &t!("Name"), "", Some(&t!("Create")), None).await else { return };
            let count = this.db(|store| store.kind(Kind::Projects).len()).unwrap_or(0);
            let now = data::ms(data::now_ms());
            let id = data::new_id();
            this.insert(Kind::Projects, json!({ "id": id, "title": title, "color": COLORS[count % COLORS.len()], "order": now, "created": now }), true);
            this.show_tasks(View::with("project", &id));
        });
    }

    fn color_items(&self, kind: Kind, item: &Value) -> Vec<Entry> {
        let current = item.str("color").to_string();
        COLORS
            .iter()
            .map(|color| {
                let (weak, id, color) = (self.me.clone(), item.id().to_string(), color.to_string());
                Entry::Item(widgets::Item {
                    label: color_label(&color),
                    glyph: None,
                    color: Some(color.clone()),
                    checked: current == color,
                    danger: false,
                    run: Rc::new(move || {
                        if let Some(this) = weak.upgrade() {
                            let mut changes = Map::new();
                            changes.insert("color".into(), Value::from(color.clone()));
                            this.update(kind, &id, &changes);
                            this.save(kind, &id, false);
                            this.render();
                        }
                    }),
                })
            })
            .collect()
    }

    pub(super) fn project_menu(&self, anchor: &gtk::Button, project: &Value) {
        let id = project.id().to_string();
        let anchor_copy = anchor.clone();
        let (rename, colour, section, delete) = (id.clone(), id.clone(), id.clone(), id);
        menu(anchor, vec![
            item(&t!("Rename"), "edit", self.on(move |this| {
                let id = rename.clone();
                this.spawn(async move |this| {
                    let current = this.item(Kind::Projects, &id).map(|p| p.title().to_string()).unwrap_or_default();
                    if let Some(title) = widgets::ask(&t!("Rename project"), &t!("Name"), &current, None, None).await {
                        let mut changes = Map::new();
                        changes.insert("title".into(), Value::from(title));
                        this.update(Kind::Projects, &id, &changes);
                        this.save(Kind::Projects, &id, false);
                        this.render();
                    }
                });
            })),
            item(&t!("Colour"), "tag", self.on(move |this| {
                if let Some(project) = this.item(Kind::Projects, &colour) {
                    menu(&anchor_copy, this.color_items(Kind::Projects, &project));
                }
            })),
            item(&t!("Add a section"), "plus", self.on(move |this| this.new_section(&section))),
            Entry::Separator,
            widgets::danger(&t!("Delete"), "trash", self.on(move |this| {
                let id = delete.clone();
                this.spawn(async move |this| {
                    let Some(project) = this.item(Kind::Projects, &id) else { return };
                    let tasks: Vec<String> = this.db(|store| store.values(Kind::Tasks).filter(|t| t.opt("project") == Some(id.as_str())).map(|t| t.id().to_string()).collect()).unwrap_or_default();
                    let sure = widgets::confirm(
                        &t!("Delete {name}?", name = project.title()),
                        &t!("{count, plural, =0 {It has no tasks.} one {Its # task is deleted with it.} other {Its # tasks are deleted with it.}}", count = tasks.len()),
                        &t!("Delete"),
                        true,
                    )
                    .await;
                    if sure {
                        this.remove(Kind::Tasks, &tasks);
                        let sections: Vec<String> = this.db(|store| store.values(Kind::Sections).filter(|s| s.opt("project") == Some(id.as_str())).map(|s| s.id().to_string()).collect()).unwrap_or_default();
                        this.remove(Kind::Sections, &sections);
                        this.remove(Kind::Projects, std::slice::from_ref(&id));
                        this.show_tasks(View::of("inbox"));
                    }
                });
            })),
        ]);
    }

    fn new_section(&self, project: &str) {
        let project = project.to_string();
        self.spawn(async move |this| {
            let name = this.item(Kind::Projects, &project).map(|p| p.title().to_string()).unwrap_or_default();
            let Some(title) = widgets::ask(&t!("New section in {project}", project = name), &t!("Name"), "", Some(&t!("Create")), None).await else { return };
            this.insert(Kind::Sections, json!({ "id": data::new_id(), "project": project, "title": title, "order": data::ms(data::now_ms()) }), true);
            this.show_tasks(View::with("project", &project));
        });
    }

    fn section_menu(&self, anchor: &gtk::Button, section: &Value) {
        let (rename, delete) = (section.id().to_string(), section.id().to_string());
        menu(anchor, vec![
            item(&t!("Rename"), "edit", self.on(move |this| {
                let id = rename.clone();
                this.spawn(async move |this| {
                    let current = this.item(Kind::Sections, &id).map(|s| s.title().to_string()).unwrap_or_default();
                    if let Some(title) = widgets::ask(&t!("Rename section"), &t!("Name"), &current, None, None).await {
                        let mut changes = Map::new();
                        changes.insert("title".into(), Value::from(title));
                        this.update(Kind::Sections, &id, &changes);
                        this.save(Kind::Sections, &id, false);
                        this.render_tasks(false);
                    }
                });
            })),
            widgets::danger(&t!("Delete"), "trash", self.on(move |this| {
                let id = delete.clone();
                this.spawn(async move |this| {
                    let name = this.item(Kind::Sections, &id).map(|s| s.title().to_string()).unwrap_or_default();
                    if widgets::confirm(&t!("Delete the section {section}?", section = name), &t!("Its tasks stay in the project."), &t!("Delete"), true).await {
                        let inside: Vec<String> = this.db(|store| store.values(Kind::Tasks).filter(|t| t.opt("section") == Some(id.as_str())).map(|t| t.id().to_string()).collect()).unwrap_or_default();
                        for task in inside {
                            let mut changes = Map::new();
                            changes.insert("section".into(), Value::Null);
                            this.save_task(&task, changes, false);
                        }
                        this.remove(Kind::Sections, std::slice::from_ref(&id));
                        this.render_tasks(false);
                    }
                });
            })),
        ]);
    }

    pub(super) fn new_label(&self) {
        self.spawn(async |this| {
            if let Some(title) = widgets::ask(&t!("New label"), &t!("Name"), "", Some(&t!("Create")), None).await {
                let id = this.label_for(&title);
                this.show_tasks(View::with("label", &id));
            }
        });
    }

    pub(super) fn label_menu(&self, anchor: &gtk::Button, label: &Value) {
        let id = label.id().to_string();
        let anchor_copy = anchor.clone();
        let (rename, colour, delete) = (id.clone(), id.clone(), id);
        menu(anchor, vec![
            item(&t!("Rename"), "edit", self.on(move |this| {
                let id = rename.clone();
                this.spawn(async move |this| {
                    let current = this.item(Kind::Labels, &id).map(|l| l.title().to_string()).unwrap_or_default();
                    if let Some(title) = widgets::ask(&t!("Rename label"), &t!("Name"), &current, None, None).await {
                        let mut changes = Map::new();
                        changes.insert("title".into(), Value::from(title));
                        this.update(Kind::Labels, &id, &changes);
                        this.save(Kind::Labels, &id, false);
                        this.render();
                    }
                });
            })),
            item(&t!("Colour"), "tag", self.on(move |this| {
                if let Some(label) = this.item(Kind::Labels, &colour) {
                    menu(&anchor_copy, this.color_items(Kind::Labels, &label));
                }
            })),
            Entry::Separator,
            widgets::danger(&t!("Delete"), "trash", self.on(move |this| {
                let id = delete.clone();
                this.spawn(async move |this| {
                    let name = this.item(Kind::Labels, &id).map(|l| l.title().to_string()).unwrap_or_default();
                    if widgets::confirm(&t!("Delete the label {label}?", label = name), &t!("The tasks stay; only the label is taken off them."), &t!("Delete"), true).await {
                        let tagged: Vec<(String, Vec<String>)> = this.db(|store| store.values(Kind::Tasks).filter(|t| t.list("labels").contains(&id)).map(|t| (t.id().to_string(), t.list("labels"))).collect()).unwrap_or_default();
                        for (task, labels) in tagged {
                            let mut changes = Map::new();
                            changes.insert("labels".into(), json!(labels.into_iter().filter(|l| *l != id).collect::<Vec<_>>()));
                            this.save_task(&task, changes, false);
                        }
                        this.remove(Kind::Labels, std::slice::from_ref(&id));
                        this.show_tasks(View::of("inbox"));
                    }
                });
            })),
        ]);
    }

    // --- The panes ---------------------------------------------------------------------------------------

    fn tasks_parts(&self) -> Parts {
        let layout = ui::hbox(0, &["tasks-layout"]);
        let model = gtk::StringList::new(&[]);
        let slots: Rc<RefCell<Vec<(Slot, bool, bool)>>> = Rc::new(RefCell::new(Vec::new()));
        let factory = gtk::SignalListItemFactory::new();
        factory.connect_setup(|_, item| {
            let Some(item) = item.downcast_ref::<gtk::ListItem>() else { return };
            item.set_activatable(false);
            item.set_focusable(false);
            let holder = ui::vbox(0, &["task-slot"]);
            let column = ui::limit_center(&holder, 820);
            item.set_child(Some(&column));
        });
        let weak = self.me.clone();
        let bound = slots.clone();
        factory.connect_bind(move |_, item| {
            let Some(item) = item.downcast_ref::<gtk::ListItem>() else { return };
            let Some(this) = weak.upgrade() else { return };
            let Some(holder) = item.child().and_then(|c| c.first_child()).and_then(|c| c.downcast::<gtk::Box>().ok()) else { return };
            let position = item.position() as usize;
            let slot = bound.borrow().get(position).cloned();
            if let Some((slot, top, bottom)) = slot {
                this.bind_task_slot(&holder, &slot, top, bottom);
            }
        });
        let selection = gtk::NoSelection::new(Some(model.clone()));
        let list = gtk::ListView::builder().model(&selection).factory(&factory).css_classes(["task-list"]).build();
        let scroller = gtk::ScrolledWindow::builder().hscrollbar_policy(gtk::PolicyType::Never).vexpand(true).hexpand(true).child(&list).build();
        let pane = ui::vbox(0, &["task-pane"]);
        pane.update_property(&[gtk::accessible::Property::Label(&t!("Tasks"))]);
        pane.set_hexpand(true);
        pane.append(&scroller);
        layout.append(&pane);
        let detail = ui::vbox(14, &["detail"]);
        let detail_scroll = gtk::ScrolledWindow::builder().hscrollbar_policy(gtk::PolicyType::Never).vexpand(true).child(&detail).build();
        let detail_pane = ui::vbox(0, &["detail-pane"]);
        detail_pane.update_property(&[gtk::accessible::Property::Label(&t!("Task"))]);
        detail_pane.append(&detail_scroll);
        let detail_column = Exact::new(&detail_pane);
        detail_column.set_hexpand(false);
        detail_column.set_visible(false);
        layout.append(&detail_column);
        Parts { layout, model, list, scroller, slots, groups: RefCell::new(Vec::new()), detail_column, detail, refocus: RefCell::new(None), refresh: RefCell::new(None) }
    }

    pub fn render_tasks(&self, force: bool) {
        let mut force = force;
        if self.tasks_parts.borrow().is_none() {
            self.tasks_parts.replace(Some(self.tasks_parts()));
        }
        let layout = self.tasks_parts.borrow().as_ref().map(|p| p.layout.clone()).expect("made");
        if self.main.first_child().as_ref() != Some(layout.upcast_ref::<gtk::Widget>()) {
            ui::clear(&self.main);
            self.main.append(&layout);
            force = true;
        }
        let task = self.ui.borrow().task.clone().filter(|id| self.db(|s| s.has(Kind::Tasks, id)).unwrap_or(false));
        if task.is_none() {
            self.ui.borrow_mut().task = None;
        }
        self.render_task_list();
        let current = self.detail_for.borrow().clone();
        if force || current.as_ref() != Some(&task) {
            self.detail_for.replace(Some(task.clone()));
            let (column, detail) = self.tasks_parts.borrow().as_ref().map(|p| (p.detail_column.clone(), p.detail.clone())).expect("made");
            column.set_visible(task.is_some());
            ui::clear(&detail);
            match &task {
                Some(id) => self.build_detail(&detail, id),
                None => {
                    self.controls_for(None);
                }
            }
        }
    }

    pub fn render_task_list(&self) {
        let parts = self.tasks_parts.borrow();
        let Some(parts) = parts.as_ref() else { return };
        let view = self.ui.borrow().tasks_view.clone();
        let query = !self.ui.borrow().query.is_empty();
        let groups = self.task_groups(&view);
        let mut slots: Vec<Slot> = vec![Slot::Head];
        let mut shown = 0;
        for (at, group) in groups.iter().enumerate() {
            let list = if group.nest { self.roots(&group.tasks) } else { group.tasks.clone() };
            let mut rows: Vec<Slot> = Vec::new();
            for task in &list {
                rows.push(Slot::Task { id: task.id().to_string(), depth: 0, group: at, first: false });
                if group.nest {
                    self.walk_subtasks(task.id(), 1, at, &mut rows);
                }
            }
            shown += list.len();
            if group.title.is_none() && rows.is_empty() {
                continue;
            }
            let quick = group.section.is_some() || (view.kind == "upcoming" && group.context.is_some());
            if group.title.is_some() {
                slots.push(Slot::GroupHead(at, list.len()));
            } else if let Some(Slot::Task { first, .. }) = rows.first_mut() {
                *first = true;
            }
            slots.extend(rows);
            if quick && !query {
                slots.push(Slot::Quick(at));
            }
        }
        // A project's and the inbox's finished tasks, out of the way until asked for
        if !query && (view.kind == "project" || view.kind == "inbox") {
            let project = if view.kind == "project" { view.id.clone() } else { None };
            let mut done: Vec<Value> = self.db(|store| store.values(Kind::Tasks).filter(|t| t.is("done") && t.opt("project").map(str::to_string) == project).cloned().collect()).unwrap_or_default();
            done.sort_by(|a, b| b.num_or_zero("done").partial_cmp(&a.num_or_zero("done")).unwrap_or(std::cmp::Ordering::Equal));
            if !done.is_empty() {
                slots.push(Slot::DoneToggle(done.len()));
                if self.ui.borrow().show_done {
                    for task in done {
                        slots.push(Slot::Done { id: task.id().to_string(), first: false });
                    }
                }
            }
        }
        if shown == 0 && view.kind != "upcoming" && view.kind != "project" {
            slots.push(Slot::Empty);
        }
        let count = slots.len();
        let marked: Vec<(Slot, bool, bool)> = slots.into_iter().enumerate().map(|(at, slot)| (slot, at == 0, at + 1 == count)).collect();
        parts.groups.replace(groups);
        let scroll = parts.scroller.vadjustment().value();
        parts.slots.replace(marked);
        let names: Vec<String> = (0..count).map(|at| at.to_string()).collect();
        let strings: Vec<&str> = names.iter().map(String::as_str).collect();
        parts.model.splice(0, parts.model.n_items(), &strings);
        let adjustment = parts.scroller.vadjustment();
        glib::idle_add_local_once(move || adjustment.set_value(scroll));
    }

    fn walk_subtasks(&self, parent: &str, depth: usize, group: usize, rows: &mut Vec<Slot>) {
        let mut children: Vec<Value> = self.subtasks_of(parent).into_iter().filter(|c| !c.is("done")).collect();
        children.sort_by(task_order);
        for child in children {
            rows.push(Slot::Task { id: child.id().to_string(), depth, group, first: false });
            if depth < 4 {
                self.walk_subtasks(child.id(), depth + 1, group, rows);
            }
        }
    }

    /// One place of the list, drawn for what it now shows
    fn bind_task_slot(&self, holder: &gtk::Box, slot: &Slot, top: bool, bottom: bool) {
        ui::clear(holder);
        holder.set_css_classes(&["task-slot"]);
        widgets::set_class(holder, "top", top);
        widgets::set_class(holder, "bottom", bottom);
        let groups = self.tasks_parts.borrow().as_ref().map(|p| p.groups.borrow().clone()).unwrap_or_default();
        let gap = (22.0 * amethystora_ui::icon::zoom()).round() as i32;
        match slot {
            Slot::Head => holder.append(&self.tasks_head()),
            Slot::GroupHead(at, count) => {
                let Some(group) = groups.get(*at) else { return };
                let head = ui::hbox(8, &["group-head"]);
                if let Some(tone) = group.tone {
                    head.add_css_class(tone);
                }
                let words = ui::hbox(0, &["grow"]);
                words.set_hexpand(true);
                let title = ui::line(group.title.as_deref().unwrap_or(""), &["h2"]);
                title.set_valign(gtk::Align::Baseline);
                words.append(&title);
                // The count of what is in it, but not of a day or a section with nothing in it yet
                if *count > 0 {
                    let number = ui::line(&format!(" {}", i18n::number(*count as f64)), &["h2", "faint"]);
                    number.set_valign(gtk::Align::Baseline);
                    words.append(&number);
                }
                if group.quiet {
                    title.add_css_class("faint");
                }
                head.append(&words);
                if let Some(section) = group.section.clone() {
                    let weak = self.me.clone();
                    head.append(&icon_button("more", &t!("More"), &[], move |anchor| {
                        if let Some(this) = weak.upgrade() {
                            this.section_menu(anchor, &section);
                        }
                    }));
                }
                head.set_margin_top(gap);
                holder.append(&head);
            }
            Slot::Task { id, depth, group, first } => {
                let Some(task) = self.item(Kind::Tasks, id) else { return };
                let nest = groups.get(*group).is_some_and(|g| g.nest);
                let row = self.task_row(&task, *depth, nest);
                if *first {
                    row.set_margin_top(gap);
                }
                holder.append(&row);
            }
            Slot::Quick(at) => {
                let Some(context) = groups.get(*at).and_then(|g| g.context.clone()) else { return };
                holder.append(&self.quick_add(context, false));
            }
            Slot::DoneToggle(count) => {
                let label = if self.ui.borrow().show_done {
                    t!("{count, plural, one {Hide # completed task} other {Hide # completed tasks}}", count = *count)
                } else {
                    t!("{count, plural, one {Show # completed task} other {Show # completed tasks}}", count = *count)
                };
                let link = link_button(&label, Some("done"), &["quiet", "small"], self.on(|this| {
                    let show = !this.ui.borrow().show_done;
                    this.ui.borrow_mut().show_done = show;
                    this.render_tasks(false);
                }));
                link.set_focus_on_click(false);
                link.set_margin_top(gap);
                holder.append(&link);
            }
            Slot::Done { id, first } => {
                let Some(task) = self.item(Kind::Tasks, id) else { return };
                let row = self.task_row(&task, 0, false);
                if *first {
                    row.set_margin_top(gap);
                }
                holder.append(&row);
            }
            Slot::Empty => {
                let view = self.ui.borrow().tasks_view.clone();
                let query = !self.ui.borrow().query.is_empty();
                let empty = ui::vbox(12, &["task-empty", "after-head"]);
                let glyph = if query { "search" } else if view.kind == "completed" { "done" } else { "mark-ok" };
                empty.append(&icon(glyph, 36));
                let text = if query {
                    t!("No task has all of those words.")
                } else {
                    match view.kind.as_str() {
                        "today" => t!("Nothing due today."),
                        "inbox" => t!("Your inbox is empty."),
                        "pinned" => t!("Pin a task to keep it here."),
                        "completed" => t!("Nothing completed yet."),
                        _ => t!("No task has this label."),
                    }
                };
                let words = ui::label(&text, &[]);
                words.set_xalign(0.5);
                empty.append(&words);
                holder.append(&empty);
            }
        }
    }

    fn tasks_head(&self) -> gtk::Widget {
        let view = self.ui.borrow().tasks_view.clone();
        let query = !self.ui.borrow().query.is_empty();
        let project = if view.kind == "project" { self.item(Kind::Projects, view.id.as_deref().unwrap_or("")) } else { None };
        let column = ui::vbox(0, &[]);
        let head = ui::hbox(12, &["tasks-head"]);
        if let Some(project) = &project {
            head.append(&widgets::dot(project.opt("color").unwrap_or("violet"), &["big"]));
        }
        let words = ui::vbox(0, &["grow"]);
        words.set_hexpand(true);
        words.append(&ui::label(&self.tasks_title(), &["h1"]));
        if view.kind == "today" && !query {
            words.append(&ui::label(&dates::today_long(), &["faint", "small"]));
        }
        head.append(&words);
        if let Some(project) = &project {
            let id = project.id().to_string();
            let section = button(&t!("Section"), Some("plus"), &["small"], self.on(move |this| this.new_section(&id)));
            section.set_valign(gtk::Align::Center);
            head.append(&section);
            let menu_project = project.clone();
            let weak = self.me.clone();
            head.append(&icon_button("more", &t!("More"), &[], move |anchor| {
                if let Some(this) = weak.upgrade() {
                    this.project_menu(anchor, &menu_project);
                }
            }));
        }
        column.append(&head);
        let addable = !query && view.kind != "completed";
        if addable {
            let groups = self.tasks_parts.borrow().as_ref().map(|p| p.groups.borrow().clone()).unwrap_or_default();
            let context = if view.kind == "upcoming" {
                json!({ "due": dates::add_days(&dates::today(), 1) }).as_object().cloned().unwrap_or_default()
            } else {
                groups.iter().find_map(|g| g.context.clone()).unwrap_or_default()
            };
            column.append(&self.quick_add(context, true));
        }
        column.upcast()
    }

    /// The field to add a task, with what the tasks added there get
    fn quick_add(&self, context: Map<String, Value>, first: bool) -> gtk::Widget {
        let input = gtk::Entry::builder().css_classes(["plain", "quick-input"]).hexpand(true).placeholder_text(if first { t!("Add a task") } else { t!("Add a task here") }).build();
        input.update_property(&[gtk::accessible::Property::Label(&t!("Add a task"))]);
        let form = ui::hbox(10, &["quick"]);
        widgets::set_class(&form, if first { "first" } else { "later" }, true);
        let plus = icon("plus", 18);
        plus.add_css_class("quick-plus");
        form.append(&plus);
        form.append(&input);
        let key = if first { "first".to_string() } else { context_key(&context) };
        let weak = self.me.clone();
        let (submitted, refocus) = (context.clone(), key.clone());
        input.connect_activate(move |entry| {
            let Some(this) = weak.upgrade() else { return };
            let text = entry.text().trim().to_string();
            if text.is_empty() {
                return;
            }
            let parsed = this.parse_quick(&text);
            let mut fields = submitted.clone();
            let mut labels: Vec<String> = submitted.get("labels").and_then(Value::as_array).map(|l| l.iter().filter_map(Value::as_str).map(str::to_string).collect()).unwrap_or_default();
            for label in parsed.get("labels").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
                if !labels.iter().any(|l| l == label) {
                    labels.push(label.to_string());
                }
            }
            for (name, value) in parsed {
                fields.insert(name, value);
            }
            fields.insert("labels".into(), json!(labels));
            this.new_task(fields);
            entry.set_text("");
            if let Some(parts) = this.tasks_parts.borrow().as_ref() {
                parts.refocus.replace(Some(refocus.clone()));
            }
            this.render_nav();
            this.render_task_list();
        });
        let wanted = self.tasks_parts.borrow().as_ref().and_then(|p| p.refocus.borrow().clone());
        if wanted.as_deref() == Some(key.as_str()) {
            if let Some(parts) = self.tasks_parts.borrow().as_ref() {
                parts.refocus.replace(None);
            }
            let focus = input.clone();
            glib::idle_add_local_once(move || {
                focus.grab_focus();
            });
        }
        if !first {
            return form.upcast();
        }
        // The words parseQuick knows, which are English in every language
        let wrap = ui::vbox(0, &["quick-wrap"]);
        wrap.append(&form);
        let hint = ui::label(&t!("Knows: {words}, @label, #project", words = "today, tomorrow, friday, 5pm, 17:30, every week, p1–p4"), &["quick-hint", "faint", "small"]);
        let revealer = gtk::Revealer::builder().child(&hint).transition_type(gtk::RevealerTransitionType::SlideDown).transition_duration(150).build();
        wrap.append(&revealer);
        let focus = gtk::EventControllerFocus::new();
        let (shown, hidden) = (revealer.clone(), revealer.clone());
        focus.connect_enter(move |_| shown.set_reveal_child(true));
        focus.connect_leave(move |_| hidden.set_reveal_child(false));
        input.add_controller(focus);
        wrap.upcast()
    }

    /// Ctrl+N in the tasks: the first field to add one
    pub fn focus_quick(&self, _context: Option<String>) {
        let Some(parts) = self.tasks_parts.borrow().as_ref().map(|p| (p.list.clone(), p.refocus.clone())).map(|(list, _)| list) else { return };
        parts.scroll_to(0, gtk::ListScrollFlags::NONE, None);
        if let Some(parts) = self.tasks_parts.borrow().as_ref() {
            parts.refocus.replace(Some("first".into()));
        }
        self.render_task_list();
    }

    pub fn focus_first_task(&self) {
        if let Some(parts) = self.tasks_parts.borrow().as_ref() {
            parts.list.grab_focus();
        }
    }

    fn check_button(&self, task: &Value, size: i32, label: &str) -> gtk::Button {
        let mark = icon("mark-ok", size);
        mark.set_hexpand(true);
        mark.set_vexpand(true);
        let check = gtk::Button::builder().child(&mark).css_classes(["plain", "check"]).valign(gtk::Align::Start).halign(gtk::Align::Start).build();
        // The mark fills the box; the box asks for no more room than its own, in a row or in the detail
        check.set_hexpand(false);
        check.set_vexpand(false);
        widgets::set_on(&check, task.is("done"));
        check.update_property(&[gtk::accessible::Property::Label(label)]);
        check.update_state(&[gtk::accessible::State::Checked(if task.is("done") { gtk::AccessibleTristate::True } else { gtk::AccessibleTristate::False })]);
        check
    }

    fn task_row(&self, task: &Value, depth: usize, nest: bool) -> gtk::Widget {
        let id = task.id().to_string();
        let now = dates::today();
        let project = task.opt("project").and_then(|p| self.item(Kind::Projects, p));
        let children = self.subtasks_of(&id);
        let view = self.ui.borrow().tasks_view.clone();
        let query = !self.ui.borrow().query.is_empty();
        let row = ui::hbox(12, &["task-row"]);
        row.add_css_class(&format!("prio-{}", priority_of(task)));
        widgets::set_class(&row, "done", task.is("done"));
        widgets::set_class(&row, "current", self.ui.borrow().task.as_deref() == Some(id.as_str()));
        if depth > 0 {
            row.add_css_class(&format!("depth-{}", depth.min(4)));
        }
        let check = self.check_button(task, 14, &if task.is("done") { t!("Mark as not done") } else { t!("Complete") });
        // A click leaves the focus where it was: the row is drawn again, and the list would hand the focus on
        check.set_focus_on_click(false);
        let done_id = id.clone();
        let weak = self.me.clone();
        check.connect_clicked(move |_| {
            if let Some(this) = weak.upgrade() {
                this.toggle_done(&done_id);
            }
        });
        row.append(&check);
        let main = ui::vbox(3, &["task-main"]);
        let title = if task.title().is_empty() { t!("Untitled") } else { task.title().to_string() };
        let title_label = ui::label(&widgets::in_page_direction(&title), &["task-title"]);
        main.append(&title_label);
        if task.is("notes") {
            let notes = widgets::cut(&widgets::in_page_direction(&super::notes::snippet(&data::text(task.get("notes")))), &["task-notes"]);
            notes.set_hexpand(true);
            main.append(&notes);
        }
        let meta = Flex::new(12, 4, &["task-meta"]);
        let mut any = false;
        if let Some(due) = task.opt("due") {
            let piece = ui::hbox(4, &["meta-due"]);
            if due < now.as_str() && !task.is("done") {
                piece.add_css_class("late");
            } else if due == now {
                piece.add_css_class("today");
            }
            piece.append(&icon("calendar", 13));
            let words = match task.opt("time") {
                Some(time) => t!("{day} {time}", day = dates::day_label(due, false), time = dates::time_label(time)),
                None => dates::day_label(due, false),
            };
            piece.append(&ui::line(&words, &[]));
            meta.append(&piece);
            any = true;
        }
        if task.is("repeat") {
            meta.append(&icon("repeat", 13));
            any = true;
        }
        if task.num("reminder").is_some_and(|n| n.fract() == 0.0) && task.is("time") {
            meta.append(&icon("bell", 13));
            any = true;
        }
        if !children.is_empty() {
            let piece = ui::hbox(4, &[]);
            piece.append(&icon("checklist", 13));
            let done = children.iter().filter(|c| c.is("done")).count();
            piece.append(&ui::line(&format!("{}/{}", i18n::number(done as f64), i18n::number(children.len() as f64)), &[]));
            meta.append(&piece);
            any = true;
        }
        if task.is("notes") {
            meta.append(&icon("note", 13));
            any = true;
        }
        if let (Some(parent), false) = (task.opt("parent").and_then(|p| self.item(Kind::Tasks, p)), nest) {
            let name = if parent.title().is_empty() { t!("Untitled") } else { parent.title().to_string() };
            meta.append(&ui::line(&t!("in {task}", task = name), &["faint"]));
            any = true;
        }
        for label in task.list("labels").iter().filter_map(|l| self.item(Kind::Labels, l)) {
            meta.append(&label_chip(&label));
            any = true;
        }
        if !["project", "inbox"].contains(&view.kind.as_str()) || query {
            let piece = ui::hbox(4, &["meta-project"]);
            match &project {
                Some(project) => {
                    piece.add_css_class(&format!("color-{}", widgets::color_name(project.opt("color").unwrap_or("violet"))));
                    piece.append(&widgets::dot(project.opt("color").unwrap_or("violet"), &[]));
                    piece.append(&ui::line(project.title(), &[]));
                }
                None => {
                    piece.append(&icon("inbox", 13));
                    piece.append(&ui::line(&t!("Inbox"), &[]));
                }
            }
            meta.append_with(&piece, Grow { push: true, ..Default::default() });
            any = true;
        }
        if any {
            main.append(&meta);
        }
        let open = gtk::Button::builder().child(&main).css_classes(["plain", "task-main-button"]).hexpand(true).focus_on_click(false).build();
        let open_id = id.clone();
        open.connect_clicked(self.on_button(move |this| {
            this.commit();
            this.ui.borrow_mut().task = Some(open_id.clone());
            this.render_tasks(false);
        }));
        row.append(&open);
        if task.is("pinned") {
            let pin = icon("pin", 15);
            pin.add_css_class("pin-mark");
            pin.set_valign(gtk::Align::Start);
            pin.set_tooltip_text(Some(&t!("Pinned")));
            row.append(&pin);
        }
        row.upcast()
    }

    // --- The open task -----------------------------------------------------------------------------------

    /// The list and the nav again, a moment after the open task was typed in
    fn refresh_later(&self) {
        let parts = self.tasks_parts.borrow();
        let Some(parts) = parts.as_ref() else { return };
        if let Some(timer) = parts.refresh.take() {
            timer.remove();
        }
        let weak = self.me.clone();
        parts.refresh.replace(Some(glib::timeout_add_local_once(Duration::from_millis(300), move || {
            let Some(this) = weak.upgrade() else { return };
            if let Some(parts) = this.tasks_parts.borrow().as_ref() {
                parts.refresh.take();
            }
            this.render_task_list();
            this.render_nav();
        })));
    }

    fn rebuild(&self) {
        self.render_nav();
        self.render_tasks(true);
    }

    fn build_detail(&self, detail: &gtk::Box, id: &str) {
        let Some(task) = self.item(Kind::Tasks, id) else { return };
        let id = id.to_string();
        // The head: where it is, and pin, delete and close
        let head = ui::hbox(4, &["detail-head"]);
        match task.opt("parent").and_then(|p| self.item(Kind::Tasks, p)) {
            Some(parent) => {
                let name = if parent.title().is_empty() { t!("Untitled") } else { parent.title().to_string() };
                let parent_id = parent.id().to_string();
                let link = link_button(&name, None, &["quiet", "small"], self.on(move |this| {
                    this.ui.borrow_mut().task = Some(parent_id.clone());
                    this.render_tasks(false);
                }));
                if let Some(content) = link.child().and_then(|c| c.downcast::<gtk::Box>().ok()) {
                    content.prepend(&icon("undo", 16).mirror_in_rtl());
                }
                head.append(&link);
            }
            None => {
                let place = match task.opt("project") {
                    Some(project) => self.item(Kind::Projects, project).map(|p| p.title().to_string()).unwrap_or_default(),
                    None => t!("Inbox"),
                };
                head.append(&ui::line(&place, &["faint", "small"]));
            }
        }
        let grow = ui::hbox(0, &[]);
        grow.set_hexpand(true);
        head.append(&grow);
        let pin_id = id.clone();
        let pinned = task.is("pinned");
        let pin = icon_button("pin", &if pinned { t!("Unpin") } else { t!("Pin") }, &[], self.on_button(move |this| {
            let pinned = this.item(Kind::Tasks, &pin_id).is_some_and(|t| t.is("pinned"));
            let mut changes = Map::new();
            changes.insert("pinned".into(), Value::Bool(!pinned));
            this.save_task(&pin_id, changes, true);
            this.rebuild();
        }));
        widgets::set_on(&pin, pinned);
        head.append(&pin);
        let delete_id = id.clone();
        head.append(&icon_button("trash", &t!("Delete"), &[], self.on_button(move |this| this.delete_task(&delete_id))));
        head.append(&icon_button("close", &t!("{action} ({key})", action = t!("Close"), key = "Esc"), &[], self.on_button(|this| {
            this.ui.borrow_mut().task = None;
            this.render_tasks(false);
        })));
        self.controls_for(Some(&head));
        detail.append(&head);

        // The box and the title
        let top = ui::hbox(12, &["detail-top"]);
        top.add_css_class(&format!("prio-{}", priority_of(&task)));
        widgets::set_class(&top, "done", task.is("done"));
        let check = self.check_button(&task, 14, &t!("Complete"));
        let toggled = id.clone();
        check.connect_clicked(self.on_button(move |this| {
            this.toggle_done(&toggled);
            this.render_tasks(true);
        }));
        top.append(&check);
        let (title_view, title_box) = text_area(&task.str("title").replace('\n', " "), &t!("Task"), "detail-title", "detail-title-placeholder");
        title_view.set_hexpand(true);
        top.append(&title_box);
        detail.append(&top);
        let (notes_view, notes_area) = text_area(task.str("notes"), &t!("Notes"), "detail-notes", "detail-notes-placeholder");
        let notes_box = ui::vbox(0, &["detail-notes-box"]);
        notes_box.append(&notes_area);
        notes_box.set_size_request(-1, 88);
        detail.append(&notes_box);
        let (weak, typed) = (self.me.clone(), id.clone());
        title_view.buffer().connect_changed(move |buffer| {
            let Some(this) = weak.upgrade() else { return };
            let text = buffer.text(&buffer.start_iter(), &buffer.end_iter(), false).replace('\n', " ");
            let mut changes = Map::new();
            changes.insert("title".into(), Value::from(text));
            this.save_task(&typed, changes, false);
            this.refresh_later();
        });
        let keys = gtk::EventControllerKey::new();
        let to_notes = notes_view.clone();
        keys.connect_key_pressed(move |_, key, _, _| {
            if matches!(key, gdk::Key::Return | gdk::Key::KP_Enter) {
                to_notes.grab_focus();
                return glib::Propagation::Stop;
            }
            glib::Propagation::Proceed
        });
        keys.set_propagation_phase(gtk::PropagationPhase::Capture);
        title_view.add_controller(keys);
        let (weak, typed) = (self.me.clone(), id.clone());
        notes_view.buffer().connect_changed(move |buffer| {
            let Some(this) = weak.upgrade() else { return };
            let text = buffer.text(&buffer.start_iter(), &buffer.end_iter(), false).to_string();
            let mut changes = Map::new();
            changes.insert("notes".into(), Value::from(text));
            this.save_task(&typed, changes, false);
            this.refresh_later();
        });

        // The fields
        let fields = ui::vbox(10, &["detail-fields"]);
        let field = |label: &str, control: &gtk::Widget| -> gtk::Box {
            let row = ui::hbox(10, &["detail-field"]);
            let words = ui::line(label, &["detail-label"]);
            words.set_size_request(76, -1);
            words.set_valign(gtk::Align::Center);
            row.append(&words);
            control.set_hexpand(true);
            row.append(control);
            row
        };
        let mut projects: Vec<Value> = self.db(|store| store.values(Kind::Projects).cloned().collect()).unwrap_or_default();
        sort_by_title(&mut projects);
        let mut choices = vec![(String::new(), t!("Inbox"))];
        choices.extend(projects.iter().map(|p| (p.id().to_string(), p.title().to_string())));
        let (weak, moved) = (self.me.clone(), id.clone());
        let project_select = select(&t!("Project"), &choices, task.str("project"), &[], move |value| {
            let Some(this) = weak.upgrade() else { return };
            let project = if value.is_empty() { Value::Null } else { Value::from(value) };
            let mut changes = Map::new();
            changes.insert("project".into(), project.clone());
            changes.insert("section".into(), Value::Null);
            this.save_task(&moved, changes.clone(), true);
            for child in this.subtasks_of(&moved) {
                this.save_task(child.id(), changes.clone(), false);
            }
            this.rebuild();
        });
        fields.append(&field(&t!("Project"), project_select.upcast_ref()));
        let mut sections: Vec<Value> = self.db(|store| store.values(Kind::Sections).filter(|s| s.opt("project") == task.opt("project")).cloned().collect()).unwrap_or_default();
        sections.sort_by(|a, b| a.num_or_zero("order").partial_cmp(&b.num_or_zero("order")).unwrap_or(std::cmp::Ordering::Equal));
        let mut choices = vec![(String::new(), t!("No section"))];
        choices.extend(sections.iter().map(|s| (s.id().to_string(), s.title().to_string())));
        let (weak, moved) = (self.me.clone(), id.clone());
        let section_select = select(&t!("Section"), &choices, task.str("section"), &[], move |value| {
            let Some(this) = weak.upgrade() else { return };
            let mut changes = Map::new();
            changes.insert("section".into(), if value.is_empty() { Value::Null } else { Value::from(value) });
            this.save_task(&moved, changes, true);
            this.rebuild();
        });
        let section_row = field(&t!("Section"), section_select.upcast_ref());
        section_row.set_visible(!sections.is_empty());
        fields.append(&section_row);

        // The date, its time and the button that takes both off
        let inline = ui::hbox(6, &["inline"]);
        let (weak, dated) = (self.me.clone(), id.clone());
        let date = date_field(task.opt("due"), move |chosen| {
            let Some(this) = weak.upgrade() else { return };
            let mut changes = Map::new();
            match chosen {
                Some(due) => {
                    changes.insert("due".into(), Value::from(due));
                }
                None => {
                    for name in ["due", "time", "reminder", "repeat"] {
                        changes.insert(name.into(), Value::Null);
                    }
                }
            }
            this.save_task(&dated, changes, true);
            this.rebuild();
        });
        date.set_hexpand(true);
        inline.append(&date);
        let (weak, timed, reminder) = (self.me.clone(), id.clone(), task.get("reminder").cloned().filter(|r| !r.is_null()));
        let time = time_field(task.opt("time"), task.is("due"), move |chosen| {
            let Some(this) = weak.upgrade() else { return };
            let mut changes = Map::new();
            match chosen {
                Some(time) => {
                    changes.insert("time".into(), Value::from(time));
                    changes.insert("reminder".into(), reminder.clone().unwrap_or(Value::from(0)));
                }
                None => {
                    changes.insert("time".into(), Value::Null);
                    changes.insert("reminder".into(), Value::Null);
                }
            }
            this.save_task(&timed, changes, true);
            this.rebuild();
        });
        time.set_size_request(116, -1);
        inline.append(&time);
        if task.is("due") {
            let cleared = id.clone();
            let clear = icon_button("close", &t!("No date"), &[], self.on_button(move |this| {
                let mut changes = Map::new();
                for name in ["due", "time", "reminder", "repeat"] {
                    changes.insert(name.into(), Value::Null);
                }
                this.save_task(&cleared, changes, true);
                this.rebuild();
            }));
            inline.append(&clear);
        }
        fields.append(&field(&t!("Date"), inline.upcast_ref()));

        // How often it repeats
        let repeat = task.get("repeat").cloned().filter(|r| data::truthy(Some(r)));
        let every = repeat.as_ref().map(|r| r.num_or_zero("every")).filter(|n| *n > 1.0).unwrap_or(1.0);
        let mut choices = vec![(String::new(), t!("Does not repeat"))];
        for unit in ["day", "week", "month", "year"] {
            choices.push((unit.to_string(), unit_label(unit, every)));
        }
        let unit = repeat.as_ref().map(|r| data::text(r.get("unit"))).unwrap_or_default();
        let (weak, repeated, every_now) = (self.me.clone(), id.clone(), repeat.as_ref().map(|r| r.num_or_zero("every")).filter(|n| *n >= 1.0).unwrap_or(1.0));
        let unit_select = select(&t!("Repeat"), &choices, &unit, &[], move |value| {
            let Some(this) = weak.upgrade() else { return };
            let mut changes = Map::new();
            changes.insert("repeat".into(), if value.is_empty() { Value::Null } else { json!({ "every": data::ms(every_now), "unit": value }) });
            this.save_task(&repeated, changes, true);
            this.rebuild();
        });
        unit_select.set_sensitive(task.is("due"));
        let repeat_row = ui::hbox(6, &["inline"]);
        unit_select.set_hexpand(true);
        repeat_row.append(&unit_select);
        if repeat.is_some() {
            // <input type="number" min="1" max="365">: its value taken when it is left or Enter is pressed,
            // as its change event came; the arrows step it
            let shown = repeat.as_ref().map(|r| r.num_or_zero("every")).filter(|n| *n >= 1.0).unwrap_or(1.0);
            let number = gtk::Entry::builder().text(data::js_number(shown)).css_classes(["field", "every"]).input_purpose(gtk::InputPurpose::Digits).width_chars(1).max_width_chars(1).build();
            number.set_size_request(66, -1);
            number.set_hexpand(false);
            number.update_property(&[gtk::accessible::Property::Label(&t!("Every how many"))]);
            let (weak, counted, kept) = (self.me.clone(), id.clone(), repeat.clone().unwrap_or(Value::Null));
            let commit = Rc::new(move |entry: &gtk::Entry| {
                let Some(this) = weak.upgrade() else { return };
                let every = entry.text().trim().parse::<f64>().unwrap_or(1.0).round().clamp(1.0, 365.0);
                if every == shown && entry.text().as_str() == data::js_number(shown) {
                    return;
                }
                let mut next = kept.clone();
                data::set(&mut next, "every", data::ms(every));
                let mut changes = Map::new();
                changes.insert("repeat".into(), next);
                this.save_task(&counted, changes, true);
                this.rebuild();
            });
            let on_enter = commit.clone();
            number.connect_activate(move |entry| on_enter(entry));
            let focus = gtk::EventControllerFocus::new();
            let (on_leave, left) = (commit.clone(), number.clone());
            focus.connect_leave(move |_| {
                let (on_leave, left) = (on_leave.clone(), left.clone());
                glib::idle_add_local_once(move || on_leave(&left));
            });
            number.add_controller(focus);
            let keys = gtk::EventControllerKey::new();
            let stepped = number.clone();
            keys.connect_key_pressed(move |_, key, _, _| {
                let step = match key {
                    gdk::Key::Up => 1.0,
                    gdk::Key::Down => -1.0,
                    _ => return glib::Propagation::Proceed,
                };
                let value = stepped.text().trim().parse::<f64>().unwrap_or(1.0);
                stepped.set_text(&data::js_number((value + step).clamp(1.0, 365.0)));
                glib::Propagation::Stop
            });
            keys.set_propagation_phase(gtk::PropagationPhase::Capture);
            number.add_controller(keys);
            repeat_row.append(&number);
        }
        fields.append(&field(&t!("Repeat"), repeat_row.upcast_ref()));

        // When it reminds
        let choices: Vec<(String, String)> = reminders().into_iter().map(|(value, label)| (value.map(|v| v.to_string()).unwrap_or_default(), label)).collect();
        let current = task.num("reminder").map(data::js_number).unwrap_or_default();
        let (weak, reminded) = (self.me.clone(), id.clone());
        let reminder_select = select(&t!("Reminder"), &choices, &current, &[], move |value| {
            let Some(this) = weak.upgrade() else { return };
            let mut changes = Map::new();
            changes.insert("reminder".into(), value.parse::<i64>().map(Value::from).unwrap_or(Value::Null));
            this.save_task(&reminded, changes, true);
            this.refresh_later();
        });
        reminder_select.set_sensitive(task.is("time"));
        fields.append(&field(&t!("Reminder"), reminder_select.upcast_ref()));

        // P1 to P3 are written as the quick add takes them, p1 to p3, and so are the same in every language
        let priority = gtk::Box::builder().orientation(gtk::Orientation::Horizontal).spacing(4).homogeneous(true).css_classes(["priority"]).build();
        priority.update_property(&[gtk::accessible::Property::Label(&t!("Priority"))]);
        for level in 1..=4i64 {
            let content = ui::hbox(5, &[]);
            content.set_halign(gtk::Align::Center);
            content.append(&icon("flag", 16));
            content.append(&ui::line(&if level == 4 { t!("None") } else { format!("P{level}") }, &[]));
            let choice = gtk::Button::builder().child(&content).css_classes(["plain", &format!("prio-{level}")]).tooltip_text(priority_label(level)).build();
            widgets::set_on(&choice, priority_of(&task) == level);
            let prioritised = id.clone();
            choice.connect_clicked(self.on_button(move |this| {
                let mut changes = Map::new();
                changes.insert("priority".into(), Value::from(level));
                this.save_task(&prioritised, changes, true);
                this.rebuild();
            }));
            priority.append(&choice);
        }
        fields.append(&field(&t!("Priority"), priority.upcast_ref()));

        // Its labels, and the menu to add one
        let labels = Flex::new(6, 6, &["label-edit"]);
        for label in task.list("labels").iter().filter_map(|l| self.item(Kind::Labels, l)) {
            let chip = label_chip(&label);
            let (label_id, unlabelled) = (label.id().to_string(), id.clone());
            let x = icon_button("close", &t!("Remove {name}", name = label.title()), &["chip-x"], self.on_button(move |this| {
                let labels = this.item(Kind::Tasks, &unlabelled).map(|t| t.list("labels")).unwrap_or_default();
                let mut changes = Map::new();
                changes.insert("labels".into(), json!(labels.into_iter().filter(|l| *l != label_id).collect::<Vec<_>>()));
                this.save_task(&unlabelled, changes, true);
                this.rebuild();
            }));
            x.set_tooltip_text(None);
            if let Some(mark) = x.child().and_then(|c| c.downcast::<amethystora_ui::icon::Icon>().ok()) {
                mark.set_size(12);
            }
            chip.append(&x);
            labels.append(&chip);
        }
        let add_content = ui::hbox(4, &[]);
        add_content.append(&icon("plus", 14));
        add_content.append(&ui::line(&t!("Label"), &[]));
        let add = gtk::Button::builder().child(&add_content).css_classes(["plain", "add-label"]).build();
        let labelled = id.clone();
        let weak = self.me.clone();
        add.connect_clicked(move |anchor| {
            let Some(this) = weak.upgrade() else { return };
            let have = this.item(Kind::Tasks, &labelled).map(|t| t.list("labels")).unwrap_or_default();
            let mut all: Vec<Value> = this.db(|store| store.values(Kind::Labels).cloned().collect()).unwrap_or_default();
            sort_by_title(&mut all);
            let mut entries: Vec<Entry> = all
                .into_iter()
                .filter(|label| !have.contains(&label.id().to_string()))
                .map(|label| {
                    let (weak, task, label_id) = (this.me.clone(), labelled.clone(), label.id().to_string());
                    Entry::Item(widgets::Item {
                        label: label.title().to_string(),
                        glyph: None,
                        color: Some(label.opt("color").unwrap_or("violet").to_string()),
                        checked: false,
                        danger: false,
                        run: Rc::new(move || {
                            if let Some(this) = weak.upgrade() {
                                let mut labels = this.item(Kind::Tasks, &task).map(|t| t.list("labels")).unwrap_or_default();
                                labels.push(label_id.clone());
                                let mut changes = Map::new();
                                changes.insert("labels".into(), json!(labels));
                                this.save_task(&task, changes, true);
                                this.rebuild();
                            }
                        }),
                    })
                })
                .collect();
            let task = labelled.clone();
            entries.push(item(&t!("New label…"), "plus", this.on(move |this| {
                let task = task.clone();
                this.spawn(async move |this| {
                    if let Some(name) = widgets::ask(&t!("New label"), &t!("Name"), "", Some(&t!("Create")), None).await {
                        let label = this.label_for(&name);
                        let mut labels = this.item(Kind::Tasks, &task).map(|t| t.list("labels")).unwrap_or_default();
                        if !labels.contains(&label) {
                            labels.push(label);
                        }
                        let mut changes = Map::new();
                        changes.insert("labels".into(), json!(labels));
                        this.save_task(&task, changes, true);
                        this.rebuild();
                    }
                });
            })));
            menu(anchor, entries);
        });
        labels.append(&add);
        fields.append(&field(&t!("Labels"), labels.upcast_ref()));
        detail.append(&fields);

        // Its subtasks, and the field to add one
        let subtasks = ui::vbox(2, &["subtasks"]);
        subtasks.append(&ui::label(&t!("Subtasks"), &["detail-label"]));
        let mut children = self.subtasks_of(&id);
        children.sort_by(|a, b| a.is("done").cmp(&b.is("done")).then_with(|| task_order(a, b)));
        for child in children {
            let row = ui::hbox(10, &["sub-row"]);
            row.add_css_class(&format!("prio-{}", priority_of(&child)));
            widgets::set_class(&row, "done", child.is("done"));
            let check = self.check_button(&child, 13, &t!("Complete"));
            check.set_valign(gtk::Align::Center);
            let child_id = child.id().to_string();
            let toggled = child_id.clone();
            check.connect_clicked(self.on_button(move |this| {
                this.toggle_done(&toggled);
                this.render_tasks(true);
            }));
            row.append(&check);
            let name = if child.title().is_empty() { t!("Untitled") } else { child.title().to_string() };
            let label = ui::label(&widgets::in_page_direction(&name), &["sub-title"]);
            let open = gtk::Button::builder().child(&label).css_classes(["plain", "sub-title"]).hexpand(true).build();
            open.connect_clicked(self.on_button(move |this| {
                this.ui.borrow_mut().task = Some(child_id.clone());
                this.render_tasks(false);
            }));
            row.append(&open);
            subtasks.append(&row);
        }
        let sub_input = gtk::Entry::builder().css_classes(["plain", "quick-input"]).placeholder_text(t!("Add a subtask")).hexpand(true).build();
        sub_input.update_property(&[gtk::accessible::Property::Label(&t!("Add a subtask"))]);
        let form = ui::hbox(10, &["quick", "later"]);
        let plus = icon("plus", 16);
        plus.add_css_class("quick-plus");
        form.append(&plus);
        form.append(&sub_input);
        let (weak, parent) = (self.me.clone(), id.clone());
        sub_input.connect_activate(move |entry| {
            let Some(this) = weak.upgrade() else { return };
            let text = entry.text().trim().to_string();
            if text.is_empty() {
                return;
            }
            let Some(task) = this.item(Kind::Tasks, &parent) else { return };
            let mut fields = Map::new();
            fields.insert("project".into(), task.get("project").cloned().unwrap_or(Value::Null));
            fields.insert("section".into(), task.get("section").cloned().unwrap_or(Value::Null));
            for (name, value) in this.parse_quick(&text) {
                fields.insert(name, value);
            }
            fields.insert("parent".into(), Value::from(parent.clone()));
            this.new_task(fields);
            this.rebuild();
            this.focus_subtask_input();
        });
        subtasks.append(&form);
        detail.append(&subtasks);
        let mut foot = vec![t!("Added {date}", date = dates::stamp(task.num("created").filter(|n| *n != 0.0).unwrap_or_else(data::now_ms)))];
        if task.is("done") {
            foot.push(t!("Completed {date}", date = dates::stamp(task.num_or_zero("done"))));
        }
        detail.append(&ui::label(&foot.join(" · "), &["detail-foot", "faint", "small"]));
        if !task.is("title") {
            glib::idle_add_local_once(move || {
                title_view.grab_focus();
            });
        }
    }

    fn focus_subtask_input(&self) {
        let Some(detail) = self.tasks_parts.borrow().as_ref().map(|p| p.detail.clone()) else { return };
        let Some(subtasks) = detail.last_child().and_then(|c| c.prev_sibling()) else { return };
        if let Some(input) = subtasks.last_child().and_then(|form| form.last_child()) {
            glib::idle_add_local_once(move || {
                input.grab_focus();
            });
        }
    }
}

fn priority_of(task: &Value) -> i64 {
    task.num("priority").filter(|n| *n != 0.0).map(|n| n as i64).unwrap_or(4)
}

fn label_chip(label: &Value) -> gtk::Box {
    let chip = ui::hbox(3, &["label-chip"]);
    chip.add_css_class(&format!("color-{}", widgets::color_name(label.opt("color").unwrap_or("violet"))));
    chip.append(&ui::line(&widgets::in_page_direction(label.title()), &[]));
    chip.set_valign(gtk::Align::Center);
    chip
}

/// A <textarea> that grows with its text: the text view, and the box with its placeholder over it
fn text_area(text: &str, placeholder: &str, class: &str, placeholder_class: &str) -> (gtk::TextView, gtk::Widget) {
    let buffer = gtk::TextBuffer::new(None);
    buffer.begin_irreversible_action();
    buffer.set_text(text);
    buffer.end_irreversible_action();
    // A text view asks to expand by itself, which a textarea never did
    let view = gtk::TextView::builder().buffer(&buffer).wrap_mode(gtk::WrapMode::WordChar).css_classes(["plain", class]).accepts_tab(false).vexpand(false).build();
    view.update_property(&[gtk::accessible::Property::Label(placeholder)]);
    widgets::auto_direction(&view, text);
    let hint = ui::line(placeholder, &["placeholder", placeholder_class]);
    hint.set_halign(gtk::Align::Start);
    hint.set_valign(gtk::Align::Start);
    hint.set_can_target(false);
    hint.set_visible(text.is_empty());
    let shown = hint.clone();
    let direction = view.clone();
    buffer.connect_changed(move |buffer| {
        let text = buffer.text(&buffer.start_iter(), &buffer.end_iter(), false);
        shown.set_visible(text.is_empty());
        widgets::auto_direction(&direction, &text);
    });
    let overlay = gtk::Overlay::new();
    overlay.set_child(Some(&view));
    overlay.add_overlay(&hint);
    (view, overlay.upcast())
}

/// How Chromium wrote a date in its date field, in the language's order and digits, and what it showed
/// when there was none
fn numeric_date(iso: &str) -> String {
    let Some((year, month, day)) = dates::parse(iso) else { return iso.to_string() };
    let digits = |n: i64, width: usize| format!("{n:0width$}").chars().map(|c| i18n::number(c.to_digit(10).unwrap_or(0) as f64)).collect::<String>();
    let lang = i18n::with(|i| i.lang.clone());
    match lang.as_str() {
        "en" => format!("{}/{}/{}", digits(month, 2), digits(day, 2), digits(year, 4)),
        "de" => format!("{}.{}.{}", digits(day, 2), digits(month, 2), digits(year, 4)),
        _ => format!("{}/{}/{}", digits(day, 2), digits(month, 2), digits(year, 4)),
    }
}

fn date_placeholder() -> &'static str {
    match i18n::with(|i| i.lang.clone()).as_str() {
        "fr" => "jj/mm/aaaa",
        "de" => "TT.MM.JJJJ",
        "es" => "dd/mm/aaaa",
        "ar" => "يوم/شهر/سنة",
        _ => "mm/dd/yyyy",
    }
}

/// <input type="date">: the date, and a calendar to choose one in
fn date_field(value: Option<&str>, on_change: impl Fn(Option<String>) + 'static) -> gtk::MenuButton {
    let content = ui::hbox(6, &[]);
    let words = ui::line(&value.map(numeric_date).unwrap_or_else(|| date_placeholder().to_string()), &[]);
    words.set_hexpand(true);
    words.set_direction(gtk::TextDirection::Ltr);
    if value.is_none() {
        words.add_css_class("placeholder");
    }
    content.append(&words);
    content.append(&crate::glyphs::calendar(14));
    let calendar = gtk::Calendar::new();
    if let Some((year, month, day)) = value.and_then(dates::parse) {
        if let Ok(date) = glib::DateTime::from_local(year as i32, month as i32, day as i32, 12, 0, 0.0) {
            calendar.select_day(&date);
        }
    }
    let popover = gtk::Popover::builder().child(&calendar).has_arrow(false).position(gtk::PositionType::Bottom).build();
    let button = gtk::MenuButton::builder().child(&content).popover(&popover).css_classes(["plain"]).build();
    if let Some(inner) = button.first_child() {
        inner.add_css_class("plain");
        inner.add_css_class("date-field");
    }
    let on_change = Rc::new(on_change);
    let closing = popover.clone();
    calendar.connect_day_selected(move |calendar| {
        let date = calendar.date();
        closing.popdown();
        on_change(Some(dates::iso(date.year() as i64, date.month() as i64, date.day_of_month() as i64)));
    });
    button
}

/// <input type="time">: the time, and the hours and minutes to choose it with; taken when the choice closes
fn time_field(value: Option<&str>, enabled: bool, on_change: impl Fn(Option<String>) + 'static) -> gtk::MenuButton {
    let content = ui::hbox(6, &[]);
    let twelve = !i18n::date(dates::local_seconds(2000, 1, 1, 13, 0).unwrap_or(0.0), i18n::DateStyle::Time).contains("13");
    let shown = match value.and_then(|v| v.split_once(':')).and_then(|(h, m)| Some((h.parse::<i64>().ok()?, m.parse::<i64>().ok()?))) {
        Some((hours, minutes)) => i18n::date(dates::local_seconds(2000, 1, 1, hours, minutes).unwrap_or(0.0), i18n::DateStyle::Time),
        None if twelve => "--:-- --".into(),
        None => "--:--".into(),
    };
    let words = ui::line(&shown, &[]);
    words.set_hexpand(true);
    if value.is_none() {
        words.add_css_class("placeholder");
    }
    content.append(&words);
    content.append(&crate::glyphs::clock(14));
    let (hours, minutes) = value.and_then(|v| v.split_once(':')).map(|(h, m)| (h.parse::<f64>().unwrap_or(9.0), m.parse::<f64>().unwrap_or(0.0))).unwrap_or((9.0, 0.0));
    let hour = gtk::SpinButton::with_range(0.0, 23.0, 1.0);
    hour.set_value(hours);
    hour.set_wrap(true);
    hour.set_orientation(gtk::Orientation::Vertical);
    let minute = gtk::SpinButton::with_range(0.0, 59.0, 1.0);
    minute.set_value(minutes);
    minute.set_wrap(true);
    minute.set_orientation(gtk::Orientation::Vertical);
    for spin in [&hour, &minute] {
        spin.connect_output(|spin| {
            spin.set_text(&format!("{:02}", spin.value() as i64));
            glib::Propagation::Stop
        });
    }
    let row = ui::hbox(6, &[]);
    row.append(&hour);
    row.append(&ui::line(":", &[]));
    row.append(&minute);
    let clear = gtk::Button::builder().child(&icon("close", 16)).css_classes(["plain", "icon-btn"]).valign(gtk::Align::Center).build();
    row.append(&clear);
    let popover = gtk::Popover::builder().child(&row).has_arrow(false).position(gtk::PositionType::Bottom).build();
    let button = gtk::MenuButton::builder().child(&content).popover(&popover).css_classes(["plain"]).sensitive(enabled).build();
    if let Some(inner) = button.first_child() {
        inner.add_css_class("plain");
        inner.add_css_class("date-field");
    }
    let on_change = Rc::new(on_change);
    let had = value.map(str::to_string);
    let cleared = Rc::new(std::cell::Cell::new(false));
    let (closing, clearing) = (popover.clone(), cleared.clone());
    clear.connect_clicked(move |_| {
        clearing.set(true);
        closing.popdown();
    });
    let changed = on_change.clone();
    popover.connect_closed(move |_| {
        if cleared.replace(false) {
            if had.is_some() {
                changed(None);
            }
            return;
        }
        let next = format!("{:02}:{:02}", hour.value() as i64, minute.value() as i64);
        if had.as_deref() != Some(next.as_str()) {
            changed(Some(next));
        }
    });
    button
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn orders_tasks_as_notes_js() {
        let a = json!({ "due": "2026-10-16", "time": "09:00", "priority": 2, "order": 1 });
        let b = json!({ "due": "2026-10-16", "time": null, "priority": 1, "order": 0 });
        let c = json!({ "due": null, "priority": 1 });
        assert_eq!(task_order(&a, &b), std::cmp::Ordering::Less);
        assert_eq!(task_order(&b, &c), std::cmp::Ordering::Less);
    }
}
