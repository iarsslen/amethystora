// The phone link in the shell, in place of the extension that used to carry it. The link itself, the network, the
// pairing and the files, is a program of its own that runs only while the person has turned it on (amethystora-connect,
// which owns org.amethystora.Connect on the session bus), so that a fault in it can never end the session. The shell
// has two small parts of it, which only the shell can do:
//
//  - the top bar: an icon, with the phone's battery beside it, while a paired phone is connected, and a menu to send
//    it files or a link, ping it and open its messages. The program shows a pairing request itself, as a
//    notification, so the bar adds nothing for one;
//  - the clipboard: under Wayland only the shell is told when the clipboard changes and may read it, so it passes the
//    text on to the program when the person has turned sending on, and sets it when a phone's text comes and the
//    person has turned receiving on (the settings org.amethystora.Connect, written by `ame desktop phone`).
//
// While the program is not running this module only waits for its name on the bus, and it believes only the program
// of this system (link.js). Windows, the lists of phones and everything else belong to the Phone app, which the menu
// starts.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import * as Util from 'resource:///org/gnome/shell/misc/util.js';

import {Bridge, KEY_RECEIVE, KEY_SEND, openSettings} from './connect/clipboard.js';
import {Indicator} from './connect/indicator.js';
import {Link} from './connect/link.js';

const ROLE = 'amethystora-connect';
// By its full path: the session's PATH may hold a folder of the account's own before the system's
const APP = '/usr/bin/amethystora-phone';
// The shell's own indicators at the right of the top bar. The phone stands to the left of all of them.
const SYSTEM_ROLES = ['screenRecording', 'screenSharing', 'dwellClick', 'a11y', 'keyboard', 'quickSettings'];
// The longest address sent from the clipboard, in characters
const MAX_ADDRESS = 8192;

// The clipboard's text if it is one web address and nothing else, otherwise null
function address(text) {
    const candidate = typeof text === 'string' ? text.trim() : '';
    // GLib is lenient about a space in a host name, so a line with one is refused here
    if (candidate === '' || candidate.length > MAX_ADDRESS || /[\s\p{Cc}]/u.test(candidate))
        return null;
    try {
        const uri = GLib.Uri.parse(candidate, GLib.UriFlags.NONE);
        return ['http', 'https'].includes(uri.get_scheme()) && uri.get_host() ? candidate : null;
    } catch {
        return null;
    }
}

export class Connect {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        this._bolt = Gio.FileIcon.new(this._ext.dir.get_child('icons').get_child('connect')
            .get_child('charging-symbolic.svg'));
        this._actions = {
            sendFiles: device => this._appFor(device, ['send', '--device', device.id]),
            sendLink: device => this._sendLink(device),
            ping: device => this._ping(device),
            messages: device => this._appFor(device, ['messages', device.id]),
            phones: () => this._app([]),
        };
        this._bridge = new Bridge(text => this._link?.pushClipboard(text));
        this._trusted = false;
        this._settings = openSettings();
        this._settings?.connectObject(`changed::${KEY_SEND}`, () => this._switchesChanged(),
            `changed::${KEY_RECEIVE}`, () => this._switchesChanged(), this);
        this._link = new Link({
            devices: () => this._devicesChanged(),
            trust: trusted => {
                this._trusted = trusted;
                this._switchesChanged();
            },
            received: text => this._bridge?.receive(text),
        });
        this._link.start();
    }

    disable() {
        this._settings?.disconnectObject(this);
        this._settings = null;
        // The link says, as it stops, that there are no phones and nothing to trust, which takes the rest down
        this._link?.stop();
        this._link = null;
        this._bridge?.stop();
        this._bridge = null;
        this._indicator?.destroy();
        this._indicator = null;
        this._source?.destroy();
        this._source = null;
        this._actions = null;
        this._bolt = null;
    }

    // The clipboard is shared only while the program is the image's own and the person has said so
    _switchesChanged() {
        const on = key => this._trusted && this._settings?.get_boolean(key) === true;
        this._bridge?.setSwitches(on(KEY_SEND), on(KEY_RECEIVE));
    }

    // The phones that are paired and connected, by name
    _ready() {
        return this._link.devices.filter(device => device.ready)
            .sort((a, b) => a.name.localeCompare(b.name) || a.path.localeCompare(b.path));
    }

    _devicesChanged() {
        if (!this._link)
            return;
        const ready = this._ready();
        if (ready.length === 0) {
            this._indicator?.destroy();
            return;
        }
        if (!this._indicator) {
            // One left by a module that did not stop cleanly
            Main.panel.statusArea[ROLE]?.destroy();
            this._indicator = new Indicator(this._actions, this._bolt);
            this._indicator.connect('destroy', actor => {
                if (this._indicator === actor)
                    this._indicator = null;
            });
            Main.panel.addToStatusArea(ROLE, this._indicator, this._position(), 'right');
        }
        this._indicator.update(ready);
    }

    // Left of the shell's own indicators, which are the last of the right side of the bar
    _position() {
        const containers = SYSTEM_ROLES.map(role => Main.panel.statusArea[role]?.container)
            .filter(container => container?.get_parent());
        if (containers.length === 0)
            return 0;
        const siblings = containers[0].get_parent().get_children();
        return Math.min(...containers.map(container => siblings.indexOf(container)));
    }

    // The app, started as the person's own program with the arguments it takes
    _app(args) {
        Util.spawn([APP, ...args]);
    }

    // The app for one phone, only when the phone's id is safe to pass on its command line
    _appFor(device, args) {
        if (device.launchable)
            this._app(args);
    }

    _ping(device) {
        device.ping().catch(e => this._failed(device, e));
    }

    // The address in the clipboard, if it is one. The clipboard is read here, for this request only. Without an
    // address the app's own dialog opens, where one can be typed.
    _sendLink(device) {
        St.Clipboard.get_default().get_text(St.ClipboardType.CLIPBOARD, (clipboard, text) => {
            if (!this._link)
                return;
            const url = address(text);
            if (url)
                device.sendUrl(url).catch(e => this._failed(device, e));
            else
                this._appFor(device, ['send', '--device', device.id]);
        });
    }

    _failed(device, error) {
        console.debug(`Amethystora UI: the phone link refused a request: ${Gio.DBusError.strip_remote_error(error)}`);
        this._say(_('Could not reach the phone'), device.name);
    }

    // Said by the phone link, in passing: it does not stay in the list
    _say(title, body) {
        if (!this._source) {
            this._source = new MessageTray.Source({title: _('Phones'), iconName: 'smartphone-symbolic'});
            this._source.connect('destroy', () => (this._source = null));
            Main.messageTray.add(this._source);
        }
        this._source.addNotification(new MessageTray.Notification({
            source: this._source,
            title,
            body,
            isTransient: true,
        }));
    }
}
