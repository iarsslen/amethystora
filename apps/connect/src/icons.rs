//! Pictures from a phone: a notification's icon and a caller's photo. They are a stranger's bytes, so they are
//! decoded here, in a bounded way, and written again as PNG; what the notification server is given is that
//! file, never the bytes the phone sent. Only PNG and JPEG are decoded (by their first bytes, not by any name
//! the phone gave), at most 512 KiB of them, scaled down to 256 pixels on a side while they are read, and
//! refused when they claim more than 4096 pixels on a side.

use std::cell::Cell;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use gdk_pixbuf::prelude::*;
use gdk_pixbuf::{Pixbuf, PixbufLoader};

use crate::limits;
use crate::store;

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n";
const JPEG: &[u8] = b"\xff\xd8\xff";
const MOST_PIXELS: i32 = 4096;

fn mime_of(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(PNG) {
        Some("image/png")
    } else if bytes.starts_with(JPEG) {
        Some("image/jpeg")
    } else {
        None
    }
}

/// The picture, scaled to fit `limits::ICON_EDGE`, or `None` when it is not one this program decodes
pub fn decode(bytes: &[u8]) -> Option<Pixbuf> {
    if bytes.is_empty() || bytes.len() as u64 > limits::ICON_BYTES {
        return None;
    }
    let loader = PixbufLoader::with_mime_type(mime_of(bytes)?).ok()?;
    let refused = Rc::new(Cell::new(false));
    let flag = refused.clone();
    loader.connect_size_prepared(move |loader, width, height| {
        if width <= 0 || height <= 0 || width > MOST_PIXELS || height > MOST_PIXELS {
            flag.set(true);
            loader.set_size(1, 1);
            return;
        }
        let edge = limits::ICON_EDGE;
        if width > edge || height > edge {
            let scale = f64::from(edge) / f64::from(width.max(height));
            loader.set_size(((f64::from(width) * scale) as i32).max(1), ((f64::from(height) * scale) as i32).max(1));
        }
    });
    let written = loader.write(bytes).is_ok();
    let closed = loader.close().is_ok();
    if refused.get() || !written || !closed {
        return None;
    }
    loader.pixbuf()
}

/// Decodes `bytes` and writes the result to `path` as PNG (0600); whether it worked
pub fn save_png(bytes: &[u8], path: &Path) -> bool {
    let Some(pixbuf) = decode(bytes) else { return false };
    let Some(folder) = path.parent() else { return false };
    if store::private_dir(folder).is_err() {
        return false;
    }
    let mut temporary = path.as_os_str().to_owned();
    temporary.push(".new");
    let temporary = PathBuf::from(temporary);
    // savev picks the type by the name we give it, never by what the phone said
    let saved = pixbuf.savev(&temporary, "png", &[]).is_ok();
    if saved {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&temporary, std::fs::Permissions::from_mode(0o600));
        saved && std::fs::rename(&temporary, path).is_ok()
    } else {
        let _ = std::fs::remove_file(&temporary);
        false
    }
}

/// Keeps a folder of icons within `limits::ICONS_KEPT` files and `limits::ICONS_BYTES`, the oldest removed first
pub fn trim(folder: &Path) {
    let Ok(read) = std::fs::read_dir(folder) else { return };
    let mut files: Vec<(std::time::SystemTime, u64, PathBuf)> = read
        .filter_map(Result::ok)
        .filter_map(|e| {
            let meta = e.metadata().ok()?;
            meta.is_file().then(|| (meta.modified().unwrap_or(std::time::UNIX_EPOCH), meta.len(), e.path()))
        })
        .collect();
    files.sort();
    let mut total: u64 = files.iter().map(|f| f.1).sum();
    let mut count = files.len();
    for (_, size, path) in files {
        if count <= limits::ICONS_KEPT && total <= limits::ICONS_BYTES {
            break;
        }
        if std::fs::remove_file(&path).is_ok() {
            count -= 1;
            total = total.saturating_sub(size);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 2x2 PNG, drawn here so that the test needs no file
    fn small_png() -> Vec<u8> {
        let pixbuf = Pixbuf::new(gdk_pixbuf::Colorspace::Rgb, true, 8, 2, 2).unwrap();
        pixbuf.fill(0xff0000ff);
        pixbuf.save_to_bufferv("png", &[]).unwrap()
    }

    fn big_png(edge: i32) -> Vec<u8> {
        let pixbuf = Pixbuf::new(gdk_pixbuf::Colorspace::Rgb, true, 8, edge, edge).unwrap();
        pixbuf.fill(0x00ff00ff);
        pixbuf.save_to_bufferv("png", &[]).unwrap()
    }

    #[test]
    fn a_small_picture_is_kept_and_a_large_one_scaled() {
        let p = decode(&small_png()).unwrap();
        assert_eq!((p.width(), p.height()), (2, 2));
        let p = decode(&big_png(1024)).unwrap();
        assert_eq!((p.width(), p.height()), (256, 256));
    }

    #[test]
    fn what_is_not_a_picture_is_refused() {
        assert!(decode(b"").is_none());
        assert!(decode(b"GIF89a....").is_none(), "only PNG and JPEG");
        assert!(decode(b"<svg xmlns='http://www.w3.org/2000/svg'/>").is_none());
        assert!(decode(&[PNG, &[0u8; 20]].concat()).is_none(), "a PNG header and nothing else");
        let mut cut = small_png();
        cut.truncate(cut.len() / 2);
        assert!(decode(&cut).is_none());
        assert!(decode(&vec![0xff; limits::ICON_BYTES as usize + 1]).is_none());
    }

    #[test]
    fn a_picture_claiming_too_much_is_refused() {
        // A 5000 x 5000 picture of one colour compresses to a few kilobytes
        let png = big_png(5000);
        assert!(png.len() as u64 <= limits::ICON_BYTES, "{} bytes", png.len());
        assert!(decode(&png).is_none());
    }

    #[test]
    fn saving_writes_a_png_of_our_own() {
        let dir = std::env::temp_dir().join(format!("amethystora-connect-icons-{}", std::process::id()));
        let path = dir.join("a").join("icon.png");
        assert!(save_png(&small_png(), &path));
        let written = std::fs::read(&path).unwrap();
        assert!(written.starts_with(PNG));
        assert!(!save_png(b"junk", &dir.join("b.png")));
        assert!(!dir.join("b.png").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_folder_is_trimmed_oldest_first() {
        let dir = std::env::temp_dir().join(format!("amethystora-connect-trim-{}", std::process::id()));
        store::private_dir(&dir).unwrap();
        for i in 0..limits::ICONS_KEPT + 10 {
            std::fs::write(dir.join(format!("{i:04}")), b"x").unwrap();
            let when = std::time::UNIX_EPOCH + std::time::Duration::from_secs(1_700_000_000 + i as u64);
            std::fs::File::options().write(true).open(dir.join(format!("{i:04}"))).unwrap().set_modified(when).unwrap();
        }
        trim(&dir);
        let left = std::fs::read_dir(&dir).unwrap().count();
        assert_eq!(left, limits::ICONS_KEPT);
        assert!(!dir.join("0000").exists() && dir.join(format!("{:04}", limits::ICONS_KEPT + 9)).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
