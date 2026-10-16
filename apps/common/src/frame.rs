//! The window most apps are: a sidebar with the wordmark, the sections and a foot, beside the page. The
//! structure and CSS classes are the Electron pages' (`.sidebar`, `.nav`, `.nav button`, `.badge`,
//! `.sidebar-foot`, `.terminal`); each app's stylesheet keeps its own sizes for them, as before.
//!
//! There is no title bar: the window can be moved by any empty part of it (gtk::WindowHandle), and its
//! buttons are wherever the app puts `controls()`, over the top of the page unless the page has a bar of its
//! own there.

use gtk::prelude::*;

use crate::icon::Icon;
use crate::ui;

/// The sidebar, `width` pixels wide, beside `main`, with the window's buttons over the top of `main` when
/// `controls_over_main`
pub fn with_sidebar(sidebar: &impl IsA<gtk::Widget>, main: &impl IsA<gtk::Widget>, width: i32, controls_over_main: bool) -> gtk::Widget {
    sidebar.set_size_request(width, -1);
    sidebar.set_hexpand(false);
    main.set_hexpand(true);
    let layout = ui::hbox(0, &["layout"]);
    layout.append(sidebar);
    if controls_over_main {
        let overlay = gtk::Overlay::new();
        overlay.set_child(Some(main));
        overlay.set_hexpand(true);
        let controls = controls();
        controls.set_halign(gtk::Align::End);
        controls.set_valign(gtk::Align::Start);
        controls.add_css_class("floating");
        overlay.add_overlay(&controls);
        layout.append(&overlay);
    } else {
        layout.append(main);
    }
    gtk::WindowHandle::builder().child(&layout).build().upcast()
}

/// The window's own buttons, as the desktop has them (close, and whatever else it is set to show)
pub fn controls() -> gtk::WindowControls {
    let controls = gtk::WindowControls::new(gtk::PackType::End);
    controls.add_css_class("window-controls");
    controls
}

/// The column the sidebar is: the wordmark, then whatever the app adds, then its foot at the bottom
pub struct Sidebar {
    pub root: gtk::Box,
    /// Where the sections go, between the wordmark and the foot
    pub body: gtk::Box,
    pub foot: gtk::Box,
}

impl Sidebar {
    /// `spacing` is the page's `.sidebar { gap }`
    pub fn new(brand: &gtk::Box, spacing: i32) -> Sidebar {
        let root = ui::vbox(spacing, &["sidebar"]);
        root.append(brand);
        let body = ui::vbox(spacing, &["sidebar-body"]);
        body.set_vexpand(true);
        root.append(&body);
        let foot = ui::vbox(14, &["sidebar-foot"]);
        root.append(&foot);
        Sidebar { root, body, foot }
    }
}

/// A list of sections in the sidebar, as `.nav`
pub fn nav(spacing: i32, label: Option<&str>, accessible: &str) -> gtk::Box {
    let nav = ui::vbox(spacing, &["nav"]);
    nav.update_property(&[gtk::accessible::Property::Label(accessible)]);
    if let Some(label) = label {
        // In capitals the language's own way: GTK does not measure the stylesheet's text-transform
        nav.append(&ui::label(&label.to_uppercase(), &["nav-label"]));
    }
    nav
}

/// One section of the sidebar: its icon and name, then whatever the app adds (a badge, a state, the
/// external-link mark), as `.nav button` with `.grow` for the name
pub struct NavButton {
    pub button: gtk::Button,
    pub content: gtk::Box,
    pub label: gtk::Label,
}

impl NavButton {
    pub fn new(icon: Icon, text: &str, spacing: i32) -> NavButton {
        let content = ui::hbox(spacing, &["content"]);
        content.append(&icon);
        let label = ui::line(text, &["grow"]);
        label.set_hexpand(true);
        label.set_ellipsize(gtk::pango::EllipsizeMode::End);
        content.append(&label);
        let button = gtk::Button::builder().child(&content).css_classes(["plain", "nav-button"]).build();
        NavButton { button, content, label }
    }

    /// Whatever goes after the name: a badge, a state, the mark of a window that opens elsewhere
    pub fn append(&self, widget: &impl IsA<gtk::Widget>) {
        self.content.append(widget);
    }

    /// The section the page shows, as aria-current was
    pub fn set_current(&self, current: bool) {
        if current {
            self.button.add_css_class("current");
        } else {
            self.button.remove_css_class("current");
        }
        self.button.update_state(&[gtk::accessible::State::Selected(Some(current))]);
    }
}

/// The count or word after a section's name, as `.badge`, hidden while it has nothing to say
pub fn badge() -> gtk::Label {
    let badge = ui::line("", &["badge"]);
    badge.set_xalign(0.5);
    badge.set_valign(gtk::Align::Center);
    badge.set_visible(false);
    badge
}

/// "Also in a terminal:" and the command under it, as the sidebars' `.terminal`
pub fn terminal(lead: &str, command: &str) -> gtk::Box {
    let terminal = ui::vbox(0, &["terminal"]);
    terminal.append(&ui::label(lead, &[]));
    let code = ui::label(command, &["code"]);
    code.set_direction(gtk::TextDirection::Ltr);
    code.set_selectable(true);
    terminal.append(&code);
    terminal
}
