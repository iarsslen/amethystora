// The small card at the bottom right of the screen after a capture, in place of GNOME's notification: the picture
// opens in its app, in Files or in Gradia from it, and it goes by itself after three seconds unless the pointer rests
// on it. Like everything else of the desktop, it is not drawn over a full-screen window.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import Shell from 'gi://Shell';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {GRADIA, contentOf, gradiaInstalled} from './capture.js';

const WIDTH = 250;
const MIN_HEIGHT = 150;
const MAX_HEIGHT = 250;
// From the screen's right and bottom edges, and the room the close button takes over the card's corner
const EDGE = 18;
const ROOM = 16;
const BUTTON = 32;
const INSET = 10;
const BORDER = 3.5;
const LINGER = 3000;
const SLIDE = 150;

export class Card {
    // A capture's picture, the file it was saved to (or null), and whether it only went to the clipboard
    constructor(picture, file, copied) {
        this._file = file;
        // Mirrored at the bottom left in a right-to-left language
        this._rtl = Clutter.get_default_text_direction() === Clutter.TextDirection.RTL;
        const height = Math.round(Math.clamp(WIDTH * picture.height / Math.max(1, picture.width),
            MIN_HEIGHT, MAX_HEIGHT));

        this.actor = new St.Widget({
            style_class: 'amethystora-screenshot-card-box',
            width: WIDTH + ROOM,
            height: height + ROOM,
            reactive: true,
            track_hover: true,
            opacity: 0,
        });

        const frame = new St.Widget({
            style_class: 'amethystora-screenshot-card',
            x: this._x(0, WIDTH),
            y: ROOM,
            width: WIDTH,
            height,
            layout_manager: new Clutter.BinLayout(),
        });
        this.actor.add_child(frame);

        // Scaled to cover the card, centred, the rest cut off
        const [paneWidth, paneHeight] = [WIDTH - 2 * BORDER, height - 2 * BORDER];
        const picturePane = new St.Widget({
            clip_to_allocation: true,
            x_expand: true,
            y_expand: true,
            reactive: true,
            accessible_name: _('Open the screenshot'),
        });
        const cover = Math.max(paneWidth / Math.max(1, picture.width), paneHeight / Math.max(1, picture.height));
        const image = new Clutter.Actor({
            content: contentOf(picture),
            width: picture.width * cover,
            height: picture.height * cover,
            x: (paneWidth - picture.width * cover) / 2,
            y: (paneHeight - picture.height * cover) / 2,
        });
        image.set_content_scaling_filters(Clutter.ScalingFilter.TRILINEAR, Clutter.ScalingFilter.LINEAR);
        picturePane.add_child(image);
        const click = new Clutter.ClickGesture();
        click.connect('recognize', () => this._act(() => this._openDefault()));
        picturePane.add_action(click);
        frame.add_child(picturePane);

        if (copied) {
            const badge = new St.BoxLayout({
                style_class: 'amethystora-screenshot-badge',
                x_align: Clutter.ActorAlign.CENTER,
                y_align: Clutter.ActorAlign.CENTER,
            });
            badge.add_child(new St.Icon({icon_name: 'object-select-symbolic', icon_size: 16}));
            badge.add_child(new St.Label({text: _('Copied'), y_align: Clutter.ActorAlign.CENTER}));
            frame.add_child(badge);
        }

        this._button('window-close-symbolic', _('Close'), WIDTH - BUTTON / 2, ROOM - BUTTON / 2, () => {});
        if (file) {
            if (gradiaInstalled()) {
                this._button('document-edit-symbolic', _('Edit in Gradia'), INSET, ROOM + height - INSET - BUTTON,
                    () => this._openInGradia());
            }
            this._button('folder-open-symbolic', _('Show in Files'), WIDTH - INSET - BUTTON,
                ROOM + height - INSET - BUTTON, () => this._showInFiles());
        }

        this.actor.connect('notify::hover', () => {
            if (this.actor.hover)
                this._stopTimer();
            else
                this._startTimer();
        });
        this.actor.connect('destroy', () => this._stopTimer());

        const monitor = Main.layoutManager.primaryMonitor;
        this.actor.set_position(this._rtl ? monitor.x + EDGE : monitor.x + monitor.width - EDGE - WIDTH - ROOM,
            monitor.y + monitor.height - EDGE - height - ROOM);
        this._slide = monitor.y + monitor.height - this.actor.y;
        Main.layoutManager.addTopChrome(this.actor, {trackFullscreen: true});

        this.actor.translation_y = this._slide;
        this.actor.ease({
            opacity: 255,
            translation_y: 0,
            duration: SLIDE,
            mode: Clutter.AnimationMode.EASE_OUT_CUBIC,
        });
        this._startTimer();
    }

    // Where something laid out from the left sits, in this language's direction
    _x(x, width) {
        return this._rtl ? WIDTH + ROOM - x - width : x;
    }

    _button(iconName, name, x, y, action) {
        const button = new St.Button({
            style_class: 'amethystora-screenshot-round',
            child: new St.Icon({icon_name: iconName, icon_size: 16}),
            accessible_name: name,
            x: this._x(x, BUTTON),
            y,
            width: BUTTON,
            height: BUTTON,
        });
        button.connect('clicked', () => this._act(action));
        this.actor.add_child(button);
    }

    _startTimer() {
        this._stopTimer();
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, LINGER, () => {
            this._timer = 0;
            this.close();
            return GLib.SOURCE_REMOVE;
        });
    }

    _stopTimer() {
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
    }

    // Every button, and the picture, does what it says and then puts the card away
    _act(action) {
        try {
            action();
        } catch (e) {
            console.warn(`Amethystora UI: the screenshot could not be opened: ${e.message}`);
        }
        this.close();
    }

    _context() {
        return global.create_app_launch_context(0, -1);
    }

    _openDefault() {
        if (this._file)
            Gio.app_info_launch_default_for_uri(this._file.get_uri(), this._context());
    }

    // Gradia's own launcher with the picture, as `gio launch` would, with the shell's launch context so that Gradia
    // comes to the front
    _openInGradia() {
        const app = Shell.AppSystem.get_default().lookup_app(`${GRADIA}.desktop`);
        app?.get_app_info()?.launch_uris([this._file.get_uri()], this._context());
    }

    _showInFiles() {
        Gio.DBus.session.call('org.freedesktop.FileManager1', '/org/freedesktop/FileManager1',
            'org.freedesktop.FileManager1', 'ShowItems', new GLib.Variant('(ass)', [[this._file.get_uri()], '']),
            null, Gio.DBusCallFlags.NONE, -1, null, null);
    }

    // Down and out; `instantly` when another capture takes its place or the module stops
    close(instantly = false) {
        if (this._closing)
            return;
        this._closing = true;
        this._stopTimer();
        this.actor.reactive = false;
        if (instantly) {
            this.actor.destroy();
            return;
        }
        this.actor.ease({
            opacity: 0,
            translation_y: this._slide,
            duration: SLIDE,
            mode: Clutter.AnimationMode.EASE_IN_CUBIC,
            onStopped: () => this.actor.destroy(),
        });
    }
}
