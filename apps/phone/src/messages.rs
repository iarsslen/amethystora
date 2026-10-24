//! The Messages page: the conversations of a phone, a chat, a box to write in, and a way to begin a new
//! conversation. Everything is what the program amethystora-connect holds in memory for the phone while it is
//! connected: nothing is stored here, and what the window shows of a conversation goes when the window closes.
//!
//! The list comes from `ListConversations`, a chat from `ListMessages`; both are filled by the phone after a
//! `Request…` call, so the window asks, shows what is there, and shows again when `ConversationsChanged` or
//! `MessagesChanged` says there is more. The words of a message are text in a label (links are links only when
//! clicked, and open in the browser), never markup. Group conversations are read-only: the program sends to one
//! address in the first version, and says so rather than send to part of a group.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

use amethystora_ui::i18n::{self, DateStyle};
use amethystora_ui::{glib, gtk, t, ui};
use gtk::prelude::*;

use crate::icons::icon;
use crate::model::{self, bdi, Conversation, Device, Message, Pending, Row};
use crate::widgets::{self, Look};
use crate::{failure_text, Page, Phone};

/// How many conversations are asked for, and how many messages of a chat
const MOST_CONVERSATIONS: i32 = 300;
const MOST_MESSAGES: i32 = 500;
/// How many messages one request for older ones asks the phone for
const PAGE: i32 = 50;
/// The conversations are asked of the phone again when the page is opened after this many seconds
const STALE: f64 = 60.0;
/// The phone has this long to answer before the window says it has not
const PATIENCE: f64 = 30.0;

/// What the chat side shows
#[derive(Debug, Clone, PartialEq, Default)]
pub enum View {
    #[default]
    None,
    /// A conversation, by the phone's thread
    Thread(i64),
    /// Choosing whom to write to
    New,
    /// A conversation not begun: this address, and the thread comes with the phone's first answer
    Draft(String),
}

/// Whether older messages of the open conversation can be asked for
#[derive(Debug, Clone, Copy, PartialEq, Default)]
enum Older {
    #[default]
    Idle,
    /// Asked at this time, when the chat had this many messages
    Loading(f64, usize),
    /// The phone has no more
    Done,
}

#[derive(Default)]
pub struct Texts {
    device: RefCell<Option<String>>,
    conversations: RefCell<Vec<Conversation>>,
    view: RefCell<View>,
    messages: RefCell<Vec<Message>>,
    pending: RefCell<Vec<Pending>>,
    /// When the conversations were last asked of the phone, and when the open chat was
    asked_list: Cell<f64>,
    asked_chat: Cell<f64>,
    older: Cell<Older>,
    /// Keep the chat scrolled to its end while it fills
    stick: Cell<bool>,
    /// The chat's size and place before older messages were added, to keep what was in view in view
    restore: Cell<Option<(f64, f64)>>,
    timer: RefCell<Option<glib::SourceId>>,
}

impl Texts {
    /// The phone to read first, before the phones have been listed
    pub fn remember(&self, device: &str) {
        self.device.replace(Some(device.to_string()));
    }

    pub fn device(&self) -> Option<String> {
        self.device.borrow().clone()
    }
}

/// The widgets of the page made once
pub struct Parts {
    pub root: gtk::Box,
    /// Shown instead of the two sides when there is no phone to read
    empty: gtk::Box,
    body: gtk::Box,
    chips: adw_wrap,
    conversations: gtk::Box,
    avatar_slot: gtk::Box,
    title: gtk::Label,
    subtitle: gtk::Label,
    disconnected: gtk::Box,
    note: gtk::Label,
    chat_scroller: gtk::ScrolledWindow,
    chat: gtk::Box,
    new_box: gtk::Box,
    new_entry: gtk::Entry,
    new_choices: gtk::Box,
    compose: gtk::Box,
    field: widgets::Field,
    send: gtk::Button,
    new_button: gtk::Button,
}

#[allow(non_camel_case_types)]
type adw_wrap = amethystora_ui::adw::WrapBox;

