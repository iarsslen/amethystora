// The dock's items that are not apps (a drive, the trash) and their menus, laid out as GNOME's app menu is: their
// windows, a new window, what can be done with the place, and closing its windows. An app's own entries, which it
// gives through the launcher protocol, go into GNOME's app menu itself.

import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {gettext as _, ngettext} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as BoxPointer from 'resource:///org/gnome/shell/ui/boxpointer.js';
import * as IconGrid from 'resource:///org/gnome/shell/ui/iconGrid.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

// The left and middle buttons, under the names GNOME 51 gives them or the ones 50 has
const BUTTONS = (St.ButtonMask.PRIMARY ?? St.ButtonMask.ONE) | (St.ButtonMask.MIDDLE ?? St.ButtonMask.TWO);

// GNOME's dash takes this item for an icon (it has a delegate with an icon), so it is sized with the apps, but not
// for an app, so GNOME's list of apps leaves it alone. activate(button) is a click; fill(menu) fills its menu.
export const PlaceButton = GObject.registerClass({
    Signals: {'menu-state-changed': {param_types: [GObject.TYPE_BOOLEAN]}},
}, class AmethystoraDockPlace extends St.Button {
    _init(place, activate, fill) {
        super._init({
            style_class: 'overview-tile',
            reactive: true,
            can_focus: true,
            track_hover: true,
            button_mask: BUTTONS,
        });
        this.place = place;
        this._activate = activate;
        this._fill = fill;
        this._delegate = this;

        this._iconContainer = new St.Widget({layout_manager: new Clutter.BinLayout(), x_expand: true, y_expand: true});
        this.set_child(this._iconContainer);
        this.icon = new IconGrid.BaseIcon(place.name, {
            setSizeManually: true,
            showLabel: false,
            createIcon: size => new St.Icon({
                gicon: this.place.gicon,
                fallback_icon_name: this.place.fallback,
                icon_size: size,
            }),
        });
        this._iconContainer.add_child(this.icon);

        const longPress = new Clutter.LongPressGesture();
        longPress.connect('recognize', () => this.popupMenu());
        this.add_action(longPress);
        const rightClick = new Clutter.ClickGesture({
            required_button: Clutter.BUTTON_SECONDARY,
            recognize_on_press: true,
        });
        rightClick.connect('recognize', () => this.popupMenu());
        this.add_action(rightClick);
        this.connect('popup-menu', () => {
            this.popupMenu();
            this._menu.actor.navigate_focus(null, St.DirectionType.TAB_FORWARD, false);
        });
        this.connect('destroy', () => this._menu?.destroy());
    }

    vfunc_clicked(button) {
        this._activate(button);
    }

    // The place's icon changed (the trash filled or emptied, a drive was renamed)
    sync() {
        if (this.icon.icon)
            this.icon.icon.gicon = this.place.gicon;
    }

    popupMenu() {
        if (!this._menu) {
            this._menu = new PopupMenu.PopupMenu(this, 0.5, St.Side.BOTTOM);
            this._menu.actor.add_style_class_name('app-menu');
            this._menu.connect('open-state-changed', (menu, open) => {
                if (!open) {
                    this.track_hover = true;
                    this.sync_hover();
                }
                this.emit('menu-state-changed', open);
            });
            Main.overview.connectObject('hiding', () => this._menu.close(), this);
            Main.uiGroup.add_child(this._menu.actor);
            this._menuManager = new PopupMenu.PopupMenuManager(this);
            this._menuManager.addMenu(this._menu);
        }
        this._fill(this._menu);
        // Lit while its menu is open, as GNOME's app icons are
        this.set({track_hover: false, hover: true});
        this._menu.open(BoxPointer.PopupAnimation.FULL);
        return false;
    }
});

// windows() gives the place's windows, most recently used first, as they are when asked
export function fillPlaceMenu(menu, place, places, windows) {
    menu.removeAll();
    const shown = windows();
    if (shown.length) {
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem(_('Open windows')));
        for (const window of shown) {
            const item = menu.addAction(window.title || place.name,
                () => Main.activateWindow(window, global.get_current_time()));
            window.connectObject('notify::title', () => (item.label.text = window.title || place.name), item);
        }
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    }
    menu.addAction(_('New window'), () => {
        places.openNew(place);
        Main.overview.hide();
    });
    menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    for (const action of places.actions(place)) {
        const item = menu.addAction(action.label, () => action.run());
        item.setSensitive(!action.busy);
    }
    if (shown.length) {
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        menu.addAction(ngettext('Close the window', 'Close %d windows', shown.length).format(shown.length), () => {
            for (const window of windows())
                window.delete(global.get_current_time());
        });
    }
}

// An app's own entries ([{label, enabled, separator, activate(time)}]) in their own group after GNOME's pin item,
// where GNOME's lines on either side set them apart
export function fillQuicklist(menu, entries) {
    if (!menu._amethystoraQuicklist) {
        menu._amethystoraQuicklist = new PopupMenu.PopupMenuSection();
        const items = menu._getMenuItems();
        const details = items.indexOf(menu._detailsItem);
        menu.addMenuItem(menu._amethystoraQuicklist, details >= 0 ? details : items.length);
    }
    const section = menu._amethystoraQuicklist;
    section.removeAll();
    for (const entry of entries) {
        if (entry.separator) {
            section.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
            continue;
        }
        const item = section.addAction(entry.label, () => entry.activate(global.get_current_time()));
        item.setSensitive(entry.enabled);
    }
    // GNOME shows or hides its lines as a menu opens, which this one already has
    for (const item of menu._getMenuItems()) {
        if (item instanceof PopupMenu.PopupSeparatorMenuItem)
            menu._updateSeparatorVisibility(item);
    }
}
