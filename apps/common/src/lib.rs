//! What the Amethystora apps share: the window and its stylesheets, the theme's colours, the wordmark and
//! the stone, line icons, translations, and running programs. plans/PLAN-rust-apps.md says why the apps
//! are native GTK windows rather than web pages.

pub mod app;
pub mod brand;
pub mod frame;
pub mod gem;
pub mod i18n;
pub mod icon;
pub mod markdown;
pub mod palette;
pub mod process;
pub mod rich;
pub mod store;
pub mod ui;
mod units;

// The toolkit, as every app uses it, so that they all build against the same one
pub use adw;
pub use gtk;
pub use gtk::{gdk, gio, glib, graphene, gsk, pango};
