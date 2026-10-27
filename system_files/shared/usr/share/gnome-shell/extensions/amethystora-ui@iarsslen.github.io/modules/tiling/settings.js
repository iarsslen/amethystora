// The GNOME settings the tiling cannot do without, set while it runs and put back as they were when it stops:
// dragging a window to an edge of the screen does not snap it to half the screen (GNOME's edge tiling would fight
// the strip), modal dialogs are not attached to their parent, and with more than one screen every screen has
// workspaces, fixed ones, so that each screen shows one of its own (dynamic workspaces keep one empty workspace at
// most, which leaves a third screen without any); those two are given back when one screen is left. What they were
// is written down first (state.js), so that a crash cannot lose it.

import Gio from 'gi://Gio';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const MUTTER = 'org.gnome.mutter';

export class GnomeSettings {
    constructor(state) {
        this._state = state;
    }

    enable() {
        this._settings = new Gio.Settings({schema_id: MUTTER});
        this._settings.connectObject('changed', (s, key) => this._changed(key), this);
        this._force('edge-tiling', false);
        // A modal dialog is a window of its own: glued to a parent the strip moves, it would be left where the parent
        // was
        this._force('attach-modal-dialogs', false);
        this.monitorsChanged();
    }

    disable(suspend = false) {
        this._settings?.disconnectObject(this);
        // At a screen lock nothing is written: the tiling is back at unlock
        if (!suspend)
            GnomeSettings.giveBackLeftovers(this._state);
        this._settings = null;
    }

    monitorsChanged() {
        if (!this._settings)
            return;
        if (Main.layoutManager.monitors.length > 1) {
            this._force('workspaces-only-on-primary', false);
            // As many fixed workspaces as there are now at least: mutter would put the windows of the ones past the
            // fixed number on the last one
            const count = global.workspace_manager.n_workspaces;
            const wm = new Gio.Settings({schema_id: 'org.gnome.desktop.wm.preferences'});
            if (this._settings.get_boolean('dynamic-workspaces') && wm.get_int('num-workspaces') < count)
                wm.set_int('num-workspaces', count);
            this._force('dynamic-workspaces', false);
        } else {
            this._giveBack('workspaces-only-on-primary');
            this._giveBack('dynamic-workspaces');
        }
    }

    _giveBack(key) {
        const record = this._records().find(r => r.key === key);
        if (!record)
            return;
        this._state.set('forced', this._records().filter(r => r !== record));
        if (this._settings.get_boolean(key) === record.wrote)
            this._settings.set_boolean(key, record.was);
    }

    _records() {
        return this._state.get('forced') ?? [];
    }

    _force(key, value) {
        const current = this._settings.get_boolean(key);
        if (current === value || this._records().some(r => r.key === key))
            return;
        this._state.set('forced', [...this._records(), {schema: MUTTER, key, was: current, wrote: value}]);
        this._settings.set_boolean(key, value);
    }

    // The person set one of them again while the tiling runs: theirs from now on
    _changed(key) {
        const record = this._records().find(r => r.key === key);
        if (record && this._settings.get_boolean(key) !== record.wrote)
            this._state.set('forced', this._records().filter(r => r !== record));
    }

    static giveBackLeftovers(state) {
        for (const record of state.get('forced') ?? []) {
            try {
                const settings = new Gio.Settings({schema_id: record.schema});
                if (settings.get_boolean(record.key) === record.wrote)
                    settings.set_boolean(record.key, record.was);
            } catch (e) {
                console.warn(`Amethystora UI: ${record.schema} ${record.key} was not put back: ${e.message}`);
            }
        }
        state.set('forced', undefined);
    }
}
