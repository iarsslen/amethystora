//! Amethystora Shelf (round 4, R4-08; plans/beyond/spec-r4-shelf.md): a place at the edge of the screen to put
//! things down while moving between apps that are never on screen together, then drag them out where they belong.
//!
//! The shell's `shelf` module shows where to drop, hands the first drop over on the standard input (`amethystora-shelf
//! take column|row`, the drop as model.rs reads it) and keeps the window above every other, on every workspace, at its
//! place. Later drops land on the window itself. A file is held by reference and offered as a copy when it is dragged
//! out, so that nothing is ever moved or deleted where it was; text and pictures are held only in this program's
//! memory, never written, and are gone when the shelf is cleared, the last item leaves or the session ends. An empty
//! shelf closes and the program ends.

mod model;

use std::cell::{Cell, RefCell};
use std::rc::{Rc, Weak};
use std::time::Duration;

use amethystora_ui::adw::prelude::*;
use amethystora_ui::app::{self, App, Shell, Spec};
use amethystora_ui::{adw, gdk, gio, glib, gtk, pango, t};

use model::Incoming;

/// An empty shelf opened by hand closes after this long without a drop
const EMPTY_FOR: Duration = Duration::from_secs(10);
/// How long "The shelf is full" is shown
const NOTE_FOR: Duration = Duration::from_secs(3);
const THUMB: i32 = 44;
const ICON: i32 = 32;
const ITEM_WIDTH: i32 = 62;
/// What a drop on the window may be, in that order of preference (Files offers text/uri-list for its files)
const DROP_TYPES: [&str; 4] = ["text/uri-list", "image/png", "text/plain;charset=utf-8", "text/plain"];

pub fn main() -> glib::ExitCode {
    app::run(
        Spec {
            name: "shelf",
            id: "org.amethystora.Shelf",
            css: include_str!("shelf.css"),
            width: 84,
            height: 60,
            min_width: 0,
            min_height: 0,
        },
        Shelf::new,
    )
}

/// What one item holds
enum Kind {
    /// A file of this computer, by reference, and the monitor that greys it when it goes
    File { file: gio::File, _monitor: Option<gio::FileMonitor> },
    Text(String),
    Picture(gdk::Texture),
}

struct Item {
    kind: Kind,
    /// What it is called, and what a screen reader says of it
    name: String,
    button: gtk::Button,
    missing: Cell<bool>,
    /// Ctrl was held as its drag started: the item stays on the shelf
    keep: Cell<bool>,
    /// Its drag was let go nowhere, or with Escape
    cancelled: Cell<bool>,
}

pub struct Shelf {
    me: Weak<Shelf>,
    shell: Rc<Shell>,
    items: RefCell<Vec<Rc<Item>>>,
    body: gtk::Box,
    list: gtk::Box,
    note: gtk::Label,
    clear: gtk::Button,
    row: Cell<bool>,
    empty_timer: RefCell<Option<glib::SourceId>>,
    note_timer: RefCell<Option<glib::SourceId>>,
    reading: Cell<u32>,
}

