//! A note as a PDF, as the page's print sheet had it: its title, then its Markdown in black on white, with
//! the sheet's own colours (print-sheet in notes.css), printed by gtk::PrintOperation to the file chosen.
//! Chromium laid the sheet out as HTML and printed that; here the Markdown is laid out with Pango, block by
//! block, and the blocks go onto the pages a line at a time, so a long paragraph or code block runs on to
//! the next page as it did there. Pictures are the attachments', decrypted for this and nowhere kept.

use std::cell::RefCell;
use std::collections::HashMap;
use std::path::Path;
use std::rc::Rc;

use amethystora_ui::{gdk, glib, gtk, pango};
use gtk::cairo;
use gtk::prelude::*;
use pulldown_cmark::{Event, HeadingLevel, Options, Parser, Tag, TagEnd};

/// The sheet's colours: --fg, --soft, --link, --line and the accent of a quote's bar. Its --code-bg is not
/// here: main.js printed with printBackground false, which left out every background, code's among them
const FG: &str = "#000000";
const SOFT: &str = "#333333";
const LINK: &str = "#3b1a86";
const FAINT: &str = "#666666";
const LINE: (f64, f64, f64) = (0.8, 0.8, 0.8);
const ACCENT: (f64, f64, f64) = (0.365, 0.102, 0.769);
const LINK_RGB: (f32, f32, f32) = (0.231, 0.102, 0.525);

/// A task's box, as the marker of its item
const CHECKED: &str = "☑";
const UNCHECKED: &str = "☐";

/// Stand-ins in the text for room the sheet gave that Pango markup cannot: each is laid out as an empty
/// shape its width wide. An attachment's start (its border, padding, clip and the gap after it), its end
/// (padding and border), and inline code's padding either side
const CHIP_OPEN: char = '\u{E000}';
const CHIP_CLOSE: char = '\u{E001}';
const CODE_PAD: char = '\u{E002}';

/// a.attachment: 1px border, 9px padding, a 14px clip and a gap of 5px; 27.5px tall as Chromium drew it
const CHIP_START: f64 = 29.0;
const CHIP_END: f64 = 10.0;
const CHIP_HEIGHT: f64 = 27.5;

/// The clip's path, as the sprite had it (i-clip)
const CLIP: &str = "M20 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1L13 4.3a3.3 3.3 0 0 1 4.7 4.7l-8.3 8.3a1.7 1.7 0 0 1-2.4-2.4L14.6 7.3";

/// CSS pixels in points, which the PDF is measured in
fn pt(px: f64) -> f64 {
    px * 0.75
}

#[derive(Clone)]
enum Kind {
    Text,
    Code,
    Rule,
    Picture(gdk::Texture),
}

/// A block of the sheet: what it says, in Pango markup, how big, where, and what is drawn around it
#[derive(Clone)]
struct Block {
    kind: Kind,
    markup: String,
    /// Its font size and line height, in CSS pixels
    size: f64,
    line: f64,
    family: &'static str,
    bold: bool,
    color: &'static str,
    /// How far in from the left, and the marker of a list's item drawn there
    indent: f64,
    marker: Option<String>,
    quote: bool,
    /// Room inside its frame or a quote's bar, above its first line and under its last
    pad_top: f64,
    pad_bottom: f64,
    /// How far up its bar reaches past its own padding: the margin between two paragraphs of one quote
    bar_above: f64,
    top: f64,
    bottom: f64,
}

impl Block {
    fn text(markup: String, size: f64, line: f64) -> Block {
        Block { kind: Kind::Text, markup, size, line, family: "Inter, Adwaita Sans, Cantarell, sans-serif", bold: false, color: FG, indent: 0.0, marker: None, quote: false, pad_top: 0.0, pad_bottom: 0.0, bar_above: 0.0, top: 0.0, bottom: 12.75 }
    }
}

