//! Share (spec-plugins.md 5): files, links and text, in both directions. Here are the parts that decide where a
//! file from a phone goes and under what name, and what a share packet is; the transfers are the service's.
//!
//! A file from a phone is written to a temporary file in its folder (0600, never executable), and put under
//! its name only when it is whole, by a hard link that fails if the name is taken: so a file is never
//! overwritten, whatever else writes into the folder at the same moment, and a name is never a path.

use std::fs::{File, OpenOptions};
use std::io;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use gio::prelude::*;

use crate::packet::Packet;
use crate::store;
use crate::text;

/// What a share packet holds
#[derive(Debug, PartialEq, Eq)]
pub enum Shared {
    /// A file: the name the phone gave it (not yet safe), its modification time in milliseconds
    File { name: String, modified: Option<i64>, batch: Option<Batch> },
    Link(String),
    Text(String),
    /// Nothing this program shows
    Nothing,
}

/// The batch a file belongs to, as the phone says: used for presentation only, never to size anything
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Batch {
    pub files: u32,
    pub bytes: u64,
}

pub fn batch_of(p: &Packet) -> Option<Batch> {
    let files = p.int("numberOfFiles").filter(|n| (1..=100_000).contains(n))? as u32;
    let bytes = p.int("totalPayloadSize").filter(|n| *n >= 0).unwrap_or(0) as u64;
    Some(Batch { files, bytes })
}

pub fn parse(p: &Packet) -> Shared {
    if let Some(name) = p.str("filename") {
        return Shared::File { name: name.to_string(), modified: p.int("lastModified"), batch: batch_of(p) };
    }
    if let Some(url) = p.str("url") {
        return Shared::Link(url.to_string());
    }
    match p.str("text") {
        // One web address and nothing else is a link all the same
        Some(text) if is_one_web_address(text) => Shared::Link(text.trim().to_string()),
        Some(text) => Shared::Text(text.to_string()),
        None => Shared::Nothing,
    }
}

fn is_one_web_address(text: &str) -> bool {
    let t = text.trim();
    (t.starts_with("http://") || t.starts_with("https://")) && !t.contains(char::is_whitespace) && t.len() > 8
}

/// Whether a link may be opened by a click: web addresses only
pub fn openable(link: &str) -> bool {
    let lower = link.to_ascii_lowercase();
    (lower.starts_with("http://") || lower.starts_with("https://")) && !link.contains(char::is_control)
}

/// Where files from phones go: the Download folder, in a folder of its own for phones. If the account has none,
/// or it is the home folder itself, `Downloads` in the home.
pub fn receive_root(download: Option<PathBuf>, home: &Path) -> PathBuf {
    let base = match download {
        Some(d) if d != home => d,
        _ => home.join("Downloads"),
    };
    base.join("Phone")
}

/// A phone's own folder under the root; created 0700
pub fn device_folder(root: &Path, device_name: &str) -> io::Result<PathBuf> {
    let folder = root.join(text::folder_name(device_name));
    if let Some(parent) = folder.parent() {
        std::fs::create_dir_all(parent)?;
    }
    store::private_dir(&folder)?;
    Ok(folder)
}

/// The free space of the file system a folder is on
pub fn free_space(folder: &Path) -> Option<u64> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let path = CString::new(folder.as_os_str().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: `path` is a valid C string and `stat` a zeroed structure statvfs fills in
    (unsafe { libc::statvfs(path.as_ptr(), &mut stat) } == 0).then(|| stat.f_bavail as u64 * stat.f_frsize as u64)
}

/// A temporary file in `folder`, new, 0600, with a name nobody else has
pub fn create_part(folder: &Path) -> io::Result<(File, PathBuf)> {
    for _ in 0..16 {
        let mut random = [0u8; 8];
        getrandom::fill(&mut random).map_err(|e| io::Error::other(e.to_string()))?;
        let name = format!(".part-{}", random.iter().map(|b| format!("{b:02x}")).collect::<String>());
        let path = folder.join(name);
        match OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path) {
            Ok(file) => return Ok((file, path)),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::other("no temporary name was free"))
}

