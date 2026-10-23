// Tray items that never told this tray about themselves: a program that registered with the tray before (before a
// lock or a restart of the shell) and does not register again. Every program on the session bus is asked which
// objects it has, from its root down, and every object that is a tray item is reported. The work is all calls to
// other programs, a few at a time, and the shell waits on none of them.

import Gio from 'gi://Gio';

import {ITEM_IFACE, busCall, call, isCancelled, nameOwner} from './dbus.js';

// Programs asked at the same time, and how long one may take to answer
const PARALLEL = 4;
const TIMEOUT = 5000;

// Runs `work` on every value, `PARALLEL` at a time
async function eachAtMost(values, work) {
    const queue = [...values];
    const worker = async () => {
        while (queue.length) {
            // eslint-disable-next-line no-await-in-loop
            await work(queue.shift());
        }
    };
    await Promise.all(Array.from({length: Math.min(PARALLEL, queue.length)}, worker));
}

async function walk(owner, path, found, cancellable) {
    let info;
    try {
        const reply = await call(owner, path, 'org.freedesktop.DBus.Introspectable', 'Introspect', null, '(s)',
            cancellable, TIMEOUT);
        info = Gio.DBusNodeInfo.new_for_xml(reply.get_child_value(0).get_string()[0]);
    } catch (e) {
        if (isCancelled(e))
            throw e;
        return;
    }
    if (info.lookup_interface(ITEM_IFACE))
        found.push(path);
    for (const child of info.nodes ?? []) {
        const name = child.path;
        if (!name || name.includes('/'))
            continue;
        // eslint-disable-next-line no-await-in-loop
        await walk(owner, path === '/' ? `/${name}` : `${path}/${name}`, found, cancellable);
    }
}

/**
 * Every tray item on the session bus, by the program that has it.
 *
 * @param {Gio.Cancellable} cancellable - stops the scan
 * @returns {Promise<Array<{owner: string, path: string, names: string[]}>>} each item, its program's unique name
 *   and its program's well-known names
 */
export async function findItems(cancellable) {
    const own = Gio.DBus.session.get_unique_name();
    const reply = await busCall('ListNames', null, '(as)', cancellable);
    const names = reply.get_child_value(0).get_strv();

    // Each program by its unique name, with the well-known names it holds
    const programs = new Map();
    for (const name of names) {
        if (name.startsWith(':') && name !== own)
            programs.set(name, []);
    }
    await eachAtMost(names.filter(name => !name.startsWith(':') && name !== 'org.freedesktop.DBus'), async name => {
        try {
            programs.get(await nameOwner(name, cancellable))?.push(name);
        } catch (e) {
            if (isCancelled(e))
                throw e;
        }
    });

    const items = [];
    await eachAtMost([...programs.keys()], async owner => {
        const found = [];
        await walk(owner, '/', found, cancellable);
        for (const path of found)
            items.push({owner, path, names: programs.get(owner)});
    });
    return items;
}

/**
 * What to register a found item as: a /StatusNotifierItem object by its program's name (one starting
 * org.kde.StatusNotifierItem first), any other by the name and its path.
 *
 * @param {{owner: string, path: string, names: string[]}} found - an item findItems reported
 * @returns {string}
 */
export function serviceFor({owner, path, names}) {
    const name = names.find(n => n.startsWith('org.kde.StatusNotifierItem')) ?? names[0];
    if (path === '/StatusNotifierItem' && name)
        return name;
    return `${name ?? owner}${path}`;
}