/// The note's Markdown as the sheet's blocks
fn blocks(title: &str, body: &str, pictures: &HashMap<String, gdk::Texture>) -> Vec<Block> {
    let mut out = Vec::new();
    // .print-sheet > h1 { margin: 0 0 0.6em; font: 700 26px/1.25 var(--display) }
    let mut heading = Block::text(glib::markup_escape_text(title).to_string(), 26.0, 32.5);
    heading.family = "Quicksand, Inter, sans-serif";
    heading.bold = true;
    // .markdown > :first-child, which the sheet is, outweighs that margin of 0 above: 0.4em
    heading.top = 10.4;
    heading.bottom = 15.6;
    out.push(heading);
    let mut inline = String::new();
    let mut lists: Vec<Option<u64>> = Vec::new();
    let mut item_marker: Option<String> = None;
    let mut quote = 0;
    let mut quote_opened = false;
    let mut code: Option<String> = None;
    let mut heading_level: Option<HeadingLevel> = None;
    let mut image: Option<(String, String)> = None;
    let mut cell = false;
    let mut links: Vec<bool> = Vec::new();
    let flush = |inline: &mut String, out: &mut Vec<Block>, lists: &[Option<u64>], marker: &mut Option<String>, quote: usize, heading: Option<HeadingLevel>, opened: &mut bool| {
        if inline.trim().is_empty() {
            inline.clear();
            return;
        }
        let mut block = Block::text(std::mem::take(inline), 15.0, 25.5);
        if let Some(level) = heading {
            let (size, top, bottom) = match level {
                HeadingLevel::H1 => (25.5, 33.15, 11.475),
                HeadingLevel::H2 => (21.0, 27.3, 9.45),
                HeadingLevel::H3 => (17.7, 23.01, 7.965),
                _ => (15.3, 19.89, 6.885),
            };
            block.size = size;
            block.line = size * 1.3;
            block.top = top;
            block.bottom = bottom;
            block.family = "Quicksand, Inter, sans-serif";
            block.bold = true;
        }
        if !lists.is_empty() {
            block.indent = 22.5 * lists.len() as f64;
            block.marker = marker.take();
            block.bottom = 2.25;
        }
        if quote > 0 {
            block.quote = true;
            block.color = SOFT;
            block.indent += 17.0 * quote as f64;
            if std::mem::take(opened) {
                block.pad_top = 2.0;
            } else {
                block.bar_above = 12.75;
            }
        }
        // li:has(> input[type="checkbox"]): 1.4em back from the list's 1.5em, then the box and its 8px
        match block.marker.as_deref() {
            Some(CHECKED) => {
                block.markup = format!("<s>{}</s>", block.markup);
                block.color = FAINT;
                block.indent += 2.0;
            }
            Some(UNCHECKED) => block.indent += 2.0,
            _ => {}
        }
        out.push(block);
    };
    for event in Parser::new_ext(body, Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH | Options::ENABLE_TASKLISTS) {
        match event {
            Event::Start(Tag::Heading { level, .. }) => heading_level = Some(level),
            Event::End(TagEnd::Heading(_)) => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, heading_level, &mut quote_opened);
                heading_level = None;
            }
            Event::End(TagEnd::Paragraph) => flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened),
            Event::Start(Tag::BlockQuote(_)) => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                quote += 1;
                quote_opened = true;
            }
            Event::End(TagEnd::BlockQuote(_)) => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                quote = quote.saturating_sub(1);
                quote_opened = false;
                if let Some(last) = out.last_mut().filter(|block| block.quote) {
                    last.pad_bottom = 2.0 + last.bottom;
                    last.bottom = 12.75;
                }
            }
            Event::Start(Tag::List(start)) => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                lists.push(start);
            }
            Event::End(TagEnd::List(_)) => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                lists.pop();
                if let Some(last) = out.last_mut() {
                    last.bottom = 12.75;
                }
            }
            Event::Start(Tag::Item) => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                item_marker = Some(match lists.last_mut() {
                    Some(Some(number)) => {
                        let marker = format!("{number}.");
                        *number += 1;
                        marker
                    }
                    _ => "•".into(),
                });
            }
            Event::End(TagEnd::Item) => flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened),
            Event::TaskListMarker(done) => item_marker = Some(if done { CHECKED.into() } else { UNCHECKED.into() }),
            Event::Start(Tag::CodeBlock(_)) => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                code = Some(String::new());
            }
            Event::End(TagEnd::CodeBlock) => {
                let text = code.take().unwrap_or_default();
                // 13px code on the pre's own line of 15px at 1.7, which its lines are as far apart as
                let mut block = Block::text(glib::markup_escape_text(text.trim_end_matches('\n')).to_string(), 13.0, 25.5);
                block.kind = Kind::Code;
                block.pad_top = 12.0;
                block.pad_bottom = 12.0;
                block.family = "JetBrains Mono, Adwaita Mono, monospace";
                out.push(block);
            }
            Event::Rule => {
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                let mut block = Block::text(String::new(), 1.0, 1.0);
                block.kind = Kind::Rule;
                block.top = 24.0;
                block.bottom = 24.0;
                out.push(block);
            }
            Event::Start(Tag::TableCell) => {
                if cell {
                    inline.push('\t');
                }
                cell = true;
            }
            Event::End(TagEnd::TableHead | TagEnd::TableRow) => {
                cell = false;
                flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                if let Some(last) = out.last_mut() {
                    last.bottom = 4.0;
                }
            }
            Event::End(TagEnd::Table) => {
                if let Some(last) = out.last_mut() {
                    last.bottom = 12.75;
                }
            }
            Event::Text(text) => match (&mut code, &mut image) {
                (Some(code), _) => code.push_str(&text),
                (_, Some((_, alt))) => alt.push_str(&text),
                _ => inline.push_str(&glib::markup_escape_text(&text)),
            },
            Event::Code(text) => inline.push_str(&format!("<span font_family=\"JetBrains Mono, Adwaita Mono, monospace\" size=\"88%\">{CODE_PAD}{}{CODE_PAD}</span>", glib::markup_escape_text(&text))),
            // Raw HTML is shown as the text it is
            Event::Html(text) | Event::InlineHtml(text) => match &mut code {
                Some(code) => code.push_str(&text),
                None => inline.push_str(&glib::markup_escape_text(&text)),
            },
            Event::SoftBreak | Event::HardBreak => inline.push('\n'),
            Event::Start(Tag::Emphasis) => inline.push_str("<i>"),
            Event::End(TagEnd::Emphasis) => inline.push_str("</i>"),
            Event::Start(Tag::Strong) => inline.push_str("<b>"),
            Event::End(TagEnd::Strong) => inline.push_str("</b>"),
            Event::Start(Tag::Strikethrough) => inline.push_str("<s>"),
            Event::End(TagEnd::Strikethrough) => inline.push_str("</s>"),
            // A link to an attachment is the page's chip: its name in the link's colour, framed, with the clip
            Event::Start(Tag::Link { dest_url, .. }) => {
                let chip = dest_url.starts_with(":/");
                links.push(chip);
                if chip {
                    inline.push(CHIP_OPEN);
                    inline.push_str(&format!("<span foreground=\"{LINK}\">"));
                } else {
                    inline.push_str(&format!("<span foreground=\"{LINK}\" underline=\"single\">"));
                }
            }
            Event::End(TagEnd::Link) => {
                inline.push_str("</span>");
                if links.pop() == Some(true) {
                    inline.push(CHIP_CLOSE);
                }
            }
            Event::Start(Tag::Image { dest_url, .. }) => image = Some((dest_url.to_string(), String::new())),
            Event::End(TagEnd::Image) => {
                let Some((url, alt)) = image.take() else { continue };
                let href = match url.strip_prefix(":/") {
                    Some(id) => format!("res://{id}/"),
                    None => url.clone(),
                };
                match pictures.get(&href).cloned().or_else(|| data_image(&href)) {
                    Some(texture) => {
                        flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
                        let mut block = Block::text(String::new(), 15.0, 25.5);
                        block.kind = Kind::Picture(texture);
                        out.push(block);
                    }
                    None => inline.push_str(&glib::markup_escape_text(&alt)),
                }
            }
            _ => {}
        }
    }
    flush(&mut inline, &mut out, &lists, &mut item_marker, quote, None, &mut quote_opened);
    out
}