impl Shelf {
    fn new(shell: Rc<Shell>) -> Rc<Self> {
        // A small window of its own drawing: no title bar and no window buttons (this process's setting only)
        if let Some(settings) = gtk::Settings::default() {
            settings.set_gtk_decoration_layout(Some(":"));
        }
        let window = &shell.window;
        window.set_decorated(false);
        window.set_resizable(false);
        window.set_size_request(-1, -1);
        window.set_title(Some(&t!("Shelf")));
        window.add_css_class("shelf-window");

        let body = gtk::Box::new(gtk::Orientation::Vertical, 10);
        body.add_css_class("shelf");
        let list = gtk::Box::new(gtk::Orientation::Vertical, 10);
        list.add_css_class("items");
        list.set_halign(gtk::Align::Center);
        let note = gtk::Label::new(None);
        note.add_css_class("note");
        note.set_wrap(true);
        note.set_justify(gtk::Justification::Center);
        note.set_max_width_chars(8);
        note.set_visible(false);
        let clear = gtk::Button::with_label(&t!("Clear"));
        clear.add_css_class("clear");
        clear.set_halign(gtk::Align::Center);
        body.append(&list);
        body.append(&note);
        body.append(&clear);
        window.set_content(Some(&body));

        let shelf = Rc::new_cyclic(|me| Shelf {
            me: me.clone(),
            shell: shell.clone(),
            items: RefCell::new(Vec::new()),
            body: body.clone(),
            list,
            note,
            clear: clear.clone(),
            row: Cell::new(false),
            empty_timer: RefCell::new(None),
            note_timer: RefCell::new(None),
            reading: Cell::new(0),
        });

        let weak = shelf.me.clone();
        clear.connect_clicked(move |_| {
            if let Some(this) = weak.upgrade() {
                this.clear_all();
            }
        });

        // Later drops land here: files, a picture, text, in that order of preference; never the shelf's own items. Each
        // is read here, within the same limits as the shell's hand-off, rather than by GTK's own readers, which read
        // whatever an app offers, however much
        let target = gtk::DropTargetAsync::new(Some(gdk::ContentFormats::new(&DROP_TYPES)), gdk::DragAction::COPY);
        target.connect_accept(|_, drop| {
            let formats = drop.formats();
            drop.drag().is_none() && DROP_TYPES.iter().any(|mime| formats.contain_mime_type(mime))
        });
        target.connect_drag_enter(|_, _, _, _| gdk::DragAction::COPY);
        target.connect_drag_motion(|_, _, _, _| gdk::DragAction::COPY);
        let weak = shelf.me.clone();
        target.connect_drop(move |_, drop, _, _| {
            let Some(this) = weak.upgrade() else { return false };
            let drop = drop.clone();
            glib::spawn_future_local(async move {
                let taken = this.read_drop(&drop).await;
                drop.finish(if taken { gdk::DragAction::COPY } else { gdk::DragAction::empty() });
            });
            true
        });
        body.add_controller(target);

        // Delete takes the focused item away, Ctrl+Delete clears the shelf, the Menu key opens an item's menu
        let keys = gtk::EventControllerKey::new();
        let weak = shelf.me.clone();
        keys.connect_key_pressed(move |_, key, _, state| {
            let Some(this) = weak.upgrade() else { return glib::Propagation::Proceed };
            match key {
                gdk::Key::Delete | gdk::Key::KP_Delete if state.contains(gdk::ModifierType::CONTROL_MASK) => {
                    this.clear_all();
                    glib::Propagation::Stop
                }
                gdk::Key::Delete | gdk::Key::KP_Delete => {
                    if let Some(item) = this.focused() {
                        this.remove(&item);
                    }
                    glib::Propagation::Stop
                }
                gdk::Key::Menu => {
                    if let Some(item) = this.focused() {
                        this.menu(&item);
                    }
                    glib::Propagation::Stop
                }
                _ => glib::Propagation::Proceed,
            }
        });
        window.add_controller(keys);
        shelf
    }

    // ---- The drop ----

    /// The shell's hand-off: the drop on the standard input, read whole before anything is added
    fn take(&self, line: &gio::ApplicationCommandLine) {
        let Some(stream) = line.stdin() else {
            self.taken(Err("no standard input".into()));
            return;
        };
        self.reading.set(self.reading.get() + 1);
        let weak = self.me.clone();
        // The launch waits until its command line is let go: kept until the drop is read
        let line = line.clone();
        glib::spawn_future_local(async move {
            let bytes = read_most(&stream, model::MOST_HANDOFF).await;
            drop(line);
            let result = match &bytes {
                Some(bytes) => model::parse_handoff(bytes),
                None => Err("too large".to_string()),
            };
            forget(bytes);
            if let Some(this) = weak.upgrade() {
                this.reading.set(this.reading.get().saturating_sub(1));
                this.taken(result);
            }
        });
    }

