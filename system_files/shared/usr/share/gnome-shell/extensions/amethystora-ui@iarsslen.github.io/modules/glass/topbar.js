// The top bar, as the desktop style makes it (modules/style.js). Where the bar is one pane (floating, neon) it is a
// clear strip of frosted wallpaper with the bar's corners, darkened a little so that its white text reads on a pale
// one, until a window on the bar's screen and workspace reaches up to within 5 pixels of it; then it fades to the
// bar's own background over half a second, and back once no window does. Where the bar is a row of islands, each
// button is a pane of its own. A solid bar, and one that is only its buttons, have no glass. In the overview it is
// clear, and the panes are gone from the moment the overview starts to open until it has closed. With the tiling's
// gap of 8 pixels under the bar, tiled windows leave it clear.

import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {TYPES, leftAlone} from './windows.js';

// How close a window's top may come to the bar's bottom before the bar takes its background back, in pixels
const NEAR = 5;
const CLEAR = 'amethystora-glass-clear';

export class TopBar {
    constructor(glass) {
        this._glass = glass;
    }

    enable() {
        this._laterId = 0;
        this._effect = null;
        this._pills = new Map();
        this._inOverview = Main.overview.visible;
        Main.overview.connectObject(
            'showing', () => {
                this._inOverview = true;
                this._sync();
            },
            'hidden', () => {
                this._inOverview = false;
                this._sync();
            }, this);
        Main.sessionMode.connectObject('updated', () => this._queue(), this);
        this._glass.windows.onChange(() => this._queue());
        this.restyle();
    }

    disable() {
        Main.overview.disconnectObject(this);
        Main.sessionMode.disconnectObject(this);
        if (this._laterId)
            global.compositor.get_laters().remove(this._laterId);
        this._laterId = 0;
        Main.panel.remove_style_class_name(CLEAR);
        this._glass.detach(Main.panel);
        this._effect = null;
        for (const button of this._pills.keys())
            this._glass.detach(button);
        this._pills = null;
    }

    // The panes the style wants: one behind the bar, one behind each button, or none
    restyle() {
        if (!this._pills)
            return;
        const style = this._glass.style;
        const bar = style?.look.bar ?? 'pane';
        if (bar === 'pane') {
            this._effect = this._glass.attach(Main.panel, {material: 'menu-bar', radius: null, inClones: true},
                {classes: ['amethystora-glass-bar']});
        } else if (this._effect) {
            this._glass.detach(Main.panel);
            this._effect = null;
        }
        const wanted = new Set(bar === 'pills' && style ? style.buttons : []);
        for (const button of [...this._pills.keys()]) {
            if (!wanted.has(button)) {
                this._glass.detach(button);
                this._pills.delete(button);
            }
        }
        for (const button of wanted) {
            if (!this._pills.has(button)) {
                this._pills.set(button, this._glass.attach(button,
                    {material: 'menu-bar', radius: null, inClones: true},
                    {classes: ['amethystora-glass-pill']}));
            }
        }
        this._sync();
    }

    // Windows move every frame while they are dragged: the bar looks once per frame at most
    _queue() {
        if (this._laterId)
            return;
        this._laterId = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._laterId = 0;
            this._sync();
            return false;
        });
    }

    _sync() {
        if (this._effect)
            this._effect.enabled = !this._inOverview;
        for (const effect of this._pills?.values() ?? [])
            effect.enabled = !this._inOverview;
        if (this._inOverview || !Main.sessionMode.hasWindows || !this._touched())
            Main.panel.add_style_class_name(CLEAR);
        else
            Main.panel.remove_style_class_name(CLEAR);
    }

    _touched() {
        const panel = Main.panel;
        if (!panel.mapped)
            return false;
        const [, top] = panel.get_transformed_position();
        const limit = top + panel.height + NEAR * St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const monitor = Main.layoutManager.primaryIndex;
        const active = global.workspace_manager.get_active_workspace();
        // With the tiling on several screens the bar's screen may show a workspace GNOME does not have, whose windows
        // are drawn as pictures (tiling/screens.js) while their own actors are hidden
        const engine = this._glass._ext.modules.get('tiling')?.engine;
        const workspace = engine?.screens?.shownOn(monitor) ?? active;
        for (const window of this._glass.windows.windows) {
            if (!TYPES.has(window.get_window_type()) || window.is_override_redirect() || window.minimized ||
                !window.located_on_workspace(workspace) || window.get_monitor() !== monitor ||
                (window.get_wm_class() && leftAlone(window)))
                continue;
            // A picture leaves out what the tiling hides (a window scrolled off the strip), as the window's own actor
            // would be
            const seen = workspace === active ? window.get_compositor_private()?.visible : !engine?.info(window)?.hidden;
            if (!seen || !window.showing_on_its_workspace())
                continue;
            if (window.get_frame_rect().y < limit)
                return true;
        }
        return false;
    }
}
