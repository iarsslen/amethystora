//! How round the current desktop style makes the windows' own parts.
//!
//! The apps' stylesheets were ported from the Electron pages, in px corners that are right for the look those pages
//! had. A desktop style (ame desktop style) rounds the rest of the desktop by its own measure, and these windows are
//! part of it: the style says how round a card is, in px, and every corner of a stylesheet is scaled by that over the
//! 12 px the pages drew a card with, so a hairline desktop has crisp windows and a capsule one soft windows, without
//! a stylesheet of its own for each. A corner that is a pill (100 px or more) or a percentage stays what it is, but for
//! the terminal style, which has no round corner at all.

/// The corners of a card in the Electron pages, which the stylesheets' px were drawn for
const BASELINE: f64 = 12.0;

/// What a style does to a stylesheet's corners: its card's radius, and its window's
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Shape {
    pub card: f64,
    pub window: f64,
}

impl Shape {
    /// The factor a corner of the stylesheets is multiplied by
    pub fn scale(&self) -> f64 {
        self.card / BASELINE
    }
}

/// The stylesheet with every px of a corner (border-radius and each of its four sides) scaled to the style
pub fn shape_css(css: &str, shape: Option<Shape>) -> String {
    let Some(shape) = shape else { return css.to_string() };
    let scale = shape.scale();
    let mut out = String::with_capacity(css.len());
    let mut at = 0;
    while let Some(found) = css[at..].find("radius") {
        let name_end = at + found + "radius".len();
        // A property of that name: a run of letters and dashes ending in "radius", after the start of a declaration
        // (a brace, a semicolon or a line), and followed by its colon
        let name_start = css[..at + found]
            .char_indices()
            .rev()
            .find(|(_, c)| !(c.is_ascii_alphabetic() || *c == '-'))
            .map_or(0, |(i, c)| i + c.len_utf8());
        let before = css[..name_start].trim_end_matches([' ', '\t']);
        let boundary = before.is_empty() || before.ends_with(['{', ';', '\n']);
        let rest = css[name_end..].trim_start_matches([' ', '\t']);
        if boundary && rest.starts_with(':') {
            let value_start = css.len() - rest.len() + 1;
            let value_end = css[value_start..].find([';', '}']).map_or(css.len(), |i| value_start + i);
            out.push_str(&css[at..value_start]);
            out.push_str(&scale_corners(&css[value_start..value_end], scale));
            at = value_end;
        } else {
            out.push_str(&css[at..name_end]);
            at = name_end;
        }
    }
    out.push_str(&css[at..]);
    out
}

/// The px lengths of one declaration, scaled
fn scale_corners(value: &str, scale: f64) -> String {
    let mut out = String::new();
    let bytes = value.as_bytes();
    let mut at = 0;
    while at < bytes.len() {
        let c = bytes[at];
        let starts_number = c.is_ascii_digit() || c == b'.';
        if starts_number && (at == 0 || !(bytes[at - 1].is_ascii_alphanumeric() || bytes[at - 1] == b'-' || bytes[at - 1] == b'_')) {
            let start = at;
            while at < bytes.len() && (bytes[at].is_ascii_digit() || bytes[at] == b'.') {
                at += 1;
            }
            let number: f64 = value[start..at].parse().unwrap_or(0.0);
            if value[at..].starts_with("px") {
                // A pill is as round as the box allows: it stays one unless the style has no round corner
                let scaled = if number >= 100.0 && scale > 0.0 { number } else { (number * scale).round() };
                out.push_str(&format!("{scaled}px"));
                at += 2;
            } else {
                // 0, or a percentage, em or the like: not a length to scale
                out.push_str(&value[start..at]);
            }
            continue;
        }
        let ch = value[at..].chars().next().unwrap_or(' ');
        out.push(ch);
        at += ch.len_utf8();
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const CAPSULE: Shape = Shape { card: 20.0, window: 18.0 };
    const HAIRLINE: Shape = Shape { card: 6.0, window: 6.0 };
    const TERMINAL: Shape = Shape { card: 0.0, window: 0.0 };

    #[test]
    fn corners_scale_with_the_card() {
        let css = ".a {\n    border-radius: 12px;\n    border-top-left-radius: 8px;\n    padding: 12px;\n}\n";
        assert_eq!(
            shape_css(css, Some(CAPSULE)),
            ".a {\n    border-radius: 20px;\n    border-top-left-radius: 13px;\n    padding: 12px;\n}\n"
        );
        assert_eq!(
            shape_css(css, Some(HAIRLINE)),
            ".a {\n    border-radius: 6px;\n    border-top-left-radius: 4px;\n    padding: 12px;\n}\n"
        );
    }

    #[test]
    fn every_value_of_a_shorthand_is_scaled() {
        let css = "    border-radius: 12px 12px 0 0;\n    border-radius: 0 var(--radius) var(--radius) 0;\n";
        assert_eq!(shape_css(css, Some(CAPSULE)), "    border-radius: 20px 20px 0 0;\n    border-radius: 0 var(--radius) var(--radius) 0;\n");
    }

    #[test]
    fn pills_and_percentages_stay_round_except_in_the_terminal() {
        let css = "    border-radius: 999px;\n    border-radius: 50%;\n    border-radius: 100%;\n";
        assert_eq!(shape_css(css, Some(HAIRLINE)), css);
        assert_eq!(shape_css(css, Some(TERMINAL)), "    border-radius: 0px;\n    border-radius: 50%;\n    border-radius: 100%;\n");
    }

    #[test]
    fn no_style_leaves_the_stylesheet_as_it_is() {
        let css = ".a { border-radius: 12px; }\n";
        assert_eq!(shape_css(css, None), css);
    }

    #[test]
    fn only_corners_are_touched() {
        let css = "    margin: 12px;\n    min-height: 12px; /* radius */\n    box-shadow: 0 0 12px 12px;\n";
        assert_eq!(shape_css(css, Some(CAPSULE)), css);
    }
}
