'use strict';

// What the Electron window of Amethystora Notes wrote and read, for the Rust window's compatibility tests:
// the functions below are main.js's own, copied as they were (system_files/shared/usr/lib/amethystora-notes/
// resources/app/main.js, before the port), with only what they reach outside themselves (the window, the
// dialogs, the session's language) put in place around them. It needs nothing of Electron's, so any Node
// runs it (the fixtures were written on the Electron windows' own, 44.7.0):
//
//   node electron.js COMMAND ...
//
//   fixtures DIR             writes the fixtures the Rust tests read (tests/fixtures), once
//   demo DIR [PASSPHRASE]    a vault of sample notes and tasks dated around today, for screenshots
//   verify DIR [PASSPHRASE]  reads a vault as main.js did and prints what is in it, as JSON
//   backup FILE [PASSPHRASE] reads a backup as main.js's import did and prints what is in it, as JSON
//   import FILE              imports a .jex, Planify .json or Markdown file into an empty store and prints it
//
// Nothing here is shipped: the image has the Rust window only.

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { promisify } = require('node:util');
const zlib = require('node:zlib');
const { constants: { MAX_STRING_LENGTH } } = require('node:buffer');

const fsp = fs.promises;
const scrypt = promisify(crypto.scrypt);
// The English, as the window spoke it with no catalog
const t = (message, values = {}) => message.replace(/\{(\w+)\}/g, (match, name) => (name in values ? String(values[name]) : match));

let DIR = '';
let VAULT = '';
let RESOURCES = '';
let PLAIN = '';
let SEALED = '';
let NEXT = '';
function at(dir) {
    DIR = dir;
    VAULT = path.join(DIR, 'vault.json');
    RESOURCES = path.join(DIR, 'resources');
    PLAIN = path.join(DIR, 'data.json');
    SEALED = path.join(DIR, 'data.bin');
    NEXT = path.join(DIR, 'next');
}

let vault = null;
let key = null;
let store = null;
let dirty = false;

// --- From main.js, as it was ------------------------------------------------------------------------------

// 128 * N * r bytes of memory for every guess at the passphrase
const KDF = { name: 'scrypt', N: 2 ** 17, r: 8, p: 1 };
const MAGIC = Buffer.from('ANv1');
const KINDS = ['notebooks', 'notes', 'tags', 'revisions', 'projects', 'sections', 'tasks', 'labels'];
const ID = /^[0-9a-f]{32}$/;
const RESOURCE_LINK = /:\/([0-9a-f]{32})/g;
const RELYING_PARTY = 'amethystora-notes';

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
        throw new Error(t('The key settings in vault.json are damaged.'));
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

// The newest readable copy. An encrypted vault reads only sealed files, so that nobody can slip it notes
// in the clear.
async function readData() {
    const candidates = key ? [SEALED, `${SEALED}.bak`] : [PLAIN, `${PLAIN}.bak`];
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
            const text = key ? unseal(key, bytes, 'data') : bytes;
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
        throw new Error(t('Your notes could not be read. Nothing has been changed in {folder}.', { folder: DIR }));
    }
    return emptyStore();
}

function resourceFile(id) {
    return path.join(RESOURCES, id);
}

// Throws on an attachment in the clear while the notes are encrypted
async function readResource(id) {
    const bytes = await fsp.readFile(resourceFile(id));
    return key ? unseal(key, bytes, `resource:${id}`) : bytes;
}

