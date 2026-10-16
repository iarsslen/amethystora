//! The gate, as notes.js drew it: the first run's choice of a passphrase, and the lock screen, with the
//! stone of the boot splash. Its stem lifts like a latch while the passphrase is checked.

use std::rc::Rc;

use amethystora_ui::gem::{Gem, Motion};
use amethystora_ui::{glib, gtk, t, ui};
use gtk::prelude::*;

use super::widgets::{self, button, key_status, link_button, password, say, Action, Dialog, PassphraseFields};
use super::Notes;
use crate::backend;
use crate::passkeys::{self, Unlocked};

/// The mark as its bowl and its stem, so that the stem can lift by itself while the notes are opened
fn gem(active: bool) -> Gem {
    let gem = Gem::halo(112.0, 96.0, 28.0);
    gem.set_motion(if active { Motion::Breathe(2.4) } else { Motion::Still });
    gem
}

impl Notes {
    pub fn render_gate(&self) {
        self.sidebar.set_visible(false);
        self.controls_for(None);
        ui::clear(&self.main);
        self.editor.replace(None);
        let status = self.ui.borrow().status;
        let page: gtk::Widget = match status {
            "loading" => {
                let spinner = crate::icons::icon("spinner", 28);
                spinner.set_spinning(true);
                let loading = ui::vbox(0, &["loading"]);
                loading.set_valign(gtk::Align::Center);
                loading.set_vexpand(true);
                loading.append(&spinner);
                loading.upcast()
            }
            "new" => self.setup_page(),
            _ => self.unlock_page(),
        };
        let scroller = gtk::ScrolledWindow::builder().hscrollbar_policy(gtk::PolicyType::Never).vexpand(true).hexpand(true).child(&page).build();
        self.main.append(&scroller);
    }

    /// A column at most 560 pixels wide, its padding included, centred, filling the window's height
    fn gate_column(spacing: i32) -> (gtk::Box, gtk::Widget) {
        let gate = ui::vbox(spacing, &["gate"]);
        gate.set_valign(gtk::Align::Center);
        let clamp = adw::Clamp::builder().maximum_size(560).tightening_threshold(560).child(&gate).vexpand(true).build();
        (gate, clamp.upcast())
    }

    fn setup_page(&self) -> gtk::Widget {
        let (gate, page) = Self::gate_column(14);
        let fields = Rc::new(PassphraseFields::new(false));
        gate.append(&gem(true));
        gate.append(&centred(&t!("Your notes, on this computer only"), &["h1"]));
        let lead = centred(&t!("Notes and tasks that are never synced and never sent anywhere. Encrypted with AES-256, which stays secure against quantum computers."), &["lead"]);
        gate.append(&ui::limit_center(&lead, 600));

        let card = ui::vbox(12, &["card", "gate-card"]);
        let head = ui::hbox(14, &["gate-card-head"]);
        let square = widgets::row_icon("shield", "accent", 22);
        square.set_valign(gtk::Align::Start);
        head.append(&square);
        let words = ui::vbox(0, &["grow"]);
        words.set_hexpand(true);
        words.append(&ui::label(&t!("Protect them with a passphrase"), &["strong"]));
        words.append(&ui::label(&t!("Recommended. Your notes, tasks and attachments are encrypted on disk, and open only with the passphrase."), &["soft", "small"]));
        head.append(&words);
        card.append(&head);
        for node in fields.nodes() {
            card.append(&node);
        }
        let callout = ui::hbox(12, &["callout", "caution"]);
        callout.append(&crate::icons::icon("alert", 20));
        let warning = ui::label(&t!("Nobody can recover a forgotten passphrase: not Amethystora, not an administrator, not anyone. Keep it somewhere safe."), &["p"]);
        warning.set_hexpand(true);
        callout.append(&warning);
        card.append(&callout);
        let submit = button(&t!("Encrypt my notes"), Some("lock"), &["primary"], || {});
        let actions = ui::hbox(12, &["actions"]);
        actions.set_halign(gtk::Align::End);
        actions.append(&submit);
        card.append(&actions);
        let weak = self.me.clone();
        let (copy, submitting) = (fields.clone(), submit.clone());
        let encrypt = Rc::new(move || {
            let Some(this) = weak.upgrade() else { return };
            let Some(passphrase) = copy.check() else { return };
            submitting.set_sensitive(false);
            if let Some(words) = ui::button_words(&submitting) {
                words.set_label(&t!("Encrypting…"));
            }
            glib::spawn_future_local(async move {
                let result = backend::create(&this.backend, Some(passphrase)).await;
                this.apply_state(result.err());
            });
        });
        let go = encrypt.clone();
        submit.connect_clicked(move |_| go());
        for entry in [&fields.first, &fields.second] {
            let go = encrypt.clone();
            entry.connect_activate(move |_| go());
        }
        gate.append(&card);

        let plain = link_button(&t!("Continue without encryption"), None, &["quiet"], self.on(|this| {
            this.spawn(async |this| {
                let sure = widgets::confirm(
                    &t!("Keep your notes unencrypted?"),
                    &t!("Anyone who can read your files, from a backup or from this disk in another computer, can read your notes. You can turn encryption on later in Settings."),
                    &t!("Keep unencrypted"),
                    false,
                )
                .await;
                if sure {
                    let result = backend::create(&this.backend, None).await;
                    this.apply_state(result.err());
                }
            });
        }));
        plain.set_halign(gtk::Align::Center);
        gate.append(&plain);
        gate.append(&centred(&t!("Coming from Joplin or Planify? Import them from Settings once you are in."), &["note"]));
        let first = fields.first.clone();
        glib::idle_add_local_once(move || {
            first.grab_focus();
        });
        page
    }

