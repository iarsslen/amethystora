'use strict';

// The page of Amethystora Logs. What it shows comes from main.js, which reads the journal with
// journalctl. Everything is built as elements with text in them and never as markup: a log message is
// whatever any program on the machine chose to write.

const view = document.getElementById('view');
const categoryButtons = [...document.querySelectorAll('.nav [data-category]')];
const pageButtons = [...document.querySelectorAll('.nav [data-page]')];
const terminalHint = document.getElementById('terminal-hint');
const usageNode = document.getElementById('usage');

// The views of the sidebar: what each is called, says about itself, and says when it is empty
const CATEGORIES = {
    important: {
        title: 'Important',
        lead: 'Errors and worse, from everything on the machine: what failed, and what is worth a look.',
        empty: 'Nothing went wrong',
    },
    all: { title: 'All logs', lead: 'Everything the system, the desktop and the apps wrote down.', empty: 'Nothing was logged' },
    session: { title: 'Your session', lead: 'Your desktop, and the apps and services you started.', empty: 'Nothing was logged' },
    system: {
        title: 'System',
        lead: 'The services that run the machine, whoever is signed in.',
        empty: 'Nothing was logged',
    },
    kernel: {
        title: 'Kernel and hardware',
        lead: 'The kernel and its drivers: devices plugged in and out, disks, graphics, power.',
        empty: 'Nothing was logged',
    },
    security: {
        title: 'Security',
        lead: 'Sign-ins, sudo and polkit, and what the audit rules caught.',
        empty: 'Nothing was logged',
    },
    crashes: {
        title: 'Crashes',
        lead: 'Programs that crashed, and where in their code they were when they did.',
        empty: 'Nothing crashed',
    },
};
// The views made of the system's journal, which only administrators can read
const SYSTEM_VIEWS = new Set(['system', 'kernel', 'security']);

const RANGES = [
    ['boot', 'This boot'],
    ['previous', 'Previous boot'],
    ['hour', 'Last hour'],
    ['day', 'Last 24 hours'],
    ['week', 'Last 7 days'],
    ['all', 'Everything kept'],
];
// Ranges that end now, so that new entries belong in them
const LIVE_RANGES = new Set(['boot', 'hour', 'day', 'week', 'all']);
const LEVELS = [
    [7, 'Every level'],
    [6, 'Info and above'],
    [5, 'Notices and above'],
    [4, 'Warnings and errors'],
    [3, 'Errors only'],
];
// syslog's priorities, 0 to 7: the word for each and the colour it is drawn in
const PRIORITIES = [
    ['Emergency', 'off'],
    ['Alert', 'off'],
    ['Critical', 'off'],
    ['Error', 'off'],
    ['Warning', 'check'],
    ['Notice', 'accent'],
    ['Info', 'info'],
    ['Debug', 'debug'],
];
// A live view keeps this many entries, and forgets the oldest
const LIVE_KEPT = 3000;

const state = {
    // 'logs', or 'sources' for the apps and services
    page: 'logs',
    category: 'important',
    // { kind: 'app' | 'unit' | 'identifier', id, scope, label }, or null for everything in the view
    source: null,
    range: 'boot',
    level: 7,
    search: '',
    regex: false,
    entries: [],
    more: false,
    loading: false,
    loadingMore: false,
    error: '',
    command: '',
    // The cursor of the entry open beside the list
    selected: '',
    live: false,
    // Entries that came in live while the list was scrolled away from the top
    fresh: 0,
    // Live entries that came in while the list was being read
    buffered: [],
    // { readable, usage, counts, boots, user } from main.js
    overview: null,
    sources: null,
    sourceFilter: '',
    // { tone, text } for the moment after an export
    notice: null,
    // Each read of the list counts up, so that an answer to an older one is dropped
    request: 0,
};

// The parts of the page that change without the whole of it being drawn again
const live = {};
const byCursor = new Map();

// --- Building blocks ---------------------------------------------------------------------------------

