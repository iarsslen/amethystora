//! Glows: the radial gradients the pages light things with (the stone's halo, a card lit from its corner),
//! drawn from a texture worked out here rather than by GTK's own radial gradient.
//!
//! GTK draws a radial gradient, CSS's radial-gradient() as much as a snapshot's, with a shader of its own, and
//! where the Vulkan device is the CPU (lavapipe: a virtual machine, a computer without a graphics driver)
//! building that shader keeps some 60 MB, and in the apps up to 110 MB, of the window's memory for as long as
//! it is open: measured in the VM lab on 2026-10-16, Security, Updates and Notes were the only windows that
//! drew one, and the only ones that big. Every window has built the texture shader already. The texture holds
//! the colours GTK drew: each pixel of the screen sampled at its centre, the alphas of the stops interpolated
//! as GTK does, premultiplied, and rounded once; in that lab, screenshots of the windows before and after
//! were the same but for a few pixels 1 apart in 255.
//!
//! Keep radial-gradient() out of the stylesheets and append_radial_gradient() out of the code: a glow is a
//! [`Gradient`] drawn by [`append`], or a card's by [`behind`].

use std::cell::RefCell;

use gtk::gdk;
use gtk::glib;
use gtk::graphene;
use gtk::prelude::*;
use gtk::subclass::prelude::*;

/// A radial gradient of one colour, its alpha changing along the ray, as CSS's radial-gradient() and
/// gsk::RadialGradientNode draw one: the ending shape an ellipse, the colour of the first stop before it and of
/// the last after it
#[derive(Debug)]
pub struct Gradient {
    /// The centre, in fractions of the box from its top left
    pub center: (f64, f64),
    /// The ending ellipse's radii, in fractions of the box's width and height
    pub radii: (f64, f64),
    /// Each stop: where along the ray it is (0 at the centre, 1 on the ending ellipse) and the alpha there, of
    /// the colour the glow is drawn in
    pub stops: &'static [(f64, f64)],
}

/// Where the gradient's box lies on a texture, in pixels: the texture `width` by `height`, the box from
/// `left`, `top` and `across` by `down`. Nothing is drawn outside the box.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Place {
    width: i32,
    height: i32,
    left: f64,
    top: f64,
    across: f64,
    down: f64,
}

impl Place {
    /// A texture that is the box
    fn whole(width: i32, height: i32) -> Place {
        Place { width, height, left: 0.0, top: 0.0, across: width as f64, down: height as f64 }
    }
}

impl Gradient {
    /// The alpha at `t` along the ray
    fn alpha(&self, t: f64) -> f64 {
        let (Some(first), Some(last)) = (self.stops.first(), self.stops.last()) else { return 0.0 };
        if t <= first.0 {
            return first.1;
        }
        for pair in self.stops.windows(2) {
            let ((from, a), (to, b)) = (pair[0], pair[1]);
            if t <= to {
                return if to > from { a + (b - a) * (t - from) / (to - from) } else { b };
            }
        }
        last.1
    }

    /// The texture's pixels in `color`, premultiplied RGBA, the centre mirrored when `mirrored`
    fn pixels(&self, place: &Place, mirrored: bool, color: &gdk::RGBA) -> Vec<u8> {
        let (width, height) = (place.width.max(0) as usize, place.height.max(0) as usize);
        let center_x = if mirrored { 1.0 - self.center.0 } else { self.center.0 };
        let (red, green, blue, opacity) = (color.red() as f64, color.green() as f64, color.blue() as f64, color.alpha() as f64);
        let byte = |value: f64| (value * 255.0).round().clamp(0.0, 255.0) as u8;
        let mut data = vec![0u8; width * height * 4];
        for y in 0..height {
            let v = (y as f64 + 0.5 - place.top) / place.down;
            if !(0.0..1.0).contains(&v) {
                continue;
            }
            let dy = (v - self.center.1) / self.radii.1;
            for x in 0..width {
                let u = (x as f64 + 0.5 - place.left) / place.across;
                if !(0.0..1.0).contains(&u) {
                    continue;
                }
                let dx = (u - center_x) / self.radii.0;
                let alpha = self.alpha((dx * dx + dy * dy).sqrt()) * opacity;
                let at = (y * width + x) * 4;
                data[at] = byte(red * alpha);
                data[at + 1] = byte(green * alpha);
                data[at + 2] = byte(blue * alpha);
                data[at + 3] = byte(alpha);
            }
        }
        data
    }
}

/// What a texture was made for: the gradient, the place in 1/256 pixels, whether mirrored, and the colour
type Key = (usize, [i64; 6], bool, [u16; 4]);

thread_local! {
    /// The last few textures, most recently drawn last: a page that is built again draws the same ones
    static MADE: RefCell<Vec<(Key, gdk::Texture)>> = const { RefCell::new(Vec::new()) };
}