impl Parts {
    pub fn new(me: &std::rc::Weak<Phone>) -> Parts {
        let root = ui::hbox(0, &["messages"]);
        root.set_vexpand(true);
        root.set_visible(false);

        // --- The empty page ---
        let empty = ui::vbox(0, &["page"]);
        empty.set_hexpand(true);
        empty.set_visible(false);

        // --- The conversations, on one side ---
        let side = ui::vbox(0, &["conversations-side"]);
        let side_head = ui::hbox(8, &["side-head"]);
        side_head.append(&widgets::heading(&t!("Messages"), "h2"));
        side_head.first_child().expect("the heading").set_hexpand(true);
        let new_button = {
            let weak = me.clone();
            widgets::icon_button("plus", 18, &t!("New conversation"), move || {
                if let Some(this) = weak.upgrade() {
                    this.texts_new();
                }
            })
        };
        side_head.append(&new_button);
        side.append(&side_head);
        let chips = ui::wrap(6, 6, &["phone-chips"]);
        side.append(&chips);
        let conversations = ui::vbox(0, &["conversation-list"]);
        let conversations_scroller = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .overlay_scrolling(false)
            .css_classes(["page-scroll"])
            .vexpand(true)
            .child(&conversations)
            .build();
        side.append(&conversations_scroller);

        // --- The chat, on the other ---
        let pane = ui::vbox(0, &["chat-pane"]);
        pane.set_hexpand(true);
        let head = ui::hbox(12, &["chat-head"]);
        let avatar_slot = ui::hbox(0, &[]);
        head.append(&avatar_slot);
        let words = ui::vbox(0, &["grow"]);
        words.set_hexpand(true);
        words.set_valign(gtk::Align::Center);
        let title = ui::line("", &["chat-title"]);
        title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let subtitle = ui::line("", &["faint", "small"]);
        subtitle.set_ellipsize(gtk::pango::EllipsizeMode::End);
        words.append(&title);
        words.append(&subtitle);
        head.append(&words);
        pane.append(&head);

        let disconnected = ui::hbox(10, &["notice-bar"]);
        disconnected.append(&icon("alert", 16));
        let note = ui::label("", &["grow"]);
        note.set_hexpand(true);
        disconnected.append(&note);
        disconnected.set_visible(false);
        pane.append(&disconnected);

        let chat = ui::vbox(0, &["chat"]);
        let chat_scroller = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .overlay_scrolling(false)
            .css_classes(["page-scroll"])
            .vexpand(true)
            .child(&chat)
            .build();
        pane.append(&chat_scroller);

        // Choosing whom to write to
        let new_box = ui::vbox(12, &["new-box"]);
        new_box.set_vexpand(true);
        new_box.set_visible(false);
        new_box.append(&ui::label(&t!("Type a phone number, or the name of someone you have written to."), &["soft"]));
        let new_entry = gtk::Entry::builder().placeholder_text(t!("Name or number")).hexpand(true).css_classes(["field-entry"]).build();
        new_entry.update_property(&[gtk::accessible::Property::Label(&t!("Whom to write to"))]);
        new_box.append(&new_entry);
        let new_choices = ui::vbox(0, &["new-choices"]);
        new_box.append(&new_choices);
        pane.append(&new_box);

        // The box to write in
        let compose = ui::hbox(10, &["compose"]);
        let send = {
            let weak = me.clone();
            widgets::icon_button("send", 20, &t!("Send"), move || {
                if let Some(this) = weak.upgrade() {
                    this.texts_send();
                }
            })
        };
        send.add_css_class("send");
        let field = {
            let (changed, entered) = (me.clone(), me.clone());
            widgets::field(
                &t!("Write a message"),
                "",
                move |_| {
                    if let Some(this) = changed.upgrade() {
                        this.texts_compose_changed();
                    }
                },
                move || {
                    if let Some(this) = entered.upgrade() {
                        this.texts_send();
                    }
                },
            )
        };
        field.root.set_hexpand(true);
        compose.append(&field.root);
        compose.append(&send);
        pane.append(&compose);

        let body = ui::hbox(0, &["messages-body"]);
        body.set_vexpand(true);
        body.append(&side);
        body.append(&pane);
        root.append(&empty);
        root.append(&body);

        // Keep the chat at its end while it fills, keep what was in view when older messages come above it, and
        // ask for older ones on reaching the top
        let vadj = chat_scroller.vadjustment();
        {
            let weak = me.clone();
            vadj.connect_upper_notify(move |adjustment| {
                let Some(this) = weak.upgrade() else { return };
                if this.texts.stick.get() {
                    adjustment.set_value(adjustment.upper() - adjustment.page_size());
                } else if let Some((upper, value)) = this.texts.restore.take() {
                    adjustment.set_value(value + (adjustment.upper() - upper));
                }
            });
            let weak = me.clone();
            vadj.connect_value_changed(move |adjustment| {
                let Some(this) = weak.upgrade() else { return };
                let scrollable = adjustment.upper() > adjustment.page_size() + 40.0;
                if adjustment.value() <= 2.0 && scrollable && !this.texts.stick.get() {
                    this.texts_older();
                }
            });
        }
        {
            let weak = me.clone();
            new_entry.connect_changed(move |_| {
                if let Some(this) = weak.upgrade() {
                    this.texts_choices();
                }
            });
            let weak = me.clone();
            new_entry.connect_activate(move |entry| {
                if let Some(this) = weak.upgrade() {
                    this.texts_pick_typed(&entry.text());
                }
            });
        }

        Parts { root, empty, body, chips, conversations, avatar_slot, title, subtitle, disconnected, note, chat_scroller, chat, new_box, new_entry, new_choices, compose, field, send, new_button }
    }
}

/// What a person typed in the compose box
fn composed(field: &widgets::Field) -> String {
    let buffer = field.view.buffer();
    buffer.text(&buffer.start_iter(), &buffer.end_iter(), false).to_string()
}

impl Phone {
    // --- Which phone, and what it has ------------------------------------------------------------------

    /// The phone being read: the one remembered if it is paired, else the first that shares its texts
    fn texts_device(&self) -> Option<Device> {
        let all = self.link.devices();
        if let Some(id) = self.texts.device() {
            if let Some(device) = all.iter().find(|d| d.id == id && d.paired) {
                return Some(device.clone());
            }
        }
        model::texting(&all).into_iter().next()
    }

    /// Phones to choose from: those that share texts now, and the one being read
    fn texts_candidates(&self) -> Vec<Device> {
        let mut list = model::texting(&self.link.devices());
        if let Some(current) = self.texts_device() {
            if !list.iter().any(|d| d.id == current.id) {
                list.push(current);
            }
        }
        list
    }

    fn texts_ready(device: &Device) -> bool {
        device.paired && device.connected && device.has("sms")
    }

    // --- Coming to the page, and going ----------------------------------------------------------------

