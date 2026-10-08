'use strict';

// Amethystora Security: the security report and a virus scanner, in a window of its own. It takes the
// place of the report's terminal launcher and of ClamUI.
//
// The report is /usr/libexec/amethystora-security-status --json, the script `ame security status`
// prints, so the window and the terminal cannot disagree. A scan started here runs as the user and
// reads only what the user can: through clamd when its socket is open to the user, and with clamscan,
// which loads the signatures itself, when it is not. The whole machine is scanned by starting the
// weekly scan's own unit, which 50-amethystora-virus-scan.rules lets the person at the machine do
// without a password. What any of them finds is only reported, unless ON_DETECTION in
// /etc/amethystora/security.conf says to quarantine or delete it: then a scan started here hands what it
// found to /usr/libexec/amethystora-quarantine, as root, after an administrator's password.
//
// Network protection is Suricata's (/usr/libexec/amethystora-ips). What it blocked and noticed is read
// from the security watcher's network.json, which the members of wheel can read, and allowing a rule
// again goes through the helper, as root, after an administrator's password.
//
// What is installed outside Flatpak, the containers amethystora-pkg manages with the apps exported from
// them and what came from the AUR, is what `amethystora-pkg containers list --json` says, run as the
// user: the containers are each account's own. What each Flatpak can reach beyond its sandbox is what
// /usr/libexec/amethystora-app-permissions says, also run as the user, whose overrides are the ones
// that apply; taking back what the account granted one app is `flatpak override --user --reset`.
//
// Every security feature is a switch, and the Settings page lists them: the detection switches in
// /etc/amethystora/security.conf (`amethystora-security-config --list --json`) and what the image
// enforces from the start (`amethystora-hardening status --json`), both read as the user. A change runs
// the switch's own `ame security` command in a terminal, which says what it changes and asks; the page
// sends a key and one of the values this process read for it, and nothing else.
//
// The window is locked down the way the Manual's is: it loads nothing but its own page, and the page
// can ask for nothing but what preload.js lists. A command it offers to run in a terminal is looked up
// here, in the report this process read, and never taken from the page.

const { app, BrowserWindow, clipboard, dialog, ipcMain, session, shell } = require('electron');
const { execFile, spawn, spawnSync } = require('node:child_process');
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
const STATE_HOME = process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state');
// Where amethystora-theme renders the current theme (CURRENT_DIR in /usr/lib/amethystora/theme/lib.sh)
const CURRENT = path.join(CONFIG_HOME, 'amethystora', 'current');
// The scans started here: what was scanned, when, and what was found. Readable by this account only.
const HISTORY = path.join(STATE_HOME, 'amethystora', 'security-scans.json');
const HISTORY_LENGTH = 20;
// A scan that finds more than this keeps the first of them: enough to act on
const FINDINGS_KEPT = 500;

const REPORT = '/usr/libexec/amethystora-security-status';
const IN_TERMINAL = '/usr/libexec/amethystora-in-terminal';
const SIGNATURE_AGE = '/usr/libexec/amethystora-clamav-signature-age';
const SECURITY_CONFIG = '/usr/libexec/amethystora-security-config';
const HARDENING = '/usr/libexec/amethystora-hardening';
const AME = '/usr/bin/ame';
const QUARANTINE = '/usr/libexec/amethystora-quarantine';
const CLAMD_CONFIG = '/etc/clamd.d/scan.conf';
const CLAMD_SOCKET = '/run/clamd.scan/clamd.sock';
// The weekly scan of the whole machine, and the root-only file it writes its findings to
const MACHINE_SCAN = 'amethystora-clamav-scan';
const MACHINE_FINDINGS = '/var/log/amethystora-clamav-findings.log';
// Network protection: its helper, the rules allowed on this machine, and what the watcher keeps of its
// alerts (network.json, for wheel) and of its state (status.json, for everyone)
const IPS = '/usr/libexec/amethystora-ips';
const IPS_UNIT = 'amethystora-ips.service';
const IPS_ALLOWED = '/etc/amethystora/ips-allowed';
const NETWORK_EVENTS = '/var/lib/amethystora/security/network.json';
const WATCH_STATUS = '/var/lib/amethystora/security/status.json';
// The containers of other distributions, and whether the AUR is on for this account (ame apps aur)
const PKG = '/usr/bin/amethystora-pkg';
const AUR_FLAG = path.join(CONFIG_HOME, 'amethystora', 'aur');
// The AI agent, which a check that needs attention can be handed to, unless the account turned it off
const AGENT = '/usr/bin/amethystora-agent';
// What each Flatpak can reach beyond its sandbox, and Flatseal, where any of it is changed
const PERMISSIONS = '/usr/libexec/amethystora-app-permissions';
const FLATSEAL = 'com.github.tchx84.Flatseal';