    fn unlock_page(&self) -> gtk::Widget {
        let (gate, page) = Self::gate_column(14);
        let input = password(&t!("Passphrase"));
        input.set_hexpand(true);
        let error = ui::label("", &["error", "small"]);
        error.set_xalign(0.5);
        error.set_visible(false);
        let submit = button(&t!("Unlock"), Some("unlock"), &["primary"], || {});
        let stone = gem(false);
        self.gate_gem.replace(Some(stone.clone()));
        gate.append(&stone);
        gate.append(&centred(&t!("Your notes are locked"), &["h1"]));
        gate.append(&centred(&t!("Enter your passphrase to open them."), &["lead"]));
        let form = ui::hbox(10, &["unlock"]);
        form.append(&input);
        form.append(&submit);
        let limited = ui::limit_center(&form, 420);
        gate.append(&limited);
        gate.append(&error);
        let weak = self.me.clone();
        let (reading, failing, pressing, latch) = (input.clone(), error.clone(), submit.clone(), stone.clone());
        let unlock = Rc::new(move || {
            let Some(this) = weak.upgrade() else { return };
            let passphrase = reading.text().to_string();
            if passphrase.is_empty() || !pressing.is_sensitive() {
                return;
            }
            pressing.set_sensitive(false);
            latch.set_motion(Motion::Latch);
            say(&failing, "");
            let (reading, failing, pressing, latch) = (reading.clone(), failing.clone(), pressing.clone(), latch.clone());
            glib::spawn_future_local(async move {
                match backend::unlock(&this.backend, passphrase).await {
                    Err(problem) => {
                        pressing.set_sensitive(true);
                        latch.set_motion(Motion::Still);
                        say(&failing, &problem);
                        reading.grab_focus();
                        reading.select_region(0, -1);
                    }
                    Ok(()) => {
                        reading.set_text("");
                        this.apply_state(None);
                    }
                }
            });
        });
        let go = unlock.clone();
        submit.connect_clicked(move |_| go());
        let go = unlock.clone();
        input.connect_activate(move |_| go());
        if !self.ui.borrow().passkeys.is_empty() {
            let failing = error.clone();
            let link = link_button(&t!("Open with a passkey"), Some("key"), &[], self.on(move |this| this.passkey_unlock(failing.clone())));
            link.set_halign(gtk::Align::Center);
            gate.append(&link);
        }
        let focus = input.clone();
        glib::idle_add_local_once(move || {
            focus.grab_focus();
        });
        page
    }

    /// Opens the notes with a security key. One that reads a fingerprint needs nothing more; for any
    /// other, the backend answers that it needs the PIN, and it is asked for here.
    fn passkey_unlock(&self, error: gtk::Label) {
        if self.backend.borrow().touching.is_some() {
            return;
        }
        self.spawn(async move |this| {
            key_status(&error, &t!("Looking for your security key. Touch it if it blinks."), true);
            let backend = this.backend.clone();
            let mut result = passkeys::with_key(&backend, async || passkeys::unlock(&backend, String::new()).await).await;
            key_status(&error, "", false);
            if result == Ok(Unlocked::NeedsPin) {
                let input = password(&t!("Security key PIN"));
                let problem = ui::label("", &["error", "small"]);
                problem.set_visible(false);
                let (reading, saying, backend) = (input.clone(), problem.clone(), this.backend.clone());
                let answer = widgets::modal(Dialog {
                    title: t!("Open with a passkey"),
                    text: Some(t!("Enter the PIN of your security key, then touch the key when it blinks.")),
                    body: vec![input.upcast(), problem.upcast()],
                    actions: vec![
                        Action::plain(&t!("Cancel"), None),
                        Action::primary(&t!("Unlock"), false, move || {
                            let (reading, saying, backend) = (reading.clone(), saying.clone(), backend.clone());
                            Box::pin(async move {
                                let pin = reading.text().to_string();
                                if pin.is_empty() || backend.borrow().touching.is_some() {
                                    return None;
                                }
                                key_status(&saying, &t!("Touch your security key when it blinks."), true);
                                let answer = passkeys::with_key(&backend, async || passkeys::unlock(&backend, pin).await).await;
                                match answer {
                                    Err(problem) => {
                                        key_status(&saying, &problem, false);
                                        reading.select_region(0, -1);
                                        None
                                    }
                                    other => Some(Some(other)),
                                }
                            })
                        }),
                    ],
                    wide: false,
                })
                .await
                .flatten();
                match answer {
                    Some(answer) => result = answer,
                    None => {
                        // Closed while the key was still waiting to be touched
                        passkeys::cancel(&this.backend);
                        return;
                    }
                }
            }
            match result {
                Err(problem) => say(&error, &problem),
                Ok(_) => this.apply_state(None),
            }
        });
    }
}

/// A line of the gate, centred as its text-align: center had it
fn centred(text: &str, classes: &[&str]) -> gtk::Label {
    let label = ui::label(text, classes);
    label.set_justify(gtk::Justification::Center);
    label.set_xalign(0.5);
    label
}

use amethystora_ui::adw;
