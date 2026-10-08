'use strict';

// The page of Amethystora Security. The report is /usr/libexec/amethystora-security-status --json, the one
// `ame security status` prints, the scans are the ones main.js runs, and network protection is what the
// security watcher kept of Suricata's alerts. Everything shown is built as elements with text in them
// and never as markup: a file name is whatever somebody called a file, and a rule's name and a host
// name are whatever the network sent.
//
// The report's own words, each check's title, text and details, and what amethystora-app-permissions
// says each app can reach, are in the session's language already, as those scripts write them: they are
// shown as they come, and never looked up in the catalog below.

// The session's language (i18n.js): every sentence below is the English, looked up in its catalog
const t = I18N.use(window.security.locale);
t.page(document);

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
    // The containers amethystora-pkg manages, as `amethystora-pkg containers list --json` lists them
    inventory: null,
    // What each Flatpak can reach beyond its sandbox, as amethystora-app-permissions says
    permissions: null,
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
            caption.textContent = t('Copied');
            setTimeout(() => {
                caption.textContent = label;
            }, 1500);
        },
    }, icon('copy', 14), caption);
}

// A mono pill holds a name such as a signature's, which reads left to right in any language
function pill(label, tone = '', { small, mono } = {}) {
    return h('span', { class: ['pill', tone, small && 'small', mono && 'mono'].filter(Boolean).join(' '), dir: mono ? 'ltr' : null }, label);
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
        h('div', { class: 'command' }, h('code', { dir: 'ltr' }, command), copyButton(command, t('Copy'), t('Copy the command'))));
}

// Facts about one thing on one line, with dots between them: text, or text and elements as t.parts gives
// them, such as a name kept apart from the words around it
function dotted(...pieces) {
    return pieces.filter(Boolean).flatMap((piece, index) => (index ? [' · ', piece] : [piece]));
}

// --- Words ---------------------------------------------------------------------------------------------

function time(ms) {
    return new Date(ms).toLocaleTimeString(t.locale, { hour: '2-digit', minute: '2-digit' });
}

function midnight(ms) {
    const date = new Date(ms);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

// Days from today to a moment: 0 today, -1 yesterday
function daysFrom(ms) {
    return Math.round((midnight(ms) - midnight(Date.now())) / 86400000);
}

function shortDay(ms) {
    return new Date(ms).toLocaleDateString(t.locale, { weekday: 'short', day: 'numeric', month: 'short' });
}

// When something happened, in a sentence: "today at 18:00", "yesterday at 09:30", "Sat 26 Sep at 12:00"
function when(ms) {
    const days = daysFrom(ms);
    return t('{day} at {time}', { day: Math.abs(days) <= 1 ? t.days(days) : shortDay(ms), time: time(ms) });
}

// ...and at the start of a line, where it begins with a capital
function whenFirst(ms) {
    const day = { 0: 'today', '-1': 'yesterday' }[daysFrom(ms)] || 'other';
    return t('{day, select, today {Today at {time}} yesterday {Yesterday at {time}} other {{date} at {time}}}',
        { day, date: shortDay(ms), time: time(ms) });
}

// "today", "yesterday", "12 days ago", for a count of whole days back, which a clock set back can make
// less than none
function daysAgo(days) {
    const back = Math.max(0, days || 0);
    return t.days(back ? -back : 0);
}

// How long a scan took: "42 s", "5 min", "1 h 20 min"
function took(seconds) {
    if (seconds < 60) {
        return t('{seconds} s', { seconds });
    }
    const minutes = Math.round(seconds / 60);
    return minutes < 60
        ? t('{minutes} min', { minutes })
        : t('{hours} h {minutes} min', { hours: Math.floor(minutes / 60), minutes: minutes % 60 });
}

// How long a scan has run, as a clock shows it, in the language's digits: "2:05", "1:02:05"
function clock(seconds) {
    const pad = (n) => t.number(n, { minimumIntegerDigits: 2 });
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor(seconds / 60) % 60;
    return hours ? `${t.number(hours)}:${pad(minutes)}:${pad(seconds % 60)}` : `${t.number(minutes)}:${pad(seconds % 60)}`;
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
        return t('None yet');
    }
    if (signatures.stale) {
        return t('{days, plural, one {# day old} other {# days old}}', { days: signatures.days });
    }
    return t('Updated {when}', { when: daysAgo(signatures.days) });
}

// ...as the note under a running scan says it
function signaturesNote(signatures) {
    if (!signatures) {
        return t('No signatures yet');
    }
    if (signatures.stale) {
        return t('{days, plural, one {Signatures # day old} other {Signatures # days old}}', { days: signatures.days });
    }
    return t('Signatures updated {when}', { when: daysAgo(signatures.days) });
}

// What a scan is of, as the values its sentences choose their words by (labelFor in main.js): { place:
// 'home' }, { place: 'items', items }, or { place: 'named', name }, the name kept apart from the words
// around it, whichever way its letters run. Made afresh for each sentence: an element is only ever in
// one place.
function scope(scan) {
    const label = scan.label || {};
    return { place: label.place, items: label.items, name: h('bdi', {}, label.name || '') };
}

// What a scan is of, as a list of them names it
function scanName(scan) {
    return t.parts('{place, select, home {Your home folder} items {{items, plural, one {# item} other {# items}}} other {{name}}}', scope(scan));
}

// ...and while it runs
function scanningTitle(scan) {
    return t.parts('{place, select, home {Scanning your home folder} items {Scanning {items, plural, one {# item} other {# items}}} other {Scanning {name}}}', scope(scan));
}

