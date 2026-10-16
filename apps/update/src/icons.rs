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
        "layers" => &LAYERS,
        "apps" => &APPS,
        "terminal" => &TERMINAL,
        "box" => &BOX,
        "download" => &DOWNLOAD,
        "power" => &POWER,
        "refresh" => &REFRESH,
        "clock" => &CLOCK,
        "back" => &BACK,
        "book" => &BOOK,
        "external" => &EXTERNAL,
        "copy" => &COPY,
        "alert" => &ALERT,
        "info" => &INFO,
        "chevron" => &CHEVRON,
        "mark-ok" => &MARK_OK,
        "mark-info" => &MARK_INFO,
        "mark-alert" => &MARK_ALERT,
        "spinner" => &SPINNER,
        "chip" => &CHIP,
        "sparkle" => &SPARKLE,
        _ => &EMPTY,
    }
}

static LAYERS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3.5l8.5 4.5-8.5 4.5L3.5 8zM3.5 12.5l8.5 4.5 8.5-4.5M3.5 16.5l8.5 4.5 8.5-4.5", fill: false, stroke: true, width: None },
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

static TERMINAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M7 9l3 3-3 3M12.5 15H17", fill: false, stroke: true, width: None },
    ],
};

static BOX: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9", fill: false, stroke: true, width: None },
    ],
};

static DOWNLOAD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 4v11M7 10l5 5 5-5M5 20h14", fill: false, stroke: true, width: None },
    ],
};

static POWER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3v8M6.3 6.8a8 8 0 1 0 11.4 0", fill: false, stroke: true, width: None },
    ],
};

static REFRESH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5", fill: false, stroke: true, width: None },
    ],
};

static CLOCK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 7v5l3 2", fill: false, stroke: true, width: None },
    ],
};

static BACK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 14L4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3", fill: false, stroke: true, width: None },
    ],
};

static BOOK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5zM5 19.5A1.5 1.5 0 0 0 6.5 21H19", fill: false, stroke: true, width: None },
    ],
};

static EXTERNAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 4h6v6M20 4l-9 9M18 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4", fill: false, stroke: true, width: None },
    ],
};

static COPY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M11 9h7a2 2 0 0 1 2 2v7a2 2 0 0 1 -2 2h-7a2 2 0 0 1 -2 -2v-7a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M5 15V6a2 2 0 0 1 2-2h8", fill: false, stroke: true, width: None },
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

static CHEVRON: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6l6 6-6 6", fill: false, stroke: true, width: None },
    ],
};

static MARK_OK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 12.5l4.5 4.5L19 7.5", fill: false, stroke: true, width: None },
    ],
};

static MARK_INFO: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 11v6M12 6.5v.01", fill: false, stroke: true, width: None },
    ],
};

static MARK_ALERT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 6.5v7M12 17.5v.01", fill: false, stroke: true, width: None },
    ],
};

static SPINNER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3a9 9 0 1 1-9 9", fill: false, stroke: true, width: None },
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

static SPARKLE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 3.5l1.6 4.9 4.9 1.6-4.9 1.6L10 16.5l-1.6-4.9L3.5 10l4.9-1.6zM18 14l.8 2.2 2.2.8-2.2.8L18 20l-.8-2.2L15 17l2.2-.8z", fill: false, stroke: true, width: None },
    ],
};
