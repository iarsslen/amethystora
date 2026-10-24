// The tiling under the mouse, the touchpad and the touchscreen: the edges of the screen show the window beyond them
// and bring it in on a click; a tiled window dragged by its title bar scrolls the strip, or, lifted away from it,
// is carried to a place in the strip shown as it is reached; three fingers sideways slide the strip; and with
// several screens, the screen the pointer goes to gets the keyboard.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Mtk from 'gi://Mtk';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import * as Layout from './layout.js';
import {ANIMATION} from './engine.js';
import {WorkspacePreview, activateQuietly} from './previews.js';

const PREVIEW_SCALE = 0.15;
const PREVIEW_DELAY = 100;
const PREVIEW_POLL = 200;
// How far the pointer may leave the edge before the preview goes
const PREVIEW_REACH = 2;
// A drag this far up or down lifts the window out of the strip; until then it shrinks as it goes
const LIFT = 300;
const SHRINK = 500;
// A window being carried is drawn at this size
const CARRIED_SCALE = 0.5;
// Half the width of the place between two columns a window can be dropped into, past half a gap
const BETWEEN = 100;
// How far from the boundary between two windows of a column a drop still stacks there, past half a gap
const STACK = 250;
// The strip drifts at this many pixels a millisecond while a dragged window is near a side of the screen
const DRAG_DRIFT = 2;
const DRAG_EDGE = 12;
// Three fingers on a touchpad, and how far they move before the direction counts
const FINGERS = 3;
const DECIDE = 16;
// The strip follows the fingers at twice their distance, and keeps going after them, slowing down
const SWIPE_SPEED = 2;
const SWIPE_FRICTION = 0.3 / 16;
// With several screens: how often the pointer's screen is looked at
const MONITOR_POLL = 100;

export class Pointer {
    constructor(tiling) {
        this._tiling = tiling;
        this._engine = tiling.engine;
    }

    enable() {
        this._edges = [];
        this._buildEdges();
        Main.layoutManager.connectObject('monitors-changed', () => {
            this._buildEdges();
            this._syncMonitorPoll();
        }, this);
        global.display.connectObject(
            'grab-op-begin', (d, window, op) => this._grabBegan(window, op),
            'grab-op-end', (d, window) => this._grabEnded(window),
            this);
        global.stage.connectObject('captured-event::touchpad', (actor, event) => this._touchpad(event), this);
        this._panelPan();
        this._touchpadSettings = new Gio.Settings({schema_id: 'org.gnome.desktop.peripherals.touchpad'});
        // GNOME's own swipes give way to the strip's outside the overview: sideways between workspaces never, up
        // and down only while the overview is open (an upward swipe on the desktop opens it, below)
        this._trackers = [Main.wm._workspaceAnimation?._swipeTracker, Main.overview._swipeTracker].filter(Boolean);
        for (const tracker of this._trackers)
            tracker.connectObject('notify::enabled', () => this._syncTrackers(), this);

        Main.overview.connectObject('showing', () => this._syncTrackers(), 'hidden', () => this._syncTrackers(), this);
        this._syncTrackers();
        this._syncMonitorPoll();
    }

    disable() {
        this._endDrag(true);
        this._hidePreview();
        for (const edge of this._edges ?? [])
            edge.destroy();
        this._edges = null;
        Main.layoutManager.disconnectObject(this);
        global.display.disconnectObject(this);
        global.stage.disconnectObject(this);
        if (this._pan)
            Main.panel.remove_action(this._pan);
        this._pan = null;
        Main.overview.disconnectObject(this);
        for (const tracker of this._trackers ?? []) {
            tracker.disconnectObject(this);
            tracker.enabled = true;
        }
        this._trackers = null;
        for (const id of ['_monitorTimer', '_previewTimer', '_pollTimer', '_retryTimer', '_settleTimer']) {
            if (this[id])
                GLib.source_remove(this[id]);
            this[id] = 0;
        }
        this._swipe?.pile?.destroy();
        this._swipe = null;
    }

    // ---- The edges of the screens ----

