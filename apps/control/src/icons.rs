//! The page's line icons, 24 units square, as path data for amethystora_ui::icon: the sprite the Electron
//! page had, converted. A new icon is its SVG path data, stroked in the CSS colour unless it says otherwise.

use amethystora_ui::icon::{Icon, IconData, Shape, EMPTY};

/// The width every icon is stroked with, as the page's `.icon { stroke-width }` had it
pub const STROKE: f32 = 1.8;

/// An icon by the name it had in the sprite (i-<name>), `size` pixels square
pub fn icon(name: &str, size: i32) -> Icon {
    Icon::new(data(name), size, STROKE)
}

pub fn data(name: &str) -> &'static IconData {
    match name {
        "palette" => &PALETTE,
        "desktop" => &DESKTOP,
        "apps" => &APPS,
        "sparkle" => &SPARKLE,
        "chip" => &CHIP,
        "file" => &FILE,
        "shield" => &SHIELD,
        "refresh" => &REFRESH,
        "archive" => &ARCHIVE,
        "book" => &BOOK,
        "search" => &SEARCH,
        "close" => &CLOSE,
        "terminal" => &TERMINAL,
        "check" => &CHECK,
        "chevron" => &CHEVRON,
        "alert" => &ALERT,
        "info" => &INFO,
        "spinner" => &SPINNER,
        "plus" => &PLUS,
        "trash" => &TRASH,
        "key" => &KEY,
        "external" => &EXTERNAL,
        "copy" => &COPY,
        "wrench" => &WRENCH,
        "disk" => &DISK,
        "gem" => &GEM,
        _ => &EMPTY,
    }
}

static PALETTE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3.5a8.5 8.5 0 0 0 0 17c1.4 0 2-.9 2-1.9 0-1.4-1.2-1.8-1.2-3 0-1.1.9-1.9 2-1.9h2.1c2.1 0 3.6-1.6 3.6-3.6C20.5 6.6 16.7 3.5 12 3.5z", fill: false, stroke: true, width: None },
        Shape { d: "M6.7 11.5a1.1 1.1 0 1 0 2.2 0a1.1 1.1 0 1 0 -2.2 0z", fill: false, stroke: true, width: None },
        Shape { d: "M9.1 7.6a1.1 1.1 0 1 0 2.2 0a1.1 1.1 0 1 0 -2.2 0z", fill: false, stroke: true, width: None },
        Shape { d: "M13.9 7.8a1.1 1.1 0 1 0 2.2 0a1.1 1.1 0 1 0 -2.2 0z", fill: false, stroke: true, width: None },
    ],
};

static DESKTOP: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v8.5a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-8.5a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M8.5 20.5h7M12 16.5v4", fill: false, stroke: true, width: None },
    ],
};

static APPS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 4h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2h-3a2 2 0 0 1 -2 -2v-3a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M15 4h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2h-3a2 2 0 0 1 -2 -2v-3a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M6 13h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2h-3a2 2 0 0 1 -2 -2v-3a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M15 13h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2h-3a2 2 0 0 1 -2 -2v-3a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
    ],
};

static SPARKLE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 3.5l1.6 4.9 4.9 1.6-4.9 1.6L10 16.5l-1.6-4.9L3.5 10l4.9-1.6zM18 14l.8 2.2 2.2.8-2.2.8L18 20l-.8-2.2L15 17l2.2-.8z", fill: false, stroke: true, width: None },
    ],
};

static CHIP: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2v-8a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M10.5 9.5h3a1 1 0 0 1 1 1v3a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1v-3a1 1 0 0 1 1 -1z", fill: false, stroke: true, width: None },
        Shape { d: "M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3", fill: false, stroke: true, width: None },
    ],
};

static FILE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8z", fill: false, stroke: true, width: None },
        Shape { d: "M14 3.5V8h4.5M9 13h6M9 16.5h4", fill: false, stroke: true, width: None },
    ],
};

static SHIELD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6z", fill: false, stroke: true, width: None },
    ],
};

static REFRESH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5", fill: false, stroke: true, width: None },
    ],
};

static ARCHIVE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4.5 4h15a1 1 0 0 1 1 1v2.5a1 1 0 0 1 -1 1h-15a1 1 0 0 1 -1 -1v-2.5a1 1 0 0 1 1 -1z", fill: false, stroke: true, width: None },
        Shape { d: "M5 8.5v10a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5v-10M10 12.5h4", fill: false, stroke: true, width: None },
    ],
};

static BOOK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5zM5 19.5A1.5 1.5 0 0 0 6.5 21H19", fill: false, stroke: true, width: None },
    ],
};

static SEARCH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 10.5a6.5 6.5 0 1 0 13 0a6.5 6.5 0 1 0 -13 0z", fill: false, stroke: true, width: None },
        Shape { d: "M15.5 15.5L20 20", fill: false, stroke: true, width: None },
    ],
};

static CLOSE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 6l12 12M18 6L6 18", fill: false, stroke: true, width: None },
    ],
};

static TERMINAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M7 9l3 3-3 3M12.5 15H17", fill: false, stroke: true, width: None },
    ],
};

static CHECK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 12.5l4.5 4.5L19 7.5", fill: false, stroke: true, width: None },
    ],
};

static CHEVRON: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6l6 6-6 6", fill: false, stroke: true, width: None },
    ],
};

static ALERT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 7.5v5M12 16v.01", fill: false, stroke: true, width: None },
    ],
};

static INFO: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 11v5M12 7.5v.01", fill: false, stroke: true, width: None },
    ],
};

static SPINNER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3a9 9 0 1 1-9 9", fill: false, stroke: true, width: None },
    ],
};

static PLUS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 5v14M5 12h14", fill: false, stroke: true, width: None },
    ],
};

static TRASH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4.5 7h15M10 11v6M14 11v6M6.5 7l1 12.5a1.5 1.5 0 0 0 1.5 1.5h6a1.5 1.5 0 0 0 1.5-1.5l1-12.5M9.5 7V4.5h5V7", fill: false, stroke: true, width: None },
    ],
};

static KEY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 15a4 4 0 1 0 8 0a4 4 0 1 0 -8 0z", fill: false, stroke: true, width: None },
        Shape { d: "M11 12l8.5-8.5M16 7l2.5 2.5M14 9l2 2", fill: false, stroke: true, width: None },
    ],
};

static EXTERNAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 4.5h5.5V10M19.5 4.5L11 13M17.5 14v4a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2h4", fill: false, stroke: true, width: None },
    ],
};

static COPY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M11 9h7a2 2 0 0 1 2 2v7a2 2 0 0 1 -2 2h-7a2 2 0 0 1 -2 -2v-7a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M5 15V6a2 2 0 0 1 2-2h8", fill: false, stroke: true, width: None },
    ],
};

static WRENCH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14.5 4.2a5 5 0 0 0-5.6 6.6L3.8 16a1.9 1.9 0 0 0 2.7 2.7l5.1-5.1a5 5 0 0 0 6.6-5.6l-3 3-2.7-.7-.7-2.7z", fill: false, stroke: true, width: None },
    ],
};

static DISK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5.5 5h13a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-13a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M3.5 13.5h17M7 16.25h.01M10 16.25h.01", fill: false, stroke: true, width: None },
    ],
};

static GEM: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M7 4h10l3.5 5L12 20.5 3.5 9zM3.5 9h17M9.5 4L8 9l4 11.5L16 9l-1.5-5", fill: false, stroke: true, width: None },
    ],
};
