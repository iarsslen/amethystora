'use strict';

// The page of Amethystora Backups. What it shows is what main.js read from /usr/libexec/amethystora-restore:
// the points in time there are to go back to, newest first, a folder as it was at one of them, the
// versions of a file, and what is set up. It sends back only those points and paths, and one of three ways
// to put back, and main.js checks each again. The helper's errors come as words such as "not-found", which
// are said here in the session's language. Everything is built as elements with text in them, never as
// markup.

// The session's language (i18n.js): every sentence below is the English, looked up in its catalog
const t = I18N.use(window.backups.locale);
t.page(document);

const view = document.getElementById('view');
const topbar = document.getElementById('topbar');
const dialogRoot = document.getElementById('dialog');
const pageButtons = [...document.querySelectorAll('.nav [data-page]')];
const statusDot = document.getElementById('status-dot');

const PAGES = new Set(['browse', 'status']);

const state = {
    page: 'browse',
    // amethystora-restore status, and whether the agentic features are on
    status: null,
    // amethystora-restore points: {points, backup, detail}, and this machine's name
    timeline: null,
    error: '',
    // The point shown, by id, and the folder, relative to the home folder ('' is the home folder)
    point: '',
    folder: '',
    // The folder as it was: {entries} or {error, detail}, or 'reading'
    listing: null,
    selected: new Set(),
    hidden: false,
    // The versions of one file: {file, result}, result 'reading' while they are looked for
    versions: null,
    // A question being asked before putting back: {kind: 'conflict' | 'folder', names}
    dialog: null,
    mode: 'keep-both',
    // A sentence while something takes a while, and what the last thing done here came to
    working: '',
    banner: null,
    // The backup started from here: {running, lines} and then {ok, lines}
    backup: null,
    // What the backup logged when it last failed, read once the status says so
    failedLines: null,
    dailyBusy: false,
    read: 0,
};

// --- Building blocks ---------------------------------------------------------------------------------

