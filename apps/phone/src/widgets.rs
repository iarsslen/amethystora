//! The pieces the pages are built from, which need nothing of the window: headings, callouts, tags, buttons, the
//! round avatar and the block a page shows when it has nothing to list. The CSS classes are the other apps' where
//! the piece is the same (`.btn`, `.callout`, `.card`, `.empty`, `.tag`), and phone.css paints them.
//!
//! What a phone said reaches these only as text in a label: nothing here sets markup from outside.

use amethystora_ui::{adw, gtk, pango, ui};
use gtk::prelude::*;

use crate::icons::icon;
use crate::model;

/// How a button looks
#[derive(Debug, Clone, Copy, Default)]
pub struct Look {
    pub icon: Option<&'static str>,
    pub small: bool,
    pub primary: bool,
    pub danger: bool,
    pub disabled: bool,
}

/// A button with its words and, before them, an icon
pub fn button(label: &str, look: Look, on_click: impl Fn() + 'static) -> gtk::Button {
    let mut classes = vec!["btn"];
    if look.small {
        classes.push("small");
    }
    if look.primary {
        classes.push("primary");
    }
    if look.danger {
        classes.push("danger");
    }
    let button = ui::button(label, look.icon.map(|name| icon(name, 16)), &classes, on_click);
    button.set_sensitive(!look.disabled);
    button.set_valign(gtk::Align::Center);
    button
}

/// A button that is only an icon, with a name for screen readers and a tooltip
pub fn icon_button(name: &'static str, size: i32, label: &str, on_click: impl Fn() + 'static) -> gtk::Button {
    let button = gtk::Button::builder().child(&icon(name, size)).css_classes(["plain", "icon-btn"]).valign(gtk::Align::Center).build();
    button.update_property(&[gtk::accessible::Property::Label(label)]);
    button.set_tooltip_text(Some(label));
    button.connect_clicked(move |_| on_click());
    button
}

/// A text link with an icon, as the other apps' `.link`
pub fn link_button(label: &str, name: Option<&'static str>, on_click: impl Fn() + 'static) -> gtk::Button {
    let button = ui::button(label, name.map(|name| icon(name, 15).mirror_in_rtl()), &["link"], on_click);
    button.set_halign(gtk::Align::Start);
    button.set_valign(gtk::Align::Center);
    button
}

/// A heading, which wraps as ui::label's text does; its role can only be given as it is made
pub fn heading(text: &str, class: &str) -> gtk::Label {
    gtk::Label::builder()
        .label(text)
        .accessible_role(gtk::AccessibleRole::Heading)
        .wrap(true)
        .wrap_mode(pango::WrapMode::WordChar)
        .natural_wrap_mode(gtk::NaturalWrapMode::None)
        .xalign(0.0)
        .halign(gtk::Align::Fill)
        .css_classes([class])
        .build()
}

/// A label whose text is centred as a whole
pub fn centered(label: gtk::Label) -> gtk::Label {
    label.set_justify(gtk::Justification::Center);
    label.set_xalign(0.5);
    label
}

/// A box with a role a screen reader is told, which only a new widget can be given
pub fn role_box(orientation: gtk::Orientation, spacing: i32, classes: &[&str], role: gtk::AccessibleRole) -> gtk::Box {
    let container = gtk::Box::builder().orientation(orientation).spacing(spacing).accessible_role(role).build();
    for class in classes {
        container.add_css_class(class);
    }
    container
}

/// A notice with an icon: `tone` is "", "check" (something to look at) or "failed"
pub fn callout(tone: &str, title: &str, text: &str) -> gtk::Box {
    let callout = ui::hbox(12, &["callout", tone]);
    let mark = icon(if tone == "check" || tone == "failed" { "alert" } else { "info" }, 18);
    mark.set_valign(gtk::Align::Start);
    callout.append(&mark);
    let body = ui::vbox(6, &["grow"]);
    body.set_hexpand(true);
    if !title.is_empty() {
        body.append(&ui::label(title, &["strong"]));
    }
    if !text.is_empty() {
        body.append(&ui::label(text, &["p"]));
    }
    callout.append(&body);
    callout
}


/// The column every page is, at most 920 pixels wide in the middle
pub fn page_column(child: &impl IsA<gtk::Widget>) -> gtk::Widget {
    adw::Clamp::builder().maximum_size(920).tightening_threshold(920).child(child).build().upcast()
}

/// Buttons side by side, wrapping where there is no room
pub fn actions(children: Vec<gtk::Widget>, classes: &[&str]) -> adw::WrapBox {
    let actions = ui::wrap(8, 8, classes);
    for child in children {
        child.set_valign(gtk::Align::Center);
        actions.append(&child);
    }
    actions
}

/// Every line of text in it centred, as `.empty`'s text-align: center did to all that was in it
fn center_text(widget: &gtk::Widget) {
    if let Some(label) = widget.downcast_ref::<gtk::Label>() {
        label.set_xalign(0.5);
        label.set_justify(gtk::Justification::Center);
    }
    let mut child = widget.first_child();
    while let Some(widget) = child {
        center_text(&widget);
        child = widget.next_sibling();
    }
}

