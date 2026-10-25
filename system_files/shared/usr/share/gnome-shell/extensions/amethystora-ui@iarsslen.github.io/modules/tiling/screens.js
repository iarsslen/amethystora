// With two screens or more, each screen shows a workspace of its own, and a workspace is shown on one screen at most.
// GNOME has one workspace at a time, the one of the screen with the keyboard; the others show theirs through live
// pictures of its windows, in a layer just above the background, with the focus frame as it is when the keyboard is
// elsewhere. The pointer moving to a screen makes its workspace GNOME's, with no animation. GNOME's own ways to another
// workspace show it on the screen it was last on; the tiling's keys and gestures show it on the screen with the
// keyboard; a workspace already shown on another screen comes with a swap. A workspace keeps its screen by the
// screen's connector, so that it goes back there when the screen is plugged in again. With one screen, nothing here
// does anything.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

import {gettext as _, ngettext} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// What survives the tiling being stopped and started in the same session (a screen lock): which workspace each
// screen showed, by its connector
const remembered = {shown: new Map(), homes: new Map()};

export class Screens {
    constructor(engine) {
        this._engine = engine;
    }

    enable() {
        // connector -> workspace shown there; workspace -> the connector it was last shown on
        this._shown = new Map(remembered.shown);
        this._homes = new Map(remembered.homes);
        this._mirrors = new Map();
        this._last = global.workspace_manager.get_active_workspace();
        this._bringing = null;
        global.display.connectObject('restacked', () => this.queueMirrors(), this);
        global.workspace_manager.connectObject('workspace-removed', () => this._prune(), this);
    }

    disable() {
        global.display.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        if (this._mirrorLater)
            global.compositor.get_laters().remove(this._mirrorLater);
        this._mirrorLater = 0;
        for (const mirror of this._mirrors?.values() ?? [])
            mirror.destroy();
        this._mirrors = null;
        remembered.shown = new Map(this._shown ?? []);
        remembered.homes = new Map(this._homes ?? []);
    }

    get separate() {
        return Main.layoutManager.monitors.length > 1;
    }

    _connector(monitor) {
        return this._engine.connectorOf(monitor);
    }

    _index(connector) {
        return this._engine.indexOf(connector);
    }

    // The workspace a screen shows: GNOME's own with one screen (and, until the screens are assigned, everywhere)
    shownOn(monitor) {
        const active = global.workspace_manager.get_active_workspace();
        if (!this.separate)
            return active;
        return this._shown.get(this._connector(monitor)) ?? active;
    }

    // The screen a workspace is shown on, or -1
    monitorShowing(workspace) {
        for (const [connector, shown] of this._shown) {
            if (shown === workspace) {
                const index = this._index(connector);
                if (index >= 0)
                    return index;
            }
        }
        return -1;
    }

    // Where a workspace's strip belongs: the screen showing it, else the one it was last shown on, else `fallback`
    placeOf(workspace, fallback = Main.layoutManager.primaryIndex) {
        const showing = this.monitorShowing(workspace);
        if (showing >= 0)
            return showing;
        const home = this._index(this._homes.get(workspace));
        return home >= 0 ? home : fallback;
    }

    // The workspaces the cards of a screen go through: in their order, the ones of that screen (shown there or last
    // shown there) and the ones shown nowhere that have no windows; or, for the pile, every one not shown on another
    // screen, the most recent first
    workspacesFor(monitor, pile, history) {
        const manager = global.workspace_manager;
        const all = Array.from({length: manager.n_workspaces}, (unused, i) => manager.get_workspace_by_index(i));
        if (!this.separate)
            return pile ? history : all;
        const elsewhere = w => {
            const at = this.monitorShowing(w);
            return at >= 0 && at !== monitor;
        };
        if (pile)
            return history.filter(w => !elsewhere(w));
        return all.filter(w => {
            if (elsewhere(w))
                return false;
            if (this.monitorShowing(w) === monitor || this._index(this._homes.get(w)) === monitor)
                return true;
            return !w.list_windows().some(window => !window.is_on_all_workspaces());
        });
    }

