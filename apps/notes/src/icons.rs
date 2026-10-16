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
        "note" => &NOTE,
        "notes" => &NOTES,
        "folder" => &FOLDER,
        "tag" => &TAG,
        "hash" => &HASH,
        "trash" => &TRASH,
        "search" => &SEARCH,
        "plus" => &PLUS,
        "lock" => &LOCK,
        "unlock" => &UNLOCK,
        "settings" => &SETTINGS,
        "book" => &BOOK,
        "inbox" => &INBOX,
        "today" => &TODAY,
        "calendar" => &CALENDAR,
        "pin" => &PIN,
        "done" => &DONE,
        "flag" => &FLAG,
        "repeat" => &REPEAT,
        "bell" => &BELL,
        "clock" => &CLOCK,
        "clip" => &CLIP,
        "bold" => &BOLD,
        "italic" => &ITALIC,
        "heading" => &HEADING,
        "list" => &LIST,
        "checklist" => &CHECKLIST,
        "code" => &CODE,
        "link" => &LINK,
        "quote" => &QUOTE,
        "history" => &HISTORY,
        "more" => &MORE,
        "close" => &CLOSE,
        "chevron" => &CHEVRON,
        "edit" => &EDIT,
        "split" => &SPLIT,
        "eye" => &EYE,
        "download" => &DOWNLOAD,
        "upload" => &UPLOAD,
        "archive" => &ARCHIVE,
        "key" => &KEY,
        "shield" => &SHIELD,
        "alert" => &ALERT,
        "info" => &INFO,
        "undo" => &UNDO,
        "sort" => &SORT,
        "file-plus" => &FILE_PLUS,
        "sidebar" => &SIDEBAR,
        "mark-ok" => &MARK_OK,
        "spinner" => &SPINNER,
        _ => &EMPTY,
    }
}

static NOTE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M9 13h6M9 17h4", fill: false, stroke: true, width: None },
    ],
};

static NOTES: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M8 7h9a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM6 17H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v2M10 12h5M10 16h3", fill: false, stroke: true, width: None },
    ],
};

static FOLDER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z", fill: false, stroke: true, width: None },
    ],
};

static TAG: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 12.1V4.5a1 1 0 0 1 1-1h7.6a1 1 0 0 1 .7.3l8 8a1 1 0 0 1 0 1.4l-7.6 7.6a1 1 0 0 1-1.4 0l-8-8a1 1 0 0 1-.3-.7zM8 8h.01", fill: false, stroke: true, width: None },
    ],
};

static HASH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 9h15M4 15h15M10 3.5L8 20.5M16 3.5l-2 17", fill: false, stroke: true, width: None },
    ],
};

static TRASH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4.5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1V7", fill: false, stroke: true, width: None },
    ],
};

static SEARCH: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4.5 11a6.5 6.5 0 1 0 13 0a6.5 6.5 0 1 0 -13 0z", fill: false, stroke: true, width: None },
        Shape { d: "M20 20l-4.2-4.2", fill: false, stroke: true, width: None },
    ],
};

static PLUS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 5v14M5 12h14", fill: false, stroke: true, width: None },
    ],
};

static LOCK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M7 10.5h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M8 10.5V7.5a4 4 0 0 1 8 0v3M12 14.5v2.5", fill: false, stroke: true, width: None },
    ],
};

static UNLOCK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M7 10.5h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M8 10.5V7.5a4 4 0 0 1 7.7-1.5M12 14.5v2.5", fill: false, stroke: true, width: None },
    ],
};

static SETTINGS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1", fill: false, stroke: true, width: None },
    ],
};

static BOOK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5zM5 19.5A1.5 1.5 0 0 0 6.5 21H19", fill: false, stroke: true, width: None },
    ],
};

static INBOX: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 13.5l2.6-7.8A1 1 0 0 1 7 5h10a1 1 0 0 1 .9.7l2.6 7.8V19a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1zM3.5 13.5H8l1.5 2.5h5l1.5-2.5h4.5", fill: false, stroke: true, width: None },
    ],
};

static TODAY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5.5 5h13a2 2 0 0 1 2 2v11a2 2 0 0 1 -2 2h-13a2 2 0 0 1 -2 -2v-11a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M3.5 10h17M8 3v4M16 3v4", fill: false, stroke: true, width: None },
        Shape { d: "M10.4 15a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0 -3.2 0z", fill: true, stroke: false, width: None },
    ],
};

static CALENDAR: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5.5 5h13a2 2 0 0 1 2 2v11a2 2 0 0 1 -2 2h-13a2 2 0 0 1 -2 -2v-11a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M3.5 10h17M8 3v4M16 3v4M8 14h.01M12 14h.01M16 14h.01M8 17.5h.01M12 17.5h.01", fill: false, stroke: true, width: None },
    ],
};

static PIN: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 4h6l-1 5 3.5 3.5V14h-11v-1.5L10 9zM12 14v6.5", fill: false, stroke: true, width: None },
    ],
};

static DONE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", fill: false, stroke: true, width: None },
        Shape { d: "M8 12.3l2.7 2.7L16.2 9.5", fill: false, stroke: true, width: None },
    ],
};