// /var/home/<name> here, which is also how clamd's ExcludePath rules spell a home directory
const HOME = (() => {
    try {
        return fs.realpathSync(os.homedir());
    } catch {
        return os.homedir();
    }
})();

app.setPath('userData', path.join(CONFIG_HOME, 'amethystora-security'));

let win = null;
let report = null;
let switches = null;
let history = [];
let scan = null;

// The page to open: `amethystora-security scan` opens the virus scanner, `amethystora-security network`
// network protection, `amethystora-security apps` what each app can reach, `amethystora-security
// containers` what is installed outside Flatpak, `amethystora-security settings` every switch
function pageArgument(argv) {
    const page = argv.slice(1).find((arg) => !arg.startsWith('-'));
    return ['scan', 'network', 'apps', 'containers', 'settings'].includes(page) ? page : '';
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
function run(file, args, timeout = 120000) {
    return new Promise((resolve) => {
        execFile(file, args, { timeout, maxBuffer: 16 * 1024 * 1024 }, (error, stdout, stderr) => {
            const code = !error ? 0 : Number.isInteger(error.code) ? error.code : -1;
            resolve({ code, stdout: String(stdout), stderr: String(stderr) });
        });
    });
}

// --- The report ------------------------------------------------------------------------------------

async function readReport() {
    const [{ stdout, stderr }, agent] = await Promise.all([run(REPORT, ['--json']), run(AGENT, ['status'])]);
    try {
        report = JSON.parse(stdout);
        if (!Array.isArray(report.checks)) {
            throw new Error('no checks');
        }
    } catch {
        report = { image: t('unknown'), checks: [], error: stderr.trim() || t('The report could not be read.') };
    }
    report.checked = Date.now();
    // Whether a check can be handed to the AI agent: the agentic features are on for this account
    report.agent = agent.code === 0;
    return report;
}

// A check that needs attention, handed to the agent in a terminal by the title and sentence the report
// gave it, looked up here as `run` looks up a command. The agent reads the report itself, and the
// diagnose skill keeps it from changing anything until asked. The words around them are the agent's
// prompt, not the page's, and stay in English like the rest of it (amethystora-agent).
function diagnose(id) {
    const check = report?.agent && report.checks.find((item) => item.id === id && item.group !== 'optional');
    if (check) {
        launch(AGENT, ['diagnose', `The Amethystora security report (/usr/libexec/amethystora-security-status) flags "${check.title}": ${check.text}`]);
    }
}

// A check that needs attention, accepted on this machine, or shown again: `ame security allow report` in a
// terminal, which asks for the password. Only a check the report this process read gives in that state.
function accept(id, again) {
    const check = report?.checks.find((item) => item.id === id && item.group !== 'optional');
    if (!check || (again ? !check.accepted : !['check', 'off'].includes(check.state))) {
        return;
    }
    launch(IN_TERMINAL, again ? [AME, 'security', 'allow', 'report', check.id, 'remove'] : [AME, 'security', 'allow', 'report', check.id]);
}

// --- The switches ----------------------------------------------------------------------------------

async function readSwitches() {
    const [detection, enforced] = await Promise.all([run(SECURITY_CONFIG, ['--list', '--json']), run(HARDENING, ['status', '--json'])]);
    switches = { profile: 'custom', settings: [], hardening: [] };
    try {
        Object.assign(switches, JSON.parse(detection.stdout));
    } catch {
        switches.error = detection.stderr.trim() || t('{program} stopped with status {code}.', { program: 'amethystora-security-config', code: String(detection.code) });
    }
    try {
        switches.hardening = JSON.parse(enforced.stdout);
    } catch {
        switches.error ||= enforced.stderr.trim() || t('{program} stopped with status {code}.', { program: 'amethystora-hardening', code: String(enforced.code) });
    }
    return switches;
}

// The switch's own command, in a terminal: `ame security settings KEY VALUE` for a detection switch,
// `ame security NAME [ARGUMENT] on|off` for one of what the image enforces, and a profile. The value has to
// be one the list gave that switch; an empty one lets the command ask.
function change(kind, key, value, argument) {
    if (kind === 'profile') {
        if (['off', 'default'].includes(key)) {
            launch(IN_TERMINAL, [AME, 'security', 'profile', key]);
        }
        return;
    }
    if (kind === 'setting') {
        const entry = switches?.settings.find((item) => item.key === key);
        if (entry && (value === '' || entry.allowed.includes(value))) {
            launch(IN_TERMINAL, [AME, 'security', 'settings', entry.setting, ...(value ? [value] : [])]);
        }
        return;
    }
    const entry = switches?.hardening.find((item) => item.name === key);
    if (!entry || entry.fixed || !['on', 'off', ''].includes(value)) {
        return;
    }
    const chosen = entry.arguments?.find((item) => item.argument === argument);
    if (argument && !chosen) {
        return;
    }
    launch(IN_TERMINAL, [AME, 'security', entry.name, ...(chosen ? [chosen.argument] : []), ...(value ? [value] : [])]);
}

// --- The scanner -----------------------------------------------------------------------------------

// Whether the owner turned the virus scanner off (VIRUS_SCAN=off): then nothing scans, here either
function scannerOff() {
    const result = spawnSync(SECURITY_CONFIG, ['VIRUS_SCAN'], { encoding: 'utf8', timeout: 10000 });
    return (result.stdout || '').trim() === 'off';
}

// Days since the signatures were updated, or null when there are none to scan with
function signatureAge() {
    const result = spawnSync(SIGNATURE_AGE, { encoding: 'utf8', timeout: 10000 });
    if (result.status !== 0 && result.status !== 2) {
        return null;
    }
    return { days: Number(result.stdout.trim()), stale: result.status === 2 };
}

// clamd's socket is only reachable by users its directory lets through
function daemonReachable() {
    try {
        fs.accessSync(CLAMD_SOCKET, fs.constants.R_OK | fs.constants.W_OK);
        return true;
    } catch {
        return false;
    }
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

async function scanner() {
    const [service, timer] = await Promise.all([
        run('systemctl', ['show', `${MACHINE_SCAN}.service`, '--timestamp=unix', '-p', 'ActiveState',
            '-p', 'ExecMainStatus', '-p', 'InactiveExitTimestamp', '-p', 'InactiveEnterTimestamp']),
        run('systemctl', ['show', `${MACHINE_SCAN}.timer`, '--timestamp=unix', '-p', 'LastTriggerUSec']),
    ]);
    const unit = properties(service.stdout);
    let found = false;
    try {
        // /var/log is traversable, so the size of the root-only findings file shows even though what
        // is in it does not
        found = fs.statSync(MACHINE_FINDINGS).size > 0;
    } catch {
        // No findings file: the last scan was clean, or there has not been one
    }
    const finished = unixTime(unit.InactiveEnterTimestamp);
    const triggered = unixTime(properties(timer.stdout).LastTriggerUSec);
    return {
        signatures: signatureAge(),
        daemon: daemonReachable(),
        machine: {
            running: unit.ActiveState === 'activating' || unit.ActiveState === 'active',
            started: unixTime(unit.InactiveExitTimestamp),
            // systemd forgets when the service last ran at every boot, but not when its timer fired
            finished: Math.max(finished || 0, triggered || 0) || null,
            // Only known for a run since boot: 0 clean, 1 found, 2 no signatures, 3 signatures too old
            status: finished ? Number(unit.ExecMainStatus || 0) : null,
            found,
        },
    };
}

// --- Scans started here ----------------------------------------------------------------------------

function loadHistory() {
    try {
        const entries = JSON.parse(fs.readFileSync(HISTORY, 'utf8'));
        history = Array.isArray(entries) ? entries : [];
    } catch {
        history = [];
    }
    // A scan from before the page put what was scanned into words of its own named it in English
    for (const entry of history) {
        if (typeof entry?.label === 'string' && entry.targets?.length) {
            entry.label = labelFor(entry.targets);
        }
    }
}

// Written whole and then moved into place, so that a crash halfway leaves the old list rather than
// half of a new one. It names files and where they are, so it is this account's alone.
function saveHistory() {
    try {
        fs.mkdirSync(path.dirname(HISTORY), { recursive: true });
        const temporary = `${HISTORY}.${process.pid}`;
        fs.writeFileSync(temporary, JSON.stringify(history, null, 1), { mode: 0o600 });
        fs.renameSync(temporary, HISTORY);
    } catch {
        // Nowhere to keep it: the scan still shows, and is forgotten when the window closes
    }
}

// What the page is told about the scan running now
function progress() {
    return {
        id: scan.id,
        kind: scan.kind,
        label: scan.label,
        started: scan.started,
        files: scan.files,
        found: scan.found.length,
        current: scan.current,
        loading: scan.loading,
    };
}

// clamd reads its ExcludePath rules itself, and clamscan has to be handed the same list. A rule such
// as ^/var/home/[^/]+/\.cache/ names what is inside the cache, and clamscan matches the directory.
function exclusions() {
    let text = '';
    try {
        text = fs.readFileSync(CLAMD_CONFIG, 'utf8');
    } catch {
        return [];
    }
    return [...text.matchAll(/^ExcludePath\s+(\S+)\s*$/gm)]
        .map(([, rule]) => `--exclude-dir=${rule.replace(/\/$/, '(/|$)')}`);
}

// One line per file: "<path>: OK", or "<path>: <signature> FOUND"
const RESULT = /^(.*): (?:(\S+) FOUND|OK)$/;

function readLine(line) {
    if (!scan) {
        return;
    }
    if (/ ERROR$/.test(line)) {
        scan.errors += 1;
        return;
    }
    const match = RESULT.exec(line);
    if (!match) {
        // Empty files, links it does not follow, what it leaves out
        return;
    }
    scan.loading = false;
    scan.files += 1;
    scan.current = match[1];
    if (match[2] && scan.found.length < FINDINGS_KEPT) {
        scan.found.push({ path: match[1], signature: match[2] });
    }
    if (!scan.timer) {
        scan.timer = setTimeout(() => {
            if (scan) {
                scan.timer = null;
                send('scan-progress', progress());
            }
        }, 150);
    }
}

// What this machine does with what a scan finds: report, quarantine or delete
function detection() {
    const result = spawnSync(SECURITY_CONFIG, ['ON_DETECTION'], { encoding: 'utf8', timeout: 10000 });
    const mode = (result.stdout || '').trim();
    return ['quarantine', 'delete'].includes(mode) ? mode : 'report';
}

// The files are the user's and the quarantine is root's, so this is the one step that asks for a
// password, once for the whole scan. The helper scans each file again before it does anything, and
// says what happened to each: quarantined, deleted, clean, failed. Declining the password leaves them.
async function act(entry) {
    entry.detection = detection();
    if (entry.detection === 'report' || !entry.found.length) {
        return;
    }
    const { code, stdout } = await run('pkexec', [QUARANTINE, 'act', ...entry.found.map((item) => item.path)], 600000);
    const outcomes = new Map();
    for (const line of stdout.split('\n')) {
        const [outcome, , file] = line.split('\t');
        if (file) {
            outcomes.set(file, outcome);
        }
    }
    // pkexec: 126 when the password was not given, 127 when it was refused
    const nobody = code === 126 || code === 127 ? 'declined' : 'failed';
    for (const item of entry.found) {
        item.outcome = outcomes.get(item.path) || nobody;
    }
}

async function finishScan(code, errors) {
    clearTimeout(scan.timer);
    // Some files unreadable is exit status 2 as well, so only a scan that got nowhere failed
    const failed = !scan.stopped && scan.files === 0 && code !== 0 && code !== 1;
    const entry = {
        id: scan.id,
        kind: scan.kind,
        label: scan.label,
        single: scan.single,
        targets: scan.targets,
        started: scan.started,
        seconds: Math.round((Date.now() - scan.started) / 1000),
        files: scan.files,
        errors: scan.errors,
        signatures: scan.signatures,
        found: scan.found,
        stopped: scan.stopped,
        // What it found is what matters, even of a scan stopped before the end
        status: scan.found.length || code === 1 ? 'found' : scan.stopped ? 'stopped' : failed ? 'failed' : 'clean',
    };
    if (failed) {
        entry.message = errors.find((line) => line.trim()) || t('The scanner stopped with status {code}.', { code: String(code) });
    }
    await act(entry);
    scan = null;
    history.unshift(entry);
    history.splice(HISTORY_LENGTH);
    saveHistory();
    send('scan-finished', entry);
}

function startScanner(daemon) {
    // Paths are absolute, so none of them can be taken for an option
    const child = daemon
        // --fdpass opens each file here, as the user, and hands clamd the open file: clamd runs as its
        // own user and could not read into a home directory itself
        ? spawn('clamdscan', ['--fdpass', '--multiscan', '--no-summary', ...scan.targets])
        : spawn('clamscan', ['--recursive', '--no-summary', ...exclusions(), ...scan.targets]);
    const errors = [];
    let ended = false;
    scan.child = child;
    // clamscan says nothing until it has loaded every signature, which takes a while
    scan.loading = !daemon;
    readline.createInterface({ input: child.stdout }).on('line', readLine);
    readline.createInterface({ input: child.stderr }).on('line', (line) => errors.push(line));
    const end = (code) => {
        if (ended) {
            return;
        }
        ended = true;
        // clamd not running, or its socket refusing the connection: scan without it instead
        if (daemon && !scan.stopped && scan.files === 0 && code !== 0 && code !== 1) {
            startScanner(false);
            return;
        }
        finishScan(code, errors);
    };
    child.on('error', (error) => {
        errors.push(error.message);
        end(-1);
    });
    child.on('close', (code) => end(code ?? -1));
}

function startScan(kind, targets, label) {
    if (scan) {
        return { error: t('A scan is already running.') };
    }
    if (scannerOff()) {
        return { error: t('The virus scanner is turned off. Turn it on in Settings first.') };
    }
    const signatures = signatureAge();
    if (!signatures) {
        return {
            error: t('There are no virus signatures to scan with yet. They download on their own soon after the machine is installed.'),
        };
    }
    let single = false;
    try {
        single = targets.length === 1 && fs.statSync(targets[0]).isFile();
    } catch {
        // Gone already: the scanner says so
    }
    scan = {
        id: `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`,
        kind,
        label,
        single,
        targets,
        started: Date.now(),
        signatures,
        files: 0,
        errors: 0,
        found: [],
        current: '',
        loading: false,
        stopped: false,
        timer: null,
        child: null,
    };
    startScanner(daemonReachable());
    return { started: true, progress: progress() };
}

// What a scan is of, as the values its sentences choose their words by: the home folder, a number of
// files and folders, or one of them by its name
function labelFor(targets) {
    if (targets.length > 1) {
        return { place: 'items', items: targets.length };
    }
    return targets[0] === HOME ? { place: 'home' } : { place: 'named', name: path.basename(targets[0]) || targets[0] };
}

// Files and folders the page names, dropped onto the window: only absolute paths that are there
function existing(paths) {
    return (Array.isArray(paths) ? paths : [])
        .map((item) => String(item))
        .filter((item) => path.isAbsolute(item) && fs.existsSync(item));
}

// --- Network protection ----------------------------------------------------------------------------

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (error) {
        return error.code === 'EACCES' ? { denied: true } : null;
    }
}

// What it blocked and noticed, newest first, and what the page shows beside that: whether Suricata is
// running, and when its rules were last built
async function network() {
    const events = readJson(NETWORK_EVENTS);
    let allowed = [];
    try {
        allowed = fs.readFileSync(IPS_ALLOWED, 'utf8').split('\n').filter((line) => /^\d+$/.test(line)).map(Number);
    } catch {
        // Nothing allowed on this machine
    }
    const { stdout } = await run('systemctl', ['is-active', IPS_UNIT]);
    return {
        // A machine where nothing has gone off yet has no file; one this account may not read says so
        readable: !events?.denied,
        events: Array.isArray(events) ? events : [],
        allowed,
        running: stdout.trim() === 'active',
        rules: readJson(WATCH_STATUS)?.network?.rules ?? null,
    };
}

// Leaves one rule out on this machine, which asks for an administrator's password. Only a rule that
// actually went off here, as network.json says, never one the page names out of nowhere.
async function allowRule(rule) {
    const events = readJson(NETWORK_EVENTS);
    if (!/^\d{1,10}$/.test(rule) || !Array.isArray(events) || !events.some((event) => String(event.sid) === rule)) {
        return { error: t('That rule is not one network protection used on this machine.') };
    }
    const { code, stdout, stderr } = await run('pkexec', [IPS, 'allow', rule], 600000);
    if (code === 0) {
        return { allowed: true };
    }
    // pkexec: 126 when the password was not given, 127 when it was refused
    if (code === 126 || code === 127) {
        return { declined: true };
    }
    return { error: (stderr || stdout).trim().split('\n').pop() || t('The rule could not be allowed (status {code}).', { code: String(code) }) };
}

// --- Installed outside Flatpak ---------------------------------------------------------------------

async function inventory() {
    const { code, stdout, stderr } = await run(PKG, ['containers', 'list', '--json'], 60000);
    let containers = [];
    try {
        containers = JSON.parse(stdout);
    } catch {
        return {
            containers: [],
            aur: fs.existsSync(AUR_FLAG),
            error: (stderr || '').trim() || t('{program} stopped with status {code}.', { program: 'amethystora-pkg', code: String(code) }),
        };
    }
    return { containers: Array.isArray(containers) ? containers : [], aur: fs.existsSync(AUR_FLAG) };
}

// --- App permissions -------------------------------------------------------------------------------

let permissions = [];

// Run as the user, whose overrides are the ones that apply
async function readPermissions() {
    const { code, stdout, stderr } = await run(PERMISSIONS, ['--json'], 120000);
    try {
        const list = JSON.parse(stdout);
        permissions = Array.isArray(list) ? list : [];
        return { apps: permissions };
    } catch {
        permissions = [];
        return {
            apps: [],
            error: (stderr || '').trim() || t('{program} stopped with status {code}.', { program: 'amethystora-app-permissions', code: String(code) }),
        };
    }
}

// Takes back everything this account granted one app: its own overrides, never the machine's or the
// image's. Only for an app the list just read says has some.
async function resetPermissions(id) {
    const entry = permissions.find((item) => item.app === id && item.user_overrides);
    if (!entry) {
        return { error: t('That app has nothing granted by this account to take back.') };
    }
    const { code, stderr } = await run('flatpak', ['override', '--user', '--reset', entry.app]);
    return code === 0
        ? readPermissions()
        : { error: stderr.trim() || t('{program} stopped with status {code}.', { program: 'flatpak override', code: String(code) }) };
}

// --- The window ------------------------------------------------------------------------------------

function createWindow(page) {
    const colors = palette();
    win = new BrowserWindow({
        width: 1180,
        height: 820,
        minWidth: 720,
        minHeight: 540,
        title: t('Amethystora Security'),
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
    // Back from a terminal where something was fixed: the page checks again if the report is old
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
        const page = pageArgument(argv);
        if (page) {
            send('open', page);
        }
    });

    app.on('web-contents-created', (_event, contents) => {
        // A file dropped on the window is scanned, never opened in it
        contents.on('will-navigate', (event) => event.preventDefault());
        contents.setWindowOpenHandler(() => ({ action: 'deny' }));
    });

    // Asked for once, by preload.js, before the page's scripts run
    ipcMain.on('locale', (event) => {
        event.returnValue = LOCALE;
    });
    ipcMain.handle('report', () => readReport());
    ipcMain.handle('scanner', () => scanner());
    ipcMain.handle('history', () => ({ home: HOME, entries: history, running: scan ? progress() : null }));
    ipcMain.handle('palette', () => palette());

    ipcMain.handle('scan-home', () => startScan('home', [HOME], labelFor([HOME])));
    ipcMain.handle('scan-pick', async (_event, folders) => {
        const { canceled, filePaths } = await dialog.showOpenDialog(win, {
            title: folders ? t('Scan folders') : t('Scan files'),
            buttonLabel: t('Scan'),
            defaultPath: HOME,
            properties: [folders ? 'openDirectory' : 'openFile', 'multiSelections'],
        });
        if (canceled || !filePaths.length) {
            return { canceled: true };
        }
        return startScan('pick', filePaths, labelFor(filePaths));
    });
    ipcMain.handle('scan-paths', (_event, paths) => {
        const targets = existing(paths);
        if (!targets.length) {
            return { error: t('Nothing that was dropped is a file or folder on this machine.') };
        }
        return startScan('pick', targets, labelFor(targets));
    });
    ipcMain.handle('scan-again', (_event, id) => {
        const entry = history.find((item) => item.id === id);
        if (!entry) {
            return { error: t('That scan is no longer in the list.') };
        }
        const targets = existing(entry.targets);
        if (!targets.length) {
            return {
                error: t('{place, select, home {Your home folder is not there any more.} items {{items, plural, one {# item is} other {# items are}} not there any more.} other {{name} is not there any more.}}', entry.label),
            };
        }
        return startScan(entry.kind, targets, entry.label);
    });
    ipcMain.handle('scan-stop', () => {
        if (scan?.child) {
            scan.stopped = true;
            scan.child.kill('SIGTERM');
        }
    });
    // Starting the unit is all the polkit rule allows without a password; stopping it is not
    ipcMain.handle('scan-machine', async () => {
        if (scannerOff()) {
            return { error: t('The virus scanner is turned off. Turn it on in Settings first.') };
        }
        const { code, stderr } = await run('systemctl', ['start', '--no-block', `${MACHINE_SCAN}.service`]);
        return code === 0 ? { started: true } : { error: stderr.trim() || t('The scan could not be started.') };
    });

    ipcMain.handle('network', () => network());
    ipcMain.handle('network-allow', (_event, rule) => allowRule(String(rule)));

    ipcMain.handle('inventory', () => inventory());
    ipcMain.handle('permissions', () => readPermissions());
    ipcMain.handle('permissions-reset', (_event, id) => resetPermissions(String(id)));
    ipcMain.handle('flatseal', () => launch('flatpak', ['run', FLATSEAL]));
    // Upgrading asks the containers' package managers, whose output is worth reading, so in a terminal
    ipcMain.handle('containers-upgrade', () => launch(IN_TERMINAL, [PKG, 'upgrade-all']));

    ipcMain.handle('dismiss', (_event, id) => {
        const entry = history.find((item) => item.id === id);
        if (entry) {
            entry.dismissed = true;
            saveHistory();
        }
    });
    ipcMain.handle('run', (_event, id) => {
        const check = report?.checks.find((item) => item.id === id);
        if (check?.command) {
            launch(IN_TERMINAL, check.command.split(/\s+/));
        }
    });
    ipcMain.handle('diagnose', (_event, id) => diagnose(String(id)));
    ipcMain.handle('accept', (_event, id, again) => accept(String(id), Boolean(again)));
    ipcMain.handle('switches', () => readSwitches());
    ipcMain.handle('change', (_event, kind, key, value, argument) =>
        change(String(kind), String(key), String(value ?? ''), argument ? String(argument) : ''));
    ipcMain.handle('show-in-files', (_event, file) => {
        if (history.some((entry) => entry.found?.some((item) => item.path === file)) && fs.existsSync(file)) {
            shell.showItemInFolder(file);
        }
    });
    ipcMain.handle('copy', (_event, text) => clipboard.writeText(String(text)));
    ipcMain.handle('manual', (_event, page) => {
        if (/^[a-z0-9-]+(#[a-z0-9-]+)?$/.test(String(page))) {
            launch('amethystora-manual', [String(page)]);
        }
    });

    app.whenReady().then(() => {
        session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        loadHistory();
        createWindow(pageArgument(process.argv));
        watchTheme();
    });

    // A scan belongs to the window that started it; the whole-machine scan is systemd's and carries on
    app.on('will-quit', () => scan?.child?.kill('SIGTERM'));
    app.on('window-all-closed', () => app.quit());
}
