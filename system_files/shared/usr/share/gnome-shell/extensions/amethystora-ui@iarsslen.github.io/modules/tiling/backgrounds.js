// A workspace's own wallpaper and colour, from the settings (workspace-backgrounds, workspace-colors and
// default-background): each screen draws the picture of the workspace it shows over GNOME's own wallpaper, with the
// workspace's colour under it where the picture leaves room. A workspace with no picture of its own, and no default
// one, shows GNOME's wallpaper as it is, so that the theme's wallpaper and its transitions are what one sees. The
// pictures take no clicks: GNOME's background menu stays where it is.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {config} from './config.js';

// Under a picture that leaves room, a workspace without a colour of its own
const NEUTRAL = '#282828';

// The picture a workspace has, as a file, or null for GNOME's own
export function pictureOf(workspace) {
    const uri = config.workspaceBackgrounds[workspace.index()] || config.defaultBackground;
    if (!uri)
        return null;
    const file = uri.includes('://') ? Gio.File.new_for_uri(uri) : Gio.File.new_for_path(uri);
    return file.query_exists(null) ? file : null;
}

// The colour a workspace has, '#rrggbb', or null for the theme's
export function colourOf(workspace) {
    return config.workspaceColors[workspace.index()] || null;
}

// A screen's background with a workspace's picture over its colour, the picture filling the screen as GNOME's zoom
// does, or null when it has none. Drawn by the shell's own stylesheet machinery, which loads the picture the way
// the shell loads every image, on GNOME 50 and 51 alike (Mutter's own background loading changed between them).
export function backgroundActor(workspace) {
    const file = pictureOf(workspace);
    if (!file)
        return null;
    const uri = file.get_uri().replace(/["\\]/g, c => `\\${c}`);
    return new St.Widget({
        reactive: false,
        // Covering, which St centres
        style: `background-color: ${colourOf(workspace) ?? NEUTRAL}; background-image: url("${uri}");` +
            ' background-size: cover;',
    });
}

export class WorkspaceBackgrounds {
    constructor(engine) {
        this._engine = engine;
    }

    enable() {
        // Just above GNOME's backgrounds, under everything else in the window group (the pictures of the other
        // screens' workspaces included, which go above it)
        this.layer = new Clutter.Actor({reactive: false});
        const group = Main.layoutManager._backgroundGroup;
        if (group?.get_parent() === global.window_group)
            global.window_group.insert_child_above(this.layer, group);
        else
            global.window_group.insert_child_at_index(this.layer, 0);
        this._shown = new Map();
        global.workspace_manager.connectObject('active-workspace-changed', () => this.sync(), this);
        Main.layoutManager.connectObject('monitors-changed', () => this.sync(), this);
        this.sync();
    }

    disable() {
        global.workspace_manager.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        this.layer?.destroy();
        this.layer = null;
        this._shown = null;
    }

    // Each screen with its workspace's picture, made again only where the workspace or its picture changed
    sync() {
        if (!this.layer)
            return;
        const monitors = Main.layoutManager.monitors;
        for (const [index, shown] of [...this._shown]) {
            if (index >= monitors.length) {
                shown.actor?.destroy();
                this._shown.delete(index);
            }
        }
        monitors.forEach((monitor, index) => {
            const workspace = this._engine.screens?.shownOn(index) ?? global.workspace_manager.get_active_workspace();
            const key = `${workspace.index()}|${pictureOf(workspace)?.get_uri() ?? ''}|${colourOf(workspace) ?? ''}|` +
                `${monitor.x},${monitor.y},${monitor.width},${monitor.height}`;
            const shown = this._shown.get(index);
            if (shown?.key === key)
                return;
            shown?.actor?.destroy();
            const actor = backgroundActor(workspace);
            if (actor) {
                actor.set_position(monitor.x, monitor.y);
                actor.set_size(monitor.width, monitor.height);
                this.layer.add_child(actor);
            }
            this._shown.set(index, {key, actor});
        });
    }
}