    _buildEdges() {
        for (const edge of this._edges)
            edge.destroy();
        this._edges = [];
        Main.layoutManager.monitors.forEach((monitor, index) => {
            const area = this._engine.area(index);
            const top = area.y + Layout.MARGIN_TOP;
            for (const side of [-1, 1]) {
                const edge = new St.Widget({
                    reactive: true, width: 1, height: monitor.y + monitor.height - top,
                    x: side < 0 ? monitor.x : monitor.x + monitor.width - 1, y: top,
                });
                edge.connectObject(
                    'enter-event', () => this._edgeEntered(index, side),
                    'leave-event', () => this._edgeLeft(),
                    'button-press-event', () => this._edgeClicked(index, side),
                    this);
                // Top chrome sits over fullscreen windows too, and takes the pointer and the clicks of the pixel
                // column it covers; tracked, it is hidden while a fullscreen window covers its screen
                Main.layoutManager.addTopChrome(edge, {trackFullscreen: true});
                this._edges.push(edge);
            }
        });
    }

    _edgesActive(monitor) {
        if (Main.overview.visible || this._engine.session || this._engine.dragging || Main.modalCount > 0)
            return false;
        const focus = global.display.focus_window;
        return !(focus && focus.get_monitor() === monitor && (focus.is_fullscreen() || focus.maximized_vertically));
    }

    // The window an edge brings in: the one used last of the nearest column, beyond that edge, that sticks out
    _target(monitor, side) {
        const strip = this._engine.activeStrip(monitor);
        const at = strip.selected ? strip.find(strip.selected) : null;
        if (!at)
            return null;
        const geo = this._engine.geometry(strip);
        const screen = Main.layoutManager.monitors[monitor];
        for (let c = at[0] + side; c >= 0 && c < strip.columns.length; c += side) {
            const column = geo.columns[c];
            const x = geo.area.x + geo.scroll + column.x;
            const out = side < 0 ? x < screen.x : x + column.width > screen.x + screen.width;
            if (out)
                return this._tiling.actions._recent(strip.columns[c]);
        }
        return null;
    }

