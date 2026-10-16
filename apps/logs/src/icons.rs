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
        "list" => &LIST,
        "alert" => &ALERT,
        "user" => &USER,
        "layers" => &LAYERS,
        "chip" => &CHIP,
        "shield" => &SHIELD,
        "crash" => &CRASH,
        "apps" => &APPS,
        "gear" => &GEAR,
        "search" => &SEARCH,
        "close" => &CLOSE,
        "live" => &LIVE,
        "pause" => &PAUSE,
        "download" => &DOWNLOAD,
        "terminal" => &TERMINAL,
        "copy" => &COPY,
        "book" => &BOOK,
        "refresh" => &REFRESH,
        "chevron" => &CHEVRON,
        "chevron-down" => &CHEVRON_DOWN,
        "filter" => &FILTER,
        "target" => &TARGET,
        "sparkle" => &SPARKLE,
        "info" => &INFO,
        "spinner" => &SPINNER,
        _ => &EMPTY,
    }
}

static LIST: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01", fill: false, stroke: true, width: None },
    ],
};

static ALERT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 7.5v5M12 16v.01", fill: false, stroke: true, width: None },
    ],
};

static USER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M8 8a4 4 0 1 0 8 0a4 4 0 1 0 -8 0z", fill: false, stroke: true, width: None },
        Shape { d: "M4.5 20.5a7.5 7.5 0 0 1 15 0", fill: false, stroke: true, width: None },
    ],
};

static LAYERS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3.5l8.5 4.5-8.5 4.5L3.5 8zM3.5 12.5l8.5 4.5 8.5-4.5M3.5 16.5l8.5 4.5 8.5-4.5", fill: false, stroke: true, width: None },
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

static SHIELD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6z", fill: false, stroke: true, width: None },
    ],
};

static CRASH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M13 3L5 13.5h6L10 21l8-10.5h-6z", fill: false, stroke: true, width: None },
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

static GEAR: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1", fill: false, stroke: true, width: None },
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

static LIVE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9.5 12a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0 -5 0z", fill: false, stroke: true, width: None },
        Shape { d: "M7.8 7.8a6 6 0 0 0 0 8.4M16.2 7.8a6 6 0 0 1 0 8.4M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14", fill: false, stroke: true, width: None },
    ],
};

static PAUSE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 5v14M15 5v14", fill: false, stroke: true, width: None },
    ],
};

static DOWNLOAD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 4v11M7 10l5 5 5-5M5 20h14", fill: false, stroke: true, width: None },
    ],
};

static TERMINAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M7 9l3 3-3 3M12.5 15H17", fill: false, stroke: true, width: None },
    ],
};

static COPY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M11 9h7a2 2 0 0 1 2 2v7a2 2 0 0 1 -2 2h-7a2 2 0 0 1 -2 -2v-7a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M5 15V6a2 2 0 0 1 2-2h8", fill: false, stroke: true, width: None },
    ],
};

static BOOK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5zM5 19.5A1.5 1.5 0 0 0 6.5 21H19", fill: false, stroke: true, width: None },
    ],
};

static REFRESH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5", fill: false, stroke: true, width: None },
    ],
};

static CHEVRON: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6l6 6-6 6", fill: false, stroke: true, width: None },
    ],
};

static CHEVRON_DOWN: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 9l6 6 6-6", fill: false, stroke: true, width: None },
    ],
};

static FILTER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 5h16l-6 7.5V19l-4-2v-4.5z", fill: false, stroke: true, width: None },
    ],
};

static TARGET: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 12a8 8 0 1 0 16 0a8 8 0 1 0 -16 0z", fill: false, stroke: true, width: None },
        Shape { d: "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 2v3M12 19v3M2 12h3M19 12h3", fill: false, stroke: true, width: None },
    ],
};

static SPARKLE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 3.5l1.6 4.9 4.9 1.6-4.9 1.6L10 16.5l-1.6-4.9L3.5 10l4.9-1.6zM18 14l.8 2.2 2.2.8-2.2.8L18 20l-.8-2.2L15 17l2.2-.8z", fill: false, stroke: true, width: None },
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
