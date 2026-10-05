'use strict';

// Amethystora Logs: what the system, the desktop and the apps have written to the journal, in a window
// of its own. It takes the place of GNOME Logs, which the upstream Flatpak list installed.
//
// Everything is read with journalctl, as the person at the machine: the members of wheel see the whole
// machine, anyone else their own session and apps. Nothing here writes to the journal or changes what it
// keeps. What the page picks, a view, a source, a time range, a level and a search, is turned into
// journalctl's arguments here, from known choices: an app has to be one this process found in the
// journal itself, a service or program is only ever the value of --unit or --identifier, and the search
// only ever the value of --grep.
//
// The window is locked down the way the Manual's is: it loads nothing but its own page, and the page
// can ask for nothing but what preload.js lists.

const { app, BrowserWindow, clipboard, dialog, ipcMain, session } = require('electron');
const { execFile, spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');
const I18N = require('./i18n.js');

// The session's language, which the page is handed too, and Chromium's own (i18n.js)
const LOCALE = I18N.load(__dirname);
const t = I18N.use(LOCALE);
app.commandLine.appendSwitch('lang', LOCALE.locale);

const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
const DATA_HOME = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
// Where amethystora-theme renders the current theme (CURRENT_DIR in /usr/lib/amethystora/theme/lib.sh)
const CURRENT = path.join(CONFIG_HOME, 'amethystora', 'current');
const IN_TERMINAL = '/usr/libexec/amethystora-in-terminal';
// The AI agent, which a crash or a service's errors can be handed to, unless the account turned it off
const AGENT = '/usr/bin/amethystora-agent';

// Entries read at a time, newest first; "Show older" reads the next as many
const PAGE = 400;
// An export keeps the newest this many entries of what is shown
const EXPORT_LINES = 250000;
// The badges count up to here and then say "999+"
const COUNT_CAP = 1000;
// What systemd-coredump logs a crash under
const COREDUMP = 'fc2e22bc6ee647b6b90729ab34a250b1';

// The views of the sidebar. Security is the audit log and the auth and authpriv syslog facilities.
const CATEGORIES = {
    important: [],
    all: [],
    session: ['--user'],
    system: ['--system'],
    kernel: ['_TRANSPORT=kernel'],
    security: ['_TRANSPORT=audit', '+', 'SYSLOG_FACILITY=4', '+', 'SYSLOG_FACILITY=10'],
    crashes: [`MESSAGE_ID=${COREDUMP}`],
};

const RANGES = {
    boot: ['--boot=0'],
    previous: ['--boot=-1'],
    hour: ['--since=-1h'],
    day: ['--since=-24h'],
    week: ['--since=-7d'],
    all: [],
};

// Terminal colour codes some programs write into their messages
const ANSI = /\u001b\[[0-9;?]*[A-Za-z]/g;

app.setPath('userData', path.join(CONFIG_HOME, 'amethystora-logs'));

let win = null;
// The query being read now, stopped when the page asks for another
let reading = null;
// The journal being followed while the page is live
let follower = null;
// Apps and units found in the journal: the only sources a view can be narrowed to
let known = null;

// The view to open: `amethystora-logs crashes` opens on the crashes, and so on
function viewArgument(argv) {
    const view = argv.slice(1).find((arg) => !arg.startsWith('-'));
    return view === 'sources' || Object.hasOwn(CATEGORIES, view || '') ? view : '';
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

// A program that outlives this window, such as a terminal or the Manual
function launch(file, args) {
    const child = spawn(file, args, { detached: true, stdio: 'ignore' });
    child.on('error', () => {});
    child.unref();
}

// How a program ended, never an exception: each caller has something to say about a program that
// is missing or failed
function run(file, args, timeout = 60000) {
    return new Promise((resolve) => {
        execFile(file, args, { timeout, maxBuffer: 64 * 1024 * 1024 }, (error, stdout, stderr) => {
            const code = !error ? 0 : Number.isInteger(error.code) ? error.code : -1;
            resolve({ code, stdout: String(stdout), stderr: String(stderr) });
        });
    });
}

// An argument as a shell would need it, for the command the page shows beside each view
function quote(arg) {
    return /^[\w@%+=:,./-]+$/.test(arg) ? arg : `'${arg.replace(/'/g, "'\\''")}'`;
}

// --- Apps and services -----------------------------------------------------------------------------

// Where launchers are, the Flatpaks' among them, for the names of the apps
function applicationDirs() {
    const dirs = (process.env.XDG_DATA_DIRS || '/usr/local/share:/usr/share').split(':').filter(Boolean);
    return [DATA_HOME, path.join(DATA_HOME, 'flatpak', 'exports', 'share'), '/var/lib/flatpak/exports/share', ...dirs]
        .map((dir) => path.join(dir, 'applications'));
}

const names = new Map();

// The name an app's launcher gives it, or '' for an app without one
function appName(id) {
    if (!names.has(id)) {
        let name = '';
        for (const dir of applicationDirs()) {
            try {
                const text = fs.readFileSync(path.join(dir, `${id}.desktop`), 'utf8');
                const entry = text.split(/^\[/m).find((part) => part.startsWith('Desktop Entry]')) || '';
                name = /^Name=(.+)$/m.exec(entry)?.[1].trim() || '';
            } catch {
                continue;
            }
            if (name) {
                break;
            }
        }
        names.set(id, name);
    }
    return names.get(id);
}

// systemd writes "-" inside a name as \x2d, and anything else unusual the same way
function unescape(text) {
    return text.replace(/\\x([0-9a-fA-F]{2})/g, (_match, hex) => String.fromCharCode(parseInt(hex, 16)));
}

// GNOME and Flatpak start every app in a unit of its own: app-gnome-org.gnome.Nautilus-4242.scope,
// app-flatpak-com.brave.Browser-1234.scope, and app-org.gnome.Evolution\x2dalarm\x2dnotify@autostart.service
// for what starts at login. One app has one such unit for each time it was started, and the pattern
// that matches all of them is what its logs are read by. journalctl matches the patterns with fnmatch,
// to which a backslash is an escape, so the one in \x2d is doubled.
const APP_UNIT = /^app-(?:([a-z]+)-)?(.+?)(?:-\d+\.scope|@[^/]*\.service)$/;

function appOf(unit) {
    const match = APP_UNIT.exec(unit || '');
    if (!match) {
        return null;
    }
    const [, launcher, escaped] = match;
    const prefix = `app-${launcher ? `${launcher}-` : ''}${escaped.replace(/\\/g, '\\\\')}`;
    const pattern = unit.endsWith('.scope') ? `${prefix}-*.scope` : `${prefix}@*.service`;
    return { id: unescape(escaped).replace(/\.desktop$/, ''), pattern };
}

// Units that only ever run once, and the scopes of login sessions and terminals: not worth listing
const TRANSIENT = /^(run-|session-\d|vte-spawn-|init\.scope$|dbus-:)/;

// Templates with more than a few instances, such as systemd-coredump@, listed once for all of them
function collapse(units) {
    const templates = new Map();
    for (const unit of units) {
        const match = /^([^@]+)@[^@]*(\.[a-z]+)$/.exec(unit);
        if (match) {
            const key = `${match[1]}@*${match[2]}`;
            templates.set(key, (templates.get(key) || 0) + 1);
        }
    }
    const listed = new Map();
    for (const unit of units) {
        const match = /^([^@]+)@[^@]*(\.[a-z]+)$/.exec(unit);
        const key = match ? `${match[1]}@*${match[2]}` : '';
        if (key && templates.get(key) > 3) {
            listed.set(key, { name: key, label: `${match[1]}@${match[2]}`, instances: templates.get(key) });
        } else {
            listed.set(unit, { name: unit, label: unit });
        }
    }
    return [...listed.values()].sort((a, b) => a.label.localeCompare(b.label));
}

// Every app and service that has written to the journal this account can read
async function sources() {
    const [system, user] = await Promise.all([
        run('journalctl', ['--system', '--quiet', '--field=_SYSTEMD_UNIT']),
        run('journalctl', ['--user', '--quiet', '--field=_SYSTEMD_USER_UNIT']),
    ]);
    const lines = (text) => text.split('\n').map((line) => line.trim()).filter(Boolean);
    const apps = new Map();
    const userUnits = [];
    for (const unit of lines(user.stdout)) {
        const found = appOf(unit);
        if (found) {
            const entry = apps.get(found.id) || { id: found.id, patterns: new Set() };
            entry.patterns.add(found.pattern);
            apps.set(found.id, entry);
        } else if (unit.endsWith('.service') && !TRANSIENT.test(unit)) {
            userUnits.push(unit);
        }
    }
    const systemUnits = lines(system.stdout).filter((unit) => unit.endsWith('.service') && !TRANSIENT.test(unit));
    known = {
        apps: new Map([...apps.values()].map((entry) => [entry.id, { ...entry, patterns: [...entry.patterns] }])),
        user: collapse(userUnits),
        system: collapse(systemUnits),
    };
    return {
        apps: [...known.apps.values()]
            .map((entry) => ({ id: entry.id, name: appName(entry.id) || entry.id }))
            .sort((a, b) => a.name.localeCompare(b.name)),
        user: known.user,
        system: known.system,
    };
}

// The arguments that narrow the journal to one source, which has to be one found above. A program is
// narrowed to by the identifier it logs under, which the page has from an entry of the journal.
async function sourceArgs(source) {
    if (!source) {
        return [];
    }
    if (source.kind === 'identifier') {
        const name = String(source.id || '');
        if (!name || name.length > 200 || /[\n=]/.test(name)) {
            throw new Error(t('That program cannot be picked out of the journal.'));
        }
        return [`--identifier=${name}`];
    }
    if (!known) {
        await sources();
    }
    if (source.kind === 'app') {
        const entry = known.apps.get(String(source.id));
        if (!entry) {
            throw new Error(t('That app has not written anything to the journal.'));
        }
        return entry.patterns.map((pattern) => `--user-unit=${pattern}`);
    }
    if (source.kind === 'unit') {
        const scope = source.scope === 'user' ? 'user' : 'system';
        const name = String(source.id);
        if (!known[scope].some((unit) => unit.name === name)) {
            // A unit named by an entry the page has open, which has not been listed yet
            if (!/^[\w@.:\\-]+\.[a-z]+$/.test(name)) {
                throw new Error(t('That service has not written anything to the journal.'));
            }
        }
        return [scope === 'user' ? `--user-unit=${name}` : `--unit=${name}`];
    }
    throw new Error(t('Unknown source.'));
}

// --- The journal -----------------------------------------------------------------------------------

// journalctl's arguments for what the page asked for, without what it is to be printed as
async function filters(query, { range = true } = {}) {
    const category = Object.hasOwn(CATEGORIES, query.category) ? query.category : 'all';
    const args = [...CATEGORIES[category]];
    if (range) {
        const value = String(query.range || 'boot');
        const boot = /^b:([0-9a-f]{32})$/.exec(value);
        const around = /^around:(\d{1,12})$/.exec(value);
        if (boot) {
            args.push(`--boot=${boot[1]}`);
        } else if (around) {
            const second = Number(around[1]);
            args.push(`--since=@${second - 60}`, `--until=@${second + 60}`);
        } else {
            args.push(...(RANGES[value] || RANGES.boot));
        }
    }
    const level = Number.isInteger(query.level) && query.level >= 0 && query.level <= 7 ? query.level : 7;
    const priority = category === 'important' ? Math.min(level, 3) : level;
    if (priority < 7) {
        args.push(`--priority=${priority}`);
    }
    args.push(...await sourceArgs(query.source));
    const search = String(query.search || '').slice(0, 500);
    if (search) {
        // Taken as it is typed, unless the page says it is a regular expression
        const pattern = query.regex ? search : search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        args.push('--case-sensitive=false', `--grep=${pattern}`);
    }
    return args;
}

// A field as journalctl --output=json writes it: a string, the bytes of one that is not text, or a list
// of either for a field an entry has more than once
function text(value) {
    if (value === null || value === undefined) {
        return '';
    }
    if (Array.isArray(value)) {
        return value.every(Number.isInteger) ? Buffer.from(value).toString('utf8') : value.map(text).join('\n');
    }
    return String(value);
}

// Where an entry came from, as a source the page can narrow the view to
function origin(fields) {
    const app = appOf(fields._SYSTEMD_USER_UNIT);
    if (app) {
        return { kind: 'app', id: app.id, label: appName(app.id) || app.id };
    }
    const userUnit = fields._SYSTEMD_USER_UNIT;
    if (userUnit && userUnit.endsWith('.service') && !TRANSIENT.test(userUnit)) {
        return { kind: 'unit', scope: 'user', id: userUnit, label: userUnit };
    }
    const unit = fields._SYSTEMD_UNIT;
    if (unit && unit.endsWith('.service') && !TRANSIENT.test(unit)) {
        return { kind: 'unit', scope: 'system', id: unit, label: unit };
    }
    return fields.SYSLOG_IDENTIFIER ? { kind: 'identifier', id: fields.SYSLOG_IDENTIFIER, label: fields.SYSLOG_IDENTIFIER } : null;
}

function entryOf(line) {
    let raw;
    try {
        raw = JSON.parse(line);
    } catch {
        return null;
    }
    const fields = {};
    for (const [key, value] of Object.entries(raw)) {
        fields[key] = text(value);
    }
    const kernel = fields._TRANSPORT === 'kernel';
    return {
        cursor: fields.__CURSOR,
        time: Math.floor(Number(fields.__REALTIME_TIMESTAMP) / 1000),
        priority: /^[0-7]$/.test(fields.PRIORITY) ? Number(fields.PRIORITY) : 6,
        source: fields.SYSLOG_IDENTIFIER || fields._COMM || (kernel ? 'kernel' : '') ||
            fields._SYSTEMD_USER_UNIT || fields._SYSTEMD_UNIT || '',
        message: (fields.MESSAGE || '').replace(ANSI, ''),
        from: origin(fields),
        fields,
    };
}

function entries(stdout) {
    return stdout.split('\n').filter(Boolean).map(entryOf).filter((entry) => entry?.cursor);
}

// What journalctl said when it could not read, without its hints about what this account may see
function complaint(stderr) {
    return stderr.split('\n')
        .filter((line) => line.trim() && !/^Hint:|not seeing messages|Users in groups|-- No entries --/.test(line))
        .join('\n').trim();
}

// One page of entries, newest first, starting after the last one the page has. Another query stops
// this one: the page only ever wants the newest.
async function query(request) {
    reading?.kill('SIGTERM');
    reading = null;
    let args;
    try {
        args = await filters(request);
    } catch (error) {
        return { error: error.message, entries: [] };
    }
    const command = ['journalctl', ...args].map(quote).join(' ');
    const read = [...args, '--quiet', '--no-pager', '--output=json', '--reverse', `--lines=${PAGE}`];
    if (typeof request.after === 'string' && request.after) {
        read.push(`--after-cursor=${request.after}`);
    }
    const result = await new Promise((resolve) => {
        const child = execFile('journalctl', read, { timeout: 120000, maxBuffer: 256 * 1024 * 1024 },
            (error, stdout, stderr) => {
                if (reading === child) {
                    reading = null;
                }
                const code = !error ? 0 : Number.isInteger(error.code) ? error.code : -1;
                resolve({ code, stdout: String(stdout), stderr: String(stderr), stopped: child.killed });
            });
        reading = child;
    });
    if (result.stopped) {
        return { stopped: true, entries: [] };
    }
    const found = entries(result.stdout);
    const said = complaint(result.stderr);
    return {
        entries: found,
        more: found.length >= PAGE,
        command,
        error: !found.length && result.code !== 0 && said ? said : '',
    };
}

// --- Following -------------------------------------------------------------------------------------

function stopFollowing() {
    follower?.kill('SIGTERM');
    follower = null;
}

// New entries as they are written, handed to the page a few times a second
async function follow(request) {
    stopFollowing();
    let args;
    try {
        // Whatever the time range, what is new is now
        args = await filters(request, { range: false });
    } catch (error) {
        return { error: error.message };
    }
    const child = spawn('journalctl', [...args, '--quiet', '--no-pager', '--output=json', '--follow', '--lines=0']);
    follower = child;
    let batch = [];
    let timer = null;
    child.on('error', () => {});
    readline.createInterface({ input: child.stdout }).on('line', (line) => {
        const entry = entryOf(line);
        if (!entry?.cursor || follower !== child) {
            return;
        }
        batch.push(entry);
        if (!timer) {
            timer = setTimeout(() => {
                timer = null;
                if (follower === child) {
                    send('live', batch);
                }
                batch = [];
            }, 250);
        }
    });
    child.on('close', () => {
        if (follower === child) {
            follower = null;
            send('live-ended');
        }
    });
    return { following: true };
}

// --- What the sidebar shows ------------------------------------------------------------------------

// How many entries of this boot match, up to COUNT_CAP
async function count(args) {
    const { stdout } = await run('journalctl', [...args, '--boot=0', '--quiet', '--no-pager', '--output=json',
        '--output-fields=PRIORITY', `--lines=${COUNT_CAP}`]);
    return stdout.split('\n').filter(Boolean).length;
}

// The boots the journal remembers, newest first
async function boots() {
    let result = await run('journalctl', ['--list-boots', '--quiet', '--no-pager', '--output=json', '--lines=40']);
    if (result.code !== 0) {
        result = await run('journalctl', ['--list-boots', '--quiet', '--no-pager', '--output=json']);
    }
    try {
        const list = JSON.parse(result.stdout);
        return list
            .map((boot) => ({
                index: Number(boot.index),
                id: String(boot.boot_id || ''),
                first: Math.floor(Number(boot.first_entry) / 1000) || null,
                last: Math.floor(Number(boot.last_entry) / 1000) || null,
            }))
            .filter((boot) => /^[0-9a-f]{32}$/.test(boot.id))
            .sort((a, b) => b.index - a.index);
    } catch {
        return [];
    }
}

async function overview() {
    const [access, usage, important, crashes, bootList] = await Promise.all([
        run('journalctl', ['--system', '--lines=0', '--no-pager']),
        run('journalctl', ['--disk-usage']),
        count(['--priority=3']),
        count([`MESSAGE_ID=${COREDUMP}`]),
        boots(),
    ]);
    return {
        // Outside wheel, journalctl can open nothing of the system's and says so
        readable: access.code === 0 && !/insufficient permissions|not seeing messages/i.test(access.stderr),
        usage: /take up (\S+)/.exec(usage.stdout)?.[1] || '',
        counts: { important, crashes, cap: COUNT_CAP },
        boots: bootList,
        user: os.userInfo().username,
    };
}

// --- Export and the terminal -----------------------------------------------------------------------

function stamp() {
    const now = new Date();
    const pad = (value) => String(value).padStart(2, '0');
    return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}`;
}

// What is shown, oldest first, into a file of the person's choosing: text as a terminal shows it, or
// journalctl's JSON. Logs name people, places and machines, so the file is theirs alone.
async function exportLogs(request) {
    let args;
    try {
        args = await filters(request);
    } catch (error) {
        return { error: error.message };
    }
    const { canceled, filePath } = await dialog.showSaveDialog(win, {
        title: t('Export logs'),
        buttonLabel: t('Export'),
        defaultPath: path.join(app.getPath('documents'), `logs-${stamp()}.txt`),
        filters: [
            { name: t('Text'), extensions: ['txt', 'log'] },
            { name: t('JSON, one entry a line'), extensions: ['json'] },
        ],
    });
    if (canceled || !filePath) {
        return { canceled: true };
    }
    const json = filePath.endsWith('.json');
    return new Promise((resolve) => {
        let out;
        try {
            out = fs.createWriteStream(filePath, { mode: 0o600 });
        } catch (error) {
            resolve({ error: error.message });
            return;
        }
        const child = spawn('journalctl', [...args, '--quiet', '--no-pager',
            json ? '--output=json' : '--output=short-iso-precise', `--lines=${EXPORT_LINES}`]);
        let stderr = '';
        let failed = null;
        child.stdout.pipe(out);
        child.stderr.on('data', (data) => {
            stderr += data;
        });
        child.on('error', (error) => {
            failed = error.message;
        });
        out.on('error', (error) => {
            failed = error.message;
            child.kill('SIGTERM');
        });
        child.on('close', (code) => {
            out.end(() => {
                const said = complaint(stderr);
                if (failed || (code !== 0 && said)) {
                    resolve({ error: failed || said });
                } else {
                    resolve({ saved: path.basename(filePath), folder: path.dirname(filePath) });
                }
            });
        });
    });
}

// The same view in journalctl in a terminal, where less can page through all of it
async function terminal(request, live) {
    try {
        const args = await filters(request, { range: !live });
        launch(IN_TERMINAL, ['journalctl', ...args, live ? '--follow' : '--pager-end']);
        return {};
    } catch (error) {
        return { error: error.message };
    }
}

// --- The AI agent ----------------------------------------------------------------------------------

// Whether the agentic features are on for this account (`ame agent toggle`)
async function agentOn() {
    return (await run(AGENT, ['status'])).code === 0;
}

// An entry handed to the agent, which looks into it in a terminal with the diagnose skill and changes
// nothing until asked. What reaches it is only ever a crash's process number, which it looks up in
// coredumpctl, or the name of the service the entry came from, which it looks up in systemd: never a
// message or anything else the page could fill with words of its own.
function diagnose(target) {
    const value = String(target?.value || '');
    if (target?.kind === 'crash' && /^\d{1,10}$/.test(value)) {
        launch(AGENT, ['diagnose', value]);
    } else if (target?.kind === 'unit' && /^[\w@.:\\-]+\.service$/.test(value)) {
        launch(AGENT, ['diagnose', value]);
    }
}

// --- The window ------------------------------------------------------------------------------------

function createWindow(view) {
    const colors = palette();
    win = new BrowserWindow({
        width: 1240,
        height: 840,
        minWidth: 760,
        minHeight: 540,
        title: t('Amethystora Logs'),
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
    win.loadFile(path.join(__dirname, 'index.html'), { hash: view });
    win.on('focus', () => send('focus'));
    win.on('closed', () => {
        win = null;
    });
}

// A theme switch replaces current/theme and rewrites current/theme.name, so the window follows it
// the way the rest of the desktop does
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
        const view = viewArgument(argv);
        if (view) {
            send('open', view);
        }
    });

    app.on('web-contents-created', (_event, contents) => {
        contents.on('will-navigate', (event) => event.preventDefault());
        contents.setWindowOpenHandler(() => ({ action: 'deny' }));
    });

    const request = (value) => (value && typeof value === 'object' ? value : {});

    // Asked for once, by preload.js, before the page's scripts run
    ipcMain.on('locale', (event) => {
        event.returnValue = LOCALE;
    });
    ipcMain.handle('overview', () => overview());
    ipcMain.handle('sources', () => sources());
    ipcMain.handle('query', (_event, value) => query(request(value)));
    ipcMain.handle('follow', (_event, value) => follow(request(value)));
    ipcMain.handle('stop-following', () => stopFollowing());
    ipcMain.handle('export', (_event, value) => exportLogs(request(value)));
    ipcMain.handle('terminal', (_event, value, live) => terminal(request(value), Boolean(live)));
    ipcMain.handle('agent', () => agentOn());
    ipcMain.handle('diagnose', (_event, value) => diagnose(request(value)));
    ipcMain.handle('palette', () => palette());
    ipcMain.handle('copy', (_event, value) => clipboard.writeText(String(value)));
    ipcMain.handle('manual', (_event, page) => {
        if (/^[a-z0-9-]+(#[a-z0-9-]+)?$/.test(String(page))) {
            launch('amethystora-manual', [String(page)]);
        }
    });

    app.whenReady().then(() => {
        session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        createWindow(viewArgument(process.argv));
        watchTheme();
    });

    app.on('will-quit', () => {
        reading?.kill('SIGTERM');
        stopFollowing();
    });
    app.on('window-all-closed', () => app.quit());
}
