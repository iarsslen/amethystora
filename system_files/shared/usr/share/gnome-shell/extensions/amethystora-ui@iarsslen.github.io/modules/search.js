// The search box. Super+Space opens GNOME's own search in a dark box in the middle of the main screen, over whatever
// is open, without going to the overview. The box holds the overview's own search field and results, lent to it while
// it is open and given back when it closes, so that every search provider (apps, files, settings, the calculator,
// the software centre...) is there and the results look and work as they do in the overview. It starts as a single
// line and grows to its full size at the first letter typed; Enter opens the first result. Escape, the same key
// again, the field's clear button, a click anywhere else, opening a result, or a window going full screen or leaving
// it closes the box, and the Super key brings the typing back to the field instead of opening the overview. Its
// colours are fixed, dark with white text, whatever the theme (stylesheets/search.css).

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Graphene from 'gi://Graphene';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as BoxPointer from 'resource:///org/gnome/shell/ui/boxpointer.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Overview from 'resource:///org/gnome/shell/ui/overview.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const SCHEMA = 'org.gnome.shell.extensions.amethystora-ui.search';

// The box's size: a base, and a share of half the main screen (at 1920×1080, 696×481)
const WIDTH = {base: 600, share: 0.1};
const HEIGHT = {base: 400, share: 0.15};
// Milliseconds for the box to appear or go; GNOME's animation settings, and the tweaks, shorten them
const DURATION = 100;
// The size it grows from and shrinks to
const SMALL = 0.9;

// The keys that open the result in focus, and the Super keys
const OPENING_KEYS = [Clutter.KEY_Return, Clutter.KEY_KP_Enter, Clutter.KEY_ISO_Enter, Clutter.KEY_space,
    Clutter.KEY_KP_Space];
const SUPER_KEYS = [Clutter.KEY_Super_L, Clutter.KEY_Super_R];
const KEY_EVENTS = [Clutter.EventType.KEY_PRESS, Clutter.EventType.KEY_RELEASE];
const POINTER_EVENTS = [Clutter.EventType.BUTTON_PRESS, Clutter.EventType.BUTTON_RELEASE,
    Clutter.EventType.TOUCH_BEGIN, Clutter.EventType.TOUCH_END];
const PRINTABLE = /[\p{L}\p{N}\p{P}\p{S}]/u;

export class Search {
    constructor(ext) {
        this._ext = ext;
    }

    // For the tiling, which leaves the keyboard here while the pointer crosses the screens
    get open() {
        return !!this._open;
    }

    enable() {
        this._open = false;
        // The signals that last only while the box is open are kept under this, and those that outlast it a little
        // under the other
        this._whileOpen = {};
        this._afterClose = {};

        this._box = new St.BoxLayout({
            style_class: 'amethystora-search-box',
            orientation: Clutter.Orientation.VERTICAL,
            // A click on the box's own edge stays in the box rather than reaching the window under it
            reactive: true,
            visible: false,
            pivot_point: new Graphene.Point({x: 0.5, y: 0.5}),
        });
        this._box.connectObject('key-press-event', (actor, event) => this._onKeyPress(event), this);
        // Over the windows, under their menus, the on-screen keyboard and the screenshot tool
        Main.layoutManager.addChrome(this._box);

        // The overview gets its search back before it lays it out
        Main.overview.connectObject('showing', () => this._giveBack(), this);

        // While the box is open, opening a result asks the overview to go (it is not there); the Super key asks it to
        // come. Both are answered here instead.
        const proto = Overview.Overview.prototype;
        const {toggle, hide} = proto;
        this._overviewMethods = {toggle, hide};
        const search = this;
        proto.toggle = function (...args) {
            if (search._open && search._answer(true))
                return undefined;
            return toggle.apply(this, args);
        };
        proto.hide = function (...args) {
            if (search._open)
                search._answer(false);
            return hide.apply(this, args);
        };

        this._settings = this._ext.getSettings(SCHEMA);
        const action = Main.wm.addKeybinding('open', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.POPUP, () => this._toggle());
        if (action === Meta.KeyBindingAction.NONE)
            console.warn('Amethystora UI: the search box key could not be set: another one has its name');
    }

    disable() {
        if (this._settings)
            Main.wm.removeKeybinding('open');
        this._settings = null;

        this._close('now');
        if (this._afterClose)
            global.stage.disconnectObject(this._afterClose);

        if (this._overviewMethods)
            Object.assign(Overview.Overview.prototype, this._overviewMethods);
        this._overviewMethods = null;
        Main.overview.disconnectObject(this);

        this._box?.destroy();
        this._box = null;
    }

    _toggle() {
        if (this._open)
            this._close('animate');
        else
            this._show();
    }