function localDate(time) {
    const date = new Date(time);
    const pad = (value) => String(value).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

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
            id: idFor('joplin', folder.id), title: folder.title || t('Untitled'),
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
        upsert('tags', { id: idFor('joplin', tag.id), title: tag.title || t('tag') });
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
                id, title: note.title || t('Untitled'), notes: note.body, project: null, section: null, parent: null,
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
            upsert('labels', { id, title: String(label.name), color: Object.hasOwn(PLANIFY_COLOURS, label.color) ? PLANIFY_COLOURS[label.color] : 'violet' });
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
            id: idFor('planify', project.id), title: String(project.name || t('Untitled')),
            color: Object.hasOwn(PLANIFY_COLOURS, project.color) ? PLANIFY_COLOURS[project.color] : 'violet', order: Number(project.child_order) || 0, created: Date.now(),
        });
        counts.projects += 1;
    }
    const projectOf = (id) => (!id || inbox.has(id) || !store.projects[idFor('planify', id)] ? null : idFor('planify', id));
    for (const section of (data.sections || []).filter((item) => !item.is_deleted && !item.is_archived)) {
        const project = projectOf(section.project_id);
        if (project) {
            upsert('sections', { id: idFor('planify', section.id), project, title: String(section.name || t('Untitled')), order: Number(section.section_order) || 0 });
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
            id: idFor('planify', item.id), title: String(item.content || t('Untitled')), notes: String(item.description || ''),
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

// Found again by its name, which is why that is the same in every language
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
            return { error: t('That is not the passphrase this backup was made with.') };
        }
    }
    const packed = backupKey ? unseal(backupKey, Buffer.from(file.data, 'base64'), 'backup') : Buffer.from(file.data, 'base64');
    // No larger than the longest text there can be, which is all a backup unpacks to
    let unpacked;
    try {
        unpacked = zlib.gunzipSync(packed, { maxOutputLength: MAX_STRING_LENGTH });
    } catch {
        throw new Error(t('This backup is damaged or too large to open.'));
    }
    const { store: saved, resources } = JSON.parse(unpacked.toString('utf8'));
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

// --- Around them ---------------------------------------------------------------------------------------

const TYPES = {
    png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp',
    svg: 'image/svg+xml', avif: 'image/avif', bmp: 'image/bmp', pdf: 'application/pdf', txt: 'text/plain',
    md: 'text/markdown', zip: 'application/zip', mp3: 'audio/mpeg', ogg: 'audio/ogg', mp4: 'video/mp4',
    webm: 'video/webm', odt: 'application/vnd.oasis.opendocument.text', json: 'application/json',
};

function typeOf(name) {
    return TYPES[path.extname(name).slice(1).toLowerCase()] || 'application/octet-stream';
}

// What an import adds, kept in memory here rather than written: main.js's addResource without the file
const imported = {};
async function addResource(name, mime, bytes, id = crypto.randomBytes(16).toString('hex')) {
    imported[id] = bytes.toString('base64');
    const resource = { id, name: String(name || 'Attachment').slice(0, 200), mime: String(mime || typeOf(name)), size: bytes.length, created: Date.now() };
    store.resources[id] = resource;
    return resource;
}

// The vault main.js's create() and flush() would leave: vault.json, the data, and each attachment
async function writeVault(dir, passphrase, data, resources, passkeys = []) {
    at(dir);
    await fsp.mkdir(RESOURCES, { recursive: true, mode: 0o700 });
    let next = { format: 1, encrypted: false };
    let secret = null;
    if (passphrase) {
        secret = crypto.randomBytes(32);
        next = await wrap(passphrase, secret);
    }
    for (const passkey of passkeys) {
        // A passkey seals the data key under the secret its security key computes (addPasskey)
        passkey.key = seal(passkey.secret, secret, `passkey:${passkey.id}`).toString('base64');
        delete passkey.secret;
    }
    if (passkeys.length) {
        next.passkeys = passkeys;
    }
    await writeAtomic(VAULT, JSON.stringify(next, null, 2));
    const json = Buffer.from(JSON.stringify(data));
    await writeAtomic(secret ? SEALED : PLAIN, secret ? seal(secret, json, 'data') : json, true);
    for (const [id, bytes] of Object.entries(resources)) {
        await writeAtomic(resourceFile(id), secret ? seal(secret, bytes, `resource:${id}`) : bytes);
    }
}

