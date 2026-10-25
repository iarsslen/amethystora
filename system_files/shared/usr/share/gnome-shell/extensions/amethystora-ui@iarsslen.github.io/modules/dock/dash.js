// The dock's row of icons: GNOME's own dash, moved out of the overview. GNOME's code still lists the pinned and the
// running apps, sizes their icons to fit, shows their names, takes drops to pin and opens GNOME's app menu; this adds
// what the dock does beyond the dash: running apps kept in the order they started, the drives and the trash, a dot
// per window, the focused app lit, a wiggle for an app that wants attention, what apps say about themselves (a
// count, a progress bar, their own menu entries), what a click does, and the app grid button opening the overview.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Mtk from 'gi://Mtk';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {gettext as _, ngettext} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as AppFavorites from 'resource:///org/gnome/shell/ui/appFavorites.js';
import * as Dash from 'resource:///org/gnome/shell/ui/dash.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Clicks} from './clicks.js';
import {PlaceButton, fillPlaceMenu, fillQuicklist} from './menus.js';

// The largest icon. GNOME's next size up is 64, so a bound on the height between the two leaves 48 the largest.
const LARGEST = 48;
const MAX_DOTS = 4;
// A call for attention: two shakes of up to 15 degrees at the start of every three seconds
const WIGGLE_EVERY = 3000;
const WIGGLE_TIME = 500;
const WIGGLE_ANGLE = 15;
// Milliseconds the pointer rests on an item of a row too long for the screen before it is scrolled into view
const HOVER_REVEAL = 100;
const SCROLL_TIME = 100;
// How large the count is beside a smaller icon: [icon size from, share of its size at 48 px]
const SHRINK = [[48, 1], [32, 0.87], [24, 0.65]];

// Most recently used first
const byUse = windows => windows.sort((a, b) => b.get_user_time() - a.get_user_time());

