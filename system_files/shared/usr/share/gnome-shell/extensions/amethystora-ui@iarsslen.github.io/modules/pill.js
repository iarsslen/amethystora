// The live pill and what goes with it. The clock in the middle of the top bar becomes whatever is happening now (a
// call, a recording, a link from the phone, the battery's question, a timer, music, an update ready, quiet), and a
// click opens its card; with nothing happening it is GNOME's clock, exactly. Beside it: the privacy dots, the glow
// round the screen while it is recorded or shared, quiet (banners held while fullscreen, sharing or at night), the
// digest, the count on a stack of notifications, and volume and brightness as a pill under the top bar.
//
// Each part is a key of org.gnome.shell.extensions.amethystora-ui.pill (ame desktop pill|quiet|digest, Control), read
// live; a part that is off has nothing connected and nothing made. Nothing here polls: every source is a signal.

import GLib from 'gi://GLib';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Activities} from './pill/activities.js';
import {Battery, batteryView} from './pill/battery.js';
import {Capture, Recording} from './pill/capture.js';
import {Clock, retire} from './pill/clock.js';
import {Glow} from './pill/glow.js';
import {Hold} from './pill/hold.js';
import {Media} from './pill/media.js';
import {Osd} from './pill/osd.js';
import {Phone} from './pill/phone.js';
import {Privacy} from './pill/privacy.js';
import {Stacks} from './pill/stacks.js';
import {disposeSettings} from './pill/text.js';
import {Timer, armOffRing, disarmOffRing} from './pill/timer.js';
import {Update} from './pill/update.js';

const SCHEMA = 'org.gnome.shell.extensions.amethystora-ui.pill';
// GNOME's own recording and sharing buttons in the bar: the pill and the dots carry their Stop
const GNOME_CAPTURE_ROLES = ['screenRecording', 'screenSharing'];

// A word in the pill for a few seconds: "Timer done", "2 waiting in the list", "Opened in the browser"
class Notice {
    constructor(text, icon, plate, activate) {
        this.id = 'waiting';
        this.text = text;
        this.accessible = text;
        this.plate = plate;
        this.row = {icon, text};
        this._icon = icon;
        if (activate)
            this.activate = activate;
    }

    pill() {
        if (!this._content) {
            this._content = new St.BoxLayout({style_class: 'amethystora-pill-content amethystora-pill-notice'});
            this._content.add_child(new St.Icon({icon_name: this._icon, icon_size: 12, y_align: Clutter.ActorAlign.CENTER}));
            this._content.add_child(new St.Label({text: this.text, y_align: Clutter.ActorAlign.CENTER}));
        }
        return this._content;
    }

    card() {
        return new St.Label({style_class: 'amethystora-pill-card-label', text: this.text});
    }

    destroy() {
        retire(this._content);
        this._content = null;
    }
}

