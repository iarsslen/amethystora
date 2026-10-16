//! The page's grid and flex layouts that GTK's boxes do not have: a column exactly as wide as the
//! stylesheet's min-width, the list with the open entry beside it or over it, the toolbar's flex-wrap with
//! the search growing, the apps' auto-fill grid, and a heading cut off where the next one covers it.

use std::cell::{Cell, RefCell};

use amethystora_ui::icon::zoom;
use amethystora_ui::{glib, graphene, gtk};
use gtk::prelude::*;
use gtk::subclass::prelude::*;

fn px(value: f64) -> i32 {
    (value * zoom()).round() as i32
}

fn rtl(widget: &gtk::Widget) -> bool {
    widget.direction() == gtk::TextDirection::Rtl
}

// --- Exactly as wide as its minimum ------------------------------------------------------------------------

mod exact {
    use super::*;

    #[derive(Default)]
    pub struct Exact;

    #[glib::object_subclass]
    impl ObjectSubclass for Exact {
        const NAME: &'static str = "AmethystoraLogsExact";
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

// --- The list and the open entry ---------------------------------------------------------------------------

/// What is told the window's height
type OnHeight = Box<dyn Fn(i32)>;

mod panes {
    use super::*;

    #[derive(Default)]
    pub struct Panes {
        pub main: RefCell<Option<gtk::Widget>>,
        pub detail: RefCell<Option<gtk::Widget>>,
        pub open: Cell<bool>,
        pub height: Cell<i32>,
        pub on_height: RefCell<Option<OnHeight>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Panes {
        const NAME: &'static str = "AmethystoraLogsPanes";
        type Type = super::Panes;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("logs");
        }
    }

    impl ObjectImpl for Panes {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl Panes {
        /// A narrow window: the entry opens over the list rather than beside it (max-width: 1100px)
        fn overlaid(&self) -> bool {
            self.obj().root().is_some_and(|root| root.has_css_class("narrow") || root.has_css_class("narrower"))
        }

        fn detail_width(&self, width: i32) -> i32 {
            if self.overlaid() {
                // width: min(460px, 70vw)
                let window = self.obj().root().map(|root| root.width()).unwrap_or(width);
                px(460.0).min((0.7 * window as f64).round() as i32).min(width)
            } else {
                // minmax(340px, 38%)
                px(340.0).max((0.38 * width as f64).round() as i32).min(width)
            }
        }
    }

    impl WidgetImpl for Panes {
        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let main = self.main.borrow().clone();
            let detail = self.detail.borrow().clone().filter(|_| self.open.get());
            let (mut min, mut nat) = (0, 0);
            for child in [main, detail].into_iter().flatten() {
                let (child_min, child_nat, _, _) = child.measure(orientation, if orientation == gtk::Orientation::Vertical { -1 } else { for_size });
                if orientation == gtk::Orientation::Vertical {
                    min = min.max(child_min);
                    nat = nat.max(child_nat);
                } else {
                    // minmax(0, 1fr): the list gives way to the entry
                    min = min.max(child_min);
                    nat = nat.max(child_nat);
                }
            }
            (min, nat, -1, -1)
        }