    _edgeEntered(monitor, side) {
        this._edge = {monitor, side};
        if (this._previewTimer)
            GLib.source_remove(this._previewTimer);
        this._previewTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, PREVIEW_DELAY, () => {
            this._previewTimer = 0;
            this._showPreview();
            return GLib.SOURCE_REMOVE;
        });
    }

    _edgeLeft() {
        if (this._previewTimer)
            GLib.source_remove(this._previewTimer);
        this._previewTimer = 0;
        // The preview stays while the pointer is close: the poll takes it away
        if (!this._preview)
            this._edge = null;
    }

    _edgeClicked(monitor, side) {
        if (!this._edgesActive(monitor))
            return Clutter.EVENT_PROPAGATE;
        const target = this._target(monitor, side);
        this._hidePreview();
        if (!target)
            return Clutter.EVENT_PROPAGATE;
        Main.activateWindow(target);
        // Still at the edge once the strip has moved: the next window beyond it
        if (this._retryTimer)
            GLib.source_remove(this._retryTimer);
        this._retryTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ANIMATION + 50, () => {
            this._retryTimer = 0;
            if (this._nearEdge())
                this._showPreview();
            return GLib.SOURCE_REMOVE;
        });
        return Clutter.EVENT_STOP;
    }

    _nearEdge() {
        if (!this._edge)
            return false;
        const [x] = global.get_pointer();
        const screen = Main.layoutManager.monitors[this._edge.monitor];
        if (!screen)
            return false;
        const edgeX = this._edge.side < 0 ? screen.x : screen.x + screen.width - 1;
        return Math.abs(x - edgeX) <= PREVIEW_REACH;
    }

    _showPreview() {
        this._hidePreview(false);
        const {monitor, side} = this._edge ?? {};
        if (monitor === undefined || !this._edgesActive(monitor))
            return;
        const target = this._target(monitor, side);
        const actor = target?.get_compositor_private();
        if (!actor)
            return;
        const frame = target.get_frame_rect();
        const buffer = target.get_buffer_rect();
        const width = Math.round(frame.width * PREVIEW_SCALE);
        const height = Math.round(frame.height * PREVIEW_SCALE);
        const screen = Main.layoutManager.monitors[monitor];
        const area = this._engine.area(monitor);
        const [, y] = global.get_pointer();
        const top = Math.max(area.y, Math.min(Math.round(y - height / 2), area.y + area.height - height));
        const x = side < 0 ? screen.x : screen.x + screen.width - width;
        const clone = new Clutter.Clone({source: actor, opacity: 242, reactive: false});
        clone.set_scale(PREVIEW_SCALE, PREVIEW_SCALE);
        clone.set_position(Math.round(x + (buffer.x - frame.x) * PREVIEW_SCALE),
            Math.round(top + (buffer.y - frame.y) * PREVIEW_SCALE));
        Main.layoutManager.uiGroup.add_child(clone);
        this._preview = clone;
        this._pollTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, PREVIEW_POLL, () => {
            if (this._nearEdge())
                return GLib.SOURCE_CONTINUE;
            this._pollTimer = 0;
            this._hidePreview();
            return GLib.SOURCE_REMOVE;
        });
    }

    _hidePreview(forget = true) {
        if (this._pollTimer)
            GLib.source_remove(this._pollTimer);
        this._pollTimer = 0;
        this._preview?.destroy();
        this._preview = null;
        if (forget)
            this._edge = null;
    }

    // ---- Dragging a tiled window ----

    _grabBegan(window, op) {
        const plain = op & ~0x400;
        const moving = plain === Meta.GrabOp.MOVING || plain === Meta.GrabOp.KEYBOARD_MOVING;
        if (!moving || !this._engine.isTiled(window))
            return;
        const strip = this._engine.stripOf(window);
        const [x, y, mods] = global.get_pointer();
        this._drag = {
            window, strip, x, y, scroll: this._engine.geometry(strip).scroll, carried: false, zone: null,
            frame: window.get_frame_rect(),
        };
        this._engine.dragging = this._drag;
        this._engine.updateBox(strip);
        const actor = window.get_compositor_private();
        actor?.set_pivot_point(0.5, 0);
        // The frame is GNOME's to move from here; the window is drawn where its frame is
        if (actor) {
            actor.translation_x = 0;
            actor.translation_y = 0;
        }
        window.connectObject('position-changed', () => this._dragged(), this);
        if (plain === Meta.GrabOp.KEYBOARD_MOVING || mods & Clutter.ModifierType.CONTROL_MASK)
            this._lift();
    }

    _dragged() {
        const drag = this._drag;
        if (!drag)
            return;
        const [x, y, mods] = global.get_pointer();
        const dx = x - drag.x, dy = y - drag.y;
        const monitor = global.display.get_current_monitor();
        if (!drag.carried && (Math.abs(dy) >= LIFT || monitor !== drag.strip.monitor ||
            mods & Clutter.ModifierType.CONTROL_MASK))
            this._lift();
        const actor = drag.window.get_compositor_private();
        if (drag.carried) {
            this._showZone(x, y);
            this._driftNear(x);
            return;
        }
        // Sideways the whole strip follows; up or down the window shrinks as it leaves
        const d = Math.min(Math.abs(dy), LIFT);
        const scale = 1 - (d / SHRINK) ** 3;
        actor?.set_scale(scale, scale);
        this._engine.scrollTo(drag.strip, drag.scroll + dx);
        this._driftNear(x);
    }

    // The window leaves the strip, which closes up around the pointer, and is carried until it is dropped
    _lift() {
        const drag = this._drag;
        if (!drag || drag.carried)
            return;
        drag.carried = true;
        const strip = drag.strip;
        this._engine.remove(drag.window, {layout: false});
        const [x] = global.get_pointer();
        const geo = this._engine.geometry(strip);
        // The gap the window left is put under the pointer
        const after = geo.columns.findIndex(c => geo.area.x + geo.scroll + c.x > x);
        if (!geo.centred && after >= 0)
            strip.scroll = x + Layout.GAP / 2 - geo.area.x - geo.columns[after].x;
        else if (!geo.centred && geo.columns.length)
            strip.scroll = x - Layout.GAP / 2 - geo.area.x - geo.columns.at(-1).x - geo.columns.at(-1).width;
        this._engine.layout(strip);
        const actor = drag.window.get_compositor_private();
        actor?.set_pivot_point(0.5, 0.5);
        actor?.ease({scale_x: CARRIED_SCALE, scale_y: CARRIED_SCALE, duration: ANIMATION});
    }

    // The place under the pointer a carried window would go, shown in GNOME's tile-preview look
    _showZone(x, y) {
        const drag = this._drag;
        const strip = this._engine.activeStrip(global.display.get_current_monitor());
        drag.dropStrip = strip;
        const geo = this._engine.geometry(strip);
        const screen = Main.layoutManager.monitors[strip.monitor];
        const top = geo.area.y;
        let zone = null;
        if (!geo.columns.length) {
            if (Math.abs(x - (screen.x + screen.width / 2)) < screen.width / 4) {
                zone = {
                    column: 0, row: -1, rect: {
                        x: screen.x + screen.width / 2 - BETWEEN, y: top,
                        width: 2 * BETWEEN, height: screen.y + screen.height - top,
                    },
                };
            }
        }
        const reach = BETWEEN + Layout.GAP / 2;
        for (let c = 0; c <= geo.columns.length && !zone; c++) {
            const left = geo.area.x + geo.scroll + (c < geo.columns.length ? geo.columns[c].x
                : geo.columns.at(-1).x + geo.columns.at(-1).width + Layout.GAP);
            const centre = left - Layout.GAP / 2;
            if (Math.abs(x - centre) <= reach) {
                zone = {
                    column: c, row: -1, rect: {
                        x: centre - reach, y: top, width: 2 * reach,
                        height: screen.y + screen.height - top,
                    },
                };
            }
        }
        if (!zone) {
            const c = geo.columns.findIndex(col => {
                const left = geo.area.x + geo.scroll + col.x;
                return x > left && x < left + col.width;
            });
            if (c >= 0) {
                const column = strip.columns[c];
                const left = geo.area.x + geo.scroll + geo.columns[c].x;
                const width = geo.columns[c].width;
                const bounds = [geo.rects.get(column[0]).y - Layout.GAP / 2,
                    ...column.map(w => geo.rects.get(w).y + geo.rects.get(w).height + Layout.GAP / 2)];
                const stackReach = STACK + Layout.GAP / 2;
                let best = -1, distance = Infinity;
                bounds.forEach((b, row) => {
                    if (Math.abs(y - b) < distance && Math.abs(y - b) <= stackReach) {
                        best = row;
                        distance = Math.abs(y - b);
                    }
                });
                if (best >= 0) {
                    const b = bounds[best];
                    const above = best === 0 ? 0 : stackReach;
                    const below = best === column.length ? 0 : stackReach;
                    zone = {column: c, row: best, rect: {x: left, y: b - above, width, height: above + below}};
                }
            }
        }
        // The last place shown stays the target until another one is reached
        if (!zone || (drag.zone && drag.zone.strip === strip && zone.column === drag.zone.column &&
            zone.row === drag.zone.row))
            return;
        zone.strip = strip;
        drag.zone = zone;
        this._drawZone(zone.rect);
    }

    _drawZone(rect) {
        const old = this._zoneActor;
        if (old)
            old.ease({scale_x: 0, scale_y: 0, opacity: 0, duration: ANIMATION, onStopped: () => old.destroy()});
        const actor = new St.Widget({
            style_class: 'tile-preview amethystora-tiling-zone', reactive: false,
            x: rect.x, y: rect.y, width: rect.width, height: rect.height, scale_x: 0, scale_y: 0,
        });
        actor.set_pivot_point(0.5, 0.5);
        global.window_group.add_child(actor);
        const carried = this._drag.window.get_compositor_private();
        if (carried && carried.get_parent() === global.window_group)
            global.window_group.set_child_below_sibling(actor, carried);
        actor.ease({scale_x: 1, scale_y: 1, duration: ANIMATION});
        this._zoneActor = actor;
        this._engine.boxHidden++;
        this._engine.updateBox(this._drag.zone.strip);
        this._engine.boxHidden--;
    }

    // Near a side of the screen the strip under a dragged window drifts that way
    _driftNear(x) {
        const drag = this._drag;
        const strip = drag.carried ? drag.dropStrip ?? drag.strip : drag.strip;
        const screen = Main.layoutManager.monitors[strip.monitor];
        let side = 0;
        if (x <= screen.x + DRAG_EDGE)
            side = 1;
        else if (x >= screen.x + screen.width - DRAG_EDGE)
            side = -1;
        if (!side || !strip.columns.length) {
            drag.drift?.stop();
            drag.drift = null;
            return;
        }
        if (drag.drift)
            return;
        const timeline = new Clutter.Timeline({actor: global.stage, duration: 1000, repeat_count: -1});
        let last = 0;
        timeline.connect('new-frame', (t, elapsed) => {
            const step = side * DRAG_DRIFT * (elapsed >= last ? elapsed - last : elapsed);
            last = elapsed;
            if (drag.carried) {
                this._engine.scrollTo(strip, strip.scroll + step);
            } else {
                drag.scroll += step;
                const [px] = global.get_pointer();
                this._engine.scrollTo(strip, drag.scroll + px - drag.x);
            }
        });
        drag.drift = timeline;
        timeline.start();
    }

    _grabEnded(window) {
        if (this._drag?.window === window)
            this._endDrag(false);
    }

    _endDrag(cancelled) {
        const drag = this._drag;
        if (!drag)
            return;
        this._drag = null;
        this._engine.dragging = null;
        drag.drift?.stop();
        drag.window.disconnectObject(this);
        const zone = this._zoneActor;
        this._zoneActor = null;
        zone?.ease({opacity: 0, duration: ANIMATION, onStopped: () => zone.destroy()});
        const actor = drag.window.get_compositor_private();
        actor?.ease({scale_x: 1, scale_y: 1, duration: ANIMATION, onStopped: () => actor.set_pivot_point(0, 0)});
        if (cancelled || !this._engine.info(drag.window))
            return;
        const window = drag.window;
        if (!drag.carried) {
            // Back in its column, the strip settling on it
            this._engine.ensureVisible(drag.strip, window);
            return;
        }
        const target = drag.zone;
        if (target)
            this._putInto(window, target);
        else
            this._engine.insert(window, this._engine.activeStrip(global.display.get_current_monitor()));

        Main.activateWindow(window);
    }

    _putInto(window, {strip, column, row}) {
        this._engine.info(window).vis = this._engine.visual(window);
        this._engine.insert(window, strip, {place: {column, row}});
    }

    // ---- The touchpad ----

    _syncTrackers() {
        const [workspaces, overview] = [Main.wm._workspaceAnimation?._swipeTracker, Main.overview._swipeTracker];
        if (workspaces?.enabled)
            workspaces.enabled = false;
        const wanted = Main.overview.visible;
        if (overview && overview.enabled !== wanted)
            overview.enabled = wanted;
    }

    _touchpad(event) {
        if (event.type() !== Clutter.EventType.TOUCHPAD_SWIPE ||
            event.get_touchpad_gesture_finger_count() !== FINGERS)
            return Clutter.EVENT_PROPAGATE;
        const phase = event.get_gesture_phase();
        if (Main.overview.visible || this._engine.session) {
            // The overview or a navigation began under fingers already down: the pile of workspaces they opened
            // still has to be shown or taken away when they lift, or it would stay over the windows
            if (this._swipe?.state === 'pile' && phase !== Clutter.TouchpadGesturePhase.UPDATE &&
                phase !== Clutter.TouchpadGesturePhase.BEGIN)
                return this._pileSwipe(this._swipe, event, 0);
            return Clutter.EVENT_PROPAGATE;
        }
        const [dx, dy] = event.get_gesture_motion_delta_unaccelerated();
        if (phase === Clutter.TouchpadGesturePhase.BEGIN) {
            // A pile left over from a swipe whose end never came goes with it
            this._swipe?.pile?.destroy();
            this._swipe?.timeline?.stop();
            const [x] = event.get_coords();
            const monitor = global.display.get_monitor_index_for_rect(new Mtk.Rectangle({
                x, y: 1,
                width: 1, height: 1,
            }));
            this._swipe = {state: 'pending', x: 0, y: 0, monitor: Math.max(0, monitor), history: []};
            return Clutter.EVENT_PROPAGATE;
        }
        const swipe = this._swipe;
        if (!swipe)
            return Clutter.EVENT_PROPAGATE;
        if (swipe.state === 'pending') {
            swipe.x += dx;
            swipe.y += dy;
            if (Math.hypot(swipe.x, swipe.y) < DECIDE)
                return Clutter.EVENT_PROPAGATE;
            const natural = this._touchpadSettings.get_boolean('natural-scroll');
            const down = (natural ? 1 : -1) * swipe.y > 0;
            // Sideways slides the strip; down opens the pile of recent workspaces; up opens the overview
            if (Math.abs(swipe.x) > Math.abs(swipe.y)) {
                swipe.state = 'strip';
                swipe.strip = this._engine.activeStrip(swipe.monitor);
                swipe.scroll = this._engine.geometry(swipe.strip).scroll;
            } else if (down) {
                swipe.state = 'pile';
                const list = this._tiling.workspaceHistory();
                swipe.pile = new WorkspacePreview(this._engine, swipe.monitor, 'pile', list, 0);
                swipe.travel = 0;
            } else {
                swipe.state = 'done';
                Main.overview.show();
            }
        }
        if (swipe.state === 'pile')
            return this._pileSwipe(swipe, event, dy);
        if (swipe.state !== 'strip')
            return Clutter.EVENT_STOP;
        const natural = this._touchpadSettings.get_boolean('natural-scroll');
        const delta = (natural ? 1 : -1) * dx * SWIPE_SPEED;
        if (phase === Clutter.TouchpadGesturePhase.UPDATE) {
            swipe.scroll += delta;
            swipe.history.push([event.get_time(), delta]);
            swipe.history = swipe.history.filter(([t]) => t > event.get_time() - 150);
            const geo = this._engine.scrollTo(swipe.strip, swipe.scroll);
            this._followSwipe(swipe, geo, delta);
        } else {
            this._release(swipe);
        }
        return Clutter.EVENT_STOP;
    }

    // Each fifth of the screen the fingers go down steps one workspace further back; letting go shows it
    _pileSwipe(swipe, event, dy) {
        const natural = this._touchpadSettings.get_boolean('natural-scroll');
        const height = Main.layoutManager.monitors[swipe.monitor].height;
        if (event.get_gesture_phase() === Clutter.TouchpadGesturePhase.UPDATE) {
            swipe.travel += (natural ? 1 : -1) * dy * SWIPE_SPEED;
            const wanted = Math.max(0, Math.min(swipe.pile.workspaces.length - 1, Math.floor(swipe.travel / (height / 5))));
            while (swipe.pile.selected < wanted && swipe.pile.step(1))
                ;
            while (swipe.pile.selected > wanted && swipe.pile.step(-1))
                ;
            return Clutter.EVENT_STOP;
        }
        this._swipe = null;
        swipe.pile.finish(workspace => {
            // The tiling stopped while the cards zoomed (the screen locked): there is nothing to hand the keyboard to
            if (this._tiling.engine !== this._engine)
                return;
            activateQuietly(workspace);
            const strip = this._engine.activeStrip(swipe.monitor);
            if (strip.selected)
                this._engine.focus(strip);
        });
        return Clutter.EVENT_STOP;
    }

    // The window the strip will settle on is the one shown as focused while the fingers move
    _followSwipe(swipe, geo, direction) {
        const window = this._mostVisible(swipe.strip, geo, direction);
        if (window && window !== swipe.strip.selected) {
            swipe.strip.selected = window;
            this._engine.updateBox(swipe.strip);
        }
    }

    _mostVisible(strip, geo, direction) {
        const area = geo.area;
        let best = null, shown = 0;
        const order = direction < 0 ? strip.windows : [...strip.windows].reverse();
        for (const window of order) {
            const rect = geo.rects.get(window);
            const visible = Math.min(rect.x + rect.width, area.x + area.width) - Math.max(rect.x, area.x);
            if (visible > shown) {
                best = window;
                shown = visible;
            }
        }
        return best;
    }

    // The fingers are off: the strip keeps going, slowing down, and settles on a window
    // `pace` shortens the glide: a finger on the top bar slides the strip one to one, and stops sooner
    _release(swipe, pace = 1) {
        this._swipe = null;
        const strip = swipe.strip;
        const times = swipe.history.map(([t]) => t);
        const span = times.length > 1 ? times.at(-1) - times[0] : 0;
        const velocity = swipe.velocity ??
            (span > 0 ? swipe.history.slice(1).reduce((sum, [, d]) => sum + d, 0) / span : 0);
        const time = Math.abs(velocity) / SWIPE_FRICTION * pace;
        const travel = Math.sign(velocity) * velocity * velocity / (2 * SWIPE_FRICTION);
        strip.scroll = swipe.scroll + travel;
        const geo = this._engine.geometry(strip);
        const window = this._mostVisible(strip, geo, velocity || 1);
        if (!window) {
            this._engine.layout(strip);
            return;
        }
        strip.selected = window;
        const at = strip.find(window);
        const column = geo.columns[at[0]];
        const x = Layout.placeFocused(geo.area, column, strip.scroll + column.x, strip.mode, at[0],
            geo.columns.length);
        const settled = Math.round(x - column.x);
        const adjusted = Math.abs(settled - strip.scroll) > 1;
        strip.scroll = settled;
        const end = at[0] === 0 || at[0] === strip.columns.length - 1;
        this._engine.layout(strip, {
            time: Math.max(adjusted ? 200 : 0, Math.round(time)) || ANIMATION,
            mode: end && Math.abs(travel) > geo.area.width ? Clutter.AnimationMode.EASE_OUT_BACK
                : Clutter.AnimationMode.EASE_OUT_QUAD,
        });
        if (this._settleTimer)
            GLib.source_remove(this._settleTimer);
        this._settleTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.max(200, Math.round(time)), () => {
            this._settleTimer = 0;
            if (strip.selected === window && this._engine.isTiled(window))
                Main.activateWindow(window);
            return GLib.SOURCE_REMOVE;
        });
    }

    // ---- A finger along the top bar ----

    // Sideways along the top bar the strip follows the finger, one to one; a tap on the bar's buttons is not a
    // drag, and works as before
    _panelPan() {
        const pan = new Clutter.PanGesture({pan_axis: Clutter.PanAxis.X, begin_threshold: DECIDE});
        pan.connect('should-handle-sequence', (gesture, event) => event.type() === Clutter.EventType.TOUCH_BEGIN);
        pan.connect('recognize', () => {
            const strip = this._engine.activeStrip(Main.layoutManager.primaryIndex);
            this._touch = {strip, scroll: this._engine.geometry(strip).scroll, last: 0};
        });
        pan.connect('pan-update', () => {
            const touch = this._touch;
            if (!touch)
                return;
            const dx = pan.get_accumulated_delta().get_x();
            const geo = this._engine.scrollTo(touch.strip, touch.scroll + dx);
            this._followSwipe({strip: touch.strip}, geo, dx - touch.last);
            touch.last = dx;
        });
        const finish = () => {
            const touch = this._touch;
            this._touch = null;
            if (touch) {
                this._release({
                    strip: touch.strip, scroll: touch.scroll + touch.last, history: [],
                    velocity: pan.get_velocity().get_x(),
                }, 0.75);
            }
        };
        pan.connect('end', finish);
        pan.connect('cancel', finish);
        Main.panel.add_action_full('amethystora-tiling-pan', Clutter.EventPhase.CAPTURE, pan);
        // GNOME's own press on the bar (it drags a maximized window down) leaves the slide its chance
        Main.panel.get_action('window-drag')?.can_not_cancel(pan);
        this._pan = pan;
    }

    // ---- Several screens ----

    _syncMonitorPoll() {
        const several = Main.layoutManager.monitors.length > 1;
        if (several && !this._monitorTimer) {
            this._lastMonitor = global.display.get_current_monitor();
            this._monitorTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, MONITOR_POLL, () => {
                this._followPointer();
                return GLib.SOURCE_CONTINUE;
            });
        } else if (!several && this._monitorTimer) {
            GLib.source_remove(this._monitorTimer);
            this._monitorTimer = 0;
        }
    }

    // The pointer went to another screen: its strip's window gets the keyboard
    _followPointer() {
        const monitor = global.display.get_current_monitor();
        if (monitor === this._lastMonitor || Main.overview.visible || this._engine.session || Main.modalCount > 0)
            return;
        this._lastMonitor = monitor;
        if (this._drag)
            return;
        const focus = global.display.focus_window;
        if (focus && this._engine.focusMonitor() === monitor)
            return;
        const strip = this._engine.activeStrip(monitor);
        if (strip.selected)
            this._engine.focus(strip);
    }
}
