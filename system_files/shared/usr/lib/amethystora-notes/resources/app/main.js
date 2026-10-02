'use strict';

// Amethystora Notes: notes and tasks, kept on this computer and nowhere else, in place of Joplin and
// Planify. Notes are Markdown in notebooks, with tags, attachments, a history and a trash; tasks sit in
// the inbox or in projects and their sections, with dates, repeats, reminders, priorities, labels and
// subtasks. Nothing is synced: the window loads only its own page, and this process opens no connection.
//
// Everything lives in $XDG_DATA_HOME/amethystora-notes, readable by this account only:
//
//   vault.json    whether the notes are encrypted and, when they are, their key, sealed
//   data.bin      the notes and tasks, one sealed JSON document (data.json when not encrypted)
//   *.bak         the version before the last save, read when the newest cannot be
//   resources/    the attachments, one sealed file each
//
// Encryption is AES-256-GCM under a random 256-bit key, and that key is sealed the same way under one
// derived from the passphrase with scrypt, so a new passphrase rewraps the key and nothing else. None of
// it is public-key cryptography, the kind a quantum computer breaks: against AES, Grover's algorithm at
// best halves the key length, which leaves a 256-bit key at the 128-bit level, and is why AES-256 is what
// NIST and CNSA 2.0 keep for the post-quantum era. The passphrase is the weak point, so scrypt is set to
// cost 128 MiB and a good part of a second for every guess.
//
// A passkey opens the notes as well, never instead: the same key sealed once more, under a secret that a
// FIDO2 security key computes with HMAC-SHA256 after its PIN or a fingerprint (see Passkeys below).
//
// The window is locked down the way the Manual's is: it loads nothing but its own page, and the page can
// ask for nothing but what preload.js lists. Attachments reach it through res://, served from here and
// only while the notes are open.

const { app, BrowserWindow, dialog, ipcMain, Notification, powerMonitor, protocol, session, shell } = require('electron');
const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');
const { promisify } = require('node:util');
const zlib = require('node:zlib');

const fsp = fs.promises;
const scrypt = promisify(crypto.scrypt);

const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
const DATA_HOME = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
// Where amethystora-theme renders the current theme (CURRENT_DIR in /usr/lib/amethystora/theme/lib.sh)
const CURRENT = path.join(CONFIG_HOME, 'amethystora', 'current');
const DIR = path.join(DATA_HOME, 'amethystora-notes');
const VAULT = path.join(DIR, 'vault.json');
const RESOURCES = path.join(DIR, 'resources');
const PLAIN = path.join(DIR, 'data.json');
const SEALED = path.join(DIR, 'data.bin');

// 128 * N * r bytes of memory for every guess at the passphrase
const KDF = { name: 'scrypt', N: 2 ** 17, r: 8, p: 1 };
const MAGIC = Buffer.from('ANv1');
const KINDS = ['notebooks', 'notes', 'tags', 'revisions', 'projects', 'sections', 'tasks', 'labels'];
const ID = /^[0-9a-f]{32}$/;
const RESOURCE_LINK = /:\/([0-9a-f]{32})/g;
const ATTACHMENT_LIMIT = 200 * 1024 * 1024;
// An attachment nothing refers to is kept this long, for the note that is about to
const GRACE = 10 * 60000;

app.setPath('userData', path.join(CONFIG_HOME, 'amethystora-notes'));
protocol.registerSchemesAsPrivileged([{ scheme: 'res', privileges: { standard: true, secure: true } }]);

let win = null;
// vault.json as read, null before the first run
let vault = null;
// The data key while the notes are open and encrypted
let key = null;
// The notes and tasks while they are open
let store = null;
let dirty = false;
let saveTimer = null;
let saving = Promise.resolve();
// Upcoming reminders, which outlive a lock so that they still go off: { id, title, at, due }
let reminders = [];
let lastCheck = Date.now();
let lastActive = Date.now();
const shown = new Set();
// The backup the page is asking the passphrase of
let pendingBackup = null;
let quitting = false;

// The page to open: `amethystora-notes tasks` opens the tasks
function pageArgument(argv) {
    const page = argv.slice(1).find((arg) => !arg.startsWith('-'));
    return page === 'tasks' || page === 'notes' ? page : '';
}

// The colours of the current theme, or null before one has been applied. The same as the Manual's.
function palette() {
    const theme = path.join(CURRENT, 'theme');
    let text;
    try {
        text = fs.readFileSync(path.join(theme, 'colors.toml'), 'utf8');
    } catch {
        return null;
    }
    const colors = { light: fs.existsSync(path.join(theme, 'light.mode')) };
    for (const [, name, value] of text.matchAll(/^\s*(\w+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm)) {
        colors[name] = value;
    }
    return colors;
}

function send(channel, value) {
    win?.webContents.send(channel, value);
}

// A program that outlives this window, such as the Manual
function launch(file, args) {
    const child = spawn(file, args, { detached: true, stdio: 'ignore' });
    child.on('error', () => {});
    child.unref();
}

// --- Sealing -----------------------------------------------------------------------------------------

// MAGIC, a fresh 96-bit nonce, the tag, then the ciphertext. The label is authenticated with it, so a
// sealed file cannot be passed off as another: an attachment as the notes, or one attachment as another.
function seal(secret, plain, label) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', secret, iv);
    cipher.setAAD(Buffer.from(`amethystora-notes:${label}`));
    const body = Buffer.concat([cipher.update(plain), cipher.final()]);
    return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), body]);
}

function isSealed(bytes) {
    return bytes.length >= 32 && bytes.subarray(0, 4).equals(MAGIC);
}

// Throws on a wrong key and on anything changed since it was sealed
function unseal(secret, bytes, label) {
    if (!isSealed(bytes)) {
        throw new Error('not sealed');
    }
    const decipher = crypto.createDecipheriv('aes-256-gcm', secret, bytes.subarray(4, 16));
    decipher.setAAD(Buffer.from(`amethystora-notes:${label}`));
    decipher.setAuthTag(bytes.subarray(16, 32));
    return Buffer.concat([decipher.update(bytes.subarray(32)), decipher.final()]);
}

// Settings read from a file are bounded, so that a damaged one cannot ask for all the memory there is
function derive(passphrase, kdf) {
    const { N, r, p, salt } = kdf || {};
    if (kdf?.name !== 'scrypt' || !Number.isInteger(Math.log2(N)) || N < 2 ** 14 || N > 2 ** 20 ||
        !(r >= 1 && r <= 16) || !(p >= 1 && p <= 4) || typeof salt !== 'string') {
        throw new Error('The key settings in vault.json are damaged.');
    }
    return scrypt(String(passphrase).normalize('NFC'), Buffer.from(salt, 'base64'), 32,
        { N, r, p, maxmem: 256 * N * r + 1024 * 1024 });
}

// A vault.json for this key under this passphrase
async function wrap(passphrase, secret) {
    const kdf = { ...KDF, salt: crypto.randomBytes(16).toString('base64') };
    const kek = await derive(passphrase, kdf);
    return { format: 1, encrypted: true, cipher: 'aes-256-gcm', kdf, key: seal(kek, secret, 'key').toString('base64') };
}

// The data key, or null for a wrong passphrase
async function unwrap(passphrase, sealedVault = vault) {
    const kek = await derive(passphrase, sealedVault.kdf);
    try {
        return unseal(kek, Buffer.from(sealedVault.key, 'base64'), 'key');
    } catch {
        return null;
    }
}

// --- Passkeys ----------------------------------------------------------------------------------------