        fn size_allocate(&self, width: i32, height: i32, _baseline: i32) {
            let widget = self.obj();
            let main = self.main.borrow().clone();
            let detail = self.detail.borrow().clone();
            let open = self.open.get();
            let right_to_left = rtl(widget.upcast_ref());
            let side = if open { self.detail_width(width) } else { 0 };
            let overlaid = self.overlaid();
            if let Some(main) = main {
                let main_width = if open && !overlaid { width - side } else { width };
                let x = if right_to_left && open && !overlaid { side } else { 0 };
                main.size_allocate(&gtk::Allocation::new(x, 0, main_width.max(0), height), -1);
            }
            if let Some(detail) = detail {
                detail.set_child_visible(open);
                if open {
                    let x = if right_to_left { 0 } else { width - side };
                    detail.size_allocate(&gtk::Allocation::new(x, 0, side, height), -1);
                }
            }
            if self.height.get() != height {
                self.height.set(height);
                // What is sized by the window's height (vh) is sized again, after this allocation
                let weak = widget.downgrade();
                glib::idle_add_local_once(move || {
                    if let Some(panes) = weak.upgrade() {
                        let height = panes.imp().height.get();
                        if let Some(on_height) = &*panes.imp().on_height.borrow() {
                            on_height(height);
                        }
                    }
                });
            }
        }
    }
}

glib::wrapper! {
    /// `.logs`: the list, and the open entry beside it in a wide window or over it in a narrow one
    pub struct Panes(ObjectSubclass<panes::Panes>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Panes {
    pub fn new(main: &impl IsA<gtk::Widget>, detail: &impl IsA<gtk::Widget>) -> Panes {
        let panes: Panes = glib::Object::new();
        main.set_parent(&panes);
        detail.set_parent(&panes);
        panes.imp().main.replace(Some(main.clone().upcast()));
        panes.imp().detail.replace(Some(detail.clone().upcast()));
        panes
    }

    pub fn set_open(&self, open: bool) {
        self.imp().open.set(open);
        if open {
            self.add_css_class("open");
        } else {
            self.remove_css_class("open");
        }
        self.queue_resize();
    }

    /// Told the window's height whenever it changes, for what the page sized in vh
    pub fn on_height(&self, callback: impl Fn(i32) + 'static) {
        self.imp().on_height.replace(Some(Box::new(callback)));
    }

    pub fn window_height(&self) -> i32 {
        self.imp().height.get()
    }
}

// --- The toolbar's flex-wrap ------------------------------------------------------------------------------

/// How one child of the toolbar flexes: its basis (None for its own width), whether it grows, its minimum,
/// and whether its start margin is auto
#[derive(Clone, Copy, Default)]
pub struct Flex {
    pub basis: Option<f64>,
    pub grow: bool,
    pub min: f64,
    pub auto_start: bool,
    /// width: 100% (the count in a narrow window)
    pub full: bool,
}

mod toolbar {
    use super::*;

    #[derive(Default)]
    pub struct Toolbar {
        pub items: RefCell<Vec<(gtk::Widget, Flex)>>,
        pub gap: Cell<i32>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Toolbar {
        const NAME: &'static str = "AmethystoraLogsToolbar";
        type Type = super::Toolbar;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Toolbar {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    pub struct Placed {
        pub widget: gtk::Widget,
        pub x: i32,
        pub width: i32,
        pub line: usize,
    }

    impl Toolbar {
        fn flex(&self, flex: &Flex) -> Flex {
            let mut flex = *flex;
            if flex.full && self.obj().root().is_some_and(|root| root.has_css_class("narrower")) {
                flex.auto_start = false;
            } else {
                flex.full = false;
            }
            flex
        }

        /// The lines of children for a width, and where each one goes on its line
        pub fn lines(&self, width: i32) -> Vec<Placed> {
            let gap = px(self.gap.get() as f64);
            let items: Vec<(gtk::Widget, Flex)> =
                self.items.borrow().iter().filter(|(widget, _)| widget.is_visible()).map(|(w, f)| (w.clone(), self.flex(f))).collect();
            // Each child's hypothetical width: its basis, or its own natural width, within its minimum
            let sizes: Vec<(i32, i32)> = items
                .iter()
                .map(|(widget, flex)| {
                    let (min, nat, _, _) = widget.measure(gtk::Orientation::Horizontal, -1);
                    let min = min.max(px(flex.min));
                    let basis = if flex.full { width } else { flex.basis.map(px).unwrap_or(nat) };
                    (min, basis.max(min))
                })
                .collect();
            let mut placed = Vec::new();
            let mut line: Vec<usize> = Vec::new();
            let mut used = 0;
            let mut number = 0;
            let finish = |line: &mut Vec<usize>, used: i32, number: usize, placed: &mut Vec<Placed>| {
                if line.is_empty() {
                    return;
                }
                let free = width - used;
                let growing: Vec<usize> = line.iter().copied().filter(|&i| items[i].1.grow).collect();
                let mut widths: Vec<i32> = line.iter().map(|&i| sizes[i].1).collect();
                if free > 0 && !growing.is_empty() {
                    let share = free / growing.len() as i32;
                    for (k, &i) in line.iter().enumerate() {
                        if items[i].1.grow {
                            widths[k] += share;
                        }
                    }
                } else if free < 0 {
                    // Shrinking, down to each minimum, the growing ones first
                    let mut over = -free;
                    for (k, &i) in line.iter().enumerate() {
                        if over == 0 {
                            break;
                        }
                        let room = widths[k] - sizes[i].0;
                        let take = room.min(over).max(0);
                        widths[k] -= take;
                        over -= take;
                    }
                }
                let total: i32 = widths.iter().sum::<i32>() + gap * (line.len() as i32 - 1);
                let mut x = 0;
                for (k, &i) in line.iter().enumerate() {
                    // margin-inline-start: auto takes what is left, when nothing grows on the line
                    if items[i].1.auto_start && growing.is_empty() && total < width {
                        x += width - total;
                    }
                    placed.push(Placed { widget: items[i].0.clone(), x, width: widths[k], line: number });
                    x += widths[k] + gap;
                }
                line.clear();
            };
            for (i, size) in sizes.iter().enumerate() {
                let extra = if line.is_empty() { size.1 } else { gap + size.1 };
                if !line.is_empty() && used + extra > width {
                    finish(&mut line, used, number, &mut placed);
                    number += 1;
                    used = 0;
                    line.push(i);
                    used += size.1;
                } else {
                    line.push(i);
                    used += extra;
                }
            }
            finish(&mut line, used, number, &mut placed);
            placed
        }

        fn line_heights(&self, placed: &[Placed]) -> Vec<(i32, i32)> {
            let count = placed.iter().map(|p| p.line + 1).max().unwrap_or(0);
            let mut heights = vec![(0, 0); count];
            for item in placed {
                let (min, nat, _, _) = item.widget.measure(gtk::Orientation::Vertical, item.width);
                heights[item.line].0 = heights[item.line].0.max(min);
                heights[item.line].1 = heights[item.line].1.max(nat);
            }
            heights
        }
    }

    impl WidgetImpl for Toolbar {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let gap = px(self.gap.get() as f64);
            if orientation == gtk::Orientation::Horizontal {
                let mut min = 0;
                let mut nat = 0;
                let items = self.items.borrow().clone();
                let visible: Vec<_> = items.iter().filter(|(widget, _)| widget.is_visible()).collect();
                for (widget, flex) in &visible {
                    let (child_min, child_nat, _, _) = widget.measure(orientation, -1);
                    min = min.max(child_min.max(px(flex.min)));
                    nat += flex.basis.map(px).unwrap_or(child_nat).max(child_min);
                }
                nat += gap * (visible.len() as i32 - 1).max(0);
                return (min, nat.max(min), -1, -1);
            }
            let width = if for_size < 0 { self.measure(gtk::Orientation::Horizontal, -1).1 } else { for_size };
            let heights = self.line_heights(&self.lines(width));
            let gaps = gap * (heights.len() as i32 - 1).max(0);
            (heights.iter().map(|h| h.0).sum::<i32>() + gaps, heights.iter().map(|h| h.1).sum::<i32>() + gaps, -1, -1)
        }

        fn size_allocate(&self, width: i32, _height: i32, _baseline: i32) {
            let gap = px(self.gap.get() as f64);
            let placed = self.lines(width);
            let heights = self.line_heights(&placed);
            let mut tops = Vec::with_capacity(heights.len());
            let mut y = 0;
            for (_, nat) in &heights {
                tops.push(y);
                y += nat + gap;
            }
            let right_to_left = rtl(self.obj().upcast_ref());
            for item in &placed {
                let line_height = heights[item.line].1;
                let (_, nat, _, _) = item.widget.measure(gtk::Orientation::Vertical, item.width);
                // align-items: center
                let top = tops[item.line] + (line_height - nat) / 2;
                let x = if right_to_left { width - item.x - item.width } else { item.x };
                item.widget.size_allocate(&gtk::Allocation::new(x, top, item.width, nat), -1);
            }
        }
    }
}

glib::wrapper! {
    /// `.toolbar`: display: flex; flex-wrap: wrap; align-items: center, with what flexes how
    pub struct Toolbar(ObjectSubclass<toolbar::Toolbar>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Toolbar {
    pub fn new(gap: i32) -> Toolbar {
        let toolbar: Toolbar = glib::Object::new();
        toolbar.imp().gap.set(gap);
        toolbar.add_css_class("tools");
        toolbar
    }

    pub fn append(&self, widget: &impl IsA<gtk::Widget>, flex: Flex) {
        widget.set_parent(self);
        self.imp().items.borrow_mut().push((widget.clone().upcast(), flex));
        self.queue_resize();
    }

    /// One child in place of another, flexing the same way
    pub fn replace(&self, old: &gtk::Widget, new: &impl IsA<gtk::Widget>) {
        let mut items = self.imp().items.borrow_mut();
        if let Some(at) = items.iter().position(|(widget, _)| widget == old) {
            new.insert_before(self, Some(old));
            old.unparent();
            items[at].0 = new.clone().upcast();
        }
        drop(items);
        self.queue_resize();
    }
}

// --- The apps' grid ---------------------------------------------------------------------------------------

mod tiles {
    use super::*;

    #[derive(Default)]
    pub struct Tiles {
        pub min: Cell<i32>,
        pub gap: Cell<i32>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Tiles {
        const NAME: &'static str = "AmethystoraLogsTiles";
        type Type = super::Tiles;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("tiles");
        }
    }

    impl ObjectImpl for Tiles {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl Tiles {
        fn children(&self) -> Vec<gtk::Widget> {
            let mut list = Vec::new();
            let mut child = self.obj().first_child();
            while let Some(widget) = child {
                child = widget.next_sibling();
                list.push(widget);
            }
            list
        }

        /// repeat(auto-fill, minmax(min, 1fr)): as many columns as fit, sharing the width
        fn columns(&self, width: i32) -> (usize, i32) {
            let (min, gap) = (px(self.min.get() as f64), px(self.gap.get() as f64));
            let count = (((width + gap) / (min + gap)).max(1)) as usize;
            let column = (width - gap * (count as i32 - 1)) / count as i32;
            (count, column)
        }

        fn rows(&self, width: i32) -> Vec<i32> {
            let (count, column) = self.columns(width);
            let children = self.children();
            children
                .chunks(count)
                .map(|row| row.iter().map(|child| child.measure(gtk::Orientation::Vertical, column).1).max().unwrap_or(0))
                .collect()
        }
    }

    impl WidgetImpl for Tiles {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let gap = px(self.gap.get() as f64);
            if orientation == gtk::Orientation::Horizontal {
                let min = px(self.min.get() as f64);
                return (min, min, -1, -1);
            }
            let rows = self.rows(if for_size < 0 { px(self.min.get() as f64) } else { for_size });
            let height = rows.iter().sum::<i32>() + gap * (rows.len() as i32 - 1).max(0);
            (height, height, -1, -1)
        }

        fn size_allocate(&self, width: i32, _height: i32, _baseline: i32) {
            let gap = px(self.gap.get() as f64);
            let (count, column) = self.columns(width);
            let rows = self.rows(width);
            let right_to_left = rtl(self.obj().upcast_ref());
            let mut y = 0;
            for (row, children) in self.children().chunks(count).enumerate() {
                for (k, child) in children.iter().enumerate() {
                    let x = k as i32 * (column + gap);
                    let x = if right_to_left { width - x - column } else { x };
                    child.size_allocate(&gtk::Allocation::new(x, y, column, rows[row]), -1);
                }
                y += rows[row] + gap;
            }
        }
    }
}

glib::wrapper! {
    /// `.apps`: grid-template-columns: repeat(auto-fill, minmax(220px, 1fr))
    pub struct Tiles(ObjectSubclass<tiles::Tiles>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Tiles {
    pub fn new(min: i32, gap: i32) -> Tiles {
        let tiles: Tiles = glib::Object::new();
        tiles.imp().min.set(min);
        tiles.imp().gap.set(gap);
        tiles
    }

    pub fn append(&self, child: &impl IsA<gtk::Widget>) {
        child.set_parent(self);
    }
}

// --- A heading cut off where the next covers it ------------------------------------------------------------

mod clip {
    use super::*;

    #[derive(Default)]
    pub struct Clip {
        /// How much of the child shows, from the top, or None for all of it
        pub shown: Cell<Option<f32>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Clip {
        const NAME: &'static str = "AmethystoraLogsClip";
        type Type = super::Clip;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Clip {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for Clip {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            match self.obj().first_child() {
                Some(child) => {
                    let (min, nat, _, _) = child.measure(orientation, for_size);
                    (min, nat, -1, -1)
                }
                None => (0, 0, -1, -1),
            }
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            if let Some(child) = self.obj().first_child() {
                child.size_allocate(&gtk::Allocation::new(0, 0, width, height), baseline);
            }
        }

        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let Some(child) = widget.first_child() else { return };
            match self.shown.get() {
                Some(shown) => {
                    snapshot.push_clip(&graphene::Rect::new(0.0, 0.0, widget.width() as f32, shown.max(0.0)));
                    widget.snapshot_child(&child, snapshot);
                    snapshot.pop();
                }
                None => widget.snapshot_child(&child, snapshot),
            }
        }
    }
}

glib::wrapper! {
    pub struct Clip(ObjectSubclass<clip::Clip>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Clip {
    pub fn new(child: &impl IsA<gtk::Widget>) -> Clip {
        let clip: Clip = glib::Object::new();
        child.set_parent(&clip);
        clip
    }

    pub fn set_shown(&self, shown: Option<f32>) {
        if self.imp().shown.get() != shown {
            self.imp().shown.set(shown);
            self.queue_draw();
        }
    }
}
