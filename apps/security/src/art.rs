//! The two drawings of the page that are not line icons: the app's own shield on the overview, and the stone
//! the scanning page shows while a scan runs.

use std::cell::{Cell, RefCell};

use amethystora_ui::gem::{self, Gem};
use amethystora_ui::{gdk, gio, glib, graphene, gsk, gtk};
use gtk::prelude::*;
use gtk::subclass::prelude::*;

// --- The shield ---------------------------------------------------------------------------------------------

/// The app's own icon, the pack's shield with report bars in it, both drawn from the one gradient: the same
/// drawing the page had in its index.html. It is a modified part of candy-icons and so under the GNU General
/// Public License, version 3 (NOTICE), which is why it is read from where the image installs it, at run time,
/// and never compiled into this program. Without the file there is no shield, and the badge stays.
const SHIELD_FILE: &str = "/usr/share/icons/hicolor/scalable/apps/amethystora-security-status.svg";

mod shield {
    use super::*;

    #[derive(Default)]
    pub struct Shield {
        pub size: Cell<i32>,
        /// The icon rendered for (pixel size, scale factor), made again when either changes
        pub drawn: RefCell<Option<(i32, i32, gtk::IconPaintable)>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Shield {
        const NAME: &'static str = "AmethystoraSecurityShield";
        type Type = super::Shield;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("art");
            klass.set_accessible_role(gtk::AccessibleRole::Presentation);
        }
    }

    impl ObjectImpl for Shield {
        fn constructed(&self) {
            self.parent_constructed();
            self.obj().connect_scale_factor_notify(|shield| shield.queue_draw());
        }
    }

