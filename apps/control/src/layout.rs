//! The page's CSS layouts that GTK has no box for: a grid of as many equal columns as fit
//! (`repeat(auto-fill, minmax(N, 1fr))`), a wrapping row whose fields grow (`flex-wrap` with `flex-grow`
//! and `flex-basis`), a box of a fixed aspect ratio (`aspect-ratio`), a box as wide as its minimum (a
//! grid column of a fixed width), and the bar of a theme's swatch, 58% as wide as the swatch. Nothing here
//! is the Control window's own; they may belong in amethystora_ui.

use std::cell::{Cell, RefCell};

use amethystora_ui::icon::zoom;
use amethystora_ui::{glib, graphene, gsk, gtk};
use gtk::prelude::*;
use gtk::subclass::prelude::*;

fn scaled(px: i32) -> i32 {
    (px as f64 * zoom()).round() as i32
}

fn visible_children(widget: &gtk::Widget) -> Vec<gtk::Widget> {
    let mut children = Vec::new();
    let mut child = widget.first_child();
    while let Some(widget) = child {
        if widget.should_layout() {
            children.push(widget.clone());
        }
        child = widget.next_sibling();
    }
    children
}

fn rtl(widget: &gtk::Widget) -> bool {
    widget.direction() == gtk::TextDirection::Rtl
}

// --- A grid of equal columns --------------------------------------------------------------------------

mod grid {
    use super::*;

    #[derive(Default)]
    pub struct AutoGrid {
        pub column: Cell<i32>,
        pub gap: Cell<i32>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for AutoGrid {
        const NAME: &'static str = "AmethystoraControlGrid";
        type Type = super::AutoGrid;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("grid");
        }
    }

    impl ObjectImpl for AutoGrid {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl AutoGrid {
        /// How many columns fit in `width`, and how wide each is
        pub fn columns(&self, width: i32) -> (usize, i32) {
            let (column, gap) = (scaled(self.column.get()), scaled(self.gap.get()));
            let fit = ((width + gap) / (column + gap).max(1)).max(1) as usize;
            (fit, ((width - gap * (fit as i32 - 1)) / fit as i32).max(0))
        }

        /// Each row's height, for columns `each` wide
        fn rows(&self, children: &[gtk::Widget], fit: usize, each: i32) -> Vec<(i32, i32)> {
            children
                .chunks(fit)
                .map(|row| {
                    row.iter().fold((0, 0), |(min, nat), child| {
                        let (child_min, child_nat, _, _) = child.measure(gtk::Orientation::Vertical, each);
                        (min.max(child_min), nat.max(child_nat))
                    })
                })
                .collect()
        }
    }

    impl WidgetImpl for AutoGrid {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let children = visible_children(self.obj().upcast_ref());
            let (column, gap) = (scaled(self.column.get()), scaled(self.gap.get()));
            if children.is_empty() {
                return (0, 0, -1, -1);
            }
            if orientation == gtk::Orientation::Horizontal {
                let count = children.len() as i32;
                return (column, column * count + gap * (count - 1), -1, -1);
            }
            let width = if for_size < 0 { column } else { for_size };
            let (fit, each) = self.columns(width);
            let rows = self.rows(&children, fit, each);
            let gaps = gap * (rows.len() as i32 - 1);
            let min = rows.iter().map(|r| r.0).sum::<i32>() + gaps;
            let nat = rows.iter().map(|r| r.1).sum::<i32>() + gaps;
            (min, nat, -1, -1)
        }

        fn size_allocate(&self, width: i32, _height: i32, _baseline: i32) {
            let obj = self.obj();
            let children = visible_children(obj.upcast_ref());
            let gap = scaled(self.gap.get());
            let (fit, each) = self.columns(width);
            let rows = self.rows(&children, fit, each);
            let right_to_left = rtl(obj.upcast_ref());
            let mut y = 0;
            for (row, (_, height)) in children.chunks(fit).zip(rows) {
                for (at, child) in row.iter().enumerate() {
                    let x = at as i32 * (each + gap);
                    let x = if right_to_left { width - x - each } else { x };
                    child.size_allocate(&gtk::Allocation::new(x, y, each, height), -1);
                }
                y += height + gap;
            }
        }
    }
}

