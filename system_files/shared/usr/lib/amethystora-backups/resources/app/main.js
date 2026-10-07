'use strict';

// Amethystora Backups: earlier versions of your files, from the hourly snapshots of the home folders and
// the daily restic backup, on one timeline, and putting them back. What there is, and everything done to
// it, is /usr/libexec/amethystora-restore's, which `ame backup snapshots` prints too: this window shows
// what that says and works nothing out for itself.
//
// The page only ever sends back what this process read: a point in time that `points` gave, a folder or
// file that `ls` listed (or the home folder, or the folder the window was opened on and those above it),
// and one of three ways to put back. Each reaches the helper as an argument of its own, never through a
// shell, and the helper checks it again: nothing comes back outside the home folder, and nothing is
// deleted. Setting the backup up runs `ame backup setup` in a terminal. The hourly snapshots are
// Amethystora Security's to switch, and this window only opens it.
//
// The window is locked down the way the Manual's is: it loads nothing but its own page, and the page can
// ask for nothing but what preload.js lists.

const { app, BrowserWindow, clipboard, ipcMain, session } = require('electron');
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
// Where amethystora-theme renders the current theme (CURRENT_DIR in /usr/lib/amethystora/theme/lib.sh)
const CURRENT = path.join(CONFIG_HOME, 'amethystora', 'current');
const RESTORE = '/usr/libexec/amethystora-restore';
const IN_TERMINAL = '/usr/libexec/amethystora-in-terminal';
// The AI agent, which a failed backup can be handed to, unless the account turned it off
const AGENT = '/usr/bin/amethystora-agent';
// The daily backup, a user unit (amethystora-backup.timer)
const UNIT = 'amethystora-backup.service';
const MODES = new Set(['keep-both', 'replace', 'skip']);
const PAGES = new Set(['browse', 'status']);

app.setPath('userData', path.join(CONFIG_HOME, 'amethystora-backups'));

let win = null;
// The points in time `points` last gave, by id: the only ones anything here is asked about
const points = new Map();
// The folders and files the helper has listed, and the folders above them: the only paths sent back.
// '' is the home folder.
const known = new Set(['']);
// The folder the window was opened on, relative to the home folder
let start = '';
// The backup started here, while it runs: its journal followed, and its state read every moment
let backing = null;

const HOME = (() => {
    try {
        return fs.realpathSync(os.homedir());
    } catch {
        return os.homedir();
    }
})();

// A path and every folder above it, as paths the page may send back
function remember(relative) {
    let current = relative;
    while (current) {
        known.add(current);
        current = current.includes('/') ? current.slice(0, current.lastIndexOf('/')) : '';
    }
}

