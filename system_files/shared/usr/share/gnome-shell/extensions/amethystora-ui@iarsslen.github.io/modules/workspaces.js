// The workspaces as a row of labels in the top bar, after the logo menu. The one you are on is filled with the
// theme's accent, one with windows on it is in the theme's text colour, and an empty one is fainter. Click a label to
// go there: the one you are on shows or hides the overview instead, and an empty one opens the overview, ready to
// search or start an app. Scrolling anywhere on the top bar steps to the previous or next workspace. Drag a label
// along the row to move its workspace, windows and all, or drop a window from the overview on a label to send the
// window there. A right click, or a finger held on a label, opens a field to rename the workspace you are on. Two keys
// move the workspace you are on one place to the left or right. There are always as many workspaces as GNOME is set
// to keep (six), so that Super+1 to Super+6 reach every one: nothing here adds or removes one. The workspaces, their
// names and the keys that switch them are GNOME's own.

import Atk from 'gi://Atk';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as BoxPointer from 'resource:///org/gnome/shell/ui/boxpointer.js';
import * as DND from 'resource:///org/gnome/shell/ui/dnd.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const ROLE = 'amethystora-workspaces';
const SCHEMA = 'org.gnome.shell.extensions.amethystora-ui.workspaces';
const KEYS = ['move-workspace-left', 'move-workspace-right'];
// GNOME's own list of names, by workspace position
const PREFS = 'org.gnome.desktop.wm.preferences';
const NAMES = 'workspace-names';
// A press held longer than this before its release is no click: it may have been the start of a drag
const CLICK_MS = 300;
// How long a finger rests on a label before the menu opens
const LONG_PRESS_MS = 500;
// At most one workspace per this long when scrolling, so that a fast spin of the wheel does not race to the end
const SCROLL_PAUSE_MS = 200;
// How long a gap in the row takes to open or close while a label is dragged along it
const GAP_MS = 500;
const STATES = ['active', 'busy', 'empty'];

// A workspace counts as having windows when one of them lives on it alone: a window on every workspace (pinned, or
// on another monitor while only the main one has workspaces) says nothing about this one
function hasWindows(workspace) {
    return workspace.list_windows().some(w => !w.is_on_all_workspaces());
}

// The window to focus on arriving: the one last used there, as Alt+Tab orders them, where a dialog fixed to its
// window stands for that window and windows kept out of the taskbar or on every workspace are passed over
function recentWindow(workspace) {
    for (let window of global.display.get_tab_list(Meta.TabList.NORMAL_ALL, workspace)) {
        if (window.is_attached_dialog())
            window = window.get_transient_for() ?? window;
        if (!window.skip_taskbar && !window.is_on_all_workspaces())
            return window;
    }
    return null;
}

function isRtl(actor) {
    return actor.get_text_direction() === Clutter.TextDirection.RTL;
}

