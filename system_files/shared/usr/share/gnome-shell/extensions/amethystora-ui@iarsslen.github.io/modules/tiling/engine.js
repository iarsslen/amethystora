// The strips: which windows tile, in what order, where each one is, and how they glide there.
//
// A window's place on screen is where the strip says, always. GNOME lets a window go only so far past the edge
// of the screen, so the frame goes as close as GNOME allows and the window actor's translation makes up the
// rest; a window that is entirely off its monitor is hidden. Gliding moves that drawn place from where it was to
// where it belongs over the animation time, with the frame already at the end, so that GNOME's own size and
// position never lag behind more than one move.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {adjustAnimationTime} from 'resource:///org/gnome/shell/misc/animationUtils.js';

import * as Layout from './layout.js';

// Milliseconds of a glide, before GNOME's own speed setting
export const ANIMATION = 250;
// How long an app's size has to stay for the strip to take it
const SIZE_SETTLE = 300;
// The least of a window GNOME keeps on screen, with a little room
const ONSCREEN = 80;
// How far the focus box stands out around its window
const OUTLINE = 8;
// The focus box's opacity while its window does not have the keyboard
const INACTIVE = 140;
// The open positions the key and the icon cycle through
export const Open = {RIGHT: 0, LEFT: 1, DOWN: 4};
export const OPEN_CYCLE = [Open.RIGHT, Open.LEFT, Open.DOWN];

// The effect a window cut at its screen's edge carries; it draws nothing of its own
const CUT = 'amethystora-tiling-cut';
const Uncovered = GObject.registerClass(class Uncovered extends Clutter.Effect {});

// What survives the tiling being stopped and started again in the same session: at every screen lock, and when
// it is switched off and on
const remembered = {strips: [], windows: new WeakMap(), floating: new Set()};

// Which screen each screen number is, by its connector. The numbers shift when a screen other than the last is
// unplugged, so a strip follows its screen by this and not by its number.
function connectors() {
    const list = [];
    for (const logical of global.backend.get_monitor_manager().get_logical_monitors())
        list[logical.get_number()] = logical.get_monitors()[0]?.get_connector() ?? null;
    return list;
}

export class Strip {
    constructor(workspace, monitor) {
        this.workspace = workspace;
        this.monitor = monitor;
        // Each column is its windows from the top
        this.columns = [];
        // The screen x of the strip's left end, from the left of the work area
        this.scroll = 0;
        this.mode = Layout.Mode.PLAIN;
        // The window the strip shows as focused, the keyboard's or the one a navigation is on
        this.selected = null;
        // While centring: which half the window was in before, to put it back there
        this.side = 0;
    }

    get windows() {
        return this.columns.flat();
    }

    find(window) {
        for (let c = 0; c < this.columns.length; c++) {
            const r = this.columns[c].indexOf(window);
            if (r >= 0)
                return [c, r];
        }
        return null;
    }
}

export class Engine {
    constructor(tiling) {
        this.tiling = tiling;
    }

    enable() {
        this._strips = new Map();
        this._info = new Map();
        this.floating = new Set();
        this._boxes = new Map();
        this._glides = new Map();
        this.session = null;
        this.dragging = null;
        this._connectors = connectors();
        // Something drawn over the strips that the focus box gives way to
        this.boxHidden = 0;

        const display = global.display;
        display.connectObject(
            'window-created', (d, window) => this._created(window),
            'notify::focus-window', () => this._focusChanged(),
            'grab-op-begin', (d, window, op) => this._grabBegan(window, op),
            'grab-op-end', (d, window) => this._grabEnded(window),
            'workareas-changed', () => this.layoutAll(false),
            'restacked', () => this._restackBoxes(),
            this);
        global.workspace_manager.connectObject(
            'active-workspace-changed', () => this._workspaceChanged(),
            'workspace-removed', () => this._prune(),
            this);
        Main.layoutManager.connectObject('monitors-changed', () => this._monitorsChanged(), this);
        Main.overview.connectObject('hidden', () => this._overviewHidden(), this);

        this._restore();
    }

    // suspend: the screen is locking. What the strips are is kept for unlock, and everything drawn is put back.
    disable(suspend = false) {
        global.display.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        Main.overview.disconnectObject(this);
        for (const glide of this._glides?.values() ?? [])
            glide.timeline.stop();
        this._glides = null;
        this._remember();
        for (const box of this._boxes?.values() ?? [])
            box.destroy();
        this._boxes = null;
        if (!suspend) {
            for (const window of this.floating ?? [])
                this._unfloatFlags(window);
        }
        for (const [window, info] of [...this._info ?? []]) {
            this._untrack(window);
            if (!suspend)
                this._release(window, info);
            else
                this._unhide(window, info);
        }
        this._info = null;
        this._strips = null;
        this.floating = null;
    }

    // ---- The model ----

    info(window) {
        return this._info.get(window) ?? null;
    }

    stripOf(window) {
        return this._info.get(window)?.strip ?? null;
    }

    strip(workspace, monitor) {
        let byMonitor = this._strips.get(workspace);
        if (!byMonitor) {
            byMonitor = new Map();
            this._strips.set(workspace, byMonitor);
        }
        let strip = byMonitor.get(monitor);
        if (!strip) {
            strip = new Strip(workspace, monitor);
            byMonitor.set(monitor, strip);
        }
        return strip;
    }

    // None once the engine has stopped: things that outlive it (the cards zooming at a screen lock) ask all the same
    strips() {
        return [...this._strips?.values() ?? []].flatMap(byMonitor => [...byMonitor.values()]);
    }