function h(tag, attributes = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attributes)) {
        if (value === false || value === null || value === undefined) {
            continue;
        }
        if (key.startsWith('on')) {
            node.addEventListener(key.slice(2), value);
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

// The mark as its bowl and its stem, so that the stem can blink by itself while the journal is read
function reading() {
    return h('span', { class: 'reading', 'aria-hidden': 'true' },
        h('img', { src: 'gem-bowl.svg', alt: '' }), h('img', { class: 'stem', src: 'gem-stem.svg', alt: '' }));
}

function button(label, onclick, { icon: name, small, primary, disabled, pressed, title } = {}) {
    const classes = ['btn', small && 'small', primary && 'primary'].filter(Boolean).join(' ');
    return h('button', {
        type: 'button',
        class: classes,
        disabled: Boolean(disabled),
        'aria-pressed': pressed === undefined ? null : String(pressed),
        title,
        onclick,
    }, name ? icon(name, 16) : null, label ? h('span', {}, label) : null);
}

function linkButton(label, onclick, { icon: name } = {}) {
    return h('button', { type: 'button', class: 'link small', onclick }, name ? icon(name, 15) : null, h('span', {}, label));
}

// A button that says it copied, for a moment
function copyButton(label, text, { small = true } = {}) {
    const caption = h('span', {}, label);
    return h('button', {
        type: 'button',
        class: `btn${small ? ' small' : ''}`,
        onclick: () => {
            window.logs.copy(typeof text === 'function' ? text() : text);
            caption.textContent = 'Copied';
            setTimeout(() => {
                caption.textContent = label;
            }, 1500);
        },
    }, icon('copy', 15), caption);
}

function callout(tone, title, text, ...extra) {
    return h('div', { class: `callout ${tone}` },
        icon(tone === 'check' ? 'alert' : 'info', 20),
        h('div', { class: 'grow' }, h('strong', {}, title), text ? h('p', {}, text) : null, extra));
}

function commandBlock(lead, command) {
    return h('div', { class: 'command-wrap' },
        lead ? h('p', { class: 'soft small' }, lead) : null,
        h('div', { class: 'command' }, h('code', {}, command), copyButton('Copy', command)));
}

function select(label, options, value, onchange) {
    const node = h('select', { 'aria-label': label, onchange: (event) => onchange(event.target.value) }, options);
    node.value = String(value);
    return h('span', { class: 'select' }, node, icon('chevron-down', 16));
}

// --- Words ---------------------------------------------------------------------------------------------

function midnight(ms) {
    const date = new Date(ms);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

// On the 24-hour clock whatever the locale, as journalctl prints it, so that the column lines up
function clock(ms) {
    return new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
}

function dayName(ms) {
    const days = Math.round((midnight(Date.now()) - midnight(ms)) / 86400000);
    if (days === 0) {
        return 'Today';
    }
    if (days === 1) {
        return 'Yesterday';
    }
    return new Date(ms).toLocaleDateString([], {
        weekday: 'long', day: 'numeric', month: 'long', year: days > 300 ? 'numeric' : undefined,
    });
}

function shortDay(ms) {
    return new Date(ms).toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
}

// To the millisecond, as the entry has it
function fullTime(ms) {
    const date = new Date(ms);
    const day = date.toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
    return `${day}, ${clock(ms)}.${String(date.getMilliseconds()).padStart(3, '0')}`;
}

function plural(count, one, many) {
    return `${count.toLocaleString()} ${count === 1 ? one : many}`;
}

function capped(count) {
    const cap = state.overview?.counts.cap || 1000;
    return count >= cap ? `${cap - 1}+` : String(count);
}

function firstLine(text) {
    const at = text.indexOf('\n');
    return at < 0 ? text : text.slice(0, at);
}

// The search as a JavaScript expression, for marking it in the messages: journalctl's PCRE and
// JavaScript agree on most of what anyone types, and where they do not nothing is marked
function matcher() {
    if (!state.search) {
        return null;
    }
    try {
        return new RegExp(state.regex ? state.search : state.search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
    } catch {
        return null;
    }
}

// Text with what the search found in it marked
function marked(text, pattern) {
    if (!pattern) {
        return [text];
    }
    const parts = [];
    let last = 0;
    pattern.lastIndex = 0;
    for (const match of text.matchAll(pattern)) {
        if (!match[0]) {
            break;
        }
        parts.push(text.slice(last, match.index), h('mark', {}, match[0]));
        last = match.index + match[0].length;
        if (parts.length > 200) {
            break;
        }
    }
    parts.push(text.slice(last));
    return parts;
}

function rangeLabel(range) {
    const fixed = RANGES.find(([value]) => value === range);
    if (fixed) {
        return fixed[1].toLowerCase();
    }
    if (range.startsWith('b:')) {
        const boot = state.overview?.boots.find((item) => item.id === range.slice(2));
        return boot?.first ? `the boot of ${shortDay(boot.first)}` : 'that boot';
    }
    return 'those two minutes';
}

function bootLabel(boot) {
    if (!boot.first) {
        return boot.id.slice(0, 12);
    }
    const minutes = (ms) => new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
    return `${shortDay(boot.first)}, ${minutes(boot.first)}${boot.last ? `–${minutes(boot.last)}` : ''}`;
}

// --- Reading the journal -----------------------------------------------------------------------------

// What is shown, as main.js takes it
function request(extra = {}) {
    const source = state.source ? { kind: state.source.kind, id: state.source.id, scope: state.source.scope } : null;
    return {
        category: state.category,
        source,
        range: state.range,
        level: state.level,
        search: state.search,
        regex: state.regex,
        ...extra,
    };
}

function canFollow() {
    return LIVE_RANGES.has(state.range);
}

function remember(list) {
    for (const entry of list) {
        byCursor.set(entry.cursor, entry);
    }
}

async function load() {
    const id = ++state.request;
    state.loading = true;
    state.error = '';
    state.more = false;
    state.fresh = 0;
    state.buffered = [];
    renderList();
    if (state.live) {
        if (canFollow()) {
            startFollowing();
        } else {
            setLive(false);
        }
    }
    const result = await window.logs.query(request());
    if (id !== state.request || result.stopped) {
        return;
    }
    state.loading = false;
    byCursor.clear();
    const seen = new Set(result.entries.map((entry) => entry.cursor));
    const newest = result.entries[0]?.time || 0;
    // What came in live while this was read, and is newer than what it found
    const extra = state.buffered.filter((entry) => !seen.has(entry.cursor) && entry.time >= newest).reverse();
    state.buffered = [];
    state.entries = [...extra, ...result.entries];
    remember(state.entries);
    state.more = result.more;
    state.error = result.error || '';
    state.command = result.command || state.command;
    if (state.selected && !byCursor.has(state.selected)) {
        state.selected = '';
        renderDetail();
    }
    renderHint();
    renderList();
}

async function loadOlder() {
    const last = state.entries.at(-1);
    if (!last || state.loadingMore) {
        return;
    }
    const id = state.request;
    state.loadingMore = true;
    renderFoot();
    const result = await window.logs.query(request({ after: last.cursor }));
    state.loadingMore = false;
    if (id !== state.request || result.stopped) {
        renderFoot();
        return;
    }
    const older = result.entries.filter((entry) => !byCursor.has(entry.cursor));
    remember(older);
    state.more = result.more && older.length > 0;
    const previous = state.entries.at(-1);
    state.entries.push(...older);
    if (result.error) {
        state.error = result.error;
    }
    if (live.rows) {
        live.rows.append(...rows(older, previous?.time));
    }
    renderFoot();
}

async function startFollowing() {
    const result = await window.logs.follow(request());
    if (result?.error) {
        setLive(false);
    }
}

function setLive(on) {
    state.live = on;
    state.fresh = 0;
    if (on) {
        startFollowing();
    } else {
        window.logs.stopFollowing();
    }
    renderActions();
    renderFresh();
}

// Entries written since, newest last, as main.js hands them over
function arrived(list) {
    if (!state.live) {
        return;
    }
    if (state.loading) {
        state.buffered.push(...list);
        return;
    }
    const fresh = list.filter((entry) => !byCursor.has(entry.cursor)).reverse();
    if (!fresh.length) {
        return;
    }
    remember(fresh);
    const wasEmpty = !state.entries.length;
    state.entries.unshift(...fresh);
    if (state.entries.length > LIVE_KEPT) {
        for (const entry of state.entries.splice(LIVE_KEPT)) {
            byCursor.delete(entry.cursor);
        }
        state.more = true;
    }
    if (wasEmpty || !live.rows) {
        renderList();
        return;
    }
    const scroller = live.scroller;
    const before = scroller.scrollHeight;
    const nodes = rows(fresh, null);
    // The day's heading moves up to above the new entries
    const first = live.rows.firstElementChild;
    if (first?.classList.contains('day') && first.dataset.day === String(midnight(fresh.at(-1).time))) {
        first.remove();
    }
    live.rows.prepend(...nodes);
    // Rows beyond what is kept go, with a heading left without rows under it
    while (live.rows.childElementCount > LIVE_KEPT + 60) {
        live.rows.lastElementChild.remove();
    }
    if (scroller.scrollTop > 8) {
        // Scrolled away to read something: it stays where it is
        scroller.scrollTop += scroller.scrollHeight - before;
        state.fresh += fresh.length;
        renderFresh();
    }
    renderCount();
}

// --- The list ------------------------------------------------------------------------------------------

function levelDot(priority) {
    const [word, tone] = PRIORITIES[priority];
    return h('span', { class: `level ${tone}`, title: word });
}

function row(entry, pattern) {
    return h('button', {
        type: 'button',
        class: `entry${entry.cursor === state.selected ? ' selected' : ''}${entry.priority <= 3 ? ' bad' : ''}`,
        'data-cursor': entry.cursor,
        onclick: () => openEntry(entry.cursor),
    },
    h('span', { class: 'entry-time' }, clock(entry.time)),
    levelDot(entry.priority),
    h('span', { class: 'entry-source', title: entry.source }, entry.source || '—'),
    h('span', { class: 'entry-message' }, marked(firstLine(entry.message), pattern)));
}

// Rows for entries newest first, with a heading wherever the day changes from the one before them
function rows(list, previousTime) {
    const pattern = matcher();
    const nodes = [];
    let day = previousTime ? midnight(previousTime) : null;
    for (const entry of list) {
        const today = midnight(entry.time);
        if (today !== day) {
            nodes.push(h('div', { class: 'day', 'data-day': String(today) }, dayName(entry.time)));
            day = today;
        }
        nodes.push(row(entry, pattern));
    }
    return nodes;
}

function emptyState() {
    const about = CATEGORIES[state.category];
    const range = rangeLabel(state.range);
    let title;
    let text;
    const actions = [];
    if (state.search) {
        title = 'Nothing matches';
        text = `No message ${range === 'those two minutes' ? 'in those two minutes' : `from ${range}`} has “${state.search}” in it. The search looks at what was said, not at who said it.`;
    } else if (state.source) {
        title = `Nothing from ${state.source.label}`;
        text = `It wrote nothing to the journal in ${range} that this view shows.`;
    } else {
        title = about.empty;
        text = state.category === 'important' || state.category === 'crashes'
            ? `Not in ${range}, at least.`
            : `Not in ${range}.`;
    }
    if (state.range !== 'all') {
        actions.push(button('Look further back', () => setRange('all'), { small: true }));
    }
    if (state.level < 7 && state.category !== 'important') {
        actions.push(button('Every level', () => setLevel(7), { small: true }));
    }
    const good = !state.search && !state.source && (state.category === 'important' || state.category === 'crashes');
    return h('div', { class: 'empty' },
        h('div', { class: `empty-icon ${good ? 'ok' : 'info'}` }, icon(good ? 'shield' : 'search', 28)),
        h('h2', {}, title),
        h('p', {}, text),
        actions.length ? h('div', { class: 'actions' }, actions) : null);
}

function renderCount() {
    if (!live.count) {
        return;
    }
    const count = state.entries.length;
    live.count.textContent = !count ? '' : state.more
        ? `The newest ${plural(count, 'entry', 'entries')}`
        : plural(count, 'entry', 'entries');
}

function renderFoot() {
    if (!live.foot) {
        return;
    }
    live.foot.replaceChildren();
    if (state.loadingMore) {
        live.foot.append(h('span', { class: 'soft' }, icon('spinner', 16, 'spin'), ' Reading older entries…'));
    } else if (state.more) {
        live.foot.append(button('Show older', loadOlder, { small: true, icon: 'chevron-down' }));
    } else if (state.entries.length) {
        live.foot.append(h('span', { class: 'faint small' }, state.range === 'all'
            ? 'That is as far back as the journal goes.'
            : `That is everything from ${rangeLabel(state.range)}.`));
    }
    renderCount();
}

function renderFresh() {
    if (!live.freshPill) {
        return;
    }
    live.freshPill.hidden = !state.fresh;
    live.freshPill.lastChild.textContent = `${plural(state.fresh, 'new entry', 'new entries')}`;
}

function renderList() {
    if (!live.list) {
        return;
    }
    live.rows = null;
    live.foot = null;
    if (state.loading) {
        live.list.replaceChildren(h('div', { class: 'loading' }, reading(),
            h('span', {}, state.search ? 'Searching the journal…' : 'Reading the journal…')));
        renderCount();
        return;
    }
    if (state.error) {
        live.list.replaceChildren(h('div', { class: 'list-pad' },
            callout('check', 'journalctl could not read that', state.error,
                state.regex ? h('p', {}, 'If it is the regular expression, switch it off to search for the text as typed.') : null)));
        renderCount();
        return;
    }
    if (!state.entries.length) {
        live.list.replaceChildren(emptyState());
        renderCount();
        return;
    }
    live.rows = h('div', { class: 'rows', role: 'list' }, rows(state.entries, null));
    live.foot = h('div', { class: 'list-foot' });
    live.list.replaceChildren(live.rows, live.foot);
    renderFoot();
}

// --- One entry -----------------------------------------------------------------------------------------

// The fields worth a name of their own, in the order they are shown, before the rest
const FACTS = [
    ['Program', (f) => [f._COMM || f.SYSLOG_IDENTIFIER, f._PID && `process ${f._PID}`].filter(Boolean).join(', ')],
    ['Service', (f) => f._SYSTEMD_UNIT && f._SYSTEMD_UNIT !== f._SYSTEMD_USER_UNIT ? f._SYSTEMD_UNIT : ''],
    ['Your service', (f) => f._SYSTEMD_USER_UNIT || ''],
    ['Executable', (f) => f._EXE || f.COREDUMP_EXE || ''],
    ['Command line', (f) => f._CMDLINE || f.COREDUMP_CMDLINE || ''],
    ['Signal', (f) => f.COREDUMP_SIGNAL_NAME || ''],
    ['Account', (f) => (f._UID ? `uid ${f._UID}` : '')],
    ['Where from', (f) => ({
        kernel: 'The kernel', audit: 'The audit log', syslog: 'syslog', journal: 'The journal',
        stdout: 'What it printed', driver: 'journald itself',
    }[f._TRANSPORT] || f._TRANSPORT || '')],
    ['Boot', (f) => f._BOOT_ID || ''],
];

function closeEntry() {
    state.selected = '';
    live.list?.querySelector('.entry.selected')?.classList.remove('selected');
    renderDetail();
}

function openEntry(cursor) {
    if (!byCursor.has(cursor)) {
        return;
    }
    state.selected = cursor;
    for (const node of live.list?.querySelectorAll('.entry.selected') || []) {
        node.classList.remove('selected');
    }
    const node = live.list?.querySelector(`.entry[data-cursor="${CSS.escape(cursor)}"]`);
    node?.classList.add('selected');
    node?.scrollIntoView({ block: 'nearest' });
    renderDetail();
}

// The next entry up or down the list from the open one
function step(by) {
    const index = state.entries.findIndex((entry) => entry.cursor === state.selected);
    const next = state.entries[index < 0 ? 0 : index + by];
    if (next) {
        openEntry(next.cursor);
        live.list?.querySelector(`.entry[data-cursor="${CSS.escape(next.cursor)}"]`)?.focus({ preventScroll: true });
    } else if (by > 0 && state.more) {
        loadOlder();
    }
}

function everyField(fields) {
    return Object.keys(fields).sort().map((key) => `${key}=${fields[key]}`).join('\n');
}

function detailPanel(entry) {
    const f = entry.fields;
    const [word, tone] = PRIORITIES[entry.priority];
    const crash = f.MESSAGE_ID === 'fc2e22bc6ee647b6b90729ab34a250b1';
    const title = crash
        ? `${f.COREDUMP_COMM || f.COREDUMP_EXE?.split('/').pop() || 'A program'} crashed`
        : entry.from?.label || entry.source || 'Entry';
    const facts = FACTS.map(([label, read]) => [label, read(f)]).filter(([, value]) => value);
    const actions = [copyButton('Copy message', entry.message)];
    if (entry.from && !(state.source && state.source.kind === entry.from.kind && state.source.id === entry.from.id)) {
        actions.push(button(`Only ${entry.from.label}`, () => setSource(entry.from), { small: true, icon: 'filter' }));
    }
    actions.push(button('Around this', () => around(entry), {
        small: true, icon: 'target', title: 'Everything from a minute before to a minute after',
    }));
    const fields = h('details', { class: 'fields' },
        h('summary', {}, icon('chevron', 15, 'chevron'), h('span', { class: 'grow' }, `Every field (${Object.keys(f).length})`)),
        h('dl', {}, Object.keys(f).sort().map((key) => [h('dt', {}, key), h('dd', {}, f[key])])),
        h('div', { class: 'fields-foot' }, copyButton('Copy every field', everyField(f))));
    return h('div', { class: 'detail-inner' },
        h('div', { class: 'detail-head' },
            h('span', { class: `pill ${tone}` }, word),
            h('span', { class: 'faint small grow' }, fullTime(entry.time)),
            h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Close', onclick: closeEntry }, icon('close', 18))),
        h('h2', { class: 'detail-title' }, title),
        h('pre', { class: 'message' }, marked(entry.message || '(no message)', matcher())),
        h('div', { class: 'detail-actions' }, actions),
        facts.length ? h('dl', { class: 'facts' }, facts.map(([label, value]) => [h('dt', {}, label), h('dd', {}, value)])) : null,
        fields);
}

function renderDetail() {
    if (!live.detail) {
        return;
    }
    const entry = byCursor.get(state.selected);
    live.layout.classList.toggle('open', Boolean(entry));
    live.detail.replaceChildren(entry ? detailPanel(entry) : '');
    live.detail.scrollTop = 0;
}

// --- The log view --------------------------------------------------------------------------------------

function title() {
    if (state.source) {
        return state.source.label;
    }
    if (state.range.startsWith('around:')) {
        return 'Around one entry';
    }
    return CATEGORIES[state.category].title;
}

function lead() {
    if (state.range.startsWith('around:')) {
        return 'Everything that was logged from a minute before it to a minute after.';
    }
    if (state.source) {
        return {
            app: 'What this app wrote, each time it ran.',
            unit: state.source.scope === 'user' ? 'One of the services of your session.' : 'One of the system’s services.',
            identifier: 'Everything logged under this name.',
        }[state.source.kind];
    }
    return CATEGORIES[state.category].lead;
}

function rangeSelect() {
    const options = RANGES.map(([value, label]) => h('option', { value }, label));
    const earlier = (state.overview?.boots || []).filter((boot) => boot.index < -1);
    if (earlier.length) {
        options.push(h('optgroup', { label: 'Earlier boots' },
            earlier.map((boot) => h('option', { value: `b:${boot.id}` }, bootLabel(boot)))));
    }
    if (!options.some((node) => node.value === state.range) && !earlier.some((boot) => `b:${boot.id}` === state.range)) {
        options.push(h('option', { value: state.range }, state.range.startsWith('around:') ? 'Two minutes' : 'That boot'));
    }
    return select('Time', options, state.range, setRange);
}

function levelSelect() {
    const levels = state.category === 'important' ? LEVELS.filter(([value]) => value <= 3) : LEVELS;
    const value = state.category === 'important' ? Math.min(state.level, 3) : state.level;
    return select('Level', levels.map(([level, label]) => h('option', { value: String(level) }, label)), value,
        (chosen) => setLevel(Number(chosen)));
}

function searchBox() {
    let timer = null;
    const input = h('input', {
        type: 'search',
        id: 'search',
        placeholder: 'Search messages',
        spellcheck: 'false',
        autocomplete: 'off',
        'aria-label': 'Search messages',
    });
    input.value = state.search;
    const apply = () => {
        clearTimeout(timer);
        if (input.value !== state.search) {
            state.search = input.value;
            load();
        }
    };
    input.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(apply, 400);
    });
    input.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
            apply();
        } else if (event.key === 'Escape' && input.value) {
            event.stopPropagation();
            input.value = '';
            apply();
        }
    });
    const regex = h('button', {
        type: 'button',
        class: 'toggle mono',
        'aria-pressed': String(state.regex),
        title: 'Search with a regular expression',
        onclick: () => {
            state.regex = !state.regex;
            regex.setAttribute('aria-pressed', String(state.regex));
            if (state.search) {
                load();
            }
            input.focus();
        },
    }, '.*');
    return h('label', { class: 'search' }, icon('search', 17), input, regex);
}

