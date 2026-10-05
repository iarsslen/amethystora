'use strict';

// The page of Amethystora Control. What it shows is the list main.js reads from
// /usr/libexec/amethystora-control-list: every entry, its words, its state and its choices. A change sends
// back the entry's id and the value of a choice the list gave, and main.js runs the command the list has
// for it. An entry's words are the script's, already in the session's language through gettext, and are
// shown as they come; only the page's own words are looked up in its catalog. Everything is built as
// elements with text in them, never as markup.

// The session's language (i18n.js): every sentence below is the English, looked up in its catalog
const t = I18N.use(window.control.locale);
t.page(document);

const view = document.getElementById('view');
const searchInput = document.getElementById('search');
const pageButtons = [...document.querySelectorAll('.nav [data-page]')];
const updatesState = document.getElementById('updates-state');
const backupsButton = document.getElementById('open-backups');

// The pages of the sidebar, in its order, with what each is called and says about itself
const PAGES = {
    appearance: { title: t('Appearance'), lead: t('The theme, the wallpaper, and how a new one is revealed.') },
    desktop: { title: t('Desktop'), lead: t('How windows are arranged, the top bar and the terminal.') },
    apps: {
        title: t('Apps'),
        lead: t('Games, Android apps, drawing tablets and web apps, and what else installs with one command.'),
    },
    agent: { title: t('The AI agent'), lead: t('An AI agent that knows this system, and which one opens.') },
    system: {
        title: t('System'),
        lead: t('The image this machine runs and the stream it follows, the CPU scheduler, and the firmware.'),
    },
    setup: { title: t('Your setup'), lead: t('Your setup as a file, to keep, to compare, and to apply here or on another machine.') },
};

// The areas of a setup file's differences (ame setup diff), by the names the script gives them
const AREAS = {
    image: t('System image'),
    flatpak: t('App'),
    tap: t('Homebrew tap'),
    formula: t('Homebrew formula'),
    cask: t('Homebrew cask'),
    container: t('Container'),
    packages: t('Packages in a container'),
    extension: t('Extension'),
    theme: t('Theme'),
    layout: t('Window layout'),
    favorites: t("The dock's apps"),
    keybinding: t('Keybinding'),
    gap: t("PaperWM's gaps"),
};

// The rule amethystora-widgets has for a widget's name, and the one amethystora-trust-image has for a
// repository: main.js checks both again, this only says so before anything is sent
const WIDGET_ID = /^[a-z0-9][a-z0-9-]*$/;
const REPOSITORY = new RegExp(String.raw`^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(\.[a-z0-9-]+|:[0-9]+)(/[a-z0-9]+(([._]|__|-+)[a-z0-9]+)*)+$`);

