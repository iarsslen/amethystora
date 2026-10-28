//! The program's notifications against a stand-in for the desktop's notification server on a bus of its own: what a
//! shell does when a button is pressed (it closes the notification and calls it dismissed), the server being slow to
//! answer, and the activation token the shell sends. One test, because the main context of a thread has one owner.

mod common;

use std::cell::RefCell;
use std::collections::HashMap;
use std::path::Path;
use std::rc::Rc;
use std::time::Duration;

use amethystora_connect::notify::{Desktop, Event, Notice, Notifier, Recorder};
use amethystora_connect::service::{Service, Settings};
use common::*;
use glib::variant::ToVariant;
use serde_json::json;

/// A notification server that remembers what it was asked and answers late when told to
struct Server {
    connection: gio::DBusConnection,
    notified: Rc<RefCell<Vec<(u32, u32, String)>>>,
    closed: Rc<RefCell<Vec<u32>>>,
    delay_ms: Rc<std::cell::Cell<u64>>,
    owner: Option<gio::OwnerId>,
}

impl Server {
    async fn start(daemon: &Daemon) -> Server {
        let connection = daemon.connect().await;
        let notified: Rc<RefCell<Vec<(u32, u32, String)>>> = Rc::default();
        let closed: Rc<RefCell<Vec<u32>>> = Rc::default();
        let delay_ms = Rc::new(std::cell::Cell::new(0u64));
        let node = gio::DBusNodeInfo::for_xml(
            "<node><interface name='org.freedesktop.Notifications'>
               <method name='Notify'><arg type='s' direction='in'/><arg type='u' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='as' direction='in'/><arg type='a{sv}' direction='in'/><arg type='i' direction='in'/><arg type='u' direction='out'/></method>
               <method name='CloseNotification'><arg type='u' direction='in'/></method>
               <method name='GetCapabilities'><arg type='as' direction='out'/></method>
             </interface></node>",
        )
        .unwrap();
        let (log, shut, wait) = (notified.clone(), closed.clone(), delay_ms.clone());
        let next = Rc::new(std::cell::Cell::new(100u32));
        connection
            .register_object("/org/freedesktop/Notifications", &node.lookup_interface("org.freedesktop.Notifications").unwrap())
            .method_call(move |_, _, _, _, method, params, invocation| match method {
                "Notify" => {
                    let replaces = params.child_value(1).get::<u32>().unwrap();
                    let id = if replaces != 0 {
                        replaces
                    } else {
                        next.set(next.get() + 1);
                        next.get()
                    };
                    // Summary, body and the sound asked for, if any
                    let sound = glib::VariantDict::new(Some(&params.child_value(6))).lookup_value("sound-name", None).and_then(|v| v.get::<String>()).unwrap_or_default();
                    log.borrow_mut().push((id, replaces, params.child_value(3).get::<String>().unwrap_or_default() + "|" + &params.child_value(4).get::<String>().unwrap_or_default() + "|" + &sound));
                    let answer = move || invocation.return_value(Some(&(id,).to_variant()));
                    if wait.get() == 0 {
                        answer();
                    } else {
                        glib::timeout_add_local_once(Duration::from_millis(wait.get()), answer);
                    }
                }
                "CloseNotification" => {
                    shut.borrow_mut().push(params.child_value(0).get::<u32>().unwrap());
                    invocation.return_value(None);
                }
                "GetCapabilities" => invocation.return_value(Some(&(vec!["body".to_string(), "actions".to_string(), "body-markup".to_string()],).to_variant())),
                _ => invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", "no such method"),
            })
            .build()
            .unwrap();
        let owner = gio::bus_own_name_on_connection(&connection, "org.freedesktop.Notifications", gio::BusNameOwnerFlags::NONE, |_, _| {}, |_, _| {});
        pause(300).await;
        Server { connection, notified, closed, delay_ms, owner: Some(owner) }
    }

