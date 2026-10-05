'use strict';

// The page of Amethystora Notes. The notes and tasks belong to main.js, which keeps them on disk, sealed
// when they are encrypted; the page holds a copy while they are open and sends every change back as it
// is made. Everything shown is built as elements with text in them, except a note's Markdown, which
// marked renders with any HTML in it shown as text rather than run.

// The session's language (i18n.js): every sentence below is the English, looked up in its catalog
const t = I18N.use(window.notes.locale);
t.page(document);

const main = document.getElementById('main');
const nav = document.getElementById('nav');
const search = document.getElementById('search');
const lockButton = document.getElementById('lock');
const todayCount = document.getElementById('today-count');
const toasts = document.getElementById('toasts');
const modeButtons = [...document.querySelectorAll('.modes [data-mode]')];

const KINDS = ['notebooks', 'notes', 'tags', 'revisions', 'projects', 'sections', 'tasks', 'labels'];
// A version of a note is kept when it is changed after this long untouched
const REVISION_GAP = 10 * 60000;
const REVISIONS_KEPT = 30;
const COLORS = ['violet', 'blue', 'teal', 'green', 'yellow', 'orange', 'red', 'pink', 'slate'];
// What the colour menu calls each of them
const COLOR_NAMES = {
    violet: t('Violet'), blue: t('Blue'), teal: t('Teal'), green: t('Green'), yellow: t('Yellow'),
    orange: t('Orange'), red: t('Red'), pink: t('Pink'), slate: t('Slate'),
};
const PRIORITIES = { 1: t('Priority 1'), 2: t('Priority 2'), 3: t('Priority 3'), 4: t('No priority') };
const REMINDERS = [
    [null, t('No reminder')],
    [0, t('At the time')],
    ...[5, 15, 30].map((count) => [count, t('{count, plural, one {# minute before} other {# minutes before}}', { count })]),
    [60, t('{count, plural, one {# hour before} other {# hours before}}', { count: 1 })],
    [1440, t('{count, plural, one {# day before} other {# days before}}', { count: 1 })],
];
// The units a task repeats in, and what the repeat menu says for each: "Every week", "Every 2 weeks"
const UNITS = {
    day: (count) => t('{count, plural, =1 {Every day} other {Every # days}}', { count }),
    week: (count) => t('{count, plural, =1 {Every week} other {Every # weeks}}', { count }),
    month: (count) => t('{count, plural, =1 {Every month} other {Every # months}}', { count }),
    year: (count) => t('{count, plural, =1 {Every year} other {Every # years}}', { count }),
};

const db = {};
const ui = {
    status: 'loading',
    encrypted: false,
    passkeys: [],
    dir: '',
    mode: 'notes',
    notesView: { type: 'all' },
    note: null,
    tasksView: { type: 'today' },
    task: null,
    query: '',
    collapsed: [],
    showDone: false,
};

function resetDb(data) {
    for (const kind of [...KINDS, 'resources']) {
        db[kind] = { ...(data?.[kind] || {}) };
    }
    db.settings = { ...(data?.settings || {}) };
    savedNotes.clear();
}

// --- Building blocks ---------------------------------------------------------------------------------

function h(tag, attributes = {}, ...children) {
    const node = document.createElement(tag);
    for (const [name, value] of Object.entries(attributes)) {
        if (value === false || value === null || value === undefined) {
            continue;
        }
        if (name.startsWith('on')) {
            node.addEventListener(name.slice(2), value);
        } else if (name === 'value') {
            node.value = value;
        } else {
            node.setAttribute(name, value === true ? '' : value);
        }
    }
    node.append(...children.flat(Infinity).filter((child) => child !== null && child !== undefined && child !== false));
    return node;
}

const SVG = 'http://www.w3.org/2000/svg';

// An icon from the sprite in index.html
function icon(name, size = 20, className = '') {
    const svg = document.createElementNS(SVG, 'svg');
    svg.setAttribute('class', `icon ${className}`.trim());
    svg.setAttribute('width', size);
    svg.setAttribute('height', size);
    svg.setAttribute('aria-hidden', 'true');
    const use = document.createElementNS(SVG, 'use');
    use.setAttribute('href', `#i-${name}`);
    svg.append(use);
    return svg;
}

function button(label, onclick, { icon: name, small, primary, danger, disabled, title, type = 'button' } = {}) {
    const classes = ['btn', small && 'small', primary && 'primary', danger && 'danger'].filter(Boolean).join(' ');
    return h('button', { type, class: classes, disabled: Boolean(disabled), title, onclick },
        name ? icon(name, 16) : null, h('span', {}, label));
}

function linkButton(label, onclick, { icon: name, quiet, small } = {}) {
    const classes = ['link', quiet && 'quiet', small && 'small'].filter(Boolean).join(' ');
    return h('button', { type: 'button', class: classes, onclick }, name ? icon(name, 16) : null, h('span', {}, label));
}

function iconButton(name, label, onclick, { active, className = '' } = {}) {
    return h('button', { type: 'button', class: `icon-btn ${className}`.trim(), title: label, 'aria-label': label,
        'aria-pressed': active === undefined ? null : String(Boolean(active)), onclick }, icon(name, 18));
}

