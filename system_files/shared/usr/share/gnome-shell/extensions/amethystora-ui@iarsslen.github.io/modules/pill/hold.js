// Holding banners: quiet (while a window is fullscreen on the main screen, while the screen is recorded or shared,
// and, when chosen, between Night Light's times) and the digest. A held notification still arrives: it is in the
// list, it counts on the clock's dot and on the app's dock badge, but it does not pop up and makes no sound. Urgent
// ones, GNOME's own feedback and GNOME Clocks' alarms and timers always pass. When quiet ends, the held ones stay in the
// list and the pill says how many are waiting, rather than showing them one after another; with the digest on, they
// wait for the next digest instead.
//
// Everything is held in memory: GNOME's Do Not Disturb setting is never written, so a crash, a lock or turning this
// off leaves notifications exactly as the person set them.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import {gettext as _, ngettext} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';

import {buttonRow, cardButton, retire} from './clock.js';
import {DigestCard} from './digest.js';
import {timeOfDay} from './text.js';

const COLOR_SCHEMA = 'org.gnome.settings-daemon.plugins.color';
const CLOCKS = ['org.gnome.clocks', 'org.gnome.clocks.desktop'];
const TIME = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const MOST_TIMES = 6;
// How long "N waiting in the list" stays in the pill (s)
const WAITING = 4;

// gnome-settings-daemon's colour plugin knows when the sun rises and sets where the person is; GNOME's own interface
// file for it leaves the two properties out
const ColorIface = `
<node>
  <interface name="org.gnome.SettingsDaemon.Color">
    <property name="Sunrise" type="d" access="read"/>
    <property name="Sunset" type="d" access="read"/>
  </interface>
</node>`;
let ColorProxy = null;

// Whether a notification comes through whatever holds banners
export function passes(notification) {
    if (notification.urgency === MessageTray.Urgency.CRITICAL || notification.forFeedback)
        return true;
    const source = notification.source;
    return CLOCKS.includes(source?._appId) || CLOCKS.includes(source?.app?.get_id?.());
}

// Whether GNOME would show it as a banner at all (its own tests)
function wouldPopUp(notification) {
    if (notification.acknowledged || notification.urgency === MessageTray.Urgency.LOW)
        return false;
    return notification.source?.policy?.showBanners !== false || notification.urgency === MessageTray.Urgency.CRITICAL;
}

// The digest's times as the key gives them: HH:MM, at most six, sorted, each once
export function digestTimes(list) {
    return [...new Set((list ?? []).filter(t => TIME.test(t)))].sort().slice(0, MOST_TIMES);
}

// Whether `hour` (decimal) falls between `from` and `to`, a span that may pass midnight
function between(hour, from, to) {
    if (from === to)
        return false;
    return from < to ? hour >= from && hour < to : hour >= from || hour < to;
}

export class Hold {
    constructor(settings, capture, activities, notice, glass) {
        this._settings = settings;
        this._capture = capture;
        this._activities = activities;
        this._notice = notice;
        this._glass = glass;
        this.id = 'quiet';
        this.plate = 'quiet';
    }

    enable() {
        this._quietHeld = new Set();
        this._digestHeld = new Set();
        this._reason = null;
        this._digestDue = false;
        this._held = new Map();

        // GNOME shows a banner by this one method, by its name: holding is a wrap of it, which lets through only
        // what passes
        const proto = MessageTray.MessageTray.prototype;
        this._original = proto._showNotification;
        const hold = this;
        const original = this._original;
        proto._showNotification = function (...args) {
            if (!hold._holding())
                return original.apply(this, args);
            const queue = this._notificationQueue;
            const index = Array.isArray(queue) ? queue.findIndex(n => passes(n)) : 0;
            if (index < 0)
                return undefined;
            if (index > 0)
                queue.unshift(...queue.splice(index, 1));
            return original.apply(this, args);
        };

        this._settings.connectObject(
            'changed::quiet', () => this._configure(),
            'changed::quiet-night', () => this._configure(),
            'changed::digest', () => this._configure(),
            'changed::digest-times', () => this._configure(),
            this);
        this._configure();
    }