/// A picture written into the note as a data: address
fn data_image(href: &str) -> Option<gdk::Texture> {
    let (_, encoded) = href.strip_prefix("data:image/")?.split_once(";base64,")?;
    gdk::Texture::from_bytes(&glib::Bytes::from_owned(crate::vault::unbase64(encoded))).ok()
}

/// A block laid out at the page's width
struct Laid {
    block: Block,
    layout: Option<pango::Layout>,
    marker: Option<pango::Layout>,
    /// The tops and heights of its lines, in points, from its own top
    lines: Vec<(f64, f64)>,
    height: f64,
    /// Its attachments' frames: on which line, from where to where, in points from the text's left
    chips: Vec<(usize, f64, f64)>,
    /// From the top of its first line down to that line's baseline, in points
    baseline: f64,
}

fn lay_out(context: &gtk::PrintContext, block: Block, width: f64) -> Laid {
    let padding = match block.kind {
        Kind::Code => pt(14.0) * 2.0,
        _ => 0.0,
    };
    let inner = width - pt(block.indent) - padding;
    match &block.kind {
        Kind::Rule => Laid { block, layout: None, marker: None, lines: vec![(0.0, pt(1.0))], height: pt(1.0), chips: Vec::new(), baseline: 0.0 },
        Kind::Picture(texture) => {
            let scale = (inner / pt(texture.width() as f64)).min(1.0);
            // The picture sits on its paragraph's baseline: under it the rest of a 25.5px line of 15px Inter
            let height = pt(texture.height() as f64) * scale + pt((25.5 - 15.0 * 1.21) / 2.0 + 15.0 * 0.241);
            Laid { block, layout: None, marker: None, lines: vec![(0.0, height)], height, chips: Vec::new(), baseline: 0.0 }
        }
        _ => {
            let mut font = pango::FontDescription::from_string(block.family);
            font.set_size((pt(block.size) * pango::SCALE as f64) as i32);
            if block.bold {
                font.set_weight(pango::Weight::Bold);
            }
            // Each line as tall as the stylesheet's line-height made it: in 1024ths of a point, as Pango takes
            // a height (a factor would scale the font's own line height, which CSS does not)
            let line_height = (pt(block.line) * pango::SCALE as f64).round() as i64;
            let markup = format!("<span foreground=\"{}\" line_height=\"{line_height}\">{}</span>", block.color, block.markup);
            let layout = context.create_pango_layout();
            layout.set_font_description(Some(&font));
            layout.set_width((inner * pango::SCALE as f64) as i32);
            layout.set_wrap(pango::WrapMode::WordChar);
            layout.set_markup(&markup);
            let chips = make_room(&layout, &font, block.size);
            let padding_top = pt(block.pad_top);
            let mut lines = Vec::new();
            let mut iter = layout.iter();
            loop {
                let (_, logical) = iter.line_extents();
                lines.push((padding_top + logical.y() as f64 / pango::SCALE as f64, logical.height() as f64 / pango::SCALE as f64));
                if !iter.next_line() {
                    break;
                }
            }
            let height = lines.last().map(|(y, h)| y + h).unwrap_or(0.0) + pt(block.pad_bottom);
            let marker = block.marker.as_ref().map(|marker| {
                let layout = context.create_pango_layout();
                layout.set_font_description(Some(&font));
                layout.set_markup(&format!("<span foreground=\"{}\" line_height=\"{line_height}\">{}</span>", block.color, glib::markup_escape_text(marker)));
                layout
            });
            let baseline = layout.baseline() as f64 / pango::SCALE as f64 - lines.first().map(|(y, _)| y - padding_top).unwrap_or(0.0);
            Laid { block, layout: Some(layout), marker, lines, height, chips, baseline }
        }
    }
}

