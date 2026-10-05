'use strict';

// The page of Amethystora Updates. What it shows comes from main.js: the deployments the machine lists,
// uupd.timer, and the update being followed through uupd's own log. Everything is built as elements with
// text in them and never as markup: the log is whatever the updater and the commands it ran printed.

// The session's language (i18n.js): every sentence below is the English, looked up in its catalog
const t = I18N.use(window.updates.locale);
t.page(document);

const view = document.getElementById('view');

const state = {
    // { machine, automatic, recent, update } from main.js
    status: null,
    // The update being followed, or the last one to end while the window was open
    update: null,
    // "Update now" was pressed and the update has not been seen yet
    starting: false,
    // Why the last thing asked for did not happen
    notice: '',
    // Automatic updates are being switched, and GNOME is asking for the password
    switching: false,
    // "Keep this version" is waiting for the password, and then has been done
    keeping: false,
    kept: false,
    // The updater's log is open
    details: false,
    // LVFS is being asked again for firmware
    checkingFirmware: false,
    // When the status was last read
    loaded: 0,
};

// The parts of the page that change while an update runs
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

function button(label, onclick, { icon: name, small, primary, disabled } = {}) {
    const classes = ['btn', small && 'small', primary && 'primary'].filter(Boolean).join(' ');
    return h('button', { type: 'button', class: classes, disabled: Boolean(disabled), onclick },
        name ? icon(name, 16) : null, h('span', {}, label));
}

function linkButton(label, onclick, { icon: name } = {}) {
    return h('button', { type: 'button', class: 'link small', onclick }, name ? icon(name, 15) : null, h('span', {}, label));
}

function copyButton(text) {
    const caption = h('span', {}, t('Copy'));
    return h('button', {
        type: 'button',
        class: 'btn small',
        'aria-label': t('Copy the command'),
        onclick: () => {
            window.updates.copy(text);
            caption.textContent = t('Copied');
            setTimeout(() => {
                caption.textContent = t('Copy');
            }, 1500);
        },
    }, icon('copy', 14), caption);
}

function section(title, ...body) {
    return h('section', { class: 'section' }, h('h2', {}, title), body);
}

function callout(tone, title, text, ...extra) {
    return h('div', { class: `callout ${tone}` },
        icon(tone === 'check' ? 'alert' : 'info', 20),
        h('div', { class: 'grow' }, h('strong', {}, title), text ? h('p', {}, text) : null, extra));
}

function commandBlock(lead, command) {
    return h('div', { class: 'command-wrap' },
        h('p', { class: 'soft small' }, lead),
        h('div', { class: 'command' }, h('code', {}, command), copyButton(command)));
}

// --- Words ---------------------------------------------------------------------------------------------

function time(ms) {
    return new Date(ms).toLocaleTimeString(t.locale, { hour: '2-digit', minute: '2-digit' });
}

// When something happened, or will: "today at 18:00", "tomorrow at 00:00", "Sat 26 Sep at 12:00"
function when(ms) {
    const date = new Date(ms);
    const midnight = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    const days = Math.round((midnight(date) - midnight(new Date())) / 86400000);
    const day = Math.abs(days) <= 1 ? t.days(days) : date.toLocaleDateString(t.locale, { weekday: 'short', day: 'numeric', month: 'short' });
    return t('{day} at {time}', { day, time: time(ms) });
}

function day(ms) {
    return new Date(ms).toLocaleDateString(t.locale, { day: 'numeric', month: 'long', year: 'numeric' });
}

// ghcr.io/iarsslen/amethystora-dx:stable -> { name: "amethystora-dx", tag: "stable" }
function imageParts(image) {
    const match = /^(?:.*\/)?([^/:@]+)(?::([^/@]+))?/.exec(image || '');
    return { name: match?.[1] || '', tag: match?.[2] || '' };
}

// A tag that names one build, such as stable-44.20260922, rather than a stream
function heldOn(image) {
    const { tag } = imageParts(image);
    return /^(?:[a-z-]+-)?\d+\.\d{8}/.test(tag) ? tag : '';
}