    disable() {
        this._settings.disconnectObject(this);
        if (this._original)
            MessageTray.MessageTray.prototype._showNotification = this._original;
        this._original = null;
        this._unwatchQuiet();
        this._unwatchClock();
        this._unwatchNight();
        this._unwatchBanners();
        // What was held stays in the list, unseen; nothing is shown in a burst
        this._takeOffQueue([...this._quietHeld ?? [], ...this._digestHeld ?? []]);
        for (const notification of this._held?.keys() ?? [])
            notification.disconnectObject(this);
        this._held?.clear();
        this._quietHeld?.clear();
        this._digestHeld?.clear();
        this._closeDigest();
        this._end();
    }

    // --- What is on -----------------------------------------------------------------------------------------------

    get _quiet() {
        return this._settings.get_boolean('quiet');
    }

    get _night() {
        return this._settings.get_boolean('quiet-night');
    }

    get _digest() {
        return this._settings.get_boolean('digest');
    }

    get times() {
        return digestTimes(this._settings.get_strv('digest-times'));
    }

    _configure() {
        if (this._quiet) {
            if (!this._quietWatched) {
                this._quietWatched = true;
                global.display.connectObject('in-fullscreen-changed', () => this._update(), this);
                this._unlistenCapture = this._capture.listen(() => this._update());
            }
        } else {
            this._unwatchQuiet();
        }
        if (this._night)
            this._watchNight();
        else
            this._unwatchNight();
        if (this._night || this._digest)
            this._watchClock();
        else
            this._unwatchClock();
        if (!this._digest && this._digestHeld.size > 0) {
            // The digest turned off: what it held waits in the list, and is not followed any more
            for (const notification of [...this._digestHeld]) {
                this._digestHeld.delete(notification);
                if (!this._quietHeld.has(notification))
                    this._forget(notification);
            }
        }
        this._update();
    }

    _unwatchQuiet() {
        if (!this._quietWatched)
            return;
        this._quietWatched = false;
        global.display.disconnectObject(this);
        this._unlistenCapture?.();
        this._unlistenCapture = null;
    }