// A passkey is a credential made on a FIDO2 security key with the hmac-secret extension. Asked with the
// salt kept beside it in vault.json, and only once its PIN or a fingerprint has been checked, the key
// answers with 32 bytes that nothing else can compute, and the data key is sealed under those. The key is
// spoken to through libfido2's own tools (fido2-tools), which take what they need as lines on stdin and,
// with no terminal to ask on, ask for the PIN on stderr and read it from stdin too.
const RELYING_PARTY = 'amethystora-notes';
const FIDO_ERRORS = [
    [/PIN_INVALID/, 'That is not the PIN of this security key.'],
    [/PIN_AUTH_BLOCKED/, 'Too many wrong PINs. Unplug the security key, plug it back in and try again.'],
    [/PIN_BLOCKED/, 'The PIN of this security key is blocked, which only resetting the key undoes.'],
    [/PIN_REQUIRED|PIN_NOT_SET|invalid PIN length/, 'Enter the PIN of the security key: 4 to 63 characters.'],
    [/UV_INVALID|UV_BLOCKED/, 'The security key did not recognise the fingerprint.'],
    [/ACTION_TIMEOUT|KEEPALIVE_CANCEL/, 'The security key was not touched in time.'],
    [/NO_CREDENTIALS/, 'This security key is not one that opens your notes.'],
    [/aborted/, 'Cancelled.'],
];
// Aborts the tool that is waiting for the key to be touched; set while a passkey is being used or added
let touching = null;

// The lines one of the tools prints, given these on stdin. Rejects with what the tool said.
function fido(tool, args, lines = [], pin = '') {
    const clean = (text) => String(text).replace(/[\r\n]/g, '');
    return new Promise((resolve, reject) => {
        // In a session of its own: with a terminal, the tool would ask for the PIN there
        const child = spawn(tool, args, { detached: true, signal: touching?.signal, timeout: 120000 });
        let printed = '';
        let said = '';
        let asked = false;
        child.stdout.on('data', (chunk) => {
            printed += chunk;
        });
        child.stderr.on('data', (chunk) => {
            said += chunk;
            if (!asked && said.includes('Enter PIN')) {
                asked = true;
                if (pin) {
                    child.stdin.end(`${clean(pin)}\n`);
                } else {
                    said = 'PIN_REQUIRED';
                    child.kill();
                }
            }
        });
        child.stdin.on('error', () => {});
        child.on('error', reject);
        child.on('close', (code) => (code === 0 ? resolve(printed.split('\n')) : reject(new Error(said.trim() || `${tool} failed`))));
        child.stdin.write(lines.map((line) => `${clean(line)}\n`).join(''));
    });
}

// One passkey operation at a time, with what went wrong said in plain words
async function withKey(run) {
    if (touching) {
        return { error: 'The security key is busy. Try again in a moment.' };
    }
    touching = new AbortController();
    try {
        return await run();
    } catch (error) {
        return { error: FIDO_ERRORS.find(([pattern]) => pattern.test(error.message))?.[1] || error.message };
    } finally {
        touching = null;
    }
}

// The security keys plugged in: where each one is, and what it calls itself
async function fidoDevices() {
    return (await fido('fido2-token', ['-L']))
        .map((line) => /^(.+?): vendor=0x[0-9a-f]+, product=0x[0-9a-f]+ \((.*)\)$/.exec(line))
        .filter(Boolean)
        .map(([, device, name]) => ({ device, name: name.trim() || 'Security key' }));
}

// Whether the key keeps secrets for apps, has a PIN, and has a fingerprint enrolled
async function fidoInfo(device) {
    const lines = await fido('fido2-token', ['-I', device]);
    const list = (label) => (lines.find((line) => line.startsWith(`${label}: `)) || '').slice(label.length + 2).split(', ');
    const options = list('options');
    return { secrets: list('extension strings').includes('hmac-secret'), pin: options.includes('clientPin'), uv: options.includes('uv') };
}

// Whether this passkey was made on this key, which the key says without being touched
function holds(device, passkey) {
    return fido('fido2-assert', ['-G', '-t', 'up=false', device],
        [crypto.randomBytes(32).toString('base64'), RELYING_PARTY, passkey.credential])
        .then(() => true, (error) => !/NO_CREDENTIALS/.test(error.message));
}

// The plugged-in key that holds one of the passkeys, and which one
async function findPasskey() {
    for (const { device } of await fidoDevices()) {
        for (const passkey of vault?.passkeys || []) {
            if (await holds(device, passkey)) {
                return { device, passkey };
            }
        }
    }
    return null;
}

// The secret the key computes for this passkey once it is touched: after its PIN, or, given none, after
// the fingerprint it reads itself. Either way the key has checked who is asking, and the secret is the
// same; a touch alone would get a different one.
async function passkeySecret(device, passkey, pin) {
    const lines = await fido('fido2-assert', ['-G', '-h', '-t', pin ? 'pin=true' : 'uv=true', device],
        [crypto.randomBytes(32).toString('base64'), RELYING_PARTY, passkey.credential, passkey.salt], pin);
    const secret = Buffer.from(lines[4] || '', 'base64');
    if (secret.length !== 32) {
        throw new Error('The security key gave no secret.');
    }
    return secret;
}

// --- Files -------------------------------------------------------------------------------------------

async function removeQuiet(...files) {
    await Promise.all(files.map((file) => fsp.rm(file, { force: true }).catch(() => {})));
}

// Written beside the file and renamed over it, so a file is only ever the old one or the new one. With
// keep, the old one stays as .bak.
async function writeAtomic(file, bytes, keep = false) {
    const temporary = `${file}.tmp`;
    const handle = await fsp.open(temporary, 'w', 0o600);
    try {
        await handle.writeFile(bytes);
        await handle.sync();
    } finally {
        await handle.close();
    }
    if (keep) {
        await fsp.rename(file, `${file}.bak`).catch(() => {});
    }
    await fsp.rename(temporary, file);
}

function emptyStore() {
    return { version: 1, settings: {}, resources: {}, ...Object.fromEntries(KINDS.map((kind) => [kind, {}])) };
}

function normalise(data) {
    const result = emptyStore();
    for (const kind of [...KINDS, 'resources']) {
        if (data?.[kind] && typeof data[kind] === 'object') {
            result[kind] = data[kind];
        }
    }
    if (data?.settings && typeof data.settings === 'object') {
        result.settings = data.settings;
    }
    return result;
}

// The newest readable copy. An encrypted vault still reads data.json, which is where the notes are
// when turning encryption on was cut short; the next save seals them and removes it.
async function readData() {
    const candidates = key ? [SEALED, `${SEALED}.bak`, PLAIN, `${PLAIN}.bak`] : [PLAIN, `${PLAIN}.bak`];
    let found = false;
    for (const file of candidates) {
        let bytes;
        try {
            bytes = await fsp.readFile(file);
        } catch {
            continue;
        }
        found = true;
        try {
            const text = file.startsWith(SEALED) ? unseal(key, bytes, 'data') : bytes;
            const data = normalise(JSON.parse(text.toString('utf8')));
            if (file !== candidates[0]) {
                dirty = true;
            }
            return data;
        } catch {
            // Damaged: try the one before it
        }
    }
    if (found) {
        throw new Error(`Your notes could not be read. Nothing has been changed in ${DIR}.`);
    }
    return emptyStore();
}

async function writeData(bytes, sealed) {
    await writeAtomic(sealed ? SEALED : PLAIN, bytes, true);
    // Whatever the other form left behind: a plain copy must not outlive turning encryption on
    await removeQuiet(...(sealed ? [PLAIN, `${PLAIN}.bak`] : [SEALED, `${SEALED}.bak`]));
}