    /// The page is shown: choose the phone, and ask it for its conversations unless it was asked a moment ago
    pub(crate) fn texts_enter(self: &Rc<Self>) {
        let Some(device) = self.texts_device() else {
            self.render_texts();
            return;
        };
        if self.texts.device().as_deref() != Some(device.id.as_str()) {
            self.texts_select(&device.id);
            return;
        }
        self.start_texts_timer();
        if Self::texts_ready(&device) && (self.texts.conversations.borrow().is_empty() || i18n::now() - self.texts.asked_list.get() > STALE) {
            self.load_conversations(&device.id, true);
        }
        self.render_texts();
    }

    /// Reads another phone's texts
    fn texts_select(self: &Rc<Self>, id: &str) {
        self.texts.device.replace(Some(id.to_string()));
        self.texts.conversations.borrow_mut().clear();
        self.texts.messages.borrow_mut().clear();
        self.texts.pending.borrow_mut().clear();
        self.texts.view.replace(View::None);
        self.texts.asked_list.set(0.0);
        self.remember();
        self.start_texts_timer();
        if let Some(device) = self.link.device(id).filter(Self::texts_ready) {
            self.load_conversations(&device.id, true);
        }
        self.render_texts();
    }

    /// The program is gone: what it held is gone with it
    pub(crate) fn texts_reset(&self) {
        self.texts.conversations.borrow_mut().clear();
        self.texts.messages.borrow_mut().clear();
        self.texts.pending.borrow_mut().clear();
        self.texts.view.replace(View::None);
        self.texts.asked_list.set(0.0);
        if let Some(timer) = self.texts.timer.take() {
            timer.remove();
        }
    }

    /// Ctrl+R: both lists asked of the phone again
    pub(crate) fn texts_reload(self: &Rc<Self>) {
        if self.state.borrow().page != Page::Messages {
            return;
        }
        let Some(device) = self.texts_device().filter(Self::texts_ready) else { return };
        self.load_conversations(&device.id, true);
        if let View::Thread(thread) = self.texts.view.borrow().clone() {
            self.open_thread(thread, true);
        }
    }

    /// The phones changed: the one being read may have come or gone
    pub(crate) fn texts_devices_changed(self: &Rc<Self>) {
        if self.state.borrow().page != Page::Messages {
            return;
        }
        let Some(device) = self.texts_device() else {
            self.render_texts();
            return;
        };
        if self.texts.device().as_deref() != Some(device.id.as_str()) {
            self.texts_select(&device.id);
            return;
        }
        // A phone that has just connected is asked for its conversations
        if Self::texts_ready(&device) && self.texts.asked_list.get() == 0.0 {
            self.load_conversations(&device.id, true);
        }
        self.render_texts();
    }

    // --- Loading ---------------------------------------------------------------------------------------

    fn load_conversations(self: &Rc<Self>, id: &str, ask: bool) {
        if ask {
            self.texts.asked_list.set(i18n::now());
        }
        let (this, id) = (self.clone(), id.to_string());
        glib::spawn_future_local(async move {
            if ask {
                let _ = this.link.request_conversations(&id).await;
            }
            match this.link.conversations(&id, MOST_CONVERSATIONS).await {
                Ok(list) if this.texts.device().as_deref() == Some(id.as_str()) => {
                    this.texts.conversations.replace(list);
                    this.texts_follow_draft(&id);
                }
                _ => {}
            }
            this.render_texts();
        });
    }

    pub(crate) fn texts_conversations_changed(self: &Rc<Self>, device: &str) {
        if self.state.borrow().page == Page::Messages && self.texts.device().as_deref() == Some(device) {
            self.load_conversations(device, false);
        }
    }

    pub(crate) fn texts_messages_changed(self: &Rc<Self>, device: &str, thread: i64) {
        if self.state.borrow().page != Page::Messages || self.texts.device().as_deref() != Some(device) {
            return;
        }
        if *self.texts.view.borrow() == View::Thread(thread) {
            self.fetch_messages(thread);
        }
    }

    /// A conversation begun here has its thread now: the chat goes on in it
    fn texts_follow_draft(self: &Rc<Self>, _id: &str) {
        let View::Draft(address) = self.texts.view.borrow().clone() else { return };
        let thread = model::find_thread(&self.texts.conversations.borrow(), &address);
        if let Some(thread) = thread {
            self.open_thread_keeping_pending(thread);
        }
    }

    /// Opens a conversation: asked of the phone, and what is there shown
    fn open_thread(self: &Rc<Self>, thread: i64, ask: bool) {
        self.texts.view.replace(View::Thread(thread));
        self.texts.messages.borrow_mut().clear();
        self.texts.pending.borrow_mut().clear();
        self.texts.older.set(Older::Idle);
        self.start_chat(thread, ask);
    }

    fn open_thread_keeping_pending(self: &Rc<Self>, thread: i64) {
        self.texts.view.replace(View::Thread(thread));
        self.texts.messages.borrow_mut().clear();
        self.texts.older.set(Older::Idle);
        self.start_chat(thread, true);
    }

    fn start_chat(self: &Rc<Self>, thread: i64, ask: bool) {
        self.texts.asked_chat.set(i18n::now());
        self.stick_to_end();
        self.render_texts();
        if let Some(device) = self.texts_device().filter(Self::texts_ready) {
            let (this, id) = (self.clone(), device.id);
            glib::spawn_future_local(async move {
                if ask {
                    let _ = this.link.request_messages(&id, thread, 0, PAGE).await;
                }
                this.fetch_messages(thread);
            });
        }
    }

