'use strict';

// Amethystora Updates: the system, the apps and the command-line tools brought up to date in a window of
// its own. It takes the place of upstream's System Update launcher, a terminal running `ujust update`;
// `ame update` stays, for the terminal.
//
// "Update now" starts uupd-manual.service: uupd, the updater the automatic updates run from uupd.timer,
// without the hardware checks that hold those back on a busy machine. It updates what `ame update`
// does, the system image, the Flatpaks of the machine and of everyone signed in, and Homebrew, and the
// polkit rule the uupd package ships lets it be started without a password. An update that is already
// running, the automatic one included, is followed instead of being started a second time.
//
// What the window shows while it runs is uupd's own JSON log, read from the journal, which Fedora opens
// to the members of wheel. For anyone else the window still knows from systemd whether an update is
// running and how it ended.
//
// The containers amethystora-pkg manages are each account's own, and uupd's own module for containers
// stays off (/etc/uupd/config.json). Once an update started here has finished, the window starts the
// account's amethystora-pkg-upgrade.service, which upgrades them, and follows the line of JSON it logs
// for each one. How that goes shows on the Containers step and nowhere else: a container that did not
// upgrade never makes the system's update a failed one.
//
// A machine started from an older version than the one it starts by default, which is what picking
// the second entry in the boot menu does, is said so, with the choice of keeping that version, which
// `bootc rollback` does after an administrator's password, or restarting into the newest.
//
// The window is locked down the way the Manual's is: it loads nothing but its own page, and the page
// can ask for nothing but what preload.js lists.