function scheduleSave() {
    dirty = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(flush, 400);
}

// Everything changed so far on its way to disk, in order
function flush() {
    clearTimeout(saveTimer);
    saveTimer = null;
    if (!store || !dirty) {
        return saving;
    }
    dirty = false;
    const json = Buffer.from(JSON.stringify(store));
    const sealed = Boolean(key);
    const bytes = sealed ? seal(key, json, 'data') : json;
    saving = saving
        .then(() => writeData(bytes, sealed))
        .catch((error) => {
            dirty = true;
            send('problem', `Your last changes could not be saved: ${error.message}`);
        });
    return saving;
}

function resourceFile(id) {
    return path.join(RESOURCES, id);
}

async function writeResource(id, bytes) {
    await fsp.mkdir(RESOURCES, { recursive: true, mode: 0o700 });
    await writeAtomic(resourceFile(id), key ? seal(key, bytes, `resource:${id}`) : bytes);
}

async function readResource(id) {
    const bytes = await fsp.readFile(resourceFile(id));
    return key && isSealed(bytes) ? unseal(key, bytes, `resource:${id}`) : bytes;
}

// Seals any attachment still in the clear, which turning encryption on leaves only if it was cut short
async function sealResources() {
    let names = [];
    try {
        names = await fsp.readdir(RESOURCES);
    } catch {
        return;
    }
    for (const name of names.filter((item) => ID.test(item))) {
        const bytes = await fsp.readFile(resourceFile(name)).catch(() => null);
        if (bytes && !isSealed(bytes)) {
            await writeResource(name, bytes);
        }
    }
}

// Removes the attachments that no note, version or task refers to any more
async function collectResources() {
    if (!store) {
        return;
    }
    const referenced = new Set();
    const scan = (text) => {
        for (const [, id] of String(text || '').matchAll(RESOURCE_LINK)) {
            referenced.add(id);
        }
    };
    Object.values(store.notes).forEach((note) => scan(note.body));
    Object.values(store.revisions).forEach((revision) => scan(revision.body));
    Object.values(store.tasks).forEach((task) => scan(task.notes));
    const now = Date.now();
    for (const [id, resource] of Object.entries(store.resources)) {
        if (!referenced.has(id) && now - (resource.created || 0) > GRACE) {
            delete store.resources[id];
            dirty = true;
            await removeQuiet(resourceFile(id));
        }
    }
    // Files a crash left without an entry
    let names = [];
    try {
        names = await fsp.readdir(RESOURCES);
    } catch {
        // No attachments yet
    }
    for (const name of names) {
        const stale = !ID.test(name) ? name.endsWith('.tmp') : !store.resources[name];
        if (stale) {
            const stat = await fsp.stat(resourceFile(name)).catch(() => null);
            if (stat && now - stat.mtimeMs > GRACE) {
                await removeQuiet(resourceFile(name));
            }
        }
    }
    if (dirty) {
        scheduleSave();
    }
}

// --- The vault ---------------------------------------------------------------------------------------

function status() {
    if (!vault) {
        return 'new';
    }
    return store ? 'open' : 'locked';
}

function describe() {
    const passkeys = (vault?.passkeys || []).map(({ id, name, created }) => ({ id, name, created }));
    return { status: status(), encrypted: Boolean(vault?.encrypted), passkeys, dir: DIR, data: store };
}

async function readVault() {
    try {
        vault = JSON.parse(await fsp.readFile(VAULT, 'utf8'));
    } catch (error) {
        vault = null;
        if (error.code !== 'ENOENT') {
            throw new Error(`${VAULT} could not be read: ${error.message}`);
        }
    }
}

// The notes are open: remember what they need reminding of and tidy up after any interrupted change
async function opened() {
    lastActive = Date.now();
    lastCheck = Date.now();
    computeReminders();
    if (key) {
        await sealResources();
    }
    setTimeout(() => collectResources().catch(() => {}), 5000);
    if (dirty) {
        flush();
    }
}

async function create(passphrase) {
    if (vault) {
        return { error: 'Notes are already set up here.' };
    }
    await fsp.mkdir(RESOURCES, { recursive: true, mode: 0o700 });
    await fsp.chmod(DIR, 0o700).catch(() => {});
    let next = { format: 1, encrypted: false };
    let secret = null;
    if (passphrase) {
        secret = crypto.randomBytes(32);
        next = await wrap(passphrase, secret);
    }
    await writeAtomic(VAULT, JSON.stringify(next, null, 2));
    vault = next;
    key = secret;
    store = emptyStore();
    const notebook = crypto.randomBytes(16).toString('hex');
    store.notebooks[notebook] = { id: notebook, title: 'Notes', parent: null, created: Date.now(), updated: Date.now() };
    dirty = true;
    await flush();
    await opened();
    return describe();
}

// Opens the notes with their data key
async function openWith(secret) {
    key = secret;
    try {
        store = await readData();
    } catch (error) {
        key = null;
        return { error: error.message };
    }
    await opened();
    return describe();
}

async function unlock(passphrase) {
    if (store) {
        return describe();
    }
    const secret = await unwrap(passphrase);
    if (!secret) {
        return { error: 'That is not the passphrase.' };
    }
    return openWith(secret);
}

// With a passkey: { pin: true } asks the page for the PIN of a key that reads no fingerprint
async function unlockWithPasskey(pin) {
    if (store) {
        return describe();
    }
    const found = await findPasskey();
    if (!found) {
        return { error: 'Plug in a security key that opens your notes.' };
    }
    if (!pin && !(await fidoInfo(found.device)).uv) {
        return { pin: true };
    }
    const secret = await passkeySecret(found.device, found.passkey, pin);
    let opening;
    try {
        opening = unseal(secret, Buffer.from(found.passkey.key, 'base64'), `passkey:${found.passkey.id}`);
    } catch {
        return { error: 'This passkey no longer opens your notes. Use your passphrase.' };
    } finally {
        secret.fill(0);
    }
    return openWith(opening);
}

// Seals the data key once more, under the secret of the one security key that is plugged in
async function addPasskey({ current, pin }) {
    if (!store || !vault.encrypted) {
        return { error: 'Unlock your notes first.' };
    }
    if (!(await unwrap(current))) {
        return { error: 'That is not the current passphrase.' };
    }
    const devices = await fidoDevices();
    if (devices.length !== 1) {
        return { error: devices.length ? 'Leave only the security key you are adding plugged in.' : 'Plug in your security key.' };
    }
    const [{ device, name }] = devices;
    const info = await fidoInfo(device);
    if (!info.secrets) {
        return { error: 'This security key cannot keep a secret for an app (FIDO2 hmac-secret), so it cannot open your notes.' };
    }
    if (!info.pin && !info.uv) {
        return { error: 'This security key has no PIN yet. Set one in Firefox at about:webauthn, then add it here.' };
    }
    if (!pin && !info.uv) {
        return { error: 'Enter the PIN of the security key.' };
    }
    if (await findPasskey()) {
        return { error: 'This security key already opens your notes.' };
    }
    // Nothing is stored on the key: the credential it returns is all there is of it, and it stays here
    const made = await fido('fido2-cred', ['-M', '-h', ...(pin ? [] : ['-v']), device], [
        crypto.randomBytes(32).toString('base64'), RELYING_PARTY, os.userInfo().username, crypto.randomBytes(16).toString('base64'),
    ], pin);
    const passkey = {
        id: crypto.randomBytes(16).toString('hex'), name, created: Date.now(),
        credential: made[4], salt: crypto.randomBytes(32).toString('base64'),
    };
    const secret = await passkeySecret(device, passkey, pin);
    if (!key) {
        return { error: 'Your notes locked before the passkey was added.' };
    }
    passkey.key = seal(secret, key, `passkey:${passkey.id}`).toString('base64');
    secret.fill(0);
    const changed = { ...vault, passkeys: [...(vault.passkeys || []), passkey] };
    await writeAtomic(VAULT, JSON.stringify(changed, null, 2));
    vault = changed;
    return describe();
}