    /// The messages the program holds for a conversation, shown
    fn fetch_messages(self: &Rc<Self>, thread: i64) {
        let Some(device) = self.texts_device() else { return };
        let near_end = {
            let adjustment = self.parts.messages.chat_scroller.vadjustment();
            adjustment.upper() - (adjustment.value() + adjustment.page_size()) < 80.0
        };
        let (this, id) = (self.clone(), device.id);
        glib::spawn_future_local(async move {
            let Ok(list) = this.link.messages(&id, thread, MOST_MESSAGES).await else { return };
            if *this.texts.view.borrow() != View::Thread(thread) || this.texts.device().as_deref() != Some(id.as_str()) {
                return;
            }
            let before = this.texts.messages.borrow().len();
            // Older messages arrived above the ones in view: they stay where they were
            if let Older::Loading(_, count) = this.texts.older.get() {
                if list.len() > count {
                    this.texts.older.set(Older::Idle);
                } else if list.len() == count && before == count {
                    // Nothing came with this change; the phone's answer may still be on its way
                    this.texts.older.set(this.texts.older.get());
                }
            }
            if before > 0 && list.len() > before && !near_end {
                let adjustment = this.parts.messages.chat_scroller.vadjustment();
                this.texts.restore.set(Some((adjustment.upper(), adjustment.value())));
            } else if near_end {
                this.stick_to_end();
            }
            let pending = std::mem::take(&mut *this.texts.pending.borrow_mut());
            this.texts.pending.replace(model::still_pending(pending, &list));
            this.texts.messages.replace(list);
            this.render_texts();
        });
    }

    fn stick_to_end(&self) {
        self.texts.stick.set(true);
        let weak = self.weak();
        glib::timeout_add_local_once(Duration::from_millis(700), move || {
            if let Some(this) = weak.upgrade() {
                this.texts.stick.set(false);
            }
        });
    }

    /// Older messages of the open conversation, asked of the phone
    pub(crate) fn texts_older(self: &Rc<Self>) {
        let View::Thread(thread) = self.texts.view.borrow().clone() else { return };
        if self.texts.older.get() != Older::Idle {
            return;
        }
        let Some(oldest) = self.texts.messages.borrow().first().map(|m| m.date) else { return };
        let Some(device) = self.texts_device().filter(Self::texts_ready) else { return };
        let count = self.texts.messages.borrow().len();
        self.texts.older.set(Older::Loading(i18n::now(), count));
        let adjustment = self.parts.messages.chat_scroller.vadjustment();
        self.texts.restore.set(Some((adjustment.upper(), adjustment.value())));
        self.render_texts();
        let (this, id) = (self.clone(), device.id);
        glib::spawn_future_local(async move {
            let _ = this.link.request_messages(&id, thread, oldest, PAGE).await;
            this.fetch_messages(thread);
        });
    }

    // --- A timer while the page shows ------------------------------------------------------------------

    /// Every few seconds while the page shows: the times in the list, a message that is not confirmed, and a
    /// phone that has not answered
    fn start_texts_timer(&self) {
        if self.texts.timer.borrow().is_some() {
            return;
        }
        let weak = self.weak();
        let id = glib::timeout_add_seconds_local(5, move || {
            let Some(this) = weak.upgrade() else { return glib::ControlFlow::Break };
            if this.state.borrow().page != Page::Messages || !this.link.present() {
                this.texts.timer.take();
                return glib::ControlFlow::Break;
            }
            let now = i18n::now();
            if let Older::Loading(since, _) = this.texts.older.get() {
                if now - since > PATIENCE {
                    // The phone had nothing older to send
                    this.texts.older.set(Older::Done);
                }
            }
            this.render_texts();
            glib::ControlFlow::Continue
        });
        self.texts.timer.replace(Some(id));
    }

    // --- Drawing ---------------------------------------------------------------------------------------

    pub(crate) fn render_texts(&self) {
        let parts = &self.parts.messages;
        let device = self.texts_device();
        let ready = device.as_ref().is_some_and(Self::texts_ready);
        // Only a phone that shares its texts, or one that is paired and away, has a page of them
        let shares = device.as_ref().is_some_and(|d| d.has("sms") || !d.connected);
        parts.empty.set_visible(!shares);
        parts.body.set_visible(shares);
        if !shares {
            self.render_texts_empty(device.as_ref());
            return;
        }
        let device = device.expect("a phone");
        self.render_chips(&device);
        self.render_conversations(&device);
        self.render_pane(&device, ready);
    }

    fn render_texts_empty(&self, device: Option<&Device>) {
        let empty = &self.parts.messages.empty;
        ui::clear(empty);
        let gem = amethystora_ui::gem::Gem::plain(46.0);
        gem.add_css_class("gem");
        let (heading, text) = match device {
            Some(device) => (
                t!("{phone} does not share its texts", phone = bdi(&device.title())),
                t!("In KDE Connect on the phone, allow it to read and send texts, then open this page again."),
            ),
            None => (
                t!("No phone to read texts from"),
                t!("Pair a phone that has the KDE Connect app, and allow it to read and send texts in the app on the phone."),
            ),
        };
        let phones = self.button(&t!("Go to the phones"), Look { icon: Some("phone"), primary: true, ..Default::default() }, |this| this.show(Page::Phones));
        let view = ui::vbox(28, &[]);
        view.append(&widgets::empty(vec![
            gem.upcast(),
            widgets::centered(widgets::heading(&heading, "h2")).upcast(),
            widgets::centered(ui::label(&text, &[])).upcast(),
            widgets::actions(vec![phones.upcast()], &["actions"]).upcast(),
        ]));
        empty.append(&view);
    }