    // The monitor the keyboard is on: the focused window's, or the pointer's
    focusMonitor() {
        const focus = global.display.focus_window;
        if (focus && !focus.is_override_redirect())
            return this.stripOf(focus)?.monitor ?? focus.get_monitor();
        return global.display.get_current_monitor();
    }

    activeStrip(monitor = this.focusMonitor()) {
        return this.strip(global.workspace_manager.get_active_workspace(), monitor);
    }

    area(monitor) {
        return Main.layoutManager.getWorkAreaForMonitor(monitor);
    }

    // The window a command acts on: the one a navigation is on, else the focused one
    current() {
        if (this.session)
            return this.session.strip.selected;
        return global.display.focus_window;
    }

    isTiled(window) {
        return !!this._info.get(window)?.strip;
    }

    // Whether a window belongs in a strip at all
    tileable(window) {
        if (!window || window.is_override_redirect() || window.get_window_type() !== Meta.WindowType.NORMAL)
            return false;
        if (window.get_transient_for() || window.is_on_all_workspaces() || this.floating.has(window))
            return false;
        return !floatsByRule(window);
    }

    // ---- Windows coming and going ----

    _created(window) {
        if (window.get_window_type() !== Meta.WindowType.NORMAL)
            return;
        this._track(window);
        if (floatsByRule(window)) {
            this.float(window, {glide: false});
            window.get_compositor_private()?.connectObject('first-frame', () => activate(window), this);
            return;
        }
        if (!this.tileable(window))
            return;
        // A new window goes where the person is looking, not where its app asked
        const active = global.workspace_manager.get_active_workspace();
        if (window.get_workspace() !== active)
            window.change_workspace(active);
        const info = this._info.get(window);
        info.fresh = true;
        // Every new tiled window gets the keyboard once it is drawn, whatever GNOME thought of its asking
        let drawn = false;
        window.get_compositor_private()?.connectObject('first-frame', () => {
            drawn = true;
            if (!info.fresh && this.isTiled(window))
                activate(window);
        }, this);
        // The app chooses its width when it first draws: the strip takes it in then
        const settle = () => {
            if (!info.fresh || !this._info?.has(window))
                return;
            info.fresh = false;
            // A dialog says whose it is after it is made: it floats, as GNOME has it
            if (!this.tileable(window))
                return;
            this.insert(window, this.activeStrip(), {appear: true});
            if (drawn)
                activate(window);
        };
        if (window.get_frame_rect().width > 0)
            settle();
        else
            window.connectObject('size-changed', settle, this);
    }

    _track(window) {
        if (this._info.has(window))
            return this._info.get(window);
        const info = {
            width: 0, height: 0, lastX: null, everFocused: false, ...remembered.windows.get(window),
            strip: null, vis: null, target: null, hidden: false,
        };
        this._info.set(window, info);
        window.connectObject(
            'unmanaging', () => this._unmanaging(window),
            'size-changed', () => this._sizeChanged(window),
            'position-changed', () => this._positionChanged(window),
            'workspace-changed', () => this._workspaceOfWindowChanged(window),
            'notify::minimized', () => this._minimizedChanged(window),
            'notify::fullscreen', () => this._fullscreenChanged(window),
            'notify::maximized-horizontally', () => this._maximizedChanged(window),
            'notify::maximized-vertically', () => this._maximizedChanged(window),
            'notify::on-all-workspaces', () => this._stickyChanged(window),
            'notify::window-type', () => this._kindChanged(window),
            this);
        window.get_compositor_private()?.connectObject('notify::visible', actor => {
            // GNOME shows a window again on its own occasions: one off the screen stays hidden
            if (actor.visible && this._info?.get(window)?.hidden)
                actor.hide();
        }, this);
        return info;
    }

    _untrack(window) {
        const info = this._info.get(window);
        if (info?.sizeCheck)
            GLib.source_remove(info.sizeCheck);
        window.disconnectObject(this);
        const actor = window.get_compositor_private();
        actor?.disconnectObject(this);
        this._info.delete(window);
    }

    // The window drawn where its frame is, and shown if GNOME shows it
    _unhide(window, info) {
        const actor = window.get_compositor_private();
        if (!actor)
            return;
        if (!busy(actor)) {
            actor.translation_x = 0;
            actor.translation_y = 0;
        }
        if (info.clipped) {
            actor.remove_clip();
            actor.remove_effect_by_name(CUT);
            info.clipped = false;
        }
        if (info.hidden) {
            info.hidden = false;
            if (window.showing_on_its_workspace() &&
                window.located_on_workspace(global.workspace_manager.get_active_workspace()))
                actor.show();
        }
    }

    // Puts a window back the way GNOME would have it
    _release(window, info) {
        this._unhide(window, info);
        if (!info.strip || window.is_fullscreen() || !window.get_compositor_private())
            return;
        // Nothing stays off its screen: a window the strip had pushed aside comes back inside it, as large as fits
        const area = this.area(info.strip.monitor);
        const frame = window.get_frame_rect();
        const width = Math.min(frame.width, area.width);
        const height = Math.min(frame.height, area.height);
        const x = Math.max(area.x, Math.min(frame.x, area.x + area.width - width));
        const y = Math.max(area.y, Math.min(frame.y, area.y + area.height - height));
        if (x !== frame.x || y !== frame.y || width !== frame.width || height !== frame.height)
            window.move_resize_frame(false, x, y, width, height);
    }