async function removePasskey(id) {
    if (!store || !vault.passkeys?.some((passkey) => passkey.id === id)) {
        return { error: 'Nothing to change.' };
    }
    const changed = { ...vault, passkeys: vault.passkeys.filter((passkey) => passkey.id !== id) };
    await writeAtomic(VAULT, JSON.stringify(changed, null, 2));
    vault = changed;
    return describe();
}

// Asks the page to hand over what it has not sent yet, and waits a moment for it
let flushed = null;
function requestFlush() {
    if (!win) {
        return Promise.resolve();
    }
    return new Promise((resolve) => {
        const timer = setTimeout(resolve, 1000);
        flushed = () => {
            clearTimeout(timer);
            resolve();
        };
        send('flush');
    });
}

let locking = null;
function lock() {
    if (!vault?.encrypted || !store) {
        return Promise.resolve();
    }
    locking ||= (async () => {
        await requestFlush();
        await flush();
        computeReminders();
        store = null;
        key?.fill(0);
        key = null;
        send('locked');
    })().finally(() => {
        locking = null;
    });
    return locking;
}

async function setEncryption({ action, current, next }) {
    if (!store) {
        return { error: 'Unlock your notes first.' };
    }
    if (vault.encrypted && !(await unwrap(current))) {
        return { error: 'That is not the current passphrase.' };
    }
    await flush();
    await saving;
    if (action === 'change' && vault.encrypted && next) {
        // The passkeys seal the same key, so they stay
        const changed = { ...await wrap(next, key), passkeys: vault.passkeys };
        await writeAtomic(VAULT, JSON.stringify(changed, null, 2));
        vault = changed;
    } else if (action === 'enable' && !vault.encrypted && next) {
        // The key is on disk before anything is sealed with it, so a crash part way loses nothing
        const secret = crypto.randomBytes(32);
        const changed = await wrap(next, secret);
        await writeAtomic(VAULT, JSON.stringify(changed, null, 2));
        vault = changed;
        key = secret;
        await sealResources();
        dirty = true;
        await flush();
    } else if (action === 'disable' && vault.encrypted) {
        // Everything in the clear first, and only then the vault that says so
        for (const id of Object.keys(store.resources)) {
            const bytes = await readResource(id).catch(() => null);
            if (bytes) {
                await writeAtomic(resourceFile(id), bytes);
            }
        }
        await writeAtomic(PLAIN, Buffer.from(JSON.stringify(store)));
        const changed = { format: 1, encrypted: false };
        await writeAtomic(VAULT, JSON.stringify(changed, null, 2));
        vault = changed;
        key.fill(0);
        key = null;
        await removeQuiet(SEALED, `${SEALED}.bak`);
    } else {
        return { error: 'Nothing to change.' };
    }
    return describe();
}

// --- Changes from the page ---------------------------------------------------------------------------

function put(kind, items) {
    if (!store || !KINDS.includes(kind) || !Array.isArray(items)) {
        return false;
    }
    for (const item of items) {
        if (item && typeof item === 'object' && ID.test(item.id)) {
            store[kind][item.id] = item;
        }
    }
    scheduleSave();
    if (kind === 'tasks') {
        computeReminders();
    }
    return true;
}

function drop(kind, ids) {
    if (!store || !KINDS.includes(kind) || !Array.isArray(ids)) {
        return false;
    }
    for (const id of ids) {
        delete store[kind][id];
    }
    scheduleSave();
    if (kind === 'tasks') {
        computeReminders();
    } else if (kind === 'notes' || kind === 'revisions') {
        collectResources().catch(() => {});
    }
    return true;
}

const SETTINGS = {
    autoLock: (value) => Number.isInteger(value) && value >= 0 && value <= 1440,
    background: (value) => typeof value === 'boolean',
    layout: (value) => ['edit', 'split', 'preview'].includes(value),
    noteSort: (value) => ['updated', 'created', 'title'].includes(value),
};

function setSettings(values) {
    if (!store || !values || typeof values !== 'object') {
        return null;
    }
    for (const [name, value] of Object.entries(values)) {
        if (SETTINGS[name]?.(value)) {
            store.settings[name] = value;
        }
    }
    scheduleSave();
    return store.settings;
}

// --- Attachments -------------------------------------------------------------------------------------

const TYPES = {
    png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp',
    svg: 'image/svg+xml', avif: 'image/avif', bmp: 'image/bmp', pdf: 'application/pdf', txt: 'text/plain',
    md: 'text/markdown', zip: 'application/zip', mp3: 'audio/mpeg', ogg: 'audio/ogg', mp4: 'video/mp4',
    webm: 'video/webm', odt: 'application/vnd.oasis.opendocument.text', json: 'application/json',
};

function typeOf(name) {
    return TYPES[path.extname(name).slice(1).toLowerCase()] || 'application/octet-stream';
}

function extensionOf(mime, name = '') {
    const own = path.extname(name).slice(1).toLowerCase();
    if (own && /^[a-z0-9]{1,8}$/.test(own)) {
        return own;
    }
    return Object.entries(TYPES).find(([, type]) => type === mime)?.[0] || 'bin';
}

async function addResource(name, mime, bytes, id = crypto.randomBytes(16).toString('hex')) {
    await writeResource(id, bytes);
    const resource = { id, name: String(name || 'Attachment').slice(0, 200), mime: String(mime || typeOf(name)), size: bytes.length, created: Date.now() };
    store.resources[id] = resource;
    scheduleSave();
    return resource;
}

async function attachFiles() {
    if (!store) {
        return [];
    }
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
        title: 'Attach files',
        properties: ['openFile', 'multiSelections'],
    });
    if (canceled) {
        return [];
    }
    const added = [];
    for (const file of filePaths) {
        const stat = await fsp.stat(file);
        if (stat.size > ATTACHMENT_LIMIT) {
            send('problem', `${path.basename(file)} is larger than 200 MB and was not attached.`);
            continue;
        }
        added.push(await addResource(path.basename(file), typeOf(file), await fsp.readFile(file)));
    }
    return added;
}

async function attachData(name, mime, data) {
    if (!store || !(data instanceof ArrayBuffer || ArrayBuffer.isView(data)) || data.byteLength > ATTACHMENT_LIMIT) {
        return null;
    }
    const bytes = Buffer.from(data instanceof ArrayBuffer ? data : data.buffer);
    const type = /^[\w.+-]+\/[\w.+-]+$/.test(String(mime)) ? String(mime) : typeOf(String(name));
    const fallback = `Pasted ${new Date().toISOString().slice(0, 10)}.${extensionOf(type)}`;
    return addResource(String(name || fallback), type, bytes);
}

async function saveResource(id) {
    const resource = store?.resources[id];
    if (!resource) {
        return { error: 'That attachment is not here any more.' };
    }
    const { canceled, filePath } = await dialog.showSaveDialog(win, {
        title: 'Save attachment',
        defaultPath: path.join(app.getPath('downloads'), resource.name.replace(/[/\\]/g, '-')),
    });
    if (canceled) {
        return {};
    }
    await fsp.writeFile(filePath, await readResource(id));
    return { path: filePath };
}

