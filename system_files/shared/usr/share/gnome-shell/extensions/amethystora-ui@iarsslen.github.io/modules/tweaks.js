// Three changes to GNOME Shell itself, the ones the image has always made: its animations take 0.6 of their time
// (half that while the power saver is on), switching workspaces shows no popup in the middle of the screen (the
// workspaces in the top bar say where you are), and the Activities button is gone from the top bar (the logo menu
// and the workspaces stand there). GNOME's own
// switch for animations is the person's, in Settings, and is never touched: with it off, every animation is already
// instant.

import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as WorkspaceSwitcherPopup from 'resource:///org/gnome/shell/ui/workspaceSwitcherPopup.js';

// The share of its usual time an animation takes, and the share of that it takes while the power saver is on (the
// comfort module watches the profile). This module is the only one that sets the factor.
const SPEED = 0.6;
const POWER_SAVER = 0.5;

export class Tweaks {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        const settings = St.Settings.get();
        this._factor = settings.slow_down_factor;
        this._unlisten = this._ext.modules.get('comfort')?.listen(() => this._speed()) ?? null;
        this._speed();

        // The popup is made hidden and only shown by display(), so it goes before it is ever drawn. Destroying it
        // is also what gives the window manager back the workspace updates it held for it.
        const popup = WorkspaceSwitcherPopup.WorkspaceSwitcherPopup.prototype;
        this._display = popup.display;
        popup.display = function () {
            this.destroy();
        };

        // The button's container rather than the button, and again whenever anything shows it
        this._activities = Main.panel.statusArea.activities?.container ?? null;
        if (this._activities) {
            this._activities.hide();
            this._activities.connectObject('notify::visible', actor => {
                if (actor.visible)
                    actor.hide();
            }, this);
        }
    }

    disable() {
        this._unlisten?.();
        this._unlisten = null;
        if (this._factor !== undefined)
            St.Settings.get().slow_down_factor = this._factor;
        this._factor = undefined;

        if (this._display)
            WorkspaceSwitcherPopup.WorkspaceSwitcherPopup.prototype.display = this._display;
        this._display = null;

        if (this._activities) {
            this._activities.disconnectObject(this);
            // The lock screen's panel has no Activities button to give back
            if (!Main.sessionMode.isLocked)
                this._activities.show();
        }
        this._activities = null;
    }

    _speed() {
        const saver = this._ext.modules.get('comfort')?.powerSaver ?? false;
        St.Settings.get().slow_down_factor = saver ? SPEED * POWER_SAVER : SPEED;
    }
}