    // ---- Showing a workspace on a screen ----

    // Puts `workspace` on `monitor`: the workspace that screen showed goes to where `workspace` was shown, or nowhere
    _place(workspace, monitor) {
        const connector = this._connector(monitor);
        if (!connector)
            return;
        const before = this.monitorShowing(workspace);
        const displaced = this._shown.get(connector);
        this._shown.set(connector, workspace);
        this._homes.set(workspace, connector);
        this._moveStrip(workspace, monitor);
        if (before >= 0 && before !== monitor) {
            const other = this._connector(before);
            if (displaced && displaced !== workspace) {
                this._shown.set(other, displaced);
                this._homes.set(displaced, other);
                this._moveStrip(displaced, before);
            } else {
                this._shown.delete(other);
            }
        }
        this._changed();
    }

    _moveStrip(workspace, monitor) {
        const engine = this._engine;
        const strip = engine.strip(workspace, monitor);
        if (strip.monitor !== monitor)
            engine.moveStrip(strip, monitor);
        engine.layout(strip, {animate: false});
    }

    _changed() {
        this.queueMirrors();
        this._engine.backgrounds?.sync();
        this._engine.tiling.topBar?.sync();
        this._engine.tiling.topBar?.applyTopBar();
    }

    // The tiling's own way to a workspace: shown on `monitor`, and GNOME's, without GNOME's slide
    bring(workspace, monitor) {
        const engine = this._engine;
        const active = global.workspace_manager.get_active_workspace();
        if (!this.separate || workspace === active) {
            if (this.separate && this.monitorShowing(workspace) !== monitor)
                this._place(workspace, monitor);
            if (workspace !== active)
                quietly(() => workspace.activate(global.get_current_time()));
            return;
        }
        this._bringing = monitor;
        try {
            const window = engine.strip(workspace, monitor).selected;
            quietly(() => {
                if (window)
                    workspace.activate_with_focus(window, global.get_current_time());
                else
                    workspace.activate(global.get_current_time());
            });
        } finally {
            this._bringing = null;
        }
    }

    // GNOME's workspace changed: the new one is shown where it belongs. Returns the screen it is on.
    switched(to) {
        const from = this._last;
        this._last = to;
        if (!this.separate)
            return -1;
        if (this._bringing !== null) {
            this._place(to, this._bringing);
            return this._bringing;
        }
        // Already on a screen: that screen gets the keyboard; else the screen it was last on shows it, the pointer
        // going there
        let target = this.monitorShowing(to);
        if (target < 0) {
            target = this.placeOf(to, this.monitorShowing(from) >= 0 ? this.monitorShowing(from)
                : Main.layoutManager.primaryIndex);
            this._place(to, target);
        } else {
            this._changed();
        }
        if (global.display.get_current_monitor() !== target)
            this._engine.tiling.actions?.warpTo(target);
        return target;
    }

    // Two screens exchange the workspaces they show; true when they did
    swap(a, b) {
        if (!this._enough())
            return false;
        const wa = this.shownOn(a), wb = this.shownOn(b);
        this._shown.set(this._connector(a), wb);
        this._shown.set(this._connector(b), wa);
        this._homes.set(wb, this._connector(a));
        this._homes.set(wa, this._connector(b));
        this._moveStrip(wa, b);
        this._moveStrip(wb, a);
        this._changed();
        return true;
    }

    // The workspace of screen `from` goes to `to`; `from` shows its most recent other workspace, or, having none,
    // what `to` showed
    moveSpace(from, to, history) {
        if (!this._enough())
            return false;
        const moving = this.shownOn(from);
        const shown = new Set(this._shown.values());
        const next = history.find(w => w !== moving && !shown.has(w) && this._index(this._homes.get(w)) === from) ??
            history.find(w => w !== moving && !shown.has(w));
        if (!next)
            return this.swap(from, to);
        this._place(moving, to);
        this._shown.set(this._connector(from), next);
        this._homes.set(next, this._connector(from));
        this._moveStrip(next, from);
        this._changed();
        return true;
    }