// --- Export ------------------------------------------------------------------------------------------

// A name any file system takes
function fileName(name, fallback = 'Untitled') {
    const clean = String(name || '').replace(/[\u0000-\u001f/\\:*?"<>|]+/g, '-').replace(/^[.\s]+|[.\s]+$/g, '').slice(0, 120);
    return clean || fallback;
}

function unique(taken, base, extension) {
    let name = `${base}${extension}`;
    for (let count = 2; taken.has(name.toLowerCase()); count += 1) {
        name = `${base} ${count}${extension}`;
    }
    taken.add(name.toLowerCase());
    return name;
}

function localDate(time) {
    const date = new Date(time);
    const pad = (value) => String(value).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

// Every note as a Markdown file in a folder per notebook, every project's tasks as a checklist, and the
// attachments in _resources, which the notes link to relatively
async function exportMarkdown() {
    if (!store) {
        return { error: 'Unlock your notes first.' };
    }
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
        title: 'Export to a folder',
        properties: ['openDirectory', 'createDirectory'],
    });
    if (canceled) {
        return {};
    }
    const root = path.join(filePaths[0], unique(new Set(fs.readdirSync(filePaths[0]).map((name) => name.toLowerCase())),
        `Notes ${localDate(Date.now())}`, ''));
    const folders = new Map();
    const takenIn = new Map();
    const folderOf = (id, depth = 0) => {
        const notebook = store.notebooks[id];
        if (!notebook || depth > 32) {
            return root;
        }
        if (!folders.has(id)) {
            const parent = folderOf(notebook.parent, depth + 1);
            const taken = takenIn.get(parent) || new Set();
            takenIn.set(parent, taken);
            folders.set(id, path.join(parent, unique(taken, fileName(notebook.title), '')));
        }
        return folders.get(id);
    };
    const resourceDir = path.join(root, '_resources');
    const used = new Set();
    let notes = 0;
    for (const note of Object.values(store.notes).filter((item) => !item.trashed)) {
        const folder = folderOf(note.notebook);
        await fsp.mkdir(folder, { recursive: true });
        const taken = takenIn.get(folder) || new Set();
        takenIn.set(folder, taken);
        const relative = path.relative(folder, resourceDir).split(path.sep).join('/');
        const body = String(note.body || '').replace(RESOURCE_LINK, (match, id) => {
            const resource = store.resources[id];
            if (!resource) {
                return match;
            }
            used.add(id);
            return `${relative}/${id}.${extensionOf(resource.mime, resource.name)}`;
        });
        const tags = (note.tags || []).map((id) => store.tags[id]?.title).filter(Boolean);
        const front = ['---', `title: ${JSON.stringify(note.title || '')}`,
            `created: ${new Date(note.created || Date.now()).toISOString()}`,
            `updated: ${new Date(note.updated || Date.now()).toISOString()}`,
            ...(tags.length ? [`tags: ${JSON.stringify(tags)}`] : []), '---', ''].join('\n');
        await fsp.writeFile(path.join(folder, unique(taken, fileName(note.title), '.md')), `${front}\n${body}\n`);
        notes += 1;
    }
    if (used.size) {
        await fsp.mkdir(resourceDir, { recursive: true });
        for (const id of used) {
            const resource = store.resources[id];
            const bytes = await readResource(id).catch(() => null);
            if (bytes) {
                await fsp.writeFile(path.join(resourceDir, `${id}.${extensionOf(resource.mime, resource.name)}`), bytes);
            }
        }
    }
    // Tasks: a checklist per project, the inbox first, sections as headings, subtasks indented
    const tasks = Object.values(store.tasks);
    const line = (task, depth) => {
        const details = [task.due && `due ${task.due}${task.time ? ` ${task.time}` : ''}`,
            task.repeat && `every ${task.repeat.every > 1 ? `${task.repeat.every} ` : ''}${task.repeat.unit}${task.repeat.every > 1 ? 's' : ''}`,
            task.priority && task.priority < 4 && `p${task.priority}`,
            ...(task.labels || []).map((id) => store.labels[id] && `@${store.labels[id].title}`)].filter(Boolean);
        const rows = [`${'  '.repeat(depth)}- [${task.done ? 'x' : ' '}] ${task.title || 'Untitled'}${details.length ? ` (${details.join(', ')})` : ''}`];
        for (const child of tasks.filter((item) => item.parent === task.id)) {
            rows.push(...line(child, depth + 1));
        }
        return rows;
    };
    const lists = [[null, 'Inbox'], ...Object.values(store.projects).map((project) => [project.id, project.title])];
    const takenTasks = new Set();
    let exportedTasks = 0;
    for (const [project, title] of lists) {
        const own = tasks.filter((task) => (task.project || null) === project && !task.parent);
        if (!own.length) {
            continue;
        }
        const rows = [`# ${title || 'Untitled'}`, ''];
        const sections = Object.values(store.sections).filter((section) => section.project === project)
            .sort((a, b) => (a.order || 0) - (b.order || 0));
        own.filter((task) => !task.section || !store.sections[task.section]).forEach((task) => rows.push(...line(task, 0)));
        for (const section of sections) {
            rows.push('', `## ${section.title || 'Untitled'}`, '');
            own.filter((task) => task.section === section.id).forEach((task) => rows.push(...line(task, 0)));
        }
        await fsp.mkdir(path.join(root, 'Tasks'), { recursive: true });
        await fsp.writeFile(path.join(root, 'Tasks', unique(takenTasks, fileName(title), '.md')), `${rows.join('\n').replace(/\n{3,}/g, '\n\n')}\n`);
        exportedTasks += own.length;
    }
    await fsp.mkdir(root, { recursive: true });
    return { path: root, notes, tasks: exportedTasks };
}

// One file with everything, attachments included, sealed with the notes' own key and carrying it wrapped
// under the current passphrase: it opens with the passphrase it was made with, on any machine. The
// passkeys are left out of it.
async function backup() {
    if (!store) {
        return { error: 'Unlock your notes first.' };
    }
    const { canceled, filePath } = await dialog.showSaveDialog(win, {
        title: 'Back up to a file',
        defaultPath: path.join(app.getPath('documents'), `Notes backup ${localDate(Date.now())}.amnotes`),
        filters: [{ name: 'Notes backup', extensions: ['amnotes'] }],
    });
    if (canceled) {
        return {};
    }
    const resources = {};
    for (const id of Object.keys(store.resources)) {
        const bytes = await readResource(id).catch(() => null);
        if (bytes) {
            resources[id] = bytes.toString('base64');
        }
    }
    const packed = zlib.gzipSync(Buffer.from(JSON.stringify({ store, resources })));
    const file = { format: 'amethystora-notes-backup', version: 1, created: new Date().toISOString(), encrypted: Boolean(key) };
    if (key) {
        Object.assign(file, { cipher: vault.cipher, kdf: vault.kdf, key: vault.key, data: seal(key, packed, 'backup').toString('base64') });
    } else {
        file.data = packed.toString('base64');
    }
    await writeAtomic(filePath, JSON.stringify(file));
    return { path: filePath, encrypted: Boolean(key) };
}

// --- Import ------------------------------------------------------------------------------------------

// A stable id for something from another app, so that importing the same file twice updates rather than
// duplicates
function idFor(source, id) {
    const text = String(id);
    return ID.test(text) ? text : crypto.createHash('sha256').update(`${source}:${text}`).digest('hex').slice(0, 32);
}

function timeOf(value, fallback = Date.now()) {
    const time = typeof value === 'number' ? value : Date.parse(value);
    return Number.isFinite(time) && time > 0 ? time : fallback;
}

function upsert(kind, item) {
    store[kind][item.id] = { ...store[kind][item.id], ...item };
}

// A ustar archive, which is what a Joplin export (.jex) is
function untar(buffer) {
    const files = new Map();
    let offset = 0;
    let longName = null;
    while (offset + 512 <= buffer.length) {
        const header = buffer.subarray(offset, offset + 512);
        if (header.every((byte) => byte === 0)) {
            break;
        }
        const field = (start, length) => header.subarray(start, start + length).toString('utf8').replace(/\0[\s\S]*$/, '');
        const prefix = field(345, 155);
        const name = prefix ? `${prefix}/${field(0, 100)}` : field(0, 100);
        const size = parseInt(field(124, 12).trim() || '0', 8) || 0;
        const type = header[156] ? String.fromCharCode(header[156]) : '0';
        const body = buffer.subarray(offset + 512, offset + 512 + size);
        if (type === 'x') {
            longName = /\d+ path=([^\n]*)\n/.exec(body.toString('utf8'))?.[1] || null;
        } else if (type === 'L') {
            longName = body.toString('utf8').replace(/\0[\s\S]*$/, '');
        } else {
            if (type === '0' || type === '7') {
                files.set(longName || name, body);
            }
            longName = null;
        }
        offset += 512 + Math.ceil(size / 512) * 512;
    }
    return files;
}

// Joplin's own serialisation, read the way it reads it: properties from the end up to the first blank
// line, then the title on the first line and the body after the line below it
function joplinItem(text) {
    const lines = text.replace(/\r\n/g, '\n').split('\n');
    const item = {};
    const body = [];
    let readingProps = true;
    for (let index = lines.length - 1; index >= 0; index -= 1) {
        const line = lines[index];
        if (readingProps) {
            if (!line.trim()) {
                if (Object.keys(item).length) {
                    readingProps = false;
                }
                continue;
            }
            const at = line.indexOf(':');
            if (at < 0) {
                return null;
            }
            item[line.slice(0, at).trim()] = line.slice(at + 1).trim();
        } else {
            body.unshift(line);
        }
    }
    item.title = body.length ? body.splice(0, 2)[0] : '';
    item.body = body.join('\n');
    return item;
}

async function importJex(buffer, counts) {
    const files = untar(buffer);
    const items = [];
    for (const [name, bytes] of files) {
        if (/^[0-9a-f]{32}\.md$/.test(name)) {
            const item = joplinItem(bytes.toString('utf8'));
            if (item?.id && item.type_) {
                items.push(item);
            }
        }
    }
    const of = (type) => items.filter((item) => item.type_ === String(type));
    for (const folder of of(2)) {
        upsert('notebooks', {
            id: idFor('joplin', folder.id), title: folder.title || 'Untitled',
            parent: folder.parent_id ? idFor('joplin', folder.parent_id) : null,
            created: timeOf(folder.created_time), updated: timeOf(folder.updated_time),
        });
        counts.notebooks += 1;
    }
    for (const resource of of(4)) {
        const file = [...files.keys()].find((name) => name.startsWith(`resources/${resource.id}`));
        if (file && ID.test(resource.id)) {
            await addResource(resource.filename || resource.title || `${resource.id}.${resource.file_extension || 'bin'}`,
                resource.mime, files.get(file), resource.id);
            counts.attachments += 1;
        }
    }
    for (const tag of of(5)) {
        upsert('tags', { id: idFor('joplin', tag.id), title: tag.title || 'tag' });
    }
    const tagsOf = new Map();
    for (const link of of(6)) {
        const list = tagsOf.get(link.note_id) || [];
        list.push(idFor('joplin', link.tag_id));
        tagsOf.set(link.note_id, list);
    }
    let fallback = null;
    for (const note of of(1)) {
        const id = idFor('joplin', note.id);
        if (note.is_todo === '1') {
            const due = Number(note.todo_due) > 0 ? new Date(Number(note.todo_due)) : null;
            upsert('tasks', {
                id, title: note.title || 'Untitled', notes: note.body, project: null, section: null, parent: null,
                due: due ? localDate(due) : null,
                time: due ? `${String(due.getHours()).padStart(2, '0')}:${String(due.getMinutes()).padStart(2, '0')}` : null,
                reminder: due ? 0 : null, priority: 4, labels: [], pinned: false, repeat: null,
                done: Number(note.todo_completed) > 0 ? Number(note.todo_completed) : null,
                created: timeOf(note.created_time), order: timeOf(note.created_time),
            });
            counts.tasks += 1;
            continue;
        }
        let notebook = note.parent_id ? idFor('joplin', note.parent_id) : null;
        if (!notebook || !store.notebooks[notebook]) {
            fallback ||= importNotebook();
            notebook = fallback;
        }
        upsert('notes', {
            id, notebook, title: note.title || '', body: note.body, tags: tagsOf.get(note.id) || [],
            created: timeOf(note.created_time), updated: timeOf(note.updated_time), trashed: null,
        });
        counts.notes += 1;
    }
}

// Planify's colours are Todoist's; each goes to the nearest of the few here
const PLANIFY_COLOURS = {
    berry_red: 'pink', red: 'red', orange: 'orange', yellow: 'yellow', olive_green: 'green', lime_green: 'green',
    green: 'green', mint_green: 'teal', teal: 'teal', sky_blue: 'blue', light_blue: 'blue', blue: 'blue',
    grape: 'violet', violet: 'violet', lavender: 'violet', magenta: 'pink', salmon: 'orange', charcoal: 'slate',
    grey: 'slate', taupe: 'slate',
};

// Planify's backup (Preferences, Backups): its own JSON, with the due date as JSON inside a string
function importPlanify(data, counts) {
    const labelOf = new Map(Object.values(store.labels).map((label) => [label.title.toLowerCase(), label.id]));
    for (const label of (data.labels || []).filter((item) => !item.is_deleted)) {
        if (!labelOf.has(String(label.name).toLowerCase())) {
            const id = idFor('planify', label.id);
            upsert('labels', { id, title: String(label.name), color: PLANIFY_COLOURS[label.color] || 'violet' });
            labelOf.set(String(label.name).toLowerCase(), id);
        }
    }
    const inbox = new Set();
    for (const project of (data.projects || []).filter((item) => !item.is_deleted)) {
        if (project.inbox_project) {
            inbox.add(project.id);
            continue;
        }
        upsert('projects', {
            id: idFor('planify', project.id), title: String(project.name || 'Untitled'),
            color: PLANIFY_COLOURS[project.color] || 'violet', order: Number(project.child_order) || 0, created: Date.now(),
        });
        counts.projects += 1;
    }
    const projectOf = (id) => (!id || inbox.has(id) || !store.projects[idFor('planify', id)] ? null : idFor('planify', id));
    for (const section of (data.sections || []).filter((item) => !item.is_deleted && !item.is_archived)) {
        const project = projectOf(section.project_id);
        if (project) {
            upsert('sections', { id: idFor('planify', section.id), project, title: String(section.name || 'Untitled'), order: Number(section.section_order) || 0 });
        }
    }
    const UNITS = { 2: 'day', 3: 'week', 4: 'month', 5: 'year' };
    for (const item of (data.items || []).filter((entry) => !entry.is_deleted)) {
        let due = {};
        try {
            due = typeof item.due === 'string' ? JSON.parse(item.due) : item.due || {};
        } catch {
            // No date
        }
        const [, date, hours, minutes] = /^(\d{4}-\d{2}-\d{2})(?:T(\d{2}):(\d{2}))?/.exec(String(due.date || '')) || [];
        const unit = due.is_recurring ? UNITS[Number(due.recurrency_type)] : null;
        const section = item.section_id && store.sections[idFor('planify', item.section_id)] ? idFor('planify', item.section_id) : null;
        upsert('tasks', {
            id: idFor('planify', item.id), title: String(item.content || 'Untitled'), notes: String(item.description || ''),
            project: projectOf(item.project_id), section, parent: item.parent_id ? idFor('planify', item.parent_id) : null,
            due: date || null, time: hours ? `${hours}:${minutes}` : null, reminder: null,
            repeat: unit && date ? { every: Math.max(1, Number(due.recurrency_interval) || 1), unit } : null,
            // Planify counts priority the Todoist way, 4 being the highest
            priority: Math.min(4, Math.max(1, 5 - (Number(item.priority) || 1))),
            labels: (item.labels || []).map((name) => labelOf.get(String(name).toLowerCase())).filter(Boolean),
            pinned: Boolean(item.pinned), done: item.checked ? timeOf(item.completed_at) : null,
            created: timeOf(item.added_at), order: Number(item.child_order) || 0,
        });
        counts.tasks += 1;
    }
}

function importNotebook() {
    const found = Object.values(store.notebooks).find((notebook) => notebook.title === 'Imported' && !notebook.parent);
    if (found) {
        return found.id;
    }
    const id = crypto.randomBytes(16).toString('hex');
    store.notebooks[id] = { id, title: 'Imported', parent: null, created: Date.now(), updated: Date.now() };
    return id;
}

function importMarkdown(file, text, counts) {
    let body = text.replace(/\r\n/g, '\n');
    let title = '';
    let tags = [];
    const front = /^---\n([\s\S]*?)\n---\n?/.exec(body);
    if (front) {
        body = body.slice(front[0].length);
        const value = (name) => new RegExp(`^${name}:\\s*(.*)$`, 'm').exec(front[1])?.[1]?.trim();
        const parse = (raw) => {
            try {
                return JSON.parse(raw);
            } catch {
                return raw;
            }
        };
        title = String(parse(value('title') || '') || '');
        const list = parse(value('tags') || '');
        tags = Array.isArray(list) ? list.map(String) : [];
    }
    title ||= /^#\s+(.+)$/m.exec(body)?.[1] || path.basename(file).replace(/\.[^.]+$/, '');
    const tagIds = tags.map((name) => {
        const found = Object.values(store.tags).find((tag) => tag.title.toLowerCase() === name.toLowerCase());
        if (found) {
            return found.id;
        }
        const id = crypto.randomBytes(16).toString('hex');
        store.tags[id] = { id, title: name };
        return id;
    });
    const id = crypto.randomBytes(16).toString('hex');
    store.notes[id] = { id, notebook: importNotebook(), title, body: body.replace(/^\n+/, ''), tags: tagIds, created: Date.now(), updated: Date.now(), trashed: null };
    counts.notes += 1;
}

async function importBackup(file, passphrase, counts) {
    let backupKey = null;
    if (file.encrypted) {
        backupKey = await unwrap(passphrase, file);
        if (!backupKey) {
            return { error: 'That is not the passphrase this backup was made with.' };
        }
    }
    const packed = backupKey ? unseal(backupKey, Buffer.from(file.data, 'base64'), 'backup') : Buffer.from(file.data, 'base64');
    const { store: saved, resources } = JSON.parse(zlib.gunzipSync(packed).toString('utf8'));
    const data = normalise(saved);
    for (const [id, bytes] of Object.entries(resources || {})) {
        if (ID.test(id) && data.resources[id]) {
            await addResource(data.resources[id].name, data.resources[id].mime, Buffer.from(bytes, 'base64'), id);
            counts.attachments += 1;
        }
    }
    for (const kind of KINDS) {
        for (const item of Object.values(data[kind])) {
            if (ID.test(item?.id)) {
                store[kind][item.id] = item;
                if (counts[kind] !== undefined) {
                    counts[kind] += 1;
                }
            }
        }
    }
    return null;
}

function newCounts() {
    return { notes: 0, notebooks: 0, tasks: 0, projects: 0, attachments: 0 };
}

function finishImport(counts) {
    scheduleSave();
    computeReminders();
    return { counts, data: store };
}

async function importFiles() {
    if (!store) {
        return { error: 'Unlock your notes first.' };
    }
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
        title: 'Import',
        properties: ['openFile', 'multiSelections'],
        filters: [
            { name: 'Joplin export, Planify backup, Markdown or Notes backup', extensions: ['jex', 'json', 'md', 'markdown', 'txt', 'amnotes'] },
        ],
    });
    if (canceled) {
        return {};
    }
    const counts = newCounts();
    const skipped = [];
    for (const file of filePaths) {
        const extension = path.extname(file).toLowerCase();
        try {
            if (extension === '.jex') {
                await importJex(await fsp.readFile(file), counts);
            } else if (extension === '.amnotes') {
                const saved = JSON.parse(await fsp.readFile(file, 'utf8'));
                if (saved.format !== 'amethystora-notes-backup') {
                    throw new Error('not a Notes backup');
                }
                if (saved.encrypted) {
                    // The passphrase is asked for by the page, and the file stays here
                    pendingBackup = saved;
                    scheduleSave();
                    return { counts, data: store, passphrase: path.basename(file) };
                }
                await importBackup(saved, null, counts);
            } else if (extension === '.json') {
                const data = JSON.parse(await fsp.readFile(file, 'utf8'));
                if (!Array.isArray(data.items) || !Array.isArray(data.projects)) {
                    throw new Error('not a Planify backup');
                }
                importPlanify(data, counts);
            } else {
                importMarkdown(file, await fsp.readFile(file, 'utf8'), counts);
            }
        } catch (error) {
            skipped.push(`${path.basename(file)}: ${error.message}`);
        }
    }
    return { ...finishImport(counts), skipped };
}