    fn taken(&self, result: Result<Vec<Incoming>, String>) {
        match result {
            Ok(incoming) => {
                let wanted = incoming.len();
                let room = model::room(self.items.borrow().len(), wanted);
                for one in incoming.into_iter().take(room) {
                    self.add(one);
                }
                if room < wanted {
                    self.say_full();
                }
            }
            // Never what the drop held: only that it was refused
            Err(why) => eprintln!("amethystora-shelf: a drop was refused: {why}"),
        }
        if self.items.borrow().is_empty() {
            self.refused();
        } else {
            self.shell.window.present();
        }
    }

    /// A drop on the window itself, read within the shelf's limits: a list of files, a PNG picture or text
    async fn read_drop(&self, drop: &gdk::Drop) -> bool {
        let formats = drop.formats();
        let Some(mime) = DROP_TYPES.iter().copied().find(|mime| formats.contain_mime_type(mime)) else { return false };
        let most = if mime == "image/png" { model::MOST_PICTURE } else { model::MOST_TEXT };
        let bytes = match drop.read_future(&[mime], glib::Priority::DEFAULT).await {
            Ok((stream, _)) => read_most(&stream, most).await,
            Err(_) => None,
        };
        let incoming: Vec<Incoming> = match (&bytes, mime) {
            (Some(bytes), "text/uri-list") => {
                model::local_uris(&String::from_utf8_lossy(bytes)).into_iter().map(Incoming::File).collect()
            }
            (Some(bytes), "image/png") => vec![Incoming::Picture(bytes.clone())],
            (Some(bytes), _) => std::str::from_utf8(bytes).ok().filter(|text| !text.trim().is_empty())
                .map(|text| vec![Incoming::Text(text.to_string())]).unwrap_or_default(),
            _ => Vec::new(),
        };
        forget(bytes);
        if incoming.is_empty() {
            self.refused();
            return false;
        }
        let wanted = incoming.len();
        let room = model::room(self.items.borrow().len(), wanted);
        let mut taken = false;
        for one in incoming.into_iter().take(room) {
            taken |= self.add(one);
        }
        if room < wanted {
            self.say_full();
        }
        if !taken && self.items.borrow().is_empty() {
            self.refused();
        }
        taken
    }

    fn add(&self, incoming: Incoming) -> bool {
        match incoming {
            Incoming::File(uri) => self.add_file(&uri),
            Incoming::Text(text) => self.push(Kind::Text(text)),
            // Its size is read before it is decoded: a few bytes can stand for more pixels than memory holds
            Incoming::Picture(bytes) if model::picture_ok(&bytes) => {
                match gdk::Texture::from_bytes(&glib::Bytes::from_owned(bytes)) {
                    Ok(texture) => self.push(Kind::Picture(texture)),
                    Err(_) => false,
                }
            }
            Incoming::Picture(_) => false,
        }
    }

    /// A drop the shelf could not take: it says so for a moment, and an empty shelf then closes
    fn refused(&self) {
        self.say(&t!("The shelf could not take that"), true);
        if !self.items.borrow().is_empty() || self.reading.get() > 0 {
            return;
        }
        self.shell.window.present();
        if let Some(source) = self.empty_timer.borrow_mut().take() {
            source.remove();
        }
        let weak = self.me.clone();
        let source = glib::timeout_add_local_once(NOTE_FOR, move || {
            if let Some(this) = weak.upgrade() {
                this.empty_timer.borrow_mut().take();
                if this.items.borrow().is_empty() && this.reading.get() == 0 {
                    this.quit();
                }
            }
        });
        self.empty_timer.replace(Some(source));
    }