    // Moving workspaces between screens needs one to spare
    _enough() {
        const needed = Main.layoutManager.monitors.length + 1;
        if (global.workspace_manager.n_workspaces >= needed)
            return true;
        Main.notify(_('Not enough workspaces'),
            ngettext('Moving workspaces between screens needs %d workspace.',
                'Moving workspaces between screens needs %d workspaces.', needed).format(needed));
        return false;
    }

    // ---- Screens plugged in and out ----

    // After the screens changed (and at the start): every screen shows a workspace, each its own. The screen a
    // workspace was shown on shows it again; the one GNOME has is on a screen, the primary one if its own is gone;
    // the rest show the most recent workspaces not shown yet.
    assign(history) {
        if (!this.separate) {
            this._shown.clear();
            this.queueMirrors();
            return;
        }
        this._enoughForScreens();
        const monitors = Main.layoutManager.monitors;
        const manager = global.workspace_manager;
        const all = new Set(Array.from({length: manager.n_workspaces}, (unused, i) => manager.get_workspace_by_index(i)));
        const before = new Map(this._shown);
        this._shown.clear();
        const taken = new Set();
        monitors.forEach((m, index) => {
            const connector = this._connector(index);
            const workspace = before.get(connector);
            if (connector && workspace && all.has(workspace) && !taken.has(workspace)) {
                this._shown.set(connector, workspace);
                taken.add(workspace);
            }
        });
        const active = manager.get_active_workspace();
        if (!taken.has(active)) {
            const index = this._engine.focusMonitor();
            const connector = this._connector(index >= 0 && index < monitors.length ? index
                : Main.layoutManager.primaryIndex);
            const old = this._shown.get(connector);
            if (old)
                taken.delete(old);
            this._shown.set(connector, active);
            taken.add(active);
        }
        const order = [...history, ...all];
        monitors.forEach((m, index) => {
            const connector = this._connector(index);
            if (!connector || this._shown.has(connector))
                return;
            const workspace = order.find(w => all.has(w) && !taken.has(w));
            if (workspace) {
                this._shown.set(connector, workspace);
                taken.add(workspace);
            }
        });
        for (const [connector, workspace] of this._shown) {
            this._homes.set(workspace, connector);
            this._moveStrip(workspace, this._index(connector));
        }
        this._changed();
    }

    // Fewer workspaces than screens: workspaces are added, and said
    _enoughForScreens() {
        const manager = global.workspace_manager;
        const missing = Main.layoutManager.monitors.length - manager.n_workspaces;
        if (missing <= 0 || Meta.prefs_get_dynamic_workspaces())
            return;
        for (let i = 0; i < missing; i++)
            manager.append_new_workspace(false, global.get_current_time());
        Main.notify(_('Workspaces added'),
            ngettext('%d workspace was added, so that each screen shows a workspace of its own.',
                '%d workspaces were added, so that each screen shows a workspace of its own.', missing).format(missing));
    }

    _prune() {
        const manager = global.workspace_manager;
        const all = new Set(Array.from({length: manager.n_workspaces}, (unused, i) => manager.get_workspace_by_index(i)));
        for (const [connector, workspace] of [...this._shown]) {
            if (!all.has(workspace))
                this._shown.delete(connector);
        }
        for (const workspace of [...this._homes.keys()]) {
            if (!all.has(workspace))
                this._homes.delete(workspace);
        }
        this.queueMirrors();
    }

    // ---- The pictures of the workspaces GNOME does not show ----