    _unmanaging(window) {
        const strip = this.stripOf(window);
        this.floating.delete(window);
        if (strip) {
            const order = strip.windows;
            const index = order.indexOf(window);
            const wasSelected = strip.selected === window;
            this.remove(window, {layout: false});
            if (wasSelected) {
                // The neighbour in strip order used most recently
                const before = order[index - 1], after = order[index + 1];
                const mru = global.display.get_tab_list(Meta.TabList.NORMAL_ALL, strip.workspace);
                const rank = w => w ? mru.indexOf(w) : -1;
                let next = before ?? after ?? null;
                if (before && after && rank(after) >= 0 && (rank(before) < 0 || rank(after) < rank(before)))
                    next = after;
                strip.selected = next;
                if (next && window.has_focus())
                    Main.activateWindow(next);
            }
            this.closeUp(strip);
        }
        this._untrack(window);
    }

    // `place` puts it at a given column, or into it at a given row, rather than beside a window
    insert(window, strip, options = {}) {
        const {position = this.tiling.openPosition, appear = false, place = null} = options;
        const info = this._track(window);
        const old = info.strip;
        if (old)
            this.remove(window, {layout: false});
        const near = 'near' in options ? options.near : strip.selected;
        if (window.is_above())
            window.unmake_above();
        if (window.maximized_horizontally || window.maximized_vertically) {
            window.unmaximize();
            info.width = Layout.maxWidth(this.area(strip.monitor)) - 2 * (Layout.MARGIN - Layout.MIN_MARGIN);
        }
        if (window.get_workspace() !== strip.workspace && !window.is_on_all_workspaces())
            window.change_workspace(strip.workspace);
        const frame = window.get_frame_rect();
        if (!info.width)
            info.width = frame.width || Math.floor(Layout.available(this.area(strip.monitor)) / 2);
        info.height = 0;
        info.strip = strip;
        const at = near ? strip.find(near) : null;
        if (place && place.row >= 0 && strip.columns[place.column]) {
            const column = strip.columns[place.column];
            column.splice(Math.min(place.row, column.length), 0, window);
            for (const w of column)
                this._info.get(w).height = 0;
        } else if (place) {
            strip.columns.splice(Math.min(place.column, strip.columns.length), 0, [window]);
        } else if (!at) {
            strip.columns.push([window]);
        } else if (position === Open.DOWN) {
            const column = strip.columns[at[0]];
            column.splice(at[1] + 1, 0, window);
            for (const w of column)
                this._info.get(w).height = 0;
        } else {
            strip.columns.splice(at[0] + (position === Open.LEFT ? 0 : 1), 0, [window]);
        }
        strip.selected = window;
        // A brand-new window appears in its place; one coming from elsewhere glides from where it was
        if (appear)
            info.vis = null;
        else if (!info.vis)
            info.vis = this.visual(window);
        this.ensureVisible(strip, window, {appear: appear ? window : null});
        // The strip it came from closes up
        if (old && old !== strip)
            this.closeUp(old);
    }

    remove(window, {layout = true} = {}) {
        const info = this._info.get(window);
        const strip = info?.strip;
        if (!strip)
            return;
        const at = strip.find(window);
        if (at) {
            const column = strip.columns[at[0]];
            column.splice(at[1], 1);
            if (!column.length)
                strip.columns.splice(at[0], 1);
            else
                column.forEach(w => (this._info.get(w).height = 0));
        }
        if (strip.selected === window)
            strip.selected = strip.windows[0] ?? null;
        info.strip = null;
        info.target = null;
        const actor = window.get_compositor_private();
        this._glides.get(strip)?.windows.delete(window);
        if (info.hidden) {
            info.hidden = false;
            if (window.showing_on_its_workspace())
                actor?.show();
        }
        if (layout)
            this.closeUp(strip);
    }

    // The strip after a window left it: closed up, and still showing the window it shows as focused
    closeUp(strip) {
        if (strip.selected)
            this.ensureVisible(strip, strip.selected);
        else
            this.layout(strip);
    }

    // ---- Floating ----

    // Takes a window out of the strip into the floating layer: above the others, on every workspace
    float(window, {glide = true} = {}) {
        const info = this._track(window);
        const strip = info.strip;
        const from = this.visual(window);
        if (strip)
            this.remove(window);
        this.floating.add(window);
        if (!window.is_above()) {
            window.make_above();
            info.madeAbove = true;
        }
        if (!window.is_on_all_workspaces()) {
            window.stick();
            info.madeSticky = true;
        }
        const actor = window.get_compositor_private();
        if (actor) {
            actor.translation_x = 0;
            actor.translation_y = 0;
        }
        if (!glide)
            return;
        const monitor = window.get_monitor();
        let frame = info.floatFrame?.monitor === monitor ? {...info.floatFrame} : null;
        if (!frame) {
            const lower = 30;
            frame = {
                x: from.x, y: from.y + lower, width: from.width,
                height: Math.min(from.height - lower, Math.round(from.height * 0.9)),
            };
        }
        this.glideFloating(window, from, frame);
    }

    // Puts a floating window back into the strip of the workspace shown
    unfloat(window, {position, near} = {}) {
        const info = this._track(window);
        const frame = window.get_frame_rect();
        info.floatFrame = {
            x: frame.x, y: frame.y, width: frame.width, height: frame.height,
            monitor: window.get_monitor(),
        };
        this.floating.delete(window);
        this._unfloatFlags(window);
        const strip = this.activeStrip(window.get_monitor());
        info.width = frame.width;
        this.insert(window, strip, {position, near});
    }