    fn signal(&self, name: &str, args: glib::Variant) {
        self.connection.emit_signal(None, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", name, Some(&args)).unwrap();
    }

    /// What a shell does for a button: the token, the action, and then the notification is closed as dismissed
    fn press(&self, id: u32, action: &str, token: &str) {
        self.signal("ActivationToken", (id, token).to_variant());
        self.signal("ActionInvoked", (id, action).to_variant());
        self.signal("NotificationClosed", (id, 2u32).to_variant());
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.take() {
            gio::bus_unown_name(owner);
        }
    }
}

fn notice(key: &str, summary: &str) -> Notice {
    Notice { key: key.into(), summary: summary.into(), body: "body".into(), actions: vec![("reply".into(), "Reply".into())], ..Notice::default() }
}

#[test]
fn the_desktop_and_its_ways() {
    let Some(daemon) = Daemon::start() else {
        eprintln!("dbus-daemon is not here: the notification scenarios are skipped");
        return;
    };
    let root = std::env::temp_dir().join(format!("amethystora-connect-notifications-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    glib::MainContext::default().block_on(async {
        let server = Server::start(&daemon).await;
        races(&daemon, &server).await;
        a_button_is_not_a_dismissal(&daemon, &server).await;
        reply_finds_its_notification(&daemon, &server, &root).await;
    });
    let _ = std::fs::remove_dir_all(&root);
}

/// The server is slow to answer: a close does not miss, and a second notice replaces the first
async fn races(daemon: &Daemon, server: &Server) {
    let desktop = Desktop::new(daemon.connect().await);
    pause(200).await;
    server.delay_ms.set(300);
    desktop.notify(notice("race:close", "to be withdrawn"));
    desktop.close("race:close");
    until("the notification to come and go", || !server.notified.borrow().is_empty() && !server.closed.borrow().is_empty()).await;
    let (id, ..) = server.notified.borrow()[0].clone();
    assert_eq!(server.closed.borrow()[0], id, "what was withdrawn before the server answered is closed when it does");

    let before = server.notified.borrow().len();
    desktop.notify(notice("race:replace", "first"));
    desktop.notify(notice("race:replace", "second"));
    desktop.notify(notice("race:replace", "third"));
    until("the replacements", || server.notified.borrow().len() >= before + 2).await;
    pause(800).await;
    let calls = server.notified.borrow()[before..].to_vec();
    assert_eq!(calls.len(), 2, "the second notice waited for the first's number and the third took its place: {calls:?}");
    assert_eq!(calls[0].1, 0);
    assert_eq!(calls[1].1, calls[0].0, "and replaced it");
    assert!(calls[1].2.contains("third"));
    server.delay_ms.set(0);
}

/// A shell closes a notification when its button is pressed and calls it dismissed
async fn a_button_is_not_a_dismissal(daemon: &Daemon, server: &Server) {
    let desktop = Desktop::new(daemon.connect().await);
    let events: Rc<RefCell<Vec<Event>>> = Rc::default();
    let sink = events.clone();
    desktop.set_handler(Rc::new(move |event| sink.borrow_mut().push(event)));
    pause(200).await;
    let before = server.notified.borrow().len();
    desktop.notify(notice("button:one", "pressed"));
    desktop.notify(notice("button:two", "swiped away"));
    until("both notifications", || server.notified.borrow().len() >= before + 2).await;
    let ids: HashMap<String, u32> = server.notified.borrow()[before..].iter().map(|(id, _, text)| (text.split('|').next().unwrap().to_string(), *id)).collect();

    server.press(ids["pressed"], "reply", "token-of-the-shell");
    until("the button", || !events.borrow().is_empty()).await;
    pause(300).await;
    assert_eq!(*events.borrow(), vec![Event::Action { key: "button:one".into(), action: "reply".into(), token: Some("token-of-the-shell".into()) }], "a button is a button, and nothing is dismissed");

    server.signal("NotificationClosed", (ids["swiped away"], 2u32).to_variant());
    until("the swipe", || events.borrow().len() == 2).await;
    assert_eq!(events.borrow()[1], Event::Dismissed { key: "button:two".into() });
    // Expiry is not a dismissal, nor is what the program closes itself
    desktop.notify(notice("button:three", "expires"));
    until("the third", || server.notified.borrow().len() >= before + 3).await;
    let third = server.notified.borrow()[before + 2].0;
    server.signal("NotificationClosed", (third, 1u32).to_variant());
    desktop.notify(notice("button:four", "closed here"));
    until("the fourth", || server.notified.borrow().len() >= before + 4).await;
    desktop.close("button:four");
    let fourth = server.notified.borrow()[before + 3].0;
    until("its close", || server.closed.borrow().contains(&fourth)).await;
    server.signal("NotificationClosed", (fourth, 2u32).to_variant());
    pause(300).await;
    assert_eq!(events.borrow().len(), 2);
}

/// The whole of finding 4: Reply from a notification starts the app, and the notification is still the phone's to
/// answer afterwards, and not cancelled on the phone
async fn reply_finds_its_notification(daemon: &Daemon, server: &Server, root: &Path) {
    let phone = make(root, "Sam phone", "phone", true, false);
    let desktop = Desktop::new(daemon.connect().await);
    let (cfg, dir) = config_for(root, "Studio laptop", "laptop", false, false, |c| {
        // A launcher that says how it was called, so that the token can be seen to go with the program
        let script = c.app_command[0].clone();
        let launcher = format!("{script}.launcher");
        std::fs::write(&launcher, format!("#!/bin/sh\necho \"LAUNCHER $@\" >> {}/launcher.log\nwhile [ \"$1\" != -- ]; do shift; done\nshift\nexec \"$@\"\n", Path::new(&script).parent().unwrap().display())).unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&launcher, std::fs::Permissions::from_mode(0o755)).unwrap();
        c.launcher = vec![launcher];
    });
    let notices = Rc::new(Recorder::default());
    let computer = started(Service::new(cfg, Box::new(desktop), Settings { name: "Studio laptop".into(), ..Settings::default() }, None).unwrap(), notices, dir);
    let (cid, pid) = (computer.id(), phone.id());
    // The computer has the desktop's notifications, so the person at the phone says yes
    computer.service.connect_to(&format!("127.0.0.1:{}", phone.port())).unwrap();
    until("the two to be connected", || computer.service.device(&pid).is_some_and(|d| d.connected()) && phone.service.device(&cid).is_some_and(|d| d.connected())).await;
    computer.service.pair(&pid).unwrap();
    until("the phone's prompt", || prompt_of(&phone, &cid).is_some()).await;
    phone.notices.press(&prompt_of(&phone, &cid).unwrap().key, "accept");
    until("the pairing", || computer.device(&pid).paired() && phone.device(&cid).paired()).await;