// --- The report ----------------------------------------------------------------------------------------

const GROUPS = [['updates', t('Updates and boot')], ['watching', t('Watching')], ['apps', t('Apps')], ['scans', t('Scans')]];
const TILE_ICONS = {
    'security-key': 'key',
    fingerprint: 'fingerprint',
    'ssh-codes': 'terminal',
    backups: 'archive',
    'ransomware-protection': 'history',
    'disk-unlock': 'chip',
    'usb-protection': 'plug',
    'browser-protection': 'monitor',
    'key-remapping': 'keyboard',
    'on-detection': 'file-alert',
    realtime: 'activity',
    'network-protection': 'globe',
    'encrypted-dns': 'lock',
    'network-address': 'wifi',
};

// What this machine does with what a scan finds (ON_DETECTION), as the report read it
function detection() {
    return state.report?.settings?.on_detection || 'report';
}

// What was done with what a scan found, as a heading: the weekly scan's paragraph says the same in
// sentences of its own (attentionCard)
const DETECTION_DONE = {
    report: t('Nothing was deleted, quarantined or moved'),
    quarantine: t('What it found was moved to quarantine'),
    delete: t('What it found was deleted'),
};

const SCAN_LEADS = {
    report: t('What it finds is reported, and never deleted, quarantined or moved.'),
    quarantine: t('What it finds is moved to quarantine, which asks for your password.'),
    delete: t('What it finds is deleted, which asks for your password.'),
};

// What was done to one file a scan started here found
const OUTCOMES = {
    quarantined: [t('Quarantined'), ''],
    deleted: [t('Deleted'), ''],
    declined: [t('Left in place'), 'check'],
    failed: [t('Could not be moved'), 'check'],
    clean: [t('Clean on a second look'), 'ok'],
};

// ...and to all of them, in a few words
function entryDone(entry) {
    const outcomes = new Set(entry.found.map((item) => item.outcome).filter((outcome) => outcome && outcome !== 'reported'));
    if (!outcomes.size) {
        return DETECTION_DONE.report;
    }
    if (outcomes.size === 1 && outcomes.has('quarantined')) {
        return t('Moved to quarantine');
    }
    if (outcomes.size === 1 && outcomes.has('deleted')) {
        return t('Deleted');
    }
    if (outcomes.size === 1 && outcomes.has('declined')) {
        return t('Left where it is, without the password');
    }
    return t('Each file below says what was done with it');
}

// ...and what to know about that
function doneNote(entry) {
    const has = (outcome) => entry.found.some((item) => item.outcome === outcome);
    if (has('quarantined')) {
        return t('Quarantined files are kept where nothing can open them. {list} shows them, and {restore} puts one back.',
            { list: 'ame security scan', restore: 'ame security scan restore' });
    }
    if (has('deleted')) {
        return t('A deleted file can only come back from a backup.');
    }
    return t('A match can be a false positive, so check where the file came from first. If you did not mean to have it, delete it in Files, then scan again.');
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
    'backup-runs': 'security#backups',
    containers: 'software#packages-from-other-distributions',
    'app-permissions': 'security#app-permissions',
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
const NAV = {
    overview: 'overview', scan: 'scan', scanning: 'scan', result: 'scan', network: 'network', apps: 'apps', containers: 'containers',
};
const RECIPES = {
    overview: 'ame security status',
    scan: 'ame security scan',
    network: 'ame security connections',
    apps: 'ame security apps',
    containers: 'amepkg containers list',
};

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
            setBadge(badge, items.length ? t.number(items.length) : '', items.some((item) => item.tone === 'off') ? 'off' : 'check');
        } else if (page === 'network') {
            setBadge(badge, blocked ? t.number(blocked) : '', 'off');
        } else if (page === 'containers') {
            const behind = (state.inventory?.containers || []).filter(stale).length;
            setBadge(badge, behind ? t.number(behind) : '', 'check');
        } else if (page === 'apps') {
            const leaving = (state.permissions?.apps || []).filter(leaves).length;
            setBadge(badge, leaving ? t.number(leaving) : '', 'off');
        } else if (busy) {
            setBadge(badge, icon('spinner', 12, 'spin'), 'busy');
        } else {
            setBadge(badge, findings ? t.number(findings) : '', 'off');
        }
    }
}

const PAGES = {
    overview: () => overviewPage(),
    scan: () => scanPage(),
    scanning: () => scanningPage(),
    result: () => resultPage(),
    network: () => networkPage(),
    apps: () => appsPage(),
    containers: () => containersPage(),
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
        return h('div', { class: 'loading' }, t('Checking this machine…'));
    }
    const items = attentionItems();
    const on = report.checks.filter((check) => check.group !== 'optional' && check.state === 'ok').length;
    let tone = items.some((item) => item.tone === 'off') ? 'off' : items.length ? 'check' : 'ok';
    let headline = t('Everything is on');
    let summary = t('{count, plural, one {# check is on, and nothing needs you right now.} other {All # checks are on, and nothing needs you right now.}}', { count: on });
    if (items.length) {
        headline = t('{count, plural, =1 {One thing to look at} other {# things to look at}}', { count: items.length });
        summary = on ? t('{count, plural, =1 {The other check is on.} other {The other # checks are all on.}}', { count: on }) : '';
    }
    if (report.error) {
        [tone, headline, summary] = ['check', t('The report could not be read'), report.error];
    }
    return h('div', { class: 'page' },
        hero(headline, summary, tone, items.length),
        items.length ? section(t('Needs your attention'), h('div', { class: 'stack' }, items.map(attentionCard))) : null,
        groupsSection(items.length > 0),
        optionalSection());
}