// The folder to open on, from the command line or from Files' Open With: inside the home folder, or
// nothing. A file opens its folder.
function folderArgument(argv, cwd = process.cwd()) {
    const given = argv.slice(1).find((arg) => !arg.startsWith('-'));
    if (!given) {
        return null;
    }
    let resolved;
    try {
        resolved = fs.realpathSync(path.resolve(cwd, given.replace(/^file:\/\//, '')));
        if (!fs.statSync(resolved).isDirectory()) {
            resolved = path.dirname(resolved);
        }
    } catch {
        return null;
    }
    if (resolved === HOME) {
        return '';
    }
    return resolved.startsWith(`${HOME}/`) ? resolved.slice(HOME.length + 1) : null;
}

// The page to open: `amethystora-backups status` opens on the status
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
// missing or failed. A timeout of 0 waits as long as it takes, for a whole folder coming back.
function run(file, args, timeout = 120000) {
    return new Promise((resolve) => {
        execFile(file, args, { timeout, maxBuffer: 256 * 1024 * 1024 }, (error, stdout, stderr) => {
            const code = !error ? 0 : Number.isInteger(error.code) ? error.code : -1;
            resolve({ code, stdout: String(stdout), stderr: String(stderr) });
        });
    });
}

// What the helper said, as JSON: what was asked for, or {error, detail}, whose error the page says in its
// own words. A helper that said nothing it could read failed.
async function helper(args, timeout) {
    const result = await run(RESTORE, [...args, '--json'], timeout);
    try {
        return JSON.parse(result.stdout);
    } catch {
        return { error: 'failed', detail: `${result.stderr}`.trim().split('\n').slice(-3).join('\n') };
    }
}

const REFUSED = () => ({ error: 'refused' });

// --- What there is ---------------------------------------------------------------------------------

async function status() {
    const [result, agent] = await Promise.all([helper(['status'], 60000), run(AGENT, ['status'], 15000)]);
    // The agentic features are on for this account unless `ame agent toggle` turned them off
    return { ...result, agent: agent.code === 0 };
}

async function readPoints() {
    const result = await helper(['points'], 300000);
    if (Array.isArray(result.points)) {
        points.clear();
        for (const point of result.points) {
            points.set(point.id, point);
        }
    }
    return { ...result, hostname: os.hostname() };
}

// One folder as it was at a point, with each entry's state now
async function list(id, folder) {
    if (!points.has(id) || !known.has(folder)) {
        return REFUSED();
    }
    const result = await helper(['ls', id, folder], 300000);
    for (const entry of result.entries || []) {
        remember(folder ? `${folder}/${entry.name}` : entry.name);
    }
    return result;
}

// The points at which a file or folder that was listed changed
async function versions(file) {
    if (!file || !known.has(file)) {
        return REFUSED();
    }
    const result = await helper(['versions', file], 600000);
    for (const version of result.versions || []) {
        if (!points.has(version.id)) {
            points.set(version.id, version);
        }
    }
    return result;
}

async function putBack(id, files, mode) {
    if (!points.has(id) || !MODES.has(mode) || !Array.isArray(files) || !files.length ||
        !files.every((file) => typeof file === 'string' && known.has(file))) {
        return REFUSED();
    }
    return helper(['put-back', id, ...files, `--${mode}`], 0);
}

// A read-only copy, opened in whatever opens it: the snapshot itself, or a copy from the backup
async function look(id, file) {
    if (!points.has(id) || !file || !known.has(file)) {
        return REFUSED();
    }
    return helper(['open', id, file], 0);
}

// --- Backing up now --------------------------------------------------------------------------------

// The service's state, as systemctl shows it: ActiveState, Result and the invocation it is on
async function unitState() {
    const { stdout } = await run('systemctl', ['--user', 'show', '-p', 'ActiveState', '-p', 'Result', '-p', 'InvocationID', UNIT], 15000);
    return Object.fromEntries(stdout.split('\n').filter((line) => line.includes('=')).map((line) => {
        const at = line.indexOf('=');
        return [line.slice(0, at), line.slice(at + 1)];
    }));
}

// What the backup logged last, for when it failed
async function lastLines() {
    const { stdout } = await run('journalctl', ['--user', `--user-unit=${UNIT}`, '--lines=12', '--output=cat', '--no-pager', '--quiet'], 15000);
    return stdout.trim();
}

function stopFollowing() {
    if (backing) {
        clearInterval(backing.timer);
        backing.journal?.kill('SIGTERM');
        backing = null;
    }
}

// The same run the daily timer starts, now, followed in the journal as Updates follows uupd. A run
// already going is followed rather than started twice.
async function backupNow() {
    if (backing) {
        return { running: true };
    }
    const before = await unitState();
    const already = before.ActiveState === 'activating' || before.ActiveState === 'active';
    if (!already) {
        const started = await run('systemctl', ['--user', 'start', '--no-block', UNIT], 15000);
        if (started.code !== 0) {
            return { error: 'failed', detail: started.stderr.trim() };
        }
    }
    const journal = spawn('journalctl', ['--user', `--user-unit=${UNIT}`, '--follow', '--lines=0', '--output=cat', '--quiet']);
    journal.on('error', () => {});
    readline.createInterface({ input: journal.stdout }).on('line', (line) => {
        if (line.trim()) {
            send('backup-line', line);
        }
    });
    const began = Date.now();
    backing = { journal, timer: null };
    backing.timer = setInterval(async () => {
        const now = await unitState();
        const running = now.ActiveState === 'activating' || now.ActiveState === 'active';
        // Done once the run this started (a new invocation) or the one it found has ended. A run too quick
        // to be seen running is done after a few seconds of nothing.
        const ours = already || now.InvocationID !== before.InvocationID || Date.now() - began > 8000;
        if (!backing || running || !ours) {
            return;
        }
        stopFollowing();
        const ok = now.ActiveState !== 'failed' && now.Result === 'success';
        send('backup-done', { ok, lines: ok ? '' : await lastLines() });
    }, 1500);
    return { running: true };
}

// --- The window ------------------------------------------------------------------------------------

function createWindow(page) {
    const colors = palette();
    win = new BrowserWindow({
        width: 1240,
        height: 840,
        minWidth: 820,
        minHeight: 560,
        title: t('Amethystora Backups'),
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
    app.on('second-instance', (_event, argv, cwd) => {
        if (!win) {
            return;
        }
        if (win.isMinimized()) {
            win.restore();
        }
        win.focus();
        const page = pageArgument(argv);
        const folder = page ? null : folderArgument(argv, cwd);
        if (folder !== null) {
            remember(folder);
            send('open', { page: 'browse', folder });
        } else if (page) {
            send('open', { page });
        }
    });

    app.on('web-contents-created', (_event, contents) => {
        contents.on('will-navigate', (event) => event.preventDefault());
        contents.setWindowOpenHandler(() => ({ action: 'deny' }));
    });

    const strings = (value) => (Array.isArray(value) ? value.map(String) : []);

    // Asked for once, by preload.js, before the page's scripts run
    ipcMain.on('locale', (event) => {
        event.returnValue = LOCALE;
    });
    ipcMain.handle('start', () => ({ folder: start, home: HOME }));
    ipcMain.handle('status', () => status());
    ipcMain.handle('points', () => readPoints());
    ipcMain.handle('ls', (_event, id, folder) => list(String(id), String(folder)));
    ipcMain.handle('versions', (_event, file) => versions(String(file)));
    ipcMain.handle('put-back', (_event, id, files, mode) => putBack(String(id), strings(files), String(mode)));
    ipcMain.handle('look', (_event, id, file) => look(String(id), String(file)));
    ipcMain.handle('backup-now', () => backupNow());
    ipcMain.handle('last-lines', () => lastLines());
    // The two of the recipe's own actions this window offers: setting up, which asks, in a terminal, and
    // the daily run on or off, which does not
    ipcMain.handle('set-up', () => launch(IN_TERMINAL, ['ame', 'backup', 'setup']));
    ipcMain.handle('daily', async (_event, on) => {
        const result = await run('ame', ['backup', on ? 'on' : 'off'], 60000);
        return { ok: result.code === 0, output: `${result.stdout}\n${result.stderr}`.trim().split('\n').slice(-4).join('\n') };
    });
    ipcMain.handle('security', () => launch('amethystora-security', []));
    // The failed backup handed to the agent, which looks into it in a terminal and changes nothing until
    // asked: only ever the one unit's name, never anything from the page
    ipcMain.handle('diagnose', () => launch(AGENT, ['diagnose', UNIT]));
    ipcMain.handle('palette', () => palette());
    ipcMain.handle('copy', (_event, text) => clipboard.writeText(String(text)));
    ipcMain.handle('manual', (_event, page) => {
        if (/^[a-z0-9-]+(#[a-z0-9-]+)?$/.test(String(page))) {
            launch('amethystora-manual', [String(page)]);
        }
    });

    app.whenReady().then(() => {
        session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        const page = pageArgument(process.argv);
        const folder = page ? null : folderArgument(process.argv);
        if (folder !== null) {
            start = folder;
            remember(folder);
        }
        createWindow(folder !== null ? 'browse' : page);
        watchTheme();
    });

    app.on('will-quit', () => stopFollowing());
    app.on('window-all-closed', () => app.quit());
}