function newId() {
    return [...crypto.getRandomValues(new Uint8Array(16))].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function debounce(fn, wait) {
    let timer = null;
    const wrapped = (...args) => {
        clearTimeout(timer);
        timer = setTimeout(() => fn(...args), wait);
    };
    wrapped.cancel = () => clearTimeout(timer);
    return wrapped;
}

function byTitle(a, b) {
    return String(a.title || '').localeCompare(String(b.title || ''), undefined, { sensitivity: 'base', numeric: true });
}

// --- Dates -------------------------------------------------------------------------------------------

function pad(value) {
    return String(value).padStart(2, '0');
}

function isoDate(date) {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function today() {
    return isoDate(new Date());
}

function parseDate(iso) {
    const [year, month, day] = String(iso).split('-').map(Number);
    return new Date(year, month - 1, day);
}

function addDays(iso, days) {
    const date = parseDate(iso);
    date.setDate(date.getDate() + days);
    return isoDate(date);
}

// The next date of a repeating task. A month that has no such day ends on its last one.
function addInterval(iso, repeat) {
    const date = parseDate(iso);
    const every = Math.max(1, repeat.every || 1);
    const day = date.getDate();
    if (repeat.unit === 'day') {
        date.setDate(day + every);
    } else if (repeat.unit === 'week') {
        date.setDate(day + every * 7);
    } else if (repeat.unit === 'month' || repeat.unit === 'year') {
        date.setDate(1);
        date.setMonth(date.getMonth() + (repeat.unit === 'month' ? every : every * 12));
        const last = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
        date.setDate(Math.min(day, last));
    }
    return isoDate(date);
}

// A label starting with a capital, where the language has them: the words for days are written to sit
// inside a sentence ("today", "vendredi")
function capital(text) {
    return text.charAt(0).toLocaleUpperCase(t.locale) + text.slice(1);
}

// A day as a label, in the language's words: "Today", "Friday", "Mon 12 Oct"
function dayLabel(iso, { long = false } = {}) {
    const now = today();
    const near = [0, 1, -1].find((days) => iso === addDays(now, days));
    if (near !== undefined) {
        return capital(t.days(near));
    }
    const date = parseDate(iso);
    if (iso > now && iso <= addDays(now, 6)) {
        return capital(date.toLocaleDateString(t.locale, { weekday: 'long' }));
    }
    const sameYear = date.getFullYear() === new Date().getFullYear();
    return capital(date.toLocaleDateString(t.locale, { weekday: long ? 'long' : 'short', day: 'numeric', month: long ? 'long' : 'short', year: sameYear ? undefined : 'numeric' }));
}

function timeLabel(time) {
    const [hours, minutes] = String(time).split(':').map(Number);
    return new Date(2000, 0, 1, hours, minutes).toLocaleTimeString(t.locale, { hour: 'numeric', minute: '2-digit' });
}

function whenLabel(time) {
    const date = new Date(time);
    if (isoDate(date) === today()) {
        return date.toLocaleTimeString(t.locale, { hour: 'numeric', minute: '2-digit' });
    }
    const sameYear = date.getFullYear() === new Date().getFullYear();
    return date.toLocaleDateString(t.locale, { day: 'numeric', month: 'short', year: sameYear ? undefined : 'numeric' });
}

function stamp(time) {
    return new Date(time).toLocaleString(t.locale, { dateStyle: 'medium', timeStyle: 'short' });
}

// --- Colours -----------------------------------------------------------------------------------------

function luminance(hex) {
    const [r, g, b] = [1, 3, 5]
        .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
        .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function applyPalette(colors) {
    const style = document.documentElement.style;
    const variables = {
        background: '--bg',
        foreground: '--fg',
        accent: '--accent',
        color0: '--surface',
        color8: '--muted',
        selection_background: '--selection',
        selection_foreground: '--selection-fg',
        color1: '--bad',
        color2: '--ok',
        color3: '--warn',
    };
    for (const [name, variable] of Object.entries(variables)) {
        if (colors?.[name]) {
            style.setProperty(variable, colors[name]);
        } else {
            style.removeProperty(variable);
        }
    }
    // Text on the accent in whichever of black and white reads better against it
    if (colors?.accent) {
        style.setProperty('--on-accent', luminance(colors.accent) > 0.18 ? '#000000' : '#ffffff');
    } else {
        style.removeProperty('--on-accent');
    }
    if (colors) {
        document.documentElement.dataset.mode = colors.light ? 'light' : 'dark';
    } else {
        delete document.documentElement.dataset.mode;
    }
}

// --- Saving ------------------------------------------------------------------------------------------

// What has changed and not been sent yet, by kind and id
const pending = new Map();
let pendingTimer = null;
// Each note as it was last sent, to tell when a change starts a new version
const savedNotes = new Map();

function save(kind, item, { now = false } = {}) {
    db[kind][item.id] = item;
    pending.set(`${kind}:${item.id}`, [kind, item]);
    clearTimeout(pendingTimer);
    pendingTimer = setTimeout(commit, now ? 0 : 350);
}

function remove(kind, ids) {
    if (!ids.length) {
        return;
    }
    for (const id of ids) {
        delete db[kind][id];
        pending.delete(`${kind}:${id}`);
    }
    commit();
    window.notes.drop(kind, ids);
}

function commit() {
    clearTimeout(pendingTimer);
    pendingTimer = null;
    const byKind = {};
    for (const [kind, item] of pending.values()) {
        (byKind[kind] ||= []).push(item);
    }
    pending.clear();
    for (const note of byKind.notes || []) {
        const revision = versionOf(note);
        if (revision) {
            db.revisions[revision.id] = revision;
            (byKind.revisions ||= []).push(revision);
        }
    }
    for (const [kind, items] of Object.entries(byKind)) {
        window.notes.put(kind, items).then((result) => {
            if (result?.error) {
                toast(result.error);
            }
        });
    }
    pruneRevisions(byKind.revisions || []);
}

// The note as it was, when this change comes after long enough untouched to count as a new sitting
function versionOf(note) {
    const before = savedNotes.get(note.id);
    savedNotes.set(note.id, { title: note.title, body: note.body, updated: note.updated });
    if (!before || (before.title === note.title && before.body === note.body) || note.updated - before.updated < REVISION_GAP) {
        return null;
    }
    return { id: newId(), note: note.id, title: before.title, body: before.body, saved: before.updated };
}

function pruneRevisions(added) {
    for (const noteId of new Set(added.map((revision) => revision.note))) {
        const old = Object.values(db.revisions).filter((revision) => revision.note === noteId)
            .sort((a, b) => b.saved - a.saved).slice(REVISIONS_KEPT);
        remove('revisions', old.map((revision) => revision.id));
    }
}

// Remembers the note as it is before the first change to it here
function editNote(note, changes) {
    if (!savedNotes.has(note.id)) {
        savedNotes.set(note.id, { title: note.title, body: note.body, updated: note.updated });
    }
    Object.assign(note, changes, { updated: Date.now() });
    save('notes', note);
}

function saveTask(task, changes, options) {
    Object.assign(task, changes);
    save('tasks', task, options);
}

// --- Menus, dialogs and toasts -----------------------------------------------------------------------

let openMenu = null;

function closeMenu() {
    openMenu?.remove();
    openMenu = null;
}

function menu(anchor, items) {
    closeMenu();
    const node = h('div', { class: 'menu', role: 'menu' }, items.filter(Boolean).map((item) => (item === '-'
        ? h('div', { class: 'menu-sep' })
        : h('button', {
            type: 'button', role: 'menuitem', class: item.danger ? 'danger' : null, 'data-color': item.color || null,
            onclick: () => {
                closeMenu();
                item.run();
            },
        }, item.color ? h('span', { class: 'dot' }) : item.icon ? icon(item.icon, 16) : h('span', { class: 'menu-gap' }),
        h('span', { class: 'grow' }, item.label), item.checked ? icon('mark-ok', 15, 'menu-check') : null))));
    document.body.append(node);
    const rect = anchor.getBoundingClientRect();
    const width = node.offsetWidth;
    const height = node.offsetHeight;
    // Lined up with the anchor's start, which is its right edge in a language written right to left
    const start = t.dir === 'rtl' ? rect.right - width : rect.left;
    node.style.left = `${Math.max(8, Math.min(start, window.innerWidth - width - 8))}px`;
    node.style.top = `${rect.bottom + height + 6 > window.innerHeight ? Math.max(8, rect.top - height - 6) : rect.bottom + 6}px`;
    openMenu = node;
    node.querySelector('button')?.focus();
}

document.addEventListener('mousedown', (event) => {
    if (openMenu && !openMenu.contains(event.target)) {
        closeMenu();
    }
}, true);

// A modal dialog. An action's value is what it resolves to; a function is called for it, and returning
// undefined keeps the dialog open, for a value that is not right yet.
function modal({ title, text, body = [], actions, wide = false }) {
    return new Promise((resolve) => {
        const dialog = h('dialog', { class: `modal${wide ? ' wide' : ''}` });
        const done = (value) => {
            dialog.close();
            dialog.remove();
            resolve(value);
        };
        const choose = async (action) => {
            const value = typeof action.value === 'function' ? await action.value() : action.value;
            if (value !== undefined) {
                done(value);
            }
        };
        const primary = actions.find((action) => action.primary);
        dialog.append(h('form', {
            method: 'dialog',
            onsubmit: (event) => {
                event.preventDefault();
                if (primary) {
                    choose(primary);
                }
            },
        },
        h('h2', {}, title),
        text ? h('p', { class: 'modal-text' }, text) : null,
        body,
        h('div', { class: 'modal-actions' }, actions.map((action) => h('button', {
            type: action.primary ? 'submit' : 'button',
            class: `btn${action.primary ? ' primary' : ''}${action.danger ? ' danger' : ''}`,
            onclick: action.primary ? null : () => choose(action),
        }, action.label)))));
        dialog.addEventListener('cancel', (event) => {
            event.preventDefault();
            done(null);
        });
        document.body.append(dialog);
        dialog.showModal();
        (dialog.querySelector('input, textarea, select') || dialog.querySelector('.btn.primary'))?.focus();
    });
}

function ask({ title, label, value = '', confirm = t('Save'), text }) {
    const input = h('input', { class: 'field', type: 'text', value, placeholder: label, 'aria-label': label, spellcheck: 'false' });
    return modal({
        title, text, body: [input],
        actions: [{ label: t('Cancel'), value: null }, { label: confirm, primary: true, value: () => input.value.trim() || undefined }],
    });
}

function confirmDialog({ title, text, confirm, danger = true }) {
    return modal({ title, text, actions: [{ label: t('Cancel'), value: false }, { label: confirm, primary: true, danger, value: true }] });
}

function toast(message, { undo } = {}) {
    const node = h('div', { class: 'toast', role: 'status' }, h('span', { class: 'grow' }, message),
        undo ? linkButton(t('Undo'), () => {
            undo();
            node.remove();
        }) : null);
    toasts.append(node);
    setTimeout(() => node.remove(), undo ? 7000 : 5000);
}

// --- Passphrases -------------------------------------------------------------------------------------

// A rough count of the guesses a passphrase would take, in bits, from its length and the kinds of
// character in it. Enough to tell a weak one from a strong one, which is all it is used for.
function strength(passphrase) {
    const text = String(passphrase);
    const pool = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^a-zA-Z0-9]/].reduce((sum, test, index) => sum + (test.test(text) ? [26, 26, 10, 33][index] : 0), 0);
    const unique = new Set(text).size;
    const bits = Math.round(Math.min(text.length, unique * 1.5) * Math.log2(Math.max(pool, 1)));
    if (bits < 45) {
        return { bits, level: 'weak', label: t('Weak: add more words') };
    }
    if (bits < 65) {
        return { bits, level: 'fair', label: t('Fair: a few more words would help') };
    }
    if (bits < 85) {
        return { bits, level: 'good', label: t('Good') };
    }
    return { bits, level: 'strong', label: t('Strong') };
}

// The fields for choosing a passphrase, and a check that they agree
function passphraseFields({ current = false } = {}) {
    const field = (placeholder, autocomplete) => h('input', { class: 'field', type: 'password', placeholder, 'aria-label': placeholder, autocomplete });
    const old = current ? field(t('Current passphrase'), 'current-password') : null;
    const first = field(t('New passphrase'), 'new-password');
    const second = field(t('The same again'), 'new-password');
    const meter = h('div', { class: 'meter' }, h('div'));
    const hint = h('p', { class: 'hint small' }, t('Use at least 8 characters. A few unrelated words make a passphrase that is long and still easy to remember.'));
    const error = h('p', { class: 'error small', role: 'alert' });
    first.addEventListener('input', () => {
        const result = strength(first.value);
        meter.dataset.level = first.value ? result.level : '';
        hint.textContent = first.value ? result.label : hint.textContent;
    });
    const check = () => {
        if (first.value.length < 8) {
            error.textContent = t('Use at least 8 characters.');
            first.focus();
            return null;
        }
        if (first.value !== second.value) {
            error.textContent = t('The two passphrases are not the same.');
            second.focus();
            return null;
        }
        error.textContent = '';
        return first.value;
    };
    return { nodes: [old, first, second, meter, hint, error], old, check, error };
}

// --- The gate: first run and unlock -----------------------------------------------------------------

// The mark as its bowl and its stem, so that the stem can lift by itself while the notes are opened
function gem(active = false) {
    return h('div', { class: `gem${active ? ' active' : ''}` },
        h('img', { src: 'gem-bowl.svg', alt: '' }), h('img', { class: 'stem', src: 'gem-stem.svg', alt: '' }));
}

function renderGate() {
    document.body.classList.add('gated');
    delete document.body.dataset.mode;
    if (ui.status === 'loading') {
        main.replaceChildren(h('div', { class: 'loading' }, icon('spinner', 28, 'spin')));
    } else if (ui.status === 'new') {
        main.replaceChildren(setupPage());
    } else {
        main.replaceChildren(unlockPage());
    }
    main.querySelector('input')?.focus();
}

function setupPage() {
    const fields = passphraseFields();
    const submit = button(t('Encrypt my notes'), null, { primary: true, icon: 'lock', type: 'submit' });
    const form = h('form', {
        class: 'card gate-card',
        onsubmit: async (event) => {
            event.preventDefault();
            const passphrase = fields.check();
            if (!passphrase) {
                return;
            }
            submit.disabled = true;
            submit.lastChild.textContent = t('Encrypting…');
            applyState(await window.notes.create(passphrase));
        },
    },
    h('div', { class: 'gate-card-head' }, h('div', { class: 'row-icon tone accent' }, icon('shield', 22)),
        h('div', { class: 'grow' }, h('strong', {}, t('Protect them with a passphrase')),
            h('p', { class: 'soft small' }, t('Recommended. Your notes, tasks and attachments are encrypted on disk, and open only with the passphrase.')))),
    fields.nodes,
    h('div', { class: 'callout caution' }, icon('alert', 20),
        h('p', {}, t('Nobody can recover a forgotten passphrase: not Amethystora, not an administrator, not anyone. Keep it somewhere safe.'))),
    h('div', { class: 'actions' }, submit));
    return h('div', { class: 'gate' },
        gem(true),
        h('h1', {}, t('Your notes, on this computer only')),
        h('p', { class: 'lead' }, t('Notes and tasks that are never synced and never sent anywhere. Encrypted with AES-256, which stays secure against quantum computers.')),
        form,
        linkButton(t('Continue without encryption'), async () => {
            const sure = await confirmDialog({
                title: t('Keep your notes unencrypted?'),
                text: t('Anyone who can read your files, from a backup or from this disk in another computer, can read your notes. You can turn encryption on later in Settings.'),
                confirm: t('Keep unencrypted'),
                danger: false,
            });
            if (sure) {
                applyState(await window.notes.create(null));
            }
        }, { quiet: true }),
        h('p', { class: 'note' }, t('Coming from Joplin or Planify? Import them from Settings once you are in.')));
}

// What is said about the security key: in red what went wrong, plainly what it is waited for
function keyStatus(node, text, waiting = false) {
    node.classList.toggle('hint', waiting);
    node.textContent = text;
}

// Opens the notes with a security key. One that reads a fingerprint needs nothing more; for any other,
// main.js answers { pin: true } and its PIN is asked for here.
let usingPasskey = false;
async function passkeyUnlock(error) {
    if (usingPasskey) {
        return;
    }
    usingPasskey = true;
    keyStatus(error, t('Looking for your security key. Touch it if it blinks.'), true);
    let result = await window.notes.unlockPasskey('');
    usingPasskey = false;
    keyStatus(error, '');
    if (result?.pin) {
        const input = h('input', { class: 'field', type: 'password', placeholder: t('Security key PIN'), 'aria-label': t('Security key PIN') });
        const problem = h('p', { class: 'error small', role: 'alert' });
        result = await modal({
            title: t('Open with a passkey'),
            text: t('Enter the PIN of your security key, then touch the key when it blinks.'),
            body: [input, problem],
            actions: [{ label: t('Cancel'), value: null }, { label: t('Unlock'), primary: true, value: async () => {
                if (usingPasskey || !input.value) {
                    return undefined;
                }
                usingPasskey = true;
                keyStatus(problem, t('Touch your security key when it blinks.'), true);
                const answer = await window.notes.unlockPasskey(input.value);
                usingPasskey = false;
                if (answer?.error) {
                    keyStatus(problem, answer.error);
                    input.select();
                    return undefined;
                }
                return answer;
            } }],
        });
        if (!result) {
            // Closed while the key was still waiting to be touched
            window.notes.passkeyCancel();
            return;
        }
    }
    if (result?.error) {
        error.textContent = result.error;
        return;
    }
    applyState(result);
}

function unlockPage() {
    const input = h('input', { class: 'field', type: 'password', placeholder: t('Passphrase'), 'aria-label': t('Passphrase'), autocomplete: 'current-password' });
    const error = h('p', { class: 'error small', role: 'alert' });
    const submit = button(t('Unlock'), null, { primary: true, icon: 'unlock', type: 'submit' });
    const gemNode = gem();
    return h('div', { class: 'gate' },
        gemNode,
        h('h1', {}, t('Your notes are locked')),
        h('p', { class: 'lead' }, t('Enter your passphrase to open them.')),
        h('form', {
            class: 'unlock',
            onsubmit: async (event) => {
                event.preventDefault();
                if (!input.value) {
                    return;
                }
                submit.disabled = true;
                gemNode.classList.add('opening');
                error.textContent = '';
                const result = await window.notes.unlock(input.value);
                if (result?.error) {
                    submit.disabled = false;
                    gemNode.classList.remove('opening');
                    error.textContent = result.error;
                    input.select();
                    return;
                }
                input.value = '';
                applyState(result);
            },
        }, input, submit),
        error,
        ui.passkeys.length ? linkButton(t('Open with a passkey'), () => passkeyUnlock(error), { icon: 'key' }) : null);
}

// --- The sidebar -------------------------------------------------------------------------------------

function navItem({ label, iconName, color, count, current, onclick, onmenu, depth = 0, toggle, drop }) {
    const row = h('div', { class: 'nav-row', 'data-depth': depth ? String(Math.min(depth, 6)) : null });
    row.append(h('button', {
        type: 'button', class: 'nav-item', 'aria-current': current ? 'true' : null, onclick,
        'data-color': color || null,
    },
    toggle || null,
    color ? h('span', { class: 'dot' }) : icon(iconName, 18),
    h('span', { class: 'grow label' }, label),
    count ? h('span', { class: 'count' }, t.number(count)) : null));
    if (onmenu) {
        row.append(h('button', { type: 'button', class: 'nav-more', title: t('More'), 'aria-label': t('More for {name}', { name: label }), onclick: (event) => onmenu(event.currentTarget) }, icon('more', 16)));
    }
    if (drop) {
        row.addEventListener('dragover', (event) => {
            if (event.dataTransfer.types.includes('application/x-note')) {
                event.preventDefault();
                row.classList.add('drop-target');
            }
        });
        row.addEventListener('dragleave', () => row.classList.remove('drop-target'));
        row.addEventListener('drop', (event) => {
            row.classList.remove('drop-target');
            const id = event.dataTransfer.getData('application/x-note');
            if (id) {
                event.preventDefault();
                drop(id);
            }
        });
    }
    return row;
}

function navHeading(label, onadd, addLabel) {
    return h('div', { class: 'nav-heading' }, h('span', { class: 'grow' }, label),
        onadd ? h('button', { type: 'button', class: 'nav-add', title: addLabel, 'aria-label': addLabel, onclick: onadd }, icon('plus', 16)) : null);
}

function sameView(a, b) {
    return !ui.query && ui.mode !== 'settings' && a.type === b.type && (a.id || null) === (b.id || null);
}

function renderNav() {
    const scroll = nav.scrollTop;
    nav.replaceChildren(...(ui.mode === 'tasks' ? tasksNav() : notesNav()));
    nav.scrollTop = scroll;
    for (const node of modeButtons) {
        const current = node.dataset.mode === ui.mode;
        node.setAttribute('aria-selected', String(current));
    }
    const due = openTasks().filter((task) => task.due && task.due <= today()).length;
    todayCount.hidden = !due;
    todayCount.textContent = t.number(due);
}

function showNotes(view) {
    commit();
    ui.mode = 'notes';
    ui.notesView = view;
    clearQuery();
    const first = sortNotes(notesIn(view))[0];
    if (!notesIn(view).some((note) => note.id === ui.note)) {
        ui.note = first?.id || null;
    }
    remember();
    render();
}

function notesNav() {
    const live = liveNotes();
    const items = [
        navItem({ label: t('All notes'), iconName: 'notes', count: live.length, current: sameView(ui.notesView, { type: 'all' }), onclick: () => showNotes({ type: 'all' }) }),
        navHeading(t('Notebooks'), () => newNotebook(null), t('New notebook')),
    ];
    const walk = (parent, depth, seen) => {
        for (const notebook of childNotebooks(parent)) {
            if (seen.has(notebook.id)) {
                continue;
            }
            seen.add(notebook.id);
            const children = childNotebooks(notebook.id);
            const collapsed = ui.collapsed.includes(notebook.id);
            const toggle = children.length ? h('span', {
                class: `twisty${collapsed ? '' : ' open'}`, role: 'button', 'aria-label': collapsed ? t('Expand') : t('Collapse'),
                onclick: (event) => {
                    event.stopPropagation();
                    ui.collapsed = collapsed ? ui.collapsed.filter((id) => id !== notebook.id) : [...ui.collapsed, notebook.id];
                    remember();
                    renderNav();
                },
            }, icon('chevron', 14)) : h('span', { class: 'twisty' });
            items.push(navItem({
                label: notebook.title || t('Untitled'), iconName: 'folder', depth, toggle,
                count: live.filter((note) => note.notebook === notebook.id).length || null,
                current: sameView(ui.notesView, { type: 'notebook', id: notebook.id }),
                onclick: () => showNotes({ type: 'notebook', id: notebook.id }),
                onmenu: (anchor) => notebookMenu(anchor, notebook),
                drop: (noteId) => moveNote(db.notes[noteId], notebook.id),
            }));
            if (!collapsed) {
                walk(notebook.id, depth + 1, seen);
            }
        }
    };
    walk(null, 0, new Set());
    const tags = Object.values(db.tags).sort(byTitle);
    if (tags.length) {
        items.push(navHeading(t('Tags')));
        for (const tag of tags) {
            items.push(navItem({
                label: tag.title, iconName: 'hash', count: live.filter((note) => note.tags?.includes(tag.id)).length || null,
                current: sameView(ui.notesView, { type: 'tag', id: tag.id }),
                onclick: () => showNotes({ type: 'tag', id: tag.id }),
                onmenu: (anchor) => tagMenu(anchor, tag),
            }));
        }
    }
    const trashed = Object.values(db.notes).filter((note) => note.trashed).length;
    items.push(h('div', { class: 'nav-gap' }), navItem({
        label: t('Trash'), iconName: 'trash', count: trashed || null, current: sameView(ui.notesView, { type: 'trash' }),
        onclick: () => showNotes({ type: 'trash' }),
    }));
    return items;
}

function showTasks(view) {
    commit();
    ui.mode = 'tasks';
    ui.tasksView = view;
    ui.task = null;
    clearQuery();
    remember();
    render();
}

function tasksNav() {
    const open = openTasks();
    const now = today();
    const count = (list) => list.length || null;
    const items = [
        navItem({ label: t('Inbox'), iconName: 'inbox', count: count(open.filter((task) => !task.project && !task.parent)), current: sameView(ui.tasksView, { type: 'inbox' }), onclick: () => showTasks({ type: 'inbox' }) }),
        navItem({ label: t('Today'), iconName: 'today', count: count(open.filter((task) => task.due && task.due <= now)), current: sameView(ui.tasksView, { type: 'today' }), onclick: () => showTasks({ type: 'today' }) }),
        navItem({ label: t('Upcoming'), iconName: 'calendar', current: sameView(ui.tasksView, { type: 'upcoming' }), onclick: () => showTasks({ type: 'upcoming' }) }),
        navItem({ label: t('Pinned'), iconName: 'pin', count: count(open.filter((task) => task.pinned)), current: sameView(ui.tasksView, { type: 'pinned' }), onclick: () => showTasks({ type: 'pinned' }) }),
        navItem({ label: t('Completed'), iconName: 'done', current: sameView(ui.tasksView, { type: 'completed' }), onclick: () => showTasks({ type: 'completed' }) }),
        navHeading(t('Projects'), () => newProject(), t('New project')),
    ];
    for (const project of Object.values(db.projects).sort((a, b) => (a.order || 0) - (b.order || 0) || byTitle(a, b))) {
        items.push(navItem({
            label: project.title || t('Untitled'), color: project.color || 'violet',
            count: count(open.filter((task) => task.project === project.id && !task.parent)),
            current: sameView(ui.tasksView, { type: 'project', id: project.id }),
            onclick: () => showTasks({ type: 'project', id: project.id }),
            onmenu: (anchor) => projectMenu(anchor, project),
        }));
    }
    items.push(navHeading(t('Labels'), () => newLabel(), t('New label')));
    for (const label of Object.values(db.labels).sort(byTitle)) {
        items.push(navItem({
            label: label.title, iconName: 'tag', count: count(open.filter((task) => task.labels?.includes(label.id))),
            current: sameView(ui.tasksView, { type: 'label', id: label.id }),
            onclick: () => showTasks({ type: 'label', id: label.id }),
            onmenu: (anchor) => labelMenu(anchor, label),
        }));
    }
    return items;
}

// --- Notes -------------------------------------------------------------------------------------------

function liveNotes() {
    return Object.values(db.notes).filter((note) => !note.trashed);
}

function childNotebooks(parent) {
    return Object.values(db.notebooks)
        .filter((notebook) => (notebook.parent && db.notebooks[notebook.parent] ? notebook.parent : null) === parent)
        .sort(byTitle);
}

function descendants(id) {
    const found = new Set([id]);
    let grew = true;
    while (grew) {
        grew = false;
        for (const notebook of Object.values(db.notebooks)) {
            if (found.has(notebook.parent) && !found.has(notebook.id)) {
                found.add(notebook.id);
                grew = true;
            }
        }
    }
    return found;
}

function terms() {
    return ui.query.toLowerCase().split(/\s+/).filter(Boolean);
}

function notesIn(view) {
    if (ui.query) {
        const words = terms();
        return liveNotes().filter((note) => {
            const text = `${note.title}\n${note.body}\n${(note.tags || []).map((id) => db.tags[id]?.title || '').join(' ')}`.toLowerCase();
            return words.every((word) => text.includes(word));
        });
    }
    if (view.type === 'trash') {
        return Object.values(db.notes).filter((note) => note.trashed);
    }
    if (view.type === 'notebook') {
        const inside = descendants(view.id);
        return liveNotes().filter((note) => inside.has(note.notebook));
    }
    if (view.type === 'tag') {
        return liveNotes().filter((note) => note.tags?.includes(view.id));
    }
    return liveNotes();
}

function sortNotes(list) {
    const order = db.settings.noteSort || 'updated';
    if (order === 'title') {
        return list.sort(byTitle);
    }
    if (ui.notesView.type === 'trash' && !ui.query) {
        return list.sort((a, b) => b.trashed - a.trashed);
    }
    return list.sort((a, b) => (b[order] || 0) - (a[order] || 0));
}

function viewTitle() {
    if (ui.query) {
        return t('Search');
    }
    const view = ui.notesView;
    if (view.type === 'notebook') {
        return db.notebooks[view.id]?.title || t('Untitled');
    }
    if (view.type === 'tag') {
        return `#${db.tags[view.id]?.title || ''}`;
    }
    return view.type === 'trash' ? t('Trash') : t('All notes');
}

// The first line of text, without the Markdown around it
function snippet(body) {
    const text = String(body || '')
        .replace(/```[\s\S]*?```/g, ' ')
        .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
        .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/^\s*(#{1,6}|>|[-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?/gm, '')
        .replace(/[*_`~]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
    return text.slice(0, 140);
}

function firstNotebook() {
    const found = childNotebooks(null)[0];
    if (found) {
        return found.id;
    }
    const notebook = { id: newId(), title: t('Notes'), parent: null, created: Date.now(), updated: Date.now() };
    save('notebooks', notebook, { now: true });
    return notebook.id;
}

function newNote() {
    commit();
    if (ui.query || ui.notesView.type === 'trash') {
        ui.notesView = { type: 'all' };
        clearQuery();
    }
    const now = Date.now();
    const note = {
        id: newId(),
        notebook: ui.notesView.type === 'notebook' && db.notebooks[ui.notesView.id] ? ui.notesView.id : firstNotebook(),
        title: '', body: '', tags: ui.notesView.type === 'tag' ? [ui.notesView.id] : [], created: now, updated: now, trashed: null,
    };
    save('notes', note, { now: true });
    ui.mode = 'notes';
    ui.note = note.id;
    remember();
    render();
    editor?.title.focus();
}

function openNote(id) {
    commit();
    ui.note = id;
    remember();
    renderNotes();
}

function moveNote(note, notebook) {
    if (!note || !db.notebooks[notebook]) {
        return;
    }
    editNote(note, { notebook, trashed: null });
    renderNav();
    renderNotes({ force: true });
    toast(t('Moved to {notebook}', { notebook: db.notebooks[notebook].title || t('Untitled') }));
}

function trashNote(note) {
    const next = neighbour(note.id);
    editNote(note, { trashed: Date.now() });
    commit();
    ui.note = next;
    renderNav();
    renderNotes({ force: true });
    toast(t('Moved to the trash'), {
        undo: () => {
            editNote(note, { trashed: null });
            ui.note = note.id;
            render();
        },
    });
}

function restoreNote(note) {
    editNote(note, { trashed: null, notebook: db.notebooks[note.notebook] ? note.notebook : firstNotebook() });
    ui.note = neighbour(note.id);
    render();
    toast(t('Restored to {notebook}', { notebook: db.notebooks[note.notebook]?.title || t('Untitled') }));
}

async function deleteForever(notes) {
    const sure = await confirmDialog({
        title: t('{count, plural, =1 {Delete this note for good?} other {Delete # notes for good?}}', { count: notes.length }),
        text: t('They cannot be brought back, and neither can their earlier versions or attachments.'),
        confirm: t('Delete'),
    });
    if (!sure) {
        return;
    }
    const ids = new Set(notes.map((note) => note.id));
    remove('revisions', Object.values(db.revisions).filter((revision) => ids.has(revision.note)).map((revision) => revision.id));
    remove('notes', [...ids]);
    ui.note = null;
    render();
}

// The note that takes this one's place in the list when it goes
function neighbour(id) {
    const list = sortNotes(notesIn(ui.notesView));
    const index = list.findIndex((note) => note.id === id);
    return (list[index + 1] || list[index - 1])?.id || null;
}

async function newNotebook(parent) {
    const title = await ask({ title: parent ? t('New notebook inside') : t('New notebook'), label: t('Name'), confirm: t('Create') });
    if (!title) {
        return;
    }
    const notebook = { id: newId(), title, parent, created: Date.now(), updated: Date.now() };
    save('notebooks', notebook, { now: true });
    ui.collapsed = ui.collapsed.filter((id) => id !== parent);
    showNotes({ type: 'notebook', id: notebook.id });
}

function notebookMenu(anchor, notebook) {
    menu(anchor, [
        { label: t('New note here'), icon: 'file-plus', run: () => {
            ui.notesView = { type: 'notebook', id: notebook.id };
            newNote();
        } },
        { label: t('New notebook inside'), icon: 'folder', run: () => newNotebook(notebook.id) },
        { label: t('Rename'), icon: 'edit', run: async () => {
            const title = await ask({ title: t('Rename notebook'), label: t('Name'), value: notebook.title });
            if (title) {
                save('notebooks', Object.assign(notebook, { title, updated: Date.now() }));
                render();
            }
        } },
        notebook.parent ? { label: t('Move to the top level'), icon: 'upload', run: () => {
            save('notebooks', Object.assign(notebook, { parent: null, updated: Date.now() }));
            render();
        } } : null,
        '-',
        { label: t('Delete'), icon: 'trash', danger: true, run: () => deleteNotebook(notebook) },
    ]);
}

async function deleteNotebook(notebook) {
    const inside = descendants(notebook.id);
    const notes = liveNotes().filter((note) => inside.has(note.notebook));
    const sure = await confirmDialog({
        title: notebook.title ? t('Delete {name}?', { name: notebook.title }) : t('Delete this notebook?'),
        text: inside.size > 1
            ? t('{count, plural, =0 {It has no notes, and the notebooks inside it are deleted too.} one {# note in it goes to the trash, and the notebooks inside it are deleted too.} other {# notes in it go to the trash, and the notebooks inside it are deleted too.}}', { count: notes.length })
            : t('{count, plural, =0 {It has no notes.} one {# note in it goes to the trash.} other {# notes in it go to the trash.}}', { count: notes.length }),
        confirm: t('Delete'),
    });
    if (!sure) {
        return;
    }
    for (const note of notes) {
        editNote(note, { trashed: Date.now() });
    }
    remove('notebooks', [...inside]);
    if (inside.has(ui.notesView.id)) {
        ui.notesView = { type: 'all' };
    }
    render();
}

function tagMenu(anchor, tag) {
    menu(anchor, [
        { label: t('Rename'), icon: 'edit', run: async () => {
            const title = await ask({ title: t('Rename tag'), label: t('Name'), value: tag.title });
            if (title) {
                save('tags', Object.assign(tag, { title }));
                render();
            }
        } },
        { label: t('Delete'), icon: 'trash', danger: true, run: async () => {
            if (await confirmDialog({ title: t('Delete the tag {tag}?', { tag: tag.title }), text: t('The notes stay; only the tag is taken off them.'), confirm: t('Delete') })) {
                for (const note of Object.values(db.notes).filter((item) => item.tags?.includes(tag.id))) {
                    save('notes', Object.assign(note, { tags: note.tags.filter((id) => id !== tag.id) }));
                }
                remove('tags', [tag.id]);
                if (ui.notesView.id === tag.id) {
                    ui.notesView = { type: 'all' };
                }
                render();
            }
        } },
    ]);
}

function tagFor(title) {
    const found = Object.values(db.tags).find((tag) => tag.title.toLowerCase() === title.toLowerCase());
    if (found) {
        return found.id;
    }
    const tag = { id: newId(), title };
    save('tags', tag, { now: true });
    return tag.id;
}

// The panes of the notes, kept across renders so that typing is never interrupted
const notesLayout = h('div', { class: 'notes-layout' });
const listPane = h('section', { class: 'list-pane', 'aria-label': t('Notes') });
const editorPane = h('section', { class: 'editor-pane', 'aria-label': t('Note') });
notesLayout.append(listPane, editorPane);
let editor = null;

function renderNotes({ force = false } = {}) {
    if (main.firstChild !== notesLayout) {
        main.replaceChildren(notesLayout);
        force = true;
    }
    const list = sortNotes(notesIn(ui.notesView));
    const note = db.notes[ui.note];
    if (!note) {
        ui.note = null;
    }
    renderNoteList(list);
    if (force || editor?.id !== (note?.id || null)) {
        editorPane.replaceChildren(note ? buildEditor(note) : emptyEditor());
    }
}

function renderNoteList(list) {
    const scroller = listPane.querySelector('.list-scroll');
    const scroll = scroller?.scrollTop || 0;
    const trash = ui.notesView.type === 'trash' && !ui.query;
    const sort = db.settings.noteSort || 'updated';
    const head = h('div', { class: 'list-head' },
        h('div', { class: 'grow' }, h('h2', {}, viewTitle()), h('p', { class: 'faint small' }, t('{count, plural, one {# note} other {# notes}}', { count: list.length }))),
        iconButton('sort', t('Sort'), (event) => menu(event.currentTarget, [
            ['updated', t('Last changed')], ['created', t('Created')], ['title', t('Title')],
        ].map(([value, label]) => ({ label, checked: sort === value, run: () => {
            db.settings.noteSort = value;
            window.notes.settings({ noteSort: value });
            renderNotes();
        } })))),
        trash
            ? (list.length ? button(t('Empty'), () => deleteForever(list), { small: true, icon: 'trash' }) : null)
            : iconButton('file-plus', t('{action} ({key})', { action: t('New note'), key: 'Ctrl+N' }), newNote, { className: 'accent' }));
    const items = list.map((note) => {
        const tags = (note.tags || []).map((id) => db.tags[id]).filter(Boolean);
        const where = ui.notesView.type !== 'notebook' || ui.query ? db.notebooks[note.notebook]?.title : null;
        return h('button', {
            type: 'button', class: 'note-item', 'aria-current': note.id === ui.note ? 'true' : null, draggable: trash ? null : 'true',
            onclick: () => openNote(note.id),
            ondragstart: (event) => {
                event.dataTransfer.setData('application/x-note', note.id);
                event.dataTransfer.effectAllowed = 'move';
            },
        },
        h('span', { class: 'note-title' }, note.title || t('Untitled')),
        h('span', { class: 'note-snippet' }, snippet(note.body) || t('No text')),
        h('span', { class: 'note-meta' },
            h('span', {}, whenLabel(trash ? note.trashed : note[sort === 'created' ? 'created' : 'updated'])),
            where ? h('span', { class: 'meta-folder' }, icon('folder', 13), where) : null,
            /:\/[0-9a-f]{32}/.test(note.body || '') ? icon('clip', 13) : null,
            tags.slice(0, 2).map((tag) => h('span', { class: 'chip' }, tag.title))));
    });
    const empty = h('div', { class: 'empty small' },
        ui.query ? t('No note has all of those words.') : trash ? t('The trash is empty.') : t('No notes here yet.'),
        !ui.query && !trash ? linkButton(t('Start one'), newNote, { icon: 'file-plus' }) : null);
    const newScroller = h('div', { class: 'list-scroll' }, items.length ? items : empty);
    listPane.replaceChildren(head, newScroller);
    newScroller.scrollTop = scroll;
}

function emptyEditor() {
    editor = null;
    return h('div', { class: 'editor-empty' },
        icon('notes', 44),
        h('p', {}, liveNotes().length ? t('Pick a note, or start a new one.') : t('Your notes will be here.')),
        button(t('New note'), newNote, { icon: 'file-plus', primary: true }),
        h('p', { class: 'faint small' }, t('{key} starts a note from anywhere in the window.', { key: 'Ctrl+N' })));
}

// marked, set to show a note's HTML as text, and to reach attachments through res://
function configureMarked() {
    if (!window.marked || configureMarked.done) {
        return;
    }
    configureMarked.done = true;
    marked.use({
        gfm: true,
        breaks: true,
        walkTokens(token) {
            if (token.type === 'image' || token.type === 'link') {
                const match = /^:\/([0-9a-f]{32})$/.exec(token.href || '');
                if (match) {
                    token.href = token.type === 'image' ? `res://${match[1]}/` : `#resource-${match[1]}`;
                }
            }
        },
        renderer: {
            html(token) {
                return escapeHtml(token.text ?? token.raw ?? '');
            },
        },
    });
}