function hero(headline, summary, tone, count) {
    const again = button(t('Check again'), async () => {
        again.disabled = true;
        again.querySelector('span').textContent = t('Checking…');
        await reload();
    }, { icon: 'refresh' });
    return h('section', { class: 'hero', 'aria-labelledby': 'headline' },
        h('div', { class: 'emblem' },
            document.getElementById('shield-art').content.cloneNode(true),
            h('span', { class: `emblem-badge ${tone}` }, count ? t.number(count) : icon(tone === 'ok' ? 'mark-ok' : 'mark-alert', 14))),
        h('div', { class: 'hero-text' },
            // The image's name reads left to right in any language
            h('div', { class: 'mono soft small', dir: 'ltr' }, state.report.image),
            h('h1', { id: 'headline' }, headline),
            summary ? h('p', { class: 'lead' }, summary) : null),
        h('div', { class: 'hero-side' },
            again,
            h('span', { class: 'faint small' }, t('Checked at {time}', { time: time(state.report.checked) }))));
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
                    pill(check.state === 'off' ? t('Off') : t('Check'), check.state), h('h3', {}, check.text)),
                lines.map((line) => h('p', { class: 'soft' }, line)),
                weekly
                    ? h('p', { class: 'soft' }, t('{detection, select, quarantine {What it found was moved to quarantine.} delete {What it found was deleted.} other {Nothing was deleted, quarantined or moved.}} What it found is in a log only an administrator can read, so seeing it asks for your password.',
                        { detection: detection() }))
                    : null),
            check.command && !weekly ? commandBlock(lead, check.command) : null,
            h('div', { class: 'actions' },
                check.command
                    ? button(weekly ? t('See what it found') : t('Run in a terminal'), () => window.security.run(check.id),
                        { icon: weekly ? 'arrow-right' : 'terminal', after: weekly })
                    : null,
                linkButton(t('{check} in the manual', { check: check.title }), () => window.security.manual(manualPage(check.id)), { icon: 'book' }),
                // The AI agent looks into it in a terminal and changes nothing until asked; not offered at
                // all while the account has the agentic features off
                state.report?.agent
                    ? linkButton(t('Ask the agent'), () => window.security.diagnose(check.id), { icon: 'sparkle' })
                    : null)));
}

function findingTitle(entry) {
    return entry.single
        ? t.parts('{name} matches known malware', scope(entry))
        : t.parts('{place, select, home {A scan of your home folder found {found, plural, one {# file} other {# files}}} items {A scan of {items, plural, one {# item} other {# items}} found {found, plural, one {# file} other {# files}}} other {A scan of {name} found {found, plural, one {# file} other {# files}}}}',
            { ...scope(entry), found: entry.found.length });
}

function findingCard(entry) {
    const first = entry.found[0];
    return h('article', { class: 'attention off' },
        h('div', { class: 'attention-icon tone off' }, icon('file-alert', 22)),
        h('div', { class: 'attention-body' },
            h('div', { class: 'attention-head' },
                h('div', { class: 'attention-title' }, pill(t('Found'), 'off'), h('h3', {}, findingTitle(entry))),
                // A signature's name reads left to right in any language
                h('p', { class: 'soft' },
                    dotted(whenFirst(entry.started), first?.signature ? h('bdi', { dir: 'ltr' }, first.signature) : null, entryDone(entry))))),
        h('div', { class: 'attention-side' },
            button(t('See what it found'), () => show('result', { entry }), { icon: 'arrow-right', after: true }),
            linkButton(t('Dismiss'), async () => {
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
            check.command ? linkButton(t('Run it now'), () => window.security.run(check.id), { small: true }) : null));
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
            h('div', { class: 'group-head' }, h('h3', {}, title), on ? pill(t('{count} on', { count: on }), 'ok', { small: true }) : null),
            rows.map(checkRow));
    }).filter(Boolean);
    if (!cards.length) {
        return null;
    }
    const allOn = GROUPS.every(([group]) => rowsOf(group).every((check) => check.state === 'ok'));
    const title = attention ? (allOn ? t('Everything else is on') : t('Everything else')) : t('What is on');
    return section(title, h('div', { class: 'groups' }, cards));
}

function optionalSection() {
    const optional = checks('optional');
    if (!optional.length) {
        return null;
    }
    const tiles = optional.map((check) => {
        const unavailable = check.state === 'unavailable';
        const stateText = unavailable ? check.details[0] || t('Not available here') : check.state === 'on' ? t('On') : t('Off');
        return h('div', { class: 'tile card' },
            h('div', { class: 'tile-icon tone accent' }, icon(TILE_ICONS[check.id] || 'shield', 20)),
            h('div', { class: 'tile-text' }, h('h3', {}, check.title), h('p', {}, check.text)),
            h('div', { class: 'tile-foot' },
                h('span', { class: `tile-state ${check.state}` }, stateText),
                button(check.state === 'on' ? t('Change…') : t('Set up…'), () => window.security.run(check.id),
                    { small: true, disabled: unavailable })));
    });
    tiles.push(h('button', { type: 'button', class: 'tile manual-tile', onclick: () => window.security.manual('security') },
        h('span', { class: 'tile-text' },
            h('span', { class: 'tile-title' }, t('What each one does')),
            h('span', { class: 'tile-note' }, t('And how to undo it, in the Security page of the manual.'))),
        h('span', { class: 'link' }, icon('book', 16), h('span', {}, t('Open the manual')))));
    return section(t('Off unless you turn it on'), h('div', { class: 'tiles' }, tiles), t('Setting one up opens it in a terminal'));
}