    fn add_file(&self, uri: &str) -> bool {
        let file = gio::File::for_uri(uri);
        if file.path().is_none() || !file.query_exists(gio::Cancellable::NONE) {
            return false;
        }
        // The same file twice is one item
        let held = self.items.borrow().iter().any(|item| matches!(&item.kind, Kind::File { file: f, .. } if f.equal(&file)));
        if held {
            return false;
        }
        let monitor = file.monitor_file(gio::FileMonitorFlags::WATCH_MOVES, gio::Cancellable::NONE).ok();
        let kind = Kind::File { file: file.clone(), _monitor: monitor.clone() };
        if !self.push(kind) {
            return false;
        }
        if let (Some(monitor), Some(item)) = (monitor, self.items.borrow().last().cloned()) {
            let weak_item = Rc::downgrade(&item);
            let weak = self.me.clone();
            monitor.connect_changed(move |_, _, _, event| {
                let (Some(this), Some(item)) = (weak.upgrade(), weak_item.upgrade()) else { return };
                let gone = matches!(event, gio::FileMonitorEvent::Deleted | gio::FileMonitorEvent::MovedOut | gio::FileMonitorEvent::Renamed);
                let back = matches!(event, gio::FileMonitorEvent::Created | gio::FileMonitorEvent::MovedIn);
                if gone || back {
                    let exists = match &item.kind {
                        Kind::File { file, .. } => file.query_exists(gio::Cancellable::NONE),
                        _ => true,
                    };
                    this.set_missing(&item, !exists);
                }
            });
        }
        true
    }

    // ---- Items ----

    fn push(&self, kind: Kind) -> bool {
        if self.items.borrow().len() >= model::MOST_ITEMS {
            self.say_full();
            return false;
        }
        let (thumb, name, tooltip) = self.look(&kind);
        let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
        content.append(&thumb);
        let label = gtk::Label::new(Some(&name));
        label.add_css_class("name");
        label.set_ellipsize(pango::EllipsizeMode::End);
        label.set_single_line_mode(true);
        label.set_max_width_chars(1);
        label.set_size_request(ITEM_WIDTH, -1);
        label.set_xalign(0.5);
        content.append(&label);
        let button = gtk::Button::builder().child(&content).css_classes(["item"]).build();
        button.set_tooltip_text(tooltip.as_deref());
        button.update_property(&[gtk::accessible::Property::Label(&name)]);
        let item = Rc::new(Item { kind, name: name.clone(), button: button.clone(), missing: Cell::new(false), keep: Cell::new(false), cancelled: Cell::new(false) });
        self.drag_out(&item);

        let press = gtk::GestureClick::new();
        press.set_button(gdk::BUTTON_SECONDARY);
        let weak = self.me.clone();
        let weak_item = Rc::downgrade(&item);
        press.connect_pressed(move |_, _, _, _| {
            if let (Some(this), Some(item)) = (weak.upgrade(), weak_item.upgrade()) {
                this.menu(&item);
            }
        });
        button.add_controller(press);

        self.list.append(&button);
        self.items.borrow_mut().push(item);
        self.not_empty();
        true
    }

    /// An item's square, its name and its tooltip
    fn look(&self, kind: &Kind) -> (gtk::Widget, String, Option<String>) {
        let thumb = gtk::Box::new(gtk::Orientation::Vertical, 0);
        thumb.add_css_class("thumb");
        thumb.set_size_request(THUMB, THUMB);
        thumb.set_halign(gtk::Align::Center);
        thumb.set_overflow(gtk::Overflow::Hidden);
        let icon = |name: &str| {
            let image = gtk::Image::from_icon_name(name);
            image.set_pixel_size(ICON);
            image.set_vexpand(true);
            image.set_valign(gtk::Align::Center);
            image.upcast::<gtk::Widget>()
        };
        let picture = |paintable: &gdk::Texture| {
            let picture = gtk::Picture::for_paintable(paintable);
            picture.set_content_fit(gtk::ContentFit::Cover);
            picture.set_size_request(THUMB, THUMB);
            picture.set_can_shrink(true);
            // The square and no larger, whatever size the picture is: a clamp each way
            let tall = adw::Clamp::builder().orientation(gtk::Orientation::Vertical).maximum_size(THUMB)
                .tightening_threshold(THUMB).child(&picture).build();
            adw::Clamp::builder().orientation(gtk::Orientation::Horizontal).maximum_size(THUMB)
                .tightening_threshold(THUMB).child(&tall).build().upcast::<gtk::Widget>()
        };
        let (inside, name, tooltip) = match kind {
            Kind::File { file, .. } => {
                let info = file.query_info(
                    "standard::display-name,standard::icon,thumbnail::path,thumbnail::is-valid",
                    gio::FileQueryInfoFlags::NONE,
                    gio::Cancellable::NONE,
                );
                let name = info.as_ref().map(|info| info.display_name().to_string()).unwrap_or_else(|_| {
                    file.basename().map(|b| b.to_string_lossy().into_owned()).unwrap_or_default()
                });
                let thumbnail = info.as_ref().ok().and_then(|info| {
                    let valid = !info.has_attribute("thumbnail::is-valid") || info.boolean("thumbnail::is-valid");
                    info.attribute_byte_string("thumbnail::path").filter(|_| valid)
                });
                let inside = match thumbnail.and_then(|path| gdk::Texture::from_filename(path.as_str()).ok()) {
                    Some(texture) => picture(&texture),
                    None => match info.as_ref().ok().and_then(|info| info.icon()) {
                        Some(gicon) => {
                            let image = gtk::Image::from_gicon(&gicon);
                            image.set_pixel_size(ICON);
                            image.set_vexpand(true);
                            image.set_valign(gtk::Align::Center);
                            image.upcast()
                        }
                        None => icon("text-x-generic"),
                    },
                };
                (inside, name.clone(), Some(name))
            }
            // Text is never in a tooltip: it may be a password, and the name shows its first words only
            Kind::Text(text) => (icon("text-x-generic"), model::text_name(text), None),
            Kind::Picture(texture) => (picture(texture), t!("Picture"), None),
        };
        thumb.append(&inside);
        (thumb.upcast(), name, tooltip)
    }

