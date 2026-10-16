//! The Rust window and the Electron one keep the same notes in the same files: what either writes, the other
//! opens. The fixtures in tests/fixtures were written by electron.js, with main.js's own functions (run once,
//! with the image's Electron as Node); these tests open them here. Where a Node is at hand (the Containerfile's
//! apps stage has one), the other way round is tested too: what these tests write, electron.js reads with
//! main.js's own code. The passkeys are tested against stand-in fido2 tools (tests/stand-ins),
//! which check the arguments and the lines on stdin main.js gave them; no real security key is involved.

use std::cell::RefCell;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use amethystora_notes::backend::{self, Backend, Change, Paths, Shared};
use amethystora_notes::data::{self, Fields, Kind, Store};
use amethystora_notes::import::Counts;
use amethystora_notes::passkeys::{self, Unlocked};
use amethystora_notes::vault;
use amethystora_ui::glib;
use serde_json::{json, Value};

const PASSPHRASE: &str = "correct horse battery staple";
const NOTE: &str = "0e7e0000000000000000000000000001";
const PICTURE: &str = "a77ac000000000000000000000000001";
const LIST: &str = "a77ac000000000000000000000000002";
const TASK: &str = "7a5c0000000000000000000000000001";

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

/// A folder of its own for each test, emptied first
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("amethystora-notes-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn copy(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).unwrap();
    for entry in std::fs::read_dir(from).unwrap().flatten() {
        let target = to.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).unwrap();
        }
    }
}

/// Runs a test's steps on a main context of its own, as the window's would. The backend's timers go on
/// GLib's default main context, which only one thread may own: these tests run on one thread
/// (`--test-threads=1`, as build-apps.sh runs them).
fn run<T>(work: impl Future<Output = T>) -> T {
    let context = glib::MainContext::new();
    context.with_thread_default(|| context.block_on(work)).unwrap()
}

fn backend_at(dir: &Path) -> Shared {
    Rc::new(RefCell::new(Backend::new(Paths::new(dir.to_path_buf()))))
}

fn store(this: &Shared) -> Store {
    this.borrow().store.clone().expect("the notes are open")
}

/// The store main.js wrote into the fixture, from its plain copy
fn fixture_store() -> Store {
    let text = std::fs::read_to_string(fixtures().join("plain/data.json")).unwrap();
    Store::normalise(&data::parse_json(&text).unwrap())
}

fn png() -> Vec<u8> {
    std::fs::read(fixtures().join("plain/resources").join(PICTURE)).unwrap()
}

/// electron.js with these arguments, when there is a Node here to run it
fn electron(args: &[&str]) -> Option<Value> {
    let Ok(output) = std::process::Command::new("node")
        .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/electron.js"))
        .args(args)
        .output()
    else {
        eprintln!("No Node here: the Electron side of this test is skipped");
        return None;
    };
    assert!(output.status.success(), "electron.js {args:?}: {}", String::from_utf8_lossy(&output.stderr));
    Some(serde_json::from_slice(&output.stdout).unwrap())
}

#[test]
fn opens_an_encrypted_vault_electron_wrote() {
    let dir = scratch("encrypted");
    copy(&fixtures().join("encrypted"), &dir);
    let this = backend_at(&dir);
    run(async {
        backend::start(&this).unwrap();
        assert_eq!(this.borrow().status(), "locked");
        assert!(this.borrow().encrypted());
        assert_eq!(backend::unlock(&this, "not it".into()).await, Err("That is not the passphrase.".into()));
        backend::unlock(&this, PASSPHRASE.into()).await.unwrap();
        assert_eq!(this.borrow().status(), "open");
        // Everything main.js put in, exactly as it put it in
        assert_eq!(store(&this), fixture_store());
        let opened = store(&this);
        let note = opened.get(Kind::Notes, NOTE).unwrap();
        assert_eq!(note.title(), "Pancakes 🥞");
        assert!(note.str("body").contains("<b>not bold</b>"));
        assert_eq!(opened.get(Kind::Notebooks, note.str("notebook")).unwrap().title(), "Recipes — été");
        let task = opened.get(Kind::Tasks, TASK).unwrap();
        assert_eq!(task["repeat"], json!({ "every": 2, "unit": "week" }));
        assert_eq!(task["reminder"], 15);
        assert_eq!(opened.settings["autoLock"], 15);
        // The attachments, unsealed
        assert_eq!(this.borrow().read_resource(PICTURE).unwrap(), png());
        assert_eq!(this.borrow().read_resource(LIST).unwrap(), b"Milk, eggs, flour.\nSomething for the weekend.\n");
        let passkeys = this.borrow().passkeys();
        assert_eq!(passkeys.len(), 1);
        assert_eq!(passkeys[0].name, "YubiKey 5 NFC");
        assert!(passkeys[0].protected);
        // The reminder of the task with a time and a reminder, fifteen minutes before it
        let reminders = this.borrow().reminders.clone();
        assert!(reminders.iter().all(|r| r.at <= r.due));
    });
}