// --- Virus scan ----------------------------------------------------------------------------------------

function scanPage() {
    const scanner = state.scanner;
    const busy = Boolean(state.running || scanner?.machine.running);
    const blocked = !scanner?.signatures || busy;
    return h('div', { class: 'page' },
        h('header', { class: 'page-head' },
            h('h1', {}, t('Virus scan')),
            h('p', { class: 'lead' }, `${t('ClamAV compares your files with known malware.')} ${SCAN_LEADS[detection()]}`)),
        state.notice ? h('p', { class: 'notice', role: 'alert' }, state.notice) : null,
        busy
            ? h('div', { class: 'banner' },
                icon('spinner', 18, 'spin'),
                h('span', { class: 'grow' }, state.running ? scanningTitle(state.running) : t('Scanning the whole machine')),
                linkButton(t('Show it'), () => show('scanning')))
            : null,
        scanStrip(scanner),
        section(t('Scan'), h('div', { class: 'choices' },
            choice({ main: true, icon: 'home', title: t('Your home folder'), text: t('Everything you keep here, apart from caches.') },
                button(t('Scan now'), () => begin(() => window.security.scanHome()), { primary: true, disabled: blocked })),
            choice({ icon: 'folder', title: t('A file or folder'), text: t('Choose some, or drop them anywhere on this window.') },
                button(t('Files…'), () => begin(() => window.security.scanPick(false)), { disabled: blocked }),
                button(t('Folders…'), () => begin(() => window.security.scanPick(true)), { disabled: blocked })),
            choice({ icon: 'monitor', title: t('The whole machine'), text: t('All home and temporary folders, like the weekly scan.') },
                button(t('Scan'), scanMachine, { disabled: blocked })))),
        section(t('Recent scans'), recentList()));
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
        return h('div', { class: 'strip card' }, h('div', {}, h('span', { class: 'soft' }, t('Checking the scanner…'))));
    }
    const { machine, signatures } = scanner;
    let weekly = ['accent', t('Sundays, not run yet')];
    if (machine.running) {
        weekly = ['accent', t('Running now')];
    } else if (machine.found) {
        weekly = ['off', t('Last one found something')];
    } else if (machine.status === 2 || machine.status > 3) {
        weekly = ['check', t('Last one could not run')];
    } else if (machine.finished) {
        weekly = ['ok', t('Last one found nothing')];
    }
    return h('div', { class: 'strip card' },
        stripCell(signatures && !signatures.stale ? 'ok' : 'check', 'database', t('Signatures'), signaturesText(signatures)),
        stripCell(weekly[0], 'calendar', t('Weekly scan'), weekly[1]),
        stripCell(signatures ? 'ok' : 'check', 'activity', t('Scanner'), signatures ? t('Ready') : t('Waiting for signatures')));
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
        : h('div', { class: 'list card' }, h('p', { class: 'list-empty' }, t('No scans yet.')));
}

function entryOutcome(entry) {
    switch (entry.status) {
        case 'found':
            return ['off', pill(entry.found.length ? t('{count} found', { count: entry.found.length }) : t('Found'), 'off')];
        case 'clean':
            return ['ok', pill(t('Nothing found'), 'ok')];
        case 'failed':
            return ['check', pill(t('Could not run'), 'check')];
        default:
            return ['info', pill(t('Stopped'))];
    }
}

function entryRow(entry) {
    const [tone, outcome] = entryOutcome(entry);
    const meta = [
        whenFirst(entry.started),
        t('took {duration}', { duration: took(entry.seconds) }),
        entry.files ? t('{count, plural, one {# file} other {# files}}', { count: entry.files }) : null,
    ].filter(Boolean).join(' · ');
    return h('button', { type: 'button', class: 'list-row', onclick: () => show('result', { entry }) },
        status(tone),
        h('span', { class: 'grow' }, h('strong', {}, scanName(entry)), h('small', {}, meta)),
        outcome,
        icon('chevron', 16, 'chevron'));
}

function machineOutcome(machine) {
    if (machine.running) {
        return ['info', pill(t('Running'))];
    }
    if (machine.found) {
        return ['off', pill(t('Found something'), 'off')];
    }
    if (machine.status === 2 || machine.status > 3) {
        return ['check', pill(t('Could not run'), 'check')];
    }
    if (!machine.finished) {
        return ['info', pill(t('Not run yet'))];
    }
    if (machine.status === 3) {
        return ['check', pill(t('Old signatures'), 'check')];
    }
    return ['ok', pill(t('Nothing found'), 'ok')];
}

