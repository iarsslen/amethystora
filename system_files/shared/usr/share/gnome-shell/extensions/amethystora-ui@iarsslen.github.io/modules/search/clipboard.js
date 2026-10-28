// clip: the history Amethystora Clipboard already keeps, in memory, shown only when the text typed starts with "clip:"
// and never otherwise; words after it pick the items that hold them. Enter puts the item back on the clipboard and
// pastes it where the person was typing. The history is read from the clipboard extension's own read-only view at
// each search (history(), content()), and nothing of it is kept or written here: in private mode, while the keyring
// keeps the history locked, or with the clipboard extension off, there is nothing to show.

import St from 'gi://St';

import * as DateUtils from 'resource:///org/gnome/shell/misc/dateUtils.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

import {fold} from '../fuzzy/matcher.js';
import {paste} from '../emoji/paste.js';

const CLIPBOARD = 'amethystora-clipboard@iarsslen.github.io';
const PREFIX = /^\s*clip:\s*/iu;
// The most of a text handed to a row's label
const LONGEST = 200;
const SHOWN = 8;

function clipboardExtension() {
    const state = Main.extensionManager.lookup(CLIPBOARD)?.stateObj;
    return typeof state?.history === 'function' && typeof state.content === 'function' ? state : null;
}

export class ClipboardProvider {
    constructor(host) {
        this._host = host;
        this.id = 'amethystora-clipboard';
        this.isRemoteProvider = false;
        this.canLaunchSearch = false;
        this._found = new Map();
        this._previous = new Map();
    }

    destroy() {
        this._found = new Map();
        this._previous = new Map();
    }

    getInitialResultSet(terms) {
        // The last search's results stay known until the next one is in: GNOME may open one of them meanwhile
        this._previous = this._found;
        this._found = new Map();
        const text = terms.join(' ');
        const match = PREFIX.exec(text);
        if (!match)
            return Promise.resolve([]);
        let history;
        try {
            history = clipboardExtension()?.history() ?? [];
        } catch (e) {
            console.warn(`Amethystora UI: the clipboard's history could not be read: ${e.message}`);
            history = [];
        }
        const wanted = fold(text.slice(match[0].length)).split(/\s+/u).filter(Boolean);
        const ids = [];
        for (const item of Array.isArray(history) ? history : []) {
            if (!Number.isInteger(item?.id))
                continue;
            if (item.kind === 'image' ? wanted.length > 0 : !wanted.every(word => fold(item.text).includes(word)))
                continue;
            const id = `clip:${item.id}`;
            this._found.set(id, item);
            ids.push(id);
        }
        return Promise.resolve(ids);
    }

    getSubsearchResultSet(previous, terms) {
        return this.getInitialResultSet(terms);
    }

    getResultMetas(ids) {
        return Promise.resolve(ids.map(id => {
            const item = (this._found.get(id) ?? this._previous.get(id));
            if (!item)
                return {id, name: id};
            const picture = item.kind === 'image';
            let name;
            if (picture) {
                name = item.width && item.height
                    ? _('Picture, %d × %d').format(item.width, item.height) : _('Picture');
            } else {
                name = (item.text.split('\n').find(line => line.trim()) ?? item.text).trim().slice(0, LONGEST) ||
                    item.text.slice(0, LONGEST);
            }
            let age = '';
            if (item.copiedAt) {
                try {
                    age = DateUtils.formatTimeSpan(item.copiedAt);
                } catch {}
            }
            return {
                id, name: name || ' ', description: age, pinned: item.pinned === true,
                gicon: null, symbol: picture ? 'image-x-generic-symbolic' : 'edit-paste-symbolic',
                hint: _('Enter pastes'),
            };
        }));
    }

    filterResults(ids, max) {
        return ids.slice(0, Math.min(max, SHOWN));
    }

    activateResult(id) {
        const item = (this._found.get(id) ?? this._previous.get(id));
        const extension = clipboardExtension();
        if (!item || !extension)
            return;
        const content = extension.content(item.id);
        if (!content?.bytes)
            return;
        St.Clipboard.get_default().set_content(St.ClipboardType.CLIPBOARD, content.mimetype, content.bytes);
        paste({keysOnly: true, window: this._host.typingWindow});
    }
}
