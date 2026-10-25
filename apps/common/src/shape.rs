//! How round the current desktop style makes the windows' own parts.
//!
//! The apps' stylesheets were ported from the Electron pages, in px corners that are right for the look those pages
//! had. A desktop style (ame desktop style) rounds the rest of the desktop by its own measure, and these windows are
//! part of it: the style says how round a card is, in px, and every corner of a stylesheet is scaled by that over the
//! 16 px the apps draw a card with, so a hairline desktop has crisp windows and a capsule one soft windows, without a
//! stylesheet of its own for each. A corner that is a pill (100 px or more) stays one, a percentage is left as it is,
//! and so is every corner of a square box drawn round (an avatar, a dot, a knob: a radius of half its side), whatever
//! the style, since such a box is a circle by what it is; the terminal style, which has no round corner at all, turns
//! only the pills into squares.

/// The corners of a card in the apps' stylesheets (their `--radius`), which the stylesheets' px were drawn for
const BASELINE: f64 = 16.0;

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
    // One rule at a time: whether a box is a circle depends on its own width and height
    while let Some(open) = css[at..].find('{') {
        let open = at + open;
        let Some(close) = css[open..].find('}') else { break };
        let close = open + close;
        out.push_str(&css[at..=open]);
        out.push_str(&shape_rule(&css[open + 1..close], scale));
        at = close;
    }
    out.push_str(&css[at..]);
    out
}

/// Whether text is inside a comment at a position: the last opening is after the last closing
fn in_comment(text: &str, at: usize) -> bool {
    match (text[..at].rfind("/*"), text[..at].rfind("*/")) {
        (Some(open), Some(close)) => open > close,
        (Some(_), None) => true,
        _ => false,
    }
}

/// The first px length of a declaration's value, and whether it was the whole value of one length
fn first_px(value: &str) -> Option<f64> {
    let number: String = value.trim_start().chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
    let rest = value.trim_start()[number.len()..].trim_start();
    if rest.starts_with("px") { number.parse().ok() } else { None }
}

/// Whether a rule draws a square box round: its width and height are the same px and its radius is half of it or more
fn is_circle(rule: &str) -> bool {
    let (mut width, mut height, mut radius) = (None, None, 0.0f64);
    for declaration in rule.split(';') {
        let Some((name, value)) = declaration.split_once(':') else { continue };
        let name = name.trim();
        let name = name.rsplit(|c: char| c.is_whitespace() || c == '/').next().unwrap_or(name);
        match name {
            "width" | "min-width" => width = first_px(value).or(width),
            "height" | "min-height" => height = first_px(value).or(height),
            _ if name.ends_with("radius") => radius = radius.max(first_px(value).unwrap_or(0.0)),
            _ => {}
        }
    }
    matches!((width, height), (Some(w), Some(h)) if (w - h).abs() < 0.5 && radius * 2.0 >= w - 0.5)
}

/// The corners of one rule's body, scaled; a circle's are left as they are
fn shape_rule(body: &str, scale: f64) -> String {
    let circle = is_circle(body);
    let mut out = String::with_capacity(body.len());
    let mut at = 0;
    while let Some(found) = body[at..].find("radius") {
        let name_end = at + found + "radius".len();
        // A property of that name: a run of letters and dashes ending in "radius", after the start of a declaration
        // (a brace, a semicolon or a line), outside a comment, and followed by its colon
        let name_start = body[..at + found]
            .char_indices()
            .rev()
            .find(|(_, c)| !(c.is_ascii_alphabetic() || *c == '-'))
            .map_or(0, |(i, c)| i + c.len_utf8());
        let before = body[..name_start].trim_end_matches([' ', '\t']);
        let boundary = before.is_empty() || before.ends_with(['{', ';', '\n']);
        let rest = body[name_end..].trim_start_matches([' ', '\t']);
        if boundary && rest.starts_with(':') && !in_comment(body, name_start) {
            let value_start = body.len() - rest.len() + 1;
            let value_end = body[value_start..].find(';').map_or(body.len(), |i| value_start + i);
            out.push_str(&body[at..value_start]);
            out.push_str(&scale_corners(&body[value_start..value_end], scale, circle));
            at = value_end;
        } else {
            out.push_str(&body[at..name_end]);
            at = name_end;
        }
    }
    out.push_str(&body[at..]);
    out
}