    /// The phones to choose between, when there are several
    fn render_chips(&self, current: &Device) {
        let parts = &self.parts.messages;
        ui::clear_wrap(&parts.chips);
        let candidates = self.texts_candidates();
        parts.chips.set_visible(candidates.len() > 1);
        for device in candidates.iter().filter(|_| candidates.len() > 1) {
            let content = ui::hbox(6, &[]);
            content.append(&crate::icons::device(&device.kind, 15));
            content.append(&ui::line(&device.title(), &[]));
            let button = gtk::Button::builder().child(&content).css_classes(["plain", "chip"]).build();
            if device.id == current.id {
                button.add_css_class("current");
            }
            let (id, weak) = (device.id.clone(), self.weak());
            button.connect_clicked(move |_| {
                if let Some(this) = weak.upgrade() {
                    this.texts_select(&id);
                }
            });
            parts.chips.append(&button);
        }
    }

    fn render_conversations(&self, device: &Device) {
        let parts = &self.parts.messages;
        ui::clear(&parts.conversations);
        let list = self.texts.conversations.borrow().clone();
        let ready = Self::texts_ready(device);
        parts.new_button.set_sensitive(ready);
        if list.is_empty() {
            let waiting = ready && i18n::now() - self.texts.asked_list.get() < PATIENCE;
            let box_ = ui::vbox(10, &["list-empty"]);
            if waiting {
                let working = widgets::role_box(gtk::Orientation::Horizontal, 10, &["working"], gtk::AccessibleRole::Status);
                let mark = icon("spinner", 18);
                mark.set_spinning(true);
                working.append(&mark);
                working.append(&ui::label(&t!("Asking the phone for its conversations…"), &[]));
                box_.append(&working);
            } else if ready {
                box_.append(&ui::label(&t!("The phone has no conversations to show."), &["soft"]));
                box_.append(&ui::label(&t!("If it has some, check that KDE Connect may read texts on the phone."), &["faint", "small"]));
            } else {
                box_.append(&ui::label(&t!("Connect the phone to read its texts."), &["soft"]));
            }
            parts.conversations.append(&box_);
            return;
        }
        let selected = match &*self.texts.view.borrow() {
            View::Thread(thread) => Some(*thread),
            _ => None,
        };
        let now = i18n::now();
        for conversation in &list {
            parts.conversations.append(&self.conversation_row(conversation, selected == Some(conversation.thread), now));
        }
    }

    fn conversation_row(&self, c: &Conversation, selected: bool, now: f64) -> gtk::Button {
        let row = ui::hbox(12, &["conversation"]);
        row.append(&widgets::avatar(&c.title(), c.group, false));
        let words = ui::vbox(1, &["grow"]);
        words.set_hexpand(true);
        let top = ui::hbox(8, &[]);
        let name = ui::line(&display_name(c), &["conversation-name"]);
        name.set_hexpand(true);
        name.set_ellipsize(gtk::pango::EllipsizeMode::End);
        top.append(&name);
        top.append(&ui::line(&model::stamp(c.date, now), &["faint", "small", "stamp"]));
        words.append(&top);
        let snippet = ui::line(&c.first_line(), &["conversation-snippet"]);
        snippet.set_ellipsize(gtk::pango::EllipsizeMode::End);
        if c.unread {
            snippet.add_css_class("unread");
            name.add_css_class("unread");
        }
        words.append(&snippet);
        row.append(&words);
        if c.unread {
            let dot = ui::hbox(0, &["unread-dot"]);
            dot.set_valign(gtk::Align::Center);
            row.append(&dot);
        }
        let button = gtk::Button::builder().child(&row).css_classes(["plain", "conversation-button"]).build();
        if selected {
            button.add_css_class("current");
        }
        if c.group {
            button.set_tooltip_text(Some(&c.addresses.join("\n")));
        }
        button.update_property(&[gtk::accessible::Property::Label(&t!("{name}: {snippet}", name = display_name(c), snippet = c.first_line()))]);
        let (thread, weak) = (c.thread, self.weak());
        button.connect_clicked(move |_| {
            if let Some(this) = weak.upgrade() {
                this.open_thread(thread, true);
                this.parts.messages.field.view.grab_focus();
            }
        });
        button
    }