    impl WidgetImpl for Shield {
        fn measure(&self, _orientation: gtk::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            let size = (self.size.get() as f64 * amethystora_ui::icon::zoom()).round() as i32;
            (size, size, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let side = widget.width().min(widget.height());
            if side <= 0 || !std::path::Path::new(SHIELD_FILE).exists() {
                return;
            }
            let scale = widget.scale_factor();
            let fresh = !matches!(&*self.drawn.borrow(), Some((size, at, _)) if *size == side && *at == scale);
            if fresh {
                let icon = gtk::IconPaintable::for_file(&gio::File::for_path(SHIELD_FILE), side, scale);
                self.drawn.replace(Some((side, scale, icon)));
            }
            if let Some((_, _, icon)) = &*self.drawn.borrow() {
                icon.snapshot(snapshot.upcast_ref::<gdk::Snapshot>(), side as f64, side as f64);
            }
        }
    }
}

glib::wrapper! {
    /// The shield of the overview's emblem
    pub struct Shield(ObjectSubclass<shield::Shield>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Shield {
    pub fn new(size: i32) -> Shield {
        let shield: Shield = glib::Object::new();
        shield.imp().size.set(size);
        shield
    }
}

// --- The stone while a scan runs --------------------------------------------------------------------------------

mod stone {
    use super::*;

    #[derive(Default)]
    pub struct ScanGem {
        pub stone: RefCell<Option<Gem>>,
        pub started: Cell<i64>,
        pub now: Cell<i64>,
        pub tick: RefCell<Option<gtk::TickCallbackId>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for ScanGem {
        const NAME: &'static str = "AmethystoraSecurityGem";
        type Type = super::ScanGem;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("scangem");
            klass.set_accessible_role(gtk::AccessibleRole::Presentation);
        }
    }

    impl ObjectImpl for ScanGem {
        fn constructed(&self) {
            self.parent_constructed();
            let stone = Gem::plain(STONE);
            stone.set_parent(&*self.obj());
            self.stone.replace(Some(stone));
        }

        fn dispose(&self) {
            if let Some(tick) = self.tick.take() {
                tick.remove();
            }
            if let Some(stone) = self.stone.take() {
                stone.unparent();
            }
        }
    }

    /// The box, the stone in it, and how far the glow reaches past the box: .gem, .gem > * and its ::before
    const SIZE: f32 = 176.0;
    const STONE: f32 = 156.0;
    const REACH: f32 = 36.0;

    impl WidgetImpl for ScanGem {
        fn measure(&self, _orientation: gtk::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            let size = (SIZE as f64 * amethystora_ui::icon::zoom()).round() as i32;
            (size, size, -1, -1)
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            if let Some(stone) = self.stone.borrow().as_ref() {
                let side = (STONE as f64 * amethystora_ui::icon::zoom()).round() as i32;
                stone.size_allocate(&gtk::Allocation::new((width - side) / 2, (height - side) / 2, side, side), baseline);
            }
        }

        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let zoom = amethystora_ui::icon::zoom() as f32;
            let (width, height) = (widget.width() as f32, widget.height() as f32);
            let seconds = (self.now.get() - self.started.get()) as f64 / 1_000_000.0;
            let moving = self.tick.borrow().is_some();
            // The glow: radial-gradient(closest-side, accent 42%, accent 12% 55%, transparent), breathing between
            // 0.55 at 94% and 1 at 105% every 3.2 s, eased in and out (glow)
            let (opacity, scale) = if moving { breathe(seconds) } else { (1.0, 1.0) };
            let accent = widget.color();
            let tint = |alpha: f32| gdk::RGBA::new(accent.red(), accent.green(), accent.blue(), alpha);
            let center = graphene::Point::new(width / 2.0, height / 2.0);
            let radius = (width.min(height) / 2.0 + REACH * zoom) * scale as f32;
            snapshot.push_opacity(opacity);
            snapshot.append_radial_gradient(
                &graphene::Rect::new(center.x() - radius, center.y() - radius, 2.0 * radius, 2.0 * radius),
                &center,
                radius,
                radius,
                0.0,
                1.0,
                &[gsk::ColorStop::new(0.0, tint(0.42)), gsk::ColorStop::new(0.55, tint(0.12)), gsk::ColorStop::new(1.0, tint(0.0))],
            );
            snapshot.pop();
            let Some(stone) = self.stone.borrow().clone() else { return };
            widget.snapshot_child(&stone, snapshot);
            if !moving {
                return;
            }
            // A band of light passing down the stone, as the glint does in the boot splash: 80 px of the 156 px
            // box, from above it to below it every 2.6 s, only where the stone is (sweep)
            let side = STONE * zoom;
            let band = 80.0 * zoom;
            let progress = gem::cubic_bezier(0.45, 0.05, 0.55, 0.95, (seconds % 2.6) / 2.6) as f32;
            let left = (width - side) / 2.0;
            let top = (height - side) / 2.0 - band + progress * (side + 2.0 * band);
            snapshot.push_mask(gsk::MaskMode::Alpha);
            widget.snapshot_child(&stone, snapshot);
            snapshot.pop();
            let light = gdk::RGBA::new(246.0 / 255.0, 239.0 / 255.0, 1.0, 0.62);
            let clear = gdk::RGBA::new(246.0 / 255.0, 239.0 / 255.0, 1.0, 0.0);
            snapshot.append_linear_gradient(
                &graphene::Rect::new(left, top, side, band),
                &graphene::Point::new(0.0, top),
                &graphene::Point::new(0.0, top + band),
                &[gsk::ColorStop::new(0.0, clear), gsk::ColorStop::new(0.5, light), gsk::ColorStop::new(1.0, clear)],
            );
            snapshot.pop();
        }
    }

    // @keyframes glow { 0%, 100% { opacity: 0.55; scale 0.94 } 50% { opacity: 1; scale 1.05 } }, eased in and out
    fn breathe(seconds: f64) -> (f64, f64) {
        let phase = (seconds % 3.2) / 3.2;
        let (from, to, x) = if phase < 0.5 { ((0.55, 0.94), (1.0, 1.05), phase * 2.0) } else { ((1.0, 1.05), (0.55, 0.94), phase * 2.0 - 1.0) };
        let e = gem::ease_in_out(x);
        (from.0 + (to.0 - from.0) * e, from.1 + (to.1 - from.1) * e)
    }
}

glib::wrapper! {
    /// The stone of the scanning page: its glow breathing and a band of light passing down it, as the page's
    /// `.gem` had them; still where the desktop asks for no animations
    pub struct ScanGem(ObjectSubclass<stone::ScanGem>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl ScanGem {
    pub fn new() -> ScanGem {
        let gem: ScanGem = glib::Object::new();
        gem.set_halign(gtk::Align::Center);
        let animations = gtk::Settings::default().map(|s| s.is_gtk_enable_animations()).unwrap_or(true);
        if animations {
            gem.imp().started.set(-1);
            let id = gem.add_tick_callback(|gem, clock| {
                let imp = gem.imp();
                if imp.started.get() < 0 {
                    imp.started.set(clock.frame_time());
                }
                imp.now.set(clock.frame_time());
                gem.queue_draw();
                glib::ControlFlow::Continue
            });
            gem.imp().tick.replace(Some(id));
        }
        gem
    }
}

impl Default for ScanGem {
    fn default() -> Self {
        ScanGem::new()
    }
}
