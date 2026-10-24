// Application windows on glass. Every window but the one being used shows the frosted desktop faintly through it:
// a pane of glass cut to its frame, with the window drawn over it at 84 %. The window with the keyboard focus, a
// fullscreen window, and every window in the overview or a window switcher's previews are fully opaque, with nothing
// drawn behind them. A maximized or tiled window's glass has square corners, so that it meets the screen's edges.
// Docks, desktop icons and desktop widgets are left alone. This part also tells the top bar when windows move.

import Meta from 'gi://Meta';

// The kinds of window that have glass, and are counted as touching the top bar
export const TYPES = new Set([Meta.WindowType.NORMAL, Meta.WindowType.DIALOG, Meta.WindowType.MODAL_DIALOG]);
// Left alone, by their class: a dock, the desktop icons and desktop widgets
const LEFT_ALONE = new Set(['plank', 'com.desktop.ding', 'conky']);
// The window over its glass, out of 255
const OPACITY = 215;
const RADIUS = 16;

// The glass under a window is its frame, inside the actor, which also holds the window's own shadow
const frame = actor => {
    const window = actor.meta_window ?? actor.source?.meta_window;
    if (!window)
        return [];
    const f = window.get_frame_rect();
    const b = window.get_buffer_rect();
    return [[f.x - b.x, f.y - b.y, f.width, f.height]];
};
const content = actor => Math.round(actor.get_paint_opacity() * OPACITY / 255);

export function leftAlone(window) {
    const name = window.get_wm_class()?.toLowerCase();
    return !name || LEFT_ALONE.has(name);
}

export class Windows {
    constructor(glass) {
        this._glass = glass;
    }

    enable() {
        this._windows = new Set();
        this._actors = new Set();
        this._queued = new Set();
        this._listeners = new Set();
        this._laterId = 0;
        global.display.connectObject(
            'window-created', (display, window) => this._watch(window),
            'notify::focus-window', () => this._queueAll(),
            this);
        global.workspace_manager.connectObject('active-workspace-changed', () => this._changed(), this);
        for (const actor of global.get_window_actors())
            this._watch(actor.meta_window);
    }

    disable() {
        global.display.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        if (this._laterId)
            global.compositor.get_laters().remove(this._laterId);
        this._laterId = 0;
        for (const window of this._windows)
            window.disconnectObject(this);
        for (const actor of this._actors) {
            actor.disconnectObject(this);
            this._glass.detach(actor);
        }
        this._windows = this._actors = this._queued = this._listeners = null;
    }

    // Called whenever a window is added, goes, moves, changes size, shows or hides, or the workspace changes
    onChange(listener) {
        this._listeners.add(listener);
    }

    get windows() {
        return this._windows;
    }

    // The look of a copy of a window that has glass, as the workspace switch slides it in
    cloneLook() {
        return {material: 'glass', radius: RADIUS, areas: frame, content, inClones: false, stageOnly: true};
    }

    _watch(window) {
        if (!window || this._windows.has(window))
            return;
        this._windows.add(window);
        const queue = () => this._queue(window);
        window.connectObject(
            'notify::fullscreen', queue,
            'notify::maximized-horizontally', queue,
            'notify::maximized-vertically', queue,
            'notify::wm-class', queue,
            'notify::minimized', () => this._changed(),
            'position-changed', () => this._changed(),
            'size-changed', () => this._changed(),
            'workspace-changed', () => this._changed(),
            'shown', queue,
            'unmanaged', () => {
                window.disconnectObject(this);
                this._windows.delete(window);
                this._queued.delete(window);
                this._changed();
            },
            this);
        queue();
        this._changed();
    }

    _queueAll() {
        for (const window of this._windows)
            this._queue(window);
    }

    // Done once before the next frame, however many changes come in
    _queue(window) {
        this._queued.add(window);
        if (this._laterId)
            return;
        this._laterId = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._laterId = 0;
            for (const queued of this._queued)
                this._sync(queued);
            this._queued.clear();
            return false;
        });
    }

    _changed() {
        for (const listener of this._listeners)
            listener();
    }

    _wantsGlass(window) {
        return TYPES.has(window.get_window_type()) && !window.is_override_redirect() &&
            !window.is_attached_dialog() && !window.is_fullscreen() && !leftAlone(window) &&
            window !== global.display.focus_window;
    }

    _sync(window) {
        if (!this._windows.has(window))
            return;
        const actor = window.get_compositor_private();
        if (!actor)
            return;
        if (!this._actors.has(actor)) {
            this._actors.add(actor);
            actor.connectObject(
                'notify::visible', () => this._changed(),
                'destroy', () => this._actors?.delete(actor),
                this);
        }
        if (!this._wantsGlass(window)) {
            this._glass.detach(actor);
            return;
        }
        const square = window.maximized_horizontally || window.maximized_vertically;
        this._glass.attach(actor, {
            material: 'glass',
            radius: square ? 0 : RADIUS,
            areas: frame,
            content,
            inClones: false,
            stageOnly: true,
        });
    }
}
