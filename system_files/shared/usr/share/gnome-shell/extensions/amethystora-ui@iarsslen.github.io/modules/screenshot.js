// Drawing on a screenshot in GNOME's own screenshot UI (Print), and what happens to the picture after. While an area
// or a whole screen is framed, a toolbar at the top offers a pen, boxes, a highlighter, an arrow, text and numbered
// markers, which are burnt into the picture. The capture goes to the clipboard and the screenshots folder and shows
// a small card to open it from; Ctrl+C only copies, Ctrl+S asks where to save, and Extract Text (Ctrl+E) hands the
// area to Gradia, which copies the text in it. A window is captured over the windows it belongs to. Everything is
// GNOME's UI with these pieces added while it is open; the keybindings that take a screenshot without it are GNOME's.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Util from 'resource:///org/gnome/shell/misc/util.js';

import {
    GRADIA, captureFrame, captureWindow, copyToClipboard, gradiaInstalled, playShutter, saveAs, saveToFolder,
} from './screenshot/capture.js';
import {Card} from './screenshot/card.js';
import {DRAWING, MAX_WIDTH, MIN_WIDTH} from './screenshot/marks.js';
import {Session} from './screenshot/session.js';

// The mode GNOME's screenshot UI opens in for an app's interactive screenshot through the screenshot portal
const PORTAL_MODE = 2;
const SCHEMA = 'org.gnome.shell.extensions.amethystora-ui.screenshot';
// Icons drawn for the toolbar, in icons/screenshot; the rest are the icon theme's
const OWN_ICONS = new Set(['move', 'pen', 'box', 'fill', 'highlight', 'arrow', 'text', 'marker', 'extract']);
const THEME_ICONS = {area: 'screenshot-ui-area-symbolic', display: 'screenshot-ui-display-symbolic'};

export class Screenshot {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        const ui = Main.screenshotUI;
        this._ui = ui;
        this._settings = this._ext.getSettings(SCHEMA);
        this._pairs = this._loadPairs();
        this._pending = new Set();
        this._icons = new Map();

        // GNOME's own methods, kept to be given back: the opening, wrapped, and the saving, which this takes over
        this._open = Object.getOwnPropertyDescriptor(ui, 'open');
        this._save = Object.getOwnPropertyDescriptor(ui, '_saveScreenshot');
        const open = ui.open;
        ui.open = (mode, ...rest) => this._onOpen(open, mode, rest);
        ui._saveScreenshot = () => this._take('normal');