function chips() {
    const list = [];
    if (state.source) {
        list.push(h('span', { class: 'chip' }, icon('filter', 14), h('span', {}, `Only ${state.source.label}`),
            h('button', { type: 'button', 'aria-label': 'Show everything again', onclick: () => setSource(null) }, icon('close', 14))));
    }
    if (state.range.startsWith('around:')) {
        const second = Number(state.range.slice(7));
        list.push(h('span', { class: 'chip' }, icon('target', 14),
            h('span', {}, `${clock((second - 60) * 1000)} to ${clock((second + 60) * 1000)}, ${shortDay(second * 1000)}`),
            h('button', { type: 'button', 'aria-label': 'Back to this boot', onclick: () => setRange('boot') }, icon('close', 14))));
    }
    return list.length ? h('div', { class: 'chips' }, list) : null;
}

// Who is not shown what: the system's side of the journal is for administrators
function access() {
    const info = state.overview;
    if (!info || info.readable || state.category === 'session') {
        return null;
    }
    const command = state.command ? `sudo ${state.command}` : 'sudo journalctl';
    if (SYSTEM_VIEWS.has(state.category)) {
        return callout('check', 'Only administrators can read these',
            `The system’s logs are open to the administrators of this machine, and ${info.user} is not one.`,
            commandBlock('An administrator can read them in a terminal:', command));
    }
    return callout('info', 'Only your own logs',
        'The system’s logs are for the administrators of this machine: you see what your session and your apps wrote.');
}

