//! The colours of the current theme, which every window follows the way the rest of the desktop does.
//!
//! amethystora-theme renders the current theme into `~/.config/amethystora/current` (CURRENT_DIR in
//! /usr/lib/amethystora/theme/lib.sh): `theme/colors.toml` holds its colours and `theme/light.mode` says
//! it is a light one. Ten of them become the windows' own colours, the status colours among them from the
//! theme's red, green and yellow; every app's stylesheet mixes the rest from those, so any theme reads well
//! in it without a stylesheet of its own. `theme/palette.toml` holds the colours the interface takes from a theme
//! beyond its palette (palette.awk in /usr/lib/amethystora/theme: an accent a label reads on, status colours that
//! read as text, each at the contrast WCAG asks), and replaces those ten where it has them. Until a theme has been
//! applied the windows keep the Amethystora colours, light or dark as the system's colour scheme says.

use std::collections::BTreeMap;
use std::path::PathBuf;

use crate::shape::Shape;

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
    ("accent-text", "#ac67ff"),
    ("destructive", "#ef6b7d"),
    ("on-destructive", "#110c18"),
    ("destructive-text", "#ef6b7d"),
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
    ("accent-text", "#5d1ac4"),
    ("destructive", "#b3261e"),
    ("on-destructive", "#ffffff"),
    ("destructive-text", "#b3261e"),
];

/// The colours of theme/palette.toml, and the window colours they become, over the ten above
const DERIVED: &[(&str, &str)] = &[
    ("accent_bg", "accent"),
    ("accent_fg", "on-accent"),
    ("accent_text", "accent-text"),
    ("destructive_bg", "destructive"),
    ("destructive_fg", "on-destructive"),
    ("destructive_text", "destructive-text"),
    ("success_text", "ok"),
    ("warning_text", "warn"),
    ("error_text", "bad"),
];

/// A theme's colours, by the names colors.toml gives them, and whether it is a light theme
#[derive(Debug, Clone, PartialEq)]
pub struct Palette {
    pub light: bool,
    pub colors: BTreeMap<String, String>,
    /// How round the desktop style makes things, when the style in force has a shape (every style but floating)
    pub shape: Option<Shape>,
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

/// The colours of a file of `name = "#rrggbb"` lines, put into `colors`
fn read_colors(text: &str, colors: &mut BTreeMap<String, String>) {
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
}

/// The radii of the desktop style in force: `current/style.name` names it, and `theme/shapes.conf` (lib.sh's STYLE_SHAPE)
/// has a `style.token = px` line for each of its radii. None for a style that leaves the applications their own corners.
fn read_shape(current: &std::path::Path) -> Option<Shape> {
    let style = std::fs::read_to_string(current.join("style.name")).ok()?;
    let style = style.lines().next()?.trim().to_string();
    let text = std::fs::read_to_string(current.join("theme").join("shapes.conf")).ok()?;
    let value = |token: &str| -> Option<f64> {
        let wanted = format!("{style}.{token}");
        text.lines().find_map(|line| {
            let (key, value) = line.split_once('=')?;
            if key.trim() == wanted { value.trim().parse().ok() } else { None }
        })
    };
    Some(Shape { card: value("card")?, window: value("window")? })
}

/// The current theme's colours, or None before one has been applied
pub fn read() -> Option<Palette> {
    let current = current();
    let theme = current.join("theme");
    let text = std::fs::read_to_string(theme.join("colors.toml")).ok()?;
    let mut colors = BTreeMap::new();
    read_colors(&text, &mut colors);
    // The interface's own, which a theme applied before they were worked out lacks
    if let Ok(text) = std::fs::read_to_string(theme.join("palette.toml")) {
        read_colors(&text, &mut colors);
    }
    Some(Palette { light: theme.join("light.mode").exists(), colors, shape: read_shape(&current) })
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
        // Text on the accent in whichever of black and white reads better against it, for a theme whose palette.toml
        // has not been worked out yet; where it has, the colours it holds are the interface's own
        if let Some(accent) = palette.colors.get("accent") {
            values.insert("on-accent", if luminance(accent) > 0.18 { "#000000" } else { "#ffffff" }.into());
            values.insert("accent-text", accent.clone());
        }
        if let Some(bad) = palette.colors.get("color1") {
            values.insert("destructive", bad.clone());
            values.insert("destructive-text", bad.clone());
            values.insert("on-destructive", if luminance(bad) > 0.18 { "#000000" } else { "#ffffff" }.into());
        }
        for (key, name) in DERIVED {
            if let Some(value) = palette.colors.get(*key) {
                values.insert(name, value.clone());
            }
        }
    }
    let mut out = String::from(":root {\n");
    for (name, value) in values {
        out.push_str(&format!("    --{name}: {value};\n"));
    }
    // The corners of a window are libadwaita's own variable, which the desktop style gives its own value
    if let Some(shape) = palette.and_then(|palette| palette.shape) {
        out.push_str(&format!("    --window-radius: {}px;\n", shape.window));
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
        let css = css(Some(&Palette { light: false, colors, shape: None }), false);
        assert!(css.contains("--on-accent: #000000;"));
        assert!(css.contains("--accent: #f5e0dc;"));
        assert!(css.contains("--bg: #110c18;"));
    }
}