/// The stand-ins as empty shapes of their widths, and the frames of the attachments between them
fn make_room(layout: &pango::Layout, font: &pango::FontDescription, size: f64) -> Vec<(usize, f64, f64)> {
    let text = layout.text();
    // As tall as the font's own runs, so that the line height spreads over them alike
    let metrics = layout.context().metrics(Some(font), None);
    let (ascent, descent) = (metrics.ascent(), metrics.descent());
    let attrs = layout.attributes().unwrap_or_default();
    let mut opens = Vec::new();
    let mut chips = Vec::new();
    let mut found = false;
    for (at, c) in text.char_indices() {
        let width = match c {
            CHIP_OPEN => CHIP_START,
            CHIP_CLOSE => CHIP_END,
            // padding: 0.1em 0.35em, of the code's 0.88em
            CODE_PAD => 0.35 * 0.88 * size,
            _ => continue,
        };
        found = true;
        let units = (pt(width) * pango::SCALE as f64).round() as i32;
        let rect = pango::Rectangle::new(0, -ascent, units, ascent + descent);
        let mut shape = pango::AttrShape::new(&rect, &rect);
        shape.set_start_index(at as u32);
        shape.set_end_index((at + c.len_utf8()) as u32);
        attrs.insert(shape);
        match c {
            CHIP_OPEN => opens.push(at as i32),
            CHIP_CLOSE => {
                if let Some(open) = opens.pop() {
                    chips.push((open, at as i32, units));
                }
            }
            _ => {}
        }
    }
    if !found {
        return Vec::new();
    }
    layout.set_attributes(Some(&attrs));
    let units = |n: i32| n as f64 / pango::SCALE as f64;
    let mut frames = Vec::new();
    for (open, close, end) in chips {
        let (first, x0) = layout.index_to_line_x(open, false);
        let (last, x1) = layout.index_to_line_x(close, false);
        let (first, last) = (first.max(0) as usize, last.max(0) as usize);
        if first == last {
            let (a, b) = (x0.min(x1 + end), x0.max(x1 + end));
            frames.push((first, units(a), units(b)));
        } else {
            // Cut by the end of a line: framed to the line's end, and from its start on the next
            let right = layout.line_readonly(first as i32).map(|line| line.extents().1.width()).unwrap_or(x0);
            frames.push((first, units(x0), units(right)));
            frames.push((last, 0.0, units(x1 + end)));
        }
    }
    frames
}