    /// Dragged out, an item is offered as a copy, and leaves the shelf once something took it, unless Ctrl was held
    fn drag_out(&self, item: &Rc<Item>) {
        let source = gtk::DragSource::new();
        source.set_actions(gdk::DragAction::COPY);
        let weak_item = Rc::downgrade(item);
        source.connect_prepare(move |_, _, _| {
            let item = weak_item.upgrade()?;
            if item.missing.get() {
                return None;
            }
            Some(match &item.kind {
                Kind::File { file, .. } => gdk::ContentProvider::for_value(&gdk::FileList::from_array(&[file.clone()]).to_value()),
                Kind::Text(text) => gdk::ContentProvider::for_value(&text.to_value()),
                Kind::Picture(texture) => gdk::ContentProvider::for_value(&texture.to_value()),
            })
        });
        let weak_item = Rc::downgrade(item);
        source.connect_drag_begin(move |source, _| {
            let Some(item) = weak_item.upgrade() else { return };
            item.cancelled.set(false);
            item.keep.set(source.current_event_state().contains(gdk::ModifierType::CONTROL_MASK));
            if let Some(thumb) = item.button.child().and_then(|content| content.first_child()) {
                source.set_icon(Some(&gtk::WidgetPaintable::new(Some(&thumb))), THUMB / 2, THUMB / 2);
            }
        });
        let weak_item = Rc::downgrade(item);
        source.connect_drag_cancel(move |_, _, _| {
            if let Some(item) = weak_item.upgrade() {
                item.cancelled.set(true);
            }
            false
        });
        let weak = self.me.clone();
        let weak_item = Rc::downgrade(item);
        source.connect_drag_end(move |_, _, _| {
            let (Some(this), Some(item)) = (weak.upgrade(), weak_item.upgrade()) else { return };
            if item.cancelled.get() || item.keep.get() || control_held() {
                return;
            }
            // Not from inside the drag's own signal: the widget that holds the drag source goes
            glib::idle_add_local_once(move || this.remove(&item));
        });
        item.button.add_controller(source);
    }

    fn set_missing(&self, item: &Rc<Item>, missing: bool) {
        if item.missing.replace(missing) == missing {
            return;
        }
        // Seen greyed, and said so to a screen reader with its name
        if missing {
            item.button.add_css_class("missing");
            item.button.set_tooltip_text(Some(&t!("Moved or deleted")));
            item.button.update_property(&[gtk::accessible::Property::Label(&t!("{name}, moved or deleted", name = item.name.as_str()))]);
        } else {
            item.button.remove_css_class("missing");
            item.button.set_tooltip_text(Some(&item.name));
            item.button.update_property(&[gtk::accessible::Property::Label(&item.name)]);
        }
    }

