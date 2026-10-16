//! What a window remembers between runs that is only a convenience, such as the page it was on: what the
//! Electron pages kept in localStorage, in `~/.local/state/amethystora/<app>.json`. Losing it costs nothing.

use std::path::PathBuf;

use serde_json::Value;

fn file(app: &str) -> PathBuf {
    let state = std::env::var_os("XDG_STATE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::palette::home().join(".local/state"));
    state.join("amethystora").join(format!("{app}.json"))
}

/// What the app saved, or an empty object
pub fn load(app: &str) -> Value {
    std::fs::read_to_string(file(app))
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .filter(Value::is_object)
        .unwrap_or_else(|| Value::Object(Default::default()))
}

/// Saved whole, through a file beside it, so that a crash never leaves half of it
pub fn save(app: &str, value: &Value) {
    let path = file(app);
    if let Some(folder) = path.parent() {
        let _ = std::fs::create_dir_all(folder);
    }
    let next = path.with_extension("json.new");
    if std::fs::write(&next, value.to_string()).is_ok() {
        let _ = std::fs::rename(&next, &path);
    }
}
