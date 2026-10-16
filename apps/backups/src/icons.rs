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
        "history" => &HISTORY,
        "archive" => &ARCHIVE,
        "shield" => &SHIELD,
        "external" => &EXTERNAL,
        "book" => &BOOK,
        "folder" => &FOLDER,
        "file" => &FILE,
        "link" => &LINK,
        "home" => &HOME,
        "disk" => &DISK,
        "cloud" => &CLOUD,
        "restore" => &RESTORE,
        "eye" => &EYE,
        "layers" => &LAYERS,
        "upload" => &UPLOAD,
        "chevron" => &CHEVRON,
        "back" => &BACK,
        "check" => &CHECK,
        "alert" => &ALERT,
        "info" => &INFO,
        "terminal" => &TERMINAL,
        "sparkle" => &SPARKLE,
        "refresh" => &REFRESH,
        "close" => &CLOSE,
        "copy" => &COPY,
        "spinner" => &SPINNER,
        _ => &EMPTY,
    }
}

static HISTORY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 12a8.5 8.5 0 1 0 2.5-6M3.5 4v4.5H8M12 7.5V12l3 2", fill: false, stroke: true, width: None },
    ],
};

static ARCHIVE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4.5 4h15a1 1 0 0 1 1 1v2.5a1 1 0 0 1 -1 1h-15a1 1 0 0 1 -1 -1v-2.5a1 1 0 0 1 1 -1z", fill: false, stroke: true, width: None },
        Shape { d: "M5 8.5v10a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5v-10M10 12.5h4", fill: false, stroke: true, width: None },
    ],
};

static SHIELD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6z", fill: false, stroke: true, width: None },
    ],
};

static EXTERNAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 4.5h5.5V10M19.5 4.5L11 13M17.5 14v4a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2h4", fill: false, stroke: true, width: None },
    ],
};

static BOOK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5zM5 19.5A1.5 1.5 0 0 0 6.5 21H19", fill: false, stroke: true, width: None },
    ],
};

static FOLDER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 7a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z", fill: false, stroke: true, width: None },
    ],
};

static FILE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8z", fill: false, stroke: true, width: None },
        Shape { d: "M14 3.5V8h4.5", fill: false, stroke: true, width: None },
    ],
};

static LINK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1", fill: false, stroke: true, width: None },
    ],
};

static HOME: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 10.5L12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5h-4v-6h-5v6h-4A1.5 1.5 0 0 1 4 19z", fill: false, stroke: true, width: None },
    ],
};

static DISK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5.5 5h13a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-13a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M3.5 13.5h17M7 16.25h.01M10 16.25h.01", fill: false, stroke: true, width: None },
    ],
};

static CLOUD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M7 18.5a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.5 1.6A3.75 3.75 0 0 1 17.25 18.5z", fill: false, stroke: true, width: None },
    ],
};

static RESTORE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 14L4.5 9.5 9 5M4.5 9.5h10a5 5 0 0 1 0 10H11", fill: false, stroke: true, width: None },
    ],
};

static EYE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z", fill: false, stroke: true, width: None },
        Shape { d: "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", fill: false, stroke: true, width: None },
    ],
};

static LAYERS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3.5l8.5 4.5-8.5 4.5L3.5 8zM3.5 12.5l8.5 4.5 8.5-4.5M3.5 16.5l8.5 4.5 8.5-4.5", fill: false, stroke: true, width: None },
    ],
};

static UPLOAD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 15V4M7 9l5-5 5 5M5 15v3.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V15", fill: false, stroke: true, width: None },
    ],
};

static CHEVRON: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6l6 6-6 6", fill: false, stroke: true, width: None },
    ],
};

static BACK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M15 6l-6 6 6 6", fill: false, stroke: true, width: None },
    ],
};

static CHECK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 12.5l4.5 4.5L19 7.5", fill: false, stroke: true, width: None },
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

static TERMINAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M7 9l3 3-3 3M12.5 15H17", fill: false, stroke: true, width: None },
    ],
};

static SPARKLE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 3.5l1.6 4.9 4.9 1.6-4.9 1.6L10 16.5l-1.6-4.9L3.5 10l4.9-1.6zM18 14l.8 2.2 2.2.8-2.2.8L18 20l-.8-2.2L15 17l2.2-.8z", fill: false, stroke: true, width: None },
    ],
};

static REFRESH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5", fill: false, stroke: true, width: None },
    ],
};

static CLOSE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 6l12 12M18 6L6 18", fill: false, stroke: true, width: None },
    ],
};

static COPY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M11 9h7a2 2 0 0 1 2 2v7a2 2 0 0 1 -2 2h-7a2 2 0 0 1 -2 -2v-7a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M5 15V6a2 2 0 0 1 2-2h8", fill: false, stroke: true, width: None },
    ],
};

static SPINNER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3a9 9 0 1 1-9 9", fill: false, stroke: true, width: None },
    ],
};