const { app, BrowserWindow, clipboard, ipcMain, session, shell } = require('electron');
const { execFile, spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');

const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
// Where amethystora-theme renders the current theme (CURRENT_DIR in /usr/lib/amethystora/theme/lib.sh)
const CURRENT = path.join(CONFIG_HOME, 'amethystora', 'current');

// The update started from here, then the automatic one
const MANUAL_UNIT = 'uupd-manual.service';
const UNITS = [MANUAL_UNIT, 'uupd.service'];
const TIMER = 'uupd.timer';
const RELEASES = 'https://github.com/iarsslen/amethystora/releases';
// Lines of what the updater said, kept for the page's details
const LOG_LENGTH = 400;
// The containers' upgrade, a unit of the account's own, and what it logs each container under
const PKG = '/usr/bin/amethystora-pkg';
const CONTAINERS_UNIT = 'amethystora-pkg-upgrade.service';
const CONTAINERS_LOG = 'amethystora-pkg-upgrade';

app.setPath('userData', path.join(CONFIG_HOME, 'amethystora-update'));

let win = null;
// The update being followed, or the last one that ended while the window was open
let update = null;
let journal = null;
// When "Update now" started one that has not been seen running yet
let requested = 0;
let ending = null;
let watching = false;
let timer = null;
// "Update now" was pressed, so the containers follow the update it started or found running
let containersWanted = false;
let containersJournal = null;

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

// A program that outlives this window, such as the Manual
function launch(file, args) {
    const child = spawn(file, args, { detached: true, stdio: 'ignore' });
    child.on('error', () => {});
    child.unref();
}

// How a program ended, never an exception: each caller has something to say about a program that
// is missing or failed
function run(file, args) {
    return new Promise((resolve) => {
        execFile(file, args, { timeout: 120000, maxBuffer: 16 * 1024 * 1024 }, (error, stdout, stderr) => {
            const code = !error ? 0 : Number.isInteger(error.code) ? error.code : -1;
            resolve({ code, stdout: String(stdout), stderr: String(stderr) });
        });
    });
}

function properties(text) {
    const values = {};
    for (const line of text.split('\n')) {
        const at = line.indexOf('=');
        if (at > 0) {
            values[line.slice(0, at)] = line.slice(at + 1);
        }
    }
    return values;
}

// systemctl --timestamp=unix: "@1758330764", or nothing for what has not happened since boot
function unixTime(value) {
    return /^@\d+$/.test(value || '') ? Number(value.slice(1)) * 1000 : null;
}

// --- This machine ----------------------------------------------------------------------------------

// rpm-ostree rather than bootc, whose status needs root. The deployment listed first is the one the
// next boot starts. When that is not the running one, it is either the update waiting for a restart,
// which is staged, or the newest version, when the machine was started from an older one at the boot
// menu: then `latest` is set, and `next` is not.
async function machine() {
    const { stdout } = await run('rpm-ostree', ['status', '--json']);
    let deployments = [];
    try {
        deployments = JSON.parse(stdout).deployments || [];
    } catch {
        return null;
    }
    const summary = (deployment) => deployment && {
        version: deployment.version || '',
        built: deployment.timestamp ? deployment.timestamp * 1000 : null,
        image: (deployment['container-image-reference'] || '').replace(/^[^:]+:(docker:\/\/)?/, ''),
    };
    const booted = deployments.findIndex((deployment) => deployment.booted);
    if (booted < 0) {
        return null;
    }
    const first = deployments[0];
    const older = booted > 0 && !first.staged && (first.timestamp || 0) > (deployments[booted].timestamp || 0);
    return {
        running: summary(deployments[booted]),
        next: booted > 0 && !older ? summary(first) : null,
        latest: older ? summary(first) : null,
        previous: older ? null : summary(deployments[booted + 1]) || null,
    };
}

// Makes the running version the one the machine starts by default. bootc reverses the queued rollback a
// start from the boot menu amounts to, and needs root, so polkit asks for an administrator's password.
async function keepVersion() {
    const { code, stderr } = await run('pkexec', ['/usr/bin/bootc', 'rollback']);
    const result = { machine: await machine() };
    // pkexec: 126 when the password was not given, 127 when it was refused
    if (code === 126 || code === 127) {
        result.declined = true;
    } else if (code !== 0) {
        result.error = stderr.trim().split('\n').pop() || 'This version could not be made the one the machine starts.';
    } else {
        result.kept = true;
    }
    return result;
}

// The containers amethystora-pkg manages: how many, and when the daily upgrade last ran over them
async function containers() {
    const { stdout } = await run(PKG, ['containers', 'list', '--json']);
    let list = [];
    try {
        list = JSON.parse(stdout);
    } catch {
        return { count: 0 };
    }
    const upgraded = list.map((item) => item.last_upgrade || 0).filter(Boolean);
    return { count: list.length, upgraded: upgraded.length ? Math.min(...upgraded) * 1000 : null };
}

async function automatic() {
    const [enabled, shown] = await Promise.all([
        run('systemctl', ['is-enabled', TIMER]),
        run('systemctl', ['show', TIMER, '--timestamp=unix', '-p', 'NextElapseUSecRealtime']),
    ]);
    const enabledNow = enabled.stdout.trim() === 'enabled';
    return { enabled: enabledNow, next: enabledNow ? unixTime(properties(shown.stdout).NextElapseUSecRealtime) : null };
}

// Both updater units as systemd has them, in the order of UNITS
async function units() {
    const { stdout } = await run('systemctl', ['show', ...UNITS, '--timestamp=unix', '-p', 'Id',
        '-p', 'ActiveState', '-p', 'SubState', '-p', 'Result', '-p', 'InvocationID',
        '-p', 'ExecMainStartTimestamp', '-p', 'ExecMainExitTimestamp']);
    return stdout.trim().split(/\n\s*\n/).map(properties).filter((unit) => unit.Id);
}

// A oneshot is "activating" for as long as it runs. One that failed and waits to be tried again,
// which uupd's units do a minute later, is not running.
function running(unit) {
    return ['activating', 'active', 'deactivating', 'reloading'].includes(unit.ActiveState) &&
        unit.SubState !== 'auto-restart';
}

// The last update that ended since the machine started, from here or by itself
function recent(list) {
    const ended = list
        .map((unit) => ({ unit: unit.Id, finished: unixTime(unit.ExecMainExitTimestamp), result: unit.Result }))
        .filter((unit) => unit.finished)
        .sort((a, b) => b.finished - a.finished);
    return ended[0] || null;
}

let lastContainers = null;

async function status() {
    const [info, auto, list, boxes] = await Promise.all([machine(), automatic(), units(), containers()]);
    lastContainers = boxes;
    return { machine: info, automatic: auto, recent: recent(list), containers: boxes, update };
}

// --- The update ------------------------------------------------------------------------------------

// uupd's modules by the title its progress gives them, in the order it runs them. uupd's own Distrobox
// module is off in /etc/uupd/config.json: the Distrobox step, Containers on the page, is the account's
// amethystora-pkg-upgrade.service, which follows an update started here.
const MODULES = ['System', 'Brew', 'Flatpak'];

// What a failed command was part of, from the context uupd gives it: "System Update", "Brew Upgrade",
// "System Apps", "Apps for User: <name>"
function moduleOf(context) {
    if (/^System Update/.test(context)) {
        return 'System';
    }
    if (/^Brew/.test(context)) {
        return 'Brew';
    }
    if (/Apps/.test(context)) {
        return 'Flatpak';
    }
    return /distrobox/i.test(context) ? 'Distrobox' : '';
}

// bootc reports its progress many times a second: the page hears of it a few times a second
let sendTimer = null;
function sendUpdate() {
    if (!sendTimer) {
        sendTimer = setTimeout(() => {
            sendTimer = null;
            send('update', update);
        }, 150);
    }
}

function log(text) {
    if (!text || text === update.log.at(-1)) {
        return;
    }
    update.log.push(text.length > 2000 ? `${text.slice(0, 2000)}…` : text);
    if (update.log.length > LOG_LENGTH) {
        update.log.splice(0, update.log.length - LOG_LENGTH);
    }
}

// One line of uupd's log: {"level":"INFO","msg":"Updating","title":"System","description":"Downloading",
// "overall":14,...}. Anything that is not JSON is systemd's own and says nothing new.
function readLine(line) {
    let entry;
    try {
        entry = JSON.parse(line);
    } catch {
        return;
    }
    if (!update || !entry || typeof entry !== 'object' || typeof entry.msg !== 'string') {
        return;
    }
    const { msg } = entry;
    const steps = update.steps;
    if (msg === 'Updating') {
        const title = String(entry.title || '');
        if (!(title in steps)) {
            steps[title] = { state: 'waiting' };
        }
        for (const [name, step] of Object.entries(steps)) {
            if (name !== title && step.state === 'running') {
                step.state = 'done';
            }
        }
        steps[title].state = 'running';
        steps[title].detail = String(entry.description || '');
        steps[title].percent = title === 'System' && Number.isFinite(entry.step_progress) ? entry.step_progress : null;
        update.overall = Number.isFinite(entry.overall) ? entry.overall : update.overall;
        log(`${title}: ${steps[title].detail}`);
    } else if (msg === 'System Updater module status' && entry.enabled === false && steps.System.state === 'waiting') {
        // No new image, or the system module turned off: nothing to download
        steps.System.state = 'current';
    } else if (msg === 'module_fail') {
        const context = String(entry.module || entry.output?.Context || '');
        const name = moduleOf(context);
        if (name && steps[name]) {
            steps[name].state = 'failed';
        }
        update.failures.push({ module: name, context, output: String(entry.output?.Stdout || '').trim().slice(-4000) });
        log(`Failed: ${context}${entry.cli ? ` (${entry.cli})` : ''}`);
    } else if (msg === 'Updates Completed Successfully' || msg === 'Updates finished with errors!') {
        update.ended = msg === 'Updates Completed Successfully' ? 'success' : 'errors';
        log(msg);
    } else if (msg.startsWith('{') || msg === 'scanned progress') {
        // bootc's own progress, many times a second: the "Updating" lines already carry it
        return;
    } else {
        if (entry.level === 'ERROR') {
            update.errors.push(msg);
        }
        const detail = typeof entry.error === 'string' ? `: ${entry.error}` : '';
        log(`${msg}${detail}`);
    }
    sendUpdate();
}

function stopJournal() {
    journal?.kill('SIGTERM');
    journal = null;
}

// Follow one run of an updater unit, from its first line on
function follow(unit) {
    stopJournal();
    clearTimeout(ending);
    ending = null;
    requested = 0;
    const previous = update;
    update = {
        unit: unit.Id,
        invocation: unit.InvocationID,
        automatic: unit.Id !== MANUAL_UNIT,
        // A unit that failed a minute ago and is being tried again by systemd
        retry: Boolean(previous && previous.unit === unit.Id && previous.state === 'failed' &&
            Date.now() - (previous.finished || 0) < 5 * 60000),
        started: unixTime(unit.ExecMainStartTimestamp) || Date.now(),
        state: 'running',
        steps: Object.fromEntries(MODULES.map((name) => [name, { state: 'waiting' }])),
        overall: null,
        failures: [],
        errors: [],
        log: [],
        ended: '',
        journal: false,
        // The containers' upgrade that follows an update started here, once it has started
        containers: null,
    };
    if (containersWanted && lastContainers?.count) {
        update.steps.Distrobox = { state: 'waiting' };
    }
    if (unit.InvocationID) {
        journal = spawn('journalctl', ['--quiet', '--follow', '--no-tail', '--output=cat',
            `_SYSTEMD_UNIT=${unit.Id}`, `_SYSTEMD_INVOCATION_ID=${unit.InvocationID}`]);
        journal.on('error', () => {});
        readline.createInterface({ input: journal.stdout }).on('line', (line) => {
            if (update && !update.journal) {
                // Something came through: the journal is readable here
                update.journal = true;
            }
            readLine(line);
        });
    }
    send('update', update);
}

// The unit has stopped: wait a moment for the journal to hand over its last lines, then say how it went
function end(unit) {
    if (ending) {
        return;
    }
    const current = update;
    ending = setTimeout(async () => {
        ending = null;
        stopJournal();
        if (update !== current) {
            return;
        }
        const succeeded = current.ended ? current.ended === 'success' : unit?.Result === 'success';
        current.state = succeeded && !current.failures.length ? 'done' : 'failed';
        current.finished = Date.now();
        // systemd runs a failed update again a minute later
        current.retrying = unit?.SubState === 'auto-restart';
        for (const step of Object.values(current.steps)) {
            if (step.state === 'running') {
                // uupd moves on to the next module whatever happens, so a module still running when it
                // stopped finished only if uupd got to the end
                step.state = current.ended ? 'done' : 'failed';
            }
            step.percent = null;
        }
        const startContainersNow = containersWanted && current.steps.Distrobox;
        containersWanted = false;
        send('status', await status());
        if (startContainersNow) {
            startContainers(current);
        }
    }, 1200);
}

// --- The containers ----------------------------------------------------------------------------------

function stopContainers() {
    containersJournal?.kill('SIGTERM');
    containersJournal = null;
}

// One line amethystora-pkg logged: {"container":"debian","state":"running","index":1,"count":2}, then
// the same with "ok" or "failed", and {"done":true,...} at the end, or {"done":true,"skipped":"..."}
function readContainers(current, line) {
    let entry;
    try {
        entry = JSON.parse(line);
    } catch {
        return;
    }
    const boxes = current.containers;
    const step = current.steps.Distrobox;
    if (!entry || typeof entry !== 'object' || !boxes || !step) {
        return;
    }
    if (entry.done) {
        boxes.state = entry.failed ? 'failed' : 'done';
        step.state = boxes.state;
        step.detail = '';
        stopContainers();
    } else if (typeof entry.container === 'string') {
        boxes.count = Number(entry.count) || boxes.count;
        if (entry.state === 'running') {
            boxes.current = entry.container;
            boxes.index = Number(entry.index) || boxes.done + 1;
            step.detail = `${entry.container} · ${boxes.index} of ${boxes.count}`;
        } else if (entry.state === 'failed') {
            boxes.failed.push(entry.container);
        }
        if (current === update) {
            const said = { running: 'upgrading', ok: 'up to date', failed: 'did not upgrade' }[entry.state] || entry.state;
            log(`Containers: ${entry.container}, ${said}`);
        }
    }
    sendUpdate();
}

// The account's own unit, which upgrades every container amethystora-pkg manages, followed through the
// line it logs for each one
async function startContainers(current) {
    const since = Math.floor(Date.now() / 1000) - 1;
    current.containers = { state: 'running', started: Date.now(), done: 0, count: lastContainers?.count || 0, failed: [] };
    current.steps.Distrobox = { state: 'running', detail: '' };
    stopContainers();
    containersJournal = spawn('journalctl', ['--user', '--quiet', '--follow', '--no-tail', '--output=cat',
        `--since=@${since}`, `SYSLOG_IDENTIFIER=${CONTAINERS_LOG}`]);
    containersJournal.on('error', () => {});
    readline.createInterface({ input: containersJournal.stdout }).on('line', (line) => readContainers(current, line));
    const { code } = await run('systemctl', ['--user', 'start', '--no-block', CONTAINERS_UNIT]);
    if (code !== 0) {
        current.containers.state = 'failed';
        current.steps.Distrobox.state = 'failed';
        stopContainers();
    }
    sendUpdate();
}

// A unit that ended without its last line, killed or failed before it could say: how systemd saw it
async function checkContainers() {
    const current = update;
    const boxes = current?.containers;
    if (boxes?.state !== 'running' || Date.now() - boxes.started < 5000) {
        return;
    }
    const { stdout } = await run('systemctl', ['--user', 'show', CONTAINERS_UNIT, '-p', 'ActiveState', '-p', 'Result']);
    const unit = properties(stdout);
    if (unit.ActiveState === 'inactive' || unit.ActiveState === 'failed') {
        // Its last line may still be on its way from the journal
        setTimeout(() => {
            if (boxes.state === 'running') {
                boxes.state = unit.Result === 'success' ? 'done' : 'failed';
                current.steps.Distrobox.state = boxes.state;
                stopContainers();
                sendUpdate();
            }
        }, 1500);
    }
}

async function watch() {
    if (watching) {
        return;
    }
    watching = true;
    try {
        const list = await units();
        // One that ended in the two seconds between two looks is only seen by when it started
        const candidate = list.find(running) ||
            (requested && list.find((unit) => unit.Id === MANUAL_UNIT &&
                (unixTime(unit.ExecMainStartTimestamp) || 0) >= requested - 2000));
        // A new run is followed once the last one has been told apart from it
        if (candidate && candidate.InvocationID !== update?.invocation && update?.state !== 'running') {
            follow(candidate);
        } else if (requested && Date.now() - requested > 30000) {
            // Started, and never seen running: systemd dropped the job
            requested = 0;
            containersWanted = false;
            send('status', await status());
        }
        if (update?.state === 'running') {
            const unit = list.find((item) => item.Id === update.unit);
            if (!unit || unit.InvocationID !== update.invocation || !running(unit)) {
                end(unit?.InvocationID === update.invocation ? unit : null);
            }
        }
        await checkContainers();
    } finally {
        watching = false;
    }
}

async function start() {
    // The containers are upgraded once the update this finds or starts has finished
    containersWanted = true;
    const list = await units();
    const active = list.find(running);
    if (active) {
        // Already running: follow that one
        await watch();
        return { started: true };
    }
    const { code, stderr } = await run('systemctl', ['start', '--no-block', MANUAL_UNIT]);
    if (code !== 0) {
        containersWanted = false;
        return { error: stderr.trim() || 'The update could not be started.' };
    }
    requested = Date.now();
    await watch();
    return { started: true };
}

// Enabling or disabling the timer is not something the uupd rule allows, so systemd asks polkit, and
// GNOME asks for the password
async function setAutomatic(on) {
    const { code, stderr } = await run('systemctl', [on ? 'enable' : 'disable', '--now', TIMER]);
    const result = { automatic: await automatic() };
    if (code !== 0) {
        result.error = /access denied|authenticat|not authorized/i.test(stderr)
            ? 'Left as it was: the password was not given.'
            : stderr.trim() || 'Automatic updates could not be changed.';
    }
    return result;
}

// --- The window ------------------------------------------------------------------------------------

function createWindow() {
    const colors = palette();
    win = new BrowserWindow({
        width: 980,
        height: 800,
        minWidth: 640,
        minHeight: 560,
        title: 'Amethystora Updates',
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
    win.loadFile(path.join(__dirname, 'index.html'));
    win.on('focus', () => send('focus'));
    win.on('closed', () => {
        win = null;
    });
}

// A theme switch replaces current/theme and rewrites current/theme.name, so the window follows it
// the way the rest of the desktop does
function watchTheme() {
    let pending = null;
    try {
        fs.watch(CURRENT, () => {
            clearTimeout(pending);
            pending = setTimeout(() => send('palette', palette()), 300);
        });
    } catch {
        // No theme applied yet: the window keeps the Amethystora colours
    }
}

if (!app.requestSingleInstanceLock()) {
    app.quit();
} else {
    app.on('second-instance', () => {
        if (win?.isMinimized()) {
            win.restore();
        }
        win?.focus();
    });

    app.on('web-contents-created', (_event, contents) => {
        contents.on('will-navigate', (event) => event.preventDefault());
        contents.setWindowOpenHandler(() => ({ action: 'deny' }));
    });

    ipcMain.handle('status', () => status());
    ipcMain.handle('palette', () => palette());
    ipcMain.handle('update', () => start());
    ipcMain.handle('automatic', (_event, on) => setAutomatic(Boolean(on)));
    ipcMain.handle('keep', () => keepVersion());
    // GNOME's own restart dialog, which gives open apps the chance to object
    ipcMain.handle('restart', () => launch('gnome-session-quit', ['--reboot']));
    ipcMain.handle('releases', () => shell.openExternal(RELEASES));
    ipcMain.handle('copy', (_event, text) => clipboard.writeText(String(text)));
    ipcMain.handle('manual', (_event, page) => {
        if (/^[a-z0-9-]+(#[a-z0-9-]+)?$/.test(String(page))) {
            launch('amethystora-manual', [String(page)]);
        }
    });

    app.whenReady().then(() => {
        session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        createWindow();
        watchTheme();
        // Picks up an update that starts by itself while the window is open, and notices when one ends
        watch();
        timer = setInterval(watch, 2000);
    });

    // The update is systemd's and carries on without the window
    app.on('will-quit', () => {
        clearInterval(timer);
        stopJournal();
        stopContainers();
    });
    app.on('window-all-closed', () => app.quit());
}
