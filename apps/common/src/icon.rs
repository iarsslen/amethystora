//! The apps' line icons, drawn as the web pages drew their SVG sprites: strokes in the widget's CSS colour,
//! round caps and joins, at any size and scale. Each app keeps its own set (apps/<app>/src/icons.rs, which
//! apps/tools/icons.js writes from the sprite the Electron page had), since the same name was drawn a
//! little differently from app to app.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;

use gtk::glib;
use gtk::gsk;
use gtk::prelude::*;
use gtk::subclass::prelude::*;

/// One element of an icon: an SVG path, stroked unless it is only filled
#[derive(Debug)]
pub struct Shape {
    pub d: &'static str,
    pub fill: bool,
    pub stroke: bool,
    /// Its own stroke width, where the sprite gave one
    pub width: Option<f32>,
}

/// An icon: its view box (24 or 48 units square) and its elements
#[derive(Debug)]
pub struct IconData {
    pub view: f32,
    pub shapes: &'static [Shape],
}

pub static EMPTY: IconData = IconData { view: 24.0, shapes: &[] };

thread_local! {
    static PATHS: RefCell<HashMap<usize, gsk::Path>> = RefCell::new(HashMap::new());
    static ZOOM: Cell<f64> = const { Cell::new(1.0) };
}

/// The window's zoom, which icons and the stone are measured by as the stylesheets are
pub fn zoom() -> f64 {
    ZOOM.with(Cell::get)
}

pub(crate) fn set_zoom(factor: f64) {
    ZOOM.with(|zoom| zoom.set(factor));
}

fn path(d: &'static str) -> Option<gsk::Path> {
    let key = d.as_ptr() as usize;
    PATHS.with(|paths| {
        if let Some(path) = paths.borrow().get(&key) {
            return Some(path.clone());
        }
        let path = gsk::Path::parse(d).ok()?;
        paths.borrow_mut().insert(key, path.clone());
        Some(path)
    })
}

mod imp {
    use super::*;

    pub struct Icon {
        pub data: Cell<&'static IconData>,
        pub size: Cell<i32>,
        pub stroke: Cell<f32>,
        pub spinning: Cell<bool>,
        pub mirrored: Cell<bool>,
        pub angle: Cell<f64>,
        pub tick: RefCell<Option<gtk::TickCallbackId>>,
    }

    impl Default for Icon {
        fn default() -> Self {
            Icon {
                data: Cell::new(&EMPTY),
                size: Cell::new(20),
                stroke: Cell::new(1.8),
                spinning: Cell::new(false),
                mirrored: Cell::new(false),
                angle: Cell::new(0.0),
                tick: RefCell::new(None),
            }
        }
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Icon {
        const NAME: &'static str = "AmethystoraIcon";
        type Type = super::Icon;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("icon");
            klass.set_accessible_role(gtk::AccessibleRole::Presentation);
        }
    }

    impl ObjectImpl for Icon {
        fn dispose(&self) {
            if let Some(tick) = self.tick.take() {
                tick.remove();
            }
        }
    }

    impl WidgetImpl for Icon {
        fn measure(&self, _orientation: gtk::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            let size = (self.size.get() as f64 * zoom()).round() as i32;
            (size, size, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let (width, height) = (widget.width() as f32, widget.height() as f32);
            let side = width.min(height);
            if side <= 0.0 {
                return;
            }
            let data = self.data.get();
            let color = widget.color();
            let scale = side / data.view;
            snapshot.save();
            snapshot.translate(&gtk::graphene::Point::new((width - side) / 2.0, (height - side) / 2.0));
            if self.spinning.get() {
                let half = side / 2.0;
                snapshot.translate(&gtk::graphene::Point::new(half, half));
                snapshot.rotate(self.angle.get() as f32);
                snapshot.translate(&gtk::graphene::Point::new(-half, -half));
            }
            if self.mirrored.get() {
                snapshot.translate(&gtk::graphene::Point::new(side, 0.0));
                snapshot.scale(-1.0, 1.0);
            }
            snapshot.scale(scale, scale);
            for shape in data.shapes {
                let Some(path) = path(shape.d) else { continue };
                if shape.fill {
                    snapshot.append_fill(&path, gsk::FillRule::Winding, &color);
                }
                if shape.stroke {
                    let stroke = gsk::Stroke::new(shape.width.unwrap_or(self.stroke.get()));
                    stroke.set_line_cap(gsk::LineCap::Round);
                    stroke.set_line_join(gsk::LineJoin::Round);
                    snapshot.append_stroke(&path, &stroke, &color);
                }
            }
            snapshot.restore();
        }
    }
}

glib::wrapper! {
    pub struct Icon(ObjectSubclass<imp::Icon>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Icon {
    /// An icon `size` pixels square, its strokes `stroke` units wide in its view box
    pub fn new(data: &'static IconData, size: i32, stroke: f32) -> Icon {
        let icon: Icon = glib::Object::new();
        icon.set_data(data);
        icon.imp().size.set(size);
        icon.imp().stroke.set(stroke);
        icon.set_halign(gtk::Align::Center);
        icon.set_valign(gtk::Align::Center);
        icon
    }

    pub fn set_data(&self, data: &'static IconData) {
        self.imp().data.set(data);
        self.queue_draw();
    }

    pub fn set_size(&self, size: i32) {
        self.imp().size.set(size);
        self.queue_resize();
    }

    /// Turning once a second, as the spinner's `spin` animation did; still where the desktop asks for
    /// no animations
    pub fn set_spinning(&self, spinning: bool) {
        let imp = self.imp();
        imp.spinning.set(spinning);
        if let Some(tick) = imp.tick.take() {
            tick.remove();
        }
        let animations = gtk::Settings::default().map(|s| s.is_gtk_enable_animations()).unwrap_or(true);
        if spinning && animations {
            let id = self.add_tick_callback(|icon, clock| {
                let seconds = clock.frame_time() as f64 / 1_000_000.0;
                icon.imp().angle.set((seconds % 1.0) * 360.0);
                icon.queue_draw();
                glib::ControlFlow::Continue
            });
            imp.tick.replace(Some(id));
        }
        self.queue_draw();
    }

    /// Drawn the other way round in a right-to-left window, for an arrow or chevron that points the way
    /// text runs
    pub fn mirror_in_rtl(self) -> Self {
        self.imp().mirrored.set(gtk::Widget::default_direction() == gtk::TextDirection::Rtl);
        self
    }

    pub fn set_mirrored(&self, mirrored: bool) {
        self.imp().mirrored.set(mirrored);
        self.queue_draw();
    }
}
