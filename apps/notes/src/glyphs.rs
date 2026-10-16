//! What the page drew that is not in its sprite: the chevron turned down, which CSS made of the sprite's
//! chevron with `transform: rotate(90deg)` for an open notebook, and Chromium's own arrow on a <select>.
//! Kept apart from icons.rs, which apps/tools/icons.js writes from the sprite.

use amethystora_ui::icon::{Icon, IconData, Shape};

/// The sprite's chevron, `M9 6l6 6-6 6`, turned a quarter clockwise about the middle of its 24 units
static CHEVRON_DOWN: IconData = IconData { view: 24.0, shapes: &[Shape { d: "M18 9l-6 6-6-6", fill: false, stroke: true, width: None }] };

/// Chromium's arrow on a <select>, a little heavier than the page's icons
static SELECT_ARROW: IconData = IconData { view: 24.0, shapes: &[Shape { d: "M7 10l5 5 5-5", fill: false, stroke: true, width: Some(2.0) }] };

/// Chromium's calendar on a date field, and its clock on a time field
static CALENDAR_FIELD: IconData = IconData {
    view: 24.0,
    shapes: &[
        Shape { d: "M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM4 10h16M8 4v4M16 4v4", fill: false, stroke: true, width: Some(2.0) },
    ],
};

static CLOCK_FIELD: IconData = IconData {
    view: 24.0,
    shapes: &[Shape { d: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM12 7v5l3.5 2", fill: false, stroke: true, width: Some(2.0) }],
};

pub fn chevron_down(size: i32) -> Icon {
    Icon::new(&CHEVRON_DOWN, size, crate::icons::STROKE)
}

pub fn select_arrow(size: i32) -> Icon {
    Icon::new(&SELECT_ARROW, size, 2.0)
}

pub fn calendar(size: i32) -> Icon {
    Icon::new(&CALENDAR_FIELD, size, 2.0)
}

pub fn clock(size: i32) -> Icon {
    Icon::new(&CLOCK_FIELD, size, 2.0)
}
