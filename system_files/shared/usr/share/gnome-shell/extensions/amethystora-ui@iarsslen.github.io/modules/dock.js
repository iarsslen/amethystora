// The dock: the pinned apps, the running ones, the drives, the trash and the app grid button in one row at the
// bottom of the main screen, always there. Its strip of the screen is kept free, so maximized and tiled windows
// stop above it, and the overview is laid out above it too, in place of GNOME's dash, which it stands for. Its
// background is the glass, which the glass module draws behind it; on a light theme a faint dark veil over the
// glass keeps the icons clear of a pale wallpaper. Nothing about it is a setting: the dock's apps are GNOME's own
// list of pinned apps.

import Clutter from 'gi://Clutter';
import St from 'gi://St';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as AppMenu from 'resource:///org/gnome/shell/ui/appMenu.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {DockDash} from './dock/dash.js';
import {LauncherEntries} from './dock/launcher.js';
import {Places} from './dock/places.js';

// The widest the dock grows, as a share of the screen's free width
const WIDTH = 0.9;
// The glass's corners, which the light veil follows exactly
const RADIUS = 32;

export class Dock {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        this._places = new Places();
        this._places.start();
        this._launcher = new LauncherEntries();
        this._launcher.start();

        // GNOME's dash gives the overview's bottom row to the dock: hidden, but as tall as the dock, so that the
        // overview leaves the dock its room
        this._overviewDash = Main.overview.dash;
        this._overviewDash.hide();

        // GNOME's app menus pin to the dock, by name, wherever they open
        const menu = AppMenu.AppMenu.prototype;
        this._updateFavoriteItem = menu._updateFavoriteItem;
        const original = this._updateFavoriteItem;
        menu._updateFavoriteItem = function (...args) {
            original.apply(this, args);
            if (this._toggleFavoriteItem.visible && this._app && !this._appFavorites.isFavorite(this._app.get_id()))
                this._toggleFavoriteItem.label.text = _('Pin to dock');
        };

        Main.layoutManager.connectObject('monitors-changed', () => this._rebuild(), this);
        global.display.connectObject('workareas-changed', () => this._place(), this);
        St.Settings.get().connectObject('notify::color-scheme', () => this._syncScheme(), this);
        this._build();
    }

    disable() {
        Main.layoutManager.disconnectObject(this);
        global.display.disconnectObject(this);
        St.Settings.get().disconnectObject(this);
        this._destroyDock();

        if (this._updateFavoriteItem)
            AppMenu.AppMenu.prototype._updateFavoriteItem = this._updateFavoriteItem;
        this._updateFavoriteItem = null;

        if (this._overviewDash) {
            this._overviewDash.height = -1;
            this._overviewDash.show();
        }
        this._overviewDash = null;

        this._launcher?.stop();
        this._launcher = null;
        this._places?.stop();
        this._places = null;
        this._ext.modules?.get('glass')?.surfacesChanged?.();
    }

    // For the glass: the pill, with the glass's own corners
    glassSurfaces() {
        return this._dash ? [{actor: this._dash.pill, material: 'dock', radius: RADIUS}] : [];
    }

    _build() {
        if (!Main.layoutManager.primaryMonitor)
            return;
        // Across the whole width, so that the window manager keeps the whole bottom strip free; only the dock in
        // it takes the pointer
        this._strip = new St.Widget({name: 'amethystoraDock', layout_manager: new Clutter.BinLayout()});
        this._dash = new DockDash(this._places, this._launcher);
        this._strip.add_child(this._dash);
        Main.layoutManager.addChrome(this._strip, {affectsStruts: true, trackFullscreen: true});
        this._strip.connectObject('notify::height', () => this._place(), this);
        this._syncScheme();
        this._place();
        this._ext.modules?.get('glass')?.surfacesChanged?.();
    }

    _destroyDock() {
        this._strip?.destroy();
        this._strip = null;
        this._dash = null;
    }

    // A screen added, taken away or rearranged: the dock is made again on the main one
    _rebuild() {
        this._destroyDock();
        this._build();
    }

    _place() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!this._strip || !monitor)
            return;
        const area = Main.layoutManager.getWorkAreaForMonitor(monitor.index);
        const room = Math.floor(area.width * WIDTH);
        const left = area.x - monitor.x + Math.floor((area.width - room) / 2);
        this._dash.set({margin_left: left, margin_right: Math.max(0, monitor.width - left - room)});
        this._dash.fitTo(room);

        this._strip.width = monitor.width;
        const [, height] = this._strip.get_preferred_height(monitor.width);
        this._strip.set_position(monitor.x, monitor.y + monitor.height - height);
        this._overviewDash.height = height;
    }

    _syncScheme() {
        if (Main.getStyleVariant() === 'light')
            this._dash?.add_style_class_name('amethystora-dock-light');
        else
            this._dash?.remove_style_class_name('amethystora-dock-light');
    }
}