function machineRow(machine) {
    const [tone, outcome] = machineOutcome(machine);
    let meta = t('Weekly, on Sundays');
    if (machine.running) {
        meta = t('Every home and temporary folder · running now');
    } else if (machine.finished) {
        meta = t('Weekly, on Sundays · last {when}', { when: when(machine.finished) });
    }
    return h('button', {
        type: 'button',
        class: 'list-row',
        onclick: () => (machine.running ? show('scanning') : show('result', { machine: true })),
    },
    status(tone),
    h('span', { class: 'grow' }, h('strong', {}, t('The whole machine')), h('small', {}, meta)),
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
    live.files.textContent = t.number(progress.files);
    live.found.textContent = t.number(progress.found);
    live.found.classList.toggle('off', progress.found > 0);
    // A path reads left to right in any language, and the words before there is one the language's way
    const file = !progress.loading && progress.current;
    live.path.dir = file ? 'ltr' : 'auto';
    live.path.textContent = file
        ? tilde(progress.current)
        : progress.loading ? t('Loading the virus signatures…') : t('Starting…');
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
        stats.push(stat(live.files, t('Files checked')), stat(live.found, t('Found')));
    }
    stats.push(stat(live.elapsed, t('Elapsed')));
    const page = h('div', { class: 'scanning' },
        h('div', { class: 'gem', 'aria-hidden': 'true' }, h('img', { src: 'gem.svg', alt: '' }), h('div', { class: 'sweep' })),
        h('h1', {}, progress ? scanningTitle(progress) : t('Scanning the whole machine')),
        h('p', { class: 'lead' }, progress
            ? t('You can keep working meanwhile. Nothing is deleted or moved.')
            : t('Every home and temporary folder, at low priority so that it stays out of your way. It carries on if you close this window, and nothing is deleted or moved.')),
        h('div', { class: 'stats card' }, stats),
        h('div', { class: 'current' },
            progress ? h('div', { class: 'current-path' }, icon('file', 15), live.path) : null,
            h('div', { class: 'bar', role: 'progressbar', 'aria-label': t('Scanning') }, h('div'))),
        progress
            ? button(t('Stop the scan'), () => window.security.stop(), { icon: 'stop' })
            : button(t('Back to Virus scan'), () => show('scan')),
        h('p', { class: 'footnote' }, [signaturesNote(state.scanner?.signatures), t('caches are skipped')].join(' · ')));
    updateLive();
    return page;
}

// --- Results -------------------------------------------------------------------------------------------

function back() {
    return h('div', {}, linkButton(t('Virus scan'), () => show('scan'), { icon: 'arrow-left', quiet: true }));
}

function resultHead(tone, name, title, subtitle) {
    return h('header', { class: 'result-head' },
        h('div', { class: `result-icon tone ${tone}` }, icon(name, 28)),
        h('div', { class: 'grow' }, h('h1', {}, title), subtitle ? h('p', { class: 'lead' }, subtitle) : null));
}

// A path, the one value that is mono, reads left to right in any language
function fact(label, value, mono = false) {
    return h('div', {}, h('div', { class: 'grow' },
        h('span', { class: 'label' }, label), h('span', { class: `value${mono ? ' mono' : ''}`, dir: mono ? 'ltr' : null }, value)));
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
            h('code', { dir: 'ltr' }, tilde(item.path))),
        h('div', { class: 'actions' },
            moved ? null : button(t('Show in Files'), () => window.security.showInFiles(item.path), { icon: 'folder', small: true }),
            copyButton(item.path, t('Copy path'), t('Copy the path of the file'))));
}