        // Before GNOME's keys, and before Escape closes the UI, so that the text field can take it
        ui.connectObject(
            'captured-event', (actor, event) => this._onEvent(event),
            'closed', () => this._endSession(), this);
    }

    disable() {
        const ui = this._ui;
        if (!ui)
            return;
        ui.disconnectObject(this);
        this._endSession();
        for (const [name, descriptor] of [['open', this._open], ['_saveScreenshot', this._save]]) {
            if (descriptor)
                Object.defineProperty(ui, name, descriptor);
            else
                delete ui[name];
        }
        for (const id of this._pending ?? [])
            Gio.DBus.session.signal_unsubscribe(id);
        this._pending = null;
        this._card?.close(true);
        this._card = null;
        this._settings = null;
        this._icons = null;
        this._ui = null;
    }

    _onOpen(open, mode, rest) {
        const ui = this._ui;
        const wasOpen = ui.visible;
        const opening = open.call(ui, mode, ...rest);
        // GNOME has just made its window previews, before its first wait: which window each one is
        if (!wasOpen)
            this._windows = this._mapWindows();
        const portal = mode === PORTAL_MODE;
        return Promise.resolve(opening).then(() => {
            if (!ui.visible || this._ui !== ui)
                return;
            try {
                if (this._session)
                    this._session.setPortal(portal);
                else
                    this._session = new Session(this, ui, portal);
            } catch (e) {
                console.error(`Amethystora UI: the screenshot tools did not open: ${e.message}\n${e.stack}`);
                this._endSession();
            }
        });
    }

    _endSession() {
        try {
            this._session?.destroy();
        } catch (e) {
            console.error(`Amethystora UI: the screenshot tools did not close cleanly: ${e.message}`);
        }
        this._session = null;
        this._windows = null;
        this._savePairs();
    }

    // GNOME's window previews are made in the order of the windows of each monitor it shows; the same windows in the
    // same order, each checked against its preview's frame, say which window a preview is
    _mapWindows() {
        const map = new Map();
        const workspace = global.workspace_manager.get_active_workspace();
        this._ui._windowSelectors.forEach((selector, monitor) => {
            const windows = global.get_window_actors().map(actor => actor.metaWindow).filter(window =>
                !window.is_override_redirect() && window.located_on_workspace(workspace) &&
                window.get_monitor() === monitor);
            const previews = selector.windows();
            if (windows.length !== previews.length)
                return;
            previews.forEach((preview, i) => {
                const frame = windows[i].get_frame_rect();
                const box = preview.boundingBox;
                if (frame.x === box.x && frame.y === box.y && frame.width === box.width && frame.height === box.height)
                    map.set(preview, windows[i]);
            });
        });
        return map;
    }

    _onEvent(event) {
        const session = this._session;
        if (!session)
            return Clutter.EVENT_PROPAGATE;
        const type = event.type();
        if (type === Clutter.EventType.SCROLL) {
            // One wheel step is a pixel of line width; the scroll still goes on to whatever is under the pointer,
            // but the width slider, which would move again
            const direction = event.get_scroll_direction();
            if (direction !== Clutter.ScrollDirection.UP && direction !== Clutter.ScrollDirection.DOWN)
                return Clutter.EVENT_PROPAGATE;
            session.scrollWidth(direction === Clutter.ScrollDirection.UP ? 1 : -1);
            const target = global.stage.get_event_actor(event);
            return session.slider.contains(target) ? Clutter.EVENT_STOP : Clutter.EVENT_PROPAGATE;
        }
        if (type !== Clutter.EventType.KEY_PRESS)
            return Clutter.EVENT_PROPAGATE;

        const symbol = event.get_key_symbol();
        const ctrl = (event.get_state() & Clutter.ModifierType.CONTROL_MASK) !== 0;
        const ui = this._ui;
        const recording = ui._castButton.checked;
        if (ctrl && !session.entryOpen) {
            // Copying only; while recording, or for an app that asked for a screenshot, GNOME's own Ctrl+C takes it
            if ((symbol === Clutter.KEY_c || symbol === Clutter.KEY_C) && !recording && !session.portal) {
                this._take('copy').catch(logError);
                return Clutter.EVENT_STOP;
            }
            if ((symbol === Clutter.KEY_s || symbol === Clutter.KEY_S) && !recording) {
                this._take('save-as').catch(logError);
                return Clutter.EVENT_STOP;
            }
            // Exactly what the button does, and nothing while the button is off
            if ((symbol === Clutter.KEY_e || symbol === Clutter.KEY_E) && session.extractLive) {
                this.extractText();
                return Clutter.EVENT_STOP;
            }
        }
        return session.handleKey(event);
    }

    // The button and Ctrl+E
    extractText() {
        this._take('extract').catch(logError);
    }

    // A capture: `normal` (the capture button, Enter, Space) to the clipboard, the folder and the card; `copy` to the
    // clipboard and the card; `save-as` where the person says; `extract` to the folder and then Gradia
    async _take(kind) {
        const ui = this._ui;
        if (this._busy || !ui)
            return;
        this._busy = true;
        try {
            const picture = await this._picture();
            if (!picture)
                return;
            switch (kind) {
            case 'normal': {
                copyToClipboard(picture);
                const file = saveToFolder(picture);
                if (file)
                    ui.emit('screenshot-taken', file);
                this._showCard(picture, file, false);
                break;
            }
            case 'copy':
                copyToClipboard(picture);
                this._showCard(picture, null, true);
                ui.close();
                break;
            case 'save-as': {
                ui.close();
                const file = await saveAs(picture, this._pending);
                if (file && this._ui)
                    this._showCard(picture, file, false);
                break;
            }
            case 'extract': {
                const file = saveToFolder(picture);
                if (file)
                    ui.emit('screenshot-taken', file);
                ui.close();
                if (file)
                    Util.spawn(['flatpak', 'run', GRADIA, `--ocr-file=${file.get_path()}`]);
                break;
            }
            }
        } catch (e) {
            console.error(`Amethystora UI: the screenshot was not taken: ${e.message}\n${e.stack}`);
            if (kind !== 'normal')
                ui.close();
        } finally {
            this._busy = false;
        }
    }

    // The picture as it will be kept: the area or the screen with the marks, or the window with its parents; null
    // for nothing to take
    _picture() {
        const ui = this._ui;
        this._session?.commit();
        if (ui._selectionButton.checked) {
            const [,, width, height] = ui._areaSelector.getGeometry();
            if (width <= 2 || height <= 2)
                return null;
        }
        if (ui._windowButton.checked) {
            const chosen = ui._windowSelectors.flatMap(selector => selector.windows()).find(w => w.checked);
            if (!chosen)
                return null;
            playShutter();
            return captureWindow(ui, chosen, this._windows?.get(chosen) ?? null);
        }
        if (!ui._selectionButton.checked && !ui._screenButton.checked)
            return null;
        playShutter();
        return captureFrame(ui, this._session?.marks ?? []);
    }

    _showCard(picture, file, copied) {
        this._card?.close(true);
        this._card = new Card(picture, file, copied);
        this._card.actor.connect('destroy', actor => {
            if (this._card?.actor === actor)
                this._card = null;
        });
    }

    gradiaInstalled() {
        return gradiaInstalled();
    }

    icon(name) {
        let icon = this._icons.get(name);
        if (!icon) {
            icon = OWN_ICONS.has(name)
                ? Gio.FileIcon.new(this._ext.dir.get_child('icons').get_child('screenshot')
                    .get_child(`${name}-symbolic.svg`))
                : Gio.ThemedIcon.new(THEME_ICONS[name]);
            this._icons.set(name, icon);
        }
        return icon;
    }

    // The colour and width each drawing tool had when it was last used, kept between screenshots and sessions
    _loadPairs() {
        const pairs = new Map();
        const stored = this._settings.get_value('tool-settings').recursiveUnpack();
        for (const [tool, [colour, width]] of Object.entries(stored)) {
            if (DRAWING.has(tool) && /^#[0-9a-f]{6}$/i.test(colour) && width >= MIN_WIDTH && width <= MAX_WIDTH)
                pairs.set(tool, [colour.toLowerCase(), width]);
        }
        return pairs;
    }

    // Written once, as the UI closes, rather than for every move of the slider
    _savePairs() {
        if (!this._settings || !this._pairsChanged)
            return;
        this._pairsChanged = false;
        const value = {};
        for (const [tool, pair] of this._pairs)
            value[tool] = pair;
        this._settings.set_value('tool-settings', new GLib.Variant('a{s(sd)}', value));
    }

    pairOf(tool) {
        return this._pairs.get(tool) ?? null;
    }

    rememberPair(tool, colour, width) {
        const old = this._pairs.get(tool);
        if (old && old[0] === colour && old[1] === width)
            return;
        this._pairs.set(tool, [colour, width]);
        this._pairsChanged = true;
    }
}
