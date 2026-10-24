// What the tiling keeps across log-outs that is the person's doing and not a setting: where new windows open,
// the workspaces whose top bar they hid, and what it took out of GNOME's settings while it runs, so that those
// are put back even if GNOME Shell stops in the middle. One small file, written only when one of them changes.

import GLib from 'gi://GLib';

const DIR = GLib.build_filenamev([GLib.get_user_state_dir(), 'amethystora']);
const FILE = GLib.build_filenamev([DIR, 'tiling.json']);

export class State {
    constructor() {
        this._data = {};
        try {
            const [, bytes] = GLib.file_get_contents(FILE);
            const data = JSON.parse(new TextDecoder().decode(bytes));
            if (data && typeof data === 'object' && !Array.isArray(data))
                this._data = data;
        } catch {
            // No file yet, or one that cannot be read: start from nothing
        }
    }

    get(key) {
        return this._data[key];
    }

    set(key, value) {
        if (JSON.stringify(this._data[key]) === JSON.stringify(value))
            return;
        if (value === undefined || (Array.isArray(value) && !value.length))
            delete this._data[key];
        else
            this._data[key] = value;
        try {
            GLib.mkdir_with_parents(DIR, 0o700);
            GLib.file_set_contents(FILE, JSON.stringify(this._data));
        } catch (e) {
            console.warn(`Amethystora UI: the tiling could not write ${FILE}: ${e.message}`);
        }
    }
}