glib::wrapper! {
    /// `display: grid; grid-template-columns: repeat(auto-fill, minmax(column, 1fr)); gap: gap`: as many
    /// equal columns as fit, each at least `column` pixels wide, every item as tall as its row
    pub struct AutoGrid(ObjectSubclass<grid::AutoGrid>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl AutoGrid {
    pub fn new(column: i32, gap: i32, classes: &[&str]) -> AutoGrid {
        let grid: AutoGrid = glib::Object::new();
        grid.imp().column.set(column);
        grid.imp().gap.set(gap);
        for class in classes {
            grid.add_css_class(class);
        }
        grid
    }

    pub fn append(&self, child: &impl IsA<gtk::Widget>) {
        child.set_parent(self);
    }
}

// --- A wrapping row -----------------------------------------------------------------------------------

/// How one child of a Flex takes its line, as its flex properties did
#[derive(Debug, Clone, Copy, Default)]
pub struct Grow {
    /// flex-grow
    pub grow: f64,
    /// flex-basis in pixels, or its natural width
    pub basis: Option<i32>,
    /// width: 100%, a line of its own
    pub whole_line: bool,
}

mod flex {
    use super::*;

    #[derive(Default)]
    pub struct Flex {
        pub gap: Cell<i32>,
        pub line_gap: Cell<i32>,
        pub center: Cell<bool>,
        pub items: RefCell<Vec<(gtk::Widget, Grow)>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Flex {
        const NAME: &'static str = "AmethystoraControlFlex";
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

    /// A child placed on a line: its width there
    pub struct Placed {
        pub child: gtk::Widget,
        pub width: i32,
    }

    impl Flex {
        fn grow_of(&self, child: &gtk::Widget) -> Grow {
            self.items.borrow().iter().find(|(widget, _)| widget == child).map(|(_, grow)| *grow).unwrap_or_default()
        }

        /// The lines the children take in `width`, as flex-wrap breaks them, each child with its width
        pub fn lines(&self, width: i32) -> Vec<Vec<Placed>> {
            let gap = scaled(self.gap.get());
            let mut lines: Vec<Vec<(gtk::Widget, Grow, i32, i32)>> = Vec::new();
            let mut used = 0;
            for child in visible_children(self.obj().upcast_ref()) {
                let grow = self.grow_of(&child);
                let (min, nat, _, _) = child.measure(gtk::Orientation::Horizontal, -1);
                let basis = if grow.whole_line { width } else { grow.basis.map(scaled).unwrap_or(nat).max(0) };
                let fits = lines.last().is_some_and(|line| !line.is_empty() && used + gap + basis <= width && !line.iter().any(|item| item.1.whole_line));
                if fits && !grow.whole_line {
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
                            Placed { child, width }
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
                    let grow = self.grow_of(child);
                    let (child_min, child_nat, _, _) = child.measure(orientation, -1);
                    min = min.max(child_min);
                    nat += grow.basis.map(scaled).unwrap_or(child_nat).max(child_min);
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
                let mut x = if self.center.get() { ((width - used) / 2).max(0) } else { 0 };
                for placed in &line {
                    // align-items: center
                    let (_, own, _, _) = placed.child.measure(gtk::Orientation::Vertical, placed.width);
                    let own = own.min(height);
                    let left = if right_to_left { width - x - placed.width } else { x };
                    placed.child.size_allocate(&gtk::Allocation::new(left, y + (height - own) / 2, placed.width, own), -1);
                    x += placed.width + gap;
                }
                y += height + line_gap;
            }
        }
    }
}

glib::wrapper! {
    /// `display: flex; flex-wrap: wrap; align-items: center; gap: line_gap gap`, with each child's grow,
    /// basis and whole line given when it is added
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

    /// Each line centred, as `justify-content: center`
    pub fn centered(self) -> Self {
        self.imp().center.set(true);
        self
    }

    pub fn append(&self, child: &impl IsA<gtk::Widget>) {
        self.append_with(child, Grow::default());
    }

    pub fn append_with(&self, child: &impl IsA<gtk::Widget>, grow: Grow) {
        child.set_parent(self);
        self.imp().items.borrow_mut().push((child.clone().upcast(), grow));
    }
}

// --- A fixed aspect ratio -----------------------------------------------------------------------------

mod aspect {
    use super::*;

    #[derive(Default)]
    pub struct Aspect {
        pub ratio: Cell<f64>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Aspect {
        const NAME: &'static str = "AmethystoraControlAspect";
        type Type = super::Aspect;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Aspect {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for Aspect {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some(child) = self.obj().first_child() else { return (0, 0, -1, -1) };
            if orientation == gtk::Orientation::Horizontal {
                let (min, nat, _, _) = child.measure(orientation, -1);
                return (min, nat, -1, -1);
            }
            let width = if for_size < 0 { child.measure(gtk::Orientation::Horizontal, -1).1 } else { for_size };
            let height = (width as f64 * self.ratio.get()).round() as i32;
            let (min, _, _, _) = child.measure(orientation, width);
            (min.max(height), min.max(height), -1, -1)
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            if let Some(child) = self.obj().first_child() {
                child.size_allocate(&gtk::Allocation::new(0, 0, width, height), baseline);
            }
        }
    }
}

glib::wrapper! {
    /// `aspect-ratio`: its child as tall as `ratio` times its width
    pub struct Aspect(ObjectSubclass<aspect::Aspect>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Aspect {
    pub fn new(child: &impl IsA<gtk::Widget>, ratio: f64) -> Aspect {
        let aspect: Aspect = glib::Object::new();
        aspect.imp().ratio.set(ratio);
        child.set_parent(&aspect);
        aspect
    }
}

// --- As wide as its minimum ---------------------------------------------------------------------------

mod tight {
    use super::*;

    #[derive(Default)]
    pub struct Tight;

    #[glib::object_subclass]
    impl ObjectSubclass for Tight {
        const NAME: &'static str = "AmethystoraControlTight";
        type Type = super::Tight;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Tight {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for Tight {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some(child) = self.obj().first_child() else { return (0, 0, -1, -1) };
            let (min, nat, _, _) = child.measure(orientation, for_size);
            if orientation == gtk::Orientation::Horizontal { (min, min, -1, -1) } else { (min, nat, -1, -1) }
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
    pub struct Tight(ObjectSubclass<tight::Tight>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Tight {
    pub fn new(child: &impl IsA<gtk::Widget>) -> Tight {
        let tight: Tight = glib::Object::new();
        child.set_parent(&tight);
        tight
    }
}

// --- What does not wrap, overflowing ------------------------------------------------------------------

mod overflow {
    use super::*;

    #[derive(Default)]
    pub struct Overflow;

    #[glib::object_subclass]
    impl ObjectSubclass for Overflow {
        const NAME: &'static str = "AmethystoraControlOverflow";
        type Type = super::Overflow;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Overflow {
        fn constructed(&self) {
            self.parent_constructed();
            self.obj().set_overflow(gtk::Overflow::Hidden);
        }

        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for Overflow {
        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some(child) = self.obj().first_child() else { return (0, 0, -1, -1) };
            let (min, nat, base_min, base_nat) = child.measure(orientation, if orientation == gtk::Orientation::Horizontal { -1 } else { for_size });
            if orientation == gtk::Orientation::Horizontal { (0, nat, -1, -1) } else { (min, nat, base_min, base_nat) }
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            let Some(child) = self.obj().first_child() else { return };
            let (min, _, _, _) = child.measure(gtk::Orientation::Horizontal, -1);
            let own = width.max(min);
            // Past the end of the line, which is the left in a right-to-left window
            let x = if rtl(self.obj().upcast_ref()) { width - own } else { 0 };
            child.size_allocate(&gtk::Allocation::new(x, 0, own, height), baseline);
        }
    }
}

glib::wrapper! {
    /// A child that never makes its parent wider than the parent would be without it, and runs past it,
    /// cut off, when it is wider: `white-space: nowrap` in a column of a fixed width
    pub struct Overflow(ObjectSubclass<overflow::Overflow>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Overflow {
    pub fn new(child: &impl IsA<gtk::Widget>) -> Overflow {
        let overflow: Overflow = glib::Object::new();
        child.set_parent(&overflow);
        overflow
    }
}

// --- A swatch's bar -----------------------------------------------------------------------------------

mod bar {
    use super::*;

    #[derive(Default)]
    pub struct SwatchBar;

    #[glib::object_subclass]
    impl ObjectSubclass for SwatchBar {
        const NAME: &'static str = "AmethystoraControlSwatchBar";
        type Type = super::SwatchBar;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("swatchbar");
            klass.set_accessible_role(gtk::AccessibleRole::Presentation);
        }
    }

    impl ObjectImpl for SwatchBar {}

    impl WidgetImpl for SwatchBar {
        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let (width, height) = (widget.width() as f32, widget.height() as f32);
            // width: 58%; height: 7px; border-radius: 4px, at the start of the line
            let bar = width * 0.58;
            let x = if rtl(widget.upcast_ref()) { width - bar } else { 0.0 };
            let radius = (4.0 * zoom() as f32).min(height / 2.0);
            let corner = graphene::Size::new(radius, radius);
            let rounded = gsk::RoundedRect::new(graphene::Rect::new(x, 0.0, bar, height), corner, corner, corner, corner);
            snapshot.push_rounded_clip(&rounded);
            snapshot.append_color(&widget.color(), &graphene::Rect::new(x, 0.0, bar, height));
            snapshot.pop();
        }
    }
}

glib::wrapper! {
    /// The bar of a theme's swatch, in the CSS colour, 58% as wide as the swatch; its height is the
    /// stylesheet's min-height
    pub struct SwatchBar(ObjectSubclass<bar::SwatchBar>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Default for SwatchBar {
    fn default() -> Self {
        glib::Object::new()
    }
}

// --- text-wrap: pretty --------------------------------------------------------------------------------

/// The lines a paragraph takes, as the indices of the words each one after the first starts with, for a
/// paragraph whose words are `full` wide with the space after them and `bare` wide without it, in
/// `width`: as `text-wrap: pretty` breaks it in Chromium. That is the greedy breaking, a line at a time,
/// unless it leaves one word alone on the last line; then the same number of lines, the last of them two
/// words at least, filled as evenly as they can be. None when the greedy breaking stands.
pub fn pretty_breaks(full: &[f64], bare: &[f64], width: f64) -> Option<Vec<usize>> {
    let words = full.len();
    if words < 3 {
        return None;
    }
    // A line of the words from..to, without the space after its last
    let line = |from: usize, to: usize| full[from..to - 1].iter().sum::<f64>() + bare[to - 1];
    let mut greedy = vec![0];
    for at in 1..words {
        if line(*greedy.last().expect("one"), at + 1) > width {
            greedy.push(at);
        }
    }
    let lines = greedy.len();
    if lines < 2 || words - greedy[lines - 1] >= 2 {
        return None;
    }
    // cost[k][j]: the best k lines over the first j words, and the word the last of them starts with
    let mut cost = vec![vec![(f64::INFINITY, 0usize); words + 1]; lines + 1];
    cost[0][0] = (0.0, 0);
    for k in 1..=lines {
        for to in 1..=words {
            for from in (k - 1)..to {
                let (before, _) = cost[k - 1][from];
                let used = line(from, to);
                if !before.is_finite() || used > width {
                    continue;
                }
                let last = k == lines && to == words;
                if last && to - from < 2 {
                    continue;
                }
                // The room left on the last line is no fault of it
                let slack = if last { 0.0 } else { (width - used).powi(2) };
                if before + slack < cost[k][to].0 {
                    cost[k][to] = (before + slack, from);
                }
            }
        }
    }
    if !cost[lines][words].0.is_finite() {
        return None;
    }
    let mut starts = Vec::new();
    let (mut k, mut to) = (lines, words);
    while k > 0 {
        let from = cost[k][to].1;
        starts.push(from);
        to = from;
        k -= 1;
    }
    starts.reverse();
    starts.remove(0);
    Some(starts)
}

mod pretty {
    use super::*;

    /// A paragraph's words: where each starts, and how wide it is with and without the space after it, for
    /// the text and font they were measured in
    #[derive(Default, Clone)]
    pub struct Words {
        pub key: String,
        pub starts: Vec<usize>,
        pub full: Vec<f64>,
        pub bare: Vec<f64>,
    }

    #[derive(Default)]
    pub struct Pretty {
        pub label: RefCell<Option<gtk::Label>>,
        pub words: RefCell<Words>,
        /// The words the lines start with, as last given to the label
        pub applied: RefCell<Option<Vec<usize>>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Pretty {
        const NAME: &'static str = "AmethystoraControlPretty";
        type Type = super::Pretty;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Pretty {
        fn dispose(&self) {
            if let Some(label) = self.label.take() {
                label.unparent();
            }
        }
    }

    impl Pretty {
        fn label(&self) -> Option<gtk::Label> {
            self.label.borrow().clone()
        }

        /// The words of the label's text in its own font, measured once for each text and font. Breaks are
        /// taken at spaces, which is where the languages the window speaks break.
        fn words(&self, label: &gtk::Label) -> Words {
            let text = label.text().to_string();
            let font = label.pango_context().font_description().map(|font| font.to_string()).unwrap_or_default();
            let key = format!("{font}\n{text}");
            if self.words.borrow().key == key {
                return self.words.borrow().clone();
            }
            let probe = label.layout().copy();
            probe.set_width(-1);
            let measure = |part: &str| {
                probe.set_text(part);
                probe.size().0 as f64
            };
            let mut words = Words { key, ..Default::default() };
            let mut start = 0;
            let ends: Vec<usize> = text.match_indices(' ').map(|(at, _)| at + 1).chain(std::iter::once(text.len())).collect();
            for end in ends {
                if end > start && !text[start..end].trim().is_empty() {
                    words.starts.push(start);
                    words.full.push(measure(&text[start..end]));
                    words.bare.push(measure(text[start..end].trim_end_matches(' ')));
                }
                start = end;
            }
            self.words.replace(words.clone());
            words
        }

        /// The label made to break where text-wrap: pretty would in `width`
        pub fn apply(&self, width: i32) {
            let Some(label) = self.label() else { return };
            let words = self.words(&label);
            // A pixel to spare, for what shaping across the words adds
            let room = ((width - 1).max(0) * gtk::pango::SCALE) as f64;
            let breaks = pretty_breaks(&words.full, &words.bare, room);
            if *self.applied.borrow() == breaks {
                return;
            }
            let attributes = breaks.as_ref().map(|breaks| {
                let list = gtk::pango::AttrList::new();
                let text = label.text();
                let mut lines: Vec<usize> = vec![0];
                lines.extend(breaks.iter().map(|&word| words.starts[word]));
                lines.push(text.len());
                // No break inside a line: Pango then breaks only between them, where they were chosen
                for pair in lines.windows(2) {
                    let end = text[..pair[1]].char_indices().next_back().map(|(at, _)| at).unwrap_or(pair[1]);
                    let mut keep = gtk::pango::AttrInt::new_allow_breaks(false);
                    keep.set_start_index(pair[0] as u32);
                    keep.set_end_index(end.max(pair[0]) as u32);
                    list.insert(keep);
                }
                list
            });
            self.applied.replace(breaks);
            label.set_attributes(attributes.as_ref());
        }
    }

    impl WidgetImpl for Pretty {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            gtk::SizeRequestMode::HeightForWidth
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some(label) = self.label() else { return (0, 0, -1, -1) };
            if orientation == gtk::Orientation::Horizontal {
                // As the label is with no lines chosen: its longest word, and all of it on one line
                let words = self.words(&label);
                let pixels = |units: f64| (units / gtk::pango::SCALE as f64).ceil() as i32;
                let min = words.bare.iter().cloned().fold(0.0, f64::max);
                let all = words.full.iter().sum::<f64>() - words.full.last().copied().unwrap_or(0.0) + words.bare.last().copied().unwrap_or(0.0);
                return (pixels(min), pixels(all), -1, -1);
            }
            if for_size >= 0 {
                self.apply(for_size);
            }
            label.measure(orientation, for_size)
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            if let Some(label) = self.label() {
                self.apply(width);
                label.size_allocate(&gtk::Allocation::new(0, 0, width, height), baseline);
            }
        }
    }
}

glib::wrapper! {
    /// A paragraph that breaks its lines as `text-wrap: pretty` did, around the label that draws it
    pub struct Pretty(ObjectSubclass<pretty::Pretty>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Pretty {
    pub fn new(label: &gtk::Label) -> Pretty {
        let pretty: Pretty = glib::Object::new();
        label.set_parent(&pretty);
        pretty.imp().label.replace(Some(label.clone()));
        pretty
    }
}

#[cfg(test)]
mod tests {
    use super::pretty_breaks;

    #[test]
    fn breaks_as_text_wrap_pretty() {
        // Each word 10 wide and 12 with the space after it: four fit on a line of 50
        let full = vec![12.0; 9];
        let bare = vec![10.0; 9];
        // Greedy gives 4, 4 and 1: the last line gets two, and the first two share the other seven
        let breaks = pretty_breaks(&full, &bare, 50.0).unwrap();
        assert_eq!(breaks.len(), 2);
        assert_eq!(9 - breaks[1], 2);
        assert!(breaks[0] == 3 || breaks[0] == 4);
        // Greedy gives 4 and 4: it stands
        assert_eq!(pretty_breaks(&full[..8], &bare[..8], 50.0), None);
        // One line, or too few words
        assert_eq!(pretty_breaks(&full[..3], &bare[..3], 50.0), None);
        assert_eq!(pretty_breaks(&full[..2], &bare[..2], 5.0), None);
        // 4 and 1 becomes 3 and 2
        assert_eq!(pretty_breaks(&full[..5], &bare[..5], 50.0), Some(vec![3]));
        // Words of different widths: 30 and three of 10 on 45 is 30 10 | 10 10 greedily, which stands
        let full = [32.0, 12.0, 12.0, 12.0];
        let bare = [30.0, 10.0, 10.0, 10.0];
        assert_eq!(pretty_breaks(&full, &bare, 45.0), None);
        // ...and on 33, 30 | 10 10 | 10, which becomes 30 | 10 | 10 10
        assert_eq!(pretty_breaks(&full, &bare, 33.0), Some(vec![1, 2]));
    }
}
