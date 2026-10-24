//! Notifications, through the desktop's standard interface (`org.freedesktop.Notifications`), so that a fault
//! in the shell never loses a pairing prompt. The program names a notification by a key of its own; this
//! module maps it to the server's number, replaces a notification in place when the key is raised again, and
//! says what the person did with one (pressed a button, closed it).
//!
//! What a notification holds that a stranger wrote is plain text here. The standard interface lets a body
//! carry a little markup, so when the server says it reads markup the body is escaped for it, once, here.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use glib::variant::ToVariant;

use crate::text;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Notice {
    /// Raising the same key again replaces what is shown
    pub key: String,
    pub summary: String,
    /// Plain text, whatever it holds
    pub body: String,
    /// A file path or a themed icon name
    pub icon: Option<String>,
    /// Button id and label; the id `default` is a click on the notification itself
    pub actions: Vec<(String, String)>,
    pub urgent: bool,
    /// Milliseconds, 0 for never, -1 for the server's choice
    pub timeout_ms: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// A button, or the notification itself ("default"). `token` is the activation token the shell sent with it, which the
    /// program that is started for the button is to be given, so that its window comes to the front.
    Action { key: String, action: String, token: Option<String> },
    /// Closed by the person, not by us, not by pressing a button and not by running out of time
    Dismissed { key: String },
}

pub trait Notifier {
    fn notify(&self, notice: Notice);
    fn close(&self, key: &str);
    fn set_handler(&self, handler: Rc<dyn Fn(Event)>);
}

// --- The desktop's -----------------------------------------------------------------------------------------

const DESTINATION: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";
/// The launcher the shell shows the notification under
const DESKTOP_ENTRY: &str = "amethystora-phone";

pub struct Desktop {
    bus: gio::DBusConnection,
    ids: RefCell<HashMap<String, u32>>,
    keys: RefCell<HashMap<u32, String>>,
    /// Numbers the server will close next, which is not the person's doing: ones we closed ourselves, and ones a
    /// button was pressed on (a shell closes a notification when its button is pressed, and says it was dismissed)
    closing: RefCell<HashSet<u32>>,
    /// Activation tokens the shell sent, by notification number, for the button that follows
    tokens: RefCell<HashMap<u32, String>>,
    /// Keys whose Notify has not been answered yet: a close or a second notice for the key waits for the number
    in_flight: RefCell<HashSet<String>>,
    queued: RefCell<HashMap<String, Notice>>,
    close_after: RefCell<HashSet<String>>,
    markup: Cell<bool>,
    handler: RefCell<Option<Rc<dyn Fn(Event)>>>,
    subscriptions: RefCell<Vec<gio::SignalSubscriptionId>>,
}

impl Desktop {
    pub fn new(bus: gio::DBusConnection) -> Rc<Desktop> {
        let desktop = Rc::new(Desktop {
            bus,
            ids: RefCell::default(),
            keys: RefCell::default(),
            closing: RefCell::default(),
            tokens: RefCell::default(),
            in_flight: RefCell::default(),
            queued: RefCell::default(),
            close_after: RefCell::default(),
            markup: Cell::new(true),
            handler: RefCell::default(),
            subscriptions: RefCell::default(),
        });
        let weak = Rc::downgrade(&desktop);
        let mut subs = Vec::new();
        #[allow(deprecated)] // the stream form would need the program to poll it for a callback this small
        for signal in ["ActionInvoked", "NotificationClosed", "ActivationToken"] {
            let weak = weak.clone();
            subs.push(desktop.bus.signal_subscribe(Some(DESTINATION), Some(DESTINATION), Some(signal), Some(PATH), None, gio::DBusSignalFlags::NONE, move |_, _, _, _, signal, params| {
                if let Some(desktop) = weak.upgrade() {
                    desktop.signal(signal, params);
                }
            }));
        }
        *desktop.subscriptions.borrow_mut() = subs;
        // Whether the server reads markup in a body
        let weak = Rc::downgrade(&desktop);
        glib::spawn_future_local(async move {
            let Some(desktop) = weak.upgrade() else { return };
            let reply = desktop.bus.call_future(Some(DESTINATION), PATH, DESTINATION, "GetCapabilities", None, None, gio::DBusCallFlags::NONE, 2000).await;
            if let Ok(reply) = reply {
                if let Some(list) = reply.child_value(0).get::<Vec<String>>() {
                    desktop.markup.set(list.iter().any(|c| c == "body-markup"));
                }
            }
        });
        desktop
    }

