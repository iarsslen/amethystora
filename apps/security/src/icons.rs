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
        "shield" => &SHIELD,
        "shield-alert" => &SHIELD_ALERT,
        "scan" => &SCAN,
        "book" => &BOOK,
        "refresh" => &REFRESH,
        "file" => &FILE,
        "file-alert" => &FILE_ALERT,
        "alert" => &ALERT,
        "info" => &INFO,
        "mark-ok" => &MARK_OK,
        "mark-info" => &MARK_INFO,
        "mark-alert" => &MARK_ALERT,
        "arrow-right" => &ARROW_RIGHT,
        "arrow-left" => &ARROW_LEFT,
        "chevron" => &CHEVRON,
        "terminal" => &TERMINAL,
        "copy" => &COPY,
        "key" => &KEY,
        "apps" => &APPS,
        "sparkle" => &SPARKLE,
        "fingerprint" => &FINGERPRINT,
        "archive" => &ARCHIVE,
        "history" => &HISTORY,
        "chip" => &CHIP,
        "plug" => &PLUG,
        "keyboard" => &KEYBOARD,
        "home" => &HOME,
        "folder" => &FOLDER,
        "monitor" => &MONITOR,
        "database" => &DATABASE,
        "calendar" => &CALENDAR,
        "activity" => &ACTIVITY,
        "globe" => &GLOBE,
        "lock" => &LOCK,
        "wifi" => &WIFI,
        "stop" => &STOP,
        "box" => &BOX,
        "spinner" => &SPINNER,
        "sliders" => &SLIDERS,
        _ => &EMPTY,
    }
}

static SHIELD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6z", fill: false, stroke: true, width: None },
    ],
};

static SHIELD_ALERT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6zM12 8.5v4M12 15.5v.01", fill: false, stroke: true, width: None },
    ],
};

static SCAN: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M4 12h16", fill: false, stroke: true, width: None },
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

static FILE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5", fill: false, stroke: true, width: None },
    ],
};

static FILE_ALERT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M12 11v3.5M12 17.5v.01", fill: false, stroke: true, width: None },
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

static ARROW_RIGHT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 12h14M13 6l6 6-6 6", fill: false, stroke: true, width: None },
    ],
};

static ARROW_LEFT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M19 12H5M11 18l-6-6 6-6", fill: false, stroke: true, width: None },
    ],
};

static CHEVRON: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6l6 6-6 6", fill: false, stroke: true, width: None },
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

static KEY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 15a4 4 0 1 0 8 0a4 4 0 1 0 -8 0z", fill: false, stroke: true, width: None },
        Shape { d: "M10.8 12.2L20 3M16 7l3 3M18 5l2 2", fill: false, stroke: true, width: None },
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

static FINGERPRINT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6.6 5.6A8 8 0 0 1 20 11.5v1.2M4.4 9a8 8 0 0 0-.4 2.5v1.8M7.6 18.8A11 11 0 0 0 8.5 14.5v-3a3.5 3.5 0 0 1 7 0v1.5M12 11.5v2.8a14 14 0 0 1-2 7.2M15.4 16.6a17 17 0 0 1-1.2 4.4M19.7 15.8a19 19 0 0 1-.6 2.4", fill: false, stroke: true, width: None },
    ],
};

static ARCHIVE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4.5 4h15a1.5 1.5 0 0 1 1.5 1.5v2a1.5 1.5 0 0 1 -1.5 1.5h-15a1.5 1.5 0 0 1 -1.5 -1.5v-2a1.5 1.5 0 0 1 1.5 -1.5z", fill: false, stroke: true, width: None },
        Shape { d: "M5 9v9a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9M10 13h4", fill: false, stroke: true, width: None },
    ],
};

static HISTORY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 12a8.5 8.5 0 1 0 2.5-6M3.5 4v4h4M12 7.5V12l3 2", fill: false, stroke: true, width: None },
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

static PLUG: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 2v5M15 2v5M6 7h12v4a6 6 0 0 1-12 0zM12 17v5", fill: false, stroke: true, width: None },
    ],
};

static KEYBOARD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4.5 6h15a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-15a2 2 0 0 1 -2 -2v-8a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M7.5 14h9", fill: false, stroke: true, width: None },
    ],
};

static HOME: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 10.5L12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z", fill: false, stroke: true, width: None },
    ],
};

static FOLDER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z", fill: false, stroke: true, width: None },
    ],
};

static MONITOR: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-8a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M8 20h8M12 16v4", fill: false, stroke: true, width: None },
    ],
};

static DATABASE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 6a8 3 0 1 0 16 0a8 3 0 1 0 -16 0z", fill: false, stroke: true, width: None },
        Shape { d: "M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3", fill: false, stroke: true, width: None },
    ],
};

static CALENDAR: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5.5 5h13a2 2 0 0 1 2 2v11a2 2 0 0 1 -2 2h-13a2 2 0 0 1 -2 -2v-11a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M3.5 10h17M8 3v4M16 3v4", fill: false, stroke: true, width: None },
    ],
};

static ACTIVITY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12h4l3-8 4 16 3-8h4", fill: false, stroke: true, width: None },
    ],
};

static GLOBE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", fill: false, stroke: true, width: None },
        Shape { d: "M3 12h18M12 3c2.4 2.5 3.6 5.5 3.6 9s-1.2 6.5-3.6 9c-2.4-2.5-3.6-5.5-3.6-9S9.6 5.5 12 3z", fill: false, stroke: true, width: None },
    ],
};

static LOCK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M8 11V7.5a4 4 0 0 1 8 0V11", fill: false, stroke: true, width: None },
    ],
};

static WIFI: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.5 16a5 5 0 0 1 7 0M12 19.5h.01", fill: false, stroke: true, width: None },
    ],
};

static STOP: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M8.5 6h7a2.5 2.5 0 0 1 2.5 2.5v7a2.5 2.5 0 0 1 -2.5 2.5h-7a2.5 2.5 0 0 1 -2.5 -2.5v-7a2.5 2.5 0 0 1 2.5 -2.5z", fill: true, stroke: true, width: None },
    ],
};

static BOX: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9", fill: false, stroke: true, width: None },
    ],
};

static SPINNER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3a9 9 0 1 1-9 9", fill: false, stroke: true, width: None },
    ],
};

static SLIDERS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 7h9M17 7h3M4 17h3M11 17h9", fill: false, stroke: true, width: None },
        Shape { d: "M13 7a2 2 0 1 0 4 0a2 2 0 1 0 -4 0z", fill: false, stroke: true, width: None },
        Shape { d: "M7 17a2 2 0 1 0 4 0a2 2 0 1 0 -4 0z", fill: false, stroke: true, width: None },
    ],
};