async function importPending(passphrase) {
    if (!store || !pendingBackup) {
        return { error: 'Choose the backup again.' };
    }
    const counts = newCounts();
    const failed = await importBackup(pendingBackup, passphrase, counts);
    if (failed) {
        return failed;
    }
    pendingBackup = null;
    return finishImport(counts);
}

// --- Reminders ---------------------------------------------------------------------------------------

function dueTime(task) {
    const [year, month, day] = String(task.due).split('-').map(Number);
    const [hours, minutes] = String(task.time || '09:00').split(':').map(Number);
    return new Date(year, month - 1, day, hours, minutes).getTime();
}

// Titles and times only, kept in memory while locked so that a reminder still says what it is about
function computeReminders() {
    if (!store) {
        return;
    }
    const now = Date.now();
    reminders = Object.values(store.tasks)
        .filter((task) => !task.done && /^\d{4}-\d{2}-\d{2}$/.test(task.due || '') && /^\d{2}:\d{2}$/.test(task.time || '') &&
            Number.isInteger(task.reminder) && task.reminder >= 0)
        .map((task) => ({ id: task.id, title: task.title || 'A task', due: dueTime(task), at: dueTime(task) - task.reminder * 60000 }))
        .filter((reminder) => reminder.at > now - 60000);
}