// --- The steps -----------------------------------------------------------------------------------------

// uupd's modules, by the title it gives them, in the order it runs them: what each row says, what it is
// in a sentence of its own, and the sentence for it while it runs
const STEPS = {
    System: {
        icon: 'layers',
        title: t('The system'),
        text: t('Amethystora itself. The new version is set up next to the one running and takes over at the next restart.'),
        what: t('the system'),
        doing: t('Updating the system'),
    },
    Brew: {
        icon: 'terminal',
        title: t('Command-line tools'),
        text: t('What you installed with Homebrew.'),
        what: t('the command-line tools'),
        doing: t('Updating the command-line tools'),
    },
    Flatpak: {
        icon: 'apps',
        title: t('Apps'),
        text: t('Flatpak apps, the whole machine’s and those of everyone signed in.'),
        what: t('the apps'),
        doing: t('Updating the apps'),
    },
    Distrobox: {
        icon: 'box',
        title: t('Containers'),
        text: t('What you installed from other distributions with amepkg. Upgraded by themselves every day, and after Update now.'),
        what: t('the containers'),
        doing: t('Upgrading the containers'),
    },
};

// What bootc is doing, as uupd names it: the step's own words, and the page's sentence for it
const SYSTEM_PHASES = {
    Bootc: [t('Starting'), t('Looking for a new version of the system')],
    Downloading: [t('Downloading'), t('Downloading the new system')],
    Importing: [t('Unpacking'), t('Unpacking the new system')],
    Deploying: [t('Setting up'), t('Setting up the new system')],
    Loading: [t('Finishing'), t('Finishing the new system')],
};

// The step's own words for what it is doing, and the sentence the page says it in
function stepActivity(name, step) {
    if (name === 'System') {
        const [phase, sentence] = SYSTEM_PHASES[step.detail] || [t('Updating'), STEPS.System.doing];
        if (Number.isFinite(step.percent) && step.percent > 0) {
            const percent = t.number(Math.round(step.percent) / 100, { style: 'percent' });
            return [t('{phase} · {percent}', { phase, percent }), sentence];
        }
        return [phase, sentence];
    }
    if (name === 'Flatpak') {
        const user = /^Apps for User: (.+)$/.exec(step.detail || '');
        return user
            ? [t('Apps of {user}', { user: user[1] }), t('Updating the apps of {user}', { user: user[1] })]
            : [t('The machine’s apps'), t('Updating the machine’s apps')];
    }
    if (name === 'Distrobox') {
        return [step.detail || t('Starting'), STEPS.Distrobox.doing];
    }
    return [t('Updating'), STEPS[name]?.doing || t('Updating {name}', { name })];
}

// The words and colour of a step's state
function stepState(name, step, update) {
    const ended = update.state !== 'running';
    switch (step.state) {
        case 'running':
            return [stepActivity(name, step)[0], 'accent', true];
        case 'done':
            return name === 'System' && state.status?.machine?.next ? [t('Ready for the restart'), 'ok'] : [t('Done'), 'ok'];
        case 'current':
            return [t('Already the newest'), 'ok'];
        case 'failed':
            return [t('Did not finish'), 'off'];
        default:
            if (!ended) {
                return [t('Waiting'), ''];
            }
            // uupd leaves out the system when there is no new version, and says so only in its debug log
            return name === 'System' && update.state === 'done' ? [t('Already the newest'), 'ok'] : [t('Not run'), ''];
    }
}

// A step's state, set on the row in place: the spinner keeps turning while the words change. Without
// the journal there is nothing to say about any one step, and the rows only say what they update. The
// containers' own log is the account's, so their step always has something to say once it has begun.
function setStep(name, step, update) {
    const nodes = live.stepNodes[name];
    const known = update?.journal || (name === 'Distrobox' && update?.containers);
    const [label, tone, spinning] = known ? stepState(name, step, update) : [];
    nodes.badge.hidden = !label;
    nodes.badge.setAttribute('class', `state ${tone || ''}`.trim());
    nodes.label.textContent = label || '';
    nodes.spinner.style.display = spinning ? '' : 'none';
    nodes.icon.setAttribute('class', `row-icon tone ${tone === 'off' ? 'off' : 'accent'}`);
}