    _show() {
        // The overview has its own search
        if (Main.overview.visible || Main.overview.animationInProgress)
            return;
        // A menu of the top bar open (the key works over one too): it gives way, with the keyboard it holds
        Main.panel.menuManager.activeMenu?.close(BoxPointer.PopupAnimation.NONE);
        // Any other grab (the screenshot tool, a dock's menu) would keep the keys from the box, which is not modal
        if (Main.modalCount > 0)
            return;
        // Still fading from the last time
        this._giveBack();
        global.stage.disconnectObject(this._afterClose);

        // The overview's field sits in a holder of its own; the holder and the results are side by side in the
        // overview's controls
        const entry = Main.overview.searchEntry;
        const results = Main.overview.searchController;
        const bin = entry?.get_parent();
        const controls = bin?.get_parent();
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || !(entry instanceof St.Entry) || !(bin instanceof St.Bin) || !controls ||
            results?.get_parent() !== controls) {
            console.warn('Amethystora UI: the overview\'s search was not found, the search box stays closed');
            return;
        }

        const children = controls.get_children();
        this._lent = {
            controls, bin, results, entry,
            places: [[bin, children.indexOf(bin)], [results, children.indexOf(results)]].sort((a, b) => a[1] - b[1]),
            align: bin.x_align,
            expand: entry.x_expand,
        };
        controls.remove_child(bin);
        controls.remove_child(results);
        // The field takes the box's whole width (the overview centres it at its own)
        bin.x_align = Clutter.ActorAlign.FILL;
        entry.x_expand = true;
        this._box.add_child(bin);
        this._box.add_child(results);

        // Worked out again at every opening, for the screen as it is now
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const width = Math.round(WIDTH.base + monitor.width * scale / 2 * WIDTH.share);
        this._height = Math.round(HEIGHT.base + monitor.height * scale / 2 * HEIGHT.share);
        this._box.set_position(monitor.x + Math.round((monitor.width - width) / 2),
            monitor.y + Math.round((monitor.height - this._height) / 2));
        // A single line, the field's own height, until something is typed
        this._box.set_size(width, -1);
        this._grown = false;

        this._open = true;
        // Drawn over a full-screen game or video too
        global.compositor.disable_unredirect();

        global.stage.connectObject('notify::key-focus', () => this._queueFocusCheck(), this._whileOpen);
        entry.clutter_text.connectObject('text-changed', () => this._grow(), this._whileOpen);
        global.display.connectObject('in-fullscreen-changed', () => this._close('animate'), this._whileOpen);
        Main.layoutManager.connectObject('monitors-changed', () => this._close('now'), this._whileOpen);
        // An app dragged from the results (to the dock, say) keeps the box open until it is dropped
        Main.overview.connectObject(
            'item-drag-begin', () => (this._dragging = true),
            'item-drag-end', () => {
                this._dragging = false;
                this._queueFocusCheck();
            }, this._whileOpen);