// The backup main.js's backup() made
async function writeBackup(file, passphrase, data, resources) {
    let secret = null;
    let sealedVault = null;
    if (passphrase) {
        secret = crypto.randomBytes(32);
        sealedVault = await wrap(passphrase, secret);
    }
    const encoded = Object.fromEntries(Object.entries(resources).map(([id, bytes]) => [id, bytes.toString('base64')]));
    const packed = zlib.gzipSync(Buffer.from(JSON.stringify({ store: data, resources: encoded })));
    const out = { format: 'amethystora-notes-backup', version: 1, created: new Date().toISOString(), encrypted: Boolean(secret) };
    if (secret) {
        Object.assign(out, { cipher: sealedVault.cipher, kdf: sealedVault.kdf, key: sealedVault.key, data: seal(secret, packed, 'backup').toString('base64') });
    } else {
        out.data = packed.toString('base64');
    }
    await writeAtomic(file, JSON.stringify(out));
}

// A ustar archive of these files, as Joplin writes its export
function tar(files) {
    const blocks = [];
    for (const [name, bytes] of files) {
        const header = Buffer.alloc(512);
        header.write(name, 0, 100, 'utf8');
        header.write('0000644\0', 100);
        header.write('0001750\0', 108);
        header.write('0001750\0', 116);
        header.write(`${bytes.length.toString(8).padStart(11, '0')}\0`, 124);
        header.write(`${Math.floor(Date.UTC(2024, 4, 1) / 1000).toString(8).padStart(11, '0')}\0`, 136);
        header.write('        ', 148);
        header.write('0', 156);
        header.write('ustar\0', 257);
        header.write('00', 263);
        let sum = 0;
        for (const byte of header) {
            sum += byte;
        }
        header.write(`${sum.toString(8).padStart(6, '0')}\0 `, 148);
        blocks.push(header, bytes, Buffer.alloc((512 - (bytes.length % 512)) % 512));
    }
    blocks.push(Buffer.alloc(1024));
    return Buffer.concat(blocks);
}

// One of Joplin's items as it serialises them: the title, the body, then the properties
function joplin(title, body, props) {
    const lines = Object.entries(props).map(([name, value]) => `${name}: ${value}`).join('\n');
    return Buffer.from(body === null ? `${title}\n\n${lines}` : `${title}\n\n${body}\n\n${lines}`);
}

// A picture, a gradient of the theme's violets, made here as a PNG, and a few lines of text, as attachments
function png(width, height) {
    const table = [...Array(256).keys()].map((n) => {
        let c = n;
        for (let k = 0; k < 8; k += 1) {
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        }
        return c >>> 0;
    });
    const crc = (bytes) => {
        let c = 0xffffffff;
        for (const byte of bytes) {
            c = table[(c ^ byte) & 0xff] ^ (c >>> 8);
        }
        return (c ^ 0xffffffff) >>> 0;
    };
    const chunk = (type, body) => {
        const head = Buffer.alloc(4);
        head.writeUInt32BE(body.length);
        const tail = Buffer.alloc(4);
        tail.writeUInt32BE(crc(Buffer.concat([Buffer.from(type), body])));
        return Buffer.concat([head, Buffer.from(type), body, tail]);
    };
    const header = Buffer.alloc(13);
    header.writeUInt32BE(width, 0);
    header.writeUInt32BE(height, 4);
    header[8] = 8;
    header[9] = 2;
    const rows = [];
    for (let y = 0; y < height; y += 1) {
        const row = Buffer.alloc(1 + width * 3);
        for (let x = 0; x < width; x += 1) {
            row[1 + x * 3] = 93 + Math.round((x / width) * 100);
            row[2 + x * 3] = 26 + Math.round((y / height) * 60);
            row[3 + x * 3] = 196 + Math.round((x / width) * 50);
        }
        rows.push(row);
    }
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header),
        chunk("IDAT", zlib.deflateSync(Buffer.concat(rows))), chunk("IEND", Buffer.alloc(0))]);
}
const PNG = png(160, 100);
const TEXT = Buffer.from('Milk, eggs, flour.\nSomething for the weekend.\n');