// One workspace's label. It is its own drag source, and takes a window dropped on it.
const WorkspaceLabel = GObject.registerClass(
class WorkspaceLabel extends St.Label {
    _init(row) {
        super._init({
            style_class: 'amethystora-workspaces-label',
            reactive: true,
            y_align: Clutter.ActorAlign.CENTER,
            accessible_role: Atk.Role.PUSH_BUTTON,
        });
        this._row = row;
        this._delegate = this;
        this.index = -1;

        // A click goes on the release, and only when it came soon after its press, so that a press that turns
        // into a drag never switches
        const click = new Clutter.ClickGesture({required_button: Clutter.BUTTON_PRIMARY});
        click.connect('notify::pressed', gesture => {
            if (gesture.pressed)
                this._pressedAt = GLib.get_monotonic_time();
        });
        click.connect('recognize', () => {
            if (GLib.get_monotonic_time() - this._pressedAt <= CLICK_MS * 1000)
                row.clicked(this.index);
        });
        this.add_action(click);

        // A second right click closes the menu again
        const menu = new Clutter.ClickGesture({required_button: Clutter.BUTTON_SECONDARY, recognize_on_press: true});
        menu.connect('recognize', () => row.toggleMenu());
        this.add_action(menu);

        // A finger only: a mouse button held still is the start of a click or a drag
        const hold = new Clutter.LongPressGesture({long_press_duration_ms: LONG_PRESS_MS});
        hold.connect('should-handle-sequence', (gesture, event) => event.type() === Clutter.EventType.TOUCH_BEGIN);
        hold.connect('recognize', () => row.openMenu());
        this.add_action(hold);

        this._draggable = DND.makeDraggable(this);
        this._draggable.connect('drag-begin', () => row.dragBegan(this));
        this._draggable.connect('drag-cancelled', () => row.dragCancelled());
        this._draggable.connect('drag-end', () => row.dragEnded(this));
    }

    update(index, text, state) {
        this.index = index;
        if (this.text !== text)
            this.text = text;
        for (const name of STATES) {
            if (name === state)
                this.add_style_class_name(`amethystora-workspaces-${name}`);
            else
                this.remove_style_class_name(`amethystora-workspaces-${name}`);
        }
        const accessible = _('Workspace %d').format(index + 1);
        if (this.accessible_name !== accessible)
            this.accessible_name = accessible;
    }

    // Another label passes on to the row, which makes room for it; anything but a window is refused there
    handleDragOver(source) {
        return source?.metaWindow ? DND.DragMotionResult.MOVE_DROP : DND.DragMotionResult.CONTINUE;
    }

    acceptDrop(source) {
        if (!source?.metaWindow)
            return false;
        source.metaWindow.change_workspace_by_index(this.index, false);
        return true;
    }
});

// The panel button that holds the row. It has no click of its own and no highlight under the pointer: only its
// labels answer. The row itself takes a label dropped on it (the button's own drop handler is the place-holder menu
// GNOME gives a button without one).
const WorkspaceRow = GObject.registerClass(
class WorkspaceRow extends PanelMenu.Button {
    _init(module) {
        super._init(0.5, _('Workspaces'), true);
        this.track_hover = false;
        this.add_style_class_name('amethystora-workspaces-button');
        this.box = new St.BoxLayout({style_class: 'amethystora-workspaces-row', y_align: Clutter.ActorAlign.CENTER});
        this.box._delegate = {
            handleDragOver: (source, actor) => module.dragOver(source, actor),
            acceptDrop: (source, actor) => module.drop(source, actor),
        };
        this.add_child(this.box);
    }
});

export class Workspaces {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        this._labels = [];
        this._watched = new Set();
        this._prefs = new Gio.Settings({schema_id: PREFS});

        this._row = new WorkspaceRow(this);
        this._row.connect('destroy', () => {
            this._row = null;
        });
        Main.panel.addToStatusArea(ROLE, this._row, 1, 'left');
        this._buildMenu();

        const queue = () => this._queue();
        global.workspace_manager.connectObject(
            'notify::n-workspaces', queue,
            'workspace-added', queue,
            'workspace-removed', queue,
            'workspaces-reordered', () => this._reordered(),
            'active-workspace-changed', queue, this);
        Shell.WindowTracker.get_default().connectObject('tracked-windows-changed', queue, this);
        this._prefs.connectObject(`changed::${NAMES}`, queue, this);

        // Scrolling anywhere on the bar that nothing under the pointer took for itself
        Main.panel.connectObject('scroll-event', (actor, event) => this._scrolled(event), this);

        this._settings = this._ext.getSettings(SCHEMA);
        const modes = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;
        Main.wm.addKeybinding(KEYS[0], this._settings, Meta.KeyBindingFlags.NONE, modes, () => this._shift(-1));
        Main.wm.addKeybinding(KEYS[1], this._settings, Meta.KeyBindingFlags.NONE, modes, () => this._shift(1));
        this._keys = true;

