//! What Notes tells the shell's calendar menu about today (the today module of Amethystora UI): the titles of the
//! open tasks due today and of the overdue ones, as the Today view lists them, and nothing else. It is on the
//! session bus, on the connection Notes' application already has, at /org/amethystora/Notes/Today, only while the
//! notes are open: registered when they open, taken away when they lock and when Notes quits. Only GNOME Shell of
//! this account may ask: the caller has to run /usr/bin/gnome-shell and own `org.gnome.Shell` (caller.rs, which says
//! what that does not stop). Anyone else is answered as if there were no such object, the answer the bus gives while
//! the notes are locked; that the object is there at all (its introspection) still says the notes are open, which is
//! inherent in its being there only then. A title is cleaned of control characters and cut before it leaves.
//! `Changed` says, without saying what, that the list may have changed.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

use serde_json::Value;

use amethystora_ui::caller::Callers;
use amethystora_ui::glib::variant::ToVariant;
use amethystora_ui::{gio, glib};

use crate::data::{Fields, Kind, Store};
use crate::page::task_order;

pub const PATH: &str = "/org/amethystora/Notes/Today";
pub const INTERFACE: &str = "org.amethystora.Notes.Today1";
/// The one program that may ask
pub const SHELL_EXE: &str = "/usr/bin/gnome-shell";
/// At most this many titles cross; the count says how many there are
const LISTED: usize = 10;
/// A title is cut to this many characters
const LONGEST: usize = 200;
/// Changes coming close together are said once
const COALESCE: Duration = Duration::from_millis(500);
/// The well-known name the shell owns
pub const SHELL_NAME: &str = "org.gnome.Shell";
/// What GDBus answers for an object that is not there: a refused caller, and a call that comes as the notes lock, are
/// told the same
const NOT_THERE: &str = "org.freedesktop.DBus.Error.UnknownMethod";
const NOT_THERE_TEXT: &str = "Object does not exist at path “/org/amethystora/Notes/Today”";

const XML: &str = r#"<node>
  <interface name="org.amethystora.Notes.Today1">
    <method name="GetToday">
      <arg name="day" type="s" direction="out"/>
      <arg name="total" type="u" direction="out"/>
      <arg name="titles" type="as" direction="out"/>
    </method>
    <signal name="Changed"/>
  </interface>
</node>"#;

/// A title as it may leave: every control character a space, runs of spaces one, trimmed, at most 200 characters
pub fn clean(title: &str) -> String {
    let spaced: String = title.chars().map(|c| if (c as u32) < 0x20 || (0x7f..=0x9f).contains(&(c as u32)) { ' ' } else { c }).collect();
    let joined = spaced.split(' ').filter(|part| !part.is_empty()).collect::<Vec<_>>().join(" ");
    joined.chars().take(LONGEST).collect()
}

/// What `GetToday` says for `today` (YYYY-MM-DD): how many open tasks are due today or before, and the first ten
/// titles, the overdue ones first, each group in the task list's order. An empty title is counted, not listed.
pub fn today_titles(store: &Store, today: &str) -> (u32, Vec<String>) {
    let open: Vec<&Value> = store.values(Kind::Tasks).filter(|task| !task.is("done")).collect();
    let mut overdue: Vec<&Value> = open.iter().copied().filter(|task| task.opt("due").is_some_and(|due| due < today)).collect();
    let mut due: Vec<&Value> = open.iter().copied().filter(|task| task.opt("due") == Some(today)).collect();
    overdue.sort_by(|a, b| task_order(a, b));
    due.sort_by(|a, b| task_order(a, b));
    let all: Vec<&Value> = overdue.into_iter().chain(due).collect();
    let total = all.len() as u32;
    let titles = all.iter().map(|task| clean(task.title())).filter(|title| !title.is_empty()).take(LISTED).collect();
    (total, titles)
}

/// The answer, from the notes as they are now: None while they are locked
pub type Answer = Rc<dyn Fn() -> Option<(String, u32, Vec<String>)>>;

pub struct Today {
    connection: gio::DBusConnection,
    exe: String,
    name: Option<String>,
    answer: Answer,
    callers: Callers,
    id: RefCell<Option<gio::RegistrationId>>,
    pending: RefCell<Option<glib::SourceId>>,
    said: Rc<Cell<u32>>,
}

impl Today {
    /// On `connection`, answering only callers that run `exe` and own `name`, when one is given
    pub fn new(connection: gio::DBusConnection, exe: &str, name: Option<&str>, answer: Answer) -> Rc<Today> {
        Rc::new(Today {
            connection,
            exe: exe.to_string(),
            name: name.map(str::to_string),
            answer,
            callers: Callers::default(),
            id: RefCell::new(None),
            pending: RefCell::new(None),
            said: Rc::new(Cell::new(0)),
        })
    }

    pub fn registered(&self) -> bool {
        self.id.borrow().is_some()
    }