    // Made again before the next frame, once for whatever changed meanwhile
    queueMirrors() {
        if (this._mirrorLater || !this._mirrors)
            return;
        this._mirrorLater = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._mirrorLater = 0;
            this._syncMirrors();
            return GLib.SOURCE_REMOVE;
        });
    }

    _syncMirrors() {
        if (!this._mirrors)
            return;
        const active = global.workspace_manager.get_active_workspace();
        const wanted = new Map();
        if (this.separate) {
            Main.layoutManager.monitors.forEach((m, index) => {
                const workspace = this._shown.get(this._connector(index));
                if (workspace && workspace !== active)
                    wanted.set(index, workspace);
            });
        }
        for (const [index, mirror] of [...this._mirrors]) {
            if (wanted.get(index) !== mirror.workspace) {
                mirror.destroy();
                this._mirrors.delete(index);
            }
        }
        for (const [index, workspace] of wanted) {
            let mirror = this._mirrors.get(index);
            if (!mirror) {
                mirror = new Mirror(this._engine, index, workspace);
                this._mirrors.set(index, mirror);
            }
            mirror.update();
        }
    }
}

// A screen's workspace while GNOME has another: a picture of each of its windows where the strip has it, and the focus
// frame, none of which takes the pointer (the pointer coming to this screen makes the workspace GNOME's anyway)
class Mirror {
    constructor(engine, monitor, workspace) {
        this._engine = engine;
        this._monitor = monitor;
        this.workspace = workspace;
        const m = Main.layoutManager.monitors[monitor];
        this.actor = new Clutter.Actor({
            x: m.x, y: m.y, width: m.width, height: m.height, clip_to_allocation: true, reactive: false,
        });
        // Over the workspaces' own pictures (backgrounds.js), else right over GNOME's backgrounds
        const background = engine.backgrounds?.layer ?? Main.layoutManager._backgroundGroup;
        if (background?.get_parent() === global.window_group)
            global.window_group.insert_child_above(this.actor, background);
        else
            global.window_group.insert_child_at_index(this.actor, 0);
    }

    update() {
        const engine = this._engine;
        const m = Main.layoutManager.monitors[this._monitor];
        if (!m)
            return;
        this.actor.set_position(m.x, m.y);
        this.actor.set_size(m.width, m.height);
        this.actor.destroy_all_children();
        const strip = engine.strip(this.workspace, this._monitor);
        const windows = global.display.sort_windows_by_stacking(this.workspace.list_windows().filter(window =>
            !window.is_on_all_workspaces() && !window.minimized && !window.is_override_redirect()));
        // The focus frame, as it is when the keyboard is elsewhere, right under its window
        const box = engine.boxFor(strip);
        box?.set_position(box.x - m.x, box.y - m.y);
        for (const window of windows) {
            const actor = window.get_compositor_private();
            const info = engine.info(window);
            if (!actor || info?.hidden)
                continue;
            const at = info?.strip && info.vis ? info.vis : window.get_frame_rect();
            if (!info?.strip && window.get_monitor() !== this._monitor)
                continue;
            if (window === strip.selected && box)
                this.actor.add_child(box);
            const frame = window.get_frame_rect();
            const buffer = window.get_buffer_rect();
            this.actor.add_child(new Clutter.Clone({
                source: actor, x: at.x + buffer.x - frame.x - m.x, y: at.y + buffer.y - frame.y - m.y,
            }));
        }
        if (box && !box.get_parent())
            box.destroy();
    }

    destroy() {
        this.actor.destroy();
    }
}

// A workspace made GNOME's without its slide: the cards or the pointer have already shown the way there
export function quietly(activate) {
    const wm = Main.wm;
    const had = Object.prototype.hasOwnProperty.call(wm, '_shouldAnimate');
    const own = wm._shouldAnimate;
    wm._shouldAnimate = () => false;
    try {
        activate();
    } finally {
        if (had)
            wm._shouldAnimate = own;
        else
            delete wm._shouldAnimate;
    }
}