    let phone_id = "0|org.example.chat|55|null|10123";
    phone.service.send_to(
        &phone.device(&cid),
        "kdeconnect.notification",
        json!({ "id": phone_id, "appName": "Example Chat", "title": "Sam", "text": "Are you coming tonight?", "isClearable": true, "requestReplyId": "5b1c2f9e-3d44-4a0a-9c53-0a5d0f6a7e11" }),
    );
    until("the notification on the desktop", || server.notified.borrow().iter().any(|(_, _, t)| t.starts_with("Example Chat"))).await;
    let id = server.notified.borrow().iter().find(|(_, _, t)| t.starts_with("Example Chat")).unwrap().0;

    server.press(id, "reply", "activation-token-1");
    until("the app to be started", || std::fs::read_to_string(computer.dir.join("app.log")).is_ok_and(|l| l.contains("reply"))).await;
    pause(500).await;
    assert!(std::fs::read_to_string(computer.dir.join("app.log")).unwrap().contains(&format!("reply -- {pid} {phone_id}")));
    let launched = std::fs::read_to_string(computer.dir.join("launcher.log")).unwrap_or_default();
    assert!(launched.contains("--setenv=XDG_ACTIVATION_TOKEN=activation-token-1"), "the token goes with the program: {launched:?}");
    // The notification is still there for the app to answer, and the phone was not told to drop it
    let repliable = computer.service.repliable(&pid).unwrap();
    assert_eq!(repliable.len(), 1, "the button did not take the notification away");
    assert!(phone.saw("kdeconnect.notification.request").iter().all(|p| p.str("cancel").is_none()), "and the phone was not asked to close it");
    let our_id = repliable[0]["id"].get::<String>().unwrap();
    computer.service.reply_to_notification(&pid, &our_id, "On my way.").unwrap();
    until("the reply to reach the phone", || !phone.saw("kdeconnect.notification.reply").is_empty()).await;

    // A swipe, which is the person taking it away, is told to the phone
    let other = "0|org.example.mail|7|null|10123";
    phone.service.send_to(&phone.device(&cid), "kdeconnect.notification", json!({ "id": other, "appName": "Example Mail", "title": "Hello", "text": "World", "isClearable": true }));
    until("the second notification", || server.notified.borrow().iter().any(|(_, _, t)| t.starts_with("Example Mail"))).await;
    let second = server.notified.borrow().iter().find(|(_, _, t)| t.starts_with("Example Mail")).unwrap().0;
    server.signal("NotificationClosed", (second, 2u32).to_variant());
    until("the dismissal to reach the phone", || phone.saw("kdeconnect.notification.request").iter().any(|p| p.str("cancel") == Some(other))).await;
    assert!(server.notified.borrow().iter().filter(|(_, _, t)| !t.is_empty()).all(|(_, _, t)| t.ends_with('|')), "no sound is asked for but a text message's");

    // A text message asks the server for the phone's own sound in the desktop's sound theme
    let text = "0|com.google.android.apps.messaging|3|null|10123";
    phone.service.send_to(&phone.device(&cid), "kdeconnect.notification", json!({ "id": text, "appName": "Messages", "title": "Sam", "text": "Running late", "isClearable": true }));
    until("the text message on the desktop", || server.notified.borrow().iter().any(|(_, _, t)| t.contains("Running late"))).await;
    assert!(server.notified.borrow().iter().find(|(_, _, t)| t.contains("Running late")).unwrap().2.ends_with("|message-new-instant-phone"));
}
