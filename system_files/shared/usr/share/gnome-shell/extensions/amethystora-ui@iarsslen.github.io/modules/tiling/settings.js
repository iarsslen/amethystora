// The two GNOME settings the tiling cannot do without, set while it runs and put back as they were when it stops:
// dragging a window to an edge of the screen does not snap it to half the screen (GNOME's edge tiling would fight
// the strip), and with more than one screen every screen has workspaces, so that each one has a strip of its own.
// What they were is written down first (state.js), so that a crash cannot lose it.

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
        if (this._settings && Main.layoutManager.monitors.length > 1)
            this._force('workspaces-only-on-primary', false);
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
