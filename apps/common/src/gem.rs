//! The stone of the boot splash, drawn from the polygons of gem.svg, which branding/generate.mjs writes
//! into apps/common/assets: crisp at any size, and in parts, the bowl and the stem (gem-stem.svg), which
//! the Logs and Notes windows move on their own.
//!
//! Three looks, each the Electron page's:
//!
//! - the "a" of the wordmark, lit by the login screen's glow: three drop-shadows in the splash's shades,
//!   each over the last, sized in em of the wordmark;
//! - the stone on a halo of the theme's accent (the widget's CSS colour), as the pages' `.gem` had it, which
//!   can breathe, have a band of light pass down it, or lift its stem like a latch;
//! - the small mark that reads the journal, its stem blinking as a cursor does.

use std::cell::{Cell, RefCell};
use std::sync::OnceLock;

use gtk::gdk;
use gtk::glib;
use gtk::graphene;
use gtk::gsk;
use gtk::prelude::*;
use gtk::subclass::prelude::*;

const GEM_SVG: &str = include_str!("../assets/gem.svg");
const STEM_SVG: &str = include_str!("../assets/gem-stem.svg");

struct Facet {
    points: Vec<(f32, f32)>,
    color: gdk::RGBA,
    stem: bool,
}

struct Stone {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    facets: Vec<Facet>,
}

fn attribute<'a>(element: &'a str, name: &str) -> Option<&'a str> {
    let start = element.find(&format!(" {name}=\""))? + name.len() + 3;
    let end = element[start..].find('"')? + start;
    Some(&element[start..end])
}

fn stone() -> &'static Stone {
    static STONE: OnceLock<Stone> = OnceLock::new();
    STONE.get_or_init(|| {
        let view: Vec<f32> = attribute(GEM_SVG, "viewBox")
            .unwrap_or("0 0 256 256")
            .split_whitespace()
            .filter_map(|v| v.parse().ok())
            .collect();
        let stem: Vec<&str> = STEM_SVG.split("<polygon").skip(1).filter_map(|e| attribute(e, "points")).collect();
        let facets = GEM_SVG
            .split("<polygon")
            .skip(1)
            .filter_map(|element| {
                let points = attribute(element, "points")?;
                let color = gdk::RGBA::parse(attribute(element, "fill")?).ok()?;
                let parsed = points
                    .split_whitespace()
                    .filter_map(|pair| {
                        let (x, y) = pair.split_once(',')?;
                        Some((x.parse().ok()?, y.parse().ok()?))
                    })
                    .collect();
                Some(Facet { points: parsed, color, stem: stem.contains(&points) })
            })
            .collect();
        Stone { x: view[0], y: view[1], width: view[2], height: view[3], facets }
    })
}

fn facet_path(facet: &Facet, stone: &Stone) -> gsk::Path {
    let builder = gsk::PathBuilder::new();
    for (i, (x, y)) in facet.points.iter().enumerate() {
        if i == 0 {
            builder.move_to(x - stone.x, y - stone.y);
        } else {
            builder.line_to(x - stone.x, y - stone.y);
        }
    }
    builder.close();
    builder.to_path()
}

/// The stone, `width` wide, its top left at the snapshot's origin; the stem moved up by `lift` of its height
/// and drawn at `stem_opacity`
fn draw_stone(snapshot: &gtk::Snapshot, width: f32, lift: f32, stem_opacity: f32, only: Option<bool>) {
    let stone = stone();
    let scale = width / stone.width;
    snapshot.save();
    snapshot.scale(scale, scale);
    let stroke = gsk::Stroke::new(0.6);
    stroke.set_line_join(gsk::LineJoin::Round);
    for facet in &stone.facets {
        if only.is_some_and(|stem| stem != facet.stem) {
            continue;
        }
        let path = facet_path(facet, stone);
        let moved = facet.stem && (lift != 0.0 || stem_opacity < 1.0);
        if moved {
            snapshot.save();
            snapshot.translate(&graphene::Point::new(0.0, -lift * stone.height));
            snapshot.push_opacity(stem_opacity as f64);
        }
        snapshot.append_fill(&path, gsk::FillRule::Winding, &facet.color);
        snapshot.append_stroke(&path, &stroke, &facet.color);
        if moved {
            snapshot.pop();
            snapshot.restore();
        }
    }
    snapshot.restore();
}

fn stone_ratio() -> f32 {
    let stone = stone();
    stone.height / stone.width
}

