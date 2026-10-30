//! Moving cards: short looping clips, drawn by us (branding/cards.mjs), that show how a gesture or a shortcut works,
//! beside the words that say it. A page writes them as pictures, `![Shake to find](media/shake-to-find.webm)`, and
//! pictures next to one another share a row.
//!
//! Only the manual's own clips play, by an exact name under /usr/share/amethystora/manual/media, each with its poster
//! beside it. A clip plays muted and looping only while its card is shown, the window is the active one and
//! animations are on, and only while it is on the screen, up to MOST_OPEN at once: each clip is a pipeline of its own,
//! and a page of them playing out of sight ran the program out of file descriptors. Otherwise the poster shows, as it does for good if the clip cannot be played. A click, or Space
//! or Enter on the card, pauses it and plays it again.

use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;

use amethystora_ui::{adw, gdk, glib, gtk, t, ui};
use adw::prelude::*;

const MEDIA: &str = "/usr/share/amethystora/manual/media";
/// Clips open at once. A pipeline takes some 60 descriptors, of the 1024 a program has by default
const MOST_OPEN: usize = 8;

thread_local! {
    static OPEN: Cell<usize> = const { Cell::new(0) };
}

/// The clip a page names: `media/<name>.webm`, lower case letters, digits and dashes, and nothing else
pub fn card_name(href: &str) -> Option<&str> {
    let name = href.strip_prefix("media/")?.strip_suffix(".webm")?;
    let fits = !name.is_empty() && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-');
    fits.then_some(name)
}

/// What a card follows while it is shown: its window's focus and the session's animations
struct Watch {
    window: glib::WeakRef<gtk::Window>,
    active: glib::SignalHandlerId,
    settings: Option<(gtk::Settings, glib::SignalHandlerId)>,
    scrolled: Option<(gtk::Adjustment, glib::SignalHandlerId, glib::SignalHandlerId)>,
}

/// One card. Its widget holds it, through its handlers; it holds no reference back, so both go together.
struct Card {
    root: glib::WeakRef<gtk::Button>,
    picture: gtk::Picture,
    clip: PathBuf,
    poster: gdk::Texture,
    caption: String,
    media: RefCell<Option<gtk::MediaFile>>,
    /// Paused by a click, which only another click undoes
    held: Cell<bool>,
    /// The clip could not be played: the poster stays
    failed: Cell<bool>,
    watch: RefCell<Option<Watch>>,
}

impl Card {
    /// Whether any of the card is inside the page's visible part
    fn on_screen(root: &gtk::Button) -> bool {
        let Some(page) = root.ancestor(gtk::ScrolledWindow::static_type()) else { return true };
        root.compute_bounds(&page).is_some_and(|box_| box_.y() + box_.height() > 0.0 && box_.y() < page.height() as f32)
    }

    fn release(&self) {
        if self.media.borrow_mut().take().is_some() {
            OPEN.with(|open| open.set(open.get() - 1));
        }
    }

    fn may_play(&self, root: &gtk::Button) -> bool {
        let animations = gtk::Settings::default().map(|s| s.is_gtk_enable_animations()).unwrap_or(false);
        let active = root.root().and_downcast::<gtk::Window>().is_some_and(|window| window.is_active());
        let room = self.media.borrow().is_some() || OPEN.with(Cell::get) < MOST_OPEN;
        root.is_mapped() && active && animations && !self.held.get() && !self.failed.get() && room && Self::on_screen(root)
    }

    fn sync(self: &Rc<Self>) {
        let Some(root) = self.root.upgrade() else { return };
        let play = self.may_play(&root);
        if play {
            let media = self.media.borrow_mut().get_or_insert_with(|| {
                OPEN.with(|open| open.set(open.get() + 1));
                self.open()
            }).clone();
            if !self.failed.get() {
                self.picture.set_paintable(Some(&media));
                media.play();
            }
        } else if self.held.get() && !self.failed.get() {
            // Held by a click, the frame it was on stays
            if let Some(media) = self.media.borrow().as_ref() {
                media.pause();
            }
        } else {
            self.picture.set_paintable(Some(&self.poster));
            self.release();
        }
        let label = if play && !self.failed.get() {
            t!("{caption}, playing", caption = &self.caption)
        } else {
            t!("{caption}, paused", caption = &self.caption)
        };
        root.update_property(&[gtk::accessible::Property::Label(&label)]);
    }

    fn open(self: &Rc<Self>) -> gtk::MediaFile {
        let media = gtk::MediaFile::for_filename(&self.clip);
        media.set_loop(true);
        media.set_muted(true);
        let weak = Rc::downgrade(self);
        media.connect_error_notify(move |media| {
            if media.error().is_none() {
                return;
            }
            if let Some(card) = weak.upgrade() {
                card.failed.set(true);
                card.picture.set_paintable(Some(&card.poster));
                card.sync();
            }
        });
        media
    }

