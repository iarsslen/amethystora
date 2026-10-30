//! Moving cards: short looping clips, drawn by us (branding/cards.mjs), that show how a gesture or a shortcut works,
//! beside the words that say it. A page writes them as pictures, `![Shake to find](media/shake-to-find.webm)`, and
//! pictures next to one another share a row.
//!
//! Only the manual's own clips play, by an exact name under /usr/share/amethystora/manual/media, each with its poster
//! beside it. A clip plays muted and looping only while its card is shown, the window is the active one and
//! animations are on; otherwise the poster shows, as it does for good if the clip cannot be played. A click, or Space
//! or Enter on the card, pauses it and plays it again.

use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;

use amethystora_ui::{adw, gdk, glib, gtk, t, ui};
use adw::prelude::*;

const MEDIA: &str = "/usr/share/amethystora/manual/media";

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
    fn may_play(&self, root: &gtk::Button) -> bool {
        let animations = gtk::Settings::default().map(|s| s.is_gtk_enable_animations()).unwrap_or(false);
        let active = root.root().and_downcast::<gtk::Window>().is_some_and(|window| window.is_active());
        root.is_mapped() && active && animations && !self.held.get() && !self.failed.get()
    }

    fn sync(self: &Rc<Self>) {
        let Some(root) = self.root.upgrade() else { return };
        let play = self.may_play(&root);
        if play {
            let media = self.media.borrow_mut().get_or_insert_with(|| self.open()).clone();
            if !self.failed.get() {
                self.picture.set_paintable(Some(&media));
                media.play();
            }
        } else if let Some(media) = self.media.borrow().as_ref() {
            media.pause();
            // Held by a click, the frame it was on stays; otherwise the poster
            if !self.held.get() || self.failed.get() {
                self.picture.set_paintable(Some(&self.poster));
            }
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
        self.watch.replace(Some(Watch { window: window.downgrade(), active, settings }));
    }

    fn unfollow(&self) {
        if let Some(watch) = self.watch.borrow_mut().take() {
            if let Some(window) = watch.window.upgrade() {
                window.disconnect(watch.active);
            }
            if let Some((settings, id)) = watch.settings {
                settings.disconnect(id);
            }
        }
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