    // One clock of the module's own, once a minute, only while quiet at night or the digest is on
    // Once a minute, at the turn of the minute, only while quiet at night or the digest is on. (GNOME's own wall clock
    // would tick every second while the person shows seconds in the top bar.)
    _watchClock() {
        if (this._clock)
            return;
        const next = () => {
            const now = GLib.DateTime.new_now_local();
            const ms = Math.max(1, (60 - now.get_second()) * 1000 - Math.floor(now.get_microsecond() / 1000));
            this._clock = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms + 50, () => {
                this._clock = 0;
                next();
                this._minute();
                return GLib.SOURCE_REMOVE;
            });
        };
        next();
    }

    _unwatchClock() {
        if (this._clock)
            GLib.source_remove(this._clock);
        this._clock = 0;
    }

    _watchNight() {
        if (this._color)
            return;
        this._color = new Gio.Settings({schema_id: COLOR_SCHEMA});
        this._color.connectObject(
            'changed::night-light-schedule-automatic', () => this._update(),
            'changed::night-light-schedule-from', () => this._update(),
            'changed::night-light-schedule-to', () => this._update(),
            this);
        ColorProxy ??= Gio.DBusProxy.makeProxyWrapper(ColorIface);
        this._colorCancellable = new Gio.Cancellable();
        new ColorProxy(Gio.DBus.session, 'org.gnome.SettingsDaemon.Color', '/org/gnome/SettingsDaemon/Color',
            (proxy, error) => {
                if (error || !this._color)
                    return;
                this._sun = proxy;
                proxy.connectObject('g-properties-changed', () => this._update(), this);
                this._update();
            }, this._colorCancellable, Gio.DBusProxyFlags.DO_NOT_AUTO_START);
    }

    _unwatchNight() {
        this._colorCancellable?.cancel();
        this._colorCancellable = null;
        this._sun?.disconnectObject(this);
        this._sun = null;
        this._color?.disconnectObject(this);
        this._color = null;
    }

    // Night Light's span, in decimal hours: the sun's times when it follows them and knows them, else the person's
    nightSpan() {
        const color = this._color;
        if (!color)
            return null;
        if (color.get_boolean('night-light-schedule-automatic')) {
            const sunset = this._sun?.Sunset;
            const sunrise = this._sun?.Sunrise;
            if (sunset > 0 && sunrise > 0)
                return {from: sunset, to: sunrise};
        }
        return {from: color.get_double('night-light-schedule-from'), to: color.get_double('night-light-schedule-to')};
    }

    _minute() {
        this._update();
        if (!this._digest)
            return;
        const now = GLib.DateTime.new_now_local().format('%H:%M');
        if (this.times.includes(now) && this._digestHeld.size > 0) {
            if (this._reason)
                this._digestDue = true;
            else
                this._showDigest(now);
        }
    }

    // --- Quiet ----------------------------------------------------------------------------------------------------

    _currentReason() {
        if (this._quiet) {
            if (this._capture.recording)
                return 'recording';
            if (this._capture.sharing)
                return 'sharing';
            if (Main.layoutManager.primaryMonitor?.inFullscreen)
                return 'fullscreen';
        }
        if (this._night) {
            const span = this.nightSpan();
            const now = GLib.DateTime.new_now_local();
            if (span && between(now.get_hour() + now.get_minute() / 60, span.from, span.to))
                return 'night';
        }
        return null;
    }

    get reason() {
        return this._reason;
    }

    _holding() {
        return this._reason !== null || this._digest;
    }

    _update() {
        if (!this._quietHeld)
            return;
        const before = this._reason;
        this._reason = this._currentReason();
        if (this._holding())
            this._watchBanners();
        else
            this._unwatchBanners();
        if (before !== null && this._reason === null)
            this._released();
        this._show();
    }

    // Quiet ended: the held ones stay in the list, and the pill says so once; with the digest on they wait for it
    _released() {
        const held = [...this._quietHeld];
        this._quietHeld.clear();
        this._takeOffQueue(held);
        if (this._digest) {
            if (this._digestDue) {
                this._digestDue = false;
                this._showDigest(GLib.DateTime.new_now_local().format('%H:%M'));
            }
            return;
        }
        const waiting = held.filter(n => this._held.has(n));
        for (const notification of waiting)
            this._forget(notification);
        if (waiting.length > 0) {
            this._notice(ngettext('%d waiting in the list', '%d waiting in the list', waiting.length).format(waiting.length),
                'weather-clear-night-symbolic', WAITING, '', () => Main.panel.statusArea.dateMenu?.menu.open());
        }
    }

    // --- Banners --------------------------------------------------------------------------------------------------

    _watchBanners() {
        if (this._bannersWatched)
            return;
        this._bannersWatched = true;
        Main.messageTray.connectObject('source-added', (tray, source) => this._watchSource(source), this);
        for (const source of Main.messageTray.getSources())
            this._watchSource(source);
    }

    _watchSource(source) {
        source.connectObject('notification-request-banner', (s, notification) => this._requested(notification), this);
    }

    _unwatchBanners() {
        if (!this._bannersWatched)
            return;
        this._bannersWatched = false;
        Main.messageTray.disconnectObject(this);
        for (const source of Main.messageTray.getSources())
            source.disconnectObject(this);
    }

    // GNOME has just queued (or, its queue being full, dropped) a banner: one that does not pass is taken off the
    // queue and counted
    _requested(notification) {
        // The banner on screen being updated is not held: it is shown already
        if (!this._holding() || passes(notification) || !wouldPopUp(notification) ||
            Main.messageTray._notification === notification)
            return;
        this._takeOffQueue([notification]);
        if (!this._held.has(notification)) {
            this._held.set(notification, true);
            notification.connectObject('destroy', () => this._forget(notification), this);
        }
        if (this._reason)
            this._quietHeld.add(notification);
        if (this._digest)
            this._digestHeld.add(notification);
        this._show();
    }

    _forget(notification) {
        notification.disconnectObject(this);
        this._held.delete(notification);
        this._quietHeld.delete(notification);
        this._digestHeld.delete(notification);
        this._show();
    }

    _takeOffQueue(notifications) {
        const tray = Main.messageTray;
        const queue = tray?._notificationQueue;
        if (!Array.isArray(queue) || notifications.length === 0)
            return;
        const kept = queue.filter(n => !notifications.includes(n));
        if (kept.length === queue.length)
            return;
        tray._notificationQueue = kept;
        tray.emit('queue-changed');
    }

    get quietHeld() {
        return this._quietHeld?.size ?? 0;
    }

    get digestHeld() {
        return this._digestHeld?.size ?? 0;
    }

    // --- Quiet in the pill ----------------------------------------------------------------------------------------

    _whyText() {
        switch (this._reason) {
        case 'fullscreen':
            return _('Quiet while fullscreen');
        case 'sharing':
        case 'recording':
            return _('Quiet while sharing');
        case 'night': {
            const span = this.nightSpan();
            const hours = Math.floor(span.to);
            const minutes = Math.round((span.to - hours) * 60) % 60;
            const date = new Date();
            date.setHours(hours, minutes, 0, 0);
            return _('Quiet until %s').format(timeOfDay(date));
        }
        default:
            return '';
        }
    }

    get text() {
        const held = this.quietHeld;
        return held > 0 ? ngettext('%s · %d held', '%s · %d held', held).format(this._whyText(), held) : this._whyText();
    }

    get accessible() {
        const held = this.quietHeld;
        return held > 0
            ? ngettext('%s, %d notification held', '%s, %d notifications held', held).format(this._whyText(), held)
            : this._whyText();
    }

    get row() {
        return {icon: 'weather-clear-night-symbolic', text: this.text};
    }

    _show() {
        if (!this._reason) {
            this._end();
            return;
        }
        this.pill();
        this._label.text = this.text;
        this._activities.set('quiet', this);
        this._activities.update('quiet');
    }

    _end() {
        if (this._activities.get('quiet') === this)
            this._activities.set('quiet', null);
        retire(this._content);
        this._content = null;
    }

    pill() {
        if (!this._content) {
            this._content = new St.BoxLayout({style_class: 'amethystora-pill-content amethystora-pill-quiet'});
            this._content.add_child(new St.Icon({icon_name: 'weather-clear-night-symbolic', icon_size: 12, y_align: Clutter.ActorAlign.CENTER}));
            this._label = new St.Label({y_align: Clutter.ActorAlign.CENTER});
            this._content.add_child(this._label);
        }
        return this._content;
    }

    card(api) {
        const body = new St.BoxLayout({style_class: 'amethystora-pill-card-body', orientation: Clutter.Orientation.VERTICAL});
        body.add_child(new St.Label({style_class: 'amethystora-pill-card-label', text: _('Notifications are waiting')}));
        const why = {
            fullscreen: _('a window is fullscreen'),
            sharing: _('the screen is shared'),
            recording: _('the screen is recorded'),
            night: _('it is night'),
        }[this._reason] ?? '';
        const held = this.quietHeld;
        const text = new St.Label({
            style_class: 'amethystora-pill-card-text',
            text: `${held > 0
                ? ngettext('%d held while %s.', '%d held while %s.', held).format(held, why)
                : _('Banners wait while %s.').format(why)} ${_('Calls, alarms and urgent ones still come through.')}`,
        });
        text.clutter_text.line_wrap = true;
        body.add_child(text);
        body.add_child(buttonRow([cardButton(_('Show them'), () => {
            api.close();
            Main.panel.statusArea.dateMenu?.menu.open();
        }, {primary: true})]));
        return body;
    }

    // --- The digest -----------------------------------------------------------------------------------------------

    _showDigest(time) {
        const held = [...this._digestHeld].filter(n => this._held.has(n));
        this._digestHeld.clear();
        for (const notification of held)
            this._forget(notification);
        if (held.length === 0)
            return;
        this._closeDigest();
        this._digestCard = new DigestCard(held, time, () => this._closeDigest());
        this._glass?.()?.surfacesChanged?.();
    }

    // For the suites and the harness: the digest now, of what is held
    showDigestNow() {
        this._showDigest(GLib.DateTime.new_now_local().format('%H:%M'));
    }

    _closeDigest() {
        const card = this._digestCard;
        this._digestCard = null;
        card?.close();
        if (card)
            this._glass?.()?.surfacesChanged?.();
    }

    get digestShown() {
        return !!this._digestCard;
    }

    get digestCard() {
        return this._digestCard ?? null;
    }

    glassSurfaces() {
        return this._digestCard?.actor ? [{actor: this._digestCard.actor, material: 'glass', radius: 22}] : [];
    }
}
