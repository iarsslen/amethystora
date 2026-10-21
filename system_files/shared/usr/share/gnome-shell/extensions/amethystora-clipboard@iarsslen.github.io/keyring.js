// Amethystora Clipboard: the key the history is sealed under, kept in the login keyring (the Secret
// Service), which gnome-keyring encrypts with the login password. Written for Amethystora; not part of
// Clipboard Indicator.
//
// Every call is asynchronous: GNOME Shell is the compositor, and the keyring's own prompter too. Nothing
// here asks to unlock the keyring by itself, so that a login by fingerprint, which leaves it locked, brings
// up no prompt: only unlock() asks, and only a click on the menu's row calls it.

import Secret from 'gi://Secret';

const SCHEMA = new Secret.Schema('org.amethystora.Clipboard', Secret.SchemaFlags.NONE, {
    purpose: Secret.SchemaAttributeType.STRING,
});
const ATTRIBUTES = { purpose: 'history-key' };
const LABEL = 'Clipboard history (Amethystora)';

function call (start, finish) {
    return new Promise((resolve, reject) => start((source, result) => {
        try {
            resolve(finish(source, result));
        } catch (e) {
            reject(e);
        }
    }));
}

const service = () => call(
    done => Secret.Service.get(Secret.ServiceFlags.NONE, null, done),
    (_source, result) => Secret.Service.get_finish(result));

const defaultCollection = svc => call(
    done => Secret.Collection.for_alias(svc, 'default', Secret.CollectionFlags.NONE, null, done),
    (_source, result) => Secret.Collection.for_alias_finish(result));

// Only the keys an unlocked keyring hands over: LOAD_SECRETS without UNLOCK never prompts
const search = svc => call(
    done => svc.search(SCHEMA, ATTRIBUTES, Secret.SearchFlags.ALL | Secret.SearchFlags.LOAD_SECRETS, null, done),
    (source, result) => source.search_finish(result));

// { state: 'open', key } with the key; 'locked' while the keyring is locked; 'none' with no keyring at all.
// newKey() makes a key, which is stored when the keyring has none yet.
export async function find (newKey) {
    let svc;
    try {
        svc = await service();
    } catch (e) {
        return { state: 'none' };
    }
    const items = await search(svc);
    for (const item of items) {
        const text = item.get_locked() ? null : item.get_secret()?.get_text();
        if (text)
            return { state: 'open', key: text };
    }
    if (items.length > 0)
        return { state: 'locked' };
    const collection = await defaultCollection(svc);
    if (!collection)
        return { state: 'none' };
    if (collection.get_locked())
        return { state: 'locked' };
    const key = await newKey();
    await call(
        done => Secret.password_store(SCHEMA, ATTRIBUTES, Secret.COLLECTION_DEFAULT, LABEL, key, null, done),
        (_source, result) => Secret.password_store_finish(result));
    return { state: 'open', key };
}

// GNOME's own prompt for the keyring's password: the items that hold the key, or the default keyring
export async function unlock () {
    const svc = await service();
    const items = await search(svc);
    const objects = items.length > 0 ? items : [await defaultCollection(svc)].filter(Boolean);
    if (objects.length > 0)
        await call(done => svc.unlock(objects, null, done), (source, result) => source.unlock_finish(result));
}

// Calls back when the default keyring is locked or unlocked, by whatever unlocked it; gives back the way
// to stop
export async function watch (callback) {
    const collection = await defaultCollection(await service());
    if (!collection)
        return () => {};
    const id = collection.connect('notify::locked', () => callback());
    return () => collection.disconnect(id);
}