/// A rectangle with rounded corners, square where a page cut it
fn rounded(cairo: &cairo::Context, x: f64, y: f64, w: f64, h: f64, top: f64, bottom: f64) {
    use std::f64::consts::{FRAC_PI_2, PI};
    cairo.new_sub_path();
    cairo.arc(x + w - top, y + top, top, -FRAC_PI_2, 0.0);
    cairo.arc(x + w - bottom, y + h - bottom, bottom, 0.0, FRAC_PI_2);
    cairo.arc(x + bottom, y + h - bottom, bottom, FRAC_PI_2, PI);
    cairo.arc(x + top, y + top, top, PI, PI + FRAC_PI_2);
    cairo.close_path();
}

/// A task's box as Chromium printed it: 15px, a grey frame, or grey with a light tick when done
fn task_box(cairo: &cairo::Context, x: f64, y: f64, checked: bool) {
    let side = pt(15.0);
    let grey = 208.0 / 255.0;
    cairo.save().ok();
    if checked {
        rounded(cairo, x, y, side, side, pt(2.0), pt(2.0));
        cairo.set_source_rgb(grey, grey, grey);
        let _ = cairo.fill();
        let light = 236.0 / 255.0;
        cairo.set_source_rgb(light, light, light);
        cairo.set_line_width(pt(2.2));
        cairo.set_line_cap(cairo::LineCap::Round);
        cairo.set_line_join(cairo::LineJoin::Round);
        cairo.move_to(x + side * 0.24, y + side * 0.53);
        cairo.line_to(x + side * 0.42, y + side * 0.71);
        cairo.line_to(x + side * 0.77, y + side * 0.31);
        let _ = cairo.stroke();
    } else {
        let inset = pt(0.5);
        rounded(cairo, x + inset, y + inset, side - 2.0 * inset, side - 2.0 * inset, pt(2.0), pt(2.0));
        let fill = 248.0 / 255.0;
        cairo.set_source_rgb(fill, fill, fill);
        let _ = cairo.fill_preserve();
        cairo.set_source_rgb(grey, grey, grey);
        cairo.set_line_width(pt(1.0));
        let _ = cairo.stroke();
    }
    cairo.restore().ok();
}