function checkReminders() {
    const now = Date.now();
    for (const reminder of reminders) {
        const tag = `${reminder.id}:${reminder.at}`;
        if (reminder.at > lastCheck && reminder.at <= now && !shown.has(tag) && Notification.isSupported()) {
            shown.add(tag);
            const time = new Date(reminder.due).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const notification = new Notification({
                title: reminder.title,
                body: reminder.due > now + 30000 ? `Due at ${time}` : `Due now, ${time}`,
                urgency: 'normal',
            });
            notification.on('click', () => {
                showWindow('tasks');
                send('task', reminder.id);
            });
            notification.show();
        }
    }
    lastCheck = now;
}

function upcoming() {
    return reminders.some((reminder) => reminder.at > Date.now());
}

// --- The window --------------------------------------------------------------------------------------

function createWindow(page = '') {
    const colors = palette();
    let closing = false;
    win = new BrowserWindow({
        width: 1240,
        height: 820,
        minWidth: 780,
        minHeight: 540,
        title: 'Notes',
        backgroundColor: colors?.background || '#110c18',
        autoHideMenuBar: true,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: true,
            spellcheck: false,
        },
    });
    win.removeMenu();
    win.loadFile(path.join(__dirname, 'index.html'), { hash: page });
    win.on('focus', () => {
        lastActive = Date.now();
    });
    // What the page has not sent yet is sent before it goes
    win.on('close', (event) => {
        if (!closing) {
            event.preventDefault();
            requestFlush().finally(() => {
                closing = true;
                win?.close();
            });
        }
    });
    win.on('closed', () => {
        win = null;
    });
}