    _unfloatFlags(window) {
        const info = this._info?.get(window) ?? remembered.windows.get(window) ?? {};
        if (info.madeAbove && window.is_above())
            window.unmake_above();
        if (info.madeSticky && window.is_on_all_workspaces())
            window.unstick();
        info.madeAbove = false;
        info.madeSticky = false;
    }

    // A floating window moved by the tiling, drawn gliding from `from` to `to`
    glideFloating(window, from, to) {
        window.move_resize_frame(false, to.x, to.y, to.width, to.height);
        const actor = window.get_compositor_private();
        const frame = window.get_frame_rect();
        if (!actor || busy(actor))
            return;
        actor.translation_x = from.x - frame.x;
        actor.translation_y = from.y - frame.y;
        actor.ease({
            translation_x: 0,
            translation_y: 0,
            duration: ANIMATION,
            mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
            onStopped: () => window.activate(global.get_current_time()),
        });
    }

    // ---- Layout ----

    visual(window) {
        const frame = window.get_frame_rect();
        const actor = window.get_compositor_private();
        return {
            x: frame.x + Math.round(actor?.translation_x ?? 0),
            y: frame.y + Math.round(actor?.translation_y ?? 0),
            width: frame.width,
            height: frame.height,
        };
    }

    // Where every window of a strip goes, for its scroll as it is
    geometry(strip) {
        const area = this.area(strip.monitor);
        const use = Layout.usable(area);
        const monitor = Main.layoutManager.monitors[strip.monitor];
        const widths = strip.columns.map(column => {
            if (column.some(w => w.is_fullscreen()))
                return monitor.width;
            const holder = column.includes(strip.selected) ? strip.selected : null;
            const width = holder ? this._info.get(holder).width
                : Math.max(...column.map(w => this._info.get(w).width));
            return Math.max(1, Math.min(width, Layout.maxWidth(area)));
        });
        const placed = Layout.columns(widths);
        const centred = Layout.centred(area, placed);
        const scroll = centred ?? strip.scroll;
        const rects = new Map();
        strip.columns.forEach((column, c) => {
            const x = area.x + scroll + placed.columns[c].x;
            const width = placed.columns[c].width;
            if (column.length === 1 && column[0].is_fullscreen()) {
                rects.set(column[0], {x, y: monitor.y, width, height: monitor.height});
                return;
            }
            const keep = column.indexOf(strip.selected);
            const hs = Layout.heights(use.height, column.map(w => this._info.get(w).height), keep);
            let y = use.y;
            column.forEach((w, r) => {
                rects.set(w, {x, y, width, height: hs[r]});
                y += hs[r] + Layout.GAP;
            });
        });
        return {area, rects, columns: placed.columns, width: placed.width, scroll, centred: centred !== null};
    }

    // Scrolls a strip so that a window is shown by the workspace's focus mode, then lays it out
    ensureVisible(strip, window, {animate = true, appear = null, from = null} = {}) {
        const at = strip.find(window);
        if (!at) {
            this.layout(strip, {animate, appear});
            return;
        }
        const geo = this.geometry(strip);
        const column = geo.columns[at[0]];
        const info = this._info.get(window);
        if (window.is_fullscreen()) {
            const monitor = Main.layoutManager.monitors[strip.monitor];
            strip.scroll = monitor.x - geo.area.x - column.x;
        } else if (!geo.centred) {
            const now = geo.scroll + column.x;
            const shown = now < geo.area.width && now + column.width > 0;
            const previous = from ?? -1;
            const neighbour = previous >= 0 && Math.abs(previous - at[0]) === 1;
            const start = neighbour || shown || !info.everFocused || info.lastX === null ? now : info.lastX;
            const x = Layout.placeFocused(geo.area, column, start, strip.mode, at[0], geo.columns.length);
            strip.scroll = Math.round(x - column.x);
        }
        this.layout(strip, {animate, appear});
    }

    layoutAll(animate = true) {
        for (const strip of this.strips())
            this.layout(strip, {animate});
    }

    // Puts every window of a strip in its place, gliding unless `animate` is false
    // `time` and `mode` are for a glide a gesture asks for: as long as its momentum, in its own curve
    layout(strip, {
        animate = true, appear = null, time = ANIMATION,
        mode = Clutter.AnimationMode.EASE_IN_OUT_QUAD,
    } = {}) {
        if (!this._strips)
            return;
        const geo = this.geometry(strip);
        const showing = strip.workspace === global.workspace_manager.get_active_workspace();
        const duration = animate && showing ? adjustAnimationTime(time) : 0;
        const moving = [];
        for (const [window, rect] of geo.rects) {
            const info = this._info.get(window);
            info.target = rect;
            this._request(window, rect, strip);
            const start = window === appear || !info.vis ? rect : {...info.vis};
            moving.push([window, start, rect]);
        }
        this._glides.get(strip)?.timeline.stop();
        this._glides.delete(strip);
        // Nothing to glide: no frame is drawn for it
        const still = moving.every(([, from, to]) => from.x === to.x && from.y === to.y);
        if (!duration || still || this.dragging?.strip === strip) {
            for (const [window, , rect] of moving)
                this._show(window, rect, strip);
            this._settled(strip);
            return;
        }
        const timeline = new Clutter.Timeline({actor: global.stage, duration});
        timeline.set_progress_mode(mode);
        const glide = {timeline, windows: new Map(moving.map(([w, from, to]) => [w, {from, to}]))};
        const step = progress => {
            for (const [window, {from, to}] of glide.windows) {
                this._show(window, {
                    x: Math.round(from.x + (to.x - from.x) * progress),
                    y: Math.round(from.y + (to.y - from.y) * progress),
                    width: to.width,
                    height: to.height,
                }, strip);
            }
            this.updateBox(strip);
        };
        timeline.connect('new-frame', () => step(timeline.get_progress()));
        timeline.connect('stopped', (t, finished) => {
            if (!finished)
                return;
            if (this._glides?.get(strip) === glide)
                this._glides.delete(strip);
            step(1);
            this._settled(strip);
        });
        this._glides.set(strip, glide);
        step(0);
        timeline.start();
    }

