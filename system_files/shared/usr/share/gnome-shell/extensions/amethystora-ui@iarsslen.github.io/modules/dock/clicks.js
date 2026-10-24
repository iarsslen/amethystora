// What a click on a dock item does. An app or place with no window opens; one whose window is not in front comes
// to the front (a window that asks for attention first); one already in front goes on to its next window, click
// after click. Shift minimizes a window, and the second click of a double click with Shift the rest of them; the
// middle button, or Ctrl, opens a new window. A double click is otherwise one click.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Dash from 'resource:///org/gnome/shell/ui/dash.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Milliseconds a walk through an app's windows is remembered after the last click
const WALK_MEMORY = 3000;

export class Clicks {
    // dash.windowsOf(key) gives an item's windows, most recently used first; dash.focusedKey() the app or place
    // in front
    constructor(dash, places, launcher) {
        this._dash = dash;
        this._places = places;
        this._launcher = launcher;
    }

    destroy() {
        this._endWalk();
    }

    appTarget(icon) {
        const {app} = icon;
        return {
            key: app,
            name: app.get_name(),
            updating: () => Boolean(this._launcher.get(app.get_id())?.updating),
            launch: () => {
                icon.animateLaunch();
                // Files can be running with every window showing a place: it opens one of its own
                if (app.state === Shell.AppState.RUNNING && app.can_open_new_window())
                    app.open_new_window(-1);
                else
                    app.activate();
            },
            // GNOME's own click, which opens a new window with Ctrl or the middle button
            gnome: button => Dash.DashIcon.prototype.activate.call(icon, button),
        };
    }

    placeTarget(place) {
        return {
            key: place,
            name: place.name,
            updating: () => false,
            launch: () => this._places.open(place),
            gnome: () => this._places.openNew(place),
        };
    }

    act(target, button) {
        const event = Clutter.get_current_event();
        const state = event?.get_state() ?? 0;
        const time = event?.get_time() ?? global.get_current_time();
        const shift = (state & Clutter.ModifierType.SHIFT_MASK) !== 0;
        const ctrl = (state & Clutter.ModifierType.CONTROL_MASK) !== 0;
        const middle = button === Clutter.BUTTON_MIDDLE;

        const last = this._lastClick;
        const second = !middle && last?.key === target.key &&
            time - last.time <= Clutter.Settings.get_default().double_click_time;
        this._lastClick = second ? null : {key: target.key, time};

        if (target.updating()) {
            Main.osdWindowManager.showAll(Gio.ThemedIcon.new('action-unavailable-symbolic'),
                _('%s is being updated. Try again later.').format(target.name));
            return;
        }

        const windows = this._dash.windowsOf(target.key);
        if (middle || ctrl) {
            if (windows.length || !(target.key instanceof Shell.App))
                target.gnome(button);
            else
                target.launch();
        } else if (shift) {
            if (windows.length)
                this._minimize(windows, second);
            else
                target.launch();
        } else if (second) {
            return;
        } else if (Main.overview.visible && target.key instanceof Shell.App) {
            target.gnome(button);
        } else if (!windows.length) {
            target.launch();
        } else {
            const urgent = windows.find(window => window.demands_attention || window.urgent);
            if (urgent || this._dash.focusedKey() !== target.key) {
                this._endWalk();
                Main.activateWindow(urgent ?? windows[0], time);
            } else {
                this._walk(target.key, windows, time);
            }
        }
        Main.overview.hide();
    }

    // The first window shown on this workspace, or all of them
    _minimize(windows, all) {
        const workspace = global.workspace_manager.get_active_workspace();
        const shown = windows.filter(window => window.located_on_workspace(workspace) &&
            window.showing_on_its_workspace() && window.can_minimize());
        for (const window of all ? shown : shown.slice(0, 1))
            window.minimize();
    }

    // In the order the windows had at the first click
    _walk(key, windows, time) {
        if (this._walking?.key !== key)
            this._walking = {key, order: [...windows]};
        if (this._walkId)
            GLib.source_remove(this._walkId);
        this._walkId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, WALK_MEMORY, () => {
            this._walkId = 0;
            this._walking = null;
            return GLib.SOURCE_REMOVE;
        });
        const order = this._walking.order.filter(window => windows.includes(window));
        if (order.length)
            Main.activateWindow(order[(order.indexOf(global.display.focus_window) + 1) % order.length], time);
    }

    _endWalk() {
        if (this._walkId)
            GLib.source_remove(this._walkId);
        this._walkId = 0;
        this._walking = null;
    }
}