const FIXED = {
    notebook: '0b1e0000000000000000000000000001',
    child: '0b1e0000000000000000000000000002',
    note: '0e7e0000000000000000000000000001',
    note2: '0e7e0000000000000000000000000002',
    trashed: '0e7e0000000000000000000000000003',
    tag: '7a90000000000000000000000000000a',
    revision: 'e5000000000000000000000000000001',
    project: '9e0c0000000000000000000000000001',
    section: '5ec00000000000000000000000000001',
    task: '7a5c0000000000000000000000000001',
    subtask: '7a5c0000000000000000000000000002',
    done: '7a5c0000000000000000000000000003',
    label: '1abe1000000000000000000000000001',
    picture: 'a77ac000000000000000000000000001',
    list: 'a77ac000000000000000000000000002',
    passkey: 'feed0000000000000000000000000001',
};

// The notes and tasks every fixture holds: one of each thing main.js keeps, with fixed ids and times
function sample() {
    const data = emptyStore();
    const time = Date.UTC(2026, 9, 1, 9, 30);
    data.settings = { autoLock: 15, background: true, layout: 'split', noteSort: 'updated' };
    data.notebooks[FIXED.notebook] = { id: FIXED.notebook, title: 'Notes', parent: null, created: time, updated: time };
    data.notebooks[FIXED.child] = { id: FIXED.child, title: 'Recipes — été', parent: FIXED.notebook, created: time, updated: time };
    data.tags[FIXED.tag] = { id: FIXED.tag, title: 'kitchen' };
    data.notes[FIXED.note] = {
        id: FIXED.note, notebook: FIXED.child, title: 'Pancakes 🥞',
        body: `# Pancakes\n\n- [ ] eggs\n- [x] flour\n\n![the pan](:/${FIXED.picture})\n\n[shopping list](:/${FIXED.list})\n\n<b>not bold</b>`,
        tags: [FIXED.tag], created: time, updated: time + 60000, trashed: null,
    };
    data.notes[FIXED.note2] = {
        id: FIXED.note2, notebook: FIXED.notebook, title: 'مرحبا', body: 'نص عربي\nsecond line', tags: [], created: time, updated: time, trashed: null,
    };
    data.notes[FIXED.trashed] = {
        id: FIXED.trashed, notebook: FIXED.notebook, title: 'Old', body: 'gone', tags: [], created: time, updated: time, trashed: time + 120000,
    };
    data.revisions[FIXED.revision] = { id: FIXED.revision, note: FIXED.note, title: 'Pancakes', body: 'first draft', saved: time - 3600000 };
    data.projects[FIXED.project] = { id: FIXED.project, title: 'Home', color: 'teal', order: time, created: time };
    data.sections[FIXED.section] = { id: FIXED.section, project: FIXED.project, title: 'Weekend', order: time };
    data.labels[FIXED.label] = { id: FIXED.label, title: 'errand', color: 'orange' };
    data.tasks[FIXED.task] = {
        id: FIXED.task, title: 'Buy flour', notes: `See [the list](:/${FIXED.list})`, project: FIXED.project, section: FIXED.section, parent: null,
        due: '2026-10-20', time: '17:30', repeat: { every: 2, unit: 'week' }, reminder: 15, priority: 1, labels: [FIXED.label],
        pinned: true, done: null, created: time, order: time,
    };
    data.tasks[FIXED.subtask] = {
        id: FIXED.subtask, title: 'Find the shop', notes: '', project: FIXED.project, section: FIXED.section, parent: FIXED.task,
        due: null, time: null, repeat: null, reminder: null, priority: 4, labels: [], pinned: false, done: null, created: time, order: time + 1,
    };
    data.tasks[FIXED.done] = {
        id: FIXED.done, title: 'Call Sam', notes: '', project: null, section: null, parent: null,
        due: '2026-10-01', time: null, repeat: null, reminder: null, priority: 3, labels: [], pinned: false, done: time + 5000, created: time, order: time,
    };
    data.resources[FIXED.picture] = { id: FIXED.picture, name: 'pan.png', mime: 'image/png', size: PNG.length, created: time };
    data.resources[FIXED.list] = { id: FIXED.list, name: 'list.txt', mime: 'text/plain', size: TEXT.length, created: time };
    return { data, resources: { [FIXED.picture]: PNG, [FIXED.list]: TEXT } };
}

