// The tiling in the top bar: two small icons, one for how the workspace on the main screen scrolls to a window and
// one for where new windows open, each changed by a click and explained on hover; and the top bar hidden on the
// workspaces where the person hid it (Super+Ctrl+B), which then give its height to their windows.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

import {Mode} from './layout.js';
import {Open} from './engine.js';
import {label as keyLabel} from './keys.js';

const MODE_ICONS = {
    [Mode.PLAIN]: 'sidebar-show-right-symbolic',
    [Mode.CENTRE]: 'preferences-desktop-multitasking-symbolic',
    [Mode.EDGE]: 'zoom-fit-best-symbolic',
};
const MODE_COLOURS = {[Mode.PLAIN]: '#6be67b', [Mode.CENTRE]: '#6be6cb', [Mode.EDGE]: '#abe67b'};
const OPEN_ICONS = {
    [Open.RIGHT]: 'go-next-symbolic',
    [Open.LEFT]: 'go-previous-symbolic',
    [Open.DOWN]: 'go-down-symbolic',
};

const Icon = GObject.registerClass(
class Icon extends PanelMenu.Button {
    _init(name, styleClass, onClick, describe) {
        super._init(0.5, name, true);
        this.add_style_class_name(styleClass);
        this._icon = new St.Icon({style_class: 'system-status-icon'});
        this.add_child(this._icon);
        this._describe = describe;
        const click = new Clutter.ClickGesture({recognize_on_press: true});
        click.connect('recognize', () => {
            if (!Main.overview.visible)
                onClick();
        });
        this.add_action(click);
        this.connect('notify::hover', () => this._tooltip());
        this.connect('destroy', () => this._tip?.destroy());
    }

    set iconName(name) {
        this._icon.icon_name = name;
        if (this._tip?.visible)
            this._fillTip();
    }

    _tooltip() {
        if (!this.hover) {
            this._tip?.hide();
            return;
        }
        if (!this._tip) {
            this._tip = new St.Label({style_class: 'amethystora-tiling-tooltip'});
            this._tip.clutter_text.use_markup = true;
            Main.uiGroup.add_child(this._tip);
        }
        this._fillTip();
        this._tip.show();
        const [x, y] = this.get_transformed_position();
        const [width, height] = this.get_transformed_size();
        const [, tipWidth] = this._tip.get_preferred_width(-1);
        const monitor = Main.layoutManager.findMonitorForActor(this);
        const left = Math.max(monitor.x + 4, Math.round(x + width / 2 - tipWidth / 2));
        this._tip.set_position(Math.min(left, monitor.x + monitor.width - tipWidth - 4), Math.round(y + height + 4));
    }

    _fillTip() {
        this._tip.clutter_text.set_markup(this._describe());
    }
});

export class TopBar {
    constructor(tiling) {
        this._tiling = tiling;
    }

    enable() {
        this._mode = new Icon(_('Focus mode'), 'amethystora-tiling-mode',
            () => this._tiling.actions.cycleFocusMode(), () => this._describeMode());
        this._open = new Icon(_('Where new windows open'), 'amethystora-tiling-open',
            () => this._tiling.actions.cycleOpenPosition(), () => this._describeOpen());
        Main.panel.addToStatusArea('amethystora-tiling-mode', this._mode, 2, 'left');
        Main.panel.addToStatusArea('amethystora-tiling-open', this._open, 3, 'left');
        global.workspace_manager.connectObject('active-workspace-changed', () => {
            this.sync();
            this._applyTopBar();
        }, this);

        // GNOME hides the top bar (and whatever else gives way to fullscreen windows) while a fullscreen window is
        // on the screen; a fullscreen window the strip has scrolled away is not, and the bar comes back. The top
        // bar also stays hidden on the workspaces where the person hid it.
        const layout = Main.layoutManager;
        const original = layout._updateActorVisibility;
        if (typeof original === 'function') {
            this._ownVisibility = Object.prototype.hasOwnProperty.call(layout, '_updateActorVisibility')
                ? original : null;
            const self = this;
            layout._updateActorVisibility = function (actorData) {
                original.call(this, actorData);
                if (!global.window_group.visible)
                    return;
                const monitor = actorData.trackFullscreen ? this.findMonitorForActor(actorData.actor) : null;
                if (monitor?.inFullscreen && !self._tiling.engine?.coversMonitor(monitor.index))
                    actorData.actor.visible = true;
                if (actorData.actor === this.panelBox && self.hidden())
                    actorData.actor.visible = false;
            };
            this._patched = true;
        }
        this.sync();
        this._applyTopBar();
    }