    fn render_pane(&self, device: &Device, ready: bool) {
        let parts = &self.parts.messages;
        let view = self.texts.view.borrow().clone();
        let conversation = match &view {
            View::Thread(thread) => self.texts.conversations.borrow().iter().find(|c| c.thread == *thread).cloned(),
            _ => None,
        };
        let choosing = view == View::New;
        let chatting = matches!(view, View::Thread(_) | View::Draft(_));
        let group = conversation.as_ref().is_some_and(|c| c.group);
        // The bar over the chat: the phone is away, or the conversation is one this window only reads
        let bar = if !ready {
            Some(t!("{phone} is not connected. What is below is what was last held; writing is off until it connects.", phone = bdi(&device.title())))
        } else if group {
            Some(t!("This is a group conversation. Reply to it on the phone."))
        } else {
            None
        };
        parts.disconnected.set_visible(bar.is_some());
        if let Some(bar) = &bar {
            parts.note.set_label(bar);
        }
        // The head
        ui::clear(&parts.avatar_slot);
        let (title, subtitle) = match (&view, &conversation) {
            (View::New, _) => (t!("New conversation"), String::new()),
            (View::Draft(address), _) => (bdi(address), String::new()),
            (View::Thread(_), Some(c)) => (display_name(c), subtitle_of(c)),
            (View::Thread(_), None) => (t!("Conversation"), String::new()),
            (View::None, _) => (bdi(&device.title()), t!("Pick a conversation, or begin a new one.")),
        };
        match (&view, &conversation) {
            (View::Thread(_), Some(c)) => parts.avatar_slot.append(&widgets::avatar(&c.title(), c.group, true)),
            (View::Draft(address), _) => parts.avatar_slot.append(&widgets::avatar(address, false, true)),
            _ => parts.avatar_slot.append(&crate::icons::device(&device.kind, 24)),
        }
        parts.title.set_label(&title);
        parts.subtitle.set_label(&subtitle);
        parts.subtitle.set_visible(!subtitle.is_empty());

        parts.new_box.set_visible(choosing);
        parts.chat_scroller.set_visible(!choosing);
        parts.compose.set_visible(chatting && !group);
        parts.field.view.set_sensitive(ready && chatting && !group);
        if choosing {
            self.texts_choices();
        }
        self.texts_compose_changed();
        ui::clear(&parts.chat);
        if chatting {
            parts.chat.append(&self.build_chat(&view, ready));
        } else if !choosing {
            parts.chat.append(&self.chat_placeholder());
        }
    }

    fn chat_placeholder(&self) -> gtk::Widget {
        let gem = amethystora_ui::gem::Gem::plain(40.0);
        gem.add_css_class("gem");
        let view = ui::vbox(0, &["chat-placeholder"]);
        view.set_vexpand(true);
        view.set_valign(gtk::Align::Center);
        let inner = widgets::empty(vec![gem.upcast(), widgets::centered(ui::label(&t!("Pick a conversation to read it, or begin a new one with +."), &["soft"])).upcast()]);
        view.append(&inner);
        view.upcast()
    }

    /// The chat: messages with a time over each stretch, and what was just sent and is not shown by the phone yet
    fn build_chat(&self, view: &View, ready: bool) -> gtk::Box {
        let chat = ui::vbox(0, &["chat-inner"]);
        let messages = self.texts.messages.borrow().clone();
        let pending = self.texts.pending.borrow().clone();
        let group = match view {
            View::Thread(thread) => self.texts.conversations.borrow().iter().any(|c| c.thread == *thread && c.group),
            _ => false,
        };
        let now = i18n::now();
        // Older messages, above
        if let View::Thread(_) = view {
            if !messages.is_empty() {
                let more = ui::hbox(0, &["older"]);
                more.set_halign(gtk::Align::Center);
                match self.texts.older.get() {
                    Older::Loading(..) => {
                        let working = widgets::role_box(gtk::Orientation::Horizontal, 8, &["working"], gtk::AccessibleRole::Status);
                        let mark = icon("spinner", 15);
                        mark.set_spinning(true);
                        working.append(&mark);
                        working.append(&ui::line(&t!("Asking the phone for older messages…"), &["faint", "small"]));
                        more.append(&working);
                    }
                    Older::Done => more.append(&ui::line(&t!("This is the start of the conversation."), &["faint", "small"])),
                    Older::Idle => {
                        let button = widgets::link_button(&t!("Load older messages"), Some("history"), self.go(|this| this.texts_older()));
                        button.set_sensitive(ready);
                        more.append(&button);
                    }
                }
                chat.append(&more);
            }
        }
        if messages.is_empty() && pending.is_empty() {
            if let View::Thread(_) = view {
                let waiting = ready && now - self.texts.asked_chat.get() < PATIENCE;
                let line = if waiting {
                    let working = widgets::role_box(gtk::Orientation::Horizontal, 10, &["working"], gtk::AccessibleRole::Status);
                    let mark = icon("spinner", 18);
                    mark.set_spinning(true);
                    working.append(&mark);
                    working.append(&ui::label(&t!("Asking the phone for this conversation…"), &[]));
                    working.upcast::<gtk::Widget>()
                } else if ready {
                    ui::label(&t!("The phone has not sent this conversation. Try again from the list."), &["soft"]).upcast()
                } else {
                    ui::label(&t!("Connect the phone to read this conversation."), &["soft"]).upcast()
                };
                let wrap = ui::vbox(0, &["working-wrap"]);
                wrap.append(&line);
                chat.append(&wrap);
            } else {
                chat.append(&ui::label(&t!("Write the first message below. The phone sends it."), &["soft", "working-wrap"]));
            }
            return chat;
        }
        for row in model::rows(&messages) {
            match row {
                Row::Time(date) => {
                    let head = ui::line(&model::moment(date, now), &["time-head", "faint", "small"]);
                    head.set_halign(gtk::Align::Center);
                    chat.append(&head);
                }
                Row::Bubble { at, first, last } => chat.append(&self.bubble(&messages[at], first, last, group)),
            }
        }
        for waiting in &pending {
            chat.append(&self.pending_bubble(waiting, now));
        }
        chat
    }