/// An attachment's frame and its clip, the frame centred on its line
fn chip(cairo: &cairo::Context, x0: f64, x1: f64, middle: f64) {
    let height = pt(CHIP_HEIGHT);
    let inset = pt(0.5);
    cairo.save().ok();
    rounded(cairo, x0 + inset, middle - height / 2.0 + inset, x1 - x0 - 2.0 * inset, height - 2.0 * inset, pt(8.0), pt(8.0));
    cairo.set_source_rgb(LINE.0, LINE.1, LINE.2);
    cairo.set_line_width(pt(1.0));
    let _ = cairo.stroke();
    cairo.restore().ok();
    let Ok(path) = gtk::gsk::Path::parse(CLIP) else { return };
    let side = pt(14.0);
    let snapshot = gtk::Snapshot::new();
    snapshot.translate(&gtk::graphene::Point::new((x0 + pt(10.0)) as f32, (middle - side / 2.0) as f32));
    snapshot.scale(side as f32 / 24.0, side as f32 / 24.0);
    let stroke = gtk::gsk::Stroke::new(crate::icons::STROKE);
    stroke.set_line_cap(gtk::gsk::LineCap::Round);
    stroke.set_line_join(gtk::gsk::LineJoin::Round);
    snapshot.append_stroke(&path, &stroke, &gdk::RGBA::new(LINK_RGB.0, LINK_RGB.1, LINK_RGB.2, 1.0));
    if let Some(node) = snapshot.to_node() {
        node.draw(cairo);
    }
}

/// Where a piece of a block goes: on which page, at what height, and which of its lines
struct Piece {
    block: usize,
    page: usize,
    y: f64,
    from: usize,
    to: usize,
}

fn paginate(laid: &[Laid], page_height: f64) -> (Vec<Piece>, usize) {
    let mut pieces = Vec::new();
    let mut page = 0;
    let mut y: f64 = 0.0;
    let mut last_bottom: f64 = 0.0;
    for (at, block) in laid.iter().enumerate() {
        // Margins collapse, as HTML's do; none at the top of a page but the first
        let gap = if at == 0 { pt(block.block.top) } else if y == 0.0 { 0.0 } else { pt(block.block.top).max(last_bottom) };
        y += gap;
        let splittable = matches!(block.block.kind, Kind::Text | Kind::Code);
        if !splittable || block.lines.len() == 1 {
            if y + block.height > page_height && y > 0.0 {
                page += 1;
                y = 0.0;
            }
            pieces.push(Piece { block: at, page, y, from: 0, to: block.lines.len() });
            y += block.height;
        } else {
            let mut from = 0;
            let count = block.lines.len();
            let pad_bottom = pt(block.block.pad_bottom);
            while from < count {
                // The first piece from the top of its padding, the others from their first line
                let start = if from == 0 { 0.0 } else { block.lines[from].0 };
                let mut to = from;
                while to < count && y + (block.lines[to].0 + block.lines[to].1 - start) + if to + 1 == count { pad_bottom } else { 0.0 } <= page_height {
                    to += 1;
                }
                if to == from {
                    if y > 0.0 {
                        page += 1;
                        y = 0.0;
                        continue;
                    }
                    to = from + 1;
                }
                pieces.push(Piece { block: at, page, y: y - start, from, to });
                let end = block.lines[to - 1].0 + block.lines[to - 1].1;
                if to < block.lines.len() {
                    page += 1;
                    y = 0.0;
                } else {
                    y += end - start + pad_bottom;
                }
                from = to;
            }
        }
        last_bottom = pt(block.block.bottom);
    }
    (pieces, page + 1)
}

/// A Pango layout drawn onto the page through a GSK text node, at x and y
fn show(cairo: &cairo::Context, layout: &pango::Layout, x: f64, y: f64) {
    let snapshot = gtk::Snapshot::new();
    snapshot.append_layout(layout, &gdk::RGBA::BLACK);
    if let Some(node) = snapshot.to_node() {
        cairo.save().ok();
        cairo.translate(x, y);
        node.draw(cairo);
        cairo.restore().ok();
    }
}