// What the Containers row adds to what it updates: which did not upgrade, or when they last did
function containersDetail(update) {
    const failed = update?.containers?.failed || [];
    if (failed.length) {
        return t('Did not upgrade: {containers}. What they said is in the log: {command}',
            { containers: t.list(failed), command: 'journalctl --user -u amethystora-pkg-upgrade' });
    }
    const upgraded = state.status?.containers?.upgraded;
    return upgraded && !update?.containers ? t('Last upgraded {when}', { when: when(upgraded) }) : '';
}

function stepRow(name, step, update) {
    const about = STEPS[name] || { icon: 'box', title: name, text: '' };
    const nodes = {
        icon: h('span', {}, icon(about.icon, 20)),
        spinner: icon('spinner', 15, 'spin'),
        label: h('span', {}),
    };
    nodes.badge = h('span', {}, nodes.spinner, nodes.label);
    live.stepNodes[name] = nodes;
    setStep(name, step, update);
    const extra = name === 'Distrobox' ? containersDetail(update) : '';
    return h('div', { class: 'row' },
        nodes.icon,
        h('div', { class: 'row-text grow' },
            h('span', { class: 'row-title' }, about.title),
            h('span', { class: 'row-detail' }, about.text),
            extra ? h('span', { class: 'row-detail' }, extra) : null),
        nodes.badge);
}

function stepsCard() {
    const update = state.update;
    const idle = { System: {}, Brew: {}, Flatpak: {} };
    if (state.status?.containers?.count) {
        idle.Distrobox = {};
    }
    const steps = update?.steps || idle;
    live.stepNodes = {};
    return h('div', { class: 'card list' }, Object.entries(steps).map(([name, step]) => stepRow(name, step, update)));
}

// What is happening right now, in a few words
function activity(update) {
    if (!update) {
        return t('Starting the update…');
    }
    const current = Object.entries(update.steps).find(([, step]) => step.state === 'running');
    return current ? stepActivity(...current)[1] : t('Looking for new versions…');
}

function runningTitle(update) {
    if (update?.automatic) {
        return t('Updating by itself');
    }
    return update?.retry ? t('Trying again') : t('Updating');
}

// --- The hero ------------------------------------------------------------------------------------------

function heroKind() {
    const update = state.update;
    if (state.starting || update?.state === 'running') {
        return 'running';
    }
    if (update?.state === 'failed') {
        return 'failed';
    }
    if (state.status?.machine?.latest) {
        return 'previous';
    }
    if (state.status?.machine?.next) {
        return 'ready';
    }
    if (update?.state === 'done') {
        return 'done';
    }
    return 'idle';
}

// The stone of the boot splash, lit, with a band of light passing down it while something happens
function gem(active) {
    return h('div', { class: `gem${active ? ' active' : ''}`, 'aria-hidden': 'true' },
        h('img', { src: 'gem.svg', alt: '' }),
        active ? h('div', { class: 'sweep' }) : null);
}

