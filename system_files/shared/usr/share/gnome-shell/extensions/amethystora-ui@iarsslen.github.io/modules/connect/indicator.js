// The phone in the top bar: its icon, with the battery of the phone beside it when there is one phone, and a menu with
// each connected phone's name and charge and what can be done with it. The rows show only while the phone can take the
// request, and do nothing themselves: they hand the choice to the module.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

// The icons of the Adwaita theme, in the order they are tried: its newer name for a phone, then its older
const BAR_ICON = ['smartphone-symbolic', 'phone-symbolic'];
const TYPE_ICONS = {
    phone: BAR_ICON,
    tablet: ['tablet-symbolic'],
    laptop: ['laptop-symbolic', 'computer-symbolic'],
    desktop: ['computer-symbolic'],
    tv: ['tv-symbolic'],
};

// The battery in the menu is quieter than the name beside it, out of 255
const QUIET = 170;

let percentFormat = null;

// 87 as the session's language writes "87%"
function percent(level) {
    percentFormat ??= new Intl.NumberFormat(undefined, {style: 'percent', maximumFractionDigits: 0});
    return percentFormat.format(level / 100);
}

// One phone's part of the menu: its title, then its rows, then a line under them. The line is the menu's own item and
// not the section's, since the menu hides a separator that ends a section.
class Section {
    constructor(device, actions, bolt) {
        this.menu = new PopupMenu.PopupMenuSection();
        this.separator = new PopupMenu.PopupSeparatorMenuItem();

        const title = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        title.add_style_class_name('amethystora-connect-title');
        this._type = new St.Icon({style_class: 'popup-menu-icon'});
        this._name = new St.Label({
            style_class: 'amethystora-connect-name',
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._level = new St.Label({
            style_class: 'amethystora-connect-battery',
            y_align: Clutter.ActorAlign.CENTER,
            opacity: QUIET,
        });
        this._charge = new St.Icon({gicon: bolt, style_class: 'popup-menu-icon amethystora-connect-bolt'});
        for (const actor of [this._type, this._name, this._level, this._charge])
            title.add_child(actor);
        this.menu.addMenuItem(title);

        // Each row is shown only while the phone says it takes the request
        this._rows = [
            [_('Send files…'), 'share', true, () => actions.sendFiles(device)],
            [_('Send a link'), 'share', false, () => actions.sendLink(device)],
            [_('Ping'), 'ping', false, () => actions.ping(device)],
            [_('Messages'), 'sms', true, () => actions.messages(device)],
        ].map(([label, feature, app, run]) => {
            const item = new PopupMenu.PopupMenuItem(label);
            item.connect('activate', run);
            this.menu.addMenuItem(item);
            return {item, feature, app};
        });
    }

    update(device) {
        this._type.gicon = Gio.ThemedIcon.new_from_names(TYPE_ICONS[device.type]);
        this._name.text = device.name;
        const level = device.level;
        this._level.visible = level >= 0;
        this._level.text = level >= 0 ? percent(level) : '';
        this._charge.visible = device.charging;

        const features = device.features;
        for (const {item, feature, app} of this._rows)
            item.visible = features.has(feature) && (!app || device.launchable);
    }

    destroy() {
        this.menu.destroy();
        this.separator.destroy();
    }
}

export const Indicator = GObject.registerClass(
class PhoneIndicator extends PanelMenu.Button {
    /**
     * @param {object} actions - what a row does, each given the phone: sendFiles, sendLink, ping, messages, and
     *     phones() for the app's window
     * @param {Gio.Icon} bolt - the mark of a phone that is charging
     */
    _init(actions, bolt) {
        super._init(0.5, _('Phones'), false);
        this.add_style_class_name('amethystora-connect-button');
        this.menu.actor.add_style_class_name('amethystora-connect-menu');
        this._actions = actions;
        this._bolt = bolt;
        this._sections = new Map();

        const box = new St.BoxLayout({style_class: 'amethystora-connect-box', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(new St.Icon({
            gicon: Gio.ThemedIcon.new_from_names(BAR_ICON),
            style_class: 'system-status-icon',
        }));
        this._level = new St.Label({
            style_class: 'amethystora-connect-level',
            y_align: Clutter.ActorAlign.CENTER,
            visible: false,
        });
        this._charge = new St.Icon({
            gicon: bolt,
            style_class: 'system-status-icon amethystora-connect-bolt',
            visible: false,
        });
        box.add_child(this._level);
        box.add_child(this._charge);
        this.add_child(box);

        const phones = new PopupMenu.PopupMenuItem(_('Phones…'));
        phones.connect('activate', () => actions.phones());
        this.menu.addMenuItem(phones);
    }

    /**
     * The phones now connected, in the order they are listed. A phone's part of the menu is made when it first
     * appears and taken away when it leaves; the rest is changed where it stands.
     *
     * @param {import('./link.js').Device[]} devices
     */
    update(devices) {
        const present = new Set(devices.map(device => device.path));
        for (const [path, section] of this._sections) {
            if (!present.has(path)) {
                section.destroy();
                this._sections.delete(path);
            }
        }
        devices.forEach((device, position) => {
            let section = this._sections.get(device.path);
            if (!section) {
                section = new Section(device, this._actions, this._bolt);
                this._sections.set(device.path, section);
                this.menu.addMenuItem(section.menu, 2 * position);
                this.menu.addMenuItem(section.separator, 2 * position + 1);
            } else if (this.menu.box.get_children().indexOf(section.menu.actor) !== 2 * position) {
                // A phone with a new name stands elsewhere in the order
                this.menu.moveMenuItem(section.menu, 2 * position);
                this.menu.moveMenuItem(section.separator, 2 * position + 1);
            }
            section.update(device);
        });

        // One phone is its battery, in the bar; several are in the menu
        const only = devices.length === 1 ? devices[0] : null;
        const level = only?.level ?? -1;
        this._level.visible = level >= 0;
        this._level.text = level >= 0 ? percent(level) : '';
        this._charge.visible = only?.charging ?? false;
        this.accessible_name = only ? only.name : _('Phones');
    }
});
