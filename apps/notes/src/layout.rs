//! The page's CSS layouts that GTK has no box for: a column exactly as wide as the stylesheet's min-width
//! (the sidebar's and the list's grid columns), a wrapping row whose children grow or push to the line's
//! end (`flex-wrap` with `flex-grow` and `margin-inline-start: auto`), and a box as wide as the page's
//! `min(460px, 92vw)`. Exact and Flex are Logs' and Control's (apps/logs, apps/control), the push added
//! here; they may belong in amethystora_ui.

use std::cell::{Cell, RefCell};

use amethystora_ui::icon::zoom;
use amethystora_ui::{glib, gtk};
use gtk::prelude::*;
use gtk::subclass::prelude::*;

fn scaled(px: i32) -> i32 {
    (px as f64 * zoom()).round() as i32
}

fn rtl(widget: &gtk::Widget) -> bool {
    widget.direction() == gtk::TextDirection::Rtl
}

fn visible_children(widget: &gtk::Widget) -> Vec<gtk::Widget> {
    let mut out = Vec::new();
    let mut child = widget.first_child();
    while let Some(widget) = child {
        if widget.is_visible() {
            out.push(widget.clone());
        }
        child = widget.next_sibling();
    }
    out
}

// --- Exactly as wide as its minimum ------------------------------------------------------------------------

mod exact {
    use super::*;

    #[derive(Default)]
    pub struct Exact;