function hero(kind) {
    const update = state.update;
    const status = state.status || {};
    const next = status.machine?.next;
    const recent = status.recent;
    const auto = status.automatic;
    let title;
    let lead;
    // Each ends in a time, which can end in "p.m.": joined with dots between them rather than after
    const notes = [];
    const actions = [];

    switch (kind) {
        case 'running': {
            live.title = h('h1', {});
            live.lead = h('p', { class: 'lead' });
            live.fill = h('div', {});
            live.percent = h('span', { class: 'percent' });
            live.bar = h('div', { class: 'bar' }, live.fill);
            updateLive();
            return h('div', { class: 'hero' },
                gem(true),
                live.title,
                live.lead,
                h('div', { class: 'progress' }, live.bar, live.percent),
                h('p', { class: 'note' }, t('You can keep working, or close this window: the update carries on without it.')));
        }
        case 'failed': {
            const steps = Object.entries(update.steps);
            const failed = steps
                .filter(([, step]) => step.state === 'failed')
                .map(([name]) => STEPS[name]?.what || name);
            const finished = steps.some(([, step]) => step.state === 'done' || step.state === 'current');
            title = failed.length && finished ? t('Some updates did not finish') : t('The update did not finish');
            if (failed.length) {
                const stopped = t('Updating {steps} stopped with an error.', { steps: t.list(failed) });
                lead = finished ? `${stopped} ${t('Everything else is up to date.')}` : stopped;
            } else {
                lead = update.errors[0] || t('The updater stopped before it got to the end.');
            }
            if (update.retrying) {
                notes.push(t('It tries again by itself in a minute'));
            }
            actions.push(button(t('Try again'), updateNow, { icon: 'refresh', primary: true }));
            if (next) {
                actions.push(button(t('Restart now'), restart, { icon: 'power' }));
            }
            actions.push(askAgent());
            break;
        }
        case 'previous': {
            const { running, latest } = status.machine;
            title = t('You’re on the previous version');
            lead = [
                running.built
                    ? t('This machine started Amethystora {version}, built {date}, from the boot menu.', { version: running.version || '', date: day(running.built) })
                    : t('This machine started Amethystora {version} from the boot menu.', { version: running.version || '' }),
                latest.built
                    ? t('The newest, built {date}, is still the one it starts by default.', { date: day(latest.built) })
                    : t('The newest is still the one it starts by default.'),
                t('Keep this one while the newest has a problem you are waiting to see fixed.'),
            ].join(' ');
            notes.push(t('Keeping it asks for your password'));
            actions.push(button(t('Keep this version'), keep, { icon: 'back', primary: true, disabled: state.keeping }));
            actions.push(button(t('Restart into the latest'), restart, { icon: 'power' }));
            actions.push(linkButton(t('Rolling back in the manual'), () => window.updates.manual('updates#rolling-back'), { icon: 'book' }));
            break;
        }
        case 'ready':
            title = t('Restart to finish');
            lead = t('Amethystora {version} is ready next to the system you are running. It takes over when you restart, all at once, and your files and settings stay as they are.', { version: next.version || '' });
            notes.push(t('No hurry: shutting down at the end of the day does it too'));
            actions.push(button(t('Restart now'), restart, { icon: 'power', primary: true }));
            actions.push(button(t('Check again'), updateNow, { icon: 'refresh' }));
            break;
        case 'done':
            title = t('Everything is up to date');
            lead = t('The system, your apps and your command-line tools are the newest there are.');
            notes.push(t('Checked {when}', { when: when(update.finished) }));
            actions.push(button(t('Check again'), updateNow, { icon: 'refresh' }));
            break;
        default:
            if (recent && recent.result !== 'success') {
                title = t('The last update did not finish');
                lead = t('It stopped {when}. Try again; if it fails again, this window shows where.', { when: when(recent.finished) });
                actions.push(button(t('Try again'), updateNow, { icon: 'refresh', primary: true }), askAgent());
            } else {
                title = t('Updates come by themselves');
                lead = t('The system, your apps and your command-line tools are updated in the background while you work. Update now to have anything new straight away.');
                actions.push(button(t('Update now'), updateNow, { icon: 'download', primary: true }));
            }
            if (recent?.result === 'success') {
                notes.push(t('Last updated {when}', { when: when(recent.finished) }));
            }
            if (auto?.enabled && auto.next) {
                notes.push(t('Next automatic update {when}', { when: when(auto.next) }));
            } else if (auto && !auto.enabled) {
                notes.push(t('Automatic updates are off'));
            }
    }
    return h('div', { class: 'hero' },
        gem(false),
        h('h1', {}, title),
        h('p', { class: 'lead' }, lead),
        h('div', { class: 'actions' }, actions),
        notes.length ? h('p', { class: 'note' }, notes.join('  ·  ')) : null);
}