// The secret the stand-in fido2-assert gives for the fixtures' passkey, which a real key would compute
const PASSKEY_SECRET = crypto.createHash('sha256').update('amethystora-notes test passkey').digest();
const PASSKEY_CREDENTIAL = Buffer.from('a credential the stand-in security key made').toString('base64');
const PASSKEY_SALT = Buffer.alloc(32, 7).toString('base64');

async function fixtures(dir) {
    const passphrase = 'correct horse battery staple';
    const { data, resources } = sample();
    await writeVault(path.join(dir, 'encrypted'), passphrase, data, resources, [{
        id: FIXED.passkey, name: 'YubiKey 5 NFC', created: Date.UTC(2026, 9, 2), protect: 3,
        credential: PASSKEY_CREDENTIAL, salt: PASSKEY_SALT, secret: PASSKEY_SECRET,
    }]);
    await writeVault(path.join(dir, 'plain'), null, data, resources);
    await writeBackup(path.join(dir, 'backup-encrypted.amnotes'), passphrase, data, resources);
    await writeBackup(path.join(dir, 'backup-plain.amnotes'), null, data, resources);
    // A Joplin export: two notebooks, one inside the other, two notes, a to-do, a tag and a picture
    const created = '2024-05-01T08:00:00.000Z';
    const props = (id, type, extra) => ({ id, parent_id: '', created_time: created, updated_time: '2024-05-02T08:00:00.000Z', ...extra, type_: type });
    const folder = 'f0000000000000000000000000000001';
    const inner = 'f0000000000000000000000000000002';
    const picture = 'c0000000000000000000000000000001';
    const tag = 'b0000000000000000000000000000001';
    fs.writeFileSync(path.join(dir, 'sample.jex'), tar([
        [`${folder}.md`, joplin('Work', null, props(folder, 2, { icon: '' }))],
        [`${inner}.md`, joplin('Meetings', null, props(inner, 2, { parent_id: folder }))],
        ['10000000000000000000000000000001.md', joplin('Standup', `Notes from the standup.\n\n![board](:/${picture})`,
            props('10000000000000000000000000000001', 1, { parent_id: inner, is_todo: 0, todo_due: 0, todo_completed: 0, markup_language: 1 }))],
        ['10000000000000000000000000000002.md', joplin('Loose note', 'Not in any notebook here',
            props('10000000000000000000000000000002', 1, { parent_id: 'ffffffffffffffffffffffffffffffff', is_todo: 0 }))],
        ['10000000000000000000000000000003.md', joplin('Send the report', 'By Friday',
            props('10000000000000000000000000000003', 1, { parent_id: folder, is_todo: 1, todo_due: Date.UTC(2024, 5, 7, 15, 45), todo_completed: 0 }))],
        [`${picture}.md`, joplin('board.png', null, props(picture, 4, { mime: 'image/png', filename: '', file_extension: 'png', size: PNG.length }))],
        [`resources/${picture}.png`, PNG],
        [`${tag}.md`, joplin('meetings', null, props(tag, 5, {}))],
        ['d0000000000000000000000000000001.md', joplin('', null, props('d0000000000000000000000000000001', 6, {
            note_id: '10000000000000000000000000000001', tag_id: tag,
        }))],
    ]));
    // A Planify backup: the inbox, a project with a section, labels, a repeating task with a subtask
    fs.writeFileSync(path.join(dir, 'planify.json'), JSON.stringify({
        version: '2.0', date: '2024-05-03T10:00:00',
        labels: [{ id: 'L1', name: 'Phone', color: 'berry_red', is_deleted: false }, { id: 'L2', name: 'Old', color: 'blue', is_deleted: true }],
        projects: [
            { id: 'inbox-1', name: 'Inbox', color: 'blue', inbox_project: true, child_order: 0, is_deleted: false },
            { id: 'P1', name: 'Garden', color: 'olive_green', inbox_project: false, child_order: 3, is_deleted: false },
        ],
        sections: [{ id: 'S1', project_id: 'P1', name: 'Spring', section_order: 1, is_deleted: false, is_archived: false }],
        items: [
            { id: 'I1', content: 'Water the roses', description: 'Before nine', due: JSON.stringify({ date: '2024-05-04T08:30:00', is_recurring: true, recurrency_type: 2, recurrency_interval: 3 }),
                added_at: '2024-05-01T10:00:00', completed_at: '', checked: false, priority: 4, project_id: 'P1', section_id: 'S1', parent_id: '', labels: ['phone'], pinned: true, child_order: 2, is_deleted: false },
            { id: 'I2', content: 'Buy seeds', description: '', due: JSON.stringify({ date: '' }), added_at: '2024-05-01T11:00:00', completed_at: '2024-05-02T09:00:00',
                checked: true, priority: 1, project_id: 'P1', section_id: '', parent_id: 'I1', labels: [], pinned: false, child_order: 1, is_deleted: false },
            { id: 'I3', content: 'Call the plumber', description: '', due: '{"date":"2024-05-06"}', added_at: '2024-05-02T08:00:00', checked: false,
                priority: 3, project_id: 'inbox-1', section_id: '', parent_id: '', labels: ['Phone', 'Old'], pinned: false, child_order: 0, is_deleted: false },
        ],
    }, null, 2));
    fs.writeFileSync(path.join(dir, 'markdown.md'), '---\ntitle: "Front matter"\ntags: ["kitchen", "new one"]\n---\n\n\nThe body.\n');
    fs.writeFileSync(path.join(dir, 'passkey.json'), JSON.stringify({
        secret: PASSKEY_SECRET.toString('base64'), credential: PASSKEY_CREDENTIAL, salt: PASSKEY_SALT, passphrase,
    }, null, 2));
}