        this._box.remove_all_transitions();
        this._box.opacity = 0;
        this._box.set_scale(SMALL, SMALL);
        this._box.show();
        this._box.ease({
            opacity: 255,
            scale_x: 1,
            scale_y: 1,
            duration: DURATION,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        });
        entry.grab_key_focus();
    }

    // The box grows to its full size at the first change to the text, and keeps it until it closes
    _grow() {
        if (this._grown)
            return;
        this._grown = true;
        this._box.height = this._height;
    }

    // How it closes: 'animate' fades it out; 'quick' makes it clear at once and gives the search back before the next
    // frame, once the result that was opened (or its menu) has finished: hiding the box would empty the results
    // under it, since GNOME empties its search when it stops being shown; 'now' gives it back at once
    _close(how) {
        this._stop();
        if (!this._lent)
            return;

        if (how === 'animate') {
            this._box.ease({
                opacity: 0,
                scale_x: SMALL,
                scale_y: SMALL,
                duration: DURATION,
                mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                onComplete: () => {
                    if (!this._open)
                        this._giveBack();
                },
            });
        } else if (how === 'quick') {
            this._box.remove_all_transitions();
            this._box.opacity = 0;
            this._box.reactive = false;
            this._queueLater('_giveBackLater', () => this._giveBack());
        } else {
            this._giveBack();
        }
    }

    // The box stops listening and lets go of the keyboard; what it shows stays until it is given back
    _stop() {
        if (!this._open)
            return;
        this._open = false;
        this._dragging = false;
        for (const source of [global.stage, global.display, Main.layoutManager, Main.overview,
            this._lent?.entry.clutter_text])
            source?.disconnectObject(this._whileOpen);
        this._removeLater('_focusLater');
        global.compositor.enable_unredirect();

        // The keyboard goes back to the windows before anything fades: nothing that cannot be seen holds it
        const focus = global.stage.get_key_focus();
        if (focus && focus !== global.stage && this._box.contains(focus))
            global.stage.set_key_focus(null);
    }

    // The field and the results go back to the overview, where they were
    _giveBack() {
        this._removeLater('_giveBackLater');
        this._stop();
        const lent = this._lent;
        if (!lent)
            return;
        this._lent = null;

        this._box.remove_all_transitions();
        this._keepingFocus(() => {
            this._box.hide();
            this._box.remove_child(lent.bin);
            this._box.remove_child(lent.results);
        });
        this._box.opacity = 255;
        this._box.reactive = true;
        this._box.set_scale(1, 1);
        lent.bin.x_align = lent.align;
        lent.entry.x_expand = lent.expand;
        for (const [actor, index] of lent.places)
            lent.controls.insert_child_at_index(actor, index);
        this._guardReturn(lent);
    }

    // Hiding GNOME's results empties the search, and GNOME then lets go of the keyboard: whatever had it outside the
    // box (a menu of the top bar, say) gets it back
    _keepingFocus(change) {
        const focus = global.stage.get_key_focus();
        const keep = focus && focus !== global.stage && !this._box.contains(focus) ? focus : null;
        change();
        if (keep?.get_stage() && global.stage.get_key_focus() !== keep)
            keep.grab_key_focus();
    }

    // A menu that opened while the field had the keyboard gives it back to the field when it closes, which may be
    // after the field is back in the hidden overview: the keyboard goes back to the windows instead, now or when
    // the menu closes
    _guardReturn(lent) {
        global.stage.disconnectObject(this._afterClose);
        const home = [lent.bin, lent.results];
        const away = () => {
            const focus = global.stage.get_key_focus();
            if (focus && !this._open && !Main.overview.visible && home.some(actor => actor.contains(focus)))
                global.stage.set_key_focus(null);
        };
        away();
        if (Main.modalCount === 0)
            return;
        global.stage.connectObject('notify::key-focus', () => {
            away();
            if (Main.modalCount === 0)
                global.stage.disconnectObject(this._afterClose);
        }, this._afterClose);
    }

    // The overview was asked to come or to go while the box is open. Returns whether the call is answered here.
    _answer(toggling) {
        const event = Clutter.get_current_event();
        const isKey = event ? KEY_EVENTS.includes(event.type()) : false;

        // The Super key: the typing goes back to the field, and the box stays
        if (toggling && isKey && SUPER_KEYS.includes(event.get_key_symbol())) {
            this._lent.entry.grab_key_focus();
            return true;
        }

        // A result was opened from the box (or from its menu): the box is gone at once, so that the app appears
        // without it, and no overview comes. Anything else that wants the overview gets it, without the box, which
        // gives the search back as the overview starts to show. The search itself is given back only once the
        // result has finished, since giving it back empties the results.
        const source = event ? global.stage.get_event_actor(event) : null;
        const fromBox = source !== null && this._box.contains(source) &&
            (isKey ? OPENING_KEYS.includes(event.get_key_symbol()) : POINTER_EVENTS.includes(event.type()));
        this._close('quick');
        return toggling && fromBox;
    }

    _onKeyPress(event) {
        if (!this._open)
            return Clutter.EVENT_PROPAGATE;

        const symbol = event.get_key_symbol();
        // The field handles Escape itself (it empties and lets go, which closes the box); here a result has the focus
        if (symbol === Clutter.KEY_Escape) {
            this._close('animate');
            return Clutter.EVENT_STOP;
        }

        // Typing while a result has the focus goes back to the field
        const modifiers = Clutter.ModifierType.CONTROL_MASK | Clutter.ModifierType.MOD1_MASK |
            Clutter.ModifierType.SUPER_MASK;
        if ((event.get_state() & modifiers) !== 0)
            return Clutter.EVENT_PROPAGATE;
        // The character comes as a string (none is an empty one)
        const typing = symbol === Clutter.KEY_BackSpace || PRINTABLE.test(event.get_key_unicode() ?? '');
        const text = this._lent.entry.clutter_text;
        if (typing && global.stage.get_key_focus() !== text) {
            text.grab_key_focus();
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    // The keyboard went somewhere: looked at once the change has settled (a drag takes the keyboard before it says
    // that it started, and the results move it while they are rebuilt)
    _queueFocusCheck() {
        if (!this._focusLater)
            this._queueLater('_focusLater', () => this._checkFocus());
    }

    _checkFocus() {
        if (!this._open || this._dragging)
            return;
        const focus = global.stage.get_key_focus();
        if (focus && focus !== global.stage && (this._box.contains(focus) || this._isResultMenu(focus)))
            return;
        this._close('animate');
    }

    // A result's own menu (right click, or the menu key): it opens over the box and leaves it open
    _isResultMenu(actor) {
        for (let at = actor; at; at = at.get_parent()) {
            const menu = at._delegate;
            if (menu instanceof PopupMenu.PopupMenuBase && menu.sourceActor && this._box.contains(menu.sourceActor))
                return true;
        }
        return false;
    }

    _queueLater(name, callback) {
        this._removeLater(name);
        this[name] = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this[name] = 0;
            callback();
            return GLib.SOURCE_REMOVE;
        });
    }

    _removeLater(name) {
        if (this[name])
            global.compositor.get_laters().remove(this[name]);
        this[name] = 0;
    }
}