/// A CSS cubic-bezier timing function at progress `x`
pub fn cubic_bezier(x1: f64, y1: f64, x2: f64, y2: f64, x: f64) -> f64 {
    if x <= 0.0 {
        return 0.0;
    }
    if x >= 1.0 {
        return 1.0;
    }
    let curve = |a: f64, b: f64, t: f64| 3.0 * a * (1.0 - t).powi(2) * t + 3.0 * b * (1.0 - t) * t * t + t * t * t;
    let (mut low, mut high) = (0.0, 1.0);
    let mut t = x;
    for _ in 0..40 {
        let value = curve(x1, x2, t);
        if (value - x).abs() < 1e-6 {
            break;
        }
        if value < x {
            low = t;
        } else {
            high = t;
        }
        t = (low + high) / 2.0;
    }
    curve(y1, y2, t)
}

pub fn ease_in_out(x: f64) -> f64 {
    cubic_bezier(0.42, 0.0, 0.58, 1.0, x)
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Look {
    /// The "a" of the wordmark, `em` pixels being the wordmark's font size
    Mark { em: f32 },
    /// On a halo: the box, the stone in it and how far the halo reaches past the box, in pixels
    Halo { size: f32, stone: f32, reach: f32 },
    /// The small mark that reads the journal
    #[default]
    Plain,
}

/// What the stone does while something happens
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Motion {
    #[default]
    Still,
    /// The halo breathes, once every so many seconds
    Breathe(f64),
    /// The halo breathes every 3.2 s and a band of light passes down the stone every 2.6 s (Updates)
    Sweep,
    /// The halo breathes every 2.4 s and the stem lifts like a latch every 1.8 s (Notes)
    Latch,
    /// The stem blinks as a cursor does, every 1.1 s (Logs)
    Blink,
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Gem {
        pub look: Cell<Look>,
        pub size: Cell<f32>,
        pub motion: Cell<Motion>,
        /// Where the letters beside it sit, from its allocation, for the wordmark's "a"
        pub baseline: Cell<i32>,
        pub started: Cell<i64>,
        pub now: Cell<i64>,
        pub tick: RefCell<Option<gtk::TickCallbackId>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Gem {
        const NAME: &'static str = "AmethystoraGem";
        type Type = super::Gem;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("gem");
            klass.set_accessible_role(gtk::AccessibleRole::Presentation);
        }
    }

    impl ObjectImpl for Gem {
        fn dispose(&self) {
            if let Some(tick) = self.tick.take() {
                tick.remove();
            }
        }
    }

    impl WidgetImpl for Gem {
        fn measure(&self, orientation: gtk::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            let zoom = crate::icon::zoom() as f32;
            match self.look.get() {
                Look::Mark { em } => {
                    let em = em * zoom;
                    if orientation == gtk::Orientation::Horizontal {
                        let width = (0.677 * em).round() as i32;
                        (width, width, -1, -1)
                    } else {
                        // Its bottom 0.032 em below the baseline of the letters beside it
                        let height = (0.686 * em).round() as i32;
                        let baseline = (height as f32 - 0.032 * em).round() as i32;
                        (height, height, baseline, baseline)
                    }
                }
                Look::Halo { size, .. } => {
                    let size = (size * zoom).round() as i32;
                    (size, size, -1, -1)
                }
                Look::Plain => {
                    let size = (self.size.get() * zoom).round() as i32;
                    (size, size, -1, -1)
                }
            }
        }

        fn size_allocate(&self, _width: i32, _height: i32, baseline: i32) {
            self.baseline.set(baseline);
        }

        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let (width, height) = (widget.width() as f32, widget.height() as f32);
            let seconds = (self.now.get() - self.started.get()) as f64 / 1_000_000.0;
            let motion = self.motion.get();
            match self.look.get() {
                Look::Mark { em } => {
                    let em = em * crate::icon::zoom() as f32;
                    // drop-shadow(0 0 0.1075em ...) drop-shadow(0 0 0.258em ...) drop-shadow(0 0 0.4946em ...):
                    // each filter shadows what the one before it drew, so the first is the innermost
                    for (radius, color) in [
                        (0.4946, gdk::RGBA::new(145.0 / 255.0, 72.0 / 255.0, 240.0 / 255.0, 0.5)),
                        (0.258, gdk::RGBA::new(179.0 / 255.0, 125.0 / 255.0, 249.0 / 255.0, 0.65)),
                        (0.1075, gdk::RGBA::new(220.0 / 255.0, 188.0 / 255.0, 1.0, 0.9)),
                    ] {
                        snapshot.push_shadow(&[gsk::Shadow::new(color, 0.0, 0.0, radius * em)]);
                    }
                    // Its bottom 0.032 em below the baseline it was given, whatever height it was allocated
                    let stone_height = width * stone_ratio();
                    let bottom = if self.baseline.get() >= 0 { self.baseline.get() as f32 + 0.032 * em } else { height };
                    snapshot.translate(&graphene::Point::new(0.0, bottom - stone_height));
                    draw_stone(snapshot, width, 0.0, 1.0, None);
                    for _ in 0..3 {
                        snapshot.pop();
                    }
                }
                Look::Halo { stone: stone_size, reach, .. } => {
                    let zoom = crate::icon::zoom() as f32;
                    let (stone_size, reach) = (stone_size * zoom, reach * zoom);
                    // The halo: radial-gradient(closest-side, accent 34%, accent 10% 55%, transparent) at
                    // 0.75, breathing between 0.55 at 94% and 1 at 105% while something happens
                    let (opacity, scale) = match motion {
                        Motion::Breathe(period) => breathe(seconds, period),
                        Motion::Sweep => breathe(seconds, 3.2),
                        Motion::Latch => breathe(seconds, 2.4),
                        _ => (0.75, 1.0),
                    };
                    let accent = widget.color();
                    let side = width.min(height) + 2.0 * reach;
                    let center = graphene::Point::new(width / 2.0, height / 2.0);
                    let radius = side / 2.0 * scale as f32;
                    let tint = |alpha: f32| gdk::RGBA::new(accent.red(), accent.green(), accent.blue(), alpha);
                    snapshot.push_opacity(opacity);
                    snapshot.append_radial_gradient(
                        &graphene::Rect::new(center.x() - radius, center.y() - radius, 2.0 * radius, 2.0 * radius),
                        &center,
                        radius,
                        radius,
                        0.0,
                        1.0,
                        &[
                            gsk::ColorStop::new(0.0, tint(0.34)),
                            gsk::ColorStop::new(0.55, tint(0.10)),
                            gsk::ColorStop::new(1.0, tint(0.0)),
                        ],
                    );
                    snapshot.pop();
                    // The stone, as an <img> with object-fit: contain in a box the stone's size
                    let stone_width = stone_size.min(stone_size / stone_ratio());
                    let stone_height = stone_width * stone_ratio();
                    let origin = graphene::Point::new((width - stone_width) / 2.0, (height - stone_height) / 2.0);
                    snapshot.save();
                    snapshot.translate(&origin);
                    // translateY(-7.35%) of the stem's picture, which is the stone's box, at the middle
                    let lift = if motion == Motion::Latch { 0.0735 * stone_size / stone_height * latch(seconds) as f32 } else { 0.0 };
                    draw_stone(snapshot, stone_width, lift, 1.0, None);
                    if motion == Motion::Sweep {
                        // A band of light 60/116 of the stone tall passing down it, only where the stone is
                        let band = stone_size * 60.0 / 116.0;
                        let progress = cubic_bezier(0.45, 0.05, 0.55, 0.95, (seconds % 2.6) / 2.6) as f32;
                        let top = -band + progress * (stone_size * 176.0 / 116.0 + band);
                        let top = top - (stone_size - stone_height) / 2.0;
                        snapshot.push_mask(gsk::MaskMode::Alpha);
                        draw_stone(snapshot, stone_width, 0.0, 1.0, None);
                        snapshot.pop();
                        let light = gdk::RGBA::new(246.0 / 255.0, 239.0 / 255.0, 1.0, 0.62);
                        let clear = gdk::RGBA::new(246.0 / 255.0, 239.0 / 255.0, 1.0, 0.0);
                        snapshot.append_linear_gradient(
                            &graphene::Rect::new(0.0, top, stone_width, band),
                            &graphene::Point::new(0.0, top),
                            &graphene::Point::new(0.0, top + band),
                            &[gsk::ColorStop::new(0.0, clear), gsk::ColorStop::new(0.5, light), gsk::ColorStop::new(1.0, clear)],
                        );
                        snapshot.pop();
                    }
                    snapshot.restore();
                }
                Look::Plain => {
                    let stone_width = width.min(height / stone_ratio());
                    let stone_height = stone_width * stone_ratio();
                    snapshot.save();
                    snapshot.translate(&graphene::Point::new((width - stone_width) / 2.0, (height - stone_height) / 2.0));
                    let opacity = if motion == Motion::Blink { blink(seconds) } else { 1.0 };
                    draw_stone(snapshot, stone_width, 0.0, opacity as f32, None);
                    snapshot.restore();
                }
            }
        }
    }

    // @keyframes glow { 0%, 100% { opacity: 0.55; scale 0.94 } 50% { opacity: 1; scale 1.05 } }, eased in
    // and out between the two
    fn breathe(seconds: f64, period: f64) -> (f64, f64) {
        let phase = (seconds % period) / period;
        let (from, to, x) = if phase < 0.5 { ((0.55, 0.94), (1.0, 1.05), phase * 2.0) } else { ((1.0, 1.05), (0.55, 0.94), phase * 2.0 - 1.0) };
        let e = ease_in_out(x);
        (from.0 + (to.0 - from.0) * e, from.1 + (to.1 - from.1) * e)
    }

    // @keyframes latch { 50% { translateY(-7.35%) } } over 1.8 s, eased in and out: how far up, 0 to 1
    fn latch(seconds: f64) -> f64 {
        let phase = (seconds % 1.8) / 1.8;
        if phase < 0.5 { ease_in_out(phase * 2.0) } else { 1.0 - ease_in_out(phase * 2.0 - 1.0) }
    }

    // @keyframes blink { 0%, 22%, 78%, 100% { opacity: 1 } 28%, 72% { opacity: 0.3 } }, linear, 1.1 s
    fn blink(seconds: f64) -> f64 {
        let phase = (seconds % 1.1) / 1.1;
        match phase {
            p if p < 0.22 => 1.0,
            p if p < 0.28 => 1.0 - 0.7 * (p - 0.22) / 0.06,
            p if p < 0.72 => 0.3,
            p if p < 0.78 => 0.3 + 0.7 * (p - 0.72) / 0.06,
            _ => 1.0,
        }
    }
}