    fn bubble(&self, m: &Message, first: bool, last: bool, group: bool) -> gtk::Box {
        let row = ui::hbox(8, &["msg-row"]);
        if m.outgoing {
            row.add_css_class("out");
        } else {
            row.add_css_class("in");
        }
        if first {
            row.add_css_class("first");
        }
        if last {
            row.add_css_class("last");
        }
        // Incoming: the avatar once for a run, at its end; outgoing: pushed to the end of the line
        let column = ui::vbox(2, &["msg-col"]);
        if m.outgoing {
            let spacer = ui::hbox(0, &[]);
            spacer.set_hexpand(true);
            row.append(&spacer);
        } else {
            let slot = ui::hbox(0, &["avatar-slot"]);
            if last {
                slot.append(&widgets::avatar(m.sender(), false, false));
            }
            slot.set_valign(gtk::Align::End);
            row.append(&slot);
            if group && first {
                column.append(&ui::line(m.sender(), &["faint", "small", "sender"]));
            }
        }
        let bubble = ui::vbox(0, &["bubble"]);
        let body = if m.body.trim().is_empty() { None } else { Some(m.body.as_str()) };
        match body {
            Some(text) => {
                let label = self.linked_label(text);
                bubble.append(&label);
            }
            None => bubble.append(&ui::line(&t!("Attachment"), &["faint", "attachment"])),
        }
        bubble.set_tooltip_text(Some(&i18n::date(m.date as f64 / 1000.0, DateStyle::MediumShort)));
        column.append(&bubble);
        let limited = ui::limit(&column, 460);
        limited.set_halign(if m.outgoing { gtk::Align::End } else { gtk::Align::Start });
        row.append(&limited);
        row
    }

    fn pending_bubble(&self, p: &Pending, now: f64) -> gtk::Box {
        let row = ui::hbox(8, &["msg-row", "out", "first", "last", "pending"]);
        let spacer = ui::hbox(0, &[]);
        spacer.set_hexpand(true);
        row.append(&spacer);
        let column = ui::vbox(2, &["msg-col"]);
        column.set_halign(gtk::Align::End);
        let bubble = ui::vbox(0, &["bubble"]);
        bubble.append(&self.linked_label(&p.body));
        column.append(&bubble);
        let late = p.overdue(now);
        let status = ui::line(&if late { t!("Not confirmed by the phone") } else { t!("Sending…") }, &["faint", "small", "pending-note"]);
        if late {
            status.add_css_class("bad");
        }
        status.set_halign(gtk::Align::End);
        column.append(&status);
        let limited = ui::limit(&column, 460);
        limited.set_halign(gtk::Align::End);
        row.append(&limited);
        row
    }

    // --- Writing ---------------------------------------------------------------------------------------

    /// The send button is on when there is something to send and somewhere to send it
    pub(crate) fn texts_compose_changed(&self) {
        let parts = &self.parts.messages;
        let ready = self.texts_device().as_ref().is_some_and(Self::texts_ready);
        let view = self.texts.view.borrow().clone();
        let group = match &view {
            View::Thread(thread) => self.texts.conversations.borrow().iter().any(|c| c.thread == *thread && c.group),
            _ => false,
        };
        let text = composed(&parts.field);
        let can = ready && !group && matches!(view, View::Thread(_) | View::Draft(_)) && !text.trim().is_empty();
        parts.send.set_sensitive(can);
    }

    /// Sends what is in the box to the open conversation, or the one being begun
    pub(crate) fn texts_send(self: &Rc<Self>) {
        let parts = &self.parts.messages;
        let body = composed(&parts.field);
        if body.trim().is_empty() || !parts.send.is_sensitive() {
            return;
        }
        let Some(device) = self.texts_device().filter(Self::texts_ready) else { return };
        let (addresses, thread) = match self.texts.view.borrow().clone() {
            View::Thread(thread) => match self.texts.conversations.borrow().iter().find(|c| c.thread == thread) {
                Some(c) if !c.group && !c.addresses.is_empty() => (c.addresses.clone(), thread),
                _ => return,
            },
            View::Draft(address) => (vec![address], 0),
            _ => return,
        };
        if !addresses.iter().all(|a| model::valid_address(a)) {
            return;
        }
        let waiting = Pending::new(&body, i18n::now(), &self.texts.messages.borrow(), &self.texts.pending.borrow());
        self.texts.pending.borrow_mut().push(waiting.clone());
        parts.field.view.buffer().set_text("");
        self.stick_to_end();
        self.render_texts();
        let (this, id) = (self.clone(), device.id);
        glib::spawn_future_local(async move {
            if let Err(failure) = this.link.send_message(&id, &addresses, &body, thread).await {
                // It did not go: it is not waiting, and what was typed is put back to be sent again
                this.texts.pending.borrow_mut().retain(|p| *p != waiting);
                let buffer = this.parts.messages.field.view.buffer();
                if composed(&this.parts.messages.field).is_empty() {
                    buffer.set_text(&body);
                }
                this.say(true, failure_text(&failure));
                this.render_texts();
            }
        });
    }

    // --- A new conversation ----------------------------------------------------------------------------

    pub(crate) fn texts_new(self: &Rc<Self>) {
        self.texts.view.replace(View::New);
        self.texts.messages.borrow_mut().clear();
        self.texts.pending.borrow_mut().clear();
        self.parts.messages.new_entry.set_text("");
        self.render_texts();
        self.parts.messages.new_entry.grab_focus();
    }