// The running hero, updated in place so that the stone's light is not restarted with every line
function updateLive() {
    const update = state.update;
    if (!live.lead) {
        return;
    }
    live.title.textContent = runningTitle(update);
    live.lead.textContent = activity(update);
    const overall = update?.journal && Number.isFinite(update.overall) ? Math.max(2, Math.min(100, update.overall)) : null;
    live.bar.classList.toggle('indeterminate', overall === null);
    live.fill.style.width = overall === null ? '' : `${overall}%`;
    live.percent.textContent = overall === null ? '' : t.number(Math.round(overall) / 100, { style: 'percent' });
    if (live.steps && update) {
        const names = Object.keys(update.steps);
        if (names.some((name) => !live.stepNodes[name])) {
            // A module the page did not know of has started, such as Distrobox
            const steps = stepsCard();
            live.steps.replaceWith(steps);
            live.steps = steps;
        } else {
            for (const name of names) {
                setStep(name, update.steps[name], update);
            }
        }
    }
    if (live.log) {
        fillLog(live.log);
    }
}

// --- This machine and automatic updates ----------------------------------------------------------------

function versionRow(label, deployment, extra) {
    return h('div', { class: 'row' },
        h('div', { class: 'row-text grow' },
            h('span', { class: 'row-label' }, label),
            h('span', { class: 'row-title' }, `Amethystora ${deployment.version || ''}`.trim()),
            h('span', { class: 'row-detail' },
                [deployment.built ? t('Built {date}', { date: day(deployment.built) }) : '', deployment.image].filter(Boolean).join(' · ')),
            extra));
}

function machineSection() {
    const info = state.status?.machine;
    if (!info) {
        return section(t('This machine'), h('div', { class: 'card list' },
            h('div', { class: 'row soft' }, t('This machine did not say which system it runs.'))));
    }
    const held = heldOn(info.running.image);
    return section(t('This machine'),
        held ? callout('check', t('This machine is held on one build'),
            t('It runs {build} and receives no new system until it follows a stream again. Apps and command-line tools still update.', { build: held }),
            linkButton(t('Following a stream again'), () => window.updates.manual('updates#holding-on-to-one-build'), { icon: 'book' })) : null,
        h('div', { class: 'card list' },
            versionRow(info.latest ? t('Running now, from the boot menu') : t('Running now'), info.running),
            info.latest ? versionRow(t('The newest, started by default'), info.latest) : null,
            info.next ? versionRow(t('After the next restart'), info.next) : null,
            info.previous ? versionRow(t('Kept to go back to'), info.previous,
                linkButton(t('Going back to it'), () => window.updates.manual('updates#rolling-back'), { icon: 'back' })) : null));
}

// Makes the running version the default, after an administrator's password. What it means for the
// updates to come is said straight after: the next one brings the newest back.
async function keep() {
    state.keeping = true;
    state.notice = '';
    render();
    const result = await window.updates.keep();
    state.keeping = false;
    if (result.machine) {
        state.status.machine = result.machine;
    }
    if (result.kept) {
        state.kept = true;
    } else if (!result.declined) {
        state.notice = result.error || '';
    }
    render();
}

async function setAutomatic(on) {
    state.switching = true;
    state.notice = '';
    render();
    const result = await window.updates.automatic(on);
    state.switching = false;
    state.status.automatic = result.automatic;
    state.notice = result.error || '';
    render();
}