// --- Notes and tasks dated around today, for screenshots -------------------------------------------------

function demoId(n) {
    return crypto.createHash('sha256').update(`demo:${n}`).digest('hex').slice(0, 32);
}

async function demo(dir, passphrase) {
    const data = emptyStore();
    const now = Date.now();
    const day = (offset) => localDate(now + offset * 86400000);
    const ids = {};
    const id = (name) => (ids[name] ||= demoId(name));
    data.settings = { layout: 'split' };
    const notebook = (name, title, parent = null) => {
        data.notebooks[id(name)] = { id: id(name), title, parent: parent && id(parent), created: now - 30 * 86400000, updated: now - 30 * 86400000 };
    };
    notebook('notes', 'Notes');
    notebook('work', 'Work');
    notebook('meetings', 'Meetings', 'work');
    notebook('home', 'Home');
    for (const [name, title] of [['kitchen', 'kitchen'], ['ideas', 'ideas'], ['travel', 'travel']]) {
        data.tags[id(name)] = { id: id(name), title };
    }
    const note = (name, title, body, notebookName, ago, tags = [], extra = {}) => {
        data.notes[id(name)] = {
            id: id(name), notebook: id(notebookName), title, body, tags: tags.map(id),
            created: now - ago - 86400000, updated: now - ago, trashed: null, ...extra,
        };
    };
    const picture = id('picture');
    data.resources[picture] = { id: picture, name: 'pan.png', mime: 'image/png', size: PNG.length, created: now - 86400000 };
    const list = id('list');
    data.resources[list] = { id: list, name: 'list.txt', mime: 'text/plain', size: TEXT.length, created: now - 86400000 };
    note('pancakes', 'Sunday pancakes', `# Sunday pancakes\n\nThe **fluffy** kind, for four. Mix the dry things first, then the _wet_ ones.\n\n## What it takes\n\n- [x] 200 g flour\n- [ ] 2 eggs\n- [ ] 300 ml milk\n- a pinch of \`salt\`\n\n![the pan](:/${picture})\n\n> Let the batter rest for ten minutes.\n\n\`\`\`\nheat: medium\ntime: 2 min a side\n\`\`\`\n\n[shopping list](:/${list})\n`, 'home', 20 * 60000, ['kitchen']);
    note('standup', 'Standup, Monday', 'Notes from the standup.\n\n1. The release is on track\n2. Testing starts on Wednesday\n3. Sam is away next week', 'meetings', 3 * 3600000, ['ideas']);
    note('trip', 'Trip to Lisbon', 'Flights are booked. Hotel near the river, three nights.\n\nThings to see: the tiles museum, Belém, a fado evening.', 'notes', 2 * 86400000, ['travel', 'ideas']);
    note('books', 'Books to read', '- The Left Hand of Darkness\n- Piranesi\n- The Dispossessed', 'notes', 5 * 86400000);
    note('plan', 'Quarter plan', 'Three things this quarter: ship the notes app, write the docs, and take a week off.', 'work', 9 * 86400000);
    note('arabic', 'ملاحظة بالعربية', 'هذه ملاحظة مكتوبة بالعربية، لترى كيف تُعرض.', 'notes', 12 * 86400000);
    note('old', 'Old draft', 'Nothing worth keeping.', 'notes', 15 * 86400000, [], { trashed: now - 3600000 });
    data.revisions[id('rev1')] = { id: id('rev1'), note: id('pancakes'), title: 'Pancakes', body: 'Flour, eggs, milk.', saved: now - 2 * 86400000 };
    data.revisions[id('rev2')] = { id: id('rev2'), note: id('pancakes'), title: 'Sunday pancakes', body: 'Flour, eggs, milk, salt.\n\nRest the batter.', saved: now - 86400000 };
    const project = (name, title, color, order) => {
        data.projects[id(name)] = { id: id(name), title, color, order, created: now - 20 * 86400000 };
    };
    project('house', 'House', 'teal', 1);
    project('launch', 'Launch', 'violet', 2);
    data.sections[id('weekend')] = { id: id('weekend'), project: id('house'), title: 'This weekend', order: 1 };
    data.sections[id('later')] = { id: id('later'), project: id('house'), title: 'Some day', order: 2 };
    data.labels[id('errand')] = { id: id('errand'), title: 'errand', color: 'orange' };
    data.labels[id('phone')] = { id: id('phone'), title: 'phone', color: 'blue' };
    let order = 0;
    const task = (name, title, fields = {}) => {
        order += 1;
        data.tasks[id(name)] = {
            id: id(name), title, notes: '', project: null, section: null, parent: null, due: null, time: null, repeat: null,
            reminder: null, priority: 4, labels: [], pinned: false, done: null, created: now - 86400000 * 3, order: now - 100000 + order,
            ...fields,
        };
    };
    task('flour', 'Buy flour and eggs', { due: day(0), time: '17:30', reminder: 15, priority: 2, labels: [id('errand')], project: id('house'), section: id('weekend') });
    task('call', 'Call the plumber', { due: day(-1), priority: 1, labels: [id('phone')] });
    task('bins', 'Put the bins out', { due: day(0), repeat: { every: 1, unit: 'week' }, project: id('house') });
    task('report', 'Write the report', { due: day(2), time: '10:00', notes: 'Two pages, with the figures from the spring.', project: id('launch'), priority: 3 });
    task('slides', 'Make the slides', { due: day(4), project: id('launch'), pinned: true });
    task('draft', 'First draft', { parent: id('report'), project: id('launch') });
    task('figures', 'Check the figures', { parent: id('report'), project: id('launch'), done: now - 3600000 });
    task('paint', 'Paint the fence', { project: id('house'), section: id('later') });
    task('read', 'Read Piranesi', {});
    task('dentist', 'Book the dentist', { done: now - 2 * 3600000, priority: 3 });
    task('passport', 'Renew the passport', { due: day(9), labels: [id('errand')] });
    const resources = { [picture]: PNG, [list]: TEXT };
    await writeVault(dir, passphrase || null, data, resources);
}