export class Pill {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        this._settings = this._ext.getSettings(SCHEMA);
        this._capture = new Capture();
        this._activities = new Activities(() => this._clock?.sync());
        this._unlistenComfort = this._comfort?.listen(() => this._comfortChanged());
        this._osd = new Osd();
        this._osd.enable();
        this._stacks = new Stacks();
        this._stacks.enable();
        this._settings.connectObject(
            'changed::live', () => this._sync(),
            'changed::privacy-dots', () => this._sync(),
            'changed::glow', () => this._sync(),
            'changed::quiet', () => this._sync(),
            'changed::quiet-night', () => this._sync(),
            'changed::digest', () => this._sync(),
            this);
        this._sync();
    }

    disable() {
        this._settings?.disconnectObject(this);
        this._stopLive();
        // Turned off whole (as while the screen is locked): nothing waits; the timer rings at the next enable if it ended
        disarmOffRing();
        this._stopPart('_privacy');
        this._stopPart('_glow');
        this._stopPart('_hold');
        this._showGnomeCapture();
        this._stacks?.disable();
        this._stacks = null;
        this._osd?.disable();
        this._osd = null;
        this._unlistenComfort?.();
        this._unlistenComfort = null;
        this._endNotice();
        this._activities?.clear();
        this._activities = null;
        this._capture?.destroy();
        this._capture = null;
        // Disposed now rather than by the collector (dock.js says why)
        this._settings?.run_dispose();
        this._settings = null;
        disposeSettings();
    }

    get _comfort() {
        return this._ext.modules?.get('comfort') ?? null;
    }

    // Reduce motion, as the comfort module says (GNOME's animations off counting too)
    _reduce() {
        const comfort = this._comfort;
        return comfort ? comfort.reduceMotion : !St.Settings.get().enable_animations;
    }

    _comfortChanged() {
        // Under reduce motion the loops stand still at once
        if (this._reduce())
            this._media?._restBars?.(this._media.playing ? null : 0.35);
    }

    _glass() {
        return this._ext.modules?.get('glass') ?? null;
    }

    // Each part as its key says
    _sync() {
        const on = key => this._settings.get_boolean(key);
        if (on('live')) {
            this._startLive();
        } else {
            this._stopLive();
            // The live pill off: a timer that runs still rings at its end
            armOffRing();
        }
        this._toggle('_privacy', on('privacy-dots'), () => new Privacy(this._capture));
        this._toggle('_glow', on('glow'), () => new Glow(this._capture, () => this._reduce()));
        this._toggle('_hold', on('quiet') || on('quiet-night') || on('digest'),
            () => new Hold(this._settings, this._capture, this._activities, (...a) => this.notice(...a), () => this._glass()));
        if (on('live') || on('privacy-dots'))
            this._hideGnomeCapture();
        else
            this._showGnomeCapture();
    }

    _toggle(name, wanted, make) {
        if (wanted && !this[name]) {
            const part = make();
            this[name] = part;
            try {
                part.enable();
            } catch (e) {
                console.error(`Amethystora UI: the pill module's ${name.slice(1)} did not start: ${e.message}\n${e.stack}`);
                this._stopPart(name);
            }
        } else if (!wanted && this[name]) {
            this._stopPart(name);
        }
    }

    _stopPart(name) {
        const part = this[name];
        this[name] = null;
        try {
            part?.disable();
        } catch (e) {
            console.error(`Amethystora UI: the pill module's ${name.slice(1)} did not stop cleanly: ${e.message}`);
        }
    }

    _startLive() {
        if (this._clock)
            return;
        const notice = (...a) => this.notice(...a);
        const reduce = () => this._reduce();
        this._clock = new Clock(this._activities, reduce);
        try {
            this._clock.enable();
        } catch (e) {
            console.error(`Amethystora UI: the pill module's clock did not start: ${e.message}\n${e.stack}`);
            this._stopLive();
            return;
        }
        this._live = [];
        const parts = [
            ['_media', () => new Media(this._activities, reduce)],
            ['_timer', () => new Timer(this._activities, notice)],
            ['_recording', () => new Recording(this._activities, notice, this._capture, reduce)],
            ['_update', () => new Update(this._activities)],
            ['_battery', () => new Battery(this._activities, notice, this._comfort, () => this._glass())],
        ];
        const connect = this._ext.modules?.get('connect');
        if (connect?.addListener)
            parts.push(['_phone', () => new Phone(this._activities, notice, connect)]);
        for (const [name, make] of parts) {
            this._toggle(name, true, make);
            if (this[name])
                this._live.push(name);
        }
        // The level meter moves while the pointer is on the pill
        Main.panel.statusArea.dateMenu?.connectObject('notify::hover', actor => this._activities.top?.hovered?.(actor.hover), this);
        this._clock.sync();
    }

    _stopLive() {
        Main.panel.statusArea.dateMenu?.disconnectObject(this);
        // The clock lets the activities' contents go first, so that each part takes its own away
        if (this._clock) {
            try {
                this._clock.disable();
            } catch (e) {
                console.error(`Amethystora UI: the pill's clock did not stop cleanly: ${e.message}`);
            }
            this._clock = null;
        }
        for (const name of [...this._live ?? []].reverse())
            this._stopPart(name);
        this._live = null;
        this._endNotice();
    }

    _hideGnomeCapture() {
        if (this._gnomeCaptureHidden)
            return;
        this._gnomeCaptureHidden = true;
        for (const role of GNOME_CAPTURE_ROLES)
            Main.panel.statusArea[role]?.container?.hide();
    }

    _showGnomeCapture() {
        if (!this._gnomeCaptureHidden)
            return;
        this._gnomeCaptureHidden = false;
        for (const role of GNOME_CAPTURE_ROLES)
            Main.panel.statusArea[role]?.container?.show();
    }

    // A word in the pill for `seconds`, in the "waiting" place; plate is '' or one of the plate's looks
    notice(text, icon, seconds, plate = '', activate = null) {
        if (!this._activities)
            return;
        this._endNotice();
        const notice = new Notice(text, icon, plate, activate ? () => {
            this._endNotice();
            activate();
        } : null);
        this._notice = notice;
        this._activities.set('waiting', notice);
        this._noticeTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, seconds, () => {
            this._noticeTimer = 0;
            this._endNotice();
            return GLib.SOURCE_REMOVE;
        });
    }

    _endNotice() {
        if (this._noticeTimer)
            GLib.source_remove(this._noticeTimer);
        this._noticeTimer = 0;
        const notice = this._notice;
        this._notice = null;
        if (notice && this._activities?.get('waiting') === notice)
            this._activities.set('waiting', null);
        notice?.destroy();
    }

    // --- For the glass, the suites and the harness ----------------------------------------------------------------

    glassSurfaces() {
        return [...this._battery?.glassSurfaces() ?? [], ...this._hold?.glassSurfaces() ?? []];
    }

    get timer() {
        return this._timer;
    }

    get privacy() {
        return this._privacy;
    }

    get capture() {
        return this._capture;
    }

    // Whether the screen is recorded or shared now, for the tips, which never show then
    sharing() {
        return !!this._capture?.active;
    }

    get hold() {
        return this._hold;
    }

    get clock() {
        return this._clock;
    }

    get phone() {
        return this._phone;
    }

    // What the battery would show for a reading (a pure function, for the suites): {offer, hover}
    batteryView(reading) {
        const {offer, hover} = batteryView(reading);
        return {offer, hover};
    }

    state() {
        const activities = this._activities;
        const top = activities?.top ?? null;
        const dateMenu = Main.panel.statusArea.dateMenu;
        return {
            activity: top?.id ?? 'idle',
            text: top ? top.text : dateMenu?._clockDisplay?.text ?? '',
            others: activities?.others.map(a => a.id) ?? [],
            card: this._clock?.cardId ?? null,
            dots: this._privacy?.state ?? {microphone: false, camera: false, screen: false, location: false, visible: false},
            glow: this._glow?.monitors ?? 0,
            quiet: {on: !!this._hold?.reason, reason: this._hold?.reason ?? null, held: this._hold?.quietHeld ?? 0},
            digest: {held: this._hold?.digestHeld ?? 0, shown: this._hold?.digestShown ?? false},
            osd: this._osd?.state ?? null,
            timer: {running: this._timer?.running ?? false, paused: this._timer?.paused ?? false, left: Math.round(this._timer?.left ?? 0)},
            paused: this._media?.paused === true,
            relayouts: this._clock?.relayouts ?? 0,
            motion: {
                morphing: this._clock?.morphing ?? false,
                bars: this._media?.barsMoving ?? false,
                pulsing: (this._recording?.pulsing ?? false) || (this._glow?.breathing ?? false),
                reduce: this._reduce(),
            },
        };
    }
}