function scanResult(entry) {
    const found = entry.found.length;
    const one = entry.targets.length === 1;
    const titles = {
        found: !found
            ? t.parts('{place, select, home {The scan of your home folder found something} items {The scan of {items, plural, one {# item} other {# items}} found something} other {The scan of {name} found something}}', scope(entry))
            : entry.single
                ? t.parts('{name} matches known malware', scope(entry))
                : t.parts('{place, select, home {Found {found, plural, one {# file} other {# files}} in your home folder} items {Found {found, plural, one {# file} other {# files}} in {items, plural, one {# item} other {# items}}} other {Found {found, plural, one {# file} other {# files}} in {name}}}',
                    { ...scope(entry), found }),
        clean: t.parts('{place, select, home {No known malware in your home folder} items {No known malware in {items, plural, one {# item} other {# items}}} other {No known malware in {name}}}', scope(entry)),
        stopped: t.parts('{place, select, home {The scan of your home folder was stopped} items {The scan of {items, plural, one {# item} other {# items}} was stopped} other {The scan of {name} was stopped}}', scope(entry)),
        failed: t.parts('{place, select, home {The scan of your home folder could not run} items {The scan of {items, plural, one {# item} other {# items}} could not run} other {The scan of {name} could not run}}', scope(entry)),
    };
    const tones = { found: 'off', clean: 'ok', stopped: 'info', failed: 'check' };
    const icons = { found: 'file-alert', clean: 'mark-ok', stopped: 'stop', failed: 'alert' };
    // Joined rather than full-stopped: a time can end in "p.m." already
    const subtitle = [
        t('Scanned {when}', { when: when(entry.started) }),
        entry.status === 'found' && found && !entry.single
            ? t('{count, plural, =1 {One file matches known malware} other {# files match known malware}}', { count: found }) : null,
        entry.stopped ? t('{count, plural, one {Stopped after # file} other {Stopped after # files}}', { count: entry.files }) : null,
    ].filter(Boolean).join(' · ');
    const parts = [
        back(),
        resultHead(tones[entry.status] || 'info', icons[entry.status] || 'info', titles[entry.status] || scanName(entry), subtitle),
        h('div', { class: 'strip card' },
            fact(one ? (entry.single ? t('File') : t('Folder')) : t('Scanned'),
                one ? tilde(entry.targets[0]) : t('{count, plural, one {# item} other {# items}}', { count: entry.targets.length }), one),
            fact(t('Files checked'), t.number(entry.files)),
            fact(t('Time'), took(entry.seconds)),
            fact(t('Signatures'), signaturesText(entry.signatures))),
    ];
    if (entry.status === 'found') {
        parts.push(callout('info', entryDone(entry), doneNote(entry)));
    }
    if (entry.status === 'failed') {
        parts.push(callout('check', t('The scanner could not start'), entry.message));
    }
    if (entry.errors) {
        parts.push(h('p', { class: 'soft' },
            t('{count, plural, one {# file could not be read, and was not checked.} other {# files could not be read, and were not checked.}}', { count: entry.errors })));
    }
    if (found) {
        parts.push(section(t('What it found'), h('div', { class: 'stack' }, entry.found.map(findingRow))));
    }
    parts.push(h('div', { class: 'actions' },
        button(t('Scan again'), () => begin(() => window.security.scanAgain(entry.id)), { primary: true, disabled: Boolean(state.running) }),
        button(t('Done'), () => show('scan'))));
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
    const finished = machine.finished ? t('Finished {when}', { when: when(machine.finished) }) : '';
    let head = resultHead('ok', 'mark-ok', t('No known malware on this machine'), finished);
    let body = [];
    if (machine.found) {
        head = resultHead('off', 'file-alert', t('The scan of the whole machine found something'), finished);
        body = [callout('info', DETECTION_DONE[detection()],
            t('What it found is in a log only an administrator can read, so seeing it asks for your password.'),
            h('div', { class: 'actions' },
                button(t('See what it found'), () => window.security.run('virus-scan'), { icon: 'terminal' })))];
    } else if (!machine.finished) {
        head = resultHead('info', 'monitor', t('The whole machine has not been scanned yet'),
            t('The weekly scan runs on Sundays, or now if you start it.'));
    } else if (machine.status === 2) {
        head = resultHead('check', 'alert', t('There were no signatures to scan with'), finished);
        body = [callout('check', t('Nothing was scanned'),
            t('The signatures download on their own soon after the machine is installed. If that was a while ago, check its network.'))];
    } else if (machine.status > 3) {
        head = resultHead('check', 'alert', t('The scan of the whole machine could not run'), finished);
        body = [callout('check', t('Its log says why'), '', commandBlock('', 'journalctl -u amethystora-clamav-scan.service'))];
    } else if (machine.status === 3) {
        head = resultHead('check', 'alert', t('Nothing found, with old signatures'), finished);
        body = [callout('check', t('A clean result proves little'),
            t("The signatures are too old for a clean scan to mean much. Check this machine's network."))];
    }
    return h('div', { class: 'page' },
        back(),
        head,
        body,
        h('div', { class: 'actions' },
            button(t('Scan again'), scanMachine, { primary: true, disabled: Boolean(state.running) || !state.scanner.signatures }),
            button(t('Done'), () => show('scan'))));
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
    off: t('Suricata can inspect every connection this machine makes and receives, and cut off the ones to known malware, command servers and exploits. It is off.'),
    watch: t('Suricata inspects every connection this machine makes and receives, and says what it recognises. Nothing is blocked yet.'),
    block: t('Suricata inspects every connection this machine makes and receives, and cuts off the ones to known malware, command servers and exploits.'),
};

const NETWORK_MODES = { off: t('Off'), watch: t('Watching'), block: t('Blocking') };

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
        return t('None yet');
    }
    return t('Updated {when}', { when: daysAgo(Math.floor((Date.now() / 1000 - rules) / 86400)) });
}

function networkStrip(mode, network) {
    const on = mode !== 'off';
    const running = Boolean(network?.running);
    const stale = network?.rules && Date.now() / 1000 - network.rules > 7 * 86400;
    const week = blockedSince(Date.now() / 1000 - 7 * 86400);
    return h('div', { class: 'strip card' },
        stripCell(on ? 'ok' : 'info', 'shield', t('Mode'), NETWORK_MODES[mode] || mode),
        stripCell(!on ? 'info' : running ? 'ok' : 'check', 'activity', 'Suricata', on && running ? t('Running') : t('Not running')),
        stripCell(!on ? 'info' : network?.rules && !stale ? 'ok' : 'check', 'database', t('Rules'), rulesText(network?.rules)),
        stripCell('accent', 'globe', t('Blocked this week'), t.number(week)));
}

// Leaves the rule out on this machine, after an administrator's password. Declining it changes nothing.
function allowButton(event) {
    const node = button(t('Allow'), async () => {
        node.disabled = true;
        node.querySelector('span').textContent = t('Allowing…');
        const outcome = await window.security.allowRule(event.sid);
        state.notice = outcome.error || '';
        state.network = await window.security.network();
        render();
    }, { small: true, title: t('Leave rule {rule} out on this machine. Asks for your password.', { rule: String(event.sid) }) });
    return node;
}

function networkRow(event, allowed) {
    const blocked = event.action === 'blocked';
    const isAllowed = allowed.includes(event.sid);
    // A host's name runs whichever way its own letters do, and an address left to right
    const peer = event.host
        ? h('bdi', {}, event.host)
        : h('span', {}, t.parts('{source} and {destination}', {
            source: h('bdi', { dir: 'ltr' }, event.src),
            destination: h('bdi', { dir: 'ltr' }, event.dest),
        }));
    const meta = dotted(
        whenFirst(event.time * 1000),
        event.port ? t.parts('{host}, port {port}', { host: peer, port: String(event.port) }) : peer,
        event.count > 1 ? t('{count, plural, one {# time} other {# times}}', { count: event.count }) : null,
        t('rule {rule}', { rule: String(event.sid) }),
    );
    // A rule's name reads left to right in any language
    return h('div', { class: 'list-row' },
        status(isAllowed ? 'info' : blocked ? 'off' : 'check'),
        h('span', { class: 'grow' }, h('strong', { title: event.signature, dir: 'ltr' }, event.signature), h('small', {}, meta)),
        pill(isAllowed ? t('Allowed') : blocked ? t('Blocked') : t('Noticed'), isAllowed ? '' : blocked ? 'off' : 'check', { small: true }),
        isAllowed ? null : allowButton(event));
}

