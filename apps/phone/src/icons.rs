//! The window's line icons, 24 units square, as path data for amethystora_ui::icon, drawn in the style of the other
//! apps' sets (two or three strokes, round caps). A new icon is its SVG path data, stroked in the CSS colour.

use amethystora_ui::icon::{EMPTY, Icon, IconData, Shape};

/// The width every icon is stroked with, as the other apps' sets have it
pub const STROKE: f32 = 1.8;

/// An icon by name, `size` pixels square
pub fn icon(name: &str, size: i32) -> Icon {
    Icon::new(data(name), size, STROKE)
}

/// The icon of a kind of device, as the connect interface names the kinds
pub fn device(kind: &str, size: i32) -> Icon {
    icon(
        match kind {
            "tablet" => "tablet",
            "laptop" => "laptop",
            "desktop" => "desktop",
            "tv" => "tv",
            _ => "phone",
        },
        size,
    )
}

pub fn data(name: &str) -> &'static IconData {
    match name {
        "phone" => &PHONE,
        "tablet" => &TABLET,
        "laptop" => &LAPTOP,
        "desktop" => &DESKTOP,
        "tv" => &TV,
        "message" => &MESSAGE,
        "send" => &SEND,
        "bolt" => &BOLT,
        "battery" => &BATTERY,
        "user" => &USER,
        "users" => &USERS,
        "bell" => &BELL,
        "key" => &KEY,
        "plus" => &PLUS,
        "unlink" => &UNLINK,
        "link" => &LINK,
        "file" => &FILE,
        "upload" => &UPLOAD,
        "download" => &DOWNLOAD,
        "history" => &HISTORY,
        "refresh" => &REFRESH,
        "check" => &CHECK,
        "close" => &CLOSE,
        "copy" => &COPY,
        "external" => &EXTERNAL,
        "terminal" => &TERMINAL,
        "book" => &BOOK,
        "alert" => &ALERT,
        "info" => &INFO,
        "chevron" => &CHEVRON,
        "spinner" => &SPINNER,
        "home" => &HOME,
        _ => &EMPTY,
    }
}

static PHONE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M8.5 3h7a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z", fill: false, stroke: true, width: None },
        Shape { d: "M10.5 18h3", fill: false, stroke: true, width: None },
    ],
};

static TABLET: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 3.5h12a1.5 1.5 0 0 1 1.5 1.5v14a1.5 1.5 0 0 1-1.5 1.5H6A1.5 1.5 0 0 1 4.5 19V5A1.5 1.5 0 0 1 6 3.5z", fill: false, stroke: true, width: None },
        Shape { d: "M10.5 17.5h3", fill: false, stroke: true, width: None },
    ],
};

static LAPTOP: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5.5 5h13a1 1 0 0 1 1 1v9.5h-15V6a1 1 0 0 1 1-1z", fill: false, stroke: true, width: None },
        Shape { d: "M2.5 19h19", fill: false, stroke: true, width: None },
    ],
};

static DESKTOP: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 4.5h16a1 1 0 0 1 1 1V15a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5.5a1 1 0 0 1 1-1z", fill: false, stroke: true, width: None },
        Shape { d: "M9 20h6M12 16v4", fill: false, stroke: true, width: None },
    ],
};

static TV: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 7.5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-10a1 1 0 0 1 1-1z", fill: false, stroke: true, width: None },
        Shape { d: "M8.5 3.5L12 7.5l3.5-4", fill: false, stroke: true, width: None },
    ],
};

static MESSAGE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4.5h14a2 2 0 0 1 2 2V15a2 2 0 0 1-2 2h-8l-4.5 3.5V17H5a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2z", fill: false, stroke: true, width: None },
    ],
};

static SEND: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M20.5 3.5L3.5 10.5l6.5 3 3 6.5z", fill: false, stroke: true, width: None },
        Shape { d: "M10 13.5l10.5-10", fill: false, stroke: true, width: None },
    ],
};

static BOLT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M13 3L5.5 13.5H11L10 21l7.5-10.5H12z", fill: true, stroke: false, width: None },
    ],
};

static BATTERY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 8h13a1.5 1.5 0 0 1 1.5 1.5v5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 2 14.5v-5A1.5 1.5 0 0 1 3.5 8z", fill: false, stroke: true, width: None },
        Shape { d: "M21 10.5v3", fill: false, stroke: true, width: None },
    ],
};

static USER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M8 8a4 4 0 1 0 8 0a4 4 0 1 0 -8 0z", fill: false, stroke: true, width: None },
        Shape { d: "M4.5 20.5a7.5 7.5 0 0 1 15 0", fill: false, stroke: true, width: None },
    ],
};

static USERS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5.5 8.5a3.2 3.2 0 1 0 6.4 0a3.2 3.2 0 1 0 -6.4 0z", fill: false, stroke: true, width: None },
        Shape { d: "M2.5 19.5a6.2 6.2 0 0 1 12.4 0", fill: false, stroke: true, width: None },
        Shape { d: "M15.2 5.6a3.2 3.2 0 0 1 0 5.8M17.5 14a6 6 0 0 1 4 5.5", fill: false, stroke: true, width: None },
    ],
};

static BELL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0", fill: false, stroke: true, width: None },
    ],
};

static KEY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 15a4 4 0 1 0 8 0a4 4 0 1 0 -8 0z", fill: false, stroke: true, width: None },
        Shape { d: "M10.8 12.2L20 3M16 7l3 3M18 5l2 2", fill: false, stroke: true, width: None },
    ],
};

static PLUS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 5v14M5 12h14", fill: false, stroke: true, width: None },
    ],
};

static LINK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1", fill: false, stroke: true, width: None },
    ],
};

static UNLINK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1", fill: false, stroke: true, width: None },
        Shape { d: "M4.5 4.5l15 15", fill: false, stroke: true, width: None },
    ],
};

static FILE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8z", fill: false, stroke: true, width: None },
        Shape { d: "M14 3.5V8h4.5", fill: false, stroke: true, width: None },
    ],
};

static UPLOAD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 15V4M7 9l5-5 5 5M5 15v3.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V15", fill: false, stroke: true, width: None },
    ],
};

static DOWNLOAD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 4v11M7 10l5 5 5-5M5 20h14", fill: false, stroke: true, width: None },
    ],
};

static HISTORY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 12a8.5 8.5 0 1 0 2.5-6M3.5 4v4.5H8M12 7.5V12l3 2", fill: false, stroke: true, width: None },
    ],
};

static REFRESH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5", fill: false, stroke: true, width: None },
    ],
};

static CHECK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 12.5l4.5 4.5L19 7.5", fill: false, stroke: true, width: None },
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

static EXTERNAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 4.5h5.5V10M19.5 4.5L11 13M17.5 14v4a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2h4", fill: false, stroke: true, width: None },
    ],
};

static TERMINAL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M7 9l3 3-3 3M12.5 15H17", fill: false, stroke: true, width: None },
    ],
};

static BOOK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5zM5 19.5A1.5 1.5 0 0 0 6.5 21H19", fill: false, stroke: true, width: None },
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

static SPINNER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3a9 9 0 1 1-9 9", fill: false, stroke: true, width: None },
    ],
};

static HOME: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 10.5L12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5h-4v-6h-5v6h-4A1.5 1.5 0 0 1 4 19z", fill: false, stroke: true, width: None },
    ],
};