function automaticSection() {
    const auto = state.status?.automatic;
    if (!auto) {
        return null;
    }
    const detail = auto.enabled
        ? t('New versions download in the background, and a new system waits for the next restart.')
        : t('Nothing is updated unless you update it here, or with ame update in a terminal.');
    return section(t('Automatic updates'), h('div', { class: 'card list' },
        h('div', { class: 'row' },
            h('span', { class: `row-icon tone ${auto.enabled ? 'ok' : 'info'}` }, icon('clock', 20)),
            h('div', { class: 'row-text grow' },
                h('span', { class: 'row-title' }, auto.enabled ? t('On') : t('Off')),
                h('span', { class: 'row-detail' }, detail),
                auto.enabled && auto.next ? h('span', { class: 'row-detail' }, t('Next {when}', { when: when(auto.next) })) : null),
            h('div', { class: 'row-side' },
                button(auto.enabled ? t('Turn off') : t('Turn on'), () => setAutomatic(!auto.enabled),
                    { small: true, disabled: state.switching }),
                h('span', { class: 'faint small' }, t('Asks for your password'))))));
}

// --- Firmware ------------------------------------------------------------------------------------------

// LVFS's own words for an update that fixes something serious
const URGENT = new Set(['high', 'critical']);

async function checkFirmware() {
    state.checkingFirmware = true;
    render();
    const result = await window.updates.refreshFirmware();
    state.checkingFirmware = false;
    state.status.firmware = result;
    render();
}

function firmwareRow(device) {
    const versions = device.current && device.next
        ? t('From {current} to {next}', { current: device.current, next: device.next })
        : device.next;
    return h('div', { class: 'row' },
        h('span', { class: `row-icon tone ${URGENT.has(device.urgency) ? 'off' : 'accent'}` }, icon('chip', 20)),
        h('div', { class: 'row-text grow' },
            h('span', { class: 'row-title' }, device.name),
            h('span', { class: 'row-detail' }, [device.vendor, versions].filter(Boolean).join(' · ')),
            device.summary ? h('span', { class: 'row-detail' }, device.summary) : null,
            device.restart ? h('span', { class: 'row-detail' }, t('Written by the firmware itself at the next restart')) : null),
        URGENT.has(device.urgency) ? h('span', { class: 'state off' }, h('span', {}, t('Important'))) : null);
}

// The devices whose makers published new firmware on LVFS. Installing it is fwupdmgr's, in a terminal.
function firmwareSection() {
    const chips = state.status?.firmware;
    if (!chips) {
        return null;
    }
    const devices = chips.devices || [];
    const rows = devices.length
        ? devices.map(firmwareRow)
        : [h('div', { class: 'row soft' }, chips.error || t('No firmware updates. fwupd looks for them every day on LVFS, where the makers of this machine and its devices publish them.'))];
    return section(t('Firmware'),
        h('div', { class: 'card list' }, rows),
        h('div', { class: 'actions' },
            devices.length ? button(t('Update firmware…'), () => window.updates.updateFirmware(), { icon: 'terminal', primary: true }) : null,
            button(state.checkingFirmware ? t('Checking…') : t('Check now'), checkFirmware, { icon: 'refresh', small: true, disabled: state.checkingFirmware }),
            linkButton(t('Firmware in the manual'), () => window.updates.manual('updates#firmware'), { icon: 'book' })));
}

// --- What the updater said -----------------------------------------------------------------------------

function fillLog(node) {
    const update = state.update;
    const lines = [...update.log];
    for (const failure of update.failures) {
        if (failure.output) {
            lines.push('', `${failure.context}:`, failure.output);
        }
    }
    const atEnd = node.scrollHeight - node.scrollTop - node.clientHeight < 24;
    node.textContent = lines.join('\n');
    if (atEnd) {
        node.scrollTop = node.scrollHeight;
    }
}

function detailsSection() {
    const update = state.update;
    if (!update) {
        return null;
    }
    const command = `journalctl -eu ${update.unit}`;
    if (!update.journal) {
        return update.state === 'running' ? null : section(t('Details'),
            commandBlock(t('What the updater said is in the system journal, which this account cannot read. An administrator sees it with:'), `sudo ${command}`));
    }
    live.log = h('pre', { class: 'log', dir: 'ltr' });
    fillLog(live.log);
    const details = h('details', { class: 'card details', open: state.details },
        h('summary', {}, icon('chevron', 16, 'chevron'), h('span', {}, t('What the updater said'))),
        live.log,
        h('div', { class: 'details-foot' }, commandBlock(t('All of it, in a terminal:'), command)));
    details.addEventListener('toggle', () => {
        state.details = details.open;
        if (details.open) {
            live.log.scrollTop = live.log.scrollHeight;
        }
    });
    return details;
}