function showWindow(page = '') {
    if (!win) {
        createWindow(page);
        return;
    }
    if (win.isMinimized()) {
        win.restore();
    }
    win.show();
    win.focus();
    if (page) {
        send('open', page);
    }
}

// A theme switch replaces current/theme and rewrites current/theme.name, so the window follows it the
// way the rest of the desktop does
function watchTheme() {
    let pending = null;
    try {
        fs.watch(CURRENT, () => {
            clearTimeout(pending);
            pending = setTimeout(() => send('palette', palette()), 300);
        });
    } catch {
        // No theme applied yet: the window keeps the Amethystora colours
    }
}

// GNOME says on the session bus when the screen locks, and the notes lock with it
function watchScreenLock() {
    const monitor = spawn('gdbus', ['monitor', '--session', '--dest', 'org.gnome.ScreenSaver', '--object-path', '/org/gnome/ScreenSaver'],
        { stdio: ['ignore', 'pipe', 'ignore'] });
    monitor.on('error', () => {});
    readline.createInterface({ input: monitor.stdout }).on('line', (line) => {
        if (/ActiveChanged \(true,?\)/.test(line)) {
            lock();
        }
    });
    app.on('will-quit', () => monitor.kill());
}

function manual(page) {
    if (/^[a-z0-9-]+(#[a-z0-9-]+)?$/.test(String(page))) {
        launch('amethystora-manual', [String(page)]);
    }
}

// Wraps a handler so that a failure reaches the page as something to say rather than as an exception
function handle(channel, fn) {
    ipcMain.handle(channel, async (...args) => {
        try {
            return await fn(...args);
        } catch (error) {
            return { error: error.message };
        }
    });
}

if (!app.requestSingleInstanceLock()) {
    app.quit();
} else {
    app.on('second-instance', (_event, argv) => showWindow(pageArgument(argv)));

    app.on('web-contents-created', (_event, contents) => {
        contents.on('will-navigate', (event) => event.preventDefault());
        contents.setWindowOpenHandler(() => ({ action: 'deny' }));
    });

    handle('palette', () => palette());
    handle('state', () => describe());
    handle('create', (_event, passphrase) => create(passphrase ? String(passphrase) : null));
    handle('unlock', (_event, passphrase) => unlock(String(passphrase)));
    handle('unlock-passkey', (_event, pin) => withKey(() => unlockWithPasskey(String(pin || ''))));
    handle('passkey-add', (_event, change) => withKey(() => addPasskey({
        current: String(change?.current || ''), pin: String(change?.pin || ''),
    })));
    handle('passkey-remove', (_event, id) => removePasskey(String(id)));
    ipcMain.on('passkey-cancel', () => touching?.abort());
    handle('lock', () => lock().then(() => describe()));
    handle('encryption', (_event, change) => setEncryption({
        action: String(change?.action), current: change?.current ? String(change.current) : '', next: change?.next ? String(change.next) : '',
    }));
    handle('put', (_event, kind, items) => put(String(kind), items));
    handle('drop', (_event, kind, ids) => drop(String(kind), Array.isArray(ids) ? ids.map(String) : null));
    handle('settings', (_event, values) => setSettings(values));
    handle('attach', () => attachFiles());
    handle('attach-data', (_event, name, mime, data) => attachData(name, mime, data));
    handle('save-resource', (_event, id) => saveResource(String(id)));
    handle('export', () => exportMarkdown());
    handle('backup', () => backup());
    handle('import', () => importFiles());
    handle('import-backup', (_event, passphrase) => importPending(String(passphrase)));
    handle('pdf', async (_event, title) => {
        const { canceled, filePath } = await dialog.showSaveDialog(win, {
            title: 'Export as PDF',
            defaultPath: path.join(app.getPath('documents'), `${fileName(title)}.pdf`),
            filters: [{ name: 'PDF', extensions: ['pdf'] }],
        });
        if (canceled) {
            return {};
        }
        await fsp.writeFile(filePath, await win.webContents.printToPDF({ printBackground: false }));
        return { path: filePath };
    });
    handle('open-external', (_event, url) => {
        if (/^(https?:\/\/|mailto:)/i.test(String(url))) {
            shell.openExternal(String(url));
        }
    });
    handle('manual', (_event, page) => manual(page));
    ipcMain.on('active', () => {
        lastActive = Date.now();
    });
    ipcMain.on('flushed', () => {
        flushed?.();
        flushed = null;
    });

    app.whenReady().then(async () => {
        session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        // Attachments, decrypted here for the page's <img>, and only while the notes are open
        protocol.handle('res', async (request) => {
            const id = new URL(request.url).hostname;
            const resource = store?.resources[id];
            if (!ID.test(id) || !resource) {
                return new Response(null, { status: 404 });
            }
            try {
                return new Response(await readResource(id), { headers: { 'content-type': resource.mime } });
            } catch {
                return new Response(null, { status: 404 });
            }
        });
        try {
            await readVault();
            if (vault && !vault.encrypted) {
                store = await readData();
                await opened();
            }
        } catch (error) {
            dialog.showErrorBox('Notes', error.message);
            app.exit(1);
            return;
        }
        createWindow(pageArgument(process.argv));
        watchTheme();
        watchScreenLock();
        powerMonitor.on('suspend', () => lock());
        powerMonitor.on('lock-screen', () => lock());
        setInterval(() => {
            checkReminders();
            const minutes = store?.settings.autoLock ?? 10;
            if (store && vault?.encrypted && minutes > 0 && Date.now() - lastActive >= minutes * 60000) {
                lock();
            }
            // In the background only for reminders: once they have all gone off, so does this
            if (!win && !upcoming() && !locking) {
                app.quit();
            }
        }, 15000);
    });

    // Closing the window locks the notes. It stays running without one while a reminder is to come,
    // unless that has been turned off.
    app.on('window-all-closed', async () => {
        const background = store?.settings.background !== false;
        await flush();
        await lock();
        await saving;
        if (!background || !upcoming()) {
            app.quit();
        }
    });

    app.on('before-quit', (event) => {
        if (!quitting && (dirty || saveTimer)) {
            event.preventDefault();
            flush().finally(() => {
                quitting = true;
                app.quit();
            });
        }
    });
}