// --- Reading back, as main.js did ----------------------------------------------------------------------

async function verify(dir, passphrase) {
    at(dir);
    vault = JSON.parse(await fsp.readFile(VAULT, 'utf8'));
    key = null;
    if (vault.encrypted) {
        key = await unwrap(passphrase);
        if (!key) {
            throw new Error(t('That is not the passphrase.'));
        }
    }
    dirty = false;
    store = await readData();
    const resources = {};
    for (const id of Object.keys(store.resources)) {
        resources[id] = (await readResource(id)).toString('base64');
    }
    const passkeys = (vault.passkeys || []).map((passkey) => {
        const own = { ...passkey };
        delete own.key;
        return own;
    });
    // Which files there are: an encrypted vault keeps no copy in the clear
    const files = fs.readdirSync(DIR).filter((name) => name !== 'resources').sort();
    return { encrypted: Boolean(vault.encrypted), fromBackup: dirty, files, passkeys, store, resources };
}

async function readBackup(file, passphrase) {
    const saved = JSON.parse(await fsp.readFile(file, 'utf8'));
    if (saved.format !== 'amethystora-notes-backup') {
        throw new Error(t('it is not a Notes backup'));
    }
    store = emptyStore();
    const counts = newCounts();
    const failed = await importBackup(saved, passphrase, counts);
    if (failed) {
        throw new Error(failed.error);
    }
    return { encrypted: Boolean(saved.encrypted), counts, store, resources: imported };
}