fn draw(cairo: &cairo::Context, laid: &Laid, piece: &Piece, width: f64) {
    let x = pt(laid.block.indent);
    let top = piece.y + laid.lines[piece.from].0;
    let bottom = piece.y + laid.lines[piece.to - 1].0 + laid.lines[piece.to - 1].1;
    match &laid.block.kind {
        // An hr is its background, which printBackground false left out: only its room is kept
        Kind::Rule => return,
        Kind::Picture(texture) => {
            let (w, h) = (texture.width(), texture.height());
            let stride = w as usize * 4;
            let mut bytes = vec![0u8; stride * h as usize];
            texture.download(&mut bytes, stride);
            if let Ok(surface) = cairo::ImageSurface::create_for_data(bytes, cairo::Format::ARgb32, w, h, stride as i32) {
                let scale = ((width - x) / w as f64).min(pt(1.0));
                cairo.save().ok();
                // border-radius: 8px
                rounded(cairo, x, piece.y, w as f64 * scale, h as f64 * scale, pt(8.0), pt(8.0));
                cairo.clip();
                cairo.translate(x, piece.y);
                cairo.scale(scale, scale);
                let _ = cairo.set_source_surface(&surface, 0.0, 0.0);
                let _ = cairo.paint();
                cairo.restore().ok();
            }
            return;
        }
        Kind::Code => {
            let pad_top = if piece.from == 0 { pt(laid.block.pad_top) } else { 0.0 };
            let pad_bottom = if piece.to == laid.lines.len() { pt(laid.block.pad_bottom) } else { 0.0 };
            // border-radius: 10px, square where the page cut it
            let inset = pt(0.5);
            let (round_top, round_bottom) = (if piece.from == 0 { pt(10.0) } else { 0.0 }, if piece.to == laid.lines.len() { pt(10.0) } else { 0.0 });
            rounded(cairo, x + inset, top - pad_top + inset, width - x - 2.0 * inset, bottom - top + pad_top + pad_bottom - 2.0 * inset, round_top, round_bottom);
            cairo.set_source_rgb(LINE.0, LINE.1, LINE.2);
            cairo.set_line_width(pt(1.0));
            let _ = cairo.stroke();
        }
        Kind::Text => {}
    }
    if laid.block.quote {
        // From the quote's padding, or from the paragraph above in it, to its padding under the last
        let above = if piece.from == 0 { pt(laid.block.pad_top + laid.block.bar_above) } else { 0.0 };
        let below = if piece.to == laid.lines.len() { pt(laid.block.pad_bottom) } else { 0.0 };
        cairo.set_source_rgba(ACCENT.0, ACCENT.1, ACCENT.2, 0.55);
        cairo.rectangle(x - pt(17.0), top - above, pt(3.0), bottom - top + above + below);
        let _ = cairo.fill();
    }
    let Some(layout) = &laid.layout else { return };
    let text_x = x + if matches!(laid.block.kind, Kind::Code) { pt(14.0) } else { 0.0 };
    let padding_top = pt(laid.block.pad_top);
    // Only this piece's lines: the whole layout, clipped to them
    cairo.save().ok();
    cairo.rectangle(0.0, top, width + pt(40.0), bottom - top);
    cairo.clip();
    show(cairo, layout, text_x, piece.y + padding_top);
    cairo.restore().ok();
    for (line, x0, x1) in laid.chips.iter().filter(|(line, _, _)| (piece.from..piece.to).contains(line)) {
        let (y, height) = laid.lines[*line];
        chip(cairo, text_x + x0, text_x + x1, piece.y + y + height / 2.0);
    }
    if piece.from != 0 {
        return;
    }
    match laid.block.marker.as_deref() {
        // vertical-align: -2px: the box's foot two pixels under the baseline
        Some(mark @ (CHECKED | UNCHECKED)) => {
            task_box(cairo, x - pt(23.0), piece.y + laid.lines[0].0 + laid.baseline + pt(2.0) - pt(15.0), mark == CHECKED);
        }
        _ => {
            if let Some(marker) = &laid.marker {
                show(cairo, marker, x - pt(18.0), piece.y + laid.lines[0].0);
            }
        }
    }
}