    fn signal(&self, name: &str, params: &glib::Variant) {
        let Some(id) = params.child_value(0).get::<u32>() else { return };
        match name {
            // Sent before the button's own signal
            "ActivationToken" => {
                if let Some(token) = params.child_value(1).get::<String>() {
                    let mut tokens = self.tokens.borrow_mut();
                    if tokens.len() > 64 {
                        tokens.clear();
                    }
                    tokens.insert(id, token);
                }
            }
            "ActionInvoked" => {
                let Some(handler) = self.handler.borrow().clone() else { return };
                let (Some(action), Some(key)) = (params.child_value(1).get::<String>(), self.keys.borrow().get(&id).cloned()) else { return };
                let token = self.tokens.borrow_mut().remove(&id);
                handler(Event::Action { key, action, token });
                // A shell closes the notification once the button is pressed and calls it dismissed: it is not
                // the person taking it away, and what the button did (a reply, say) still needs it
                self.closing.borrow_mut().insert(id);
            }
            "NotificationClosed" => {
                let Some(handler) = self.handler.borrow().clone() else { return };
                let reason = params.child_value(1).get::<u32>().unwrap_or(0);
                let ours = self.closing.borrow_mut().remove(&id);
                self.tokens.borrow_mut().remove(&id);
                let Some(key) = self.keys.borrow_mut().remove(&id) else { return };
                // Only if it is the number we still hold for the key (a replaced one closes quietly)
                if self.ids.borrow().get(&key) == Some(&id) {
                    self.ids.borrow_mut().remove(&key);
                    if reason == 2 && !ours {
                        handler(Event::Dismissed { key });
                    }
                }
            }
            _ => {}
        }
    }

    fn body_for_server(&self, body: &str) -> String {
        let plain = text::clean(body);
        if self.markup.get() { text::escape_markup(&plain) } else { plain }
    }

    /// Sends one notice. The next notice for the key, or a close, waits for the server's number to come, so that
    /// a notice replaces the one before it and a close finds what it closes.
    fn send(self: &Rc<Self>, notice: Notice) {
        let key = notice.key.clone();
        if !self.in_flight.borrow_mut().insert(key.clone()) {
            self.queued.borrow_mut().insert(key.clone(), notice);
            self.close_after.borrow_mut().remove(&key);
            return;
        }
        let desktop = self.clone();
        let replaces = desktop.ids.borrow().get(&key).copied().unwrap_or(0);
        let mut hints = HashMap::<String, glib::Variant>::new();
        hints.insert("desktop-entry".into(), DESKTOP_ENTRY.to_variant());
        hints.insert("urgency".into(), (if notice.urgent { 2u8 } else { 1u8 }).to_variant());
        if let Some(icon) = notice.icon.as_deref().filter(|i| i.starts_with('/')) {
            hints.insert("image-path".into(), icon.to_variant());
        }
        let actions: Vec<String> = notice.actions.iter().flat_map(|(id, label)| [id.clone(), label.clone()]).collect();
        let icon = notice.icon.clone().filter(|i| !i.starts_with('/')).unwrap_or_default();
        let args = (text::tr("Phone"), replaces, icon, text::shorten(&text::clean_line(&notice.summary), 256), desktop.body_for_server(&notice.body), actions, hints, notice.timeout_ms);
        glib::spawn_future_local(async move {
            let reply = desktop.bus.call_future(Some(DESTINATION), PATH, DESTINATION, "Notify", Some(&args.to_variant()), None, gio::DBusCallFlags::NONE, 3000).await;
            match reply {
                Ok(reply) => {
                    if let Some(id) = reply.child_value(0).get::<u32>() {
                        desktop.ids.borrow_mut().insert(key.clone(), id);
                        desktop.keys.borrow_mut().insert(id, key.clone());
                    }
                }
                Err(e) => eprintln!("amethystora-connect: the desktop did not take a notification: {}", e.message()),
            }
            desktop.in_flight.borrow_mut().remove(&key);
            if desktop.close_after.borrow_mut().remove(&key) {
                desktop.close_now(&key);
            } else if let Some(next) = desktop.queued.borrow_mut().remove(&key) {
                desktop.send(next);
            }
        });
    }