    fn follow(self: &Rc<Self>, root: &gtk::Button) {
        if self.watch.borrow().is_some() {
            return;
        }
        let Some(window) = root.root().and_downcast::<gtk::Window>() else { return };
        let weak = Rc::downgrade(self);
        let active = window.connect_is_active_notify(move |_| {
            if let Some(card) = weak.upgrade() {
                card.sync();
            }
        });
        let settings = gtk::Settings::default().map(|settings| {
            let weak = Rc::downgrade(self);
            let id = settings.connect_gtk_enable_animations_notify(move |_| {
                if let Some(card) = weak.upgrade() {
                    card.sync();
                }
            });
            (settings, id)
        });
        // Scrolled, or the page laid out, a card may have come on or gone off the screen
        let scrolled = root.ancestor(gtk::ScrolledWindow::static_type()).and_downcast::<gtk::ScrolledWindow>().map(|page| {
            let adjustment = page.vadjustment();
            let weak = Rc::downgrade(self);
            let moved = adjustment.connect_value_changed(move |_| {
                if let Some(card) = weak.upgrade() {
                    card.sync();
                }
            });
            let weak = Rc::downgrade(self);
            let laid_out = adjustment.connect_changed(move |_| {
                if let Some(card) = weak.upgrade() {
                    card.sync();
                }
            });
            (adjustment, moved, laid_out)
        });
        self.watch.replace(Some(Watch { window: window.downgrade(), active, settings, scrolled }));
    }

    fn unfollow(&self) {
        if let Some(watch) = self.watch.borrow_mut().take() {
            if let Some(window) = watch.window.upgrade() {
                window.disconnect(watch.active);
            }
            if let Some((settings, id)) = watch.settings {
                settings.disconnect(id);
            }
            if let Some((adjustment, moved, laid_out)) = watch.scrolled {
                adjustment.disconnect(moved);
                adjustment.disconnect(laid_out);
            }
        }
    }
}

impl Drop for Card {
    fn drop(&mut self) {
        self.release();
    }
}

/// The card for a picture a page names, or None for anything that is not one of the manual's clips (its words show)
pub fn card(href: &str, caption: &str) -> Option<gtk::Widget> {
    let name = card_name(href)?;
    let clip = Path::new(MEDIA).join(format!("{name}.webm"));
    if !clip.is_file() {
        return None;
    }
    let poster = gdk::Texture::from_filename(Path::new(MEDIA).join(format!("{name}.png"))).ok()?;
    let picture = gtk::Picture::builder().paintable(&poster).content_fit(gtk::ContentFit::Cover).can_shrink(true).build();
    picture.set_size_request(150, 112);
    picture.add_css_class("mcard-art");
    // A button, so that a screen reader's click, Space and Enter all press it, as a pointer does
    let inner = ui::vbox(0, &[]);
    let root = gtk::Button::builder().child(&inner).css_classes(["mcard"]).build();
    root.set_overflow(gtk::Overflow::Hidden);
    root.set_size_request(150, 158);
    root.set_halign(gtk::Align::Start);
    // The poster is twice the size it is shown at: the card is as wide as the board has it, whatever the picture
    inner.append(&ui::limit(&picture, 150));
    let words = ui::label(caption, &["mcard-cap"]);
    words.set_xalign(0.0);
    inner.append(&words);
    let card = Rc::new(Card {
        root: root.downgrade(),
        picture,
        clip,
        poster,
        caption: caption.to_string(),
        media: RefCell::new(None),
        held: Cell::new(false),
        failed: Cell::new(false),
        watch: RefCell::new(None),
    });

    let pressed = card.clone();
    root.connect_clicked(move |_| {
        pressed.held.set(!pressed.held.get());
        pressed.sync();
    });

    // Shown: it follows its window and the animations setting; hidden: it lets go of them, and its clip stops
    let shown = card.clone();
    root.connect_map(move |root| {
        shown.follow(root);
        shown.sync();
        // Only laid out by the next frame can it tell whether it is on the screen, and a window already active says nothing more
        let card = shown.clone();
        root.add_tick_callback(move |_, _| {
            card.sync();
            glib::ControlFlow::Break
        });
    });
    let hidden = card.clone();
    root.connect_unmap(move |_| {
        hidden.unfollow();
        hidden.sync();
    });
    card.sync();
    Some(root.upcast())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_manuals_own_clips() {
        assert_eq!(card_name("media/shake-to-find.webm"), Some("shake-to-find"));
        assert_eq!(card_name("media/../x.webm"), None);
        assert_eq!(card_name("/usr/share/amethystora/manual/media/a.webm"), None);
        assert_eq!(card_name("media/A.webm"), None);
        assert_eq!(card_name("media/a.webm.png"), None);
        assert_eq!(card_name("media/.webm"), None);
        assert_eq!(card_name("https://example.com/media/a.webm"), None);
        assert_eq!(card_name("media/sub/a.webm"), None);
    }
}