/// The px lengths of one declaration's value, scaled
fn scale_corners(value: &str, scale: f64, circle: bool) -> String {
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
                // A circle stays one; a pill is as round as the box allows, and stays one unless the style has no round
                // corner; anything else is scaled
                let scaled = if circle || (number >= 100.0 && scale > 0.0) { number } else { (number * scale).round() };
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

    const ISLANDS: Shape = Shape { card: 16.0, window: 16.0 };
    const CAPSULE: Shape = Shape { card: 20.0, window: 18.0 };
    const HAIRLINE: Shape = Shape { card: 8.0, window: 6.0 };
    const TERMINAL: Shape = Shape { card: 0.0, window: 0.0 };

    #[test]
    fn corners_scale_with_the_card() {
        let css = ".a {\n    border-radius: 16px;\n    border-top-left-radius: 8px;\n    padding: 12px;\n}\n";
        assert_eq!(shape_css(css, Some(ISLANDS)), css);
        assert_eq!(
            shape_css(css, Some(CAPSULE)),
            ".a {\n    border-radius: 20px;\n    border-top-left-radius: 10px;\n    padding: 12px;\n}\n"
        );
        assert_eq!(
            shape_css(css, Some(HAIRLINE)),
            ".a {\n    border-radius: 8px;\n    border-top-left-radius: 4px;\n    padding: 12px;\n}\n"
        );
    }

    #[test]
    fn every_value_of_a_shorthand_is_scaled() {
        let css = ".a {\n    border-radius: 16px 16px 0 0;\n    border-radius: 0 var(--radius) var(--radius) 0;\n}\n";
        assert_eq!(shape_css(css, Some(CAPSULE)), ".a {\n    border-radius: 20px 20px 0 0;\n    border-radius: 0 var(--radius) var(--radius) 0;\n}\n");
    }

    #[test]
    fn pills_and_percentages_stay_round_except_in_the_terminal() {
        let css = ".a {\n    border-radius: 999px;\n    border-radius: 50%;\n    border-radius: 100%;\n}\n";
        assert_eq!(shape_css(css, Some(HAIRLINE)), css);
        assert_eq!(shape_css(css, Some(TERMINAL)), ".a {\n    border-radius: 0px;\n    border-radius: 50%;\n    border-radius: 100%;\n}\n");
    }

    #[test]
    fn a_square_box_drawn_round_stays_a_circle_in_every_style() {
        let css = ".avatar {\n    min-width: 38px;\n    min-height: 38px;\n    border-radius: 19px;\n}\n.dot {\n    width: 9px;\n    height: 9px;\n    border-radius: 5px;\n}\n";
        for shape in [ISLANDS, CAPSULE, HAIRLINE, TERMINAL] {
            assert_eq!(shape_css(css, Some(shape)), css);
        }
        // A pill is not a circle: its width is not its height, and the style rounds it as it does a card
        let pill = ".track {\n    min-width: 46px;\n    min-height: 26px;\n    border-radius: 13px;\n}\n";
        assert_eq!(shape_css(pill, Some(TERMINAL)), ".track {\n    min-width: 46px;\n    min-height: 26px;\n    border-radius: 0px;\n}\n");
        // And a square with a small radius is a card
        let card = ".tile {\n    width: 40px;\n    height: 40px;\n    border-radius: 8px;\n}\n";
        assert_eq!(shape_css(card, Some(CAPSULE)), ".tile {\n    width: 40px;\n    height: 40px;\n    border-radius: 10px;\n}\n");
    }

    #[test]
    fn no_style_leaves_the_stylesheet_as_it_is() {
        let css = ".a { border-radius: 12px; }\n";
        assert_eq!(shape_css(css, None), css);
        // ...and a rule on one line is a declaration like any other
        assert_eq!(shape_css(css, Some(CAPSULE)), ".a { border-radius: 15px; }\n");
    }

    #[test]
    fn only_corners_are_touched() {
        let css = ".a {\n    margin: 12px;\n    min-height: 12px; /* radius */\n    box-shadow: 0 0 12px 12px;\n}\n";
        assert_eq!(shape_css(css, Some(CAPSULE)), css);
        // A comment that looks like a declaration is not one
        let comment = ".a {\n    /*\n    radius: 12px;\n    */\n    padding: 12px;\n}\n";
        assert_eq!(shape_css(comment, Some(CAPSULE)), comment);
    }
}