    fn focused(&self) -> Option<Rc<Item>> {
        let focus = gtk::prelude::GtkWindowExt::focus(&self.shell.window)?;
        self.items.borrow().iter().find(|item| focus == item.button.clone().upcast::<gtk::Widget>() || focus.is_ancestor(&item.button)).cloned()
    }

    fn remove(&self, item: &Rc<Item>) {
        let index = self.items.borrow().iter().position(|held| Rc::ptr_eq(held, item));
        let Some(index) = index else { return };
        let item = self.items.borrow_mut().remove(index);
        detach_menu(&item.button);
        self.list.remove(&item.button);
        if self.items.borrow().is_empty() {
            self.quit();
        } else if let Some(next) = self.items.borrow().get(index.min(self.items.borrow().len() - 1)) {
            next.button.grab_focus();
        }
    }

    fn clear_all(&self) {
        for item in self.items.borrow_mut().drain(..) {
            detach_menu(&item.button);
            self.list.remove(&item.button);
        }
        self.quit();
    }

    /// An item's menu: Remove, Show in Files for a file, and Clear the shelf
    fn menu(&self, item: &Rc<Item>) {
        let popover = gtk::Popover::new();
        popover.add_css_class("shelf-menu");
        let box_ = gtk::Box::new(gtk::Orientation::Vertical, 2);
        let entry = |label: &str, run: Box<dyn Fn()>| {
            let button = gtk::Button::with_label(label);
            button.add_css_class("flat");
            if let Some(child) = button.child().and_then(|c| c.downcast::<gtk::Label>().ok()) {
                child.set_xalign(0.0);
            }
            // The menu is let go of before what it does, which may take its item (and the item's button) away
            let popover = popover.downgrade();
            button.connect_clicked(move |_| {
                if let Some(popover) = popover.upgrade() {
                    popover.popdown();
                    if popover.parent().is_some() {
                        popover.unparent();
                    }
                }
                run();
            });
            box_.append(&button);
        };
        let weak = self.me.clone();
        let weak_item = Rc::downgrade(item);
        entry(&t!("Remove"), Box::new(move || {
            if let (Some(this), Some(item)) = (weak.upgrade(), weak_item.upgrade()) {
                this.remove(&item);
            }
        }));
        if let Kind::File { file, .. } = &item.kind {
            if !item.missing.get() {
                let file = file.clone();
                let window = self.shell.gtk_window();
                entry(&t!("Show in Files"), Box::new(move || {
                    gtk::FileLauncher::new(Some(&file)).open_containing_folder(Some(&window), gio::Cancellable::NONE, |_| {});
                }));
            }
        }
        let weak = self.me.clone();
        entry(&t!("Clear the shelf"), Box::new(move || {
            if let Some(this) = weak.upgrade() {
                this.clear_all();
            }
        }));
        popover.set_child(Some(&box_));
        popover.set_parent(&item.button);
        popover.set_position(if self.row.get() { gtk::PositionType::Top } else { gtk::PositionType::Left });
        // Closed by Escape or a click elsewhere: let go of once GTK is done with it (an entry already did)
        popover.connect_closed(|popover| {
            let popover = popover.downgrade();
            glib::idle_add_local_once(move || {
                if let Some(popover) = popover.upgrade().filter(|p| p.parent().is_some()) {
                    popover.unparent();
                }
            });
        });
        popover.popup();
    }

    // ---- The window ----

    /// As a column at the screen's edge, or a row where a shake opened it; chosen while the shelf is empty
    fn set_row(&self, row: bool) {
        if !self.items.borrow().is_empty() || self.row.replace(row) == row {
            return;
        }
        let orientation = if row { gtk::Orientation::Horizontal } else { gtk::Orientation::Vertical };
        self.body.set_orientation(orientation);
        self.list.set_orientation(orientation);
        self.list.set_spacing(if row { 6 } else { 10 });
        self.clear.set_visible(!row);
        if row {
            self.body.add_css_class("row");
        } else {
            self.body.remove_css_class("row");
        }
    }