/// How many bytes of textures are kept, besides the last one made: a window resized makes one at every size
const KEPT_BYTES: usize = 8 << 20;

/// The glow at `place` in `color`, made once and kept while it is drawn
fn texture(gradient: &'static Gradient, place: Place, mirrored: bool, color: &gdk::RGBA) -> gdk::Texture {
    let place = Place { width: place.width.max(1), height: place.height.max(1), ..place };
    let fine = |value: f64| (value * 256.0).round() as i64;
    let channel = |value: f32| (value.clamp(0.0, 1.0) * 65535.0).round() as u16;
    let key: Key = (
        gradient as *const Gradient as usize,
        [place.width as i64, place.height as i64, fine(place.left), fine(place.top), fine(place.across), fine(place.down)],
        mirrored,
        [channel(color.red()), channel(color.green()), channel(color.blue()), channel(color.alpha())],
    );
    MADE.with(|made| {
        let mut made = made.borrow_mut();
        if let Some(at) = made.iter().position(|(k, _)| *k == key) {
            let entry = made.remove(at);
            let texture = entry.1.clone();
            made.push(entry);
            return texture;
        }
        let data = gradient.pixels(&place, mirrored, color);
        let texture: gdk::Texture = gdk::MemoryTexture::new(
            place.width,
            place.height,
            gdk::MemoryFormat::R8g8b8a8Premultiplied,
            &glib::Bytes::from_owned(data),
            place.width as usize * 4,
        )
        .upcast();
        made.push((key, texture.clone()));
        let bytes = |texture: &gdk::Texture| texture.width() as usize * texture.height() as usize * 4;
        while made.len() > 1 && made.iter().map(|(_, texture)| bytes(texture)).sum::<usize>() > KEPT_BYTES {
            made.remove(0);
        }
        texture
    })
}

/// How many pixels a unit of `widget` is drawn with on its screen (1.25 at a fractional scale of 125%)
fn scale(widget: &impl IsA<gtk::Widget>) -> f64 {
    widget
        .native()
        .and_then(|native| native.surface())
        .map(|surface| surface.scale())
        .unwrap_or_else(|| widget.scale_factor() as f64)
}

/// `gradient` across `bounds` of `widget`, as GTK drew a gradient node there: the texture covers the whole
/// pixels `bounds` touches, and each is sampled at its centre
pub fn append(snapshot: &gtk::Snapshot, widget: &impl IsA<gtk::Widget>, gradient: &'static Gradient, bounds: &graphene::Rect, mirrored: bool, color: &gdk::RGBA) {
    let scale = scale(widget);
    let (left, top) = (bounds.x() as f64 * scale, bounds.y() as f64 * scale);
    let (across, down) = (bounds.width() as f64 * scale, bounds.height() as f64 * scale);
    if across <= 0.0 || down <= 0.0 {
        return;
    }
    let (x0, y0) = (left.floor(), top.floor());
    let (x1, y1) = ((left + across).ceil(), (top + down).ceil());
    let place = Place { width: (x1 - x0) as i32, height: (y1 - y0) as i32, left: left - x0, top: top - y0, across, down };
    let texture = texture(gradient, place, mirrored, color);
    let area = graphene::Rect::new((x0 / scale) as f32, (y0 / scale) as f32, ((x1 - x0) / scale) as f32, ((y1 - y0) / scale) as f32);
    snapshot.append_texture(&texture, &area);
}

/// `gradient` made `width` by `height` units and drawn stretched across `bounds`: for a glow that grows and
/// shrinks as it breathes, which is made once rather than at every frame
pub fn append_scaled(
    snapshot: &gtk::Snapshot,
    widget: &impl IsA<gtk::Widget>,
    gradient: &'static Gradient,
    (width, height): (f32, f32),
    bounds: &graphene::Rect,
    color: &gdk::RGBA,
) {
    let scale = scale(widget);
    let pixels = |length: f32| (length as f64 * scale).round().max(1.0) as i32;
    let texture = texture(gradient, Place::whole(pixels(width), pixels(height)), false, color);
    snapshot.append_texture(&texture, bounds);
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Glow {
        pub gradient: std::cell::Cell<Option<&'static Gradient>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Glow {
        const NAME: &'static str = "AmethystoraGlow";
        type Type = super::Glow;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("glow");
            klass.set_accessible_role(gtk::AccessibleRole::Presentation);
        }
    }

    impl ObjectImpl for Glow {}

    impl WidgetImpl for Glow {
        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let Some(gradient) = self.gradient.get() else { return };
            let bounds = graphene::Rect::new(0.0, 0.0, widget.width() as f32, widget.height() as f32);
            let mirrored = widget.direction() == gtk::TextDirection::Rtl;
            append(snapshot, &*widget, gradient, &bounds, mirrored, &widget.color());
        }
    }
}

