//! Who called on the session bus. An app that answers on the bus answers only the program it is meant for: the
//! bus says which process a connection belongs to and whose it is, the file that process runs (`/proc/PID/exe`)
//! says what it is, and, for a program that owns a well-known name on the bus (GNOME Shell owns `org.gnome.Shell`),
//! the caller has to be that name's owner as well. A caller the bus cannot vouch for, of another account, running
//! another file or not owning the name, is no one. Where the bus hands over the process itself (dbus-broker's
//! `ProcessFD`, a pidfd), the process is read through it, so that a number the kernel has given to another process
//! since cannot stand in for it. Each connection is asked about once, and the answer kept until it leaves the bus, or
//! until a well-known name changes hands.
//!
//! This keeps other programs of the account from asking what an app tells only the shell, as a sandboxed program
//! would try to: it is not a boundary against the account's own code outside a sandbox, which can take the shell's
//! name over (breaking the running shell to do so), or read the app's memory where the kernel lets a process of the
//! same account trace another.

use std::cell::RefCell;
use std::collections::HashMap;
use std::os::fd::{AsRawFd, OwnedFd};
use std::rc::Rc;

use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;
use gtk::glib::variant::ToVariant;

/// The decision itself, apart from the bus: the caller's account and file against this account and the one file
/// allowed, and whether it owns the name it has to own
pub fn allowed(caller_uid: Option<u32>, own_uid: u32, caller_exe: Option<&str>, exe: &str, owns_name: bool) -> bool {
    owns_name && matches!((caller_uid, caller_exe), (Some(uid), Some(found)) if uid == own_uid && found == exe)
}

/// The account, the process and, where the bus gives one, a pidfd of the process a connection belongs to
async fn credentials(connection: &gio::DBusConnection, sender: &str) -> Option<(u32, u32, Option<OwnedFd>)> {
    let (reply, fds) = connection
        .call_with_unix_fd_list_future(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetConnectionCredentials",
            Some(&(sender,).to_variant()),
            Some(glib::VariantTy::new("(a{sv})").expect("a type")),
            gio::DBusCallFlags::NONE,
            2000,
            None::<&gio::UnixFDList>,
        )
        .await
        .ok()?;
    let found = glib::VariantDict::new(Some(&reply.child_value(0)));
    let uid = found.lookup::<u32>("UnixUserID").ok().flatten()?;
    let pid = found.lookup::<u32>("ProcessID").ok().flatten()?;
    let pidfd = found
        .lookup_value("ProcessFD", Some(glib::VariantTy::HANDLE))
        .and_then(|value| value.get::<glib::variant::Handle>())
        .and_then(|handle| fds.as_ref()?.get(handle.0).ok());
    Some((uid, pid, pidfd))
}

/// The process a pidfd stands for, as the kernel has it: None once it has ended
fn pid_of(pidfd: &OwnedFd) -> Option<u32> {
    let info = std::fs::read_to_string(format!("/proc/self/fdinfo/{}", pidfd.as_raw_fd())).ok()?;
    let pid: i64 = info.lines().find_map(|line| line.strip_prefix("Pid:"))?.trim().parse().ok()?;
    u32::try_from(pid).ok().filter(|pid| *pid > 0)
}

/// Whether `sender` owns the well-known name `name`
async fn owns(connection: &gio::DBusConnection, sender: &str, name: &str) -> bool {
    let reply = connection
        .call_future(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetNameOwner",
            Some(&(name,).to_variant()),
            Some(glib::VariantTy::new("(s)").expect("a type")),
            gio::DBusCallFlags::NONE,
            2000,
        )
        .await;
    reply.ok().and_then(|reply| reply.child_value(0).get::<String>()).as_deref() == Some(sender)
}

/// Whether the connection `sender` belongs to a process of this account running `exe`, and owns `name` when one is
/// given
pub async fn is_program(connection: &gio::DBusConnection, sender: &str, exe: &str, name: Option<&str>) -> bool {
    let owns_name = match name {
        Some(name) => owns(connection, sender, name).await,
        None => true,
    };
    let Some((uid, pid, pidfd)) = credentials(connection, sender).await else { return false };
    // Through the pidfd when there is one: the very process, alive before and after its file is read
    let pid = match &pidfd {
        Some(fd) => match pid_of(fd) {
            Some(found) => found,
            None => return false,
        },
        None => pid,
    };
    let found = std::fs::read_link(format!("/proc/{pid}/exe")).ok();
    if pidfd.as_ref().is_some_and(|fd| pid_of(fd) != Some(pid)) {
        return false;
    }
    // SAFETY: getuid has no arguments and cannot fail
    let own = unsafe { libc::getuid() };
    allowed(Some(uid), own, found.as_ref().and_then(|path| path.to_str()), exe, owns_name)
}

/// The answers for the connections that called, forgotten as each leaves the bus, and all of them when a well-known
/// name changes hands
#[derive(Clone, Default)]
pub struct Callers {
    known: Rc<RefCell<HashMap<String, bool>>>,
    watch: Rc<RefCell<Option<gio::SignalSubscriptionId>>>,
}

impl Callers {
    /// Starts following the connections and names of `connection`'s bus
    pub fn watch(&self, connection: &gio::DBusConnection) {
        if self.watch.borrow().is_some() {
            return;
        }
        let known = Rc::downgrade(&self.known);
        #[allow(deprecated)] // the stream form would need the app to poll it for a callback this small
        let id = connection.signal_subscribe(
            Some("org.freedesktop.DBus"),
            Some("org.freedesktop.DBus"),
            Some("NameOwnerChanged"),
            Some("/org/freedesktop/DBus"),
            None,
            gio::DBusSignalFlags::NONE,
            move |_, _, _, _, _, params| {
                let Some((name, _, new)) = params.get::<(String, String, String)>() else { return };
                let Some(known) = known.upgrade() else { return };
                if !name.starts_with(':') {
                    // Who owns a name is asked again
                    known.borrow_mut().clear();
                } else if new.is_empty() {
                    known.borrow_mut().remove(&name);
                }
            },
        );
        self.watch.replace(Some(id));
    }

    pub fn unwatch(&self, connection: &gio::DBusConnection) {
        if let Some(id) = self.watch.take() {
            #[allow(deprecated)]
            connection.signal_unsubscribe(id);
        }
        self.known.borrow_mut().clear();
    }

    /// Whether `sender` runs `exe` as this account (and owns `name`), asked of the bus the first time only
    pub async fn check(&self, connection: &gio::DBusConnection, sender: &str, exe: &str, name: Option<&str>) -> bool {
        if let Some(answer) = self.known.borrow().get(sender) {
            return *answer;
        }
        let answer = is_program(connection, sender, exe, name).await;
        self.known.borrow_mut().insert(sender.to_string(), answer);
        answer
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_this_account_running_that_file_and_owning_the_name() {
        let shell = "/usr/bin/gnome-shell";
        assert!(allowed(Some(1000), 1000, Some(shell), shell, true));
        assert!(!allowed(Some(1000), 1000, Some(shell), shell, false));
        assert!(!allowed(Some(1001), 1000, Some(shell), shell, true));
        assert!(!allowed(Some(1000), 1000, Some("/usr/bin/gdbus"), shell, true));
        assert!(!allowed(Some(1000), 1000, Some("/usr/bin/gnome-shell (deleted)"), shell, true));
        assert!(!allowed(None, 1000, Some(shell), shell, true));
        assert!(!allowed(Some(1000), 1000, None, shell, true));
        assert!(!allowed(Some(0), 1000, Some(shell), shell, true));
    }
}
