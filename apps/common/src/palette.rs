//! The colours of the current theme, which every window follows the way the rest of the desktop does.
//!
//! amethystora-theme renders the current theme into `~/.config/amethystora/current` (CURRENT_DIR in
//! /usr/lib/amethystora/theme/lib.sh): `theme/colors.toml` holds its colours and `theme/light.mode` says
//! it is a light one. Ten of them become the windows' own colours, the status colours among them from the
//! theme's red, green and yellow; every app's stylesheet mixes the rest from those, so any theme reads well
//! in it without a stylesheet of its own. Until a theme has been applied the windows keep the Amethystora
//! colours, light or dark as the system's colour scheme says.

use std::collections::BTreeMap;
use std::path::PathBuf;

/// The theme's colour names, and the window colours they become
const VARIABLES: &[(&str, &str)] = &[
    ("background", "bg"),
    ("foreground", "fg"),
    ("accent", "accent"),
    ("color0", "surface"),
    ("color8", "muted"),
    ("selection_background", "selection"),
    ("selection_foreground", "selection-fg"),
    ("color1", "bad"),
    ("color2", "ok"),
    ("color3", "warn"),
];

/// The Amethystora colours, dark, until a theme is applied
const DARK: &[(&str, &str)] = &[
    ("bg", "#110c18"),
    ("fg", "#e8e0f2"),
    ("accent", "#9148f0"),
    ("surface", "#2a2136"),
    ("muted", "#6b5f7d"),
    ("selection", "#4a13a0"),
    ("selection-fg", "#f3ecfb"),
    ("bad", "#ef6b7d"),
    ("ok", "#8ddba4"),
    ("warn", "#e8c06a"),
    ("on-accent", "#ffffff"),
];

/// ...and light
const LIGHT: &[(&str, &str)] = &[
    ("bg", "#fdf8ff"),
    ("fg", "#1d1a22"),
    ("accent", "#5d1ac4"),
    ("surface", "#e6dfec"),
    ("muted", "#b8b0c4"),
    ("selection", "#eaddff"),
    ("selection-fg", "#1d1a22"),
    ("bad", "#b3261e"),
    ("ok", "#2f7d4f"),
    ("warn", "#8a6100"),
    ("on-accent", "#ffffff"),
];

/// A theme's colours, by the names colors.toml gives them, and whether it is a light theme
#[derive(Debug, Clone, PartialEq)]
pub struct Palette {
    pub light: bool,
    pub colors: BTreeMap<String, String>,
}

/// Where amethystora-theme renders the current theme
pub fn current() -> PathBuf {
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"));
    config.join("amethystora").join("current")
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

/// The current theme's colours, or None before one has been applied
pub fn read() -> Option<Palette> {
    let theme = current().join("theme");
    let text = std::fs::read_to_string(theme.join("colors.toml")).ok()?;
    let mut colors = BTreeMap::new();
    for line in text.lines() {
        // name = "#rrggbb", as the Manual's regular expression read it
        let Some((key, value)) = line.split_once('=') else { continue };
        let key = key.trim();
        if key.is_empty() || !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            continue;
        }
        let value = value.trim();
        let Some(hex) = value.strip_prefix("\"#").and_then(|rest| rest.get(..7)) else { continue };
        let (digits, quote) = hex.split_at(6);
        if quote == "\"" && digits.chars().all(|c| c.is_ascii_hexdigit()) {
            colors.insert(key.to_string(), format!("#{digits}"));
        }
    }
    Some(Palette { light: theme.join("light.mode").exists(), colors })
}

fn luminance(hex: &str) -> f64 {
    let channel = |at: usize| {
        let c = u8::from_str_radix(hex.get(at..at + 2).unwrap_or("00"), 16).unwrap_or(0) as f64 / 255.0;
        if c <= 0.03928 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
    };
    0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
}

/// The window colours as CSS variables on every toplevel: the defaults for light or dark, the theme's
/// own over them, and text on the accent in whichever of black and white reads better against it
pub fn css(palette: Option<&Palette>, light: bool) -> String {
    let mut values: BTreeMap<&str, String> =
        (if light { LIGHT } else { DARK }).iter().map(|(name, value)| (*name, value.to_string())).collect();
    if let Some(palette) = palette {
        for (key, name) in VARIABLES {
            if let Some(value) = palette.colors.get(*key) {
                values.insert(name, value.clone());
            }
        }
        if let Some(accent) = palette.colors.get("accent") {
            values.insert("on-accent", if luminance(accent) > 0.18 { "#000000" } else { "#ffffff" }.into());
        }
    }
    let mut out = String::from(":root {\n");
    for (name, value) in values {
        out.push_str(&format!("    --{name}: {value};\n"));
    }
    out.push_str("}\n");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn on_accent_follows_luminance() {
        let mut colors = BTreeMap::new();
        colors.insert("accent".to_string(), "#f5e0dc".to_string());
        let css = css(Some(&Palette { light: false, colors }), false);
        assert!(css.contains("--on-accent: #000000;"));
        assert!(css.contains("--accent: #f5e0dc;"));
        assert!(css.contains("--bg: #110c18;"));
    }
}