static FLAG: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 21V4.5M5 4.5h11.5l-2 4 2 4H5", fill: false, stroke: true, width: None },
    ],
};

static REPEAT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M17 3l3 3-3 3M4 11V9.5A3.5 3.5 0 0 1 7.5 6H20M7 21l-3-3 3-3M20 13v1.5a3.5 3.5 0 0 1-3.5 3.5H4", fill: false, stroke: true, width: None },
    ],
};

static BELL: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0", fill: false, stroke: true, width: None },
    ],
};

static CLOCK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", fill: false, stroke: true, width: None },
        Shape { d: "M12 7v5l3 2", fill: false, stroke: true, width: None },
    ],
};

static CLIP: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M20 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1L13 4.3a3.3 3.3 0 0 1 4.7 4.7l-8.3 8.3a1.7 1.7 0 0 1-2.4-2.4L14.6 7.3", fill: false, stroke: true, width: None },
    ],
};

static BOLD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M7 5h6a3.5 3.5 0 0 1 0 7H7zM7 12h7a3.5 3.5 0 0 1 0 7H7z", fill: false, stroke: true, width: None },
    ],
};

static ITALIC: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 5h8M6 19h8M14.5 5l-5 14", fill: false, stroke: true, width: None },
    ],
};

static HEADING: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 5v14M16 5v14M6 12h10", fill: false, stroke: true, width: None },
    ],
};

static LIST: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01", fill: false, stroke: true, width: None },
    ],
};

static CHECKLIST: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 6.5l1.8 1.8L8.5 5M3.5 15.5l1.8 1.8 3.2-3.3M12 7h8.5M12 16h8.5", fill: false, stroke: true, width: None },
    ],
};

static CODE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M8 7l-5 5 5 5M16 7l5 5-5 5", fill: false, stroke: true, width: None },
    ],
};

static LINK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1", fill: false, stroke: true, width: None },
    ],
};

static QUOTE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 5v14M9.5 8h9.5M9.5 12h9.5M9.5 16h6", fill: false, stroke: true, width: None },
    ],
};

static HISTORY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M3.5 12a8.5 8.5 0 1 0 2.5-6M3.5 4v5h5M12 7.5V12l3 2", fill: false, stroke: true, width: None },
    ],
};

static MORE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 12h.01M12 12h.01M18 12h.01", fill: false, stroke: true, width: Some(3.0) },
    ],
};

static CLOSE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M6 6l12 12M18 6L6 18", fill: false, stroke: true, width: None },
    ],
};

static CHEVRON: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 6l6 6-6 6", fill: false, stroke: true, width: None },
    ],
};

static EDIT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16zM13.5 6.5l4 4", fill: false, stroke: true, width: None },
    ],
};

static SPLIT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M12 4v16", fill: false, stroke: true, width: None },
    ],
};

static EYE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M2.5 12S6 5 12 5s9.5 7 9.5 7-3.5 7-9.5 7-9.5-7-9.5-7z", fill: false, stroke: true, width: None },
        Shape { d: "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", fill: false, stroke: true, width: None },
    ],
};

static DOWNLOAD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 4v11M7 10l5 5 5-5M5 20h14", fill: false, stroke: true, width: None },
    ],
};

static UPLOAD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 20V9M7 14l5-5 5 5M5 4h14", fill: false, stroke: true, width: None },
    ],
};

static ARCHIVE: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4.5 4h15a1.5 1.5 0 0 1 1.5 1.5v2a1.5 1.5 0 0 1 -1.5 1.5h-15a1.5 1.5 0 0 1 -1.5 -1.5v-2a1.5 1.5 0 0 1 1.5 -1.5z", fill: false, stroke: true, width: None },
        Shape { d: "M5 9v9a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9M10 13h4", fill: false, stroke: true, width: None },
    ],
};

static KEY: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 15a4 4 0 1 0 8 0a4 4 0 1 0 -8 0z", fill: false, stroke: true, width: None },
        Shape { d: "M10.8 12.2L20 3M16 7l3 3M18 5l2 2", fill: false, stroke: true, width: None },
    ],
};

static SHIELD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6zM9 12l2 2 4-4", fill: false, stroke: true, width: None },
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

static UNDO: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M9 14L4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3", fill: false, stroke: true, width: None },
    ],
};

static SORT: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M4 7h10M4 12h7M4 17h4M17 5v14M14 16l3 3 3-3", fill: false, stroke: true, width: None },
    ],
};

static FILE_PLUS: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M12 11.5v6M9 14.5h6", fill: false, stroke: true, width: None },
    ],
};

static SIDEBAR: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", fill: false, stroke: true, width: None },
        Shape { d: "M9 4v16", fill: false, stroke: true, width: None },
    ],
};

static MARK_OK: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 12.5l4.5 4.5L19 7.5", fill: false, stroke: true, width: None },
    ],
};

static SPINNER: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M12 3a9 9 0 1 1-9 9", fill: false, stroke: true, width: None },
    ],
};