    /// How many times `Changed` was said, for the tests
    pub fn said(&self) -> u32 {
        self.said.get()
    }

    /// On the bus while the notes are open, off it otherwise
    pub fn set_open(self: &Rc<Self>, open: bool) {
        if open && !self.registered() {
            self.register();
            self.changed();
        } else if !open {
            self.unregister();
        }
    }

    fn register(self: &Rc<Self>) {
        let node = gio::DBusNodeInfo::for_xml(XML).expect("the interface is valid XML");
        let interface = node.lookup_interface(INTERFACE).expect("the interface is in it");
        self.callers.watch(&self.connection);
        let weak = Rc::downgrade(self);
        let result = self
            .connection
            .register_object(PATH, &interface)
            .method_call(move |connection, sender, _, _, method, _, invocation| {
                let Some(this) = weak.upgrade() else {
                    return invocation.return_dbus_error(NOT_THERE, NOT_THERE_TEXT);
                };
                let sender = sender.unwrap_or_default().to_string();
                let method = method.to_string();
                glib::spawn_future_local(async move {
                    if !this.callers.check(&connection, &sender, &this.exe, this.name.as_deref()).await {
                        return invocation.return_dbus_error(NOT_THERE, NOT_THERE_TEXT);
                    }
                    if method != "GetToday" {
                        return invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", "no such method");
                    }
                    match (this.answer)() {
                        Some((day, total, titles)) => invocation.return_value(Some(&(day, total, titles).to_variant())),
                        None => invocation.return_dbus_error(NOT_THERE, NOT_THERE_TEXT),
                    }
                });
            })
            .build();
        match result {
            Ok(id) => {
                self.id.replace(Some(id));
            }
            Err(error) => eprintln!("amethystora-notes: today's tasks are not on the bus: {}", error.message()),
        }
    }

    pub fn unregister(&self) {
        if let Some(source) = self.pending.take() {
            source.remove();
        }
        if let Some(id) = self.id.take() {
            let _ = self.connection.unregister_object(id);
        }
    }

    /// The tasks may have changed: said once for whatever changes in the next half second, and only while on the bus
    pub fn changed(self: &Rc<Self>) {
        if !self.registered() || self.pending.borrow().is_some() {
            return;
        }
        let weak = Rc::downgrade(self);
        let source = glib::timeout_add_local_once(COALESCE, move || {
            let Some(this) = weak.upgrade() else { return };
            this.pending.take();
            if this.registered() && this.connection.emit_signal(None, PATH, INTERFACE, "Changed", None).is_ok() {
                this.said.set(this.said.get() + 1);
            }
        });
        self.pending.replace(Some(source));
    }
}

impl Drop for Today {
    fn drop(&mut self) {
        self.unregister();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn task(title: &str, due: Option<&str>, done: bool, order: f64) -> Value {
        json!({ "id": crate::data::new_id(), "title": title, "due": due, "done": if done { json!(1) } else { Value::Null }, "order": order, "created": order })
    }

    fn store(tasks: Vec<Value>) -> Store {
        let mut store = Store::empty();
        for task in tasks {
            store.put(Kind::Tasks, task);
        }
        store
    }

    #[test]
    fn overdue_then_today_open_only() {
        let s = store(vec![
            task("Water the plants", Some("2026-10-28"), false, 2.0),
            task("Call the bakery", Some("2026-10-27"), false, 1.0),
            task("Later thing", Some("2026-10-29"), false, 3.0),
            task("Done thing", Some("2026-10-28"), true, 4.0),
            task("No date", None, false, 5.0),
        ]);
        assert_eq!(today_titles(&s, "2026-10-28"), (2, vec!["Call the bakery".to_string(), "Water the plants".to_string()]));
    }

    #[test]
    fn ten_listed_every_one_counted() {
        let s = store((0..14).map(|i| task(&format!("Task {i:02}"), Some("2026-10-28"), false, i as f64)).collect());
        let (total, titles) = today_titles(&s, "2026-10-28");
        assert_eq!(total, 14);
        assert_eq!(titles.len(), 10);
        assert_eq!(titles[0], "Task 00");
    }

    #[test]
    fn an_empty_title_is_counted_not_listed() {
        let s = store(vec![task("  \n ", Some("2026-10-28"), false, 1.0), task("Real", Some("2026-10-28"), false, 2.0)]);
        assert_eq!(today_titles(&s, "2026-10-28"), (2, vec!["Real".to_string()]));
    }

    #[test]
    fn titles_are_cleaned_and_cut() {
        assert_eq!(clean("a\nb\tc\u{7f}"), "a b c");
        assert_eq!(clean("  two   spaces \u{85} here "), "two spaces here");
        assert_eq!(clean("<b>bold</b>"), "<b>bold</b>");
        let long = "é".repeat(300);
        assert_eq!(clean(&long).chars().count(), 200);
    }
}
