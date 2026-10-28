//! Notes' Today object on a session bus of its own (today.rs): it answers only the program it is meant for, is on the
//! bus only while the notes are open, and says Changed once for changes that come close together. Skipped where there
//! is no dbus-daemon. One test, since a thread's main context has one owner.

use std::rc::Rc;
use std::time::Duration;

use amethystora_notes::today::{self, Today, INTERFACE, PATH};
use amethystora_ui::glib::variant::ToVariant;
use amethystora_ui::{gio, glib};

struct Daemon {
    address: String,
    pid: String,
}

impl Daemon {
    fn start() -> Option<Daemon> {
        let out = std::process::Command::new("dbus-daemon").args(["--session", "--fork", "--print-address", "--print-pid"]).output().ok()?;
        let text = String::from_utf8_lossy(&out.stdout).to_string();
        let mut lines = text.lines();
        Some(Daemon { address: lines.next()?.to_string(), pid: lines.next()?.to_string() })
    }

    async fn connect(&self) -> gio::DBusConnection {
        gio::DBusConnection::for_address_future(&self.address, gio::DBusConnectionFlags::AUTHENTICATION_CLIENT | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION, None).await.expect("the test bus")
    }
}

impl Drop for Daemon {
    fn drop(&mut self) {
        let _ = std::process::Command::new("kill").arg(&self.pid).status();
    }
}

async fn sleep(ms: u64) {
    glib::timeout_future(Duration::from_millis(ms)).await;
}

/// GetToday on `name`, the error's D-Bus name when it fails
async fn ask(client: &gio::DBusConnection, name: &str) -> Result<(String, u32, Vec<String>), String> {
    client
        .call_future(Some(name), PATH, INTERFACE, "GetToday", None, Some(glib::VariantTy::new("(suas)").unwrap()), gio::DBusCallFlags::NONE, 5000)
        .await
        .map(|reply| reply.get::<(String, u32, Vec<String>)>().expect("(suas)"))
        .map_err(|error| gio::DBusError::remote_error(&error).map(|s| s.to_string()).unwrap_or_else(|| error.message().to_string()))
}

#[test]
fn today_on_the_bus() {
    let Some(daemon) = Daemon::start() else {
        eprintln!("skipped: no dbus-daemon");
        return;
    };
    glib::MainContext::default().block_on(async {
        let notes = daemon.connect().await;
        let client = daemon.connect().await;
        let name = notes.unique_name().expect("a name").to_string();
        let me = std::env::current_exe().unwrap().to_string_lossy().to_string();
        let answer: today::Answer = Rc::new(|| Some(("2026-10-28".to_string(), 2, vec!["Call the bakery".to_string(), "Water the plants".to_string()])));

        // Locked: nothing there
        let object = Today::new(notes.clone(), &me, None, answer.clone());
        object.set_open(false);
        let none = ask(&client, &name).await.unwrap_err();
        assert!(none.contains("UnknownObject") || none.contains("UnknownMethod"), "{none}");

        // Open: this test's program asks, and is answered
        object.set_open(true);
        assert!(object.registered());
        assert_eq!(ask(&client, &name).await, Ok(("2026-10-28".to_string(), 2, vec!["Call the bakery".to_string(), "Water the plants".to_string()])));
        // Introspection shows the interface and nothing else of Notes'
        let xml = client
            .call_future(Some(&name), PATH, "org.freedesktop.DBus.Introspectable", "Introspect", None, None, gio::DBusCallFlags::NONE, 5000)
            .await
            .unwrap()
            .child_value(0)
            .get::<String>()
            .unwrap();
        assert!(xml.contains(INTERFACE) && xml.contains("GetToday") && xml.contains("Changed"));

        // Changed: said once after registering, and once for two changes 100 ms apart
        sleep(700).await;
        let before = object.said();
        assert_eq!(before, 1);
        object.changed();
        sleep(100).await;
        object.changed();
        sleep(700).await;
        assert_eq!(object.said(), before + 1);

        // Locked again: gone
        object.set_open(false);
        let gone = ask(&client, &name).await.unwrap_err();
        assert!(gone.contains("UnknownObject") || gone.contains("UnknownMethod"), "{gone}");

        // Another program is refused, as if there were no object
        let other = Today::new(notes.clone(), "/usr/bin/gnome-shell", None, answer.clone());
        other.set_open(true);
        assert_eq!(ask(&client, &name).await, Err("org.freedesktop.DBus.Error.UnknownMethod".to_string()));
        other.unregister();

        // The right program that does not own the name it has to own is refused; once it owns it, it is answered
        let named = Today::new(notes.clone(), &me, Some("org.amethystora.TestShell"), answer.clone());
        named.set_open(true);
        assert_eq!(ask(&client, &name).await, Err("org.freedesktop.DBus.Error.UnknownMethod".to_string()));
        let owned = client
            .call_future(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                Some(&("org.amethystora.TestShell", 4u32).to_variant()), None, gio::DBusCallFlags::NONE, 5000)
            .await
            .unwrap()
            .child_value(0)
            .get::<u32>();
        assert_eq!(owned, Some(1));
        // The name changing hands makes Notes ask again
        sleep(200).await;
        assert!(ask(&client, &name).await.is_ok());
        named.unregister();
        drop(object);
    });
}