async function importOne(file) {
    store = emptyStore();
    const counts = newCounts();
    const extension = path.extname(file).toLowerCase();
    if (extension === '.jex') {
        await importJex(await fsp.readFile(file), counts);
    } else if (extension === '.json') {
        importPlanify(JSON.parse(await fsp.readFile(file, 'utf8')), counts);
    } else {
        importMarkdown(file, await fsp.readFile(file, 'utf8'), counts);
    }
    return { counts, store, resources: imported };
}

// Whether a passkey in vault.json seals the same data key the passphrase opens, under the secret given
async function passkey(dir, passphrase, id, secretBase64) {
    at(dir);
    vault = JSON.parse(await fsp.readFile(VAULT, 'utf8'));
    const data = await unwrap(passphrase);
    const entry = (vault.passkeys || []).find((item) => item.id === id);
    const opening = unseal(Buffer.from(secretBase64, 'base64'), Buffer.from(entry.key, 'base64'), `passkey:${entry.id}`);
    return { opens: Boolean(data) && opening.equals(data), entry: { ...entry, key: undefined } };
}

async function main() {
    const [command, target, passphrase, ...rest] = process.argv.slice(2);
    let result;
    if (command === 'passkey') {
        process.stdout.write(`${JSON.stringify(await passkey(target, passphrase, ...rest), null, 2)}\n`);
        return;
    }
    if (command === 'fixtures') {
        await fixtures(target);
        return;
    }
    if (command === 'demo') {
        await demo(target, passphrase);
        return;
    }
    if (command === 'verify') {
        result = await verify(target, passphrase);
    } else if (command === 'backup') {
        result = await readBackup(target, passphrase);
    } else if (command === 'import') {
        result = await importOne(target);
    } else {
        throw new Error(`no such command: ${command}`);
    }
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
});