const state = {
    page: 'appearance',
    // The list from main.js: {version, sealed, elsewhere, items}
    list: null,
    error: '',
    search: '',
    // The entries whose command runs now, and what the last one run here said, by id
    busy: new Set(),
    said: new Map(),
    // {tone, text} at the top of the page, after a command opened a terminal or could not run
    banner: null,
    // What `ame setup diff` said: {changes} or {error}, or 'reading'
    diff: null,
    // The trust card's own fields: the repository typed, the name of the key file chosen, and the
    // repository a trust was started for, whose next steps it then shows
    repository: '',
    key: '',
    trusted: '',
    // The new widget's fields
    widgetName: '',
    widgetExample: '',
    // When the list was last read, and whether it is being read now
    read: 0,
    reading: false,
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

// A button that asks once more before it does what it says, for what cannot be put back by clicking again
function confirmButton(label, ask, onconfirm, { icon: name, disabled } = {}) {
    let armed = false;
    let timer = null;
    const caption = h('span', {}, label);
    const node = h('button', {
        type: 'button',
        class: 'btn small',
        disabled: Boolean(disabled),
        onclick: () => {
            if (armed) {
                clearTimeout(timer);
                onconfirm();
                return;
            }
            armed = true;
            node.classList.add('danger');
            caption.textContent = ask;
            timer = setTimeout(() => {
                armed = false;
                node.classList.remove('danger');
                caption.textContent = label;
            }, 4000);
        },
    }, name ? icon(name, 15) : null, caption);
    return node;
}

// A button that says it copied, for a moment
function copyButton(text) {
    const caption = h('span', {}, t('Copy'));
    return h('button', {
        type: 'button',
        class: 'btn small',
        onclick: () => {
            window.control.copy(text);
            caption.textContent = t('Copied');
            setTimeout(() => {
                caption.textContent = t('Copy');
            }, 1500);
        },
    }, icon('copy', 15), caption);
}

function commandBlock(command) {
    return h('div', { class: 'command' }, h('code', { dir: 'ltr' }, command), copyButton(command));
}

function callout(tone, title, text, ...extra) {
    return h('div', { class: `callout ${tone}` },
        icon(tone === 'check' ? 'alert' : 'info', 18),
        h('div', { class: 'grow' }, title ? h('strong', {}, title) : null, text ? h('p', {}, text) : null, extra));
}

// The spinning mark of something running, in a button's place
function spinner() {
    return h('span', { class: 'icon-btn', role: 'status', 'aria-label': t('Running') }, icon('spinner', 18, 'spin'));
}

// --- Running what the list says --------------------------------------------------------------------

// A change, an action or a widget's command, sent to main.js. A command that opened a terminal is said
// at the top of the page; one run here shows what it said under its card, and the list is read again.
async function perform(id, call) {
    if (state.busy.has(id)) {
        return;
    }
    state.busy.add(id);
    state.said.delete(id);
    state.banner = null;
    render();
    let result;
    try {
        result = await call();
    } catch (error) {
        result = { error: error.message };
    }
    state.busy.delete(id);
    if (result?.terminal) {
        state.banner = {
            tone: 'terminal',
            text: t('It opened in a terminal. This page reads the settings again when you come back to it.'),
        };
        render();
        return;
    }
    if (result?.error) {
        state.said.set(id, { ok: false, output: result.error });
        render();
        return;
    }
    if (result && (result.output || !result.ok)) {
        state.said.set(id, { ok: result.ok, output: result.output });
    }
    await load({ quiet: true });
}

// --- One entry ---------------------------------------------------------------------------------------

// Whether the next click on a switch, the one away from its state, opens a terminal
function nextOpensTerminal(item) {
    const next = item.choices?.find((choice) => choice.value !== item.state);
    return Boolean(next?.terminal);
}

function terminalTag() {
    return h('span', { class: 'tag', title: t('Opens in a terminal, where it asks before it changes anything') },
        icon('terminal', 13), t('Terminal'));
}

// What the last command run from this card said
function saidBox(item) {
    const said = state.said.get(item.id);
    if (!said) {
        return null;
    }
    return h('div', { class: `said${said.ok ? '' : ' failed'}`, role: said.ok ? 'status' : 'alert' },
        h('div', { class: 'said-head' },
            icon(said.ok ? 'check' : 'alert', 15),
            h('span', { class: 'grow' }, said.ok ? t('Done') : t('That did not work')),
            h('button', {
                type: 'button',
                class: 'icon-btn',
                'aria-label': t('Dismiss'),
                onclick: () => {
                    state.said.delete(item.id);
                    render();
                },
            }, icon('close', 15))),
        said.output ? h('pre', { dir: 'ltr' }, said.output) : null);
}

// A card: the entry's words and state, its control at the inline end, whatever it shows below them, and
// where it is in the manual and in a terminal
function frame(item, control, below = [], { danger = false, tags = [] } = {}) {
    const classes = ['setting', 'card', !item.available && 'unavailable', danger && 'danger'].filter(Boolean).join(' ');
    // A link's own button is its way to the manual
    const manual = item.manual && item.kind !== 'link';
    return h('section', { class: classes, 'data-id': item.id, 'aria-label': item.title },
        h('div', { class: 'setting-head' },
            h('div', { class: 'setting-words' },
                h('div', { class: 'setting-title' }, h('h3', {}, item.title), tags),
                item.text ? h('p', { class: 'setting-text' }, item.text) : null,
                !item.available && item.reason ? h('p', { class: 'setting-detail check' }, item.reason) : null,
                item.detail ? h('p', { class: 'setting-detail' }, item.detail) : null),
            state.busy.has(item.id) ? spinner() : control),
        below,
        saidBox(item),
        manual || item.usage
            ? h('div', { class: 'setting-foot' },
                manual ? linkButton(t('In the manual'), () => window.control.manual(item.manual), 'book') : null,
                item.usage ? h('span', {}, t('In a terminal:'), ' ', h('code', { dir: 'ltr' }, item.usage)) : null)
            : null);
}

function switchCard(item) {
    const busy = state.busy.has(item.id) || !item.available;
    let control;
    if (item.state === 'on' || item.state === 'off') {
        const on = item.state === 'on';
        control = h('button', {
            type: 'button',
            class: 'switch',
            role: 'switch',
            'aria-checked': String(on),
            'aria-label': item.title,
            disabled: busy,
            onclick: () => perform(item.id, () => window.control.change(item.id, on ? 'off' : 'on')),
        });
    } else {
        // A state only an administrator can see: both ways, each in a terminal
        control = h('div', { class: 'actions' },
            button(t('Turn on…'), () => perform(item.id, () => window.control.change(item.id, 'on')), { small: true, disabled: busy }),
            button(t('Turn off…'), () => perform(item.id, () => window.control.change(item.id, 'off')), { small: true, disabled: busy }));
    }
    return frame(item, control, [], { tags: item.available && nextOpensTerminal(item) ? [terminalTag()] : [] });
}

function choiceCard(item) {
    const disabled = state.busy.has(item.id) || !item.available;
    const options = h('div', { class: 'options', role: 'radiogroup', 'aria-label': item.title },
        (item.choices || []).map((choice) => {
            const chosen = choice.value === item.state;
            return h('button', {
                type: 'button',
                class: 'option',
                role: 'radio',
                'aria-checked': String(chosen),
                disabled,
                onclick: () => {
                    if (!chosen) {
                        perform(item.id, () => window.control.change(item.id, choice.value));
                    }
                },
            },
            h('span', { class: 'dot', 'aria-hidden': 'true' }),
            h('span', { class: 'option-words' },
                h('strong', {}, choice.title),
                choice.text ? h('small', {}, choice.text) : null),
            choice.terminal && !chosen ? icon('terminal', 15, 'faint') : null);
        }));
    return frame(item, null, [options]);
}

// Milliseconds as seconds, the language's way: "1.2 s"
function seconds(ms) {
    return t.number(ms / 1000, { style: 'unit', unit: 'second', unitDisplay: 'short', maximumFractionDigits: 1 });
}

function rangeCard(item) {
    const value = Number(item.state) || item.min;
    const output = h('output', {}, item.unit === 'ms' ? seconds(value) : t.number(value));
    const input = h('input', {
        type: 'range',
        min: item.min,
        max: item.max,
        step: item.step || 1,
        value,
        'aria-label': item.title,
        disabled: state.busy.has(item.id) || !item.available,
        oninput: (event) => {
            const number = Number(event.target.value);
            output.textContent = item.unit === 'ms' ? seconds(number) : t.number(number);
        },
        onchange: (event) => perform(item.id, () => window.control.change(item.id, String(event.target.value))),
    });
    return frame(item, null, [h('div', { class: 'range' }, input, output)]);
}

function actionCard(item) {
    const control = button(item.button || t('Run'), () => perform(item.id, () => window.control.act(item.id)), {
        danger: Boolean(item.danger),
        disabled: state.busy.has(item.id) || !item.available,
    });
    return frame(item, control, [], { danger: Boolean(item.danger), tags: item.terminal && item.available ? [terminalTag()] : [] });
}

function linkCard(item) {
    const control = button(t('Open'), () => window.control.manual(item.manual), { icon: 'book' });
    return frame(item, control);
}

function themesCard(item) {
    const disabled = state.busy.has(item.id) || !item.available;
    const swatches = h('div', { class: 'themes', role: 'radiogroup', 'aria-label': item.title },
        (item.choices || []).map((choice) => {
            const colors = choice.colors || {};
            const chosen = choice.value === item.state;
            const picture = h('span', { class: 'swatch-picture', 'aria-hidden': 'true' },
                h('span', { class: 'swatch-text' }, 'Aa'),
                h('span', { class: 'swatch-bar' }),
                h('span', { class: 'swatch-dots' }, ['color1', 'color2', 'color3', 'color4', 'color5', 'color6'].map((key) => {
                    const dot = h('span', {});
                    dot.style.background = colors[key] || 'transparent';
                    return dot;
                })));
            picture.style.background = colors.background || 'var(--code-bg)';
            picture.querySelector('.swatch-text').style.color = colors.foreground || 'var(--fg)';
            picture.querySelector('.swatch-bar').style.background = colors.accent || 'var(--accent)';
            return h('button', {
                type: 'button',
                class: 'swatch',
                role: 'radio',
                'aria-checked': String(chosen),
                disabled,
                onclick: () => {
                    if (!chosen) {
                        perform(item.id, () => window.control.change(item.id, choice.value));
                    }
                },
            }, picture, h('span', { class: 'swatch-name' }, chosen ? icon('check', 14) : null, h('span', {}, choice.title)));
        }));
    return frame(item, null, [swatches]);
}

function wallpapersCard(item) {
    const choices = item.choices || [];
    const disabled = state.busy.has(item.id) || !item.available;
    const below = !item.available ? [] : !choices.length
        ? [h('p', { class: 'row-empty' }, t('This theme has no pictures of its own.'))]
        : [h('div', { class: 'pictures', role: 'radiogroup', 'aria-label': item.title }, choices.map((choice, index) => {
            const chosen = choice.value === item.state;
            return h('button', {
                type: 'button',
                class: 'picture',
                role: 'radio',
                'aria-checked': String(chosen),
                title: choice.title,
                disabled,
                onclick: () => {
                    if (!chosen) {
                        perform(item.id, () => window.control.change(item.id, choice.value));
                    }
                },
            }, h('img', { src: `wallpaper://picture-${index}/`, alt: choice.title, loading: 'lazy' }));
        }))];
    return frame(item, null, below);
}

function widgetsCard(item) {
    const busy = state.busy.has(item.id);
    const widgets = item.widgets || [];
    const rows = widgets.length
        ? h('div', { class: 'rows' }, widgets.map((widget) => h('div', { class: 'row' },
            h('div', { class: 'row-words' },
                h('strong', {}, widget.name || widget.id),
                h('small', { dir: 'ltr' }, widget.broken ? t('{id}: its widget.json is missing or broken', { id: widget.id }) : widget.id)),
            item.agentic
                ? button(t('Fix…'), () => perform(item.id, () => window.control.widget('fix', widget.id)), { small: true, icon: 'wrench', disabled: busy })
                : null,
            confirmButton(t('Remove'), t('Move it to the trash?'),
                () => perform(item.id, () => window.control.widget('remove', widget.id)), { icon: 'trash', disabled: busy }),
            h('button', {
                type: 'button',
                class: 'switch',
                role: 'switch',
                'aria-checked': String(widget.on),
                'aria-label': t('Show {name} in the top bar', { name: widget.name || widget.id }),
                disabled: busy,
                onclick: () => perform(item.id, () => window.control.widget(widget.on ? 'off' : 'on', widget.id)),
            }))))
        : h('p', { class: 'row-empty' }, t('No widgets yet.'));

    // A new one from an example, under a name checked as amethystora-widgets checks it
    const examples = item.examples || [];
    if (!examples.includes(state.widgetExample)) {
        state.widgetExample = examples[0] || '';
    }
    const valid = WIDGET_ID.test(state.widgetName) && state.widgetName.length <= 40 &&
        !widgets.some((widget) => widget.id === state.widgetName);
    const add = h('button', {
        type: 'button',
        class: 'btn',
        disabled: busy || !valid || !state.widgetExample,
        onclick: () => {
            const name = state.widgetName;
            state.widgetName = '';
            perform(item.id, () => window.control.newWidget(name, state.widgetExample));
        },
    }, icon('plus', 16), h('span', {}, t('Add')));
    const nameField = h('input', {
        class: `field${state.widgetName && !valid ? ' invalid' : ''}`,
        type: 'text',
        dir: 'ltr',
        value: state.widgetName,
        // An example of a name, which is lower case letters, digits and dashes in any language
        placeholder: 'my-widget',
        'aria-label': t("The new widget's name"),
        spellcheck: 'false',
        oninput: (event) => {
            state.widgetName = event.target.value.trim();
            const ok = WIDGET_ID.test(state.widgetName) && state.widgetName.length <= 40 &&
                !widgets.some((widget) => widget.id === state.widgetName);
            event.target.classList.toggle('invalid', Boolean(state.widgetName) && !ok);
            add.disabled = busy || !ok || !state.widgetExample;
        },
    });
    const exampleSelect = h('select', {
        class: 'field',
        'aria-label': t('The example it starts from'),
        onchange: (event) => {
            state.widgetExample = event.target.value;
        },
    }, examples.map((example) => h('option', { value: example }, example)));
    exampleSelect.value = state.widgetExample;

    const below = [];
    if (!item.bar) {
        below.push(callout('check', null, null,
            h('div', { class: 'actions' },
                button(t('Turn the extension on'), () => perform(item.id, () => window.control.widget('restart', '')), { small: true }))));
    }
    if (item.available) {
        below.push(rows,
            h('div', { class: 'form' },
                h('span', { class: 'form-note' }, t('Start one from an example, then change its files in ~/.config/amethystora/widgets:')),
                nameField, exampleSelect, add),
            item.agentic
                ? h('div', { class: 'actions' },
                    button(t('Make one with the agent…'), () => perform(item.id, () => window.control.widget('make', '')), { icon: 'sparkle' }))
                : null);
    }
    return frame(item, null, below);
}

function webappsCard(item) {
    const busy = state.busy.has(item.id);
    const webapps = item.webapps || [];
    const rows = webapps.length
        ? h('div', { class: 'rows' }, webapps.map((webapp) => h('div', { class: 'row' },
            h('div', { class: 'row-words' }, h('strong', {}, webapp.name), h('small', { dir: 'ltr' }, webapp.address)),
            confirmButton(t('Remove'), t('Remove it?'),
                () => perform(item.id, () => window.control.webapp('remove', webapp.name)), { icon: 'trash', disabled: busy }))))
        : h('p', { class: 'row-empty' }, t('No web apps yet.'));
    const control = button(t('Add a web app…'), () => perform(item.id, () => window.control.webapp('install', '')), {
        icon: 'plus',
        disabled: busy || !item.available,
    });
    return frame(item, control, item.available ? [rows] : [], { tags: item.available ? [terminalTag()] : [] });
}

function trustCard(item) {
    const busy = state.busy.has(item.id);
    const validRepository = () => REPOSITORY.test(state.repository);
    const note = h('p', { class: 'form-note' });
    const trust = h('button', {
        type: 'button',
        class: 'btn primary',
        onclick: () => {
            const repository = state.repository;
            perform(item.id, async () => {
                const result = await window.control.trustImage(repository);
                if (result.terminal) {
                    state.trusted = repository;
                }
                return result;
            });
        },
    }, h('span', {}, item.button || t('Trust…')));
    const refresh = () => {
        const typed = Boolean(state.repository);
        const ok = validRepository();
        note.className = `form-note${typed && !ok ? ' bad' : ''}`;
        note.textContent = typed && !ok
            ? t('A repository such as ghcr.io/you/your-image: lower case, and no tag.')
            : t('The repository your image is published to, and the cosign.pub from it.');
        trust.disabled = busy || !item.available || !ok || !state.key;
    };
    const field = h('input', {
        class: 'field',
        type: 'text',
        dir: 'ltr',
        value: state.repository,
        placeholder: 'ghcr.io/you/your-image',
        'aria-label': t('The repository'),
        spellcheck: 'false',
        disabled: !item.available,
        oninput: (event) => {
            state.repository = event.target.value.trim();
            field.classList.toggle('invalid', Boolean(state.repository) && !validRepository());
            refresh();
        },
    });
    const keyButton = button(state.key ? state.key : t('Choose cosign.pub…'), async () => {
        const result = await window.control.chooseKey();
        if (result?.name) {
            state.key = result.name;
            render();
        }
    }, { icon: 'key', disabled: busy || !item.available });
    refresh();
    const below = item.available ? [h('div', { class: 'form' }, field, keyButton, trust, note)] : [];
    if (state.trusted) {
        below.push(callout('info', t('Then switch to it, and hand the signature policy back to the image'), null,
            commandBlock(`sudo bootc switch --enforce-container-sigpolicy ${state.trusted}:stable`),
            commandBlock('sudo cp /usr/etc/containers/policy.json /etc/containers/policy.json'),
            h('div', { class: 'actions' },
                linkButton(t('Why, in the manual'), () => window.control.manual('developer#an-image-of-your-own'), 'book'))));
    }
    return frame(item, null, below, { tags: item.available ? [terminalTag()] : [] });
}

// A date and time, the language's way
function when(seconds) {
    return new Intl.DateTimeFormat(t.locale, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(seconds * 1000));
}

// What one difference between the machine and the setup file is about, in the file's own names
function changeName(change) {
    if (change.area === 'packages') {
        return `${change.container}: ${(change.packages || []).join(', ')}`;
    }
    if (change.area === 'favorites') {
        return (change.to || change.from || []).join(', ');
    }
    if (change.area === 'keybinding') {
        return change.schema === 'custom' ? change.key : `${change.schema} ${change.key}`;
    }
    return change.app || change.uuid || change.key || change.name || (typeof change.to === 'string' ? change.to : '') || '';
}

function setupDiffRows() {
    const diff = state.diff;
    if (diff === 'reading' || diff === null) {
        return h('p', { class: 'row-empty' }, icon('spinner', 15, 'spin'), ' ', t('Comparing this machine with the file…'));
    }
    if (diff.error) {
        return callout('check', t('The file could not be compared with this machine'), diff.error);
    }
    const changes = diff.changes || [];
    if (!changes.length) {
        return callout('info', t('This machine is as your setup file says.'), null);
    }
    const kind = (change) => (!change.ok ? 'cannot' : change.action);
    const order = { cannot: 0, add: 1, set: 2, remove: 3 };
    const marks = { cannot: '!', add: '+', set: '~', remove: '−' };
    const words = {
        cannot: t('In the file, but this machine cannot have it'),
        add: t('In the file, not here'),
        set: t('Set differently here'),
        remove: t('Here, not in the file'),
    };
    const sorted = [...changes].sort((a, b) => order[kind(a)] - order[kind(b)]);
    return h('div', { class: 'section' },
        h('p', { class: 'soft small' }, t('{count, plural, one {One difference} other {# differences}} between this machine and the file. Apply adds and sets what is missing; it takes nothing away.', { count: changes.length })),
        h('div', { class: 'rows' }, sorted.map((change) => h('div', { class: 'row' },
            h('span', { class: `mark ${kind(change)}`, title: words[kind(change)], 'aria-label': words[kind(change)] }, marks[kind(change)]),
            h('div', { class: 'row-words' },
                h('strong', { dir: 'ltr' }, changeName(change)),
                h('small', {}, change.ok ? (AREAS[change.area] || change.area) : `${AREAS[change.area] || change.area}: ${change.why || ''}`))))));
}

function setupCard(item) {
    const busy = state.busy.has(item.id);
    const saved = item.saved ? t('Saved {when}', { when: when(item.saved) }) : t('Not saved yet.');
    const save = item.commands?.save;
    const apply = item.commands?.apply;
    const below = [
        h('div', { class: 'setting-foot' }, h('code', { dir: 'ltr' }, item.file), h('span', {}, saved)),
        h('div', { class: 'actions' },
            button(item.saved ? t('Save again') : t('Save'), () => perform(item.id, () => window.control.setup('save')), {
                primary: !item.saved,
                disabled: busy || !save,
            }),
            item.saved
                ? button(t('Apply…'), () => perform(item.id, () => window.control.setup('apply')), { icon: 'terminal', disabled: busy || !apply })
                : null),
    ];
    if (item.saved) {
        below.push(setupDiffRows());
    }
    return frame(item, null, below);
}

// The pools of disks, each with the actions the list gave it
function disksCard(item) {
    const busy = state.busy.has(item.id);
    const disks = item.disks || [];
    const rows = disks.length
        ? h('div', { class: 'rows' }, disks.map((disk) => h('div', { class: 'row' },
            h('div', { class: 'row-words' },
                h('strong', {}, disk.title),
                disk.text ? h('small', {}, disk.text) : null),
            disk.state === 'check' ? h('span', { class: 'tag check' }, icon('alert', 13), t('Needs a look')) : h('span', { class: 'tag on' }, t('Fine')),
            (disk.actions || []).map((action) => button(action.title, () => perform(item.id, () => window.control.pool(action.id, disk.id)), {
                icon: action.terminal ? 'terminal' : null,
                small: true,
                disabled: busy || !item.available,
            })))))
        : null;
    return frame(item, null, rows ? [rows] : []);
}

const KINDS = {
    switch: switchCard,
    choice: choiceCard,
    range: rangeCard,
    action: actionCard,
    link: linkCard,
    themes: themesCard,
    wallpapers: wallpapersCard,
    widgets: widgetsCard,
    webapps: webappsCard,
    'trust-image': trustCard,
    setup: setupCard,
    disks: disksCard,
};

function card(item) {
    return (KINDS[item.kind] || actionCard)(item);
}

// --- Pages -------------------------------------------------------------------------------------------

function items() {
    return state.list?.items || [];
}

// An entry's cards in the groups the list gives them, in its order
function sections(list) {
    const groups = [];
    for (const item of list) {
        const last = groups[groups.length - 1];
        if (last && last.group === (item.group || '')) {
            last.items.push(item);
        } else {
            groups.push({ group: item.group || '', items: [item] });
        }
    }
    return groups.map(({ group, items: entries }) => h('div', { class: 'section' },
        group ? h('h2', {}, group) : null,
        h('div', { class: 'cards' }, entries.map(card))));
}

function banner() {
    if (!state.banner) {
        return null;
    }
    return h('div', { class: 'banner-wrap' },
        h('div', { class: `banner${state.banner.tone === 'failed' ? ' failed' : ''}`, role: 'status' },
            icon(state.banner.tone === 'failed' ? 'alert' : 'terminal', 18),
            h('span', { class: 'grow' }, state.banner.text),
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

function pageView() {
    const page = PAGES[state.page];
    const list = items().filter((item) => item.page === state.page);
    return h('div', { class: 'page' },
        h('header', { class: 'page-head' }, h('h1', {}, page.title), h('p', { class: 'lead' }, page.lead)),
        list.length ? sections(list) : h('div', { class: 'empty' }, h('p', {}, t('Nothing to set here on this machine.'))),
        state.page === 'system' ? h('p', { class: 'soft small' },
            t('Security settings are in Amethystora Security, and automatic updates in Updates.'), ' ',
            linkButton(t('Open Security'), () => window.control.open('security'), 'shield')) : null);
}

// Letters without their accents, in lower case, so that "écran" is found by "ecran"
function plain(text) {
    return String(text || '').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

function matches(item, words) {
    const haystack = plain([item.title, item.text, item.detail, item.group, item.usage, PAGES[item.page]?.title,
        ...(item.choices || []).map((choice) => `${choice.title} ${choice.text || ''}`)].join(' '));
    return words.every((word) => haystack.includes(word));
}

function searchView() {
    const words = plain(state.search).split(/\s+/).filter(Boolean);
    const found = items().filter((item) => matches(item, words));
    if (!found.length) {
        return h('div', { class: 'page' },
            h('div', { class: 'empty' },
                h('h2', {}, t('Nothing matches')),
                h('p', {}, t('Security settings are in Amethystora Security, and automatic updates in Updates.')),
                h('div', { class: 'actions' },
                    button(t('Open Security'), () => window.control.open('security'), { icon: 'shield', small: true }),
                    button(t('Open Updates'), () => window.control.open('updates'), { icon: 'refresh', small: true }))));
    }
    return h('div', { class: 'page' },
        h('header', { class: 'page-head' },
            h('h1', {}, t('Search')),
            h('p', { class: 'lead' }, t('{count, plural, one {One setting matches} other {# settings match}} “{search}”.', { count: found.length, search: state.search }))),
        Object.keys(PAGES).map((page) => {
            const here = found.filter((item) => item.page === page);
            return here.length
                ? h('div', { class: 'section' }, h('h2', {}, PAGES[page].title), h('div', { class: 'cards' }, here.map(card)))
                : null;
        }));
}

function loadingView() {
    return h('div', { class: 'loading', role: 'status' }, h('img', { class: 'gem', src: 'gem.svg', alt: '' }), h('span', {}, t('Reading the settings…')));
}

function errorView() {
    return h('div', { class: 'page' },
        h('div', { class: 'empty' },
            h('h2', {}, t('The settings could not be read')),
            h('p', {}, state.error),
            h('div', { class: 'actions' }, button(t('Try again'), () => load(), { icon: 'refresh', primary: true }))));
}

// --- The window --------------------------------------------------------------------------------------

function renderNav() {
    for (const node of pageButtons) {
        if (!state.search && node.dataset.page === state.page) {
            node.setAttribute('aria-current', 'page');
        } else {
            node.removeAttribute('aria-current');
        }
    }
    const updates = state.list?.elsewhere?.automatic_updates;
    updatesState.textContent = updates === 'on' ? t('On') : updates === 'off' ? t('Off') : '';
    updatesState.className = `nav-state${updates === 'on' ? ' on' : ''}`;
    updatesState.title = t('Automatic updates');
    backupsButton.hidden = !state.list?.elsewhere?.backups;
}

function render() {
    renderNav();
    // Drawn again in place, at the same scroll, as a change comes back
    const top = view.scrollTop;
    const content = !state.list
        ? (state.error ? errorView() : loadingView())
        : state.search ? searchView() : pageView();
    view.replaceChildren(banner() || '', content);
    view.scrollTop = top;
}

async function load({ quiet = false } = {}) {
    if (state.reading) {
        return;
    }
    state.reading = true;
    if (!quiet) {
        state.list = null;
        state.error = '';
        render();
    }
    const result = await window.control.list();
    state.reading = false;
    state.read = Date.now();
    if (result?.error) {
        // A list read before stays on screen; only the first one failing takes its place
        if (!state.list) {
            state.error = result.error;
        } else {
            state.banner = { tone: 'failed', text: result.error };
        }
    } else {
        state.list = result;
        state.error = '';
        // Set up again, or saved: what it says has to be compared once more
        state.diff = null;
    }
    render();
    readDiff();
}

// The setup page compares the machine with the file, which takes a moment, once it is shown
async function readDiff() {
    const setup = items().find((item) => item.kind === 'setup');
    if (state.page !== 'setup' || state.search || !setup?.saved || state.diff !== null) {
        return;
    }
    state.diff = 'reading';
    render();
    state.diff = await window.control.setupDiff();
    render();
}

function show(page) {
    if (!Object.hasOwn(PAGES, page)) {
        return;
    }
    state.page = page;
    state.search = '';
    searchInput.value = '';
    state.banner = null;
    render();
    view.scrollTop = 0;
    readDiff();
}

function luminance(hex) {
    const [r, g, b] = [1, 3, 5]
        .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
        .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// The same palette mapping as the Manual's, Security's, Updates' and Logs'
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

window.control.onPalette(applyPalette);
window.control.onOpen(show);
// Back from a terminal, or from anywhere a setting may have changed: read the list again
window.control.onFocus(() => {
    if (state.list && Date.now() - state.read > 1500) {
        load({ quiet: true });
    }
});

for (const node of pageButtons) {
    node.addEventListener('click', () => show(node.dataset.page));
}
document.getElementById('open-security').addEventListener('click', () => window.control.open('security'));
document.getElementById('open-updates').addEventListener('click', () => window.control.open('updates'));
backupsButton.addEventListener('click', () => window.control.open('backups'));
document.getElementById('open-manual').addEventListener('click', () => window.control.manual('control'));

searchInput.addEventListener('input', () => {
    state.search = searchInput.value.trim();
    render();
    if (!state.search) {
        readDiff();
    }
});

function typing(target) {
    return target instanceof HTMLInputElement || target instanceof HTMLSelectElement || target instanceof HTMLTextAreaElement;
}

document.addEventListener('keydown', (event) => {
    if ((event.ctrlKey && event.key === 'r') || event.key === 'F5') {
        event.preventDefault();
        load({ quiet: true });
    } else if ((event.ctrlKey && event.key === 'f') || (event.key === '/' && !typing(event.target))) {
        event.preventDefault();
        searchInput.focus();
        searchInput.select();
    } else if (event.key === 'Escape' && state.search) {
        searchInput.value = '';
        state.search = '';
        render();
        readDiff();
    } else if (event.ctrlKey && (event.key === '=' || event.key === '+')) {
        window.control.zoom(0.5);
    } else if (event.ctrlKey && event.key === '-') {
        window.control.zoom(-0.5);
    } else if (event.ctrlKey && event.key === '0') {
        window.control.zoom(0);
    }
});

async function start() {
    applyPalette(await window.control.palette());
    const page = location.hash.slice(1);
    state.page = Object.hasOwn(PAGES, page) ? page : 'appearance';
    render();
    await load();
}

start();