    /// What the typed words can be: conversations the phone has, by name or number, and the typed number itself
    pub(crate) fn texts_choices(&self) {
        let parts = &self.parts.messages;
        ui::clear(&parts.new_choices);
        if *self.texts.view.borrow() != View::New {
            return;
        }
        let typed = parts.new_entry.text().trim().to_string();
        let lower = typed.to_lowercase();
        let digits: String = typed.chars().filter(char::is_ascii_digit).collect();
        let list = self.texts.conversations.borrow().clone();
        let mut shown = 0;
        // A number that is not a conversation yet comes first, once it has some digits
        let known = model::find_thread(&list, &typed).is_some();
        if digits.len() >= 2 && model::valid_address(&typed) && !known {
            parts.new_choices.append(&self.choice_row(&t!("Write to {number}", number = bdi(&typed)), &t!("A new conversation"), Choice::Address(typed.clone()), true));
            shown += 1;
        }
        for c in list.iter().filter(|c| !c.group).filter(|c| {
            lower.is_empty()
                || c.title().to_lowercase().contains(&lower)
                || (digits.len() >= 2 && c.addresses.iter().any(|a| a.chars().filter(char::is_ascii_digit).collect::<String>().contains(&digits)))
        }) {
            if shown >= 8 {
                break;
            }
            let number = c.addresses.first().cloned().unwrap_or_default();
            parts.new_choices.append(&self.choice_row(&display_name(c), &bdi(&number), Choice::Thread(c.thread), false));
            shown += 1;
        }
        if shown == 0 {
            parts.new_choices.append(&ui::label(&t!("Nothing matches yet. Type a whole phone number to write to it."), &["faint", "small", "list-empty"]));
        }
    }

    fn choice_row(&self, name: &str, detail: &str, choice: Choice, address: bool) -> gtk::Button {
        let row = ui::hbox(12, &["conversation"]);
        // A number that is no one's yet has no letters to show
        row.append(&widgets::avatar(if address { "" } else { name }, false, false));
        let words = ui::vbox(0, &["grow"]);
        words.set_hexpand(true);
        let label = ui::line(name, &["conversation-name"]);
        label.set_ellipsize(gtk::pango::EllipsizeMode::End);
        words.append(&label);
        let detail = ui::line(detail, &["faint", "small"]);
        detail.set_ellipsize(gtk::pango::EllipsizeMode::End);
        words.append(&detail);
        row.append(&words);
        if address {
            row.append(&icon("send", 16));
        }
        let button = gtk::Button::builder().child(&row).css_classes(["plain", "conversation-button"]).build();
        let weak = self.weak();
        button.connect_clicked(move |_| {
            if let Some(this) = weak.upgrade() {
                this.texts_choose(&choice);
            }
        });
        button
    }

    fn texts_choose(self: &Rc<Self>, choice: &Choice) {
        match choice {
            Choice::Thread(thread) => self.open_thread(*thread, true),
            Choice::Address(address) => {
                self.texts.view.replace(View::Draft(address.clone()));
                self.texts.messages.borrow_mut().clear();
                self.texts.pending.borrow_mut().clear();
                self.render_texts();
            }
        }
        self.parts.messages.field.view.grab_focus();
    }

    /// Enter in the box of a new conversation: the first choice
    pub(crate) fn texts_pick_typed(self: &Rc<Self>, typed: &str) {
        let typed = typed.trim().to_string();
        let list = self.texts.conversations.borrow().clone();
        if let Some(thread) = model::find_thread(&list, &typed) {
            self.texts_choose(&Choice::Thread(thread));
        } else if model::valid_address(&typed) && typed.chars().filter(char::is_ascii_digit).count() >= 2 {
            self.texts_choose(&Choice::Address(typed));
        } else if let Some(c) = list.iter().find(|c| !c.group && !typed.is_empty() && c.title().to_lowercase().contains(&typed.to_lowercase())) {
            self.texts_choose(&Choice::Thread(c.thread));
        }
    }
}

/// What a row of the new conversation's choices does
#[derive(Debug, Clone)]
enum Choice {
    Thread(i64),
    Address(String),
}

/// The name of a conversation for a row or a head: the contact's, the numbers, or for a group its first member
/// and how many others
fn display_name(c: &Conversation) -> String {
    if c.group && c.addresses.len() > 1 {
        let first = if c.name.trim().is_empty() { c.addresses[0].clone() } else { c.name.clone() };
        return t!("{first} and {count, plural, one {# other} other {# others}}", first = bdi(&first), count = c.addresses.len() - 1);
    }
    bdi(&c.title())
}

/// Under the name in the chat's head: the number, when the name is not the number
fn subtitle_of(c: &Conversation) -> String {
    if c.group {
        return t!("{count, plural, one {# person} other {# people}}", count = c.addresses.len());
    }
    let number = c.addresses.first().cloned().unwrap_or_default();
    if number.is_empty() || number == c.title() { String::new() } else { bdi(&number) }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conversation(name: &str, addresses: &[&str], group: bool) -> Conversation {
        Conversation { thread: 1, addresses: addresses.iter().map(|a| a.to_string()).collect(), name: name.into(), snippet: String::new(), date: 0, unread: false, group }
    }

    #[test]
    fn names_and_numbers_head_a_chat() {
        let one = conversation("Grace Hopper", &["+1 555 0100"], false);
        assert_eq!(display_name(&one), "Grace Hopper");
        assert_eq!(subtitle_of(&one), "+1 555 0100");
        let bare = conversation("", &["+1 555 0100"], false);
        assert_eq!(display_name(&bare), "+1 555 0100");
        assert_eq!(subtitle_of(&bare), "");
    }

    #[test]
    fn a_group_is_its_first_member_and_the_others() {
        let group = conversation("", &["111", "222", "333"], true);
        assert_eq!(display_name(&group), "111 and 2 others");
        assert_eq!(subtitle_of(&group), "3 people");
        let pair = conversation("Ann", &["111", "222"], true);
        assert_eq!(display_name(&pair), "Ann and 1 other");
    }
}