    // Sets how far a strip has scrolled and draws it there at once: for gestures that follow a finger
    scrollTo(strip, scroll) {
        strip.scroll = Math.round(scroll);
        const geo = this.geometry(strip);
        for (const [window, rect] of geo.rects) {
            this._info.get(window).target = rect;
            this._show(window, rect, strip);
        }
        this.updateBox(strip);
        return geo;
    }

    // After a strip comes to rest: where each window was, for coming back to it, and the frames
    _settled(strip) {
        const geo = this.geometry(strip);
        for (const [window, rect] of geo.rects) {
            this._request(window, rect, strip);
            if (window === strip.selected)
                this._info.get(window).lastX = rect.x - geo.area.x;
        }
        this.updateBox(strip);
        // A fullscreen window scrolled away, or back: the top bar follows (topbar.js)
        if (strip.windows.some(w => w.is_fullscreen()))
            Main.layoutManager._updateVisibility();
    }

    // Whether a fullscreen window really covers a monitor: GNOME counts one the strip has scrolled away too
    coversMonitor(index) {
        const monitor = Main.layoutManager.monitors[index];
        if (!monitor)
            return false;
        return global.display.list_all_windows().some(window => {
            if (!window.is_fullscreen() || window.minimized || window.get_monitor() !== index)
                return false;
            const info = this._info.get(window);
            if (!info?.strip)
                return true;
            return !info.hidden && info.vis && Math.abs(info.vis.x - monitor.x) < monitor.width / 2;
        });
    }

    // Asks GNOME for a window's frame as close to its place as it allows
    _request(window, rect, strip) {
        if (window.is_fullscreen() || this.dragging?.window === window)
            return;
        const monitor = Main.layoutManager.monitors[strip.monitor];
        const several = Main.layoutManager.monitors.length > 1;
        let x = rect.x;
        if (several) {
            // Kept on its own monitor, so that GNOME counts it as there
            x = Math.max(monitor.x, Math.min(x, monitor.x + monitor.width - Math.min(rect.width, monitor.width)));
        } else {
            x = Math.max(monitor.x + ONSCREEN - rect.width, Math.min(x, monitor.x + monitor.width - ONSCREEN));
        }
        const frame = window.get_frame_rect();
        const info = this._info.get(window);
        info.asked = {x, y: rect.y, width: rect.width, height: rect.height};
        if (frame.x !== x || frame.y !== rect.y || frame.width !== rect.width || frame.height !== rect.height)
            window.move_resize_frame(false, x, rect.y, rect.width, rect.height);
    }

    // Draws a window at `vis`, hiding it when none of it is on its monitor
    _show(window, vis, strip) {
        const info = this._info.get(window);
        const actor = window.get_compositor_private();
        if (!info || !actor)
            return;
        info.vis = vis;
        if (!busy(actor)) {
            const frame = window.get_frame_rect();
            actor.translation_x = vis.x - frame.x;
            actor.translation_y = vis.y - frame.y;
        }
        const monitor = Main.layoutManager.monitors[strip.monitor];
        const onScreen = vis.x < monitor.x + monitor.width && vis.x + vis.width > monitor.x;
        this._clip(actor, info, vis, monitor);
        if (onScreen === !info.hidden)
            return;
        info.hidden = !onScreen;
        if (info.hidden)
            actor.hide();
        else if (window.showing_on_its_workspace() &&
            window.located_on_workspace(global.workspace_manager.get_active_workspace()))
            actor.show();
    }

    // With several screens a window that reaches past its own is cut at its edge, so that none of it shows on the
    // next screen; never while GNOME takes a screenshot, which takes windows whole
    _clip(actor, info, vis, monitor) {
        const past = vis.x < monitor.x || vis.x + vis.width > monitor.x + monitor.width;
        const wanted = past && !this.unclipped && Main.layoutManager.monitors.length > 1;
        if (wanted) {
            const left = actor.x + actor.translation_x;
            const top = actor.y + actor.translation_y;
            actor.set_clip(monitor.x - left, monitor.y - top, monitor.width, monitor.height);
            // Mutter leaves out what it thinks a window covers when it draws the desktop, without looking at the
            // cut: an effect on the window makes it look again
            if (!info.clipped)
                actor.add_effect_with_name(CUT, new Uncovered());
            info.clipped = true;
        } else if (info.clipped) {
            actor.remove_clip();
            actor.remove_effect_by_name(CUT);
            info.clipped = false;
        }
    }

    // GNOME's screenshot tool opened or closed: the cut edges go and come back
    setUnclipped(unclipped) {
        this.unclipped = unclipped;
        for (const strip of this.strips()) {
            for (const window of strip.windows) {
                const info = this._info.get(window);
                const actor = window.get_compositor_private();
                if (info?.vis && actor)
                    this._clip(actor, info, info.vis, Main.layoutManager.monitors[strip.monitor]);
            }
        }
    }