    disable() {
        global.workspace_manager.disconnectObject(this);
        if (this._patched) {
            if (this._ownVisibility)
                Main.layoutManager._updateActorVisibility = this._ownVisibility;
            else
                delete Main.layoutManager._updateActorVisibility;
            this._patched = false;
        }
        this._applyTopBar(false);
        this._mode?.destroy();
        this._open?.destroy();
        this._mode = null;
        this._open = null;
    }

    _primaryStrip() {
        return this._tiling.engine.activeStrip(Main.layoutManager.primaryIndex);
    }

    sync() {
        if (!this._mode)
            return;
        this._mode.iconName = MODE_ICONS[this._primaryStrip().mode];
        this._open.iconName = OPEN_ICONS[this._tiling.openPosition] ?? OPEN_ICONS[Open.RIGHT];
    }

    _key(name) {
        return GLib.markup_escape_text(keyLabel(this._tiling.keys.first(name)), -1);
    }

    _describeMode() {
        const mode = this._primaryStrip().mode;
        const name = {
            [Mode.PLAIN]: _('Keep in view'),
            [Mode.CENTRE]: _('Centre the focused window'),
            [Mode.EDGE]: _('Push to the nearest edge'),
        }[mode];
        const heading = GLib.markup_escape_text(_('How this workspace scrolls to a window'), -1);
        const current = `<span foreground="${MODE_COLOURS[mode]}">${GLib.markup_escape_text(name, -1)}</span>`;
        const key = this._key('switch-focus-mode');
        return key ? `${heading}\n${current}\n<i>${key}</i>` : `${heading}\n${current}`;
    }

    _describeOpen() {
        const name = {
            [Open.RIGHT]: _('To the right'),
            [Open.LEFT]: _('To the left'),
            [Open.DOWN]: _('Below'),
        }[this._tiling.openPosition] ?? _('To the right');
        const heading = GLib.markup_escape_text(_('Where new windows open'), -1);
        const key = this._key('switch-open-window-position');
        const current = `<b>${GLib.markup_escape_text(name, -1)}</b>`;
        return key ? `${heading}\n${current}\n<i>${key}</i>` : `${heading}\n${current}`;
    }

    // ---- The top bar per workspace ----

    hidden() {
        return this.hiddenOn(global.workspace_manager.get_active_workspace());
    }

    hiddenOn(workspace) {
        return (this._tiling.state?.get('hiddenTopBar') ?? []).includes(workspace.index());
    }

    toggle() {
        const index = global.workspace_manager.get_active_workspace_index();
        const list = new Set(this._tiling.state.get('hiddenTopBar') ?? []);
        if (list.has(index))
            list.delete(index);
        else
            list.add(index);
        this._tiling.state.set('hiddenTopBar', [...list].sort((a, b) => a - b));
        this._applyTopBar();
    }

    // The bar hidden takes its space on the screen with it, so that the windows can have it
    _applyTopBar(hidden = this.hidden()) {
        const layout = Main.layoutManager;
        const data = layout._trackedActors?.find(a => a.actor === layout.panelBox);
        if (data && data.affectsStruts === hidden) {
            data.affectsStruts = !hidden;
            layout._queueUpdateRegions();
        }
        layout._updateVisibility();
    }
}