function renderActions() {
    if (!live.actions) {
        return;
    }
    const followable = canFollow();
    live.actions.replaceChildren(
        button(state.live ? 'Live' : 'Follow', () => setLive(!state.live), {
            small: true,
            primary: state.live,
            pressed: state.live,
            icon: state.live ? 'pause' : 'live',
            disabled: !followable,
            title: followable ? 'Show new entries as they are written' : 'Only a time range that ends now can be followed',
        }),
        button('Export', exportLogs, { small: true, icon: 'download', title: 'Save what is shown to a file' }),
        button('', () => window.logs.terminal(request(), state.live), {
            small: true, icon: 'terminal', title: 'Open the same in journalctl, in a terminal',
        }),
        button('', () => {
            load();
            refreshOverview();
        }, { small: true, icon: 'refresh', title: 'Read again (Ctrl+R)' }));
}

function renderNotice() {
    if (!live.notice) {
        return;
    }
    const notice = state.notice;
    live.notice.replaceChildren(notice ? h('div', { class: `banner ${notice.tone}` },
        icon(notice.tone === 'check' ? 'alert' : 'info', 18),
        h('span', { class: 'grow' }, notice.text),
        h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Dismiss', onclick: () => setNotice(null) }, icon('close', 16))) : '');
}

let noticeTimer = null;
function setNotice(notice) {
    clearTimeout(noticeTimer);
    state.notice = notice;
    renderNotice();
    if (notice) {
        noticeTimer = setTimeout(() => setNotice(null), 8000);
    }
}

function logsPage() {
    live.actions = h('div', { class: 'head-actions' });
    live.count = h('span', { class: 'count' });
    live.notice = h('div', {});
    live.list = h('div', { class: 'log-list' });
    live.freshPill = h('button', {
        type: 'button',
        class: 'fresh',
        hidden: true,
        onclick: () => {
            live.scroller.scrollTo({ top: 0, behavior: 'smooth' });
        },
    }, icon('chevron-down', 15, 'up'), h('span', {}));
    live.scroller = h('div', { class: 'scroller' }, live.list);
    live.scroller.addEventListener('scroll', () => {
        if (live.scroller.scrollTop <= 8 && state.fresh) {
            state.fresh = 0;
            renderFresh();
        }
        if (state.more && !state.loadingMore && !state.loading &&
            live.scroller.scrollHeight - live.scroller.scrollTop - live.scroller.clientHeight < 400) {
            loadOlder();
        }
    });
    live.detail = h('aside', { class: 'detail', 'aria-label': 'The entry' });
    live.layout = h('div', { class: 'logs' },
        h('div', { class: 'logs-main' },
            h('header', { class: 'logs-head' },
                h('div', { class: 'title-row' },
                    h('div', { class: 'grow' }, h('h1', {}, title()), h('p', { class: 'lead' }, lead())),
                    live.actions),
                h('div', { class: 'toolbar' }, searchBox(), rangeSelect(), levelSelect(), live.count),
                chips(),
                access(),
                live.notice),
            h('div', { class: 'list-wrap' }, live.scroller, live.freshPill)),
        live.detail);
    renderActions();
    renderNotice();
    renderList();
    renderFresh();
    renderDetail();
    return live.layout;
}

// --- Apps and services -----------------------------------------------------------------------------------

function sourceMatches(...texts) {
    const filter = state.sourceFilter.trim().toLowerCase();
    return !filter || texts.some((text) => text.toLowerCase().includes(filter));
}

function sourceRow(kind, scope, unit) {
    return h('button', {
        type: 'button',
        class: 'list-row',
        onclick: () => setSource({ kind, id: unit.name, scope, label: unit.label }),
    },
    h('div', { class: 'grow' },
        h('strong', { class: 'mono' }, unit.label),
        unit.instances ? h('small', {}, `${unit.instances} instances, together`) : null),
    icon('chevron', 16, 'chevron'));
}

function sourcesSection(heading, count, body) {
    return h('section', { class: 'section' },
        h('div', { class: 'section-head' }, h('h2', {}, heading), h('span', { class: 'section-note' }, count)),
        body);
}

function sourcesPage() {
    const found = state.sources;
    const head = h('div', { class: 'page-head' },
        h('h1', {}, 'Apps and services'),
        h('p', { class: 'lead' }, 'Everything that has written to the journal. Pick one to read only what it said.'));
    if (!found) {
        return h('div', { class: 'page' }, head, h('div', { class: 'loading' }, reading()));
    }
    const filter = h('input', {
        type: 'search',
        placeholder: 'Find an app or service',
        spellcheck: 'false',
        autocomplete: 'off',
        'aria-label': 'Find an app or service',
    });
    filter.value = state.sourceFilter;
    const results = h('div', { class: 'stack' });
    const fill = () => {
        const apps = found.apps.filter((item) => sourceMatches(item.name, item.id));
        const user = found.user.filter((unit) => sourceMatches(unit.label));
        const system = found.system.filter((unit) => sourceMatches(unit.label));
        const none = h('div', { class: 'list-empty' }, 'None match.');
        results.replaceChildren(
            sourcesSection('Apps', apps.length, apps.length ? h('div', { class: 'apps' }, apps.map((item) => h('button', {
                type: 'button',
                class: 'app card',
                onclick: () => setSource({ kind: 'app', id: item.id, label: item.name }),
            },
            h('span', { class: 'avatar tone accent', 'aria-hidden': 'true' }, (item.name.match(/[\p{L}\p{N}]/u)?.[0] || '?').toUpperCase()),
            h('span', { class: 'grow app-text' }, h('strong', {}, item.name), h('small', {}, item.id))))) : h('div', { class: 'card' }, none)),
            sourcesSection('Your services', user.length,
                h('div', { class: 'card list' }, user.length ? user.map((unit) => sourceRow('unit', 'user', unit)) : none)),
            sourcesSection('System services', system.length, system.length || state.overview?.readable !== false
                ? h('div', { class: 'card list' }, system.length ? system.map((unit) => sourceRow('unit', 'system', unit)) : none)
                : callout('check', 'Only administrators can read these',
                    'The system’s services write to the system’s logs, which are for the administrators of this machine.')));
    };
    filter.addEventListener('input', () => {
        state.sourceFilter = filter.value;
        fill();
    });
    fill();
    return h('div', { class: 'page' },
        head,
        h('label', { class: 'search wide' }, icon('search', 17), filter),
        results);
}

async function loadSources() {
    state.sources = await window.logs.sources();
    if (state.page === 'sources') {
        render();
    }
}

// --- The page ------------------------------------------------------------------------------------------

function renderHint() {
    terminalHint.textContent = state.page === 'sources' ? 'journalctl --field=_SYSTEMD_UNIT' : state.command || 'journalctl';
}

function renderNav() {
    const counts = state.overview?.counts;
    for (const node of categoryButtons) {
        const current = state.page === 'logs' && !state.source && node.dataset.category === state.category;
        if (current) {
            node.setAttribute('aria-current', 'page');
        } else {
            node.removeAttribute('aria-current');
        }
        const badge = node.querySelector('.badge');
        if (badge) {
            const count = counts?.[node.dataset.category] || 0;
            badge.hidden = !count;
            badge.textContent = count ? capped(count) : '';
            badge.title = count ? 'This boot' : '';
        }
    }
    for (const node of pageButtons) {
        if (state.page === 'sources' || (state.page === 'logs' && state.source)) {
            node.setAttribute('aria-current', 'page');
        } else {
            node.removeAttribute('aria-current');
        }
    }
    usageNode.hidden = !state.overview?.usage;
    usageNode.textContent = state.overview?.usage
        ? `${state.overview.readable ? 'The journal takes' : 'Your logs take'} ${state.overview.usage} on disk.`
        : '';
}

function render() {
    for (const key of Object.keys(live)) {
        delete live[key];
    }
    renderNav();
    renderHint();
    view.dataset.page = state.page;
    view.replaceChildren(state.page === 'sources' ? sourcesPage() : logsPage());
}

// Anything that changes what is read draws the view again and reads it
function show(changes) {
    Object.assign(state, changes);
    state.page = 'logs';
    state.selected = changes.selected ?? '';
    render();
    load();
}

function openCategory(category) {
    show({ category, source: null, range: state.range.startsWith('around:') ? 'boot' : state.range });
}

function setSource(source) {
    show({ source, category: source ? 'all' : state.category });
}

function setRange(range) {
    show({ range, selected: state.selected });
}

function setLevel(level) {
    show({ level, selected: state.selected });
}

// Everything else on the machine in the two minutes around one entry, with that entry still open
function around(entry) {
    show({
        category: 'all',
        source: null,
        search: '',
        level: 7,
        range: `around:${Math.floor(entry.time / 1000)}`,
        selected: entry.cursor,
        live: false,
    });
    window.logs.stopFollowing();
}

async function exportLogs() {
    const result = await window.logs.exportLogs(request());
    if (result.saved) {
        setNotice({ tone: 'ok', text: `Saved as ${result.saved} in ${result.folder}.` });
    } else if (result.error) {
        setNotice({ tone: 'check', text: `Nothing was saved: ${result.error}` });
    }
}

async function refreshOverview() {
    state.overview = await window.logs.overview();
    renderNav();
    // The list of boots and who may read what are part of the view
    if (state.page === 'logs' && !state.loading) {
        const range = live.layout?.querySelector('.toolbar .select select');
        if (range) {
            range.parentElement.replaceWith(rangeSelect());
        }
        const current = live.layout?.querySelector('.logs-head > .callout');
        const replacement = access();
        if (current && replacement) {
            current.replaceWith(replacement);
        } else if (current) {
            current.remove();
        } else if (replacement) {
            live.notice.before(replacement);
        }
    }
}

function luminance(hex) {
    const [r, g, b] = [1, 3, 5]
        .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
        .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// The same palette mapping as the Manual's, Security's and Updates'
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

function openView(name) {
    if (name === 'sources') {
        state.page = 'sources';
        render();
        loadSources();
    } else if (Object.hasOwn(CATEGORIES, name)) {
        openCategory(name);
    }
}

window.logs.onPalette(applyPalette);
window.logs.onLive(arrived);
window.logs.onLiveEnded(() => {
    if (state.live) {
        setLive(false);
    }
});
window.logs.onOpen(openView);
// Back from elsewhere: the counts in the sidebar may have moved on
window.logs.onFocus(() => {
    if (state.overview && Date.now() - (state.overview.read || 0) > 30000) {
        refreshOverview().then(() => {
            state.overview.read = Date.now();
        });
    }
});

for (const node of categoryButtons) {
    node.addEventListener('click', () => openCategory(node.dataset.category));
}
for (const node of pageButtons) {
    node.addEventListener('click', () => openView(node.dataset.page));
}
document.getElementById('open-manual').addEventListener('click', () => window.logs.manual('troubleshooting#the-logs'));

function typing(target) {
    return target instanceof HTMLInputElement || target instanceof HTMLSelectElement || target instanceof HTMLTextAreaElement;
}

document.addEventListener('keydown', (event) => {
    if ((event.ctrlKey && event.key === 'r') || event.key === 'F5') {
        event.preventDefault();
        if (state.page === 'sources') {
            loadSources();
        } else {
            load();
        }
        refreshOverview();
    } else if ((event.ctrlKey && event.key === 'f') || (event.key === '/' && !typing(event.target))) {
        event.preventDefault();
        (document.getElementById('search') || view.querySelector('input'))?.focus();
    } else if (event.key === 'Escape' && state.selected) {
        closeEntry();
    } else if (state.page === 'logs' && !typing(event.target) && (event.key === 'ArrowDown' || event.key === 'j')) {
        event.preventDefault();
        step(1);
    } else if (state.page === 'logs' && !typing(event.target) && (event.key === 'ArrowUp' || event.key === 'k')) {
        event.preventDefault();
        step(-1);
    } else if (event.ctrlKey && (event.key === '=' || event.key === '+')) {
        window.logs.zoom(0.5);
    } else if (event.ctrlKey && event.key === '-') {
        window.logs.zoom(-0.5);
    } else if (event.ctrlKey && event.key === '0') {
        window.logs.zoom(0);
    }
});

async function start() {
    applyPalette(await window.logs.palette());
    const name = location.hash.slice(1);
    if (name === 'sources') {
        state.page = 'sources';
        render();
        loadSources();
    } else {
        state.category = Object.hasOwn(CATEGORIES, name) ? name : 'important';
        render();
        load();
    }
    await refreshOverview();
    state.overview.read = Date.now();
}

start();