/// Puts the finished temporary file under `name` in `folder`: that name, or `name (1)`, `name (2)` with the
/// number before the extension. The name is made safe here; the temporary file is removed. Returns the path.
pub fn publish(part: &Path, folder: &Path, name: &str) -> io::Result<PathBuf> {
    let name = text::file_name(name);
    for n in 0..10_000u32 {
        let target = folder.join(text::numbered(&name, n));
        match std::fs::hard_link(part, &target) {
            Ok(()) => {
                let _ = std::fs::remove_file(part);
                // The folder is the file's parent and nothing else, whatever the name held
                return if text::directly_in(folder, &target) {
                    Ok(target)
                } else {
                    let _ = std::fs::remove_file(&target);
                    Err(io::Error::other("the name leaves the folder"))
                };
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::other("no free name"))
}

/// The phone's idea of when a file was made, if it is a plausible time: after 1990, not more than a day ahead
pub fn plausible_time(millis: i64, now: SystemTime) -> Option<SystemTime> {
    let when = UNIX_EPOCH.checked_add(Duration::from_millis(u64::try_from(millis).ok()?))?;
    let floor = UNIX_EPOCH + Duration::from_secs(631_152_000);
    (when > floor && when < now + Duration::from_secs(86_400)).then_some(when)
}

pub fn set_modified(path: &Path, when: SystemTime) {
    if let Ok(file) = OpenOptions::new().write(true).open(path) {
        let _ = file.set_modified(when);
    }
}

/// The `kdeconnect.share.request` body for a file we send: the base name, not opened on the phone
pub fn file_body(name: &str, modified_ms: Option<i64>, batch: Option<Batch>) -> serde_json::Value {
    let mut body = serde_json::json!({ "filename": name, "open": false });
    if let (Some(map), Some(ms)) = (body.as_object_mut(), modified_ms) {
        map.insert("lastModified".into(), ms.into());
    }
    if let (Some(map), Some(b)) = (body.as_object_mut(), batch) {
        map.insert("numberOfFiles".into(), b.files.into());
        map.insert("totalPayloadSize".into(), b.bytes.into());
    }
    body
}

/// Whether a received file may be opened by a button: pictures, plain text, PDF, sound and video, by the type its
/// name says. What starts a program or installs something (a launcher, a package, a script, a Flatpak reference,
/// a page with scripts) is shown in the folder and opened only by the person's own choice there.
pub fn safe_to_open(path: &Path) -> bool {
    let Some(name) = path.file_name() else { return false };
    let (content_type, _) = gio::content_type_guess(Some(Path::new(name)), None::<&[u8]>);
    let Some(mime) = gio::content_type_get_mime_type(&content_type) else { return false };
    let mime = mime.as_str();
    let family = |prefix: &str| mime.starts_with(prefix);
    (family("image/") && mime != "image/svg+xml") || family("audio/") || family("video/") || mime == "text/plain" || mime == "application/pdf"
}

/// A `file:` address as a local regular file the program may send: not a folder, not a link to one, not another
/// host's. The path and its size.
pub fn sendable(uri: &str) -> Result<(PathBuf, u64), String> {
    let lower = uri.to_ascii_lowercase();
    if !(lower.starts_with("file:///") || lower.starts_with("file://localhost/")) {
        return Err(text::tr("Only files on this computer can be sent."));
    }
    let file = gio::File::for_uri(uri);
    let path = file.path().ok_or_else(|| text::tr("Only files on this computer can be sent."))?;
    let meta = std::fs::metadata(&path).map_err(|_| text::tr("A file cannot be read."))?;
    if !meta.is_file() {
        return Err(text::tr("A folder cannot be sent."));
    }
    File::open(&path).map_err(|_| text::tr("A file cannot be read."))?;
    Ok((path, meta.len()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn packet(v: serde_json::Value) -> Packet {
        Packet::parse(v.to_string().as_bytes()).unwrap()
    }

    fn folder(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("amethystora-connect-share-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        store::private_dir(&dir).unwrap();
        dir
    }

    #[test]
    fn what_a_share_is() {
        assert_eq!(
            parse(&packet(json!({ "type": "kdeconnect.share.request", "body": { "filename": "holiday.jpg", "lastModified": 1790000000000i64, "numberOfFiles": 3, "totalPayloadSize": 99 }, "payloadSize": 5, "payloadTransferInfo": { "port": 1739 } }))),
            Shared::File { name: "holiday.jpg".into(), modified: Some(1790000000000), batch: Some(Batch { files: 3, bytes: 99 }) }
        );
        assert_eq!(parse(&packet(json!({ "type": "t", "body": { "url": "https://example.org/page" } }))), Shared::Link("https://example.org/page".into()));
        assert_eq!(parse(&packet(json!({ "type": "t", "body": { "text": "Meet at the north gate at 9." } }))), Shared::Text("Meet at the north gate at 9.".into()));
        assert_eq!(parse(&packet(json!({ "type": "t", "body": { "text": " https://example.org/x " } }))), Shared::Link("https://example.org/x".into()));
        assert_eq!(parse(&packet(json!({ "type": "t", "body": { "text": "see https://example.org/x" } }))), Shared::Text("see https://example.org/x".into()));
        assert_eq!(parse(&packet(json!({ "type": "t", "body": { "text": 5 } }))), Shared::Nothing);
        // A file wins over text
        assert!(matches!(parse(&packet(json!({ "type": "t", "body": { "filename": "a", "text": "b" } }))), Shared::File { .. }));
        // The empty filename is still a file (and gets a name of ours)
        assert!(matches!(parse(&packet(json!({ "type": "t", "body": { "filename": "" } }))), Shared::File { .. }));
    }

    #[test]
    fn only_web_links_are_opened() {
        assert!(openable("https://example.org/"));
        assert!(openable("HTTP://example.org/"));
        assert!(!openable("file:///etc/passwd"));
        assert!(!openable("javascript:alert(1)"));
        assert!(!openable("smb://host/share"));
        assert!(!openable("https://example.org/\u{0}"));
    }

    #[test]
    fn the_receive_folder() {
        let home = Path::new("/home/ada");
        assert_eq!(receive_root(Some("/home/ada/Downloads".into()), home), Path::new("/home/ada/Downloads/Phone"));
        assert_eq!(receive_root(Some("/home/ada/Téléchargements".into()), home), Path::new("/home/ada/Téléchargements/Phone"));
        assert_eq!(receive_root(Some("/home/ada".into()), home), Path::new("/home/ada/Downloads/Phone"));
        assert_eq!(receive_root(None, home), Path::new("/home/ada/Downloads/Phone"));
    }

    #[test]
    fn a_file_is_put_under_a_safe_name_and_never_over_another() {
        let root = folder("publish");
        let folder = device_folder(&root, "Sam phone").unwrap();
        assert_eq!(folder, root.join("Sam phone"));
        let mut names = Vec::new();
        for i in 0..3 {
            let (mut file, part) = create_part(&folder).unwrap();
            use std::io::Write;
            write!(file, "content {i}").unwrap();
            drop(file);
            names.push(publish(&part, &folder, "holiday photo.jpg").unwrap());
            assert!(!part.exists());
        }
        assert_eq!(names[0], folder.join("holiday photo.jpg"));
        assert_eq!(names[1], folder.join("holiday photo (1).jpg"));
        assert_eq!(names[2], folder.join("holiday photo (2).jpg"));
        assert_eq!(std::fs::read_to_string(&names[0]).unwrap(), "content 0", "the first is untouched");
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(std::fs::metadata(&names[0]).unwrap().permissions().mode() & 0o777, 0o600, "not executable");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_hostile_name_stays_in_the_folder() {
        let root = folder("hostile");
        let folder = device_folder(&root, "Sam phone").unwrap();
        let (file, part) = create_part(&folder).unwrap();
        drop(file);
        let path = publish(&part, &folder, "..\\..\\.config/autostart/evil.sh").unwrap();
        assert_eq!(path, folder.join("evil.sh"));
        let (file, part) = create_part(&folder).unwrap();
        drop(file);
        let path = publish(&part, &folder, "..").unwrap();
        assert_eq!(path.parent().unwrap(), folder);
        assert!(!root.join("evil.sh").exists() && !root.parent().unwrap().join("evil.sh").exists());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_phone_with_a_strange_name_gets_a_folder_inside_the_root() {
        let root = folder("odd-device");
        let f = device_folder(&root, "../../etc").unwrap();
        assert_eq!(f.parent().unwrap(), root);
        let f = device_folder(&root, "..").unwrap();
        assert_eq!(f.parent().unwrap(), root);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn times_and_space() {
        let now = SystemTime::now();
        assert!(plausible_time(1_761_000_000_000, now).is_some());
        assert!(plausible_time(0, now).is_none());
        assert!(plausible_time(-5, now).is_none());
        assert!(plausible_time(i64::MAX, now).is_none());
        let far = now.duration_since(UNIX_EPOCH).unwrap().as_millis() as i64 + 3 * 86_400_000;
        assert!(plausible_time(far, now).is_none());
        assert!(free_space(&std::env::temp_dir()).is_some_and(|n| n > 0));
        assert!(free_space(Path::new("/nonexistent/x")).is_none());
    }

    #[test]
    fn only_a_short_list_of_types_is_opened_by_a_button() {
        for safe in ["photo.jpg", "picture.PNG", "notes.txt", "paper.pdf", "song.mp3", "clip.mp4", "voice.ogg", "shot.webp"] {
            assert!(safe_to_open(Path::new(&format!("/x/{safe}"))), "{safe}");
        }
        for unsafe_ in ["app.desktop", "tool.flatpakref", "package.rpm", "install.sh", "page.html", "drawing.svg", "bundle.zip", "macro.docm", "a.AppImage", "noextension", "x.exe", "run.py", "repo.flatpakrepo", "x.jar", "file.torrent"] {
            assert!(!safe_to_open(Path::new(&format!("/x/{unsafe_}"))), "{unsafe_}");
        }
        assert!(!safe_to_open(Path::new("/")));
    }

    #[test]
    fn bodies_we_send() {
        assert_eq!(file_body("notes.txt", None, None), json!({ "filename": "notes.txt", "open": false }));
        assert_eq!(
            file_body("a", Some(5), Some(Batch { files: 2, bytes: 9 })),
            json!({ "filename": "a", "open": false, "lastModified": 5, "numberOfFiles": 2, "totalPayloadSize": 9 })
        );
    }

    #[test]
    fn what_may_be_sent() {
        let root = folder("sendable");
        let file = root.join("a.txt");
        std::fs::write(&file, "12345").unwrap();
        let uri = gio::File::for_path(&file).uri().to_string();
        assert_eq!(sendable(&uri).unwrap(), (file.clone(), 5));
        let dir_uri = gio::File::for_path(&root).uri().to_string();
        assert!(sendable(&dir_uri).is_err(), "a folder");
        assert!(sendable("file:///nonexistent/file").is_err());
        assert!(sendable("file://otherhost/etc/passwd").is_err(), "another host's");
        assert!(sendable("https://example.org/a").is_err());
        assert!(sendable("/etc/passwd").is_err());
        let _ = std::fs::remove_dir_all(&root);
    }
}
