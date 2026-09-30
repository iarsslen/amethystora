'use strict';

// The page of Amethystora Security. The report is /usr/libexec/amethystora-security-status --json, the one
// `ujust security-status` prints, the scans are the ones main.js runs, and network protection is what the
// security watcher kept of Suricata's alerts. Everything shown is built as elements with text in them
// and never as markup: a file name is whatever somebody called a file, and a rule's name and a host
// name are whatever the network sent.

const main = document.getElementById('main');
const view = document.getElementById('view');
const navButtons = [...document.querySelectorAll('.nav [data-page]')];
const terminalHint = document.querySelector('.terminal code');

const state = {
    page: 'overview',
    report: null,
    scanner: null,
    history: [],
    home: '',
    // The scan in progress, as main.js last described it
    running: null,
    // What the result page is about: { entry } for a scan started here, { machine: true } for the weekly one
    result: null,
    // Why the last thing asked for did not happen
    notice: '',
    // When the whole-machine scan was started from here, before systemd says it is running
    machineAsked: 0,
    // Network protection, as main.js read it: what it blocked and noticed, and whether it runs
    network: null,
};

// The parts of the scanning page that change while it is on screen
const live = {};

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

function button(label, onclick, { icon: name, small, primary, disabled, after, title } = {}) {
    const classes = ['btn', small && 'small', primary && 'primary'].filter(Boolean).join(' ');
    return h('button', { type: 'button', class: classes, disabled: Boolean(disabled), title, onclick },
        name && !after ? icon(name, 16) : null,
        h('span', {}, label),
        name && after ? icon(name, 16) : null);
}

function linkButton(label, onclick, { icon: name, quiet, small } = {}) {
    const classes = ['link', quiet && 'quiet', small && 'small'].filter(Boolean).join(' ');
    return h('button', { type: 'button', class: classes, onclick }, name ? icon(name, 16) : null, h('span', {}, label));
}

function copyButton(text, label, description) {
    const caption = h('span', {}, label);
    return h('button', {
        type: 'button',
        class: 'btn small',
        'aria-label': description,
        onclick: () => {
            window.security.copy(text);
            caption.textContent = 'Copied';
            setTimeout(() => {
                caption.textContent = label;
            }, 1500);
        },
    }, icon('copy', 14), caption);
}

function pill(label, tone = '', { small, mono } = {}) {
    return h('span', { class: ['pill', tone, small && 'small', mono && 'mono'].filter(Boolean).join(' ') }, label);
}

const MARKS = { ok: 'mark-ok', info: 'mark-info', check: 'mark-alert', off: 'mark-alert' };

// The small round mark in front of a row
function dot(tone) {
    return h('span', { class: `dot ${tone}` }, icon(MARKS[tone] || 'mark-info', 13));
}

// ...and the larger one in front of a scan
function status(tone) {
    return h('span', { class: `status tone ${tone}` }, icon(MARKS[tone] || 'mark-info', 15));
}

function section(title, body, note) {
    return h('section', { class: 'section' },
        h('div', { class: 'section-head' }, h('h2', {}, title), note ? h('span', { class: 'section-note' }, note) : null),
        body);
}

function callout(tone, title, text, ...extra) {
    return h('div', { class: `callout ${tone}` },
        icon(tone === 'check' ? 'alert' : 'info', 20),
        h('div', { class: 'grow' }, h('strong', {}, title), text ? h('p', {}, text) : null, extra));
}

function commandBlock(lead, command) {
    return h('div', { class: 'command-wrap' },
        lead ? h('p', {}, lead) : null,
        h('div', { class: 'command' }, h('code', {}, command), copyButton(command, 'Copy', 'Copy the command')));
}

// --- Words ---------------------------------------------------------------------------------------------

const NUMBERS = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];

function number(n) {
    return NUMBERS[n] ?? n.toLocaleString();
}

function capital(text) {
    return text.charAt(0).toUpperCase() + text.slice(1);
}

function plural(n, one, many = `${one}s`) {
    return `${n.toLocaleString()} ${n === 1 ? one : many}`;
}

