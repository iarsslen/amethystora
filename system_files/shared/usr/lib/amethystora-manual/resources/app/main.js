'use strict';

// The Amethystora Manual: the Markdown pages in /usr/share/amethystora/manual, in a window of its own.
//
// The window only ever shows the manual. It reads nothing but those pages, the keybindings they share
// with `ujust keybindings` and the palette of the current theme; every web link opens in the browser,
// and nothing the page asks for (camera, notifications, new windows) is granted.

const { app, BrowserWindow, clipboard, ipcMain, session, shell } = require('electron');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const SHARE = '/usr/share/amethystora';
const MANUAL = path.join(SHARE, 'manual');
const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
// Where amethystora-theme renders the current theme (CURRENT_DIR in /usr/lib/amethystora/theme/lib.sh)
const CURRENT = path.join(CONFIG_HOME, 'amethystora', 'current');

app.setPath('userData', path.join(CONFIG_HOME, 'amethystora-manual'));

// The page to open, `amethystora-manual keybindings` or `amethystora-manual updates#rollback`, as the
// route the window uses: keybindings, updates/rollback
function pageArgument(argv) {
    return (argv.slice(1).find((arg) => !arg.startsWith('-')) || '').replace('#', '/');
}

// A manual page, or the keybindings next to it. Nothing outside /usr/share/amethystora is readable.
function readPage(file) {
    const full = path.resolve(MANUAL, String(file));
    if (!full.startsWith(SHARE + path.sep) || path.extname(full) !== '.md') {
        throw new Error(`not a manual page: ${file}`);
    }
    return fs.promises.readFile(full, 'utf8');
}

// The colours of the current theme, or null before one has been applied
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

function openExternal(url) {
    if (/^(https?|mailto):/i.test(String(url))) {
        shell.openExternal(String(url));
    }
}

let win = null;

function createWindow(page) {
    const colors = palette();
    win = new BrowserWindow({
        width: 1180,
        height: 820,
        minWidth: 560,
        minHeight: 420,
        title: 'Amethystora Manual',
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
            timer = setTimeout(() => win?.webContents.send('palette', palette()), 300);
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
            win.webContents.send('open', page);
        }
    });

    app.on('web-contents-created', (_event, contents) => {
        contents.on('will-navigate', (event, url) => {
            event.preventDefault();
            openExternal(url);
        });
        contents.setWindowOpenHandler(({ url }) => {
            openExternal(url);
            return { action: 'deny' };
        });
    });

    ipcMain.handle('toc', async () => JSON.parse(await fs.promises.readFile(path.join(MANUAL, 'pages.json'), 'utf8')));
    ipcMain.handle('page', (_event, file) => readPage(file));
    ipcMain.handle('palette', () => palette());
    ipcMain.handle('open-external', (_event, url) => openExternal(url));
    ipcMain.handle('copy', (_event, text) => clipboard.writeText(String(text)));

    app.whenReady().then(() => {
        session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        createWindow(pageArgument(process.argv));
        watchTheme();
    });

    app.on('window-all-closed', () => app.quit());
}
