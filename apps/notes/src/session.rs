//! What the window hears from the desktop and says to it, as Electron's Notification and powerMonitor did:
//! a reminder as a desktop notification, which brings the task up when it is clicked, and the screen
//! locking or the computer going to sleep, which lock the notes.
//!
//! Both are D-Bus: org.freedesktop.Notifications on the session bus, with the hints Electron's libnotify
//! sent (the desktop entry, so that GNOME files it under Notes, the urgency and the sender's pid); logind's
//! PrepareForSleep and the session's Lock on the system bus; and GNOME's ScreenSaver ActiveChanged on the
//! session bus, which main.js followed with `gdbus monitor`.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use amethystora_ui::{gio, glib};
use gio::prelude::*;

/// The application name Electron gave libnotify: its productName
const APP_NAME: &str = "Amethystora Notes";
const DESKTOP_ENTRY: &str = "amethystora-notes";

/// The notifications shown, by their id on the bus, and what a click on each does
pub struct Notifier {
    connection: Option<gio::DBusConnection>,
    clicks: Rc<RefCell<HashMap<u32, Rc<dyn Fn()>>>>,
    _subscription: Option<gio::SignalSubscription>,
}

impl Notifier {
    pub fn new() -> Notifier {
        let connection = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE).ok();
        let clicks: Rc<RefCell<HashMap<u32, Rc<dyn Fn()>>>> = Rc::new(RefCell::new(HashMap::new()));
        let subscription = connection.as_ref().map(|connection| {
            let clicks = clicks.clone();
            connection.subscribe_to_signal(
                Some("org.freedesktop.Notifications"),
                Some("org.freedesktop.Notifications"),
                None,
                Some("/org/freedesktop/Notifications"),
                None,
                gio::DBusSignalFlags::NONE,
                move |signal| {
                    let parameters = signal.parameters;
                    match signal.signal_name {
                        "ActionInvoked" => {
                            if let Some((id, action)) = parameters.get::<(u32, String)>() {
                                let click = clicks.borrow().get(&id).cloned();
                                if let (Some(click), "default") = (click, action.as_str()) {
                                    click();
                                }
                            }
                        }
                        "NotificationClosed" => {
                            if let Some((id, _)) = parameters.get::<(u32, u32)>() {
                                clicks.borrow_mut().remove(&id);
                            }
                        }
                        _ => {}
                    }
                },
            )
        });
        Notifier { connection, clicks, _subscription: subscription }
    }

    /// A reminder: its task's title, when it is due, and what a click on it does
    pub fn show(&self, title: &str, body: &str, on_click: Rc<dyn Fn()>) {
        let Some(connection) = self.connection.clone() else { return };
        let hints = glib::VariantDict::new(None);
        hints.insert_value("desktop-entry", &DESKTOP_ENTRY.to_variant());
        // NOTIFY_URGENCY_NORMAL
        hints.insert_value("urgency", &1u8.to_variant());
        hints.insert_value("sender-pid", &(std::process::id() as i64).to_variant());
        let parameters = glib::Variant::tuple_from_iter([
            APP_NAME.to_variant(),
            0u32.to_variant(),
            "".to_variant(),
            title.to_variant(),
            body.to_variant(),
            // Electron's libnotify notification offers its default action, which is the click
            vec!["default", "View"].to_variant(),
            hints.end(),
            (-1i32).to_variant(),
        ]);
        let clicks = self.clicks.clone();
        glib::spawn_future_local(async move {
            let answer = connection
                .call_future(
                    Some("org.freedesktop.Notifications"),
                    "/org/freedesktop/Notifications",
                    "org.freedesktop.Notifications",
                    "Notify",
                    Some(&parameters),
                    Some(glib::VariantTy::new("(u)").expect("a type")),
                    gio::DBusCallFlags::NONE,
                    -1,
                )
                .await;
            if let Some((id,)) = answer.ok().and_then(|reply| reply.get::<(u32,)>()) {
                clicks.borrow_mut().insert(id, on_click);
            }
        });
    }
}

/// What locks the notes: the computer going to sleep, the session locking, the screen saver coming on
pub struct LockWatch {
    _subscriptions: Vec<gio::SignalSubscription>,
}

impl LockWatch {
    pub fn new(on_lock: Rc<dyn Fn()>) -> LockWatch {
        let mut subscriptions = Vec::new();
        if let Ok(system) = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE) {
            let lock = on_lock.clone();
            subscriptions.push(system.subscribe_to_signal(
                Some("org.freedesktop.login1"),
                Some("org.freedesktop.login1.Manager"),
                Some("PrepareForSleep"),
                Some("/org/freedesktop/login1"),
                None,
                gio::DBusSignalFlags::NONE,
                move |signal| {
                    if signal.parameters.get::<(bool,)>().is_some_and(|(sleeping,)| sleeping) {
                        lock();
                    }
                },
            ));
            // The session this window runs in, which logind asks to lock when the screen locks
            let session = system
                .call_sync(
                    Some("org.freedesktop.login1"),
                    "/org/freedesktop/login1",
                    "org.freedesktop.login1.Manager",
                    "GetSessionByPID",
                    Some(&(std::process::id(),).to_variant()),
                    Some(glib::VariantTy::new("(o)").expect("a type")),
                    gio::DBusCallFlags::NONE,
                    2000,
                    gio::Cancellable::NONE,
                )
                .ok()
                .and_then(|reply| reply.child_value(0).str().map(str::to_string));
            if let Some(session) = session {
                let lock = on_lock.clone();
                subscriptions.push(system.subscribe_to_signal(
                    Some("org.freedesktop.login1"),
                    Some("org.freedesktop.login1.Session"),
                    Some("Lock"),
                    Some(&session),
                    None,
                    gio::DBusSignalFlags::NONE,
                    move |_| lock(),
                ));
            }
        }
        // GNOME says on the session bus when the screen locks, and the notes lock with it
        if let Ok(session) = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE) {
            let lock = on_lock.clone();
            subscriptions.push(session.subscribe_to_signal(
                None,
                Some("org.gnome.ScreenSaver"),
                Some("ActiveChanged"),
                Some("/org/gnome/ScreenSaver"),
                None,
                gio::DBusSignalFlags::NONE,
                move |signal| {
                    if signal.parameters.get::<(bool,)>().is_some_and(|(active,)| active) {
                        lock();
                    }
                },
            ));
        }
        LockWatch { _subscriptions: subscriptions }
    }
}