function networkList(network) {
    const empty = (text) => h('div', { class: 'list card' }, h('p', { class: 'list-empty' }, text));
    if (!network) {
        return empty(t('Reading…'));
    }
    // network.json names the sites this machine talked to, so it is wheel's to read
    if (!network.readable) {
        return empty(t('Only administrators can see what it blocked. {command} shows it after asking for your password.',
            { command: 'ame security connections' }));
    }
    if (!network.events.length) {
        return empty(t('Nothing blocked or noticed yet.'));
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
            h('h1', {}, t('Network protection')),
            h('p', { class: 'lead' }, NETWORK_LEADS[mode] || NETWORK_LEADS.off)),
        state.notice ? h('p', { class: 'notice', role: 'alert' }, state.notice) : null,
        networkStrip(mode, network),
        mode === 'off'
            ? callout('info', t('Start by watching'),
                t('Watching blocks nothing, and a week of it shows what blocking would get in the way of. Whatever goes wrong with network protection, connections go on uninspected rather than stop.'),
                h('div', { class: 'actions' },
                    button(t('Turn it on…'), () => window.security.run('network-protection'), { icon: 'terminal', primary: true })))
            : null,
        attention ? attentionCard({ check }) : null,
        section(t('Blocked and noticed'), networkList(network), network?.events.length ? t('Allowing a rule asks for your password') : null),
        h('div', { class: 'actions' },
            mode === 'off' ? null : button(t('Change…'), () => window.security.run('network-protection'), { icon: 'terminal' }),
            attention ? null : linkButton(t('Network protection in the manual'), () => window.security.manual('security#network-protection'), { icon: 'book' })));
}

// --- App permissions --------------------------------------------------------------------------------------

// What lets an app leave its sandbox altogether, and what lets it see what is typed into another app:
// the ids /usr/libexec/amethystora-app-permissions gives each reach, as the report sorts them too
const ESCAPES = new Set(['session-bus', 'system-bus', 'flatpak', 'systemd', 'autostart']);
const TYPING = new Set(['x11', 'input']);

function leaves(app) {
    return app.reaches.some((reach) => ESCAPES.has(reach.id));
}

function reachTone(id) {
    return ESCAPES.has(id) ? 'off' : TYPING.has(id) ? 'check' : 'info';
}

// The apps that can leave their sandbox first, then those that see typing, then the rest by name
function weight(app) {
    return leaves(app) ? 0 : app.reaches.some((reach) => TYPING.has(reach.id)) ? 1 : 2;
}

async function resetApp(app, node) {
    node.disabled = true;
    const outcome = await window.security.resetPermissions(app.app);
    state.notice = outcome.error || '';
    if (!outcome.error) {
        state.permissions = outcome;
    }
    render();
}

function appRow(app) {
    const tone = leaves(app) ? 'off' : app.reaches.some((reach) => TYPING.has(reach.id)) ? 'check' : 'info';
    const reset = app.user_overrides
        ? button(t('Take back what you granted'), (event) => resetApp(app, event.currentTarget), {
            small: true,
            title: t('Remove every permission this account granted this app, in Flatseal or with {command}', { command: 'flatpak override' }),
        })
        : null;
    return h('div', { class: 'list-row container-row' },
        status(tone),
        h('span', { class: 'grow' },
            h('strong', {}, app.name),
            h('small', { dir: 'ltr' }, app.app),
            app.reaches.map((reach) => h('small', { class: 'container-line' },
                h('span', { class: `reach ${reachTone(reach.id)}` }, reach.text),
                reach.granted ? pill(t('Granted here'), '', { small: true }) : null))),
        reset);
}

function appsPage() {
    const data = state.permissions;
    const apps = data?.apps || [];
    const reaching = apps.filter((app) => app.reaches.length)
        .sort((a, b) => weight(a) - weight(b) || a.name.localeCompare(b.name));
    const leaving = reaching.filter(leaves);
    const empty = (text) => h('div', { class: 'list card' }, h('p', { class: 'list-empty' }, text));
    let list;
    if (!data) {
        list = empty(t('Reading…'));
    } else if (data.error) {
        list = empty(data.error);
    } else if (!apps.length) {
        list = empty(t('No Flatpak apps are installed.'));
    } else if (!reaching.length) {
        list = empty(t('No app reaches anything beyond its sandbox without asking.'));
    } else {
        list = h('div', { class: 'list card' }, reaching.map(appRow));
    }
    return h('div', { class: 'page' },
        h('header', { class: 'page-head' },
            h('h1', {}, t('Apps')),
            h('p', { class: 'lead' },
                t('What each Flatpak app can reach beyond its sandbox without asking you: what it asked for itself, and what was granted on this machine. What an app asks for through a portal, such as a file you choose for it, is asked each time and is not listed.'))),
        state.notice ? h('p', { class: 'notice', role: 'alert' }, state.notice) : null,
        leaving.length
            ? callout('check',
                leaving.length === 1
                    ? t.parts('{name} can leave its sandbox', { name: h('bdi', {}, leaving[0].name) })
                    : t('{count, plural, one {# app can leave its sandbox} other {# apps can leave their sandbox}}', { count: leaving.length }),
                t('Whatever runs in it can do anything you can. If you did not mean it to, change it in Flatseal, or take back what you granted.'))
            : null,
        section(t('What apps can reach'), list, apps.length ? t('{count, plural, one {# app checked} other {# apps checked}}', { count: apps.length }) : null),
        h('div', { class: 'actions' },
            button(t('Change permissions in Flatseal'), () => window.security.flatseal(), { icon: 'arrow-right', after: true }),
            linkButton(t('App permissions in the manual'), () => window.security.manual('security#app-permissions'), { icon: 'book' })));
}