// --- The page ------------------------------------------------------------------------------------------

function render() {
    for (const key of Object.keys(live)) {
        delete live[key];
    }
    if (!state.status) {
        view.replaceChildren(h('div', { class: 'loading' }, icon('spinner', 28, 'spin')));
        return;
    }
    const kind = heroKind();
    live.kind = kind;
    const top = hero(kind);
    live.steps = stepsCard();
    view.replaceChildren(h('div', { class: 'page' },
        top,
        state.notice ? callout('check', t('That did not work'), state.notice) : null,
        state.kept ? callout('info', t('This version is the one the machine starts now'),
            t('The next update brings the newest back, automatic or not. To stay on this one until a fix is out, turn automatic updates off below, or hold the machine on this build.'),
            linkButton(t('Holding on to one build'), () => window.updates.manual('updates#holding-on-to-one-build'), { icon: 'book' })) : null,
        section(kind === 'running' || state.update ? t('This update') : t('What gets updated'), live.steps),
        detailsSection(),
        machineSection(),
        firmwareSection(),
        automaticSection(),
        h('p', { class: 'terminal' }, t.parts('Also in a terminal: {command}', { command: h('code', {}, 'ame update') }))));
}

async function reload() {
    state.loaded = Date.now();
    state.status = await window.updates.status();
    state.update = state.status.update || state.update;
    render();
}

async function updateNow() {
    state.notice = '';
    state.starting = true;
    render();
    const result = await window.updates.update();
    if (result.error) {
        state.starting = false;
        state.notice = result.error;
        render();
    }
}

function restart() {
    window.updates.restart();
}

// The failed update, handed to the AI agent in a terminal: it reads the updater's log itself and
// changes nothing until asked. Nothing at all while the account has the agentic features off.
function askAgent() {
    return state.status?.agent ? linkButton(t('Ask the agent why'), () => window.updates.diagnose(), { icon: 'sparkle' }) : null;
}

function luminance(hex) {
    const [r, g, b] = [1, 3, 5]
        .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
        .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// The same palette mapping as the Manual's and Security's
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

window.updates.onPalette(applyPalette);
window.updates.onUpdate((update) => {
    state.update = update;
    state.starting = false;
    // Drawn whole only when the page changes shape: the first of the log, or the update ending
    if (state.status && live.kind === 'running' && heroKind() === 'running' && (live.log || !update?.journal)) {
        updateLive();
    } else {
        render();
    }
});
// An update ended, or one that was started never ran: everything is read again
window.updates.onStatus((status) => {
    state.status = status;
    state.update = status.update || state.update;
    state.starting = false;
    render();
});
// Back from elsewhere, where the machine may have been updated or restarted into a new version
window.updates.onFocus(() => {
    if (heroKind() !== 'running' && !state.switching && Date.now() - (state.loaded || 0) > 15000) {
        reload();
    }
});

document.getElementById('open-releases').addEventListener('click', () => window.updates.releases());
document.getElementById('open-manual').addEventListener('click', () => window.updates.manual('updates'));

document.addEventListener('keydown', (event) => {
    if ((event.ctrlKey && event.key === 'r') || event.key === 'F5') {
        event.preventDefault();
        reload();
    } else if (event.ctrlKey && (event.key === '=' || event.key === '+')) {
        window.updates.zoom(0.5);
    } else if (event.ctrlKey && event.key === '-') {
        window.updates.zoom(-0.5);
    } else if (event.ctrlKey && event.key === '0') {
        window.updates.zoom(0);
    }
});

async function start() {
    applyPalette(await window.updates.palette());
    render();
    await reload();
}

start();