glib::wrapper! {
    pub struct Gem(ObjectSubclass<imp::Gem>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Gem {
    pub fn new(look: Look) -> Gem {
        let gem: Gem = glib::Object::new();
        gem.imp().look.set(look);
        gem
    }

    /// The small mark, `size` pixels square
    pub fn plain(size: f32) -> Gem {
        let gem = Gem::new(Look::Plain);
        gem.imp().size.set(size);
        gem.set_halign(gtk::Align::Center);
        gem.set_valign(gtk::Align::Center);
        gem
    }

    /// The wordmark's "a", for lettering `em` pixels high
    pub fn mark(em: f32) -> Gem {
        let gem = Gem::new(Look::Mark { em });
        gem.set_valign(gtk::Align::Baseline);
        gem
    }

    /// On its halo: Updates has a 132 px box with a 116 px stone and the halo 30 px past it, Notes 112, 96
    /// and 28
    pub fn halo(size: f32, stone: f32, reach: f32) -> Gem {
        let gem = Gem::new(Look::Halo { size, stone, reach });
        gem.set_halign(gtk::Align::Center);
        gem
    }

    pub fn set_motion(&self, motion: Motion) {
        let imp = self.imp();
        if imp.motion.get() == motion {
            return;
        }
        imp.motion.set(motion);
        if let Some(tick) = imp.tick.take() {
            tick.remove();
        }
        let animations = gtk::Settings::default().map(|s| s.is_gtk_enable_animations()).unwrap_or(true);
        if motion != Motion::Still && animations {
            imp.started.set(-1);
            let id = self.add_tick_callback(|gem, clock| {
                let imp = gem.imp();
                if imp.started.get() < 0 {
                    imp.started.set(clock.frame_time());
                }
                imp.now.set(clock.frame_time());
                gem.queue_draw();
                glib::ControlFlow::Continue
            });
            imp.tick.replace(Some(id));
        } else {
            imp.started.set(0);
            imp.now.set(0);
        }
        self.queue_draw();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eases_like_css() {
        assert!((ease_in_out(0.5) - 0.5).abs() < 1e-4);
        assert!(ease_in_out(0.25) < 0.25);
        assert!((cubic_bezier(0.0, 0.0, 1.0, 1.0, 0.3) - 0.3).abs() < 1e-4);
    }
}