// --- Installed outside Flatpak ---------------------------------------------------------------------------

const DAY = 86400;

// A container left two weeks without an upgrade, as the report counts it (amethystora-security-status)
function stale(container) {
    const since = container.last_upgrade || container.created || 0;
    return Date.now() / 1000 - since >= 14 * DAY;
}

function upgradedText(container) {
    const since = container.last_upgrade;
    if (!since) {
        return t('never upgraded');
    }
    const when = daysAgo(Math.floor((Date.now() / 1000 - since) / DAY));
    return container.last_upgrade_result === 'failed'
        ? t('upgraded {when}, and the last try failed', { when })
        : t('upgraded {when}', { when });
}

// The app grid shows an exported app with the container it runs in after its name
function appName(app) {
    return app.name.replace(/ \(on [^)]*\)$/, '');
}

// The names of what is in a container, in a list the language's way: "vim, git, htop"
function names(list) {
    return t.list(list, 'unit');
}

function containerRow(container) {
    const tone = stale(container) || container.last_upgrade_result === 'failed' ? 'check' : 'ok';
    const lines = [];
    if (container.exported_apps.length) {
        lines.push(t('In the app grid: {apps}', { apps: names(container.exported_apps.map(appName)) }));
    }
    const fromAur = container.packages.filter((name) => container.aur_packages.includes(name));
    const byName = container.packages.filter((name) => !fromAur.includes(name));
    if (byName.length) {
        lines.push(t('Installed by name: {packages}', { packages: names(byName) }));
    }
    if (fromAur.length) {
        lines.push(container.aur_pending
            ? t('{count, plural, one {From the AUR: {packages}, # update waits for you to review} other {From the AUR: {packages}, # updates wait for you to review}}',
                { packages: names(fromAur), count: container.aur_pending })
            : t('From the AUR: {packages}', { packages: names(fromAur) }));
    }
    if (container.files.length) {
        lines.push(t('Installed from a file: {files}', { files: names(container.files.map((file) => file.name)) }));
    }
    if (container.exported_bins.length) {
        lines.push(t('Commands: {commands}', { commands: names(container.exported_bins.map(basename)) }));
    }
    return h('div', { class: 'list-row container-row' },
        status(tone),
        h('span', { class: 'grow' },
            h('strong', {}, container.name),
            h('small', {}, [t('From the template {template}', { template: container.template }), upgradedText(container),
                container.home ? t('a home folder of its own') : null].filter(Boolean).join(' · ')),
            lines.map((line) => h('small', { class: 'container-line' }, line))),
        pill(container.status === 'running' ? t('Running') : t('Stopped'), '', { small: true }));
}

function containersPage() {
    const inventory = state.inventory;
    const containers = inventory?.containers || [];
    const behind = containers.filter(stale);
    let list;
    if (!inventory) {
        list = h('div', { class: 'list card' }, h('p', { class: 'list-empty' }, t('Reading…')));
    } else if (!containers.length) {
        list = h('div', { class: 'list card' }, h('p', { class: 'list-empty' },
            inventory.error || t('None. Software from another distribution goes into a container with amepkg.')));
    } else {
        list = h('div', { class: 'list card' }, containers.map(containerRow));
    }
    return h('div', { class: 'page' },
        h('header', { class: 'page-head' },
            h('h1', {}, t('Containers')),
            h('p', { class: 'lead' },
                t('What is installed outside Flatpak: software from other distributions, each in a container amepkg made, upgraded every day. Containers are not a sandbox: what runs in one runs as you, with your home folder, your display, your sound and your session bus.'))),
        behind.length
            ? callout('check',
                behind.length === 1
                    ? t.parts('{name} has not been upgraded for two weeks', { name: h('bdi', {}, behind[0].name) })
                    : t('{count, plural, one {# container has not been upgraded for two weeks} other {# containers have not been upgraded for two weeks}}', { count: behind.length }),
                t('What runs in a container goes without the fixes its distribution has published since.'))
            : null,
        inventory?.aur
            ? callout('info', t('The AUR is on'),
                t('Packages from it are built from scripts nobody reviews, and are never upgraded unattended: each waits for you to read what changed. {command} turns it off.',
                    { command: 'ame apps aur' }))
            : null,
        section(t('Installed outside Flatpak'), list),
        h('div', { class: 'actions' },
            containers.length ? button(t('Upgrade them now'), () => window.security.upgradeContainers(), { icon: 'terminal', primary: Boolean(behind.length) }) : null,
            linkButton(t('Containers in the manual'), () => window.security.manual('software#packages-from-other-distributions'), { icon: 'book' })));
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
            window.security.network(), window.security.inventory(), window.security.permissions()])
            .then(([report, scanner, history, network, inventory, permissions]) => {
                Object.assign(state, { report, scanner, history: history.entries, home: history.home, network, inventory, permissions });
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
    show(['scan', 'network', 'apps', 'containers'].includes(page) ? page : 'overview');
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
    state.page = ['#scan', '#network', '#apps', '#containers'].includes(location.hash) ? location.hash.slice(1) : 'overview';
    render();
    await reload();
}

start();