function time(ms) {
    return new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function when(ms) {
    const date = new Date(ms);
    const midnight = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    const days = Math.round((midnight(new Date()) - midnight(date)) / 86400000);
    if (days === 0) {
        return `today at ${time(ms)}`;
    }
    if (days === 1) {
        return `yesterday at ${time(ms)}`;
    }
    return `${date.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' })} at ${time(ms)}`;
}

function took(seconds) {
    if (seconds < 60) {
        return `${seconds} s`;
    }
    const minutes = Math.round(seconds / 60);
    return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
}

function clock(seconds) {
    const pad = (n) => String(n).padStart(2, '0');
    const hours = Math.floor(seconds / 3600);
    const rest = `${pad(Math.floor(seconds / 60) % 60)}:${pad(seconds % 60)}`;
    return hours ? `${hours}:${rest}` : rest.replace(/^0/, '');
}

function elapsed(since) {
    return clock(Math.max(0, Math.round((Date.now() - since) / 1000)));
}

// A path in the home folder, as ~/...
function tilde(file) {
    const home = state.home;
    return home && (file === home || file.startsWith(`${home}/`)) ? `~${file.slice(home.length)}` : file;
}

function basename(file) {
    return file.replace(/\/+$/, '').split('/').pop() || file;
}

function signaturesText(signatures) {
    if (!signatures) {
        return 'None yet';
    }
    if (signatures.stale) {
        return `${signatures.days} days old`;
    }
    if (signatures.days === 0) {
        return 'Updated today';
    }
    return signatures.days === 1 ? 'Updated yesterday' : `Updated ${signatures.days} days ago`;
}

// --- The report ----------------------------------------------------------------------------------------

const GROUPS = [['updates', 'Updates and boot'], ['watching', 'Watching'], ['scans', 'Scans']];
const TILE_ICONS = {
    'security-key': 'key',
    backups: 'archive',
    'ransomware-protection': 'history',
    'disk-unlock': 'chip',
    'usb-protection': 'plug',
    'key-remapping': 'keyboard',
    'on-detection': 'file-alert',
    realtime: 'activity',
    'network-protection': 'globe',
};

// What this machine does with what a scan finds (ON_DETECTION), as the report read it
function detection() {
    return state.report?.settings?.on_detection || 'report';
}

const DETECTION_DONE = {
    report: 'Nothing was deleted, quarantined or moved.',
    quarantine: 'What it found was moved to quarantine.',
    delete: 'What it found was deleted.',
};

const SCAN_LEADS = {
    report: 'What it finds is reported, and never deleted, quarantined or moved.',
    quarantine: 'What it finds is moved to quarantine, which asks for your password.',
    delete: 'What it finds is deleted, which asks for your password.',
};

// What was done to one file a scan started here found
const OUTCOMES = {
    quarantined: ['Quarantined', ''],
    deleted: ['Deleted', ''],
    declined: ['Left in place', 'check'],
    failed: ['Could not be moved', 'check'],
    clean: ['Clean on a second look', 'ok'],
};

// ...and to all of them, in a sentence
function entryDone(entry) {
    const outcomes = new Set(entry.found.map((item) => item.outcome).filter((outcome) => outcome && outcome !== 'reported'));
    if (!outcomes.size) {
        return DETECTION_DONE.report;
    }
    if (outcomes.size === 1 && outcomes.has('quarantined')) {
        return 'Moved to quarantine.';
    }
    if (outcomes.size === 1 && outcomes.has('deleted')) {
        return 'Deleted.';
    }
    if (outcomes.size === 1 && outcomes.has('declined')) {
        return 'Left where it is, without the password.';
    }
    return 'Each file below says what was done with it.';
}

// ...and what to know about that
function doneNote(entry) {
    const has = (outcome) => entry.found.some((item) => item.outcome === outcome);
    if (has('quarantined')) {
        return 'Quarantined files are kept where nothing can open them. ujust virus-scan shows them, and ujust virus-scan restore puts one back.';
    }
    if (has('deleted')) {
        return 'A deleted file can only come back from a backup.';
    }
    return 'A match can be a false positive, so check where the file came from first. If you did not mean to have it, delete it in Files, then scan again.';
}
// Where the manual explains a check, when it is not the Security page
const MANUAL_PAGES = {
    'secure-boot': 'hardware#secure-boot',
    'signing-keys': 'hardware#secure-boot',
    'signed-updates': 'updates#signed-updates',
    'single-build': 'updates',
    network: 'security#network-protection',
    'network-protection': 'security#network-protection',
    'home-snapshots': 'security#ransomware-protection',
    'ransomware-protection': 'security#ransomware-protection',
};

function manualPage(id) {
    return id.startsWith('key-') ? 'hardware#secure-boot' : MANUAL_PAGES[id] || 'security';
}

function checks(group) {
    return (state.report?.checks || []).filter((check) => check.group === group);
}

function needsAttention(check) {
    return check.group !== 'optional' && (check.state === 'check' || check.state === 'off');
}

// A check's details, and apart from them the one ending in a colon that introduces its command
function explain(check) {
    const lines = [...check.details];
    const lead = check.command && lines.length && lines[lines.length - 1].endsWith(':') ? lines.pop() : '';
    return { lines, lead };
}

// The latest scan started here that found something, until it is dismissed or a later scan of the same
// place comes back clean
function openFinding() {
    const cleared = new Set();
    for (const entry of state.history) {
        const place = entry.targets.join('\n');
        if (entry.status === 'clean') {
            cleared.add(place);
        } else if (entry.status === 'found' && !entry.dismissed && !cleared.has(place)) {
            return entry;
        }
    }
    return null;
}

function attentionItems() {
    const items = (state.report?.checks || []).filter(needsAttention).map((check) => ({ check, tone: check.state }));
    const finding = openFinding();
    if (finding) {
        items.unshift({ finding, tone: 'off' });
    }
    // What is off before what only wants a look
    return items.sort((a, b) => (a.tone === 'off' ? 0 : 1) - (b.tone === 'off' ? 0 : 1));
}

// --- Navigation -----------------------------------------------------------------------------------------

function setBadge(badge, content, tone) {
    badge.className = `badge ${tone}`;
    badge.replaceChildren(content || '');
    badge.hidden = !content;
}

// The sidebar entry each page is under, and the recipe that does in a terminal what it does
const NAV = { overview: 'overview', scan: 'scan', scanning: 'scan', result: 'scan', network: 'network' };
const RECIPES = { overview: 'ujust security-status', scan: 'ujust virus-scan', network: 'ujust blocked-connections' };

function renderNav() {
    const current = NAV[state.page];
    terminalHint.textContent = RECIPES[current];
    const items = attentionItems();
    const machine = state.scanner?.machine;
    const busy = Boolean(state.running || machine?.running);
    const findings = (openFinding() ? 1 : 0) + (machine?.found ? 1 : 0);
    const blocked = recentBlocks();
    for (const node of navButtons) {
        const page = node.dataset.page;
        if (page === current) {
            node.setAttribute('aria-current', 'page');
        } else {
            node.removeAttribute('aria-current');
        }
        const badge = node.querySelector('.badge');
        if (page === 'overview') {
            setBadge(badge, items.length ? String(items.length) : '', items.some((item) => item.tone === 'off') ? 'off' : 'check');
        } else if (page === 'network') {
            setBadge(badge, blocked ? String(blocked) : '', 'off');
        } else if (busy) {
            setBadge(badge, icon('spinner', 12, 'spin'), 'busy');
        } else {
            setBadge(badge, findings ? String(findings) : '', 'off');
        }
    }
}

const PAGES = {
    overview: () => overviewPage(),
    scan: () => scanPage(),
    scanning: () => scanningPage(),
    result: () => resultPage(),
    network: () => networkPage(),
};

function render() {
    const keep = view.dataset.page === state.page ? main.scrollTop : 0;
    for (const key of Object.keys(live)) {
        delete live[key];
    }
    const page = PAGES[state.page]();
    renderNav();
    view.replaceChildren(page);
    view.dataset.page = state.page;
    main.scrollTop = keep;
}

function show(page, result) {
    state.page = page;
    if (result !== undefined) {
        state.result = result;
    }
    render();
}

// --- Overview ---------------------------------------------------------------------------------------------

function overviewPage() {
    const report = state.report;
    if (!report) {
        return h('div', { class: 'loading' }, 'Checking this machine…');
    }
    const items = attentionItems();
    const on = report.checks.filter((check) => check.group !== 'optional' && check.state === 'ok').length;
    let tone = items.some((item) => item.tone === 'off') ? 'off' : items.length ? 'check' : 'ok';
    let headline = 'Everything is on';
    let summary = `All ${number(on)} checks are on, and nothing needs you right now.`;
    if (items.length) {
        headline = items.length === 1 ? 'One thing to look at' : `${capital(number(items.length))} things to look at`;
        summary = on === 1 ? 'The other check is on.' : on ? `The other ${number(on)} checks are all on.` : '';
    }
    if (report.error) {
        [tone, headline, summary] = ['check', 'The report could not be read', report.error];
    }
    return h('div', { class: 'page' },
        hero(headline, summary, tone, items.length),
        items.length ? section('Needs your attention', h('div', { class: 'stack' }, items.map(attentionCard))) : null,
        groupsSection(items.length > 0),
        optionalSection());
}

function hero(headline, summary, tone, count) {
    const again = button('Check again', async () => {
        again.disabled = true;
        again.querySelector('span').textContent = 'Checking…';
        await reload();
    }, { icon: 'refresh' });
    return h('section', { class: 'hero', 'aria-labelledby': 'headline' },
        h('div', { class: 'emblem' },
            document.getElementById('shield-art').content.cloneNode(true),
            h('span', { class: `emblem-badge ${tone}` }, count ? String(count) : icon(tone === 'ok' ? 'mark-ok' : 'mark-alert', 14))),
        h('div', { class: 'hero-text' },
            h('div', { class: 'mono soft small' }, state.report.image),
            h('h1', { id: 'headline' }, headline),
            summary ? h('p', { class: 'lead' }, summary) : null),
        h('div', { class: 'hero-side' },
            again,
            h('span', { class: 'faint small' }, `Checked at ${time(state.report.checked)}`)));
}

function attentionCard(item) {
    if (item.finding) {
        return findingCard(item.finding);
    }
    const { check } = item;
    const { lines, lead } = explain(check);
    // The weekly scan's findings are in a root-only log, which the recipe shows after asking for a password
    const weekly = check.id === 'virus-scan';
    return h('article', { class: `attention ${check.state}` },
        h('div', { class: `attention-icon tone ${check.state}` }, icon(check.state === 'off' ? 'alert' : 'shield-alert', 22)),
        h('div', { class: 'attention-body' },
            h('div', { class: 'attention-head' },
                h('div', { class: 'attention-title' },
                    pill(check.state === 'off' ? 'Off' : 'Check', check.state), h('h3', {}, check.text)),
                lines.map((line) => h('p', { class: 'soft' }, line)),
                weekly ? h('p', { class: 'soft' }, `${DETECTION_DONE[detection()]} What it found is in a log only an administrator can read, so seeing it asks for your password.`) : null),
            check.command && !weekly ? commandBlock(lead, check.command) : null,
            h('div', { class: 'actions' },
                check.command
                    ? button(weekly ? 'See what it found' : 'Run in a terminal', () => window.security.run(check.id),
                        { icon: weekly ? 'arrow-right' : 'terminal', after: weekly })
                    : null,
                linkButton(`${check.title} in the manual`, () => window.security.manual(manualPage(check.id)), { icon: 'book' }))));
}

function findingTitle(entry) {
    return entry.single
        ? `${entry.label} matches known malware`
        : `A scan of ${entry.label} found ${plural(entry.found.length, 'file')}`;
}

function findingCard(entry) {
    const first = entry.found[0];
    return h('article', { class: 'attention off' },
        h('div', { class: 'attention-icon tone off' }, icon('file-alert', 22)),
        h('div', { class: 'attention-body' },
            h('div', { class: 'attention-head' },
                h('div', { class: 'attention-title' }, pill('Found', 'off'), h('h3', {}, findingTitle(entry))),
                h('p', { class: 'soft' },
                    [capital(when(entry.started)), first?.signature, entryDone(entry)].filter(Boolean).join(' · ')))),
        h('div', { class: 'attention-side' },
            button('See what it found', () => show('result', { entry }), { icon: 'arrow-right', after: true }),
            linkButton('Dismiss', async () => {
                await window.security.dismiss(entry.id);
                entry.dismissed = true;
                render();
            }, { quiet: true, small: true })));
}

function checkRow(check) {
    const { lines } = explain(check);
    return h('div', { class: 'row' },
        dot(check.state === 'ok' ? 'ok' : 'info'),
        h('div', { class: 'row-text' },
            h('div', { class: 'row-title' }, check.title),
            h('div', { class: 'row-detail' }, check.text),
            lines.length ? h('div', { class: 'row-detail' }, lines.join(' ')) : null,
            check.command ? linkButton('Run it now', () => window.security.run(check.id), { small: true }) : null));
}

function groupsSection(attention) {
    const rowsOf = (group) => checks(group).filter((check) => !needsAttention(check));
    const cards = GROUPS.map(([group, title]) => {
        const rows = rowsOf(group);
        if (!rows.length) {
            return null;
        }
        const on = rows.filter((check) => check.state === 'ok').length;
        return h('div', { class: 'group card' },
            h('div', { class: 'group-head' }, h('h3', {}, title), on ? pill(`${on} on`, 'ok', { small: true }) : null),
            rows.map(checkRow));
    }).filter(Boolean);
    if (!cards.length) {
        return null;
    }
    const allOn = GROUPS.every(([group]) => rowsOf(group).every((check) => check.state === 'ok'));
    const title = attention ? (allOn ? 'Everything else is on' : 'Everything else') : 'What is on';
    return section(title, h('div', { class: 'groups' }, cards));
}

function optionalSection() {
    const optional = checks('optional');
    if (!optional.length) {
        return null;
    }
    const tiles = optional.map((check) => {
        const unavailable = check.state === 'unavailable';
        const stateText = unavailable ? check.details[0] || 'Not available here' : check.state === 'on' ? 'On' : 'Off';
        return h('div', { class: 'tile card' },
            h('div', { class: 'tile-icon tone accent' }, icon(TILE_ICONS[check.id] || 'shield', 20)),
            h('div', { class: 'tile-text' }, h('h3', {}, check.title), h('p', {}, check.text)),
            h('div', { class: 'tile-foot' },
                h('span', { class: `tile-state ${check.state}` }, stateText),
                button(check.state === 'on' ? 'Change…' : 'Set up…', () => window.security.run(check.id),
                    { small: true, disabled: unavailable })));
    });
    tiles.push(h('button', { type: 'button', class: 'tile manual-tile', onclick: () => window.security.manual('security') },
        h('span', { class: 'tile-text' },
            h('span', { class: 'tile-title' }, 'What each one does'),
            h('span', { class: 'tile-note' }, 'And how to undo it, in the Security page of the manual.')),
        h('span', { class: 'link' }, icon('book', 16), h('span', {}, 'Open the manual'))));
    return section('Off unless you turn it on', h('div', { class: 'tiles' }, tiles), 'Setting one up opens it in a terminal');
}

// --- Virus scan ----------------------------------------------------------------------------------------

function scanPage() {
    const scanner = state.scanner;
    const busy = Boolean(state.running || scanner?.machine.running);
    const blocked = !scanner?.signatures || busy;
    return h('div', { class: 'page' },
        h('header', { class: 'page-head' },
            h('h1', {}, 'Virus scan'),
            h('p', { class: 'lead' }, `ClamAV compares your files with known malware. ${SCAN_LEADS[detection()]}`)),
        state.notice ? h('p', { class: 'notice', role: 'alert' }, state.notice) : null,
        busy
            ? h('div', { class: 'banner' },
                icon('spinner', 18, 'spin'),
                h('span', { class: 'grow' }, state.running ? `Scanning ${state.running.label}` : 'Scanning the whole machine'),
                linkButton('Show it', () => show('scanning')))
            : null,
        scanStrip(scanner),
        section('Scan', h('div', { class: 'choices' },
            choice({ main: true, icon: 'home', title: 'Your home folder', text: 'Everything you keep here, apart from caches.' },
                button('Scan now', () => begin(() => window.security.scanHome()), { primary: true, disabled: blocked })),
            choice({ icon: 'folder', title: 'A file or folder', text: 'Choose some, or drop them anywhere on this window.' },
                button('Files…', () => begin(() => window.security.scanPick(false)), { disabled: blocked }),
                button('Folders…', () => begin(() => window.security.scanPick(true)), { disabled: blocked })),
            choice({ icon: 'monitor', title: 'The whole machine', text: 'All home and temporary folders, like the weekly scan.' },
                button('Scan', scanMachine, { disabled: blocked })))),
        section('Recent scans', recentList()));
}

function choice({ main: highlighted, icon: name, title, text }, ...actions) {
    return h('div', { class: `choice card${highlighted ? ' main' : ''}` },
        h('div', { class: 'choice-icon tone accent' }, icon(name, 21)),
        h('div', { class: 'choice-text' }, h('h3', {}, title), h('p', {}, text)),
        h('div', { class: 'actions' }, actions));
}

function stripCell(tone, name, label, value) {
    return h('div', {},
        h('div', { class: `strip-icon tone ${tone}` }, icon(name, 19)),
        h('div', { class: 'grow' }, h('span', { class: 'label' }, label), h('span', { class: 'value' }, value)));
}

function scanStrip(scanner) {
    if (!scanner) {
        return h('div', { class: 'strip card' }, h('div', {}, h('span', { class: 'soft' }, 'Checking the scanner…')));
    }
    const { machine, signatures } = scanner;
    let weekly = ['accent', 'Sundays, not run yet'];
    if (machine.running) {
        weekly = ['accent', 'Running now'];
    } else if (machine.found) {
        weekly = ['off', 'Last one found something'];
    } else if (machine.status === 2 || machine.status > 3) {
        weekly = ['check', 'Last one could not run'];
    } else if (machine.finished) {
        weekly = ['ok', 'Last one found nothing'];
    }
    return h('div', { class: 'strip card' },
        stripCell(signatures && !signatures.stale ? 'ok' : 'check', 'database', 'Signatures', signaturesText(signatures)),
        stripCell(weekly[0], 'calendar', 'Weekly scan', weekly[1]),
        stripCell(signatures ? 'ok' : 'check', 'activity', 'Scanner', signatures ? 'Ready' : 'Waiting for signatures'));
}

function recentList() {
    const rows = [];
    if (state.scanner) {
        rows.push(machineRow(state.scanner.machine));
    }
    for (const entry of state.history.slice(0, 6)) {
        rows.push(entryRow(entry));
    }
    return rows.length
        ? h('div', { class: 'list card' }, rows)
        : h('div', { class: 'list card' }, h('p', { class: 'list-empty' }, 'No scans yet.'));
}

function entryOutcome(entry) {
    switch (entry.status) {
        case 'found':
            return ['off', pill(entry.found.length ? `${entry.found.length.toLocaleString()} found` : 'Found', 'off')];
        case 'clean':
            return ['ok', pill('Nothing found', 'ok')];
        case 'failed':
            return ['check', pill('Could not run', 'check')];
        default:
            return ['info', pill('Stopped')];
    }
}

function entryRow(entry) {
    const [tone, outcome] = entryOutcome(entry);
    const meta = [capital(when(entry.started)), `took ${took(entry.seconds)}`, entry.files ? plural(entry.files, 'file') : null]
        .filter(Boolean).join(' · ');
    return h('button', { type: 'button', class: 'list-row', onclick: () => show('result', { entry }) },
        status(tone),
        h('span', { class: 'grow' }, h('strong', {}, entry.kind === 'home' ? 'Your home folder' : entry.label), h('small', {}, meta)),
        outcome,
        icon('chevron', 16, 'chevron'));
}

function machineOutcome(machine) {
    if (machine.running) {
        return ['info', pill('Running')];
    }
    if (machine.found) {
        return ['off', pill('Found something', 'off')];
    }
    if (machine.status === 2 || machine.status > 3) {
        return ['check', pill('Could not run', 'check')];
    }
    if (!machine.finished) {
        return ['info', pill('Not run yet')];
    }
    if (machine.status === 3) {
        return ['check', pill('Old signatures', 'check')];
    }
    return ['ok', pill('Nothing found', 'ok')];
}

function machineRow(machine) {
    const [tone, outcome] = machineOutcome(machine);
    let meta = 'Weekly, on Sundays';
    if (machine.running) {
        meta = 'Every home and temporary folder · running now';
    } else if (machine.finished) {
        meta = `Weekly, on Sundays · last ${when(machine.finished)}`;
    }
    return h('button', {
        type: 'button',
        class: 'list-row',
        onclick: () => (machine.running ? show('scanning') : show('result', { machine: true })),
    },
    status(tone),
    h('span', { class: 'grow' }, h('strong', {}, 'The whole machine'), h('small', {}, meta)),
    outcome,
    icon('chevron', 16, 'chevron'));
}

// --- Scanning ------------------------------------------------------------------------------------------

function stat(value, label) {
    return h('div', {}, value, h('span', { class: 'label' }, label));
}

function updateLive() {
    const progress = state.running;
    if (!progress || !live.files) {
        return;
    }
    live.files.textContent = progress.files.toLocaleString();
    live.found.textContent = progress.found.toLocaleString();
    live.found.classList.toggle('off', progress.found > 0);
    live.path.textContent = progress.loading
        ? 'Loading the virus signatures…'
        : progress.current ? tilde(progress.current) : 'Starting…';
}

function scanningPage() {
    const progress = state.running;
    const machine = state.scanner?.machine;
    if (!progress && !machine?.running) {
        state.page = 'scan';
        return scanPage();
    }
    live.since = progress ? progress.started : Math.max(machine.started || 0, state.machineAsked) || Date.now();
    live.elapsed = h('span', { class: 'stat-value' }, elapsed(live.since));
    const stats = [];
    if (progress) {
        live.files = h('span', { class: 'stat-value' });
        live.found = h('span', { class: 'stat-value' });
        live.path = h('code');
        stats.push(stat(live.files, 'Files checked'), stat(live.found, 'Found'));
    }
    stats.push(stat(live.elapsed, 'Elapsed'));
    const page = h('div', { class: 'scanning' },
        h('div', { class: 'gem', 'aria-hidden': 'true' }, h('img', { src: 'gem.svg', alt: '' }), h('div', { class: 'sweep' })),
        h('h1', {}, progress ? `Scanning ${progress.label}` : 'Scanning the whole machine'),
        h('p', { class: 'lead' }, progress
            ? 'You can keep working meanwhile. Nothing is deleted or moved.'
            : 'Every home and temporary folder, at low priority so that it stays out of your way. It carries on if you close this window, and nothing is deleted or moved.'),
        h('div', { class: 'stats card' }, stats),
        h('div', { class: 'current' },
            progress ? h('div', { class: 'current-path' }, icon('file', 15), live.path) : null,
            h('div', { class: 'bar', role: 'progressbar', 'aria-label': 'Scanning' }, h('div'))),
        progress
            ? button('Stop the scan', () => window.security.stop(), { icon: 'stop' })
            : button('Back to Virus scan', () => show('scan')),
        h('p', { class: 'footnote' }, `Signatures ${signaturesText(state.scanner?.signatures).toLowerCase()} · caches are skipped`));
    updateLive();
    return page;
}

// --- Results -------------------------------------------------------------------------------------------

function back() {
    return h('div', {}, linkButton('Virus scan', () => show('scan'), { icon: 'arrow-left', quiet: true }));
}

function resultHead(tone, name, title, subtitle) {
    return h('header', { class: 'result-head' },
        h('div', { class: `result-icon tone ${tone}` }, icon(name, 28)),
        h('div', { class: 'grow' }, h('h1', {}, title), subtitle ? h('p', { class: 'lead' }, subtitle) : null));
}

function fact(label, value, mono = false) {
    return h('div', {}, h('div', { class: 'grow' },
        h('span', { class: 'label' }, label), h('span', { class: `value${mono ? ' mono' : ''}` }, value)));
}

function findingRow(item) {
    const [outcome, tone] = OUTCOMES[item.outcome] || [];
    // Gone from where it was: there is nothing to show in Files
    const moved = item.outcome === 'quarantined' || item.outcome === 'deleted';
    return h('div', { class: 'finding card' },
        h('div', { class: 'attention-icon tone off' }, icon('file', 21)),
        h('div', { class: 'grow' },
            h('div', { class: 'finding-name' }, h('span', {}, basename(item.path)), pill(item.signature, 'off', { mono: true }),
                outcome ? pill(outcome, tone, { small: true }) : null),
            h('code', {}, tilde(item.path))),
        h('div', { class: 'actions' },
            moved ? null : button('Show in Files', () => window.security.showInFiles(item.path), { icon: 'folder', small: true }),
            copyButton(item.path, 'Copy path', 'Copy the path of the file')));
}

function scanResult(entry) {
    const found = entry.found.length;
    const one = entry.targets.length === 1;
    const titles = {
        found: found ? (entry.single ? `${entry.label} matches known malware` : `Found ${plural(found, 'file')} in ${entry.label}`) : `The scan of ${entry.label} found something`,
        clean: `No known malware in ${entry.label}`,
        stopped: `The scan of ${entry.label} was stopped`,
        failed: `The scan of ${entry.label} could not run`,
    };
    const tones = { found: 'off', clean: 'ok', stopped: 'info', failed: 'check' };
    const icons = { found: 'file-alert', clean: 'mark-ok', stopped: 'stop', failed: 'alert' };
    // Joined rather than full-stopped: a time can end in "p.m." already
    const subtitle = [
        `Scanned ${when(entry.started)}`,
        entry.status === 'found' && found && !entry.single
            ? `${capital(number(found))} ${found === 1 ? 'file matches' : 'files match'} known malware` : null,
        entry.stopped ? `Stopped after ${plural(entry.files, 'file')}` : null,
    ].filter(Boolean).join(' · ');
    const parts = [
        back(),
        resultHead(tones[entry.status] || 'info', icons[entry.status] || 'info', titles[entry.status] || entry.label, subtitle),
        h('div', { class: 'strip card' },
            fact(one ? (entry.single ? 'File' : 'Folder') : 'Scanned', one ? tilde(entry.targets[0]) : entry.label, one),
            fact('Files checked', entry.files.toLocaleString()),
            fact('Time', took(entry.seconds)),
            fact('Signatures', signaturesText(entry.signatures))),
    ];
    if (entry.status === 'found') {
        parts.push(callout('info', entryDone(entry).replace(/\.$/, ''), doneNote(entry)));
    }
    if (entry.status === 'failed') {
        parts.push(callout('check', 'The scanner could not start', entry.message));
    }
    if (entry.errors) {
        parts.push(h('p', { class: 'soft' },
            `${plural(entry.errors, 'file')} could not be read, and ${entry.errors === 1 ? 'was' : 'were'} not checked.`));
    }
    if (found) {
        parts.push(section('What it found', h('div', { class: 'stack' }, entry.found.map(findingRow))));
    }
    parts.push(h('div', { class: 'actions' },
        button('Scan again', () => begin(() => window.security.scanAgain(entry.id)), { primary: true, disabled: Boolean(state.running) }),
        button('Done', () => show('scan'))));
    return h('div', { class: 'page' }, parts);
}

function machineResult() {
    const machine = state.scanner?.machine;
    if (!machine) {
        state.page = 'scan';
        return scanPage();
    }
    if (machine.running) {
        state.page = 'scanning';
        return scanningPage();
    }
    const finished = machine.finished ? `Finished ${when(machine.finished)}` : '';
    let head = resultHead('ok', 'mark-ok', 'No known malware on this machine', finished);
    let body = [];
    if (machine.found) {
        head = resultHead('off', 'file-alert', 'The scan of the whole machine found something', finished);
        body = [callout('info', DETECTION_DONE[detection()].replace(/\.$/, ''),
            'What it found is in a log only an administrator can read, so seeing it asks for your password.',
            h('div', { class: 'actions' },
                button('See what it found', () => window.security.run('virus-scan'), { icon: 'terminal' })))];
    } else if (!machine.finished) {
        head = resultHead('info', 'monitor', 'The whole machine has not been scanned yet',
            'The weekly scan runs on Sundays, or now if you start it.');
    } else if (machine.status === 2) {
        head = resultHead('check', 'alert', 'There were no signatures to scan with', finished);
        body = [callout('check', 'Nothing was scanned',
            'The signatures download on their own soon after the machine is installed. If that was a while ago, check its network.')];
    } else if (machine.status > 3) {
        head = resultHead('check', 'alert', 'The scan of the whole machine could not run', finished);
        body = [callout('check', 'Its log says why', '', commandBlock('', 'journalctl -u amethystora-clamav-scan.service'))];
    } else if (machine.status === 3) {
        head = resultHead('check', 'alert', 'Nothing found, with old signatures', finished);
        body = [callout('check', 'A clean result proves little',
            "The signatures are too old for a clean scan to mean much. Check this machine's network.")];
    }
    return h('div', { class: 'page' },
        back(),
        head,
        body,
        h('div', { class: 'actions' },
            button('Scan again', scanMachine, { primary: true, disabled: Boolean(state.running) || !state.scanner.signatures }),
            button('Done', () => show('scan'))));
}

function resultPage() {
    const result = state.result;
    if (!result) {
        state.page = 'scan';
        return scanPage();
    }
    return result.machine ? machineResult() : scanResult(result.entry);
}

// --- Network protection --------------------------------------------------------------------------------

// NETWORK in /etc/amethystora/security.conf, as the report read it
function networkMode() {
    return state.report?.settings?.network || 'off';
}

const NETWORK_LEADS = {
    off: 'Suricata can inspect every connection this machine makes and receives, and cut off the ones to known malware, command servers and exploits. It is off.',
    watch: 'Suricata inspects every connection this machine makes and receives, and says what it recognises. Nothing is blocked yet.',
    block: 'Suricata inspects every connection this machine makes and receives, and cuts off the ones to known malware, command servers and exploits.',
};

const NETWORK_MODES = { off: 'Off', watch: 'Watching', block: 'Blocking' };

// Connections blocked since a moment, in seconds, counting each time a rule went off
function blockedSince(seconds) {
    return (state.network?.events || [])
        .filter((event) => event.action === 'blocked' && event.time >= seconds)
        .reduce((sum, event) => sum + (event.count || 1), 0);
}

// ...and in the last day, which the sidebar counts
function recentBlocks() {
    return blockedSince(Date.now() / 1000 - 86400);
}

function rulesText(rules) {
    if (!rules) {
        return 'None yet';
    }
    const days = Math.floor((Date.now() / 1000 - rules) / 86400);
    if (days <= 0) {
        return 'Updated today';
    }
    return days === 1 ? 'Updated yesterday' : `Updated ${days} days ago`;
}

function networkStrip(mode, network) {
    const on = mode !== 'off';
    const running = Boolean(network?.running);
    const stale = network?.rules && Date.now() / 1000 - network.rules > 7 * 86400;
    const week = blockedSince(Date.now() / 1000 - 7 * 86400);
    return h('div', { class: 'strip card' },
        stripCell(on ? 'ok' : 'info', 'shield', 'Mode', NETWORK_MODES[mode] || mode),
        stripCell(!on ? 'info' : running ? 'ok' : 'check', 'activity', 'Suricata', on && running ? 'Running' : 'Not running'),
        stripCell(!on ? 'info' : network?.rules && !stale ? 'ok' : 'check', 'database', 'Rules', rulesText(network?.rules)),
        stripCell('accent', 'globe', 'Blocked this week', week.toLocaleString()));
}

// Leaves the rule out on this machine, after an administrator's password. Declining it changes nothing.
function allowButton(event) {
    const node = button('Allow', async () => {
        node.disabled = true;
        node.querySelector('span').textContent = 'Allowing…';
        const outcome = await window.security.allowRule(event.sid);
        state.notice = outcome.error || '';
        state.network = await window.security.network();
        render();
    }, { small: true, title: `Leave rule ${event.sid} out on this machine. Asks for your password.` });
    return node;
}

function networkRow(event, allowed) {
    const blocked = event.action === 'blocked';
    const isAllowed = allowed.includes(event.sid);
    const peer = event.host || `${event.src} and ${event.dest}`;
    const meta = [
        capital(when(event.time * 1000)),
        event.port ? `${peer}, port ${event.port}` : peer,
        event.count > 1 ? `${event.count.toLocaleString()} times` : null,
        `rule ${event.sid}`,
    ].filter(Boolean).join(' · ');
    return h('div', { class: 'list-row' },
        status(isAllowed ? 'info' : blocked ? 'off' : 'check'),
        h('span', { class: 'grow' }, h('strong', { title: event.signature }, event.signature), h('small', {}, meta)),
        pill(isAllowed ? 'Allowed' : blocked ? 'Blocked' : 'Noticed', isAllowed ? '' : blocked ? 'off' : 'check', { small: true }),
        isAllowed ? null : allowButton(event));
}

function networkList(network) {
    const empty = (text) => h('div', { class: 'list card' }, h('p', { class: 'list-empty' }, text));
    if (!network) {
        return empty('Reading…');
    }
    // network.json names the sites this machine talked to, so it is wheel's to read
    if (!network.readable) {
        return empty('Only administrators can see what it blocked. ujust blocked-connections shows it after asking for your password.');
    }
    if (!network.events.length) {
        return empty('Nothing blocked or noticed yet.');
    }
    return h('div', { class: 'list card' }, network.events.slice(0, 50).map((event) => networkRow(event, network.allowed)));
}

function networkPage() {
    const mode = networkMode();
    const network = state.network;
    const check = state.report?.checks.find((item) => item.id === 'network');
    // Something wrong with it comes with its own way into the manual
    const attention = check && needsAttention(check);
    return h('div', { class: 'page' },
        h('header', { class: 'page-head' },
            h('h1', {}, 'Network protection'),
            h('p', { class: 'lead' }, NETWORK_LEADS[mode] || NETWORK_LEADS.off)),
        state.notice ? h('p', { class: 'notice', role: 'alert' }, state.notice) : null,
        networkStrip(mode, network),
        mode === 'off'
            ? callout('info', 'Start by watching',
                'Watching blocks nothing, and a week of it shows what blocking would get in the way of. Whatever goes wrong with network protection, connections go on uninspected rather than stop.',
                h('div', { class: 'actions' },
                    button('Turn it on…', () => window.security.run('network-protection'), { icon: 'terminal', primary: true })))
            : null,
        attention ? attentionCard({ check }) : null,
        section('Blocked and noticed', networkList(network), network?.events.length ? 'Allowing a rule asks for your password' : null),
        h('div', { class: 'actions' },
            mode === 'off' ? null : button('Change…', () => window.security.run('network-protection'), { icon: 'terminal' }),
            attention ? null : linkButton('Network protection in the manual', () => window.security.manual('security#network-protection'), { icon: 'book' })));
}

// --- Talking to main.js ---------------------------------------------------------------------------------

async function begin(request) {
    state.notice = '';
    const outcome = await request();
    if (!outcome || outcome.canceled) {
        return;
    }
    if (outcome.error) {
        state.notice = outcome.error;
        show('scan');
        return;
    }
    state.running = outcome.progress;
    show('scanning');
}

let machineTimer = null;

// The whole-machine scan is systemd's, so the page asks after it rather than being told
function watchMachine() {
    clearTimeout(machineTimer);
    machineTimer = setTimeout(async () => {
        const wasRunning = state.scanner?.machine.running;
        state.scanner = await window.security.scanner();
        if (state.scanner.machine.running) {
            renderNav();
            watchMachine();
            return;
        }
        if (wasRunning) {
            state.report = await window.security.report();
            if (state.page === 'scanning' && !state.running) {
                show('result', { machine: true });
                return;
            }
        }
        render();
    }, 3000);
}

async function scanMachine() {
    state.notice = '';
    const outcome = await window.security.scanMachine();
    if (outcome.error) {
        state.notice = outcome.error;
        show('scan');
        return;
    }
    state.machineAsked = Date.now();
    state.scanner = await window.security.scanner();
    // systemctl --no-block returns before systemd has started the unit
    state.scanner.machine.running = true;
    show('scanning');
    watchMachine();
}

let reloading = null;

function reload() {
    if (!reloading) {
        reloading = Promise.all([window.security.report(), window.security.scanner(), window.security.history(),
            window.security.network()])
            .then(([report, scanner, history, network]) => {
                Object.assign(state, { report, scanner, history: history.entries, home: history.home, network });
                if (history.running) {
                    state.running = history.running;
                }
                if (scanner.machine.running) {
                    watchMachine();
                }
                render();
            })
            .finally(() => {
                reloading = null;
            });
    }
    return reloading;
}

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

window.security.onPalette(applyPalette);
window.security.onProgress((progress) => {
    state.running = progress;
    if (state.page === 'scanning' && live.files) {
        updateLive();
    } else {
        renderNav();
    }
});
window.security.onFinished((entry) => {
    state.running = null;
    state.history = [entry, ...state.history.filter((item) => item.id !== entry.id)].slice(0, 20);
    if (state.page === 'scanning') {
        show('result', { entry });
    } else {
        render();
    }
});
window.security.onOpen((page) => {
    state.notice = '';
    show(page === 'scan' || page === 'network' ? page : 'overview');
});
// Back from a terminal where something may have been fixed
window.security.onFocus(() => {
    if (state.report && Date.now() - state.report.checked > 15000) {
        reload();
    }
});

setInterval(() => {
    if (live.elapsed && live.since) {
        live.elapsed.textContent = elapsed(live.since);
    }
}, 1000);

for (const node of navButtons) {
    node.addEventListener('click', () => {
        state.notice = '';
        show(node.dataset.page);
    });
}
document.getElementById('open-manual').addEventListener('click', () => window.security.manual('security'));

// A file or folder dropped anywhere on the window is scanned
let dragDepth = 0;
document.addEventListener('dragenter', (event) => {
    if (event.dataTransfer?.types.includes('Files')) {
        dragDepth += 1;
        document.body.classList.add('dropping');
    }
});
document.addEventListener('dragleave', () => {
    dragDepth = Math.max(0, dragDepth - 1);
    if (!dragDepth) {
        document.body.classList.remove('dropping');
    }
});
document.addEventListener('dragover', (event) => {
    if (event.dataTransfer?.types.includes('Files')) {
        event.preventDefault();
    }
});
document.addEventListener('drop', (event) => {
    event.preventDefault();
    dragDepth = 0;
    document.body.classList.remove('dropping');
    const files = [...(event.dataTransfer?.files || [])];
    if (files.length) {
        begin(() => window.security.scanFiles(files));
    }
});

document.addEventListener('keydown', (event) => {
    if ((event.ctrlKey && event.key === 'r') || event.key === 'F5') {
        event.preventDefault();
        reload();
    } else if (event.ctrlKey && (event.key === '=' || event.key === '+')) {
        window.security.zoom(0.5);
    } else if (event.ctrlKey && event.key === '-') {
        window.security.zoom(-0.5);
    } else if (event.ctrlKey && event.key === '0') {
        window.security.zoom(0);
    }
});

async function start() {
    applyPalette(await window.security.palette());
    state.page = location.hash === '#scan' || location.hash === '#network' ? location.hash.slice(1) : 'overview';
    render();
    await reload();
}

start();