        this._refresh();
    }

    disable() {
        if (this._keys) {
            for (const key of KEYS)
                Main.wm.removeKeybinding(key);
        }
        this._keys = false;
        this._settings = null;

        Main.panel.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        Shell.WindowTracker.get_default().disconnectObject(this);
        this._prefs?.disconnectObject(this);
        for (const workspace of this._watched ?? [])
            workspace.disconnectObject(this);
        this._watched = null;

        if (this._later)
            global.compositor.get_laters().remove(this._later);
        this._later = 0;
        if (this._scrollPause)
            GLib.source_remove(this._scrollPause);
        this._scrollPause = 0;

        // A label being dragged lives outside the row until the drag ends: taking it away ends the drag
        const dragged = this._drag?.label;
        this._drag = null;
        this._dropped = null;
        dragged?.destroy();

        this._menu?.destroy();
        this._menu = null;
        this._row?.destroy();
        this._row = null;
        this._labels = null;
        this._order = null;
        this._prefs = null;
    }

    // Everything that can change a label lands here, and the row is brought up to date once, before the next frame
    _queue() {
        if (this._later)
            return;
        this._later = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._later = 0;
            this._refresh();
            return GLib.SOURCE_REMOVE;
        });
    }

    // The row has a label per workspace, the label at a place standing for the workspace at that place. Only what
    // changed is touched, so a refresh that finds the row as it was draws nothing.
    _refresh() {
        if (!this._row || this._drag)
            return;
        if (this._dropped) {
            // Back from a drag that went nowhere: put back in the row at its end, so it is made again in its place
            const label = this._dropped;
            this._dropped = null;
            label.destroy();
        }

        const manager = global.workspace_manager;
        const count = manager.n_workspaces;
        while (this._labels.length < count) {
            const label = new WorkspaceLabel(this);
            label.connect('destroy', () => {
                const at = this._labels?.indexOf(label) ?? -1;
                if (at >= 0)
                    this._labels.splice(at, 1);
            });
            this._labels.push(label);
            this._row.box.add_child(label);
        }
        while (this._labels.length > count)
            this._labels.at(-1).destroy();

        const active = manager.get_active_workspace_index();
        const names = this._prefs.get_strv(NAMES);
        this._order = this._workspaces();
        this._labels.forEach((label, index) => {
            const workspace = manager.get_workspace_by_index(index);
            let state = 'empty';
            if (index === active)
                state = 'active';
            else if (hasWindows(workspace))
                state = 'busy';
            label.update(index, names[index] || `${index + 1}`, state);
        });

        // A window opened, closed or moved onto or off any workspace
        const workspaces = new Set(this._order);
        for (const workspace of this._watched) {
            if (!workspaces.has(workspace))
                workspace.disconnectObject(this);
        }
        for (const workspace of workspaces) {
            if (!this._watched.has(workspace)) {
                workspace.connectObject(
                    'window-added', () => this._queue(),
                    'window-removed', () => this._queue(), this);
            }
        }
        this._watched = workspaces;
    }

    _workspaces() {
        const manager = global.workspace_manager;
        const workspaces = [];
        for (let index = 0; index < manager.n_workspaces; index++)
            workspaces.push(manager.get_workspace_by_index(index));
        return workspaces;
    }

    // A workspace that something else moved keeps its name as well: the names follow the workspaces from the order
    // they were last seen in. A move of the row's own has written them already.
    _reordered() {
        const now = this._workspaces();
        if (!this._moving && this._order) {
            const names = this._namesFor(this._order.length);
            this._writeNames(now.map(workspace => names[this._order.indexOf(workspace)] ?? ''));
        }
        this._order = now;
        this._queue();
    }

    // Every click on the one you are on shows or hides the overview, even one that comes while it is still sliding
    clicked(index) {
        const manager = global.workspace_manager;
        if (index === manager.get_active_workspace_index()) {
            Main.overview.toggle();
            return;
        }
        const workspace = manager.get_workspace_by_index(index);
        if (!workspace)
            return;
        if (!hasWindows(workspace) && !Main.overview.visible) {
            workspace.activate(global.get_current_time());
            Main.overview.show();
            return;
        }
        this._goTo(workspace);
    }

    _goTo(workspace) {
        const time = global.get_current_time();
        const window = recentWindow(workspace);
        if (window)
            workspace.activate_with_focus(window, time);
        else
            workspace.activate(time);
    }

    // A notch of the wheel steps one workspace, up to the previous and down to the next, and stops at either end. Two
    // fingers on a touchpad do the same: GNOME turns their smooth scrolling into steps too, which count as notches.
    // The smooth events themselves and sideways scrolling are left to whatever else wants them.
    _scrolled(event) {
        let step;
        switch (event.get_scroll_direction()) {
        case Clutter.ScrollDirection.UP:
            step = -1;
            break;
        case Clutter.ScrollDirection.DOWN:
            step = 1;
            break;
        default:
            return Clutter.EVENT_PROPAGATE;
        }
        if (this._scrollPause)
            return Clutter.EVENT_STOP;

        const manager = global.workspace_manager;
        const target = manager.get_workspace_by_index(manager.get_active_workspace_index() + step);
        if (!target)
            return Clutter.EVENT_STOP;
        this._scrollPause = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SCROLL_PAUSE_MS, () => {
            this._scrollPause = 0;
            return GLib.SOURCE_REMOVE;
        });
        this._goTo(target);
        return Clutter.EVENT_STOP;
    }

    // The keys move the workspace you are on by one place, as the row shows it: in a right-to-left language the row
    // runs from the right, so the left key moves it to a later place
    _shift(direction) {
        const step = this._row && isRtl(this._row) ? -direction : direction;
        const from = global.workspace_manager.get_active_workspace_index();
        this._move(from, from + step);
    }

    // A workspace moved to another place takes its windows and its name with it; the others close up behind it
    _move(from, to) {
        const manager = global.workspace_manager;
        if (from === to || to < 0 || to >= manager.n_workspaces)
            return;
        const names = this._namesFor(manager.n_workspaces);
        const [name] = names.splice(from, 1);
        names.splice(to, 0, name);
        this._moving = true;
        manager.reorder_workspace(manager.get_workspace_by_index(from), to);
        this._moving = false;
        this._writeNames(names);
    }

    // GNOME's list padded to one entry per workspace
    _namesFor(count) {
        const names = this._prefs.get_strv(NAMES);
        while (names.length < count)
            names.push('');
        return names;
    }

    _writeNames(names) {
        while (names.length > 0 && names.at(-1) === '')
            names.pop();
        this._prefs.set_strv(NAMES, names);
    }

    // The menu belongs to the row, beside the other menus of the top bar, but opens only from a label. The place-holder
    // GNOME gave the button leaves the top bar's menus, so that moving along the bar with a menu open finds this one.
    _buildMenu() {
        Main.panel.menuManager.removeMenu(this._row.menu);
        this._menu = new PopupMenu.PopupMenu(this._row, 0.5, St.Side.TOP);
        this._menu.actor.add_style_class_name('panel-menu');
        this._menu.actor.add_style_class_name('amethystora-workspaces-menu');
        Main.uiGroup.add_child(this._menu.actor);
        this._menu.actor.hide();
        Main.panel.menuManager.addMenu(this._menu);

        const heading = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        heading.add_child(new St.Label({
            text: _('Name of this workspace'),
            style_class: 'amethystora-workspaces-heading',
        }));
        this._menu.addMenuItem(heading);

        const field = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        this._entry = new St.Entry({style_class: 'amethystora-workspaces-entry', can_focus: true, x_expand: true});
        this._entry.clutter_text.connect('activate', () => this._menu.close());
        field.add_child(this._entry);
        this._menu.addMenuItem(field);

        // Connected after the top bar's own handler, which gives the menu the keyboard first
        this._menu.connect('open-state-changed', (menu, open) => {
            if (open) {
                this._row?.add_style_pseudo_class('active');
                const index = global.workspace_manager.get_active_workspace_index();
                const name = this._prefs.get_strv(NAMES)[index] ?? '';
                this._renaming = {index, name};
                this._entry.text = name;
                global.stage.set_key_focus(this._entry.clutter_text);
                this._entry.clutter_text.set_selection(0, -1);
            } else {
                this._row?.remove_style_pseudo_class('active');
                this._rename();
            }
        });
    }

    openMenu() {
        this._menu?.open(BoxPointer.PopupAnimation.FULL);
    }

    toggleMenu() {
        if (this._menu?.isOpen)
            this._menu.close(BoxPointer.PopupAnimation.FULL);
        else
            this.openMenu();
    }

    // However the menu closes, what the field then says is the name of the workspace it was opened on
    _rename() {
        const renaming = this._renaming;
        this._renaming = null;
        if (!renaming || !this._entry || this._entry.text === renaming.name)
            return;
        if (renaming.index >= global.workspace_manager.n_workspaces)
            return;
        const names = this._namesFor(renaming.index + 1);
        names[renaming.index] = this._entry.text;
        this._writeNames(names);
    }

    // A label taken out of the row leaves a gap the size of itself where it was, so that nothing moves until the
    // drag goes somewhere else
    dragBegan(label) {
        const span = label.width + label.margin_left + label.margin_right;
        this._drag = {label, from: label.index, to: label.index, span, gap: null};
        label.add_style_class_name('amethystora-workspaces-dragged');
        this._drag.gap = this._openGap(label, span, false);
    }

    dragCancelled() {
        if (this._drag)
            this._closeGap(this._drag);
    }

    // The label is either gone, when it was dropped on the row and its workspace moved, or back at the end of the
    // row after its way home; either way it is made again in its place
    dragEnded(label) {
        if (!this._drag || this._drag.label !== label)
            return;
        const drag = this._drag;
        this._drag = null;
        this._closeGap(drag, false);
        if (this._labels.includes(label)) {
            label.remove_style_class_name('amethystora-workspaces-dragged');
            this._dropped = label;
        }
        this._queue();
    }

    _openGap(before, span, animate) {
        const gap = new St.Widget({style_class: 'amethystora-workspaces-gap', y_expand: true});
        if (before)
            this._row.box.insert_child_below(gap, before);
        else
            this._row.box.add_child(gap);
        if (animate) {
            gap.width = 0;
            gap.ease({width: span, duration: GAP_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        } else {
            gap.width = span;
        }
        return gap;
    }

    _closeGap(drag, animate = true) {
        const gap = drag.gap;
        drag.gap = null;
        if (!gap)
            return;
        gap.remove_all_transitions();
        if (!animate) {
            gap.destroy();
            return;
        }
        gap.ease({
            width: 0,
            duration: GAP_MS,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onStopped: () => gap.destroy(),
        });
    }

    // Where the dragged label would land: before the first other label whose middle its leading edge (the left one,
    // or the right one in a right-to-left language) has not passed yet, or after the last
    _landing(dragActor) {
        const rtl = isRtl(this._row);
        const [x] = dragActor.get_transformed_position();
        const [width] = dragActor.get_transformed_size();
        const lead = rtl ? x + width : x;
        const others = this._labels.filter(label => label !== this._drag.label);
        const at = others.findIndex(label => {
            const [labelX] = label.get_transformed_position();
            const [labelWidth] = label.get_transformed_size();
            const middle = labelX + labelWidth / 2;
            return rtl ? lead > middle : lead < middle;
        });
        return at < 0 ? others.length : at;
    }

    dragOver(source, dragActor) {
        if (!this._drag || source !== this._drag.label)
            return DND.DragMotionResult.NO_DROP;
        const to = this._landing(dragActor);
        if (to !== this._drag.to) {
            this._drag.to = to;
            this._closeGap(this._drag);
            const others = this._labels.filter(label => label !== this._drag.label);
            this._drag.gap = this._openGap(others[to] ?? null, this._drag.span, true);
        }
        return DND.DragMotionResult.MOVE_DROP;
    }

    drop(source, dragActor) {
        if (!this._drag || source !== this._drag.label)
            return false;
        const {from} = this._drag;
        const to = this._landing(dragActor);
        this._move(from, to);
        return true;
    }
}