function escapeHtml(text) {
    return String(text).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
}

function renderMarkdown(target, body, { ontoggle } = {}) {
    configureMarked();
    if (!window.marked) {
        target.replaceChildren(h('pre', { dir: 'auto' }, body || ''));
        return;
    }
    target.innerHTML = marked.parse(String(body || ''));
    // Each block is laid out by its own text, Arabic or English whatever the window's language is, and
    // code always from left to right
    for (const block of target.children) {
        block.dir = block.localName === 'pre' ? 'ltr' : 'auto';
    }
    [...target.querySelectorAll('input[type="checkbox"]')].forEach((box, index) => {
        box.disabled = !ontoggle;
        if (ontoggle) {
            box.addEventListener('click', (event) => {
                event.preventDefault();
                ontoggle(index);
            });
        }
    });
    for (const link of target.querySelectorAll('a[href^="#resource-"]')) {
        const resource = db.resources[link.getAttribute('href').slice(10)];
        link.classList.add('attachment');
        link.prepend(icon('clip', 14));
        if (resource) {
            link.title = t('{name}, {size}. Click to save a copy.', { name: resource.name, size: size(resource.size) });
        }
    }
    for (const image of target.querySelectorAll('img')) {
        image.loading = 'lazy';
    }
}

// A size the way the language writes it: "512 bytes", "1.4 MB"
function size(bytes) {
    const units = ['byte', 'kilobyte', 'megabyte', 'gigabyte'];
    let value = Number(bytes) || 0;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit += 1;
    }
    const digits = unit && value < 10 ? 1 : 0;
    return t.number(value, { style: 'unit', unit: units[unit], unitDisplay: unit ? 'short' : 'long',
        minimumFractionDigits: digits, maximumFractionDigits: digits });
}