    #[glib::object_subclass]
    impl ObjectSubclass for Exact {
        const NAME: &'static str = "AmethystoraNotesExact";
        type Type = super::Exact;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Exact {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for Exact {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some(child) = self.obj().first_child() else { return (0, 0, -1, -1) };
            let (min, nat, base_min, base_nat) = child.measure(orientation, for_size);
            if orientation == gtk::Orientation::Horizontal { (min, min, -1, -1) } else { (min, nat, base_min, base_nat) }
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            if let Some(child) = self.obj().first_child() {
                child.size_allocate(&gtk::Allocation::new(0, 0, width, height), baseline);
            }
        }
    }
}

glib::wrapper! {
    /// Its child no wider than the child's minimum, which its stylesheet's min-width sets: a column as wide
    /// as the page's grid made it, whatever the words in it would like
    pub struct Exact(ObjectSubclass<exact::Exact>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Exact {
    pub fn new(child: &impl IsA<gtk::Widget>) -> Exact {
        let exact: Exact = glib::Object::new();
        child.set_parent(&exact);
        exact
    }
}

// --- As wide as min(N px, F of the window) -------------------------------------------------------------------

mod fit {
    use super::*;

    #[derive(Default)]
    pub struct Fit {
        pub max: Cell<i32>,
        pub fraction: Cell<f64>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Fit {
        const NAME: &'static str = "AmethystoraNotesFit";
        type Type = super::Fit;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Fit {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl Fit {
        fn width(&self) -> i32 {
            let window = self.obj().root().map(|root| root.width()).unwrap_or(i32::MAX);
            scaled(self.max.get()).min((window as f64 * self.fraction.get()) as i32)
        }
    }

    impl WidgetImpl for Fit {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some(child) = self.obj().first_child() else { return (0, 0, -1, -1) };
            let width = self.width();
            if orientation == gtk::Orientation::Horizontal {
                let (min, _, _, _) = child.measure(orientation, -1);
                let width = width.max(min);
                return (width, width, -1, -1);
            }
            let for_width = if for_size < 0 { width } else { for_size };
            child.measure(orientation, for_width)
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            if let Some(child) = self.obj().first_child() {
                child.size_allocate(&gtk::Allocation::new(0, 0, width, height), baseline);
            }
        }
    }
}

glib::wrapper! {
    /// `width: min(max, fraction * 100vw)`, as the dialogs were
    pub struct Fit(ObjectSubclass<fit::Fit>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Fit {
    pub fn new(child: &impl IsA<gtk::Widget>, max: i32, fraction: f64) -> Fit {
        let fit: Fit = glib::Object::new();
        fit.imp().max.set(max);
        fit.imp().fraction.set(fraction);
        child.set_parent(&fit);
        fit
    }
}

// --- At most so wide, changed as the page goes -----------------------------------------------------------

mod cap {
    use super::*;

    #[derive(Default)]
    pub struct Cap {
        pub max: Cell<i32>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Cap {
        const NAME: &'static str = "AmethystoraNotesCap";
        type Type = super::Cap;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Cap {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl Cap {
        fn max(&self) -> i32 {
            if self.max.get() <= 0 { i32::MAX } else { scaled(self.max.get()) }
        }
    }

    impl WidgetImpl for Cap {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some(child) = self.obj().first_child() else { return (0, 0, -1, -1) };
            if orientation == gtk::Orientation::Horizontal {
                let (min, nat, _, _) = child.measure(orientation, for_size);
                return (min.min(self.max()), nat.min(self.max()).max(min.min(self.max())), -1, -1);
            }
            let width = if for_size < 0 { -1 } else { for_size.min(self.max()) };
            child.measure(orientation, width)
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            let Some(child) = self.obj().first_child() else { return };
            let inner = width.min(self.max());
            let x = if rtl(self.obj().upcast_ref()) { width - inner } else { 0 };
            child.size_allocate(&gtk::Allocation::new(x, 0, inner, height), baseline);
        }
    }
}

glib::wrapper! {
    /// `max-width`, at the start of the line, which the page can change: none while it is 0
    pub struct Cap(ObjectSubclass<cap::Cap>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Cap {
    pub fn new(child: &impl IsA<gtk::Widget>, max: i32) -> Cap {
        let cap: Cap = glib::Object::new();
        cap.imp().max.set(max);
        child.set_parent(&cap);
        cap
    }

    pub fn set_max(&self, max: i32) {
        if self.imp().max.replace(max) != max {
            self.queue_resize();
        }
    }
}

// --- A picture in a note -------------------------------------------------------------------------------------

mod image {
    use super::*;
    use amethystora_ui::{gdk, graphene, gsk};

    #[derive(Default)]
    pub struct Image {
        pub texture: RefCell<Option<gdk::Texture>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Image {
        const NAME: &'static str = "AmethystoraNotesImage";
        type Type = super::Image;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("picture");
            klass.set_accessible_role(gtk::AccessibleRole::Img);
        }
    }

    impl ObjectImpl for Image {}

    impl Image {
        fn natural(&self) -> (f64, f64) {
            match &*self.texture.borrow() {
                Some(texture) => (texture.width() as f64, texture.height() as f64),
                None => (0.0, 0.0),
            }
        }
    }

    impl WidgetImpl for Image {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let (width, height) = self.natural();
            if orientation == gtk::Orientation::Horizontal {
                return (0, width.round() as i32, -1, -1);
            }
            let shown = if for_size < 0 { width } else { width.min(for_size as f64) };
            let tall = if width > 0.0 { (height * shown / width).round() as i32 } else { 0 };
            (tall, tall, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let Some(texture) = self.texture.borrow().clone() else { return };
            let widget = self.obj();
            let (width, height) = self.natural();
            let shown = width.min(widget.width() as f64) as f32;
            let tall = if width > 0.0 { (height * shown as f64 / width) as f32 } else { 0.0 };
            let x = if rtl(widget.upcast_ref()) { widget.width() as f32 - shown } else { 0.0 };
            let bounds = graphene::Rect::new(x, 0.0, shown, tall);
            // img { border-radius: 8px }
            snapshot.push_rounded_clip(&gsk::RoundedRect::from_rect(bounds, 8.0));
            snapshot.append_texture(&texture, &bounds);
            snapshot.pop();
        }
    }
}

glib::wrapper! {
    /// `img { max-width: 100% }`: a picture at its own size, or the width of the page, in its proportions
    pub struct Image(ObjectSubclass<image::Image>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Image {
    pub fn new(texture: &amethystora_ui::gdk::Texture) -> Image {
        let image: Image = glib::Object::new();
        image.imp().texture.replace(Some(texture.clone()));
        image
    }
}

// --- A wrapping row ------------------------------------------------------------------------------------------

/// How one child of a Flex takes its line, as its flex properties did
#[derive(Debug, Clone, Copy, Default)]
pub struct Grow {
    /// flex-grow
    pub grow: f64,
    /// flex-basis in pixels, or its natural width
    pub basis: Option<i32>,
    /// min-width in pixels, below which it does not shrink
    pub min: Option<i32>,
    /// margin-inline-start: auto, the rest of its line before it
    pub push: bool,
}

mod flex {
    use super::*;

    #[derive(Default)]
    pub struct Flex {
        pub gap: Cell<i32>,
        pub line_gap: Cell<i32>,
        /// align-items: flex-start rather than center
        pub top: Cell<bool>,
        pub items: RefCell<Vec<(gtk::Widget, Grow)>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Flex {
        const NAME: &'static str = "AmethystoraNotesFlex";
        type Type = super::Flex;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("flex");
        }
    }

    impl ObjectImpl for Flex {
        fn dispose(&self) {
            self.items.borrow_mut().clear();
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    pub struct Placed {
        pub child: gtk::Widget,
        pub width: i32,
        pub push: bool,
    }

    impl Flex {
        fn grow_of(&self, child: &gtk::Widget) -> Grow {
            self.items.borrow().iter().find(|(widget, _)| widget == child).map(|(_, grow)| *grow).unwrap_or_default()
        }

        fn natural(child: &gtk::Widget, grow: Grow) -> (i32, i32) {
            let (min, nat, _, _) = child.measure(gtk::Orientation::Horizontal, -1);
            let min = grow.min.map(scaled).map(|m| m.max(min)).unwrap_or(min);
            (min, grow.basis.map(scaled).unwrap_or(nat).max(min))
        }

        /// The lines the children take in `width`, as flex-wrap breaks them, each child with its width
        pub fn lines(&self, width: i32) -> Vec<Vec<Placed>> {
            let gap = scaled(self.gap.get());
            let mut lines: Vec<Vec<(gtk::Widget, Grow, i32, i32)>> = Vec::new();
            let mut used = 0;
            for child in visible_children(self.obj().upcast_ref()) {
                let grow = self.grow_of(&child);
                let (min, basis) = Self::natural(&child, grow);
                let fits = lines.last().is_some_and(|line| !line.is_empty() && used + gap + basis <= width);
                if fits {
                    used += gap + basis;
                    lines.last_mut().expect("a line").push((child, grow, basis, min));
                } else {
                    used = basis;
                    lines.push(vec![(child, grow, basis, min)]);
                }
            }
            lines
                .into_iter()
                .map(|line| {
                    let gaps = gap * (line.len() as i32 - 1);
                    let total: i32 = line.iter().map(|item| item.2).sum();
                    let free = width - total - gaps;
                    let growing: f64 = line.iter().map(|item| item.1.grow).sum();
                    let shrinking: f64 = line.iter().map(|item| item.2 as f64).sum();
                    line.into_iter()
                        .map(|(child, grow, basis, min)| {
                            let width = if free >= 0 {
                                if growing > 0.0 { basis + (free as f64 * grow.grow / growing).floor() as i32 } else { basis }
                            } else {
                                // flex-shrink: 1, in proportion to the basis, never below the minimum
                                let share = if shrinking > 0.0 { basis as f64 / shrinking } else { 0.0 };
                                (basis + (free as f64 * share).floor() as i32).max(min)
                            };
                            Placed { child, width, push: grow.push }
                        })
                        .collect()
                })
                .collect()
        }

        fn heights(line: &[Placed]) -> (i32, i32) {
            line.iter().fold((0, 0), |(min, nat), placed| {
                let (child_min, child_nat, _, _) = placed.child.measure(gtk::Orientation::Vertical, placed.width);
                (min.max(child_min), nat.max(child_nat))
            })
        }
    }

    impl WidgetImpl for Flex {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let children = visible_children(self.obj().upcast_ref());
            if children.is_empty() {
                return (0, 0, -1, -1);
            }
            let gap = scaled(self.gap.get());
            if orientation == gtk::Orientation::Horizontal {
                let mut min = 0;
                let mut nat = 0;
                for child in &children {
                    let (child_min, child_nat) = Self::natural(child, self.grow_of(child));
                    min = min.max(child_min);
                    nat += child_nat;
                }
                return (min, nat + gap * (children.len() as i32 - 1), -1, -1);
            }
            let width = if for_size < 0 { self.measure(gtk::Orientation::Horizontal, -1).1 } else { for_size };
            let lines = self.lines(width);
            let gaps = scaled(self.line_gap.get()) * (lines.len() as i32 - 1);
            let (mut min, mut nat) = (gaps, gaps);
            for line in &lines {
                let (line_min, line_nat) = Self::heights(line);
                min += line_min;
                nat += line_nat;
            }
            (min, nat, -1, -1)
        }

        fn size_allocate(&self, width: i32, _height: i32, _baseline: i32) {
            let obj = self.obj();
            let gap = scaled(self.gap.get());
            let line_gap = scaled(self.line_gap.get());
            let right_to_left = rtl(obj.upcast_ref());
            let mut y = 0;
            for line in self.lines(width) {
                let (_, height) = Self::heights(&line);
                let used: i32 = line.iter().map(|placed| placed.width).sum::<i32>() + gap * (line.len() as i32 - 1);
                let mut x = 0;
                for placed in &line {
                    if placed.push {
                        x += (width - used).max(0);
                    }
                    let (_, own, _, _) = placed.child.measure(gtk::Orientation::Vertical, placed.width);
                    let own = own.min(height);
                    let top = if self.top.get() { y } else { y + (height - own) / 2 };
                    let left = if right_to_left { width - x - placed.width } else { x };
                    placed.child.size_allocate(&gtk::Allocation::new(left, top, placed.width, own), -1);
                    x += placed.width + gap;
                }
                y += height + line_gap;
            }
        }
    }
}

glib::wrapper! {
    /// `display: flex; flex-wrap: wrap; align-items: center; gap: line_gap gap`, with each child's grow,
    /// basis, minimum and auto margin given when it is added
    pub struct Flex(ObjectSubclass<flex::Flex>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Flex {
    pub fn new(gap: i32, line_gap: i32, classes: &[&str]) -> Flex {
        let flex: Flex = glib::Object::new();
        flex.imp().gap.set(gap);
        flex.imp().line_gap.set(line_gap);
        for class in classes {
            flex.add_css_class(class);
        }
        flex
    }

    pub fn append(&self, child: &impl IsA<gtk::Widget>) {
        self.append_with(child, Grow::default());
    }

    pub fn append_with(&self, child: &impl IsA<gtk::Widget>, grow: Grow) {
        child.set_parent(self);
        self.imp().items.borrow_mut().push((child.clone().upcast(), grow));
    }

    pub fn clear(&self) {
        self.imp().items.borrow_mut().clear();
        while let Some(child) = self.first_child() {
            child.unparent();
        }
        self.queue_resize();
    }
}