/// The note printed to a PDF at `file`
pub fn pdf(window: &impl IsA<gtk::Window>, title: &str, body: &str, pictures: &HashMap<String, gdk::Texture>, file: &Path) -> Result<(), String> {
    let sheet = blocks(title, body, pictures);
    let operation = gtk::PrintOperation::new();
    operation.set_export_filename(file);
    operation.set_unit(gtk::Unit::Points);
    // printToPDF's defaults: US Letter, whatever the language, and margins of about a centimetre
    let setup = gtk::PageSetup::new();
    setup.set_paper_size(&gtk::PaperSize::new(Some("na_letter")));
    setup.set_top_margin(28.35, gtk::Unit::Points);
    setup.set_bottom_margin(28.35, gtk::Unit::Points);
    setup.set_left_margin(28.35, gtk::Unit::Points);
    setup.set_right_margin(28.35, gtk::Unit::Points);
    operation.set_default_page_setup(Some(&setup));
    let state: Rc<RefCell<(Vec<Laid>, Vec<Piece>)>> = Rc::new(RefCell::new((Vec::new(), Vec::new())));
    let begin = state.clone();
    operation.connect_begin_print(move |operation, context| {
        let width = context.width();
        let height = context.height();
        let laid: Vec<Laid> = sheet.iter().cloned().map(|block| lay_out(context, block, width)).collect();
        let (pieces, pages) = paginate(&laid, height);
        operation.set_n_pages(pages as i32);
        begin.replace((laid, pieces));
    });
    let drawing = state.clone();
    operation.connect_draw_page(move |_, context, page| {
        let cairo = context.cairo_context();
        let width = context.width();
        let state = drawing.borrow();
        for piece in state.1.iter().filter(|piece| piece.page == page as usize) {
            draw(&cairo, &state.0[piece.block], piece, width);
        }
    });
    match operation.run(gtk::PrintOperationAction::Export, Some(window)) {
        Ok(_) => Ok(()),
        Err(error) => Err(error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The blocks as Chromium laid the sheet out (checked against a PDF main.js printed, 2026-10-16)
    #[test]
    fn lays_out_the_sheet_as_chromium_did() {
        let body = "- [x] flour\n- [ ] eggs\n- a pinch of `salt`\n\n> Let it rest.\n\n```\nheat: medium\n```\n\n[shopping list](:/0123456789abcdef0123456789abcdef) and [a site](https://example.org)\n\n---\n";
        let sheet = blocks("Sunday pancakes", body, &HashMap::new());
        let title = &sheet[0];
        assert_eq!((title.size, title.line, title.top, title.bottom), (26.0, 32.5, 10.4, 15.6));
        let done = &sheet[1];
        assert_eq!((done.marker.as_deref(), done.color, done.indent), (Some(CHECKED), FAINT, 24.5));
        assert!(done.markup.starts_with("<s>"));
        let open = &sheet[2];
        assert_eq!((open.marker.as_deref(), open.color, open.indent), (Some(UNCHECKED), FG, 24.5));
        assert!(!open.markup.contains("<s>"));
        let bullet = &sheet[3];
        assert_eq!((bullet.marker.as_deref(), bullet.indent, bullet.bottom), (Some("•"), 22.5, 12.75));
        assert!(bullet.markup.contains(&format!("{CODE_PAD}salt{CODE_PAD}")));
        let quote = &sheet[4];
        assert!(quote.quote);
        assert_eq!((quote.color, quote.pad_top, quote.pad_bottom, quote.bottom), (SOFT, 2.0, 14.75, 12.75));
        let code = &sheet[5];
        assert!(matches!(code.kind, Kind::Code));
        assert_eq!((code.size, code.line, code.pad_top, code.pad_bottom), (13.0, 25.5, 12.0, 12.0));
        let links = &sheet[6];
        assert!(links.markup.contains(&format!("{CHIP_OPEN}<span foreground=\"{LINK}\">shopping list</span>{CHIP_CLOSE}")));
        assert!(links.markup.contains("underline=\"single\">a site</span>"));
        assert!(matches!(sheet[7].kind, Kind::Rule));
        assert_eq!(sheet.len(), 8);
    }
}
