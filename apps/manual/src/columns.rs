//! The sidebar and the page side by side, the sidebar as wide as the page's grid made it:
//! clamp(248px, 24vw, 290px), a quarter of the window between those two.

use std::cell::RefCell;

use amethystora_ui::{glib, gtk, icon};
use gtk::prelude::*;
use gtk::subclass::prelude::*;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Columns {
        pub children: RefCell<Option<(gtk::Widget, gtk::Widget)>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Columns {
        const NAME: &'static str = "AmethystoraManualColumns";
        type Type = super::Columns;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Columns {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl Columns {
        fn sidebar_width(width: i32) -> i32 {
            let zoom = icon::zoom();
            ((width as f64 * 0.24).clamp(248.0 * zoom, 290.0 * zoom)).round() as i32
        }
    }

    impl WidgetImpl for Columns {
        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            let Some((side, main)) = self.children.borrow().clone() else { return (0, 0, -1, -1) };
            if orientation == gtk::Orientation::Horizontal {
                let (main_min, main_nat, _, _) = main.measure(orientation, -1);
                let side = (248.0 * icon::zoom()) as i32;
                (side + main_min, side + main_nat, -1, -1)
            } else {
                let (a, b, _, _) = side.measure(orientation, -1);
                let (c, d, _, _) = main.measure(orientation, -1);
                let _ = for_size;
                (a.max(c), b.max(d), -1, -1)
            }
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            let Some((side, main)) = self.children.borrow().clone() else { return };
            let side_width = Self::sidebar_width(width).min(width);
            let rtl = self.obj().direction() == gtk::TextDirection::Rtl;
            let (side_x, main_x) = if rtl { (width - side_width, 0) } else { (0, side_width) };
            side.size_allocate(&gtk::Allocation::new(side_x, 0, side_width, height), baseline);
            main.size_allocate(&gtk::Allocation::new(main_x, 0, width - side_width, height), baseline);
        }
    }
}

glib::wrapper! {
    pub struct Columns(ObjectSubclass<imp::Columns>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Columns {
    pub fn new(side: &impl IsA<gtk::Widget>, main: &impl IsA<gtk::Widget>) -> Columns {
        let columns: Columns = glib::Object::new();
        side.set_parent(&columns);
        main.set_parent(&columns);
        columns.imp().children.replace(Some((side.clone().upcast(), main.clone().upcast())));
        columns
    }
}