    fn say_full(&self) {
        self.say(&t!("The shelf is full"), true);
    }

    fn say(&self, text: &str, passing: bool) {
        self.note.set_text(text);
        self.note.set_visible(true);
        if let Some(source) = self.note_timer.borrow_mut().take() {
            source.remove();
        }
        if passing {
            let weak = self.me.clone();
            let source = glib::timeout_add_local_once(NOTE_FOR, move || {
                if let Some(this) = weak.upgrade() {
                    this.note_timer.borrow_mut().take();
                    this.note.set_visible(false);
                }
            });
            self.note_timer.replace(Some(source));
        }
    }

    fn not_empty(&self) {
        if let Some(source) = self.empty_timer.borrow_mut().take() {
            source.remove();
        }
        if self.note_timer.borrow().is_none() {
            self.note.set_visible(false);
        }
    }

    fn quit(&self) {
        self.shell.app.quit();
    }
}

/// An item's menu let go of before its button is: a popover outlives no parent
fn detach_menu(button: &gtk::Button) {
    let mut child = button.first_child();
    while let Some(widget) = child {
        child = widget.next_sibling();
        if let Ok(popover) = widget.downcast::<gtk::Popover>() {
            popover.unparent();
        }
    }
}

/// A stream read whole, or None when it holds more than `most` bytes (then read no further)
async fn read_most(stream: &gio::InputStream, most: usize) -> Option<Vec<u8>> {
    let mut bytes: Vec<u8> = Vec::new();
    let mut whole = true;
    loop {
        match stream.read_bytes_future(65536, glib::Priority::DEFAULT).await {
            Ok(chunk) if !chunk.is_empty() => {
                bytes.extend_from_slice(&chunk);
                if bytes.len() > most {
                    whole = false;
                    break;
                }
            }
            _ => break,
        }
    }
    let _ = stream.close_future(glib::Priority::DEFAULT).await;
    if whole {
        Some(bytes)
    } else {
        forget(Some(bytes));
        None
    }
}

/// A drop's bytes overwritten once it has become what the shelf holds: text may be a password
fn forget(bytes: Option<Vec<u8>>) {
    if let Some(mut bytes) = bytes {
        bytes.fill(0);
        std::hint::black_box(&bytes);
    }
}

/// Ctrl held now, as the keyboard says
fn control_held() -> bool {
    gdk::Display::default()
        .and_then(|display| display.default_seat())
        .and_then(|seat| seat.keyboard())
        .is_some_and(|keyboard| keyboard.modifier_state().contains(gdk::ModifierType::CONTROL_MASK))
}

impl App for Shelf {
    fn command_line(&self, line: &gio::ApplicationCommandLine) {
        let args: Vec<String> = line.arguments().iter().skip(1).map(|arg| arg.to_string_lossy().into_owned()).collect();
        if args.first().map(String::as_str) == Some("take") {
            self.set_row(args.get(1).map(String::as_str) == Some("row"));
            self.take(line);
        }
    }

    fn open(&self, args: &[String]) {
        if args.first().map(String::as_str) == Some("take") || !self.items.borrow().is_empty() {
            return;
        }
        // Opened by hand with nothing on it: it says what it is for, and closes if nothing comes
        self.say(&t!("Drop files, text or pictures here"), false);
        if self.empty_timer.borrow().is_none() {
            let weak = self.me.clone();
            let source = glib::timeout_add_local_once(EMPTY_FOR, move || {
                if let Some(this) = weak.upgrade() {
                    this.empty_timer.borrow_mut().take();
                    if this.items.borrow().is_empty() && this.reading.get() == 0 {
                        this.quit();
                    }
                }
            });
            self.empty_timer.replace(Some(source));
        }
    }

    /// A hand-off shows the window once its drop is read; a launch by hand shows it at once
    fn presents(&self, args: &[String]) -> bool {
        args.first().map(String::as_str) != Some("take")
    }
}