export const DockDash = GObject.registerClass(
class AmethystoraDockDash extends Dash.Dash {
    _init(places, launcher) {
        super._init();
        this._places = places;
        this._launcher = launcher;
        this._clicks = new Clicks(this, places, launcher);
        this._items = new Map();
        this._placeItems = new Map();
        this._attention = new Set();
        this._started = [];
        this.add_style_class_name('amethystora-dock-dash');
        this.set({x_align: Clutter.ActorAlign.CENTER, y_align: Clutter.ActorAlign.END, reactive: true});

        // The dock's own entry in Ctrl+Alt+Tab, in place of the dash's
        Main.ctrlAltTabManager.removeGroup(this);
        Main.ctrlAltTabManager.addGroup(this, _('Dock'), 'user-bookmarks-symbolic');

        // GNOME lists running apps most recently used first, which would move them about as they are used: the
        // dock keeps them in the order they started, and leaves out an app whose every window shows a place
        const apps = Shell.AppSystem.get_default();
        this._appSystem = {get_running: () => this._inStartOrder(apps.get_running())};

        // A row too long for the screen scrolls, faded at the ends, but never under the wheel
        this._scroll = new St.ScrollView({
            style_class: 'amethystora-dock-scroll',
            hscrollbar_policy: St.PolicyType.EXTERNAL,
            vscrollbar_policy: St.PolicyType.NEVER,
            enable_mouse_scrolling: false,
            x_expand: true,
            y_expand: true,
        });
        const row = new St.BoxLayout({x_expand: true, y_expand: true});
        this._dashContainer.remove_child(this._box);
        row.add_child(this._box);
        // GNOME's row claims no width of its own so that the overview's dash can shrink; inside the scroll view it
        // claims all of it, which is what the view scrolls through
        this._box.layout_manager = new Clutter.BoxLayout({orientation: Clutter.Orientation.HORIZONTAL});
        this._scroll.child = row;
        this._dashContainer.insert_child_at_index(this._scroll, 0);
        this._dashContainer.add_style_class_name('amethystora-dock-row');

        // The app grid button opens the overview's app grid; it shows as on while the grid is shown
        const gridButton = Main.overview.dash.showAppsButton;
        this.showAppsButton.toggle_mode = false;
        this.showAppsButton.connectObject('clicked', () => this._toggleApps(), this);
        this._gridBinding = gridButton.bind_property('checked', this.showAppsButton, 'checked',
            GObject.BindingFlags.SYNC_CREATE);
        gridButton.connectObject('notify::checked', () => {
            if (!gridButton.checked)
                this._appsFromDesktop = false;
        }, this);
        Main.overview.connectObject('hidden', () => (this._appsFromDesktop = false), this);
        this._showAppsIcon.label?.add_style_class_name('amethystora-dock-label');

        this._banners = new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'});
        this._banners.connectObject('changed::show-banners', () => this._syncAll(), this);
        St.Settings.get().connectObject('notify::enable-animations', () => this._syncWiggle(), this);
        global.display.connectObject(
            'notify::focus-window', () => this._onFocus(),
            'window-demands-attention', (display, window) => this._watchAttention(window),
            'window-marked-urgent', (display, window) => this._watchAttention(window),
            this);
        for (const window of global.display.list_all_windows()) {
            if (window.demands_attention || window.urgent)
                this._watchAttention(window);
        }
        Main.messageTray.connectObject(
            'source-added', (tray, source) => this._watchSource(source),
            'source-removed', (tray, source) => {
                source.disconnectObject(this);
                this._syncAll();
            }, this);
        for (const source of Main.messageTray.getSources())
            this._watchSource(source);
        places.connectObject(
            'places-changed', () => this._syncPlaces(),
            'place-changed', (o, place) => {
                const item = this._placeItems.get(place);
                item?.child.sync();
                item?.setLabelText(place.name);
            },
            'windows-changed', () => {
                this._queueRedisplay();
                this._syncAll();
                this._queueGeometry();
            }, this);
        launcher.connectObject('changed', () => this._syncAll(), this);
        this.connect('icon-size-changed', () => this._syncSizes());
        this.connect('notify::mapped', () => this._syncWiggle());
        this.connect('notify::allocation', () => this._queueGeometry());
        this.connect('destroy', () => this._onDestroy());

        this._syncPlaces();
    }

    // The pill the glass is drawn behind
    get pill() {
        return this._background;
    }

    // The widest the row may be. GNOME picks the largest of its icon sizes that fits both ways; the height given
    // here leaves 48 px the largest, whatever padding the theme puts around an icon. What is around the icon is
    // measured against the icon as drawn, not this.iconSize: in the overview GNOME eases an icon to its new size,
    // and every frame of that changes the dock's height and comes back here, which against this.iconSize gave a
    // new limit, a new size and a new ease, for ever.
    fitTo(width) {
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const [, height] = this.get_preferred_height(-1);
        const icon = this._showAppsIcon.icon?.icon;
        const [, drawn] = icon ? icon.get_preferred_height(-1) : [0, this.iconSize * scale];
        const around = Math.max(0, height - drawn);
        // What GNOME does not count: the pill's own ends and the line after the pinned apps
        const pill = this._background.get_theme_node();
        const ends = pill.get_horizontal_padding() + pill.get_border_width(St.Side.LEFT) * 2 + 8 * scale;
        this.setMaxSize(Math.max(0, width - ends), around + (LARGEST + 4) * scale);
    }

    // An item's windows that are not kept from the taskbar, most recently used first
    windowsOf(key) {
        return byUse(key instanceof Shell.App ? this._windowsOfApp(key) : this._places.windowsOf(key));
    }

    // The app or place whose window has the focus
    focusedKey() {
        const window = global.display.focus_window;
        if (!window)
            return null;
        return this._places.owner(window) ?? Shell.WindowTracker.get_default().get_window_app(window);
    }

    vfunc_scroll_event() {
        return Clutter.EVENT_STOP;
    }

    _onDestroy() {
        this._clicks.destroy();
        this._gridBinding?.unbind();
        this._gridBinding = null;
        // GNOME's dash leaves its label timers running when it goes, which then show a label that is gone: the
        // dock goes whenever the screen locks, and the pointer is often over it
        for (const id of [this._wiggleId, this._revealId, this._showLabelTimeoutId, this._resetHoverTimeoutId]) {
            if (id)
                GLib.source_remove(id);
        }
        this._wiggleId = this._revealId = this._showLabelTimeoutId = this._resetHoverTimeoutId = 0;
        this._wiggle?.stop();
        this._wiggle = null;
        if (this._geometryId)
            global.compositor.get_laters().remove(this._geometryId);
        this._geometryId = 0;
        for (const window of this._attention)
            window.disconnectObject(this);
        this._attention.clear();
        // The minimize animation would otherwise still aim at where the dock was
        for (const window of global.display.list_all_windows())
            window.set_icon_geometry(null);
    }

    // GNOME's separator sits among the icons and throws out the places GNOME inserts new apps at, which count only
    // apps: it is taken away before GNOME redraws the row, and GNOME puts a new one back
    _redisplay() {
        this._separator?.destroy();
        this._separator = null;
        super._redisplay();

        // The line also comes between the pinned apps and the places when no other app runs
        const children = this._box.get_children();
        const pinned = child => child.child?._delegate?.app && !child.animatingOut &&
            this._isPinned(child.child._delegate.app);
        if (!this._separator && children.some(pinned) && this._placeItems.size > 0) {
            this._separator = new St.Widget({
                style_class: 'dash-separator',
                y_align: Clutter.ActorAlign.CENTER,
                height: this.iconSize,
            });
            this._box.insert_child_at_index(this._separator, children.findLastIndex(pinned) + 1);
        }
        this._syncAll();
        this._queueGeometry();
    }

    _isPinned(app) {
        return AppFavorites.getAppFavorites().isFavorite(app.get_id());
    }

    _inStartOrder(running) {
        running = running.filter(app => app.get_n_windows() === 0 || this._windowsOfApp(app).length > 0);
        this._started = this._started.filter(app => running.includes(app));
        for (const app of running) {
            if (!this._started.includes(app))
                this._started.push(app);
        }
        return [...this._started];
    }

    _windowsOfApp(app) {
        return app.get_windows().filter(window => !window.skip_taskbar && !this._places.owner(window));
    }

    // An app's icon is GNOME's; what the dock does with it is given to that one icon
    _createAppItem(app) {
        const item = super._createAppItem(app);
        const icon = item.child;
        icon.activate = button => this._clicks.act(this._clicks.appTarget(icon), button);
        icon.popupMenu = () => {
            const result = Dash.DashIcon.prototype.popupMenu.call(icon);
            if (icon._menu)
                fillQuicklist(icon._menu, this._launcher.quicklist(app.get_id()));
            return result;
        };
        // The icon being dragged stays behind, faint, rather than at full strength
        icon.scaleAndFade = () => (icon.opacity = 51);
        icon.undoScaleAndFade = () => (icon.opacity = 255);
        icon.getDragActor = () => app.create_icon_texture(this.iconSize);
        // GNOME's single running dot gives way to one dot per window
        icon._dot.opacity = 0;
        // GNOME leaves the menu behind when the icon goes
        icon.connect('destroy', () => icon._menu?.destroy());
        this._decorate(item, app);
        return item;
    }

    _syncPlaces() {
        const wanted = this._places.list();
        for (const [place, item] of [...this._placeItems]) {
            if (wanted.includes(place))
                continue;
            this._placeItems.delete(place);
            item.animateOutAndDestroy();
        }
        for (const place of wanted) {
            if (this._placeItems.has(place))
                continue;
            const item = new Dash.DashItemContainer();
            const button = new PlaceButton(place,
                mouseButton => this._clicks.act(this._clicks.placeTarget(place), mouseButton),
                menu => fillPlaceMenu(menu, place, this._places, () => this.windowsOf(place)));
            button.connect('menu-state-changed', (o, open) => this._itemMenuStateChanged(item, open));
            item.setChild(button);
            item.setLabelText(place.name);
            button.icon.setIconSize(this.iconSize);
            this._hookUpLabel(item);
            // Before the trash, which stays last
            const trash = this._placeItems.get(this._places.trash);
            const index = trash ? this._box.get_children().indexOf(trash) : -1;
            this._box.insert_child_at_index(item, index >= 0 ? index : this._box.get_n_children());
            this._placeItems.set(place, item);
            this._decorate(item, place);
            item.show(this._shownInitially && Main.overview.visible);
        }
        // The line after the pinned apps, and the icon size, with the places counted
        this._queueRedisplay();
    }

    // The dots, the count, the progress bar and the urgency of one item, whether app or place
    _decorate(item, key) {
        const button = item.child;
        const state = {
            item,
            key,
            button,
            count: 0,
            dots: new St.BoxLayout({
                style_class: 'amethystora-dock-dots',
                x_align: Clutter.ActorAlign.CENTER,
                y_align: Clutter.ActorAlign.END,
                x_expand: true,
                y_expand: true,
            }),
            badge: new St.Label({
                style_class: 'amethystora-dock-badge',
                x_align: Clutter.ActorAlign.END,
                y_align: Clutter.ActorAlign.START,
                x_expand: true,
                y_expand: true,
                visible: false,
            }),
            progress: new St.Widget({
                style_class: 'amethystora-dock-progress',
                layout_manager: new Clutter.BinLayout(),
                y_align: Clutter.ActorAlign.END,
                x_expand: true,
                y_expand: true,
                visible: false,
            }),
            // From the start side, which Clutter turns round for right-to-left languages
            fill: new St.Widget({
                style_class: 'amethystora-dock-progress-fill',
                x_align: Clutter.ActorAlign.START,
                y_expand: true,
            }),
        };
        state.progress.add_child(state.fill);
        state.progress.connect('notify::width', () => this._syncFill(state));
        const container = button._iconContainer;
        container.add_child(state.progress);
        container.add_child(state.dots);
        container.add_child(state.badge);
        item.label?.add_style_class_name('amethystora-dock-label');

        // A row too long for the screen shows an item the pointer rests on, or the keyboard reaches
        button.connect('notify::hover', () => this._onHover(button));
        button.connect('key-focus-in', () => this._reveal(item));
        button.connect('clicked', () => this._reveal(item));
        button.connect('destroy', () => this._items.delete(button));
        if (key instanceof Shell.App) {
            key.connectObject('windows-changed', () => {
                this._sync(state);
                this._queueGeometry();
            }, button);
        }
        this._items.set(button, state);
        this._syncSize(state);
        this._sync(state);
    }

    _onFocus() {
        this._syncAll();
        const focused = this.focusedKey();
        for (const state of this._items.values()) {
            if (state.key === focused)
                this._reveal(state.item);
        }
    }

    _syncAll() {
        for (const state of this._items.values())
            this._sync(state);
        this._syncWiggle();
    }

    _sync(state) {
        const {key, button} = state;
        const windows = this.windowsOf(key);
        const entry = key instanceof Shell.App ? this._launcher.get(key.get_id()) : null;

        const dots = Math.min(windows.length, MAX_DOTS);
        if (state.dots.get_n_children() !== dots) {
            state.dots.destroy_all_children();
            for (let i = 0; i < dots; i++)
                state.dots.add_child(new St.Widget({style_class: 'app-grid-running-dot amethystora-dock-dot'}));
            this._syncSize(state);
        }

        if (key === this.focusedKey())
            button.add_style_class_name('amethystora-dock-focused');
        else
            button.remove_style_class_name('amethystora-dock-focused');

        const quiet = !this._banners.get_boolean('show-banners');
        const count = quiet || !(key instanceof Shell.App) ? 0 : this._unread(key, entry);
        state.badge.visible = count > 0;
        state.badge.text = count > 0 ? this._shortCount(count) : '';
        if (count !== state.count) {
            state.count = count;
            const name = key instanceof Shell.App ? key.get_name() : key.name;
            button.accessible_name = count > 0
                ? ngettext('%s, %d unread', '%s, %d unread', count).format(name, count) : name;
        }

        const progress = entry?.progressVisible ? Math.clamp(Number(entry.progress) || 0, 0, 1) : null;
        state.progress.visible = progress !== null;
        state.value = progress ?? 0;
        this._syncFill(state);

        const image = button.icon?.icon;
        if (image)
            image.opacity = entry?.updating ? 128 : 255;

        const urgent = Boolean(entry?.urgent) || windows.some(window => this._attention.has(window));
        if (urgent && !state.urgent)
            this._reveal(state.item);
        state.urgent = urgent;
    }

    _syncSizes() {
        for (const state of this._items.values())
            this._syncSize(state);
        this._separator?.set_height(this.iconSize);
    }

    // The dots, the bar and the count scale with the icon
    _syncSize(state) {
        const size = this.iconSize;
        const tile = size + 12;
        const dot = Math.max(2, Math.round(tile * 0.09));
        state.dots.set_style(`spacing: ${Math.max(1, Math.round(dot / 2))}px;`);
        for (const child of state.dots.get_children())
            child.set_style(`width: ${dot}px; height: ${dot}px; border-radius: ${dot}px;`);

        // Inside the icon, a twentieth of it in from the sides and the bottom
        const inset = 6 + Math.round(size * 0.05);
        const height = Math.min(18, Math.round(size * 0.2));
        state.progress.set_style(`margin: 0 ${inset}px ${inset}px ${inset}px; height: ${height}px;`);

        // The count shrinks less than the icon does, and never below half
        const shrink = SHRINK.find(([smallest]) => size >= smallest)?.[1] ?? 0.5;
        state.badge.set_style(`font-size: ${(0.9 * shrink).toFixed(2)}em; margin-left: ${Math.round(3 * shrink)}px;`);
    }

    _syncFill(state) {
        if (!state.progress.visible || !state.progress.has_allocation())
            return;
        const box = state.progress.get_theme_node().get_content_box(state.progress.get_allocation_box());
        state.fill.width = Math.round((box.x2 - box.x1) * state.value);
    }

    // Notifications in the tray, but resident ones already seen; an app's own count above zero instead
    _unread(app, entry) {
        if (entry?.countVisible && Number(entry.count) > 0)
            return Number(entry.count);
        let count = 0;
        for (const source of Main.messageTray.getSources()) {
            if ((source.app ?? source._app) === app)
                count += source.notifications.filter(n => !(n.resident && n.acknowledged)).length;
        }
        return count;
    }

    _shortCount(count) {
        if (count <= 9999)
            return count.toLocaleString(undefined, {useGrouping: false});
        // Thousands, millions and billions, with a decimal while it says something
        const fractions = Math.floor(Math.log10(count)) % 3 === 2 ? 0 : 1;
        return new Intl.NumberFormat(undefined, {notation: 'compact', maximumFractionDigits: fractions}).format(count);
    }

    _watchSource(source) {
        source.connectObject('notify::count', () => this._syncAll(), this);
        this._syncAll();
    }

    _watchAttention(window) {
        if (this._attention.has(window))
            return;
        this._attention.add(window);
        const forget = () => {
            window.disconnectObject(this);
            this._attention.delete(window);
            this._syncAll();
        };
        window.connectObject(
            'notify::demands-attention', () => !window.demands_attention && !window.urgent && forget(),
            'notify::urgent', () => !window.demands_attention && !window.urgent && forget(),
            'unmanaged', forget,
            this);
        this._syncAll();
    }

    // One clock for every icon that wiggles, so that they move together; none while animations are off, while
    // notifications are silenced or while the dock is not on screen
    _syncWiggle() {
        const shaking = [...this._items.values()].some(state => state.urgent);
        const run = shaking && this.mapped && St.Settings.get().enable_animations &&
            this._banners.get_boolean('show-banners');
        if (run && !this._wiggleId) {
            this._shake();
            this._wiggleId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, WIGGLE_EVERY, () => {
                this._shake();
                return GLib.SOURCE_CONTINUE;
            });
        } else if (!run && this._wiggleId) {
            GLib.source_remove(this._wiggleId);
            this._wiggleId = 0;
            this._wiggle?.stop();
            this._tilt(0);
        } else if (run) {
            // An icon that stopped asking stands still at once
            this._tilt(null);
        }
    }

    _shake() {
        if (!this._wiggle) {
            this._wiggle = new Clutter.Timeline({actor: this, duration: WIGGLE_TIME});
            this._wiggle.connect('new-frame', timeline =>
                this._tilt(WIGGLE_ANGLE * Math.sin(4 * Math.PI * timeline.get_progress())));
            this._wiggle.connect('completed', () => this._tilt(0));
        }
        // As fast as GNOME's own animations are
        this._wiggle.duration = Math.max(1, WIGGLE_TIME * St.Settings.get().slow_down_factor);
        this._wiggle.rewind();
        this._wiggle.start();
    }

    // The angle for every icon that wants attention, 0 for the rest; null keeps the shaking ones as they are
    _tilt(angle) {
        for (const state of this._items.values()) {
            const image = state.button.icon?.icon;
            if (!image)
                continue;
            if (!state.urgent || angle === 0) {
                image.rotation_angle_z = 0;
            } else if (angle !== null) {
                image.set_pivot_point(0.5, 0.5);
                image.rotation_angle_z = angle;
            }
        }
    }

    // Each window minimizes into its item
    _queueGeometry() {
        if (this._geometryId)
            return;
        this._geometryId = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._geometryId = 0;
            for (const state of this._items.values()) {
                if (!state.button.mapped)
                    continue;
                const [x, y] = state.button.get_transformed_position();
                const [width, height] = state.button.get_transformed_size();
                const rect = new Mtk.Rectangle({
                    x: Math.round(x),
                    y: Math.round(y),
                    width: Math.round(width),
                    height: Math.round(height),
                });
                for (const window of this.windowsOf(state.key))
                    window.set_icon_geometry(rect);
            }
            return GLib.SOURCE_REMOVE;
        });
    }

    _overflows() {
        const [, , upper, , , page] = this._scroll.hadjustment.get_values();
        return upper > page;
    }

    _onHover(button) {
        if (this._revealId)
            GLib.source_remove(this._revealId);
        this._revealId = 0;
        if (!button.hover || !this._overflows())
            return;
        this._revealId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, HOVER_REVEAL, () => {
            this._revealId = 0;
            const state = this._items.get(button);
            if (state)
                this._reveal(state.item);
            return GLib.SOURCE_REMOVE;
        });
    }

    // Scrolls a row too long for the screen until the item is clear of the faded ends
    _reveal(item) {
        if (!this._overflows() || !item.has_allocation() || item.get_parent() !== this._box)
            return;
        const adjustment = this._scroll.hadjustment;
        const [value, , upper, , , page] = adjustment.get_values();
        const fade = this._scroll.get_theme_node().get_length('-st-hfade-offset');
        const box = item.get_allocation_box();
        const rtl = this._box.get_text_direction() === Clutter.TextDirection.RTL;
        const start = rtl ? upper - box.x2 : box.x1;
        const end = rtl ? upper - box.x1 : box.x2;
        let target = value;
        if (start < value + fade)
            target = start - fade;
        else if (end > value + page - fade)
            target = end - page + fade;
        target = Math.clamp(target, 0, upper - page);
        if (target !== value)
            adjustment.ease(target, {duration: SCROLL_TIME, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
    }

    // From the desktop the button opens the app grid, and closes it again; in the overview it switches between
    // the windows and the app grid, as GNOME's own button does
    _toggleApps() {
        const gridButton = Main.overview.dash.showAppsButton;
        if (!Main.overview.visible) {
            Main.overview.showApps();
            this._appsFromDesktop = true;
        } else if (gridButton.checked && this._appsFromDesktop) {
            Main.overview.hide();
        } else {
            gridButton.checked = !gridButton.checked;
        }
    }
});