#[test]
fn opens_a_plain_vault_electron_wrote() {
    let dir = scratch("plain");
    copy(&fixtures().join("plain"), &dir);
    let this = backend_at(&dir);
    run(async {
        backend::start(&this).unwrap();
        assert_eq!(this.borrow().status(), "open");
        assert!(!this.borrow().encrypted());
        assert_eq!(store(&this), fixture_store());
        assert_eq!(this.borrow().read_resource(PICTURE).unwrap(), png());
    });
}

#[test]
fn an_encrypted_vault_reads_only_sealed_files() {
    // Somebody slips a plain data.json beside the sealed one: an encrypted vault never reads it
    let dir = scratch("slipped");
    copy(&fixtures().join("encrypted"), &dir);
    std::fs::write(dir.join("data.json"), r#"{"notes":{"ffffffffffffffffffffffffffffffff":{"id":"ffffffffffffffffffffffffffffffff","title":"slipped in"}}}"#).unwrap();
    std::fs::remove_file(dir.join("data.bin")).unwrap();
    let this = backend_at(&dir);
    run(async {
        backend::start(&this).unwrap();
        backend::unlock(&this, PASSPHRASE.into()).await.unwrap();
        assert!(store(&this).kind(Kind::Notes).is_empty());
    });
}

#[test]
fn electron_reads_what_this_wrote() {
    let dir = scratch("written");
    let this = backend_at(&dir);
    run(async {
        backend::start(&this).unwrap();
        assert_eq!(this.borrow().status(), "new");
        backend::create(&this, Some(PASSPHRASE.into())).await.unwrap();
        let resource = backend::add_resource(&this, "pan.png".into(), "image/png".into(), png(), None).await.unwrap();
        let id = resource.id().to_string();
        let note = data::new_id();
        let task = data::new_id();
        {
            let mut backend = this.borrow_mut();
            let notebook = backend.store.as_ref().unwrap().values(Kind::Notebooks).next().unwrap().id().to_string();
            let store = backend.store.as_mut().unwrap();
            store.put(Kind::Notes, json!({ "id": note, "notebook": notebook, "title": "Écrit ici 🥞", "body": format!("![x](:/{id})"), "tags": [], "created": 1, "updated": 2, "trashed": null }));
            store.put(Kind::Tasks, json!({ "id": task, "title": "Buy flour", "due": "2026-10-20", "time": "17:30", "reminder": 0, "priority": 2, "labels": [], "done": null, "repeat": { "every": 1, "unit": "week" } }));
        }
        Backend::changed(&this, &[Kind::Notes, Kind::Tasks], false);
        backend::flush(&this).await;
        let ours = store(&this);
        let check = |seen: &Value, form: &str| {
            assert_eq!(Store::normalise(&seen["store"]), ours);
            assert_eq!(vault::unbase64(seen["resources"][&id].as_str().unwrap()), png());
            // Only the one form of the data: an encrypted vault keeps no copy in the clear, and the other way round
            let other = if form == "data.bin" { "data.json" } else { "data.bin" };
            let files: Vec<&str> = seen["files"].as_array().unwrap().iter().map(|f| f.as_str().unwrap()).collect();
            assert!(files.contains(&form) && files.contains(&"vault.json") && !files.iter().any(|f| f.starts_with(other)), "{files:?}");
        };
        if let Some(seen) = electron(&["verify", dir.to_str().unwrap(), PASSPHRASE]) {
            // An encrypted vault keeps no copy in the clear
            check(&seen, "data.bin");
        }
        // A new passphrase alone: the same key, rewrapped
        backend::set_encryption(&this, Change::Passphrase { new_key: false }, PASSPHRASE.into(), "a second passphrase".into()).await.unwrap();
        if let Some(seen) = electron(&["verify", dir.to_str().unwrap(), "a second passphrase"]) {
            check(&seen, "data.bin");
        }
        // A new key as well: everything sealed anew, through next/
        backend::set_encryption(&this, Change::Passphrase { new_key: true }, "a second passphrase".into(), "and a third one".into()).await.unwrap();
        assert!(!dir.join("next").exists());
        if let Some(seen) = electron(&["verify", dir.to_str().unwrap(), "and a third one"]) {
            check(&seen, "data.bin");
        }
        assert_eq!(backend::set_encryption(&this, Change::Disable, "wrong".into(), String::new()).await, Err("That is not the current passphrase.".into()));
        // Off: written in the clear, and nothing sealed left behind
        backend::set_encryption(&this, Change::Disable, "and a third one".into(), String::new()).await.unwrap();
        assert!(!this.borrow().encrypted());
        assert!(!dir.join("data.bin").exists());
        assert!(!vault::is_sealed(&std::fs::read(dir.join("resources").join(&id)).unwrap()));
        if let Some(seen) = electron(&["verify", dir.to_str().unwrap()]) {
            check(&seen, "data.json");
        }
        // And on again
        backend::set_encryption(&this, Change::Enable, String::new(), PASSPHRASE.into()).await.unwrap();
        assert!(vault::is_sealed(&std::fs::read(dir.join("resources").join(&id)).unwrap()));
        assert!(!dir.join("data.json").exists());
        if let Some(seen) = electron(&["verify", dir.to_str().unwrap(), PASSPHRASE]) {
            check(&seen, "data.bin");
        }
        // Locked: the key is gone, and the passphrase opens it again
        backend::lock(&this).await;
        assert_eq!(this.borrow().status(), "locked");
        assert!(this.borrow().key.is_none());
        backend::unlock(&this, PASSPHRASE.into()).await.unwrap();
        assert_eq!(store(&this), ours);
    });
}

#[test]
fn a_change_of_key_cut_short_loses_nothing() {
    // next/ holds files sealed under a key that vault.json does not have: they are thrown away, and what
    // is in place stays
    let dir = scratch("cut-short");
    copy(&fixtures().join("encrypted"), &dir);
    std::fs::create_dir_all(dir.join("next/resources")).unwrap();
    let other = vault::Key::random();
    std::fs::write(dir.join("next/data"), vault::seal(&other, b"{}", "data")).unwrap();
    std::fs::write(dir.join("next/resources").join(PICTURE), vault::seal(&other, b"x", &format!("resource:{PICTURE}"))).unwrap();
    let this = backend_at(&dir);
    run(async {
        backend::start(&this).unwrap();
        backend::unlock(&this, PASSPHRASE.into()).await.unwrap();
        assert!(!dir.join("next").exists());
        assert_eq!(store(&this), fixture_store());
        assert_eq!(this.borrow().read_resource(PICTURE).unwrap(), png());
    });
}

fn counts(notes: u64, notebooks: u64, tasks: u64, projects: u64, attachments: u64) -> Counts {
    Counts { notes, notebooks, tasks, projects, attachments }
}

#[test]
fn backups_both_ways() {
    let dir = scratch("backups");
    let this = backend_at(&dir);
    run(async {
        backend::start(&this).unwrap();
        backend::create(&this, None).await.unwrap();
        // An encrypted backup asks for the passphrase it was made with
        let imported = backend::import_files(&this, vec![fixtures().join("backup-encrypted.amnotes")]).await.unwrap();
        assert_eq!(imported.passphrase.as_deref(), Some("backup-encrypted.amnotes"));
        assert_eq!(backend::import_pending(&this, "wrong".into()).await, Err("That is not the passphrase this backup was made with.".into()));
        assert_eq!(backend::import_pending(&this, PASSPHRASE.into()).await.unwrap(), counts(3, 2, 3, 1, 2));
        let fixture = fixture_store();
        let opened = store(&this);
        for kind in Kind::ALL {
            for (id, item) in fixture.kind(kind) {
                assert_eq!(opened.kind(kind).get(id), Some(item), "{} {id}", kind.name());
            }
        }
        assert_eq!(this.borrow().read_resource(PICTURE).unwrap(), png());
        // A plain one is added at once
        let imported = backend::import_files(&this, vec![fixtures().join("backup-plain.amnotes")]).await.unwrap();
        assert_eq!(imported.counts, counts(3, 2, 3, 1, 2));
        assert!(imported.skipped.is_empty());
        // What this backs up, electron.js opens, plain and encrypted
        let file = dir.join("Notes backup.amnotes");
        assert!(!backend::backup(&this, file.clone()).await.unwrap());
        if let Some(seen) = electron(&["backup", file.to_str().unwrap()]) {
            assert_eq!(Store::normalise(&seen["store"]).kind(Kind::Notes), store(&this).kind(Kind::Notes));
            assert_eq!(vault::unbase64(seen["resources"][PICTURE].as_str().unwrap()), png());
        }
        backend::set_encryption(&this, Change::Enable, String::new(), PASSPHRASE.into()).await.unwrap();
        assert!(backend::backup(&this, file.clone()).await.unwrap());
        if let Some(seen) = electron(&["backup", file.to_str().unwrap(), PASSPHRASE]) {
            assert_eq!(seen["encrypted"], true);
            assert_eq!(Store::normalise(&seen["store"]).kind(Kind::Tasks), store(&this).kind(Kind::Tasks));
            assert_eq!(vault::unbase64(seen["resources"][LIST].as_str().unwrap()), b"Milk, eggs, flour.\nSomething for the weekend.\n");
        }
        // The backup carries no passkey
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(!text.contains("passkeys"));
    });
}

/// An imported store as it can be compared with what main.js made of the same file: without what main.js
/// filled in with the moment of the import (the Imported notebook's times, the projects' and attachments'
/// created, a Markdown note's times) or at random (the Imported notebook's id, a Markdown note's and its new
/// tags'), every list in a fixed order. electron.js ran with TZ=UTC; elsewhere the times Joplin and Planify
/// wrote without a zone are the session's own, and the tasks' times are left out too.
fn canonical(store: &Store, markdown: bool) -> Value {
    let local_utc = glib::DateTime::now_local().map(|now| now.utc_offset().as_seconds() == 0).unwrap_or(false);
    let imported: Vec<String> = store.values(Kind::Notebooks).filter(|n| n.title() == "Imported").map(|n| n.id().to_string()).collect();
    let tag_title = |id: &str| store.get(Kind::Tags, id).map(|tag| tag.title().to_string()).unwrap_or_default();
    let drop = |item: &mut Value, fields: &[&str]| {
        for field in fields {
            item.as_object_mut().unwrap().remove(*field);
        }
    };
    let mut out = serde_json::Map::new();
    for kind in Kind::ALL {
        let mut items: Vec<Value> = store.values(kind).cloned().collect();
        for item in &mut items {
            match kind {
                Kind::Notebooks if imported.iter().any(|id| id == item.id()) => {
                    data::set(item, "id", "(imported)");
                    drop(item, &["created", "updated"]);
                }
                Kind::Notes => {
                    if imported.iter().any(|id| id == item.str("notebook")) {
                        data::set(item, "notebook", "(imported)");
                    }
                    if markdown {
                        // A Markdown note: made now, with an id and tags made at random
                        data::set(item, "id", "(new)");
                        let titles: Vec<Value> = item.list("tags").iter().map(|id| Value::String(tag_title(id))).collect();
                        data::set(item, "tags", Value::Array(titles));
                        drop(item, &["created", "updated"]);
                    }
                }
                Kind::Tags if markdown => data::set(item, "id", "(new)"),
                Kind::Projects => drop(item, &["created"]),
                Kind::Tasks if !local_utc => drop(item, &["due", "time", "done", "created", "order"]),
                _ => {}
            }
        }
        items.sort_by_key(|item| format!("{}\u{0}{}", item.str("id"), item.str("title")));
        out.insert(kind.name().into(), Value::Array(items));
    }
    let mut resources: Vec<Value> = store.resources.values().cloned().collect();
    for resource in &mut resources {
        drop(resource, &["created"]);
    }
    resources.sort_by_key(|item| item.id().to_string());
    out.insert("resources".into(), Value::Array(resources));
    Value::Object(out)
}

fn same_import(ours: &Store, expected: &Value, markdown: bool) {
    let expected = Store::normalise(&expected["store"]);
    assert_eq!(canonical(ours, markdown), canonical(&expected, markdown));
}

#[test]
fn imports_as_main_js_did() {
    let expected = |name: &str| data::parse_json(&std::fs::read_to_string(fixtures().join(format!("{name}.expected.json"))).unwrap()).unwrap();
    for (file, random) in [("sample.jex", false), ("planify.json", false), ("markdown.md", true)] {
        let dir = scratch(&format!("import-{file}"));
        let this = backend_at(&dir);
        run(async {
            backend::start(&this).unwrap();
            backend::create(&this, None).await.unwrap();
            // The first notebook create() makes is not what main.js's import started from
            this.borrow_mut().store.as_mut().unwrap().kind_mut(Kind::Notebooks).clear();
            let imported = backend::import_files(&this, vec![fixtures().join(file)]).await.unwrap();
            assert!(imported.skipped.is_empty(), "{:?}", imported.skipped);
            let wanted = expected(file);
            let counts = &wanted["counts"];
            assert_eq!(imported.counts, Counts {
                notes: counts["notes"].as_u64().unwrap(),
                notebooks: counts["notebooks"].as_u64().unwrap(),
                tasks: counts["tasks"].as_u64().unwrap(),
                projects: counts["projects"].as_u64().unwrap(),
                attachments: counts["attachments"].as_u64().unwrap(),
            }, "{file}");
            same_import(&store(&this), &wanted, random);
            for (id, bytes) in wanted["resources"].as_object().unwrap() {
                assert_eq!(this.borrow().read_resource(id).unwrap(), vault::unbase64(bytes.as_str().unwrap()), "{file} {id}");
            }
        });
    }
}

#[test]
fn a_file_that_is_not_one_is_skipped() {
    let dir = scratch("skipped");
    std::fs::write(dir.join("other.json"), "{\"hello\": 1}").unwrap();
    std::fs::write(dir.join("not.amnotes"), "{\"format\": \"zip\"}").unwrap();
    let vault_dir = dir.join("vault");
    let this = backend_at(&vault_dir);
    run(async {
        backend::start(&this).unwrap();
        backend::create(&this, None).await.unwrap();
        let imported = backend::import_files(&this, vec![dir.join("other.json"), dir.join("not.amnotes")]).await.unwrap();
        assert_eq!(imported.skipped, vec![
            "other.json was not imported: it is not a Planify backup".to_string(),
            "not.amnotes was not imported: it is not a Notes backup".to_string(),
        ]);
    });
}

#[test]
fn exports_markdown_as_main_js_did() {
    let dir = scratch("export");
    copy(&fixtures().join("plain"), &dir.join("vault"));
    let out = dir.join("out");
    std::fs::create_dir_all(&out).unwrap();
    let this = backend_at(&dir.join("vault"));
    run(async {
        backend::start(&this).unwrap();
        let exported = backend::export_markdown(&this, out.clone()).await.unwrap();
        assert_eq!((exported.notes, exported.tasks), (2, 2));
        let root = exported.path;
        let note = std::fs::read_to_string(root.join("Notes/Recipes — été/Pancakes 🥞.md")).unwrap();
        assert!(note.starts_with("---\ntitle: \"Pancakes 🥞\"\ncreated: 2026-10-01T09:30:00.000Z\nupdated: 2026-10-01T09:31:00.000Z\ntags: [\"kitchen\"]\n---\n\n# Pancakes"));
        assert!(note.contains(&format!("![the pan](../../_resources/{PICTURE}.png)")));
        assert_eq!(std::fs::read(root.join("_resources").join(format!("{PICTURE}.png"))).unwrap(), png());
        let home = std::fs::read_to_string(root.join("Tasks/Home.md")).unwrap();
        assert_eq!(home, "# Home\n\n## Weekend\n\n- [ ] Buy flour (due 2026-10-20 17:30, every 2 weeks, p1, @errand)\n  - [ ] Find the shop\n");
        let inbox = std::fs::read_to_string(root.join("Tasks/Inbox.md")).unwrap();
        assert_eq!(inbox, "# Inbox\n\n- [x] Call Sam (due 2026-10-01, p3)\n");
    });
}

// --- Passkeys, against stand-in tools ---------------------------------------------------------------------

/// The stand-in fido2 tools in a folder of their own, with what the key they stand for can do
fn stand_ins(dir: &Path, uv: bool, credentials: Value) -> PathBuf {
    let tools = dir.join("tools");
    std::fs::create_dir_all(&tools).unwrap();
    for tool in ["fido2-token", "fido2-assert", "fido2-cred"] {
        let target = tools.join(tool);
        std::fs::copy(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/stand-ins").join(tool), &target).unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&target, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
    let mut options = vec!["rk", "up", "noplat", "clientPin", "credMgmt"];
    if uv {
        options.push("uv");
    }
    std::fs::write(tools.join("config.json"), json!({
        "device": "/dev/hidraw3",
        "list": ["/dev/hidraw3: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)"],
        "options": options,
        "extensions": ["credBlob", "credProtect", "hmac-secret", "largeBlobKey", "minPinLength"],
        "uv": uv,
        "pin": "1234",
        "credentials": credentials,
    }).to_string()).unwrap();
    tools
}

fn calls(tools: &Path) -> Vec<Value> {
    std::fs::read_to_string(tools.join("calls.log")).unwrap_or_default().lines().map(|line| serde_json::from_str(line).unwrap()).collect()
}

fn fixture_passkey() -> Value {
    data::parse_json(&std::fs::read_to_string(fixtures().join("passkey.json")).unwrap()).unwrap()
}

#[test]
fn opens_with_a_passkey_electron_added() {
    let dir = scratch("passkey-open");
    copy(&fixtures().join("encrypted"), &dir.join("vault"));
    let fixture = fixture_passkey();
    let tools = stand_ins(&dir, false, json!({ fixture["credential"].as_str().unwrap(): fixture["secret"] }));
    let this = backend_at(&dir.join("vault"));
    this.borrow_mut().tools = Some(tools.clone());
    run(async {
        backend::start(&this).unwrap();
        // A key that reads no fingerprint: its PIN is asked for first
        assert_eq!(passkeys::with_key(&this, async || passkeys::unlock(&this, String::new()).await).await, Ok(Unlocked::NeedsPin));
        assert_eq!(passkeys::with_key(&this, async || passkeys::unlock(&this, "0000".into()).await).await, Err("That is not the PIN of this security key.".into()));
        assert_eq!(passkeys::with_key(&this, async || passkeys::unlock(&this, "1234".into()).await).await, Ok(Unlocked::Open));
        assert_eq!(store(&this), fixture_store());
        let asked = calls(&tools);
        let tools_and_args: Vec<(String, Vec<String>)> = asked.iter().map(|call| (call["tool"].as_str().unwrap().to_string(), call["args"].as_array().unwrap().iter().map(|a| a.as_str().unwrap().to_string()).collect())).collect();
        assert_eq!(tools_and_args[0], ("fido2-token".into(), vec!["-L".to_string()]));
        assert_eq!(tools_and_args[1], ("fido2-token".into(), vec!["-I".to_string(), "/dev/hidraw3".into()]));
        assert!(tools_and_args.contains(&("fido2-assert".into(), ["-G", "-h", "-t", "pin=true", "/dev/hidraw3"].map(String::from).to_vec())));
    });
}

#[test]
fn adds_a_passkey_electron_opens_with() {
    let dir = scratch("passkey-add");
    copy(&fixtures().join("encrypted"), &dir.join("vault"));
    // A key with a fingerprint, which knows only the credentials it makes: the fixture's passkey is not its own
    let tools = stand_ins(&dir, true, json!({}));
    let this = backend_at(&dir.join("vault"));
    this.borrow_mut().tools = Some(tools.clone());
    run(async {
        backend::start(&this).unwrap();
        backend::unlock(&this, PASSPHRASE.into()).await.unwrap();
        assert_eq!(passkeys::with_key(&this, async || passkeys::add(&this, "wrong".into(), String::new()).await).await, Err("That is not the current passphrase.".into()));
        passkeys::with_key(&this, async || passkeys::add(&this, PASSPHRASE.into(), String::new()).await).await.unwrap();
        let list = this.borrow().passkeys();
        assert_eq!(list.len(), 2);
        assert_eq!(list[1].name, "Yubico YubiKey OTP+FIDO+CCID");
        assert!(list[1].protected);
        // Made with credProtect 3 and a fingerprint, as main.js made them
        let made: Vec<Value> = calls(&tools).into_iter().filter(|call| call["tool"] == "fido2-cred").collect();
        assert_eq!(made.len(), 1);
        assert_eq!(made[0]["args"], json!(["-M", "-h", "-c", "3", "-v", "/dev/hidraw3"]));
        let config: Value = serde_json::from_str(&std::fs::read_to_string(tools.join("config.json")).unwrap()).unwrap();
        assert!(!config["made"]["user"].as_str().unwrap().is_empty());
        let vault_value = this.borrow().vault.clone().unwrap();
        let passkey = &vault_value["passkeys"][1];
        assert_eq!(passkey["protect"], 3);
        assert_eq!(passkey["credential"], config["made"]["credential"]);
        // The secret the stand-in gives this credential and salt, which electron.js checks the seal with
        let secret = {
            use sha2::Digest;
            vault::base64(&sha2::Sha256::digest(format!("{}{}", passkey.str("credential"), passkey.str("salt")).as_bytes()))
        };
        if let Some(seen) = electron(&["passkey", dir.join("vault").to_str().unwrap(), PASSPHRASE, passkey.str("id"), &secret]) {
            assert_eq!(seen["opens"], true);
        }
        // Locked, it opens with the new passkey: the first, the fixture's, is turned down, the next tried
        backend::lock(&this).await;
        assert_eq!(passkeys::with_key(&this, async || passkeys::unlock(&this, String::new()).await).await, Ok(Unlocked::Open));
        assert!(this.borrow().store.is_some());
        let asserts: Vec<Value> = calls(&tools).into_iter().filter(|call| call["tool"] == "fido2-assert").collect();
        assert!(asserts.iter().all(|call| call["args"] == json!(["-G", "-h", "-t", "uv=true", "/dev/hidraw3"])));
        // Removing it leaves the passphrase
        let id = list[1].id.clone();
        passkeys::remove(&this, &id).unwrap();
        assert_eq!(this.borrow().passkeys().len(), 1);
        // A new key: the passkeys sealed the old one, and go with it
        backend::set_encryption(&this, Change::Passphrase { new_key: true }, PASSPHRASE.into(), "another".into()).await.unwrap();
        assert!(this.borrow().passkeys().is_empty());
    });
}

#[test]
fn a_passkey_wait_can_be_cancelled() {
    let dir = scratch("passkey-cancel");
    copy(&fixtures().join("encrypted"), &dir.join("vault"));
    let fixture = fixture_passkey();
    let tools = stand_ins(&dir, true, json!({ fixture["credential"].as_str().unwrap(): fixture["secret"] }));
    let mut config: Value = serde_json::from_str(&std::fs::read_to_string(tools.join("config.json")).unwrap()).unwrap();
    config["slow"] = json!(true);
    std::fs::write(tools.join("config.json"), config.to_string()).unwrap();
    let this = backend_at(&dir.join("vault"));
    this.borrow_mut().tools = Some(tools);
    run(async {
        backend::start(&this).unwrap();
        let canceller = this.clone();
        glib::spawn_future_local(async move {
            glib::timeout_future(std::time::Duration::from_millis(1500)).await;
            passkeys::cancel(&canceller);
        });
        let started = std::time::Instant::now();
        assert_eq!(passkeys::with_key(&this, async || passkeys::unlock(&this, String::new()).await).await, Err("Cancelled.".into()));
        assert!(started.elapsed().as_secs() < 20);
        assert_eq!(this.borrow().status(), "locked");
    });
}