    fn close_now(self: &Rc<Self>, key: &str) {
        let Some(id) = self.ids.borrow_mut().remove(key) else { return };
        self.keys.borrow_mut().remove(&id);
        self.closing.borrow_mut().insert(id);
        let desktop = self.clone();
        glib::spawn_future_local(async move {
            let _ = desktop.bus.call_future(Some(DESTINATION), PATH, DESTINATION, "CloseNotification", Some(&(id,).to_variant()), None, gio::DBusCallFlags::NONE, 3000).await;
        });
    }
}

impl Notifier for Rc<Desktop> {
    fn notify(&self, notice: Notice) {
        self.send(notice);
    }

    fn close(&self, key: &str) {
        if self.in_flight.borrow().contains(key) {
            // Its number has not come: it is closed when it does
            self.queued.borrow_mut().remove(key);
            self.close_after.borrow_mut().insert(key.to_string());
            return;
        }
        self.close_now(key);
    }

    fn set_handler(&self, handler: Rc<dyn Fn(Event)>) {
        *self.handler.borrow_mut() = Some(handler);
    }
}

// --- For tests ---------------------------------------------------------------------------------------------

/// Remembers what was raised, and lets a test press a button
#[derive(Default)]
pub struct Recorder {
    pub raised: RefCell<Vec<Notice>>,
    pub closed: RefCell<Vec<String>>,
    handler: RefCell<Option<Rc<dyn Fn(Event)>>>,
}

impl Recorder {
    pub fn last(&self, key: &str) -> Option<Notice> {
        self.raised.borrow().iter().rev().find(|n| n.key == key).cloned()
    }

    pub fn raised_with_prefix(&self, prefix: &str) -> Vec<Notice> {
        self.raised.borrow().iter().filter(|n| n.key.starts_with(prefix)).cloned().collect()
    }

    pub fn press(&self, key: &str, action: &str) {
        let handler = self.handler.borrow().clone();
        if let Some(handler) = handler {
            handler(Event::Action { key: key.to_string(), action: action.to_string(), token: None });
        }
    }

    /// A button pressed with the shell's activation token
    pub fn press_with_token(&self, key: &str, action: &str, token: &str) {
        let handler = self.handler.borrow().clone();
        if let Some(handler) = handler {
            handler(Event::Action { key: key.to_string(), action: action.to_string(), token: Some(token.to_string()) });
        }
    }

    pub fn dismiss(&self, key: &str) {
        let handler = self.handler.borrow().clone();
        if let Some(handler) = handler {
            handler(Event::Dismissed { key: key.to_string() });
        }
    }
}

impl Notifier for Rc<Recorder> {
    fn notify(&self, notice: Notice) {
        self.raised.borrow_mut().push(notice);
    }

    fn close(&self, key: &str) {
        self.closed.borrow_mut().push(key.to_string());
    }

    fn set_handler(&self, handler: Rc<dyn Fn(Event)>) {
        *self.handler.borrow_mut() = Some(handler);
    }
}