function h(tag, attributes = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attributes)) {
        if (value === false || value === null || value === undefined) {
            continue;
        }
        if (key.startsWith('on')) {
            node.addEventListener(key.slice(2), value);
        } else if (key === 'checked') {
            node.checked = Boolean(value);
        } else {
            node.setAttribute(key, value === true ? '' : value);
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

function button(label, onclick, { icon: name, small, primary, danger, disabled, title } = {}) {
    const classes = ['btn', small && 'small', primary && 'primary', danger && 'danger'].filter(Boolean).join(' ');
    return h('button', { type: 'button', class: classes, disabled: Boolean(disabled), title, onclick },
        name ? icon(name, 16) : null, label ? h('span', {}, label) : null);
}

function linkButton(label, onclick, name) {
    return h('button', { type: 'button', class: 'link', onclick }, name ? icon(name, 15) : null, h('span', {}, label));
}

function callout(tone, title, text, ...extra) {
    return h('div', { class: `callout ${tone}` },
        icon(tone === 'check' || tone === 'failed' ? 'alert' : 'info', 18),
        h('div', { class: 'grow' }, title ? h('strong', {}, title) : null, text ? h('p', {}, text) : null, extra));
}

function spinner(text) {
    return h('div', { class: 'working', role: 'status' }, icon('spinner', 18, 'spin'), text ? h('span', {}, text) : null);
}

function terminalTag() {
    return h('span', { class: 'tag', title: t('Opens in a terminal, where it asks before it changes anything') },
        icon('terminal', 13), t('Terminal'));
}

// What a program printed, as it printed it
function logBox(text) {
    return text ? h('pre', { class: 'log', dir: 'ltr' }, text) : null;
}

// --- Words for times, sizes and places ---------------------------------------------------------------

const TIME = new Intl.DateTimeFormat(t.locale, { hour: '2-digit', minute: '2-digit' });
const DAY = new Intl.DateTimeFormat(t.locale, { weekday: 'long', day: 'numeric', month: 'long' });
const DAY_YEAR = new Intl.DateTimeFormat(t.locale, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
const WHEN = new Intl.DateTimeFormat(t.locale, { dateStyle: 'medium', timeStyle: 'short' });
const RELATIVE = new Intl.RelativeTimeFormat(t.locale, { numeric: 'auto' });
const NAMES = new Intl.Collator(t.locale, { numeric: true, sensitivity: 'base' });

function capitalised(text) {
    return text.charAt(0).toLocaleUpperCase(t.locale) + text.slice(1);
}

function midnight(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

// "Today", "Yesterday" or "Tuesday 6 October", in the language's words
function dayOf(seconds) {
    const date = new Date(seconds * 1000);
    const days = Math.round((midnight(date) - midnight(new Date())) / 86400000);
    if (days === 0 || days === -1) {
        return capitalised(t.days(days));
    }
    return (date.getFullYear() === new Date().getFullYear() ? DAY : DAY_YEAR).format(date);
}

// "3 hours ago", "yesterday"
function ago(seconds) {
    const diff = seconds - Date.now() / 1000;
    if (Math.abs(diff) < 3600) {
        return RELATIVE.format(Math.round(diff / 60), 'minute');
    }
    if (Math.abs(diff) < 86400) {
        return RELATIVE.format(Math.round(diff / 3600), 'hour');
    }
    return RELATIVE.format(Math.round(diff / 86400), 'day');
}

function size(bytes) {
    if (bytes === null || bytes === undefined) {
        return '';
    }
    const units = ['byte', 'kilobyte', 'megabyte', 'gigabyte', 'terabyte'];
    let value = bytes;
    let unit = 0;
    while (value >= 1000 && unit < units.length - 1) {
        value /= 1000;
        unit += 1;
    }
    return t.number(value, { style: 'unit', unit: units[unit], unitDisplay: 'short', maximumFractionDigits: unit ? 1 : 0 });
}

function sourceLabel(point) {
    return point.source === 'local' ? t('On this machine') : t('In the backup');
}

function sourceIcon(point) {
    return icon(point.source === 'local' ? 'disk' : 'cloud', 16, 'source');
}

// A point made by another machine that backs up to the same repository says which
function hostOf(point) {
    return point.host && state.timeline?.hostname && point.host !== state.timeline.hostname ? point.host : '';
}

function join(folder, name) {
    return folder ? `${folder}/${name}` : name;
}

function currentPoint() {
    return state.timeline?.points.find((point) => point.id === state.point) || null;
}

// What went wrong, from the error the helper or main.js named
function errorText(result) {
    switch (result?.error) {
        case 'refused':
            return t('That cannot be done from here now. Choose the folder again and try once more.');
        case 'outside':
            return t('Only what is inside your home folder comes back here.');
        case 'not-found':
            return t('That was not there then.');
        case 'point':
            return t('That point in time is not there any more.');
        case 'no-backup':
            return t('No backup is set up.');
        case 'repository':
            return t('The backup could not be read.');
        default:
            return t('That did not work.');
    }
}

// --- The timeline --------------------------------------------------------------------------------------

function timelineView() {
    const points = state.timeline.points;
    const groups = [];
    for (const point of points) {
        const day = dayOf(point.time);
        if (!groups.length || groups[groups.length - 1].day !== day) {
            groups.push({ day, points: [] });
        }
        groups[groups.length - 1].points.push(point);
    }
    return h('aside', { class: 'timeline', 'aria-label': t('Points in time') },
        h('div', { class: 'timeline-head' },
            h('h2', {}, t('Go back to')),
            h('p', { class: 'faint small' }, t('{count, plural, one {# point in time} other {# points in time}}', { count: points.length }))),
        h('div', { class: 'timeline-list' },
            groups.map((group) => h('div', { class: 'day' },
                h('h3', {}, group.day),
                group.points.map((point) => {
                    const host = hostOf(point);
                    return h('button', {
                        type: 'button',
                        class: `moment ${point.source}`,
                        'aria-current': point.id === state.point ? 'true' : false,
                        title: `${sourceLabel(point)}${host ? ` (${host})` : ''}`,
                        onclick: () => choosePoint(point.id),
                    },
                    h('span', { class: 'moment-dot' }),
                    h('span', { class: 'moment-time' }, TIME.format(new Date(point.time * 1000))),
                    h('span', { class: 'grow faint small' }, host ? h('bdi', {}, host) : ''),
                    sourceIcon(point));
                })))),
        h('div', { class: 'timeline-key small faint' },
            h('span', {}, icon('disk', 14), t('On this machine')),
            h('span', {}, icon('cloud', 14), t('In the backup'))));
}

// --- Browse --------------------------------------------------------------------------------------------

function crumbs() {
    const parts = state.folder ? state.folder.split('/') : [];
    const items = [h('button', { type: 'button', class: 'crumb', onclick: () => openFolder('') }, icon('home', 15), t('Home'))];
    parts.forEach((part, index) => {
        const target = parts.slice(0, index + 1).join('/');
        items.push(icon('chevron', 14, 'crumb-sep'));
        items.push(index === parts.length - 1
            ? h('span', { class: 'crumb current', 'aria-current': 'location' }, h('bdi', {}, part))
            : h('button', { type: 'button', class: 'crumb', onclick: () => openFolder(target) }, h('bdi', {}, part)));
    });
    return h('nav', { class: 'crumbs', 'aria-label': t('Folder') }, items);
}

function folderHead() {
    const point = currentPoint();
    const folderName = state.folder ? state.folder.split('/').pop() : t('Your home folder');
    return h('div', { class: 'folder-head' },
        h('div', { class: 'folder-title' },
            h('h1', {}, t.parts('{folder} as it was', { folder: h('bdi', {}, folderName) })),
            point
                ? h('p', { class: 'lead' },
                    `${dayOf(point.time)}, ${TIME.format(new Date(point.time * 1000))}`,
                    h('span', { class: `chip ${point.source}` }, sourceIcon(point), sourceLabel(point)))
                : null),
        crumbs(),
        h('div', { class: 'folder-tools' },
            h('label', { class: 'check-label' },
                h('input', {
                    type: 'checkbox',
                    checked: state.hidden,
                    onchange: (event) => {
                        state.hidden = event.target.checked;
                        render();
                    },
                }),
                h('span', {}, t('Show hidden files'))),
            h('span', { class: 'grow' }),
            state.listing?.entries
                ? button(state.folder ? t('Put the whole folder back…') : t('Put your whole home folder back…'),
                    () => ask({ kind: 'folder' }), { small: true, icon: 'restore' })
                : null));
}

function nowTag(entry) {
    switch (entry.now) {
        case 'missing':
            return h('span', { class: 'tag on' }, t('Not in your folder now'));
        case 'changed':
            return h('span', { class: 'tag check' }, t('Changed since'));
        case 'same':
            return h('span', { class: 'tag' }, t('Same as now'));
        default:
            return null;
    }
}

function entries() {
    const list = (state.listing?.entries || []).filter((entry) => state.hidden || !entry.name.startsWith('.'));
    return list.sort((a, b) => ((a.type === 'dir') === (b.type === 'dir') ? NAMES.compare(a.name, b.name) : a.type === 'dir' ? -1 : 1));
}

function fileRow(entry) {
    const selected = state.selected.has(entry.name);
    const glyph = entry.type === 'dir' ? 'folder' : entry.type === 'link' ? 'link' : 'file';
    return h('label', {
        class: `file-row${selected ? ' selected' : ''}`,
        ondblclick: entry.type === 'dir' ? () => openFolder(join(state.folder, entry.name)) : null,
    },
    h('input', {
        type: 'checkbox',
        checked: selected,
        'aria-label': t('Select {name}', { name: entry.name }),
        onchange: (event) => {
            if (event.target.checked) {
                state.selected.add(entry.name);
            } else {
                state.selected.delete(entry.name);
            }
            render();
        },
    }),
    icon(glyph, 20, `file-icon ${glyph}`),
    entry.type === 'dir'
        ? h('button', { type: 'button', class: 'file-name folder', onclick: () => openFolder(join(state.folder, entry.name)) },
            h('bdi', {}, entry.name))
        : h('span', { class: 'file-name' }, h('bdi', {}, entry.name)),
    h('span', { class: 'file-now' }, nowTag(entry)),
    h('span', { class: 'file-when faint small' }, WHEN.format(new Date(entry.mtime * 1000))),
    h('span', { class: 'file-size faint small' }, size(entry.size)));
}

function filesBody() {
    if (state.versions) {
        return versionsView();
    }
    if (!state.listing || state.listing === 'reading') {
        return h('div', { class: 'file-list' }, spinner(t('Reading the folder…')));
    }
    if (state.listing.error) {
        const missing = state.listing.error === 'not-found';
        return h('div', { class: 'file-list padded' },
            callout(missing ? 'info' : 'failed',
                missing ? t('This folder was not there then') : errorText(state.listing),
                missing ? t('Go back to a later point in time, or to a folder above it.') : '',
                missing ? null : logBox(state.listing.detail)));
    }
    const list = entries();
    if (!list.length) {
        return h('div', { class: 'file-list padded' },
            h('p', { class: 'soft' }, state.listing.entries.length ? t('Only hidden files were in this folder then.') : t('This folder was empty then.')));
    }
    return h('div', { class: 'file-list', role: 'list' }, list.map(fileRow));
}

function selectionBar() {
    const names = [...state.selected];
    if (!names.length || state.versions) {
        return null;
    }
    const one = names.length === 1 ? (state.listing?.entries || []).find((entry) => entry.name === names[0]) : null;
    return h('div', { class: 'selection-bar' },
        h('span', { class: 'grow' }, t('{count, plural, one {# selected} other {# selected}}', { count: names.length })),
        linkButton(t('Clear'), () => {
            state.selected.clear();
            render();
        }),
        one ? button(t('Versions'), () => showVersions(join(state.folder, one.name)), { icon: 'layers', small: true }) : null,
        one ? button(t('Look'), () => lookAt(join(state.folder, one.name)), { icon: 'eye', small: true }) : null,
        button(t('Put back'), () => startPutBack(names), { icon: 'restore', small: true, primary: true }));
}

function browseView() {
    const timeline = state.timeline;
    if (!timeline.points.length) {
        return h('div', { class: 'page' },
            h('div', { class: 'empty' },
                icon('history', 40),
                h('h2', {}, t('Nothing to go back to yet')),
                h('p', {}, nothingYetText()),
                unreachable(),
                h('div', { class: 'actions' }, button(t('See what is set up'), () => show('status'), { primary: true }))));
    }
    return h('div', { class: 'browse' },
        h('section', { class: 'files' },
            unreachable(),
            folderHead(),
            filesBody(),
            selectionBar()),
        timelineView());
}

// While neither is set up, both are offered; with one or both on, there is just nothing there yet
function nothingYetText() {
    const status = state.status;
    if (status.backup.set_up || status.snapshots.on) {
        return t('The first snapshot or backup appears here once it has been taken.');
    }
    return t('Neither the hourly snapshots nor a backup are set up.');
}

function unreachable() {
    if (state.timeline?.backup !== 'unreachable') {
        return null;
    }
    return callout('check', t('The backup could not be read'),
        t('Only the snapshots on this machine are shown. The backup comes back once its repository can be reached.'),
        logBox(state.timeline.detail));
}

// --- Versions of one file ------------------------------------------------------------------------------

function versionsView() {
    const { file, result } = state.versions;
    const name = file.split('/').pop();
    const back = linkButton(t('Back to the folder'), () => {
        state.versions = null;
        render();
    }, 'back');
    if (result === 'reading') {
        return h('div', { class: 'file-list padded' }, back,
            spinner(t('Looking for every version of {name}…', { name })));
    }
    if (result.error) {
        return h('div', { class: 'file-list padded' }, back, callout('failed', errorText(result), '', logBox(result.detail)));
    }
    const rows = result.versions.map((version) => h('div', { class: 'version-row' },
        sourceIcon(version),
        h('div', { class: 'grow' },
            h('strong', {}, `${dayOf(version.time)}, ${TIME.format(new Date(version.time * 1000))}`),
            h('small', { class: 'faint' },
                [sourceLabel(version), t('modified {when}', { when: WHEN.format(new Date(version.mtime * 1000)) }), size(version.size)]
                    .filter(Boolean).join(' · '))),
        h('div', { class: 'actions' },
            button(t('Go there'), () => goTo(version.id, name), { small: true }),
            button(t('Look'), () => lookAt(file, version.id), { small: true, icon: 'eye' }))));
    return h('div', { class: 'file-list padded' },
        back,
        h('h2', { class: 'versions-title' }, t.parts('Versions of {name}', { name: h('bdi', {}, name) })),
        result.now
            ? h('p', { class: 'soft' }, t('Now, in your folder: modified {when}', { when: WHEN.format(new Date(result.now.mtime * 1000)) }))
            : h('p', { class: 'soft' }, t('It is not in your folder now.')),
        result.backup === 'unreachable'
            ? callout('check', t('The backup could not be read'), t('Only the versions on this machine are shown.'), logBox(result.detail))
            : null,
        rows.length ? h('div', { class: 'versions' }, rows) : h('p', { class: 'soft' }, t('No version of it was kept.')));
}

async function showVersions(file) {
    state.versions = { file, result: 'reading' };
    render();
    const result = await window.backups.versions(file);
    if (state.versions?.file === file) {
        state.versions.result = result;
        render();
    }
}

// From a version to the folder it is in, at that point, with it selected
async function goTo(id, name) {
    state.versions = null;
    state.selected = new Set([name]);
    await choosePoint(id, { keep: true });
}

// --- Putting back and looking ----------------------------------------------------------------------------

function ask(dialog) {
    state.dialog = dialog;
    state.mode = 'keep-both';
    renderDialog();
}

// Only a file that is still there and differs, or a folder still there, can meet something of the same
// name: then the question is asked, once for all of them
function startPutBack(names) {
    const picked = (state.listing?.entries || []).filter((entry) => names.includes(entry.name));
    if (picked.some((entry) => entry.now === 'changed' || entry.now === 'present')) {
        ask({ kind: 'conflict', names });
    } else {
        putBack(names.map((name) => join(state.folder, name)), 'keep-both');
    }
}

function putBackText(result, mode) {
    const changed = result.added + result.kept + result.replaced;
    const parts = [];
    if (!changed && !result.skipped && result.same) {
        parts.push(t('Nothing needed putting back: it is the same in your folder now.'));
    } else if (changed || result.skipped) {
        parts.push(t('Put back.'));
    }
    if (result.kept) {
        parts.push(t('{count, plural, one {The earlier version of # file is beside the newer one, with its date in its name.} other {The earlier versions of # files are beside the newer ones, with their date in their names.}}', { count: result.kept }));
    }
    if (mode === 'replace' && result.replaced) {
        parts.push(t('What had the same name was replaced.'));
    }
    if (result.skipped) {
        parts.push(t('What differs now was left as it is.'));
    }
    if (result.missing?.length) {
        parts.push(t('{count, plural, one {# was not there then.} other {# were not there then.}}', { count: result.missing.length }));
    }
    return parts.join(' ');
}

async function putBack(files, mode) {
    const point = currentPoint();
    state.dialog = null;
    renderDialog();
    state.banner = null;
    state.working = point?.source === 'backup' ? t('Getting it from the backup and putting it back…') : t('Putting it back…');
    render();
    const result = await window.backups.putBack(state.point, files, mode);
    state.working = '';
    state.banner = result.error
        ? { tone: 'failed', text: errorText(result), detail: result.detail }
        : { tone: 'done', text: putBackText(result, mode) };
    state.selected.clear();
    await loadFolder({ quiet: true });
}

async function lookAt(file, id = state.point) {
    const point = state.timeline.points.find((entry) => entry.id === id);
    state.banner = null;
    state.working = point?.source === 'backup' ? t('Getting a copy from the backup…') : '';
    render();
    const result = await window.backups.look(id, file);
    state.working = '';
    state.banner = result.error
        ? { tone: 'failed', text: errorText(result), detail: result.detail }
        : { tone: 'done', text: t('Opened read-only. Copy out of it what you want, or put it back from here.') };
    render();
}

const MODES = [
    ['keep-both', () => t('Keep both'), () => t('The earlier version comes back beside the one you have, with its date in its name.')],
    ['replace', () => t('Replace'), () => t('The earlier version takes the place of the one you have.')],
    ['skip', () => t('Skip'), () => t('What you have now stays as it is; only what is missing comes back.')],
];

function renderDialog() {
    const dialog = state.dialog;
    if (!dialog) {
        dialogRoot.replaceChildren();
        return;
    }
    const close = () => {
        state.dialog = null;
        renderDialog();
    };
    let body;
    if (dialog.kind === 'folder') {
        const name = state.folder ? state.folder.split('/').pop() : t('your home folder');
        body = [
            h('h2', {}, t.parts('Put {folder} back as it was?', { folder: h('bdi', {}, name) })),
            h('p', { class: 'soft' }, t('Files with the same name as one then are replaced by the earlier version. Files it did not have, such as what ransomware renamed, stay where they are: nothing is deleted.')),
            h('p', { class: 'soft' }, t('This is for getting back from ransomware or from a change that went wrong everywhere at once. For a few files, select them instead.')),
            h('div', { class: 'actions end' },
                button(t('Cancel'), close),
                button(t('Put the folder back'), () => putBack([state.folder], 'replace'), { primary: true, icon: 'restore' })),
        ];
    } else {
        const options = h('div', { class: 'options', role: 'radiogroup', 'aria-label': t('What to do with what you have now') },
            MODES.map(([mode, label, text]) => h('button', {
                type: 'button',
                class: 'option',
                role: 'radio',
                'aria-checked': String(state.mode === mode),
                onclick: () => {
                    state.mode = mode;
                    renderDialog();
                },
            }, h('span', { class: 'dot' }), h('span', { class: 'option-words' }, h('strong', {}, label()), h('small', {}, text())))));
        body = [
            h('h2', {}, t('{count, plural, one {Something with this name is in your folder now} other {Some of these are in your folder now}}', { count: dialog.names.length })),
            h('p', { class: 'soft' }, t('Files that are the same are left alone. For those that differ:')),
            options,
            h('div', { class: 'actions end' },
                button(t('Cancel'), close),
                button(t('Put back'), () => putBack(dialog.names.map((name) => join(state.folder, name)), state.mode),
                    { primary: true, icon: 'restore' })),
        ];
    }
    dialogRoot.replaceChildren(h('div', {
        class: 'dialog-back',
        onclick: (event) => {
            if (event.target === event.currentTarget) {
                close();
            }
        },
    }, h('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true' }, body)));
    dialogRoot.querySelector('.btn.primary')?.focus();
}

// --- Status --------------------------------------------------------------------------------------------

function row(label, value) {
    return h('div', { class: 'fact' }, h('span', { class: 'faint' }, label), h('span', {}, value));
}

function backupCard() {
    const backup = state.status.backup;
    const tag = !backup.set_up ? h('span', { class: 'tag' }, t('Not set up'))
        : backup.daily ? h('span', { class: 'tag on' }, t('Every day')) : h('span', { class: 'tag' }, t('Daily run off'));
    const body = [];
    if (!backup.set_up) {
        body.push(h('p', { class: 'setting-text' }, t('Set it up once, in a terminal, where it explains how to make a repository that this machine can add to and read from but never delete from.')),
            h('div', { class: 'actions' },
                button(t('Set up a backup…'), () => window.backups.setUp(), { primary: true, icon: 'terminal' }), terminalTag()));
        return card('archive', t('Daily backup'), t('A restic backup of your home folder, once a day, to a repository that ransomware on this machine cannot delete from.'), tag, body);
    }
    body.push(h('div', { class: 'facts' },
        row(t('Repository'), h('code', { dir: 'ltr' }, backup.repository)),
        row(t('Last good backup'), backup.last_success
            ? `${WHEN.format(new Date(backup.last_success * 1000))} (${ago(backup.last_success)})`
            : t('None yet')),
        backup.daily && backup.next ? row(t('Next'), WHEN.format(new Date(backup.next * 1000))) : null));
    if (backup.stale) {
        body.push(callout('check',
            backup.last_success
                ? t('{days, plural, one {No backup has succeeded for # day} other {No backup has succeeded for # days}}', { days: Math.floor((Date.now() / 1000 - backup.last_success) / 86400) })
                : t('The daily backup is on, but none has succeeded yet'),
            t('It runs once a day. Back up now to see what goes wrong, or ask the agent.'),
            logBox(state.failedLines), agentLink()));
    } else if (backup.failed) {
        body.push(callout('check', t('The last backup failed'), t('The next one runs as planned. What it logged:'), logBox(state.failedLines), agentLink()));
    }
    body.push(backupProgress());
    body.push(h('div', { class: 'actions' },
        button(t('Back up now'), backupNow, { primary: true, icon: 'upload', disabled: state.backup?.running || backup.running }),
        button(t('Change…'), () => window.backups.setUp(), { icon: 'terminal' }),
        button(backup.daily ? t('Turn off the daily run') : t('Turn on the daily run'), () => setDaily(!backup.daily),
            { disabled: state.dailyBusy })));
    body.push(h('p', { class: 'faint small' }, t('Nothing on this machine deletes from the repository, so old backups build up. Thin them out from somewhere else, as the manual explains.')));
    return card('archive', t('Daily backup'), t('A restic backup of your home folder, once a day, to a repository that ransomware on this machine cannot delete from.'), tag, body);
}

// The agent looks into the failed unit in a terminal and changes nothing until asked
function agentLink() {
    return state.status.agent ? linkButton(t('Ask the agent'), () => window.backups.diagnose(), 'sparkle') : null;
}

function backupProgress() {
    const backup = state.backup;
    if (!backup) {
        return null;
    }
    if (backup.running) {
        return h('div', { class: 'progress', role: 'status' },
            h('div', { class: 'progress-head' }, icon('spinner', 16, 'spin'), h('span', {}, t('Backing up…'))),
            logBox(backup.lines.slice(-6).join('\n')));
    }
    return backup.ok
        ? callout('info', t('Backed up'), t('Your home folder is in the backup as it is now.'))
        : callout('failed', t('The backup did not succeed'), t('What it logged:'), logBox(backup.lines), agentLink());
}

function snapshotsCard() {
    const snapshots = state.status.snapshots;
    const tag = snapshots.on ? h('span', { class: 'tag on' }, t('Every hour')) : h('span', { class: 'tag' }, t('Off'));
    const body = [];
    if (!snapshots.possible) {
        body.push(callout('info', '', t('This machine cannot take them: the home folders are not on a btrfs subvolume of their own, which is how the installer sets a disk up unless it was partitioned by hand.')));
    } else if (snapshots.on) {
        body.push(h('div', { class: 'facts' },
            row(t('Kept'), t('{count, plural, one {# snapshot of your home folder} other {# snapshots of your home folder}}', { count: snapshots.count })),
            snapshots.latest ? row(t('Latest'), `${WHEN.format(new Date(snapshots.latest * 1000))} (${ago(snapshots.latest)})`) : null));
    }
    if (snapshots.on && !snapshots.covers) {
        body.push(callout('check', '', t('Your home folder is not under /var/home, so the snapshots do not cover it.')));
    }
    body.push(h('p', { class: 'setting-text' }, t('They are part of ransomware protection, which Security turns on and off.')),
        h('div', { class: 'actions' }, button(t('Open Security'), () => window.backups.security(), { icon: 'external' })));
    return card('history', t('Hourly snapshots'), t('A read-only copy of the home folders every hour, on this machine: every one from the last day, and one a day for two weeks.'), tag, body);
}

function card(glyph, title, text, tag, body) {
    return h('section', { class: 'setting card' },
        h('div', { class: 'setting-head' },
            h('div', { class: 'setting-icon' }, icon(glyph, 22)),
            h('div', { class: 'setting-words' },
                h('div', { class: 'setting-title' }, h('h3', {}, title), tag),
                h('p', { class: 'setting-text' }, text))),
        body);
}

function statusView() {
    return h('div', { class: 'page' },
        h('div', { class: 'page-head' },
            h('h1', {}, t('Status')),
            h('p', { class: 'lead' }, t('Two things keep earlier versions of your files: snapshots on this machine every hour, and a backup somewhere else every day. Each covers what the other cannot.'))),
        backupCard(),
        snapshotsCard());
}

// Neither is set up: both are offered, and nothing else is shown
function nothingSetUp() {
    const status = state.status;
    return !status.backup.set_up && !status.snapshots.on && !state.timeline?.points.length;
}

function emptyView() {
    return h('div', { class: 'page' },
        h('div', { class: 'empty' },
            h('img', { class: 'gem', src: 'gem.svg', alt: '' }),
            h('h2', {}, t('Nothing keeps earlier versions of your files yet')),
            h('p', {}, t('Two things can, and they work best together: a backup somewhere else every day, which survives losing this machine, and snapshots here every hour, which bring back a file from this morning in a moment.'))),
        h('div', { class: 'offers' },
            h('section', { class: 'card offer' },
                icon('archive', 26),
                h('h3', {}, t('A daily backup')),
                h('p', { class: 'soft' }, t('To a server, an object store or a USB drive, set up in a terminal.')),
                h('div', { class: 'actions' }, button(t('Set up a backup…'), () => window.backups.setUp(), { primary: true, icon: 'terminal' }))),
            h('section', { class: 'card offer' },
                icon('history', 26),
                h('h3', {}, t('Hourly snapshots')),
                h('p', { class: 'soft' }, state.status.snapshots.possible
                    ? t('Turned on in Security, as ransomware protection.')
                    : t('Not possible on this machine: the home folders are not on a btrfs subvolume of their own.')),
                h('div', { class: 'actions' }, button(t('Open Security'), () => window.backups.security(),
                    { icon: 'external', disabled: !state.status.snapshots.possible })))));
}

// --- The window ----------------------------------------------------------------------------------------

function loadingView() {
    return h('div', { class: 'loading', role: 'status' }, h('img', { class: 'gem', src: 'gem.svg', alt: '' }),
        h('span', {}, t('Looking for your snapshots and backups…')));
}

function errorView() {
    return h('div', { class: 'page' },
        h('div', { class: 'empty' },
            h('h2', {}, t('What is set up could not be read')),
            logBox(state.error),
            h('div', { class: 'actions' }, button(t('Try again'), () => load(), { icon: 'refresh', primary: true }))));
}

function bannerView() {
    if (state.working) {
        return h('div', { class: 'banner-wrap' }, h('div', { class: 'banner' }, icon('spinner', 18, 'spin'), h('span', { class: 'grow' }, state.working)));
    }
    if (!state.banner) {
        return null;
    }
    const failed = state.banner.tone === 'failed';
    return h('div', { class: 'banner-wrap' },
        h('div', { class: `banner${failed ? ' failed' : ''}`, role: failed ? 'alert' : 'status' },
            icon(failed ? 'alert' : 'check', 18),
            h('div', { class: 'grow' }, h('span', {}, state.banner.text), logBox(state.banner.detail)),
            h('button', {
                type: 'button',
                class: 'icon-btn',
                'aria-label': t('Dismiss'),
                onclick: () => {
                    state.banner = null;
                    render();
                },
            }, icon('close', 16))));
}

// The top bar: when the backup last succeeded, and backing up now, from any page
function renderTopbar() {
    const backup = state.status?.backup;
    if (!backup?.set_up) {
        topbar.replaceChildren();
        return;
    }
    let said;
    if (state.backup?.running || backup.running) {
        said = h('span', { class: 'topbar-state' }, icon('spinner', 15, 'spin'), t('Backing up…'));
    } else if (backup.stale || backup.failed) {
        said = h('button', { type: 'button', class: 'topbar-state check', onclick: () => show('status') }, icon('alert', 15),
            backup.last_success ? t('Last good backup {when}', { when: ago(backup.last_success) }) : t('No good backup yet'));
    } else if (backup.last_success) {
        said = h('span', { class: 'topbar-state' }, icon('check', 15), t('Last good backup {when}', { when: ago(backup.last_success) }));
    }
    // The status page has the button on its own card
    topbar.replaceChildren(said || '', state.page === 'status' ? '' : button(t('Back up now'), backupNow,
        { small: true, icon: 'upload', disabled: state.backup?.running || backup.running }));
}

function renderNav() {
    for (const node of pageButtons) {
        if (node.dataset.page === state.page) {
            node.setAttribute('aria-current', 'page');
        } else {
            node.removeAttribute('aria-current');
        }
    }
    const backup = state.status?.backup;
    statusDot.hidden = !(backup?.stale || backup?.failed);
}

function render() {
    renderNav();
    renderTopbar();
    // Drawn again in place: the page, the file list and the timeline keep where they were scrolled to
    const scrolled = ['.file-list', '.timeline-list'].map((selector) => view.querySelector(selector)?.scrollTop || 0);
    const top = view.scrollTop;
    let content;
    if (!state.status || !state.timeline) {
        content = state.error ? errorView() : loadingView();
    } else if (nothingSetUp()) {
        content = emptyView();
    } else {
        content = state.page === 'status' ? statusView() : browseView();
    }
    view.replaceChildren(bannerView() || '', content);
    view.scrollTop = top;
    ['.file-list', '.timeline-list'].forEach((selector, index) => {
        const node = view.querySelector(selector);
        if (node) {
            node.scrollTop = scrolled[index];
        }
    });
}

// What is set up, and, unless only that is wanted, every point in time again
async function load({ quiet = false, statusOnly = false } = {}) {
    if (!quiet) {
        state.status = null;
        state.timeline = null;
        state.error = '';
        render();
    }
    const [status, timeline] = await Promise.all([window.backups.status(), statusOnly ? state.timeline : window.backups.points()]);
    state.read = Date.now();
    if (status.error || timeline?.error) {
        state.error = status.detail || timeline?.detail || errorText(status.error ? status : timeline);
        render();
        return;
    }
    state.status = status;
    state.timeline = timeline;
    state.error = '';
    // What a failed or stale backup last logged, read once
    if (!status.backup.failed && !status.backup.stale) {
        state.failedLines = null;
    } else if (state.failedLines === null) {
        state.failedLines = await window.backups.lastLines();
    }
    // The newest point, unless the one shown is still there
    if (!timeline.points.some((point) => point.id === state.point)) {
        state.point = timeline.points[0]?.id || '';
        state.listing = null;
    }
    render();
    if (state.point && (!state.listing || !quiet)) {
        await loadFolder({ quiet });
    }
}

async function loadFolder({ quiet = false } = {}) {
    if (!state.point) {
        return;
    }
    const asked = `${state.point}\n${state.folder}`;
    if (!quiet) {
        state.listing = 'reading';
        render();
    }
    const result = await window.backups.ls(state.point, state.folder);
    // Another point or folder was picked meanwhile: that one's answer is the one to show
    if (asked !== `${state.point}\n${state.folder}`) {
        return;
    }
    state.listing = result;
    // What is selected and still there stays selected
    const names = new Set((result.entries || []).map((entry) => entry.name));
    state.selected = new Set([...state.selected].filter((name) => names.has(name)));
    render();
}

async function choosePoint(id, { keep = false } = {}) {
    if (!keep) {
        state.selected.clear();
    }
    state.point = id;
    state.banner = null;
    await loadFolder();
}

async function openFolder(folder) {
    state.folder = folder;
    state.selected.clear();
    state.versions = null;
    state.banner = null;
    view.querySelector('.file-list')?.scrollTo(0, 0);
    await loadFolder();
    const list = view.querySelector('.file-list');
    if (list) {
        list.scrollTop = 0;
    }
}

function show(page) {
    if (!PAGES.has(page)) {
        return;
    }
    state.page = page;
    state.banner = null;
    render();
    view.scrollTop = 0;
}

async function backupNow() {
    state.backup = { running: true, lines: [] };
    render();
    const result = await window.backups.backupNow();
    if (result?.error) {
        state.backup = { running: false, ok: false, lines: result.detail || '' };
        render();
    }
}

async function setDaily(on) {
    state.dailyBusy = true;
    render();
    const result = await window.backups.daily(on);
    state.dailyBusy = false;
    if (!result.ok) {
        state.banner = { tone: 'failed', text: t('That did not work.'), detail: result.output };
    }
    await load({ quiet: true, statusOnly: true });
}

window.backups.onBackupLine((line) => {
    if (state.backup?.running) {
        state.backup.lines.push(line);
        if (state.backup.lines.length > 200) {
            state.backup.lines.shift();
        }
        render();
    }
});

window.backups.onBackupDone(async (result) => {
    state.backup = { running: false, ok: result.ok, lines: result.lines };
    state.failedLines = null;
    await load({ quiet: true });
});

function luminance(hex) {
    const [r, g, b] = [1, 3, 5]
        .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
        .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// The same palette mapping as the Manual's, Security's, Updates', Logs' and Control's
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
    for (const [key, variable] of Object.entries(variables)) {
        if (colors?.[key]) {
            style.setProperty(variable, colors[key]);
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

window.backups.onPalette(applyPalette);
// Opened again on a folder or a page, from Files or the command line
window.backups.onOpen((where) => {
    if (typeof where?.folder === 'string') {
        state.page = 'browse';
        openFolder(where.folder);
    } else {
        show(where?.page);
    }
});
// Back from a terminal or from Security, where something may have been set up or switched
window.backups.onFocus(() => {
    if (state.status && Date.now() - state.read > 3000 && !state.backup?.running) {
        const before = JSON.stringify([state.status.backup.set_up, state.status.snapshots.on]);
        load({ quiet: true, statusOnly: true }).then(() => {
            if (JSON.stringify([state.status?.backup.set_up, state.status?.snapshots.on]) !== before) {
                load({ quiet: true });
            }
        });
    }
});

for (const node of pageButtons) {
    node.addEventListener('click', () => show(node.dataset.page));
}
document.getElementById('open-security').addEventListener('click', () => window.backups.security());
document.getElementById('open-manual').addEventListener('click', () => window.backups.manual('security#backups'));

document.addEventListener('keydown', (event) => {
    const typing = event.target instanceof HTMLInputElement && event.target.type !== 'checkbox';
    if ((event.ctrlKey && event.key === 'r') || event.key === 'F5') {
        event.preventDefault();
        load({ quiet: true });
    } else if (event.key === 'Escape' && state.dialog) {
        state.dialog = null;
        renderDialog();
    } else if (event.key === 'Escape' && state.versions) {
        state.versions = null;
        render();
    } else if (((event.altKey && event.key === 'ArrowUp') || (event.key === 'Backspace' && !typing)) &&
        state.page === 'browse' && state.folder && !state.dialog) {
        event.preventDefault();
        openFolder(state.folder.includes('/') ? state.folder.slice(0, state.folder.lastIndexOf('/')) : '');
    } else if (event.ctrlKey && event.key === 'a' && !typing && state.page === 'browse' && state.listing?.entries) {
        event.preventDefault();
        state.selected = new Set(entries().map((entry) => entry.name));
        render();
    } else if (event.ctrlKey && (event.key === '=' || event.key === '+')) {
        window.backups.zoom(0.5);
    } else if (event.ctrlKey && event.key === '-') {
        window.backups.zoom(-0.5);
    } else if (event.ctrlKey && event.key === '0') {
        window.backups.zoom(0);
    }
});

async function start() {
    applyPalette(await window.backups.palette());
    const page = location.hash.slice(1);
    state.page = PAGES.has(page) ? page : 'browse';
    state.folder = (await window.backups.start()).folder || '';
    render();
    await load();
}

start();
