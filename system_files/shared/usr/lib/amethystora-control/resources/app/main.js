'use strict';

// Amethystora Control: Amethystora's own settings outside security, in a window of their own, for what is
// otherwise only in `ame`. What each setting is now, and the command that changes it, come from one
// script, /usr/libexec/amethystora-control-list, which `ame control` prints too. This window shows that
// list and runs its commands, and nothing of its own.
//
// The page only ever sends back an entry's id and one of the values the list gave for it, and what runs
// is the argument vector the list has for that, never through a shell. The few things the page does type
// are checked here first: a slider's number against the list's range, a new widget's name against the
// rule amethystora-widgets keeps for names, and a repository to trust against the rule
// amethystora-trust-image keeps. The key to trust is picked in this process's own file dialog, and the
// page never names it. A command that asks something, explains a risk or needs a password opens in a
// terminal (amethystora-in-terminal), and the page reads the list again when the window has the focus
// back.
//
// Security's settings are not here: they are Amethystora Security's, which this window only opens.
//
// The window is locked down the way the Manual's is: it loads nothing but its own page, and the page
// can ask for nothing but what preload.js lists.

const { app, BrowserWindow, clipboard, dialog, ipcMain, protocol, session } = require('electron');
const { execFile, spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const I18N = require('./i18n.js');

// The session's language, which the page is handed too, and Chromium's own (i18n.js)
const LOCALE = I18N.load(__dirname);
const t = I18N.use(LOCALE);
app.commandLine.appendSwitch('lang', LOCALE.locale);

const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
// Where amethystora-theme renders the current theme (CURRENT_DIR in /usr/lib/amethystora/theme/lib.sh)
const CURRENT = path.join(CONFIG_HOME, 'amethystora', 'current');
const LIST = '/usr/libexec/amethystora-control-list';
const SETUP = '/usr/libexec/amethystora-setup';
const IN_TERMINAL = '/usr/libexec/amethystora-in-terminal';
const IMAGE_INFO = '/usr/share/amethystora/image-info.json';
const PAGES = new Set(['appearance', 'desktop', 'apps', 'agent', 'system', 'setup']);
// The windows a link opens, each by the one command that opens it
const LINKS = { security: 'amethystora-security', updates: 'amethystora-update', backups: 'amethystora-backups' };
// A widget's name, as amethystora-widgets new takes it
const WIDGET_ID = /^[a-z0-9][a-z0-9-]*$/;
// A repository as amethystora-trust-image takes it: a registry with a dot or a port, a path in lower
// case, no tag and no digest. The helper's own expression, letter for letter, and it checks it again.
const REPOSITORY = new RegExp(String.raw`^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(\.[a-z0-9-]+|:[0-9]+)(/[a-z0-9]+(([._]|__|-+)[a-z0-9]+)*)+$`);
// The pictures a wallpaper can be, by the type the page's <img> is told
const PICTURES = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml' };
// Terminal colour codes some commands write into what they say
const ANSI = /\u001b\[[0-9;?]*[A-Za-z]/g;

app.setPath('userData', path.join(CONFIG_HOME, 'amethystora-control'));
// The current theme's wallpapers, for the page's thumbnails, and only those (protocol.handle below)
protocol.registerSchemesAsPrivileged([{ scheme: 'wallpaper', privileges: { standard: true, secure: true } }]);

let win = null;
// The list as the script last gave it: the only entries, choices and commands anything here runs
let list = null;
// The public key picked for an image of one's own, which the page knows only by its file's name
let chosenKey = null;

// The page to open: `amethystora-control system` opens on the system's settings
function pageArgument(argv) {
    const page = argv.slice(1).find((arg) => !arg.startsWith('-'));
    return PAGES.has(page || '') ? page : '';
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
    for (const [, key, value] of text.matchAll(/^\s*(\w+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm)) {
        colors[key] = value;
    }
    return colors;
}

function send(channel, value) {
    win?.webContents.send(channel, value);
}

// A program that outlives this window, such as a terminal or another window
function launch(file, args) {
    const child = spawn(file, args, { detached: true, stdio: 'ignore' });
    child.on('error', () => {});
    child.unref();
}

// How a program ended, never an exception: each caller has something to say about a program that is
// missing or failed
function run(file, args, timeout = 60000) {
    return new Promise((resolve) => {
        execFile(file, args, { timeout, maxBuffer: 16 * 1024 * 1024 }, (error, stdout, stderr) => {
            const code = !error ? 0 : Number.isInteger(error.code) ? error.code : -1;
            resolve({ code, stdout: String(stdout), stderr: String(stderr) });
        });
    });
}

// --- The list --------------------------------------------------------------------------------------

async function readList() {
    const result = await run(LIST, ['--json'], 60000);
    try {
        list = JSON.parse(result.stdout);
        return list;
    } catch {
        list = null;
        return { error: result.stderr.replace(ANSI, '').trim() || t('The settings could not be read.') };
    }
}

function find(id) {
    return list?.items?.find((item) => item.id === id) || null;
}

const REFUSED = () => ({ error: t('That cannot be done from here now. Read the settings again and try once more.') });

// What a command run here printed, as the page shows it under its card: the last lines, without colours
function said(result) {
    return `${result.stdout}\n${result.stderr}`.replace(ANSI, '').trim().split('\n').slice(-12).join('\n');
}

// A command from the list, in a terminal when it asks for one, and otherwise here, with what it said
async function perform(command, terminal) {
    if (!Array.isArray(command) || !command.length || !command.every((arg) => typeof arg === 'string')) {
        return REFUSED();
    }
    if (terminal) {
        launch(IN_TERMINAL, command);
        return { terminal: true };
    }
    const result = await run(command[0], command.slice(1), 300000);
    return { ok: result.code === 0, output: said(result) };
}

// A command of the list with values checked here in the place of its placeholders, {value} and the like,
// each of which stands for a whole argument
function fill(command, values) {
    return command.map((arg) => (Object.hasOwn(values, arg) ? values[arg] : arg));
}

// A setting set to one of its choices, or a slider to a number in its range
async function change(id, value) {
    const item = find(id);
    if (!item?.available) {
        return REFUSED();
    }
    if (item.kind === 'range') {
        const number = Number(value);
        if (!/^\d{1,9}$/.test(value) || number < item.min || number > item.max) {
            return REFUSED();
        }
        return perform(fill(item.command, { '{value}': String(number) }), item.terminal);
    }
    const choice = item.choices?.find((entry) => entry.value === value);
    return choice ? perform(choice.command, choice.terminal) : REFUSED();
}

async function act(id) {
    const item = find(id);
    return item?.available && item.kind === 'action' ? perform(item.command, item.terminal) : REFUSED();
}

// A widget the list named: on, off, fix or remove; or restart and make, which name none
async function widget(action, id) {
    const item = find('widgets');
    const command = item?.commands?.[action];
    if (!item?.available || !command || action === 'new') {
        return REFUSED();
    }
    if ((action === 'make' || action === 'fix') && !item.agentic) {
        return REFUSED();
    }
    if (command.command.includes('{id}') && !item.widgets.some((entry) => entry.id === id)) {
        return REFUSED();
    }
    return perform(fill(command.command, { '{id}': id }), command.terminal);
}

// A new widget from one of the examples, under a name of its own
async function newWidget(id, example) {
    const item = find('widgets');
    if (!item?.available || !item.examples?.includes(example)) {
        return REFUSED();
    }
    if (!WIDGET_ID.test(id) || id.length > 40 || item.widgets.some((entry) => entry.id === id)) {
        return { error: t("A widget's name is lower case letters, digits and dashes, and not the name of one you have.") };
    }
    const command = item.commands.new;
    return perform(fill(command.command, { '{id}': id, '{example}': example }), command.terminal);
}

// A web app the list named, removed; or a new one, added in a terminal
async function webapp(action, name) {
    const item = find('webapps');
    const command = item?.commands?.[action];
    if (!item?.available || !command) {
        return REFUSED();
    }
    if (command.command.includes('{name}') && !item.webapps.some((entry) => entry.name === name)) {
        return REFUSED();
    }
    return perform(fill(command.command, { '{name}': name }), command.terminal);
}

// One of the actions the list gave a pool of disks
async function pool(action, id) {
    const item = list?.items?.find((entry) => entry.kind === 'disks');
    const entry = item?.disks?.find((disk) => disk.id === id);
    const found = entry?.actions?.find((candidate) => candidate.id === action);
    return item?.available && found ? perform(found.command, found.terminal) : REFUSED();
}

// --- An image of one's own -------------------------------------------------------------------------

async function chooseKey() {
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
        title: t('Choose the public key'),
        buttonLabel: t('Choose'),
        properties: ['openFile'],
        filters: [
            { name: t('Public keys'), extensions: ['pub', 'pem'] },
            { name: t('Every file'), extensions: ['*'] },
        ],
    });
    if (canceled || !filePaths?.length) {
        return { canceled: true };
    }
    chosenKey = filePaths[0];
    return { name: path.basename(chosenKey) };
}

// Amethystora's own repositories, which keep Amethystora's key, as amethystora-trust-image has them
function ownRepository() {
    try {
        const vendor = JSON.parse(fs.readFileSync(IMAGE_INFO, 'utf8'))['image-vendor'];
        return vendor ? `ghcr.io/${vendor}` : null;
    } catch {
        return null;
    }
}

async function trustImage(repository) {
    const item = find('trust-image');
    if (!item?.available) {
        return REFUSED();
    }
    if (!REPOSITORY.test(repository)) {
        return { error: t('That is not a repository such as ghcr.io/you/your-image: lower case, and no tag.') };
    }
    const own = ownRepository();
    if (own && (repository === own || repository.startsWith(`${own}/`))) {
        return { error: t("Amethystora's own images are checked against Amethystora's key, and that stays as it is.") };
    }
    if (!chosenKey || !fs.existsSync(chosenKey)) {
        return { error: t('Choose the key first: the cosign.pub of your repository.') };
    }
    return perform(fill(item.command, { '{repository}': repository, '{key}': chosenKey }), item.terminal);
}

// --- The setup file --------------------------------------------------------------------------------

// The setup file saved here, or applied in a terminal, where `ame setup apply` shows what it adds first
async function setup(action) {
    const item = list?.items?.find((entry) => entry.kind === 'setup');
    const command = item?.commands?.[action];
    return item?.available && command ? perform(command.command, command.terminal) : REFUSED();
}

// What the machine and the setup file disagree on, which `ame setup diff` works out and changes nothing
async function setupDiff() {
    const result = await run(SETUP, ['diff', '--json'], 120000);
    try {
        return { changes: JSON.parse(result.stdout) };
    } catch {
        return { error: said(result) || t('Your setup file could not be compared with this machine.') };
    }
}

// --- The window ------------------------------------------------------------------------------------

function createWindow(page) {
    const colors = palette();
    win = new BrowserWindow({
        width: 1180,
        height: 840,
        minWidth: 760,
        minHeight: 540,
        title: t('Amethystora Control'),
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
    win.on('focus', () => send('focus'));
    win.on('closed', () => {
        win = null;
    });
}

// A theme switch replaces current/theme and rewrites current/theme.name, so the window follows it the
// way the rest of the desktop does
function watchTheme() {
    let timer = null;
    try {
        fs.watch(CURRENT, () => {
            clearTimeout(timer);
            timer = setTimeout(() => send('palette', palette()), 300);
        });
    } catch {
        // No theme applied yet: the window keeps the Amethystora colours
    }
}

if (!app.requestSingleInstanceLock()) {
    app.quit();
} else {
    app.on('second-instance', (_event, argv) => {
        if (!win) {
            return;
        }
        if (win.isMinimized()) {
            win.restore();
        }
        win.focus();
        const page = pageArgument(argv);
        if (page) {
            send('open', page);
        }
    });

    app.on('web-contents-created', (_event, contents) => {
        contents.on('will-navigate', (event) => event.preventDefault());
        contents.setWindowOpenHandler(() => ({ action: 'deny' }));
    });

    // Asked for once, by preload.js, before the page's scripts run
    ipcMain.on('locale', (event) => {
        event.returnValue = LOCALE;
    });
    ipcMain.handle('list', () => readList());
    ipcMain.handle('change', (_event, id, value) => change(String(id), String(value)));
    ipcMain.handle('act', (_event, id) => act(String(id)));
    ipcMain.handle('widget', (_event, action, id) => widget(String(action), String(id)));
    ipcMain.handle('new-widget', (_event, id, example) => newWidget(String(id), String(example)));
    ipcMain.handle('webapp', (_event, action, name) => webapp(String(action), String(name)));
    ipcMain.handle('pool', (_event, action, id) => pool(String(action), String(id)));
    ipcMain.handle('choose-key', () => chooseKey());
    ipcMain.handle('trust-image', (_event, repository) => trustImage(String(repository)));
    ipcMain.handle('setup', (_event, action) => setup(String(action)));
    ipcMain.handle('setup-diff', () => setupDiff());
    ipcMain.handle('open', (_event, link) => {
        if (Object.hasOwn(LINKS, link) && (link !== 'backups' || list?.elsewhere?.backups)) {
            launch(LINKS[link], []);
        }
    });
    ipcMain.handle('palette', () => palette());
    ipcMain.handle('copy', (_event, text) => clipboard.writeText(String(text)));
    ipcMain.handle('manual', (_event, page) => {
        if (/^[a-z0-9-]+(#[a-z0-9-]+)?$/.test(String(page))) {
            launch('amethystora-manual', [String(page)]);
        }
    });

    app.whenReady().then(() => {
        session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        // A wallpaper of the current theme, by its place in the list the page was last given: wallpaper://picture-2
        protocol.handle('wallpaper', async (request) => {
            const index = /^picture-(\d{1,4})$/.exec(new URL(request.url).hostname)?.[1];
            const picture = index === undefined ? null : find('wallpaper')?.choices?.[Number(index)]?.value;
            const type = picture ? PICTURES[path.extname(picture).toLowerCase()] : null;
            if (!type) {
                return new Response(null, { status: 404 });
            }
            try {
                return new Response(await fs.promises.readFile(picture), { headers: { 'content-type': type } });
            } catch {
                return new Response(null, { status: 404 });
            }
        });
        createWindow(pageArgument(process.argv));
        watchTheme();
    });

    app.on('window-all-closed', () => app.quit());
}