// Links in a rendered note: attachments are saved, web links go to the browser, anything else stays put
document.addEventListener('click', (event) => {
    const link = event.target.closest?.('.markdown a');
    if (!link) {
        return;
    }
    event.preventDefault();
    const href = link.getAttribute('href') || '';
    if (href.startsWith('#resource-')) {
        window.notes.saveResource(href.slice(10)).then((result) => {
            if (result?.error) {
                toast(result.error);
            } else if (result?.path) {
                toast(t('Saved to {path}', { path: result.path }));
            }
        });
    } else if (/^(https?:|mailto:)/i.test(href)) {
        window.notes.openExternal(href);
    }
});

// The nth task list item's box, flipped in the Markdown itself; fenced code does not count
function toggleCheckbox(body, index) {
    const lines = String(body).split('\n');
    let count = -1;
    let fenced = false;
    for (let at = 0; at < lines.length; at += 1) {
        if (/^\s*(```|~~~)/.test(lines[at])) {
            fenced = !fenced;
            continue;
        }
        const match = !fenced && /^(\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+\[)([ xX])\]/.exec(lines[at]);
        if (match && ++count === index) {
            lines[at] = `${match[1]}${match[2] === ' ' ? 'x' : ' '}${lines[at].slice(match[1].length + 1)}`;
            return lines.join('\n');
        }
    }
    return body;
}

function words(text) {
    return (String(text).match(/[\p{L}\p{N}]+/gu) || []).length;
}

function buildEditor(note) {
    const trashed = Boolean(note.trashed);
    const layout = db.settings.layout || 'split';
    // The note's own text is laid out by itself, Arabic or English whatever the window's language is
    const title = h('input', { class: 'title-input', type: 'text', value: note.title, placeholder: t('Title'), 'aria-label': t('Title'), dir: 'auto', readonly: trashed, spellcheck: 'false' });
    const text = h('textarea', { class: 'source', placeholder: t('Write in Markdown…'), 'aria-label': t('Note'), dir: 'auto', readonly: trashed, spellcheck: 'false' });
    text.value = note.body || '';
    const preview = h('article', { class: 'preview markdown', 'aria-label': t('Preview') });
    const foot = h('div', { class: 'editor-foot faint small' });
    const body = h('div', { class: 'editor-body', 'data-layout': layout }, text, preview);
    editor = { id: note.id, title, text, preview };

    const updateFoot = () => {
        foot.textContent = [
            trashed ? t('In the trash since {date}', { date: stamp(note.trashed) }) : t('Changed {date}', { date: stamp(note.updated) }),
            t('{count, plural, one {# word} other {# words}}', { count: words(note.body) }),
        ].join(' · ');
    };
    const updatePreview = () => renderMarkdown(preview, note.body, trashed ? {} : {
        ontoggle: (index) => {
            const next = toggleCheckbox(note.body, index);
            text.value = next;
            editNote(note, { body: next });
            updatePreview();
            updateFoot();
        },
    });
    const refreshList = debounce(() => renderNoteList(sortNotes(notesIn(ui.notesView))), 400);
    const previewLater = debounce(updatePreview, 150);
    title.addEventListener('input', () => {
        editNote(note, { title: title.value });
        refreshList();
    });
    title.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === 'ArrowDown') {
            event.preventDefault();
            text.focus();
            text.setSelectionRange(0, 0);
        }
    });
    text.addEventListener('input', () => {
        editNote(note, { body: text.value });
        previewLater();
        updateFoot();
        refreshList();
    });
    text.addEventListener('keydown', (event) => editorKeys(event, text));
    text.addEventListener('paste', (event) => {
        const files = [...(event.clipboardData?.files || [])];
        if (files.length && !trashed) {
            event.preventDefault();
            attachFiles(text, files);
        }
    });
    body.addEventListener('dragover', (event) => {
        if (!trashed && event.dataTransfer.types.includes('Files')) {
            event.preventDefault();
        }
    });
    body.addEventListener('drop', (event) => {
        const files = [...(event.dataTransfer?.files || [])];
        if (files.length && !trashed) {
            event.preventDefault();
            attachFiles(text, files);
        }
    });

    const notebooks = [];
    const walk = (parent, depth, seen) => childNotebooks(parent).forEach((notebook) => {
        if (!seen.has(notebook.id)) {
            seen.add(notebook.id);
            notebooks.push([notebook.id, `${' '.repeat(depth)}${notebook.title || t('Untitled')}`]);
            walk(notebook.id, depth + 1, seen);
        }
    });
    walk(null, 0, new Set());
    const notebookSelect = h('select', {
        class: 'crumb-select', 'aria-label': t('Notebook'), disabled: trashed,
        onchange: (event) => moveNote(note, event.target.value),
    }, notebooks.map(([id, label]) => h('option', { value: id, selected: id === note.notebook }, label)));

    const setLayout = (next) => {
        db.settings.layout = next;
        window.notes.settings({ layout: next });
        body.dataset.layout = next;
        for (const node of segment.children) {
            node.setAttribute('aria-pressed', String(node.dataset.layout === next));
        }
        toolbar.hidden = next === 'preview' || trashed;
        if (next !== 'edit') {
            updatePreview();
        }
    };
    const segment = h('div', { class: 'segment', role: 'group', 'aria-label': t('Layout') },
        [['edit', 'edit', t('Editor')], ['split', 'split', t('Editor and preview')], ['preview', 'eye', t('Preview')]].map(([value, name, label]) => h('button', {
            type: 'button', title: t('{action} ({key})', { action: label, key: 'Ctrl+E' }), 'aria-label': label, 'data-layout': value, 'aria-pressed': String(value === layout),
            onclick: () => setLayout(value),
        }, icon(name, 17))));
    editor.cycleLayout = () => setLayout({ edit: 'split', split: 'preview', preview: 'edit' }[db.settings.layout || 'split']);

    const tool = (name, label, run) => h('button', { type: 'button', class: 'tool', title: label, 'aria-label': label, onclick: () => run(text) }, icon(name, 17));
    const toolbar = h('div', { class: 'toolbar', role: 'toolbar', 'aria-label': t('Formatting'), hidden: layout === 'preview' || trashed },
        tool('bold', t('{action} ({key})', { action: t('Bold'), key: 'Ctrl+B' }), (area) => surround(area, '**', '**', t('bold text'))),
        tool('italic', t('{action} ({key})', { action: t('Italic'), key: 'Ctrl+I' }), (area) => surround(area, '_', '_', t('italic text'))),
        tool('heading', t('Heading'), (area) => prefixLines(area, '## ')),
        h('span', { class: 'tool-sep' }),
        tool('list', t('List'), (area) => prefixLines(area, '- ')),
        tool('checklist', t('Checklist'), (area) => prefixLines(area, '- [ ] ')),
        tool('quote', t('Quote'), (area) => prefixLines(area, '> ')),
        tool('code', t('Code'), (area) => (area.value.slice(area.selectionStart, area.selectionEnd).includes('\n')
            ? surround(area, '```\n', '\n```', t('code')) : surround(area, '`', '`', t('code')))),
        tool('link', t('{action} ({key})', { action: t('Link'), key: 'Ctrl+K' }), (area) => surround(area, '[', '](https://)', t('link text'))),
        h('span', { class: 'tool-sep' }),
        tool('clip', t('Attach a file'), async (area) => {
            const added = await window.notes.attach();
            if (Array.isArray(added)) {
                insertAttachments(area, added);
            }
        }));

    const tagInput = h('input', { class: 'tag-input', type: 'text', placeholder: t('Add a tag'), 'aria-label': t('Add a tag'), list: 'tag-options', spellcheck: 'false' });
    const tagRow = h('div', { class: 'tag-row' });
    const renderTags = () => {
        tagRow.replaceChildren(...[
            icon('hash', 15, 'faint'),
            ...(note.tags || []).map((id) => db.tags[id]).filter(Boolean).map((tag) => h('span', { class: 'chip' }, tag.title,
                trashed ? null : h('button', { type: 'button', class: 'chip-x', 'aria-label': t('Remove {name}', { name: tag.title }), onclick: () => {
                    editNote(note, { tags: note.tags.filter((id) => id !== tag.id) });
                    renderTags();
                    renderNav();
                } }, icon('close', 12)))),
            trashed ? null : tagInput,
            h('datalist', { id: 'tag-options' }, Object.values(db.tags).sort(byTitle).map((tag) => h('option', { value: tag.title }))),
        ].filter(Boolean));
    };
    const addTag = () => {
        const value = tagInput.value.replace(/^#/, '').trim();
        tagInput.value = '';
        if (value) {
            const id = tagFor(value);
            if (!note.tags?.includes(id)) {
                editNote(note, { tags: [...(note.tags || []), id] });
            }
            renderTags();
            renderNav();
            tagInput.focus();
        }
    };
    tagInput.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ',') {
            event.preventDefault();
            addTag();
        } else if (event.key === 'Backspace' && !tagInput.value && note.tags?.length) {
            editNote(note, { tags: note.tags.slice(0, -1) });
            renderTags();
            renderNav();
            tagInput.focus();
        }
    });
    tagInput.addEventListener('change', addTag);
    renderTags();

    const head = h('div', { class: 'editor-head' },
        h('label', { class: 'crumb' }, icon('folder', 16), notebookSelect),
        h('span', { class: 'grow' }),
        trashed ? null : segment,
        trashed ? null : iconButton('history', t('Earlier versions'), () => showHistory(note)),
        iconButton('more', t('More'), (event) => menu(event.currentTarget, trashed ? [
            { label: t('Restore'), icon: 'undo', run: () => restoreNote(note) },
            { label: t('Delete for good'), icon: 'trash', danger: true, run: () => deleteForever([note]) },
        ] : [
            { label: t('Export as PDF'), icon: 'download', run: () => exportPdf(note) },
            { label: t('Earlier versions'), icon: 'history', run: () => showHistory(note) },
            '-',
            { label: t('Move to the trash'), icon: 'trash', danger: true, run: () => trashNote(note) },
        ])));

    const banner = trashed ? h('div', { class: 'callout caution banner' }, icon('trash', 20),
        h('div', { class: 'grow' }, h('p', {}, t('This note is in the trash.'))),
        button(t('Restore'), () => restoreNote(note), { small: true, icon: 'undo' }),
        button(t('Delete for good'), () => deleteForever([note]), { small: true, danger: true })) : null;

    updatePreview();
    updateFoot();
    return h('div', { class: 'editor' }, head, banner, title, tagRow, toolbar, body, foot);
}

// Markdown shortcuts in the note: bold, italic and links, lists that carry on with Enter, and Tab that
// indents rather than leaving the field
function editorKeys(event, area) {
    const mod = event.ctrlKey || event.metaKey;
    if (mod && event.key.toLowerCase() === 'b') {
        event.preventDefault();
        surround(area, '**', '**', t('bold text'));
    } else if (mod && event.key.toLowerCase() === 'i') {
        event.preventDefault();
        surround(area, '_', '_', t('italic text'));
    } else if (mod && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        surround(area, '[', '](https://)', t('link text'));
    } else if (event.key === 'Tab' && !mod && !event.altKey) {
        event.preventDefault();
        if (event.shiftKey) {
            prefixLines(area, '    ', { remove: true });
        } else if (area.selectionStart !== area.selectionEnd) {
            prefixLines(area, '    ', { add: true });
        } else {
            document.execCommand('insertText', false, '    ');
        }
    } else if (event.key === 'Enter' && !event.shiftKey && !mod) {
        const start = area.value.lastIndexOf('\n', area.selectionStart - 1) + 1;
        const line = area.value.slice(start, area.selectionStart);
        const match = /^(\s*(?:>\s*)?)([-*+]|(\d+)([.)]))(\s+)(\[[ xX]\]\s+)?/.exec(line);
        if (!match || area.selectionStart !== area.selectionEnd) {
            return;
        }
        event.preventDefault();
        if (line.length === match[0].length) {
            // An empty item ends the list
            area.setSelectionRange(start, area.selectionStart);
            document.execCommand('insertText', false, '');
            return;
        }
        const marker = match[3] ? `${Number(match[3]) + 1}${match[4]}` : match[2];
        document.execCommand('insertText', false, `\n${match[1]}${marker}${match[5]}${match[6] ? '[ ] ' : ''}`);
    }
}

// Through insertText, so that Ctrl+Z undoes it like typing
function surround(area, before, after, placeholder) {
    const { selectionStart: start, selectionEnd: end } = area;
    const selected = area.value.slice(start, end) || placeholder;
    area.focus();
    area.setSelectionRange(start, end);
    document.execCommand('insertText', false, `${before}${selected}${after}`);
    area.setSelectionRange(start + before.length, start + before.length + selected.length);
}

// Adds the prefix to every selected line, or takes it off when they all have it
function prefixLines(area, prefix, { add = false, remove: take = false } = {}) {
    const start = area.value.lastIndexOf('\n', area.selectionStart - 1) + 1;
    let end = area.value.indexOf('\n', area.selectionEnd - (area.selectionEnd > area.selectionStart ? 1 : 0));
    end = end < 0 ? area.value.length : end;
    const lines = area.value.slice(start, end).split('\n');
    const all = lines.every((line) => line.startsWith(prefix));
    const next = lines.map((line) => {
        if (take || (all && !add)) {
            return line.startsWith(prefix) ? line.slice(prefix.length) : line.replace(/^ {1,4}/, '');
        }
        return `${prefix}${line}`;
    }).join('\n');
    area.focus();
    area.setSelectionRange(start, end);
    document.execCommand('insertText', false, next);
    area.setSelectionRange(start, start + next.length);
}

function insertAttachments(area, resources) {
    for (const resource of resources.filter(Boolean)) {
        db.resources[resource.id] = resource;
    }
    const text = resources.filter(Boolean).map((resource) => {
        const name = resource.name.replace(/[[\]]/g, '');
        return resource.mime.startsWith('image/') ? `![${name}](:/${resource.id})` : `[${name}](:/${resource.id})`;
    }).join('\n');
    if (text) {
        area.focus();
        document.execCommand('insertText', false, text);
    }
}

async function attachFiles(area, files) {
    const added = [];
    for (const file of files) {
        if (file.size > 200 * 1024 * 1024) {
            toast(t('{file} is larger than 200 MB and was not attached.', { file: file.name }));
            continue;
        }
        const resource = await window.notes.attachData(file.name, file.type, await file.arrayBuffer());
        if (resource?.error) {
            toast(resource.error);
        } else if (resource) {
            added.push(resource);
        }
    }
    insertAttachments(area, added);
}

async function showHistory(note) {
    commit();
    const revisions = Object.values(db.revisions).filter((revision) => revision.note === note.id).sort((a, b) => b.saved - a.saved);
    if (!revisions.length) {
        toast(t('No earlier versions yet. One is kept each time you come back to change a note after ten minutes away from it.'));
        return;
    }
    let chosen = revisions[0];
    const preview = h('article', { class: 'markdown history-preview' });
    const list = h('div', { class: 'history-list' });
    const show = () => {
        list.replaceChildren(...revisions.map((revision) => h('button', {
            type: 'button', class: 'history-item', 'aria-current': revision === chosen ? 'true' : null,
            onclick: () => {
                chosen = revision;
                show();
            },
        }, h('span', {}, stamp(revision.saved)), h('span', { class: 'faint small' }, revision.title || t('Untitled')))));
        renderMarkdown(preview, `# ${escapeMarkdown(chosen.title || t('Untitled'))}\n\n${chosen.body || ''}`);
    };
    show();
    const restore = await modal({
        title: t('Earlier versions'),
        text: t('A version is kept each time you come back to change a note after ten minutes away from it, up to the last 30.'),
        body: [h('div', { class: 'history' }, list, preview)],
        wide: true,
        actions: [{ label: t('Close'), value: null }, { label: t('Restore this version'), primary: true, value: () => chosen }],
    });
    if (restore) {
        // What is there now becomes a version of its own, so restoring can itself be undone
        savedNotes.set(note.id, { title: note.title, body: note.body, updated: 0 });
        editNote(note, { title: restore.title, body: restore.body });
        commit();
        renderNotes({ force: true });
        renderNav();
        toast(t('Restored. The version it replaced is in the history too.'));
    }
}

function escapeMarkdown(text) {
    return String(text).replace(/[\\`*_{}[\]()#+\-.!<>|]/g, '\\$&');
}

// Rendered into a sheet that only print shows, and printed to PDF by main.js
async function exportPdf(note) {
    commit();
    const content = h('div');
    renderMarkdown(content, note.body);
    const sheet = h('article', { class: 'print-sheet markdown' }, h('h1', { dir: 'auto' }, note.title || t('Untitled')), content);
    document.body.append(sheet);
    await Promise.all([...sheet.querySelectorAll('img')].map((image) => (image.complete ? null : new Promise((resolve) => {
        image.loading = 'eager';
        image.addEventListener('load', resolve);
        image.addEventListener('error', resolve);
    }))));
    // The name the file is offered under, English like every name the app gives a file
    const result = await window.notes.pdf(note.title || 'Untitled');
    sheet.remove();
    if (result?.error) {
        toast(result.error);
    } else if (result?.path) {
        toast(t('Saved to {path}', { path: result.path }));
    }
}

// --- Tasks -------------------------------------------------------------------------------------------

function openTasks() {
    return Object.values(db.tasks).filter((task) => !task.done);
}

function subtasksOf(id) {
    return Object.values(db.tasks).filter((task) => task.parent === id);
}

function taskOrder(a, b) {
    return (a.due || '9999').localeCompare(b.due || '9999') || (a.time || '99').localeCompare(b.time || '99') ||
        (a.priority || 4) - (b.priority || 4) || (a.order || 0) - (b.order || 0) || (a.created || 0) - (b.created || 0);
}

function roots(list) {
    const ids = new Set(list.map((task) => task.id));
    return list.filter((task) => !task.parent || !db.tasks[task.parent] || !ids.has(task.parent));
}

function taskSearch() {
    const words = terms();
    return Object.values(db.tasks).filter((task) => {
        const text = `${task.title}\n${task.notes || ''}\n${(task.labels || []).map((id) => db.labels[id]?.title || '').join(' ')}`.toLowerCase();
        return words.every((word) => text.includes(word));
    });
}

// The groups of the view, each with what a task added to it gets: { title, tasks, context, tone, section, nest }
function taskGroups(view) {
    const now = today();
    const open = openTasks();
    if (ui.query) {
        const found = taskSearch();
        return [
            { title: t('To do'), tasks: found.filter((task) => !task.done).sort(taskOrder) },
            { title: t('Completed'), tasks: found.filter((task) => task.done).sort((a, b) => b.done - a.done) },
        ].filter((group) => group.tasks.length);
    }
    switch (view.type) {
        case 'inbox':
            return [{ tasks: open.filter((task) => !task.project).sort(taskOrder), nest: true, context: { project: null } }];
        case 'today': {
            const overdue = open.filter((task) => task.due && task.due < now).sort(taskOrder);
            return [
                overdue.length ? { title: t('Overdue'), tone: 'bad', tasks: overdue } : null,
                { title: overdue.length ? dayLabel(now, { long: true }) : null, tasks: open.filter((task) => task.due === now).sort(taskOrder), context: { due: now } },
            ].filter(Boolean);
        }
        case 'upcoming': {
            const days = new Map();
            for (let day = 1; day <= 7; day += 1) {
                days.set(addDays(now, day), []);
            }
            for (const task of open.filter((item) => item.due && item.due > now).sort(taskOrder)) {
                if (!days.has(task.due)) {
                    days.set(task.due, []);
                }
                days.get(task.due).push(task);
            }
            return [...days.entries()].sort(([a], [b]) => a.localeCompare(b))
                .map(([date, tasks]) => ({ title: dayLabel(date, { long: true }), date, tasks, context: { due: date }, quiet: !tasks.length }));
        }
        case 'pinned':
            return [{ tasks: open.filter((task) => task.pinned).sort(taskOrder), context: { pinned: true } }];
        case 'completed': {
            const byDay = new Map();
            for (const task of Object.values(db.tasks).filter((item) => item.done).sort((a, b) => b.done - a.done).slice(0, 300)) {
                const day = isoDate(new Date(task.done));
                byDay.set(day, [...(byDay.get(day) || []), task]);
            }
            return [...byDay.entries()].map(([day, tasks]) => ({ title: dayLabel(day, { long: true }), tasks }));
        }
        case 'label':
            return [{ tasks: open.filter((task) => task.labels?.includes(view.id)).sort(taskOrder), context: { labels: [view.id] } }];
        case 'project': {
            const own = open.filter((task) => task.project === view.id);
            const sections = Object.values(db.sections).filter((section) => section.project === view.id)
                .sort((a, b) => (a.order || 0) - (b.order || 0));
            const known = new Set(sections.map((section) => section.id));
            return [
                { tasks: own.filter((task) => !known.has(task.section)).sort(taskOrder), nest: true, context: { project: view.id, section: null } },
                ...sections.map((section) => ({
                    title: section.title || t('Untitled'), section, nest: true,
                    tasks: own.filter((task) => task.section === section.id).sort(taskOrder),
                    context: { project: view.id, section: section.id },
                })),
            ];
        }
        default:
            return [];
    }
}

function tasksTitle() {
    if (ui.query) {
        return t('Search');
    }
    const view = ui.tasksView;
    if (view.type === 'project') {
        return db.projects[view.id]?.title || t('Untitled');
    }
    if (view.type === 'label') {
        return db.labels[view.id]?.title || '';
    }
    return { inbox: t('Inbox'), today: t('Today'), upcoming: t('Upcoming'), pinned: t('Pinned'), completed: t('Completed') }[view.type] || '';
}

function newTask(fields) {
    const task = {
        id: newId(), title: '', notes: '', project: null, section: null, parent: null, due: null, time: null,
        repeat: null, reminder: null, priority: 4, labels: [], pinned: false, done: null, created: Date.now(), order: Date.now(), ...fields,
    };
    save('tasks', task, { now: true });
    return task;
}

// "Call Sam tomorrow 5pm p1 @phone #Work every week": the words it knows are taken out of the title.
// They are English whatever the window's language is.
function parseQuick(text) {
    let title = ` ${text} `;
    const found = {};
    const take = (pattern, use) => {
        title = title.replace(pattern, (...match) => (use(...match) === false ? match[0] : ' '));
    };
    take(/\s[pP]([1-4])(?=\s)/, (_, level) => {
        found.priority = Number(level);
    });
    take(/\s(?:every\s+(\d+\s+)?(day|week|month|year)s?|(daily|weekly|monthly|yearly))(?=\s)/i, (_, count, unit, adverb) => {
        const units = { daily: 'day', weekly: 'week', monthly: 'month', yearly: 'year' };
        found.repeat = { every: Number(count) || 1, unit: unit ? unit.toLowerCase() : units[adverb.toLowerCase()] };
    });
    take(/\s#([\p{L}\p{N}_-]+)(?=\s)/u, (_, name) => {
        const key = name.toLowerCase();
        const project = Object.values(db.projects).find((item) => item.title.replace(/\s+/g, '').toLowerCase() === key);
        if (!project) {
            return false;
        }
        found.project = project.id;
        found.section = null;
        return true;
    });
    take(/\s@([\p{L}\p{N}_-]+)(?=\s)/gu, (_, name) => {
        (found.labels ||= []).push(labelFor(name));
    });
    const weekdays = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
    take(/\s(today|tod|tonight|tomorrow|tmr|next week|(?:on\s+)?(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*|\d{4}-\d{2}-\d{2})(?=\s)/i, (_, word) => {
        const lower = word.toLowerCase().replace(/^on\s+/, '');
        const now = today();
        if (/^\d{4}-\d{2}-\d{2}$/.test(lower)) {
            found.due = lower;
        } else if (['today', 'tod', 'tonight'].includes(lower)) {
            found.due = now;
        } else if (['tomorrow', 'tmr'].includes(lower)) {
            found.due = addDays(now, 1);
        } else if (lower === 'next week') {
            found.due = addDays(now, 7 - ((new Date().getDay() + 6) % 7));
        } else {
            const day = weekdays.findIndex((name) => name.startsWith(lower.slice(0, 3)));
            if (day < 0 || (lower.length > 3 && !weekdays[day].startsWith(lower))) {
                return false;
            }
            found.due = addDays(now, ((day - new Date().getDay() + 7) % 7) || 7);
        }
        return true;
    });
    take(/\s(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?=\s)/i, (_, hours, minutes, half) => {
        const hour = (Number(hours) % 12) + (half.toLowerCase() === 'pm' ? 12 : 0);
        found.time = `${pad(hour)}:${minutes || '00'}`;
    });
    take(/\s(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s)/, (_, hours, minutes) => {
        found.time = `${pad(hours)}:${minutes}`;
    });
    if ((found.time || found.repeat) && !found.due) {
        found.due = found.time && found.time < new Date().toTimeString().slice(0, 5) && !found.repeat ? addDays(today(), 1) : today();
    }
    if (found.time) {
        found.reminder = 0;
    }
    found.title = title.replace(/\s+/g, ' ').trim() || text.trim();
    return found;
}

function labelFor(title) {
    const found = Object.values(db.labels).find((label) => label.title.toLowerCase() === title.toLowerCase());
    if (found) {
        return found.id;
    }
    const label = { id: newId(), title, color: COLORS[Object.keys(db.labels).length % COLORS.length] };
    save('labels', label, { now: true });
    return label.id;
}

// The next date of a repeating task, past today when it has fallen behind
function nextDue(task) {
    let due = addInterval(task.due, task.repeat);
    for (let guard = 0; due < today() && guard < 1000; guard += 1) {
        due = addInterval(due, task.repeat);
    }
    return due;
}

function toggleDone(task) {
    const before = { ...task };
    if (!task.done && task.repeat && task.due) {
        const due = nextDue(task);
        saveTask(task, { due }, { now: true });
        toast(t('Done. Next on {day}.', { day: dayLabel(due) }), { undo: () => {
            saveTask(task, before, { now: true });
            renderTasks();
        } });
    } else if (!task.done) {
        const changed = subtasksOf(task.id).filter((child) => !child.done);
        for (const child of changed) {
            saveTask(child, { done: Date.now() });
        }
        saveTask(task, { done: Date.now() }, { now: true });
        toast(t('Completed “{task}”', { task: task.title || t('Untitled') }), { undo: () => {
            saveTask(task, { done: null }, { now: true });
            changed.forEach((child) => saveTask(child, { done: null }));
            renderTasks();
            renderNav();
        } });
    } else {
        saveTask(task, { done: null }, { now: true });
    }
    renderNav();
    renderTasks();
}

function deleteTask(task) {
    const gone = [task, ...subtasksOf(task.id)];
    remove('tasks', gone.map((item) => item.id));
    if (gone.some((item) => item.id === ui.task)) {
        ui.task = null;
    }
    renderNav();
    renderTasks({ force: true });
    toast(t('Deleted “{task}”', { task: task.title || t('Untitled') }), { undo: () => {
        gone.forEach((item) => save('tasks', item, { now: true }));
        renderNav();
        renderTasks({ force: true });
    } });
}

async function newProject() {
    const title = await ask({ title: t('New project'), label: t('Name'), confirm: t('Create') });
    if (title) {
        const project = { id: newId(), title, color: COLORS[Object.keys(db.projects).length % COLORS.length], order: Date.now(), created: Date.now() };
        save('projects', project, { now: true });
        showTasks({ type: 'project', id: project.id });
    }
}

function colorItems(item, kind) {
    return COLORS.map((color) => ({
        label: COLOR_NAMES[color], color, checked: item.color === color,
        run: () => {
            save(kind, Object.assign(item, { color }));
            render();
        },
    }));
}

function projectMenu(anchor, project) {
    menu(anchor, [
        { label: t('Rename'), icon: 'edit', run: async () => {
            const title = await ask({ title: t('Rename project'), label: t('Name'), value: project.title });
            if (title) {
                save('projects', Object.assign(project, { title }));
                render();
            }
        } },
        { label: t('Colour'), icon: 'tag', run: () => menu(anchor, colorItems(project, 'projects')) },
        { label: t('Add a section'), icon: 'plus', run: () => newSection(project) },
        '-',
        { label: t('Delete'), icon: 'trash', danger: true, run: async () => {
            const tasks = Object.values(db.tasks).filter((task) => task.project === project.id);
            if (await confirmDialog({
                title: t('Delete {name}?', { name: project.title }),
                text: t('{count, plural, =0 {It has no tasks.} one {Its # task is deleted with it.} other {Its # tasks are deleted with it.}}', { count: tasks.length }),
                confirm: t('Delete'),
            })) {
                remove('tasks', tasks.map((task) => task.id));
                remove('sections', Object.values(db.sections).filter((section) => section.project === project.id).map((section) => section.id));
                remove('projects', [project.id]);
                showTasks({ type: 'inbox' });
            }
        } },
    ]);
}

async function newSection(project) {
    const title = await ask({ title: t('New section in {project}', { project: project.title }), label: t('Name'), confirm: t('Create') });
    if (title) {
        save('sections', { id: newId(), project: project.id, title, order: Date.now() }, { now: true });
        showTasks({ type: 'project', id: project.id });
    }
}

function sectionMenu(anchor, section) {
    menu(anchor, [
        { label: t('Rename'), icon: 'edit', run: async () => {
            const title = await ask({ title: t('Rename section'), label: t('Name'), value: section.title });
            if (title) {
                save('sections', Object.assign(section, { title }));
                renderTasks();
            }
        } },
        { label: t('Delete'), icon: 'trash', danger: true, run: async () => {
            if (await confirmDialog({ title: t('Delete the section {section}?', { section: section.title }), text: t('Its tasks stay in the project.'), confirm: t('Delete') })) {
                for (const task of Object.values(db.tasks).filter((item) => item.section === section.id)) {
                    saveTask(task, { section: null });
                }
                remove('sections', [section.id]);
                renderTasks();
            }
        } },
    ]);
}

async function newLabel() {
    const title = await ask({ title: t('New label'), label: t('Name'), confirm: t('Create') });
    if (title) {
        showTasks({ type: 'label', id: labelFor(title) });
    }
}

function labelMenu(anchor, label) {
    menu(anchor, [
        { label: t('Rename'), icon: 'edit', run: async () => {
            const title = await ask({ title: t('Rename label'), label: t('Name'), value: label.title });
            if (title) {
                save('labels', Object.assign(label, { title }));
                render();
            }
        } },
        { label: t('Colour'), icon: 'tag', run: () => menu(anchor, colorItems(label, 'labels')) },
        '-',
        { label: t('Delete'), icon: 'trash', danger: true, run: async () => {
            if (await confirmDialog({ title: t('Delete the label {label}?', { label: label.title }), text: t('The tasks stay; only the label is taken off them.'), confirm: t('Delete') })) {
                for (const task of Object.values(db.tasks).filter((item) => item.labels?.includes(label.id))) {
                    saveTask(task, { labels: task.labels.filter((id) => id !== label.id) });
                }
                remove('labels', [label.id]);
                showTasks({ type: 'inbox' });
            }
        } },
    ]);
}

const tasksLayout = h('div', { class: 'tasks-layout' });
const taskListPane = h('section', { class: 'task-pane', 'aria-label': t('Tasks') });
const detailPane = h('aside', { class: 'detail-pane', 'aria-label': t('Task') });
tasksLayout.append(taskListPane, detailPane);
let detailFor = null;

function renderTasks({ force = false } = {}) {
    if (main.firstChild !== tasksLayout) {
        main.replaceChildren(tasksLayout);
        force = true;
    }
    if (ui.task && !db.tasks[ui.task]) {
        ui.task = null;
    }
    tasksLayout.classList.toggle('with-detail', Boolean(ui.task));
    renderTaskList();
    if (force || detailFor !== ui.task) {
        detailFor = ui.task;
        detailPane.replaceChildren(ui.task ? buildDetail(db.tasks[ui.task]) : '');
    }
}

function renderTaskList() {
    const scroller = taskListPane.querySelector('.task-scroll');
    const scroll = scroller?.scrollTop || 0;
    const view = ui.tasksView;
    const groups = taskGroups(view);
    const project = view.type === 'project' ? db.projects[view.id] : null;
    const addable = !ui.query && view.type !== 'completed';
    const context = groups.find((group) => group.context)?.context || {};
    const subtitle = view.type === 'today' && !ui.query ? capital(new Date().toLocaleDateString(t.locale, { weekday: 'long', day: 'numeric', month: 'long' })) : '';
    const head = h('div', { class: 'tasks-head' },
        project ? h('span', { class: 'dot big', 'data-color': project.color || 'violet' }) : null,
        h('div', { class: 'grow' }, h('h1', {}, tasksTitle()), subtitle ? h('p', { class: 'faint small' }, subtitle) : null),
        project ? button(t('Section'), () => newSection(project), { small: true, icon: 'plus' }) : null,
        project ? iconButton('more', t('More'), (event) => projectMenu(event.currentTarget, project)) : null);
    const body = [];
    if (addable) {
        body.push(quickAdd(view.type === 'upcoming' ? { due: addDays(today(), 1) } : context, { main: true }));
    }
    let shown = 0;
    for (const group of groups) {
        const rows = [];
        const list = group.nest ? roots(group.tasks) : group.tasks;
        for (const task of list) {
            rows.push(taskRow(task, 0, group));
            if (group.nest) {
                const walk = (parent, depth) => {
                    for (const child of subtasksOf(parent.id).filter((item) => !item.done).sort(taskOrder)) {
                        rows.push(taskRow(child, depth, group));
                        if (depth < 4) {
                            walk(child, depth + 1);
                        }
                    }
                };
                walk(task, 1);
            }
        }
        shown += list.length;
        if (!group.title && !rows.length) {
            continue;
        }
        body.push(h('div', { class: `task-group${group.quiet ? ' quiet' : ''}` },
            group.title ? h('div', { class: `group-head${group.tone ? ` ${group.tone}` : ''}` },
                h('h2', { class: 'grow' }, group.title, rows.length ? h('span', { class: 'faint' }, ` ${t.number(list.length)}`) : null),
                group.section ? iconButton('more', t('More'), (event) => sectionMenu(event.currentTarget, group.section)) : null) : null,
            rows,
            group.section || (view.type === 'upcoming' && group.context) ? quickAdd(group.context) : null));
    }
    // A project's and the inbox's finished tasks, out of the way until asked for
    if (!ui.query && (view.type === 'project' || view.type === 'inbox')) {
        const done = Object.values(db.tasks).filter((task) => task.done && (task.project || null) === (view.type === 'project' ? view.id : null))
            .sort((a, b) => b.done - a.done);
        if (done.length) {
            body.push(h('div', { class: 'task-group' },
                linkButton(ui.showDone
                    ? t('{count, plural, one {Hide # completed task} other {Hide # completed tasks}}', { count: done.length })
                    : t('{count, plural, one {Show # completed task} other {Show # completed tasks}}', { count: done.length }), () => {
                    ui.showDone = !ui.showDone;
                    renderTasks();
                }, { quiet: true, small: true, icon: 'done' }),
                ui.showDone ? done.map((task) => taskRow(task, 0, {})) : null));
        }
    }
    if (!shown && view.type !== 'upcoming' && view.type !== 'project') {
        body.push(h('div', { class: 'task-empty' }, icon(ui.query ? 'search' : view.type === 'completed' ? 'done' : 'mark-ok', 36),
            h('p', {}, ui.query ? t('No task has all of those words.')
                : { today: t('Nothing due today.'), inbox: t('Your inbox is empty.'), pinned: t('Pin a task to keep it here.'), completed: t('Nothing completed yet.'), label: t('No task has this label.') }[view.type])));
    }
    const newScroller = h('div', { class: 'task-scroll' }, h('div', { class: 'task-column' }, head, body));
    taskListPane.replaceChildren(newScroller);
    newScroller.scrollTop = scroll;
}

function quickAdd(context, { main: first = false } = {}) {
    const input = h('input', {
        type: 'text', class: 'quick-input', spellcheck: 'false', 'aria-label': t('Add a task'),
        placeholder: first ? t('Add a task') : t('Add a task here'),
    });
    // The words parseQuick knows, which are English in every language
    const hint = h('p', { class: 'quick-hint faint small' },
        t('Knows: {words}, @label, #project', { words: 'today, tomorrow, friday, 5pm, 17:30, every week, p1–p4' }));
    const form = h('form', {
        class: `quick${first ? ' first' : ''}`,
        onsubmit: (event) => {
            event.preventDefault();
            const text = input.value.trim();
            if (!text) {
                return;
            }
            const parsed = parseQuick(text);
            newTask({ ...context, ...parsed, labels: [...new Set([...(context.labels || []), ...(parsed.labels || [])])] });
            input.value = '';
            renderNav();
            renderTaskList();
            const again = taskListPane.querySelector(first ? '.quick.first input' : `.quick[data-context="${CSS.escape(form.dataset.context)}"] input`);
            again?.focus();
        },
        'data-context': JSON.stringify(context),
    }, icon('plus', 18, 'quick-plus'), input);
    return first ? h('div', { class: 'quick-wrap' }, form, hint) : form;
}

function taskRow(task, depth, group) {
    const project = task.project ? db.projects[task.project] : null;
    const now = today();
    const children = subtasksOf(task.id);
    const meta = [
        task.due ? h('span', { class: `meta-due${task.due < now && !task.done ? ' late' : task.due === now ? ' today' : ''}` },
            icon('calendar', 13), task.time ? t('{day} {time}', { day: dayLabel(task.due), time: timeLabel(task.time) }) : dayLabel(task.due)) : null,
        task.repeat ? icon('repeat', 13) : null,
        Number.isInteger(task.reminder) && task.time ? icon('bell', 13) : null,
        children.length ? h('span', {}, icon('checklist', 13), `${t.number(children.filter((child) => child.done).length)}/${t.number(children.length)}`) : null,
        task.notes ? icon('note', 13) : null,
        task.parent && !group.nest && db.tasks[task.parent] ? h('span', { class: 'faint' }, t('in {task}', { task: db.tasks[task.parent].title || t('Untitled') })) : null,
        (task.labels || []).map((id) => db.labels[id]).filter(Boolean).map((label) => h('span', { class: 'label-chip', 'data-color': label.color || 'violet' }, label.title)),
        !['project', 'inbox'].includes(ui.tasksView.type) || ui.query ? h('span', { class: 'meta-project', 'data-color': project?.color || null },
            project ? h('span', { class: 'dot' }) : icon('inbox', 13), project?.title || t('Inbox')) : null,
    ].flat().filter(Boolean);
    return h('div', {
        class: `task-row${task.done ? ' done' : ''}`, 'aria-current': task.id === ui.task ? 'true' : null,
        'data-priority': String(task.priority || 4), 'data-depth': depth ? String(depth) : null,
    },
    h('button', {
        type: 'button', class: 'check', role: 'checkbox', 'aria-checked': String(Boolean(task.done)),
        'aria-label': task.done ? t('Mark as not done') : t('Complete'), onclick: () => toggleDone(task),
    }, icon('mark-ok', 14)),
    h('button', {
        type: 'button', class: 'task-main', onclick: () => {
            commit();
            ui.task = task.id;
            renderTasks();
        },
    },
    h('span', { class: 'task-title' }, task.title || t('Untitled')),
    task.notes ? h('span', { class: 'task-notes' }, snippet(task.notes)) : null,
    meta.length ? h('span', { class: 'task-meta' }, meta) : null),
    task.pinned ? h('span', { class: 'pin-mark', title: t('Pinned') }, icon('pin', 15)) : null);
}

function field(label, control, { hidden = false } = {}) {
    return h('label', { class: 'detail-field', hidden }, h('span', { class: 'detail-label' }, label), control);
}

function autosize(area) {
    area.style.height = 'auto';
    area.style.height = `${area.scrollHeight}px`;
}

function buildDetail(task) {
    const refresh = debounce(() => {
        renderTaskList();
        renderNav();
    }, 300);
    const rebuild = () => {
        renderNav();
        renderTasks({ force: true });
    };
    // The task's own text is laid out by itself, as a note's is
    const title = h('textarea', { class: 'detail-title', rows: '1', placeholder: t('Task'), 'aria-label': t('Task'), dir: 'auto', spellcheck: 'false' });
    title.value = task.title || '';
    title.addEventListener('input', () => {
        saveTask(task, { title: title.value.replace(/\n/g, ' ') });
        autosize(title);
        refresh();
    });
    title.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
            event.preventDefault();
            notes.focus();
        }
    });
    const notes = h('textarea', { class: 'detail-notes', placeholder: t('Notes'), 'aria-label': t('Notes'), dir: 'auto', spellcheck: 'false' });
    notes.value = task.notes || '';
    notes.addEventListener('input', () => {
        saveTask(task, { notes: notes.value });
        autosize(notes);
        refresh();
    });

    const projects = Object.values(db.projects).sort(byTitle);
    const project = h('select', {
        onchange: (event) => {
            saveTask(task, { project: event.target.value || null, section: null }, { now: true });
            for (const child of subtasksOf(task.id)) {
                saveTask(child, { project: task.project, section: null });
            }
            rebuild();
        },
    }, h('option', { value: '', selected: !task.project }, t('Inbox')), projects.map((item) => h('option', { value: item.id, selected: item.id === task.project }, item.title)));
    const sections = Object.values(db.sections).filter((section) => section.project === task.project).sort((a, b) => (a.order || 0) - (b.order || 0));
    const section = h('select', {
        onchange: (event) => {
            saveTask(task, { section: event.target.value || null }, { now: true });
            rebuild();
        },
    }, h('option', { value: '', selected: !task.section }, t('No section')), sections.map((item) => h('option', { value: item.id, selected: item.id === task.section }, item.title)));

    const date = h('input', { type: 'date', value: task.due || '' });
    date.addEventListener('change', () => {
        saveTask(task, date.value ? { due: date.value } : { due: null, time: null, reminder: null, repeat: null }, { now: true });
        rebuild();
    });
    const time = h('input', { type: 'time', value: task.time || '', disabled: !task.due });
    time.addEventListener('change', () => {
        saveTask(task, time.value ? { time: time.value, reminder: task.reminder ?? 0 } : { time: null, reminder: null }, { now: true });
        rebuild();
    });
    const repeatUnit = h('select', {
        disabled: !task.due,
        onchange: (event) => {
            saveTask(task, { repeat: event.target.value ? { every: task.repeat?.every || 1, unit: event.target.value } : null }, { now: true });
            rebuild();
        },
    }, h('option', { value: '', selected: !task.repeat }, t('Does not repeat')),
    Object.entries(UNITS).map(([unit, label]) => h('option', { value: unit, selected: task.repeat?.unit === unit }, label(task.repeat?.every > 1 ? task.repeat.every : 1))));
    const repeatEvery = h('input', { type: 'number', min: '1', max: '365', value: String(task.repeat?.every || 1), class: 'every', 'aria-label': t('Every how many') });
    repeatEvery.addEventListener('change', () => {
        const every = Math.min(365, Math.max(1, Math.round(Number(repeatEvery.value) || 1)));
        saveTask(task, { repeat: { ...task.repeat, every } }, { now: true });
        rebuild();
    });
    const reminder = h('select', {
        disabled: !task.time,
        onchange: (event) => {
            saveTask(task, { reminder: event.target.value === '' ? null : Number(event.target.value) }, { now: true });
            refresh();
        },
    }, REMINDERS.map(([value, label]) => h('option', { value: value === null ? '' : String(value), selected: (task.reminder ?? null) === value }, label)));

    // P1 to P3 are written as the quick add takes them, p1 to p3, and so are the same in every language
    const priority = h('div', { class: 'priority', role: 'radiogroup', 'aria-label': t('Priority') }, [1, 2, 3, 4].map((level) => h('button', {
        type: 'button', role: 'radio', 'aria-checked': String((task.priority || 4) === level), title: PRIORITIES[level], 'data-priority': String(level),
        onclick: () => {
            saveTask(task, { priority: level }, { now: true });
            rebuild();
        },
    }, icon('flag', 16), h('span', {}, level === 4 ? t('None') : `P${level}`))));

    const labelChips = h('div', { class: 'label-edit' },
        (task.labels || []).map((id) => db.labels[id]).filter(Boolean).map((label) => h('span', { class: 'label-chip', 'data-color': label.color || 'violet' }, label.title,
            h('button', { type: 'button', class: 'chip-x', 'aria-label': t('Remove {name}', { name: label.title }), onclick: () => {
                saveTask(task, { labels: task.labels.filter((id) => id !== label.id) }, { now: true });
                rebuild();
            } }, icon('close', 12)))),
        h('button', { type: 'button', class: 'add-label', onclick: (event) => menu(event.currentTarget, [
            ...Object.values(db.labels).sort(byTitle).filter((label) => !task.labels?.includes(label.id)).map((label) => ({
                label: label.title, color: label.color || 'violet', run: () => {
                    saveTask(task, { labels: [...(task.labels || []), label.id] }, { now: true });
                    rebuild();
                },
            })),
            { label: t('New label…'), icon: 'plus', run: async () => {
                const name = await ask({ title: t('New label'), label: t('Name'), confirm: t('Create') });
                if (name) {
                    saveTask(task, { labels: [...new Set([...(task.labels || []), labelFor(name)])] }, { now: true });
                    rebuild();
                }
            } },
        ]) }, icon('plus', 14), t('Label')));

    const children = subtasksOf(task.id).sort((a, b) => Boolean(a.done) - Boolean(b.done) || taskOrder(a, b));
    const subInput = h('input', { type: 'text', class: 'quick-input', placeholder: t('Add a subtask'), 'aria-label': t('Add a subtask'), spellcheck: 'false' });
    const subtasks = h('div', { class: 'subtasks' },
        h('h3', { class: 'detail-label' }, t('Subtasks')),
        children.map((child) => h('div', { class: `sub-row${child.done ? ' done' : ''}`, 'data-priority': String(child.priority || 4) },
            h('button', { type: 'button', class: 'check', role: 'checkbox', 'aria-checked': String(Boolean(child.done)), 'aria-label': t('Complete'), onclick: () => {
                toggleDone(child);
                renderTasks({ force: true });
            } }, icon('mark-ok', 13)),
            h('button', { type: 'button', class: 'sub-title', onclick: () => {
                ui.task = child.id;
                renderTasks();
            } }, child.title || t('Untitled')))),
        h('form', { class: 'quick', onsubmit: (event) => {
            event.preventDefault();
            const text = subInput.value.trim();
            if (text) {
                const parsed = parseQuick(text);
                newTask({ project: task.project, section: task.section, ...parsed, parent: task.id });
                rebuild();
                detailPane.querySelector('.subtasks input')?.focus();
            }
        } }, icon('plus', 16, 'quick-plus'), subInput));

    const parent = task.parent ? db.tasks[task.parent] : null;
    const node = h('div', { class: 'detail' },
        h('div', { class: 'detail-head' },
            parent ? linkButton(parent.title || t('Untitled'), () => {
                ui.task = parent.id;
                renderTasks();
            }, { icon: 'undo', quiet: true, small: true }) : h('span', { class: 'faint small' }, task.project ? db.projects[task.project]?.title : t('Inbox')),
            h('span', { class: 'grow' }),
            iconButton('pin', task.pinned ? t('Unpin') : t('Pin'), () => {
                saveTask(task, { pinned: !task.pinned }, { now: true });
                rebuild();
            }, { active: task.pinned }),
            iconButton('trash', t('Delete'), () => deleteTask(task)),
            iconButton('close', t('{action} ({key})', { action: t('Close'), key: 'Esc' }), () => {
                ui.task = null;
                renderTasks();
            })),
        h('div', { class: `detail-top${task.done ? ' done' : ''}`, 'data-priority': String(task.priority || 4) },
            h('button', { type: 'button', class: 'check', role: 'checkbox', 'aria-checked': String(Boolean(task.done)), 'aria-label': t('Complete'), onclick: () => {
                toggleDone(task);
                renderTasks({ force: true });
            } }, icon('mark-ok', 14)),
            title),
        notes,
        h('div', { class: 'detail-fields' },
            field(t('Project'), project),
            field(t('Section'), section, { hidden: !sections.length }),
            h('div', { class: 'detail-field' }, h('span', { class: 'detail-label' }, t('Date')),
                h('div', { class: 'inline' }, date, time, task.due ? iconButton('close', t('No date'), () => {
                    saveTask(task, { due: null, time: null, reminder: null, repeat: null }, { now: true });
                    rebuild();
                }) : null)),
            h('div', { class: 'detail-field' }, h('span', { class: 'detail-label' }, t('Repeat')),
                h('div', { class: 'inline' }, repeatUnit, task.repeat ? repeatEvery : null)),
            field(t('Reminder'), reminder),
            h('div', { class: 'detail-field' }, h('span', { class: 'detail-label' }, t('Priority')), priority),
            h('div', { class: 'detail-field' }, h('span', { class: 'detail-label' }, t('Labels')), labelChips)),
        subtasks,
        h('p', { class: 'detail-foot faint small' }, [
            t('Added {date}', { date: stamp(task.created || Date.now()) }),
            task.done ? t('Completed {date}', { date: stamp(task.done) }) : null,
        ].filter(Boolean).join(' · ')));
    requestAnimationFrame(() => {
        autosize(title);
        autosize(notes);
        if (!task.title) {
            title.focus();
        }
    });
    return node;
}

// --- Settings ----------------------------------------------------------------------------------------

function settingRow(iconName, tone, heading, detail, ...controls) {
    return h('div', { class: 'row' },
        h('div', { class: `row-icon tone ${tone}` }, icon(iconName, 20)),
        h('div', { class: 'row-text grow' }, h('span', { class: 'row-title' }, heading), detail ? h('span', { class: 'row-detail' }, detail) : null),
        controls.length ? h('div', { class: 'row-side' }, controls) : null);
}

function toggleSwitch(on, label, onchange) {
    return h('button', { type: 'button', class: 'switch', role: 'switch', 'aria-checked': String(on), 'aria-label': label, onclick: () => onchange(!on) }, h('span'));
}

async function encryptionDialog(action) {
    const fields = passphraseFields({ current: action !== 'enable' });
    const titles = {
        enable: [t('Turn on encryption'), t('Choose a passphrase. From now on your notes, tasks and attachments are encrypted on disk.'), t('Encrypt')],
        change: [t('Change the passphrase'), t('Your notes stay encrypted with the same key; only the passphrase that opens it changes.'), t('Change')],
        disable: [t('Turn off encryption'), t('Your notes, tasks and attachments are written to disk as they are, readable by anyone who can read your files.'), t('Turn off')],
    }[action];
    const body = action === 'disable' ? [fields.old, fields.error] : fields.nodes;
    const result = await modal({
        title: titles[0], text: titles[1], body,
        actions: [{ label: t('Cancel'), value: null }, {
            label: titles[2], primary: true, danger: action === 'disable',
            value: async () => {
                const next = action === 'disable' ? '' : fields.check();
                if (next === null) {
                    return undefined;
                }
                if (fields.old && !fields.old.value) {
                    fields.error.textContent = t('Enter the current passphrase.');
                    return undefined;
                }
                fields.error.textContent = t('Working…');
                const answer = await window.notes.encryption({ action, current: fields.old?.value || '', next });
                if (answer?.error) {
                    fields.error.textContent = answer.error;
                    return undefined;
                }
                return answer;
            },
        }],
    });
    if (result) {
        ui.encrypted = result.encrypted;
        ui.passkeys = result.passkeys;
        render();
        toast({ enable: t('Encryption is on.'), change: t('The passphrase is changed.'), disable: t('Encryption is off.') }[action]);
    }
}

// Adds the security key that is plugged in as a passkey. It is asked twice, once to make the passkey and
// once to use it, so it blinks twice.
async function passkeyDialog() {
    const current = h('input', { class: 'field', type: 'password', placeholder: t('Current passphrase'), 'aria-label': t('Current passphrase'), autocomplete: 'current-password' });
    const pin = h('input', { class: 'field', type: 'password', placeholder: t('Security key PIN'), 'aria-label': t('Security key PIN') });
    const hint = h('p', { class: 'hint small' }, t('Leave the PIN empty for a key that reads your fingerprint.'));
    const error = h('p', { class: 'error small', role: 'alert' });
    let adding = false;
    const result = await modal({
        title: t('Add a passkey'),
        text: t('Plug in your security key. It will open your notes with its PIN or your fingerprint, and your passphrase keeps working.'),
        body: [current, pin, hint, error],
        actions: [{ label: t('Cancel'), value: null }, { label: t('Add'), primary: true, value: async () => {
            if (adding) {
                return undefined;
            }
            if (!current.value) {
                error.textContent = t('Enter the current passphrase.');
                return undefined;
            }
            adding = true;
            keyStatus(error, t('Touch your security key each time it blinks: twice.'), true);
            const answer = await window.notes.passkeyAdd({ current: current.value, pin: pin.value });
            adding = false;
            if (answer?.error) {
                keyStatus(error, answer.error);
                return undefined;
            }
            return answer;
        } }],
    });
    if (!result) {
        // Closed while the key was still waiting to be touched
        window.notes.passkeyCancel();
        return;
    }
    ui.passkeys = result.passkeys;
    render();
    toast(t('The passkey is added.'));
}

async function removePasskey(passkey) {
    const sure = await confirmDialog({
        title: t('Remove {name}?', { name: passkey.name }),
        text: t('It will no longer open your notes. Your passphrase keeps working.'),
        confirm: t('Remove'),
    });
    if (!sure) {
        return;
    }
    const result = await window.notes.passkeyRemove(passkey.id);
    if (result?.error) {
        toast(result.error);
        return;
    }
    ui.passkeys = result.passkeys;
    render();
}

// What an import brought in, by the kinds main.js counts
const COUNTED = {
    notes: (count) => t('{count, plural, one {# note} other {# notes}}', { count }),
    notebooks: (count) => t('{count, plural, one {# notebook} other {# notebooks}}', { count }),
    tasks: (count) => t('{count, plural, one {# task} other {# tasks}}', { count }),
    projects: (count) => t('{count, plural, one {# project} other {# projects}}', { count }),
    attachments: (count) => t('{count, plural, one {# attachment} other {# attachments}}', { count }),
};

async function runImport() {
    commit();
    let result = await window.notes.import();
    if (result?.passphrase) {
        const input = h('input', { class: 'field', type: 'password', placeholder: t('Passphrase'), 'aria-label': t('Passphrase') });
        const error = h('p', { class: 'error small', role: 'alert' });
        result = await modal({
            title: t('Open the backup'),
            text: t('{file} is encrypted. Enter the passphrase your notes had when it was made.', { file: result.passphrase }),
            body: [input, error],
            actions: [{ label: t('Cancel'), value: null }, { label: t('Import'), primary: true, value: async () => {
                error.textContent = t('Opening…');
                const answer = await window.notes.importBackup(input.value);
                if (answer?.error) {
                    error.textContent = answer.error;
                    return undefined;
                }
                return answer;
            } }],
        });
    }
    if (!result) {
        return;
    }
    if (result.error) {
        toast(result.error);
        return;
    }
    if (result.data) {
        resetDb(result.data);
        render();
    }
    if (result.counts) {
        const parts = Object.entries(result.counts).filter(([kind, count]) => count && COUNTED[kind])
            .map(([kind, count]) => COUNTED[kind](count));
        toast(parts.length ? t('Imported {items}.', { items: t.list(parts) }) : t('Nothing was found to import.'));
    }
    // Each one a sentence of main.js's, which says which file it was and why
    for (const skipped of result.skipped || []) {
        toast(skipped);
    }
}

async function runExport(kind) {
    commit();
    const result = await (kind === 'backup' ? window.notes.backup() : window.notes.exportMarkdown());
    if (result?.error) {
        toast(result.error);
    } else if (result?.path) {
        toast(kind === 'backup' ? t('Backed up to {path}', { path: result.path })
            : t('Exported {notes, plural, one {# note} other {# notes}} and {tasks, plural, one {# task} other {# tasks}} to {path}',
                { notes: result.notes, tasks: result.tasks, path: result.path }));
    }
}

function renderSettings() {
    const minutes = db.settings.autoLock ?? 10;
    const background = db.settings.background !== false;
    const encryption = ui.encrypted
        ? settingRow('shield', 'ok', t('Encrypted'),
            ui.passkeys.length
                ? t('AES-256-GCM, under a key that opens only with your passphrase (scrypt, 128 MiB a guess) or a passkey. There is no public-key cryptography in it for a quantum computer to break, and AES-256 keeps 128-bit strength against one.')
                : t('AES-256-GCM, under a key that opens only with your passphrase (scrypt, 128 MiB a guess). There is no public-key cryptography in it for a quantum computer to break, and AES-256 keeps 128-bit strength against one.'),
            button(t('Change passphrase'), () => encryptionDialog('change'), { small: true, icon: 'key' }))
        : settingRow('unlock', 'off', t('Not encrypted'),
            t('Your notes are on disk as they are. Anyone who can read your files can read them.'),
            button(t('Turn on encryption'), () => encryptionDialog('enable'), { small: true, primary: true, icon: 'lock' }));
    const lockAfter = [
        ...[5, 10, 15, 30].map((count) => [count, t('{count, plural, one {# minute} other {# minutes}}', { count })]),
        [60, t('{count, plural, one {# hour} other {# hours}}', { count: 1 })],
        [0, t('Only then')],
    ];
    const page = h('div', { class: 'page' },
        h('div', { class: 'page-head' }, h('h1', {}, t('Settings')),
            h('p', { class: 'lead' }, t('Everything stays on this computer. Nothing is synced, and the app never connects to the internet.'))),
        h('section', { class: 'section' }, h('h2', {}, t('Encryption')),
            h('div', { class: 'card list' },
                encryption,
                ui.encrypted ? settingRow('key', 'info', t('Passkeys'),
                    t('A security key opens your notes with its PIN or your fingerprint, so that you need not type the passphrase. The passphrase keeps working.'),
                    button(t('Add a passkey'), passkeyDialog, { small: true, icon: 'plus' })) : null,
                ui.passkeys.map((passkey) => settingRow('key', 'ok', passkey.name, t('Added {date}', { date: stamp(passkey.created) }),
                    button(t('Remove'), () => removePasskey(passkey), { small: true }))),
                ui.encrypted ? settingRow('lock', 'info', t('Lock when away'),
                    t('Locks after this long without using Notes, and whenever the screen locks, the computer sleeps or the window closes.'),
                    h('select', { class: 'compact', 'aria-label': t('Lock after'), onchange: (event) => {
                        db.settings.autoLock = Number(event.target.value);
                        window.notes.settings({ autoLock: db.settings.autoLock });
                    } }, lockAfter.map(([value, label]) => h('option', { value: String(value), selected: value === minutes }, label)))) : null,
                ui.encrypted ? settingRow('unlock', 'info', t('Turn off encryption'), t('Writes everything back to disk unencrypted.'),
                    button(t('Turn off'), () => encryptionDialog('disable'), { small: true })) : null)),
        h('section', { class: 'section' }, h('h2', {}, t('Reminders')),
            h('div', { class: 'card list' },
                settingRow('bell', 'accent', t('Keep running for reminders'),
                    t('When you close the window, Notes stays running in the background until the reminders still to come have gone off. Reminders only go off while Notes is running.'),
                    toggleSwitch(background, t('Keep running for reminders'), (on) => {
                        db.settings.background = on;
                        window.notes.settings({ background: on });
                        renderSettings();
                    })))),
        h('section', { class: 'section' }, h('h2', {}, t('Import')),
            h('div', { class: 'card list' },
                settingRow('notes', 'accent', t('From Joplin'),
                    t('In Joplin, choose File, Export all, JEX, then import the .jex file here. Notebooks, notes, tags, attachments and to-dos all come across.'),
                    button(t('Import…'), runImport, { small: true, icon: 'upload' })),
                settingRow('done', 'accent', t('From Planify'),
                    t('In Planify, open Preferences, Backup and create a backup, then import its .json file here. Planify keeps them in {folder}.',
                        { folder: '~/.var/app/io.github.alainm23.planify/data/io.github.alainm23.planify/backups' }),
                    button(t('Import…'), runImport, { small: true, icon: 'upload' })),
                // Imported is the notebook's name in every language: main.js finds it again by it
                settingRow('note', 'accent', t('Markdown files, or a Notes backup'),
                    t('Markdown files go into a notebook called {notebook}. A backup is added to what is here, and asks for the passphrase it was made with.',
                        { notebook: 'Imported' }),
                    button(t('Import…'), runImport, { small: true, icon: 'upload' })))),
        h('section', { class: 'section' }, h('h2', {}, t('Back up and export')),
            h('div', { class: 'card list' },
                settingRow('archive', 'accent', t('Back up to a file'),
                    ui.encrypted ? t('One file with everything in it, encrypted like your notes. It opens with the passphrase you have now, on any computer.')
                        : t('One file with everything in it. It is not encrypted, because your notes are not.'),
                    button(t('Back up…'), () => runExport('backup'), { small: true, icon: 'download' })),
                settingRow('download', 'info', t('Export as Markdown'),
                    t('Every note as a Markdown file in a folder per notebook, and every project as a checklist. The files are not encrypted.'),
                    button(t('Export…'), () => runExport('markdown'), { small: true, icon: 'download' })))),
        h('section', { class: 'section' }, h('h2', {}, t('Where they are')),
            h('div', { class: 'command' }, h('code', { dir: 'ltr' }, ui.dir))));
    main.replaceChildren(page);
}

// --- Everything --------------------------------------------------------------------------------------

function remember() {
    try {
        localStorage.setItem('view', JSON.stringify({ mode: ui.mode === 'settings' ? 'notes' : ui.mode, notesView: ui.notesView, note: ui.note, tasksView: ui.tasksView, collapsed: ui.collapsed }));
    } catch {
        // Only a convenience
    }
}

function recall() {
    try {
        const saved = JSON.parse(localStorage.getItem('view') || '{}');
        Object.assign(ui, Object.fromEntries(Object.entries(saved).filter(([name]) => ['mode', 'notesView', 'note', 'tasksView', 'collapsed'].includes(name))));
    } catch {
        // Only a convenience
    }
}

function clearQuery() {
    ui.query = '';
    search.value = '';
}

function render() {
    if (ui.status !== 'open') {
        renderGate();
        return;
    }
    document.body.classList.remove('gated');
    document.body.dataset.mode = ui.mode;
    lockButton.hidden = !ui.encrypted;
    search.placeholder = ui.mode === 'tasks' ? t('Search tasks') : t('Search notes');
    renderNav();
    if (ui.mode === 'settings') {
        editor = null;
        detailFor = null;
        renderSettings();
    } else if (ui.mode === 'tasks') {
        renderTasks();
    } else {
        renderNotes();
    }
}

function applyState(state) {
    if (!state || state.error) {
        toast(state?.error || t('Something went wrong.'));
        return;
    }
    ui.status = state.status;
    ui.encrypted = state.encrypted;
    ui.passkeys = state.passkeys || [];
    ui.dir = state.dir;
    resetDb(state.data);
    // Views that point at something no longer there fall back to the defaults
    if ((ui.notesView.type === 'notebook' && !db.notebooks[ui.notesView.id]) || (ui.notesView.type === 'tag' && !db.tags[ui.notesView.id])) {
        ui.notesView = { type: 'all' };
    }
    if ((ui.tasksView.type === 'project' && !db.projects[ui.tasksView.id]) || (ui.tasksView.type === 'label' && !db.labels[ui.tasksView.id])) {
        ui.tasksView = { type: 'today' };
    }
    if (!db.notes[ui.note]) {
        ui.note = sortNotes(notesIn(ui.notesView))[0]?.id || null;
    }
    editor = null;
    detailFor = null;
    render();
}

function setMode(mode) {
    commit();
    closeMenu();
    ui.mode = mode;
    clearQuery();
    remember();
    render();
}

async function lockNow() {
    if (!ui.encrypted) {
        return;
    }
    commit();
    await window.notes.lock();
}

for (const node of modeButtons) {
    node.addEventListener('click', () => setMode(node.dataset.mode));
}
document.getElementById('open-settings').addEventListener('click', () => setMode('settings'));
document.getElementById('open-manual').addEventListener('click', () => window.notes.manual('notes'));
lockButton.addEventListener('click', lockNow);

search.addEventListener('input', () => {
    commit();
    ui.query = search.value.trim();
    if (ui.mode === 'settings') {
        ui.mode = 'notes';
    }
    if (ui.mode === 'tasks') {
        ui.task = null;
        renderTasks();
    } else {
        const list = sortNotes(notesIn(ui.notesView));
        if (!list.some((note) => note.id === ui.note)) {
            ui.note = list[0]?.id || null;
        }
        renderNotes();
    }
    renderNav();
});
search.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && search.value) {
        event.stopPropagation();
        search.value = '';
        search.dispatchEvent(new Event('input'));
    } else if (event.key === 'Enter' || event.key === 'ArrowDown') {
        (main.querySelector('.note-item, .task-main'))?.focus();
    }
});

window.notes.onPalette(applyPalette);
window.notes.onLocked(() => {
    closeMenu();
    for (const dialog of document.querySelectorAll('dialog')) {
        dialog.close();
        dialog.remove();
    }
    pending.clear();
    ui.status = 'locked';
    resetDb(null);
    editor = null;
    detailFor = null;
    // Nothing of the notes is left in the page, on screen or off it, and nothing left to undo
    for (const pane of [listPane, editorPane, taskListPane, detailPane, toasts]) {
        pane.replaceChildren();
    }
    clearQuery();
    render();
});
window.notes.onFlush(() => {
    commit();
    window.notes.flushed();
});
window.notes.onOpen((page) => {
    if (ui.status === 'open' && (page === 'notes' || page === 'tasks')) {
        setMode(page);
    }
});
window.notes.onTask((id) => {
    if (ui.status === 'open' && db.tasks[id]) {
        ui.mode = 'tasks';
        ui.task = id;
        render();
    }
});
window.notes.onProblem((text) => toast(text));

// Using the window keeps it unlocked; main.js counts the time away from it
let lastPing = 0;
function active() {
    if (Date.now() - lastPing > 20000) {
        lastPing = Date.now();
        window.notes.active();
    }
}
document.addEventListener('keydown', active, true);
document.addEventListener('mousedown', active, true);

document.addEventListener('keydown', (event) => {
    const mod = event.ctrlKey || event.metaKey;
    const key = event.key.toLowerCase();
    if (event.key === 'Escape') {
        if (openMenu) {
            closeMenu();
        } else if (ui.mode === 'tasks' && ui.task && !document.querySelector('dialog[open]')) {
            ui.task = null;
            renderTasks();
        }
        return;
    }
    if (!mod) {
        return;
    }
    if (key === '=' || key === '+') {
        window.notes.zoom(0.5);
    } else if (key === '-') {
        window.notes.zoom(-0.5);
    } else if (key === '0') {
        window.notes.zoom(0);
    } else if (ui.status !== 'open' || document.querySelector('dialog[open]')) {
        return;
    } else if (key === 'n') {
        event.preventDefault();
        if (ui.mode === 'tasks') {
            taskListPane.querySelector('.quick.first input')?.focus();
        } else {
            newNote();
        }
    } else if (key === 'f') {
        event.preventDefault();
        search.focus();
        search.select();
    } else if (key === 'l') {
        event.preventDefault();
        lockNow();
    } else if (key === '1' || key === '2') {
        event.preventDefault();
        setMode(key === '1' ? 'notes' : 'tasks');
    } else if (key === 'e' && ui.mode === 'notes' && editor?.cycleLayout) {
        event.preventDefault();
        editor.cycleLayout();
    } else if (key === ',') {
        event.preventDefault();
        setMode('settings');
    }
});

// Past midnight, Today and the overdue ones move on
let shownDay = today();
setInterval(() => {
    if (today() !== shownDay) {
        shownDay = today();
        if (ui.status === 'open' && ui.mode === 'tasks') {
            renderNav();
            renderTaskList();
        }
    }
}, 60000);

async function start() {
    applyPalette(await window.notes.palette());
    recall();
    if (location.hash === '#tasks' || location.hash === '#notes') {
        ui.mode = location.hash.slice(1);
    }
    resetDb(null);
    renderGate();
    applyState(await window.notes.state());
}

start();