glib::wrapper! {
    /// A glow filling the widget's content box, in its CSS colour, its centre mirrored in a right-to-left
    /// window as :dir(rtl) had it: what a card's background-image was
    pub struct Glow(ObjectSubclass<imp::Glow>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Glow {
    pub fn new(gradient: &'static Gradient) -> Glow {
        let glow: Glow = glib::Object::new();
        glow.imp().gradient.set(Some(gradient));
        glow
    }
}

mod layers {
    use super::*;

    #[derive(Default)]
    pub struct Layers;

    #[glib::object_subclass]
    impl ObjectSubclass for Layers {
        const NAME: &'static str = "AmethystoraLayers";
        type Type = super::Layers;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            // Every child the whole size, measured as the largest of them, drawn first to last
            klass.set_layout_manager_type::<gtk::BinLayout>();
            klass.set_css_name("layers");
        }
    }

    impl ObjectImpl for Layers {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for Layers {}
}

glib::wrapper! {
    /// Widgets one over the other, each the size of the largest
    pub struct Layers(ObjectSubclass<layers::Layers>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

/// `card` with `gradient` on its background, as `background-image: radial-gradient(...)` painted it: under the
/// card's border, over its background colour, across its padding box and cut at its rounded corners. The
/// widget returned goes where the card would. Under the card it puts a [`Glow`] with the CSS class `class`,
/// which takes over the card's background: the stylesheet gives it the card's background colour, shadow and
/// border-radius, the card's border width as its padding (so that its content box, where the glow is, is
/// the card's padding box), and the glow's colour as its `color`; the card's own background is then
/// transparent and its shadow none.
pub fn behind(card: &impl IsA<gtk::Widget>, gradient: &'static Gradient, class: &str) -> gtk::Widget {
    let glow = Glow::new(gradient);
    glow.add_css_class(class);
    // Its padding box is its border box, with the card's rounded corners
    glow.set_overflow(gtk::Overflow::Hidden);
    let layers: Layers = glib::Object::new();
    glow.set_parent(&layers);
    card.set_parent(&layers);
    layers.upcast()
}

#[cfg(test)]
mod tests {
    use super::*;

    static CORNER: Gradient = Gradient { center: (0.0, 0.0), radii: (1.1, 1.7), stops: &[(0.0, 0.28), (0.42, 0.07), (0.72, 0.0)] };
    static HALO: Gradient = Gradient { center: (0.5, 0.5), radii: (0.5, 0.5), stops: &[(0.0, 1.0), (1.0, 0.0)] };

    fn accent() -> gdk::RGBA {
        gdk::RGBA::new(145.0 / 255.0, 72.0 / 255.0, 240.0 / 255.0, 1.0)
    }

    #[test]
    fn alpha_follows_the_stops() {
        assert!((CORNER.alpha(0.0) - 0.28).abs() < 1e-9);
        assert!((CORNER.alpha(0.21) - 0.175).abs() < 1e-9);
        assert!((CORNER.alpha(0.42) - 0.07).abs() < 1e-9);
        assert!((CORNER.alpha(0.57) - 0.035).abs() < 1e-9);
        assert_eq!(CORNER.alpha(0.9), 0.0);
        assert_eq!(CORNER.alpha(-1.0), 0.28);
    }

    #[test]
    fn pixels_are_premultiplied_and_sampled_at_their_centres() {
        let data = CORNER.pixels(&Place::whole(400, 160), false, &accent());
        // The top left pixel's centre is 0.00216 along the ray: the accent at 0.2789, premultiplied
        assert_eq!(&data[0..4], &[40, 20, 67, 71]);
        // Past 72% of the ray, nothing
        let far = (159 * 400 + 399) * 4;
        assert_eq!(&data[far..far + 4], &[0, 0, 0, 0]);
        // Mirrored, the top right is what the top left was
        let mirrored = CORNER.pixels(&Place::whole(400, 160), true, &accent());
        assert_eq!(&mirrored[399 * 4..400 * 4], &data[0..4]);
    }

    #[test]
    fn a_box_off_the_pixels_is_sampled_where_it_lies() {
        // A box 3 pixels wide from half a pixel in covers four pixels: the first one's centre is on the box's
        // edge, where the ray is at 1; the middle two are a third of the way out; the last is past the box
        let place = Place { width: 4, height: 1, left: 0.5, top: 0.0, across: 3.0, down: 1.0 };
        let data = HALO.pixels(&place, false, &gdk::RGBA::new(1.0, 1.0, 1.0, 1.0));
        let alphas: Vec<u8> = data.chunks(4).map(|pixel| pixel[3]).collect();
        assert_eq!(alphas, [0, 170, 170, 0]);
    }
}