/// What a page shows when it has nothing to list: a few centred things in a column no wider than a paragraph
pub fn empty(children: Vec<gtk::Widget>) -> gtk::Widget {
    let empty = ui::vbox(8, &["empty"]);
    for child in children {
        child.set_halign(if child.is::<gtk::Label>() { gtk::Align::Fill } else { gtk::Align::Center });
        center_text(&child);
        empty.append(&child);
    }
    ui::limit_center(&empty, 480).upcast()
}

/// A command to type, in a box with a button that copies it
pub fn command(text: &str) -> gtk::Box {
    let row = ui::hbox(8, &["command"]);
    let code = ui::line(text, &["code"]);
    code.set_direction(gtk::TextDirection::Ltr);
    code.set_selectable(true);
    code.set_hexpand(true);
    row.append(&code);
    row.append(&ui::copy_button(text, icon("copy", 15), &amethystora_ui::t!("Copy"), &amethystora_ui::t!("Copied"), &amethystora_ui::t!("Copy the command"), &["btn", "small"]));
    row
}

/// A round avatar: the initials of a name, else a person (or people, for a group)
pub fn avatar(name: &str, group: bool, big: bool) -> gtk::Widget {
    let avatar = ui::hbox(0, &["avatar"]);
    if big {
        avatar.add_css_class("big");
    }
    avatar.set_valign(gtk::Align::Center);
    avatar.set_halign(gtk::Align::Center);
    avatar.set_hexpand(false);
    match model::initials(name).filter(|_| !group) {
        Some(letters) => {
            let label = ui::line(&letters, &["initials"]);
            label.set_hexpand(true);
            label.set_xalign(0.5);
            label.set_halign(gtk::Align::Center);
            avatar.append(&label);
        }
        None => {
            let mark = icon(if group { "users" } else { "user" }, if big { 22 } else { 18 });
            mark.set_hexpand(true);
            avatar.append(&mark);
        }
    }
    avatar.upcast()
}

/// The battery as a small icon with its percentage, and a bolt while it charges
pub fn battery(device: &model::Device) -> Option<gtk::Box> {
    let text = model::battery_text(device)?;
    let chip = ui::hbox(5, &["battery"]);
    if model::battery_low(device) {
        chip.add_css_class("low");
    }
    chip.set_valign(gtk::Align::Center);
    chip.append(&icon("battery", 18));
    chip.append(&ui::line(&text, &[]));
    if device.charging {
        chip.append(&icon("bolt", 13));
    }
    chip.update_property(&[gtk::accessible::Property::Label(&if device.charging {
        amethystora_ui::t!("Battery {level}, charging", level = text)
    } else {
        amethystora_ui::t!("Battery {level}", level = text)
    })]);
    Some(chip)
}

/// A field for a few lines of text, which grows with them: Enter takes the text, Shift+Enter starts a new line
pub struct Field {
    pub root: gtk::Widget,
    pub view: gtk::TextView,
}

/// A field with a hint while it is empty, `on_change` told the text at each change and `on_enter` when it is taken
pub fn field(hint: &str, text: &str, on_change: impl Fn(&str) + 'static, on_enter: impl Fn() + 'static) -> Field {
    let view = gtk::TextView::builder().wrap_mode(gtk::WrapMode::WordChar).accepts_tab(false).css_classes(["field-text"]).build();
    let buffer = view.buffer();
    buffer.set_text(text);
    let scroller = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .max_content_height(150)
        .propagate_natural_height(true)
        .overlay_scrolling(false)
        .css_classes(["field", "page-scroll"])
        .child(&view)
        .build();
    let hint = ui::line(hint, &["field-hint"]);
    hint.set_halign(gtk::Align::Start);
    hint.set_valign(gtk::Align::Start);
    hint.set_can_target(false);
    hint.set_visible(text.is_empty());
    let overlay = gtk::Overlay::new();
    overlay.set_child(Some(&scroller));
    overlay.add_overlay(&hint);
    buffer.connect_changed(move |buffer| {
        let text = buffer.text(&buffer.start_iter(), &buffer.end_iter(), false).to_string();
        hint.set_visible(text.is_empty());
        on_change(&text);
    });
    let keys = gtk::EventControllerKey::new();
    keys.connect_key_pressed(move |_, key, _, modifiers| {
        let enter = matches!(key, amethystora_ui::gdk::Key::Return | amethystora_ui::gdk::Key::KP_Enter);
        if enter && !modifiers.contains(amethystora_ui::gdk::ModifierType::SHIFT_MASK) {
            on_enter();
            return amethystora_ui::glib::Propagation::Stop;
        }
        amethystora_ui::glib::Propagation::Proceed
    });
    view.add_controller(keys);
    Field { root: overlay.upcast(), view }
}