    _sizeChanged(window) {
        const info = this._info?.get(window);
        // A maximized frame is on its way to filling the width instead, and a fullscreen one is the screen's
        if (!info?.strip || window.is_fullscreen() || info.unmaximizing ||
            window.maximized_horizontally || window.maximized_vertically)
            return;
        const frame = window.get_frame_rect();
        const grab = this.dragging?.window === window || this._resizing === window;
        // The person dragging an edge chose another size: the strip takes it
        if (grab) {
            info.width = frame.width;
            info.height = frame.height;
            this.layout(info.strip, {animate: false});
            return;
        }
        if (info.vis)
            this._show(window, info.vis, info.strip);
        // So did the app, if its width still is not the one asked for a moment later: an app answers several
        // requests in turn, and only the last answer is its choice
        if (info.asked && frame.width !== info.asked.width && !info.sizeCheck) {
            info.sizeCheck = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SIZE_SETTLE, () => {
                info.sizeCheck = 0;
                const now = window.get_frame_rect();
                if (this._info?.get(window) === info && info.strip && info.asked && !window.is_fullscreen() &&
                    !window.maximized_horizontally && !window.maximized_vertically &&
                    now.width !== info.asked.width) {
                    info.width = now.width;
                    this.layout(info.strip);
                }
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    _positionChanged(window) {
        const info = this._info?.get(window);
        if (!info?.strip || !info.vis || this.dragging?.window === window || this._resizing === window)
            return;
        const frame = window.get_frame_rect();
        // Something other than the tiling moved a tiled window: it goes back, once per change it makes
        if (info.asked && !window.is_fullscreen() && !this._glides.has(info.strip) &&
            (frame.x !== info.asked.x || frame.y !== info.asked.y) && info.corrected !== `${frame.x},${frame.y}`) {
            info.corrected = `${frame.x},${frame.y}`;
            window.move_frame(false, info.asked.x, info.asked.y);
            return;
        }
        this._show(window, info.vis, info.strip);
        if (info.strip.selected === window)
            this.updateBox(info.strip);
    }

    // ---- Focus ----

    _focusChanged() {
        const window = global.display.focus_window;
        if (this.session || !window) {
            this._syncBoxes();
            return;
        }
        const info = this._info.get(window);
        if (info?.strip) {
            const strip = info.strip;
            const previous = strip.selected ? strip.find(strip.selected)?.[0] ?? -1 : -1;
            strip.selected = window;
            this._fullscreenAbove(strip, window);
            this.ensureVisible(strip, window, {from: previous});
            info.everFocused = true;
            this.restack(strip, window);
        }
        this._syncBoxes();
    }

    // A fullscreen window stays above everything only while it has the keyboard
    _fullscreenAbove(strip, focused) {
        for (const window of strip.windows) {
            const info = this._info.get(window);
            if (!window.is_fullscreen() || info.wasAbove)
                continue;
            if (window === focused && !window.is_above())
                window.make_above();
            else if (window !== focused && window.is_above())
                window.unmake_above();
        }
    }

    // A tiled window being resized by its edge, or dragged by its title bar
    _grabBegan(window, op) {
        if (!this.isTiled(window))
            return;
        if (isResize(op))
            this._resizing = window;
    }

    _grabEnded(window) {
        if (this._resizing !== window)
            return;
        this._resizing = null;
        const info = this._info.get(window);
        if (info?.strip) {
            const frame = window.get_frame_rect();
            info.width = frame.width;
            info.height = frame.height;
            this.ensureVisible(info.strip, window);
        }
    }

    // The focused window on top, and its neighbours in the strip right under it, so that when it closes GNOME
    // gives the keyboard to one of them
    restack(strip, window) {
        const order = strip.windows;
        const index = order.indexOf(window);
        const neighbours = [order[index - 1], order[index + 1]].filter(Boolean);
        const mru = global.display.get_tab_list(Meta.TabList.NORMAL_ALL, strip.workspace);
        neighbours.sort((a, b) => mru.indexOf(b) - mru.indexOf(a));
        for (const w of neighbours)
            w.raise();
        window.raise();
    }

    // Gives a strip's selected window the keyboard
    focus(strip) {
        const window = strip.selected;
        if (!window)
            return;
        const focus = global.display.focus_window;
        if (focus === window || (focus && focus.get_transient_for() === window))
            this._focusChanged();
        else
            Main.activateWindow(window);
    }

    _workspaceChanged() {
        const workspace = global.workspace_manager.get_active_workspace();
        for (const strip of this.strips()) {
            if (strip.workspace === workspace)
                this.layout(strip, {animate: false});
        }
        // The strip's own focused window, rather than whatever GNOME found on that workspace
        const strip = this.activeStrip();
        if (strip.selected && !this.session && !this.dragging)
            this.focus(strip);
        this._syncBoxes();
    }

    _workspaceOfWindowChanged(window) {
        const info = this._info?.get(window);
        if (!info?.strip || window.is_on_all_workspaces())
            return;
        const workspace = window.get_workspace();
        if (!workspace || workspace === info.strip.workspace)
            return;
        // Moved to another workspace by GNOME (Super+Shift+number): it joins that workspace's strip
        const target = this.strip(workspace, info.strip.monitor);
        this.remove(window);
        this.insert(window, target, {near: target.selected});
    }

    // A window that became a dialog leaves the strip
    _kindChanged(window) {
        if (this.isTiled(window) && !this.tileable(window))
            this.remove(window);
    }

    _stickyChanged(window) {
        const info = this._info?.get(window);
        if (info?.strip && window.is_on_all_workspaces() && !this.floating.has(window))
            this.float(window, {glide: false});
    }

    _minimizedChanged(window) {
        const info = this._info?.get(window);
        if (!info)
            return;
        if (window.minimized && info.strip) {
            info.fromStrip = true;
            this.remove(window);
        } else if (!window.minimized && info.fromStrip) {
            info.fromStrip = false;
            if (!this.tileable(window))
                return;
            // Back beside the focused window, which stays the one shown as focused until the keyboard moves
            const strip = this.activeStrip(window.get_monitor());
            const focused = strip.selected;
            this.insert(window, strip);
            if (focused && !window.has_focus() && global.display.focus_window === focused) {
                strip.selected = focused;
                this.ensureVisible(strip, focused);
            }
        }
    }

    _fullscreenChanged(window) {
        const info = this._info?.get(window);
        const strip = info?.strip;
        if (!strip)
            return;
        if (window.is_fullscreen()) {
            info.fullscreenWidth = info.width;
            info.wasAbove = window.is_above();
            // A stacked window gets a column of its own to cover the screen from
            const at = strip.find(window);
            if (at && strip.columns[at[0]].length > 1) {
                strip.columns[at[0]].splice(at[1], 1);
                strip.columns.splice(at[0] + 1, 0, [window]);
            }
            if (!info.wasAbove)
                window.make_above();
        } else {
            if (info.fullscreenWidth)
                info.width = info.fullscreenWidth;
            if (!info.wasAbove && window.is_above())
                window.unmake_above();
        }
        this.ensureVisible(strip, window);
        this._syncBoxes();
    }

    _maximizedChanged(window) {
        const info = this._info?.get(window);
        if (!info?.strip || !(window.maximized_horizontally || window.maximized_vertically) || info.unmaximizing)
            return;
        // Maximizing a tiled window fills the width instead, and maximizing again goes back. Done once GNOME has
        // finished maximizing it, before anything is drawn.
        info.unmaximizing = true;
        const width = info.width;
        global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            info.unmaximizing = false;
            if (this._info?.get(window) === info && info.strip) {
                window.unmaximize();
                info.width = width;
                this.tiling.actions?.fillWidth(window);
            }
            return false;
        });
    }

    _overviewHidden() {
        const strip = this.activeStrip(global.display.get_current_monitor());
        const focus = global.display.focus_window;
        if (focus && this.stripOf(focus))
            this.ensureVisible(this.stripOf(focus), focus);
        else if (strip.selected)
            this.layout(strip);
    }

    // ---- The focus box ----

    _box(strip) {
        let box = this._boxes.get(strip);
        if (!box) {
            box = new St.Widget({style_class: 'tile-preview amethystora-tiling-focus', reactive: false});
            global.window_group.add_child(box);
            this._boxes.set(strip, box);
        }
        return box;
    }

    updateBox(strip) {
        if (!this._boxes)
            return;
        const window = strip.selected;
        const info = window ? this._info.get(window) : null;
        const showing = strip.workspace === global.workspace_manager.get_active_workspace();
        if (!info?.vis || !showing || window.is_fullscreen() || this.boxHidden > 0 || info.hidden ||
            this.dragging?.window === window) {
            this._boxes.get(strip)?.hide();
            return;
        }
        const box = this._box(strip);
        const {x, y, width, height} = info.vis;
        box.set_position(x - OUTLINE, y - OUTLINE);
        box.set_size(width + 2 * OUTLINE, height + 2 * OUTLINE);
        const focus = global.display.focus_window;
        const active = this.session ? this.session.strip === strip : focus === window;
        box.opacity = active ? 255 : INACTIVE;
        box.show();
        const actor = window.get_compositor_private();
        if (actor && box.get_parent() === actor.get_parent())
            global.window_group.set_child_below_sibling(box, actor);
    }

    _syncBoxes() {
        for (const strip of this.strips())
            this.updateBox(strip);
    }

    _restackBoxes() {
        for (const strip of this.strips()) {
            const actor = strip.selected?.get_compositor_private();
            const box = this._boxes.get(strip);
            if (box && actor && box.get_parent() === actor.get_parent())
                global.window_group.set_child_below_sibling(box, actor);
        }
    }

    // ---- Monitors and workspaces ----

    _monitorsChanged() {
        // A navigation is on a strip that is about to be merged or renumbered: it ends first, and quietly
        const released = this.tiling.sessions?.end({quiet: true}) ?? [];
        const count = Main.layoutManager.monitors.length;
        const primary = Main.layoutManager.primaryIndex;
        const before = this._connectors;
        const after = this._connectors = connectors();
        for (const [workspace, byMonitor] of this._strips) {
            const strips = [...byMonitor.values()];
            byMonitor.clear();
            const gone = [];
            for (const strip of strips) {
                // The strip stays with its screen, whatever number the screen has now
                const connector = before[strip.monitor];
                const index = connector ? after.indexOf(connector) : strip.monitor;
                if (index < 0 || index >= count) {
                    gone.push(strip);
                    continue;
                }
                strip.monitor = index;
                byMonitor.set(index, strip);
            }
            for (const strip of gone) {
                // A monitor that went away: its windows join the primary monitor's strip
                const target = this.strip(workspace, primary);
                for (const column of strip.columns) {
                    for (const window of column)
                        this._info.get(window).strip = target;
                    target.columns.push(column);
                }
                target.selected ??= strip.selected;
                this._glides.get(strip)?.timeline.stop();
                this._glides.delete(strip);
                this._boxes.get(strip)?.destroy();
                this._boxes.delete(strip);
            }
        }
        // The windows the navigation was carrying are in no strip: the primary monitor's takes them
        for (const window of released) {
            if (this._info.has(window) && this.tileable(window))
                this.insert(window, this.activeStrip(primary));
        }
        this.tiling.monitorsChanged?.();
        this.layoutAll(false);
    }

    _prune() {
        const workspaces = new Set(Array.from({length: global.workspace_manager.n_workspaces},
            (_, i) => global.workspace_manager.get_workspace_by_index(i)));
        for (const [workspace, byMonitor] of [...this._strips]) {
            if (workspaces.has(workspace))
                continue;
            for (const strip of byMonitor.values()) {
                this._boxes.get(strip)?.destroy();
                this._boxes.delete(strip);
            }
            this._strips.delete(workspace);
        }
    }

    // ---- Starting and stopping ----

    _remember() {
        if (!this._strips)
            return;
        remembered.strips = this.strips().map(strip => ({
            workspace: strip.workspace, monitor: strip.monitor, connector: this._connectors?.[strip.monitor],
            columns: strip.columns.map(c => [...c]),
            scroll: strip.scroll, mode: strip.mode, selected: strip.selected,
        }));
        remembered.windows = new WeakMap();
        for (const [window, info] of this._info) {
            const {width, height, lastX, everFocused, floatFrame, madeAbove, madeSticky, fromStrip} = info;
            remembered.windows.set(window, {
                width, height, lastX, everFocused, floatFrame, madeAbove, madeSticky,
                fromStrip,
            });
        }
        remembered.floating = new Set(this.floating);
    }

    // The windows already open: as they were when the tiling stopped in this session, else by where they are
    _restore() {
        const alive = new Set(global.display.list_all_windows());
        for (const window of remembered.floating) {
            if (alive.has(window) && !window.minimized)
                this.float(window, {glide: false});
        }
        const placed = new Set();
        const workspaces = new Set(Array.from({length: global.workspace_manager.n_workspaces},
            (_, i) => global.workspace_manager.get_workspace_by_index(i)));
        for (const saved of remembered.strips) {
            // The screen it was on, by its connector, whatever number it has now
            const monitor = saved.connector ? this._connectors.indexOf(saved.connector) : saved.monitor;
            if (!workspaces.has(saved.workspace) || monitor < 0 || monitor >= Main.layoutManager.monitors.length)
                continue;
            const strip = this.strip(saved.workspace, monitor);
            Object.assign(strip, {scroll: saved.scroll, mode: saved.mode});
            for (const column of saved.columns) {
                const kept = column.filter(w => alive.has(w) && this.tileable(w) && !w.minimized &&
                    w.located_on_workspace(saved.workspace));
                if (!kept.length)
                    continue;
                strip.columns.push(kept);
                for (const window of kept) {
                    this._track(window).strip = strip;
                    placed.add(window);
                }
            }
            strip.selected = alive.has(saved.selected) && placed.has(saved.selected) ? saved.selected
                : strip.windows[0] ?? null;
        }
        // Windows the tiling has not seen: from the left of the screen, the stacking breaking ties
        const stacked = global.display.sort_windows_by_stacking(global.display.list_all_windows());
        const others = stacked.filter(w => !placed.has(w) && w.get_window_type() === Meta.WindowType.NORMAL);
        for (const window of others) {
            this._track(window);
            if (window.is_above() && this.tileable(window) && !window.minimized)
                this.floating.add(window);
        }
        const fresh = others.filter(w => this.tileable(w) && !w.minimized)
            .sort((a, b) => a.get_frame_rect().x - b.get_frame_rect().x);
        for (const window of fresh) {
            const workspace = window.get_workspace();
            if (!workspace)
                continue;
            const strip = this.strip(workspace, window.get_monitor());
            const info = this._track(window);
            if (window.maximized_horizontally || window.maximized_vertically) {
                window.unmaximize();
                info.width = Layout.maxWidth(this.area(strip.monitor)) - 2 * (Layout.MARGIN - Layout.MIN_MARGIN);
            }
            info.width ||= window.get_frame_rect().width;
            info.strip = strip;
            strip.columns.push([window]);
            strip.selected ??= window;
        }
        for (const window of others.filter(w => w.minimized && this.tileable(w)))
            this._info.get(window).fromStrip ??= true;
        const focus = global.display.focus_window;
        for (const strip of this.strips()) {
            if (focus && strip.find(focus))
                strip.selected = focus;
            if (strip.selected)
                this.ensureVisible(strip, strip.selected, {animate: false});
            else
                this.layout(strip, {animate: false});
        }
        this._syncBoxes();
    }
}

// A new window takes the keyboard, without closing the overview if it is open
function activate(window) {
    window.activate(global.get_current_time());
}

// GNOME's extension preferences and its screenshot tool float, and take the keyboard when they open
function floatsByRule(window) {
    const wmClass = window.get_wm_class() ?? '';
    return wmClass === 'Gnome-shell-extension-prefs' || /gnome-screenshot/i.test(wmClass);
}

// A grab that changes a window's size, by the mouse or the keyboard (the unconstrained flag aside)
function isResize(op) {
    const plain = op & ~0x400;
    return (plain & 0xf000) !== 0 || plain === Meta.GrabOp.KEYBOARD_RESIZING_UNKNOWN;
}

// GNOME is animating the window itself (opening it, or a change of size): its translation is GNOME's meanwhile
function busy(actor) {
    return !!actor.__animationInfo || Main.wm._mapping?.has(actor) || Main.wm._resizing?.has(actor) ||
        Main.wm._minimizing?.has(actor) || Main.wm._unminimizing?.has(actor);
}
