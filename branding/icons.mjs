// The Amethystora icon packs: one set of glyphs (icons/glyphs.mjs), each icon in colours of its own, drawn three ways.
//
//   Glass    the glyph filled with its gradient, its details lighter, a glass sheen inside and a shadow below
//   Neon     the glyph's outline and its details lit in a three-colour prism, glowing
//   Duotone  the glyph in its gradient and its details in a contrasting one
//
// They cover Amethystora's apps, GNOME's and the system's, folders, file types, devices and categories. Every other
// maker's app keeps the icon it ships with, which the packs reach through Inherits (hicolor), and the symbolic icons
// of the top bar and the menus are Adwaita's.
//
//   node branding/icons.mjs            writes the packs into system_files/shared/usr/share/icons
//   node branding/icons.mjs --preview  also writes a sheet of every icon in every pack, and prints where
import {mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DRAW} from './icons/glyphs.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const ICONS = join(ROOT, 'system_files/shared/usr/share/icons');

// The colours: each ramp is the gradient the glyph is filled with, the prism Neon lights it in, and the contrasting
// gradient Duotone draws its details in
const RAMPS = {
    sunset: [['#ffb347', '#ff5f6d'], ['#ffe259', '#ffa751', '#ff5f6d'], ['#5be7ff', '#4facfe']],
    ocean: [['#36d1dc', '#5b86e5'], ['#a8ff78', '#36d1dc', '#5b86e5'], ['#ffd86f', '#fc6262']],
    mint: [['#38ef7d', '#11998e'], ['#f9f871', '#38ef7d', '#11998e'], ['#f6d365', '#fda085']],
    orchid: [['#ff6ec4', '#7873f5'], ['#ffd3a5', '#ff6ec4', '#7873f5'], ['#d4fc79', '#96e6a1']],
    amber: [['#ffd200', '#f7971e'], ['#fff6b7', '#ffd200', '#f7971e'], ['#6a11cb', '#2575fc']],
    dusk: [['#b06ab3', '#4568dc'], ['#ff9a9e', '#b06ab3', '#4568dc'], ['#fddb92', '#f6d365']],
    emerald: [['#00f260', '#0575e6'], ['#e0ff4f', '#00f260', '#0575e6'], ['#ffe29f', '#ffa99f']],
    flame: [['#fc466b', '#3f5efb'], ['#ffb199', '#fc466b', '#3f5efb'], ['#c2e9fb', '#a1c4fd']],
    sky: [['#00f2fe', '#4facfe'], ['#c2ffd8', '#00f2fe', '#4facfe'], ['#ffecd2', '#fcb69f']],
    blossom: [['#f093fb', '#f5576c'], ['#ffe0f7', '#f093fb', '#f5576c'], ['#fffde4', '#fbd786']],
    grape: [['#da22ff', '#9733ee'], ['#ffb3ff', '#da22ff', '#9733ee'], ['#f9f871', '#7df9c4']],
    lagoon: [['#00c6ff', '#0072ff'], ['#8fffef', '#00c6ff', '#0072ff'], ['#ffe985', '#fa742b']],
    coral: [['#ff9966', '#ff5e62'], ['#ffd194', '#ff9966', '#ff5e62'], ['#a1ffce', '#5ee7df']],
    lime: [['#a8e063', '#2fb36d'], ['#f9f871', '#a8e063', '#2fb36d'], ['#ffc3f8', '#f093fb']],
    cherry: [['#ff512f', '#dd2476'], ['#ffc371', '#ff512f', '#dd2476'], ['#fdfcfb', '#b8f1ff']],
    royal: [['#4776e6', '#8e54e9'], ['#7ee8fa', '#4776e6', '#8e54e9'], ['#ffd3a5', '#fd6585']],
    aqua: [['#43e97b', '#38f9d7'], ['#f9f871', '#43e97b', '#38f9d7'], ['#5f72ff', '#9a5cff']],
    peach: [['#f6d365', '#fda085'], ['#fff1b8', '#f6d365', '#fda085'], ['#7f7fd5', '#86a8e7']],
    magenta: [['#ec008c', '#fc6767'], ['#ffb3d9', '#ec008c', '#fc6767'], ['#fff6b7', '#f6d365']],
    indigo: [['#667eea', '#764ba2'], ['#a1c4fd', '#667eea', '#8e6bd8'], ['#f9f871', '#ffc371']],
    ice: [['#89f7fe', '#66a6ff'], ['#e0fcff', '#89f7fe', '#66a6ff'], ['#ff9a9e', '#fecfef']],
    gold: [['#f7b733', '#fc4a1a'], ['#fff3b0', '#f7b733', '#fc4a1a'], ['#89f7fe', '#66a6ff']],
};

// Every icon: its name, the drawing, the ramp, and the other names it answers to. A file type is named as
// shared-mime-info's generic icons are, so it covers every type that falls back on that name.
const SET = {
    apps: [
        ['amethystora-docs', 'manual', 'dusk'],
        ['amethystora-security-status', 'security', 'emerald'],
        ['amethystora-control', 'control', 'flame'],
        ['amethystora-update', 'update', 'lagoon', ['system-software-update', 'system-software-install', 'software-update-available']],
        ['amethystora-logs', 'logs', 'aqua', ['utilities-log-viewer', 'org.gnome.Logs']],
        ['amethystora-notes', 'notes', 'gold', ['accessories-notes']],
        ['amethystora-backups', 'backups', 'royal'],
        ['amethystora-community', 'community', 'magenta'],
        ['org.gnome.Nautilus', 'files', 'sunset', ['system-file-manager']],
        ['org.gnome.Settings', 'settings', 'ocean', ['preferences-system', 'preferences-desktop', 'gnome-control-center']],
        ['org.gnome.Ptyxis', 'terminal', 'mint', ['utilities-terminal', 'org.gnome.Terminal', 'org.gnome.Console']],
        ['org.gnome.SystemMonitor', 'monitor', 'cherry', ['utilities-system-monitor', 'gnome-system-monitor']],
        ['org.gnome.DiskUtility', 'drive', 'indigo', ['disk-utility', 'gnome-disks']],
        ['org.gnome.Tour', 'compass', 'peach'],
        ['org.gnome.tweaks', 'wrench', 'lime'],
        ['org.freedesktop.MalcontentControl', 'guardian', 'grape'],
        ['firewall-config', 'wall', 'coral'],
        ['input-remapper', 'keyboard', 'dusk'],
        ['gnome-color-manager', 'palette', 'blossom', ['preferences-color']],
        ['rygel', 'broadcast', 'lagoon'],
        ['help-browser', 'lifebuoy', 'cherry', ['org.gnome.Yelp', 'help-contents', 'yelp']],
        ['org.gnome.Calculator', 'calculator', 'amber', ['accessories-calculator', 'gnome-calculator']],
        ['org.gnome.Calendar', 'calendar', 'cherry', ['office-calendar']],
        ['org.gnome.Characters', 'smile', 'peach', ['accessories-character-map']],
        ['org.gnome.Connections', 'remote', 'royal', ['preferences-desktop-remote-desktop']],
        ['org.gnome.Contacts', 'contact', 'coral', ['office-address-book']],
        ['org.gnome.FileRoller', 'archive', 'gold', ['file-roller']],
        ['org.gnome.Firmware', 'chip', 'lime'],
        ['org.gnome.Loupe', 'photo', 'magenta', ['image-viewer', 'multimedia-photo-viewer']],
        ['org.gnome.Maps', 'map', 'aqua'],
        ['org.gnome.Papers', 'pages', 'flame', ['document-viewer', 'org.gnome.Evince']],
        ['org.gnome.Showtime', 'play', 'grape', ['multimedia-video-player', 'video-player', 'org.gnome.Totem']],
        ['org.gnome.SimpleScan', 'scanner', 'ice'],
        ['org.gnome.Snapshot', 'camera', 'indigo', ['accessories-camera']],
        ['org.gnome.Decibels', 'notes2', 'blossom', ['multimedia-audio-player', 'audio-player']],
        ['org.gnome.TextEditor', 'editor', 'orchid', ['accessories-text-editor', 'text-editor', 'org.gnome.gedit']],
        ['org.gnome.Weather', 'weather', 'sky'],
        ['org.gnome.baobab', 'pie', 'gold', ['disk-usage-analyzer', 'baobab']],
        ['org.gnome.clocks', 'alarm', 'lagoon', ['preferences-system-time']],
        ['org.gnome.font-viewer', 'letter', 'dusk', ['preferences-desktop-font']],
        ['org.gnome.Builder', 'code', 'royal'],
        ['application-default-icon', 'app', 'royal'],
    ],
    places: [
        ['folder', 'folder', 'sky', ['inode-directory']],
        ['folder-documents', 'folder-documents', 'sky'],
        ['folder-download', 'folder-download', 'sky'],
        ['folder-music', 'folder-music', 'sky'],
        ['folder-pictures', 'folder-pictures', 'sky'],
        ['folder-videos', 'folder-videos', 'sky'],
        ['folder-templates', 'folder-templates', 'sky'],
        ['folder-publicshare', 'folder-publicshare', 'sky'],
        ['user-desktop', 'folder-desktop', 'sky', ['folder-desktop']],
        ['folder-remote', 'folder-remote', 'sky'],
        ['folder-locked', 'folder-locked', 'sky'],
        ['user-home', 'home', 'peach', ['folder-home']],
        ['user-trash', 'trash', 'ice'],
        ['user-trash-full', 'trash-full', 'ice'],
        ['network-server', 'server', 'indigo', ['network-workgroup']],
        ['user-bookmarks', 'bookmark', 'gold'],
        ['avatar-default', 'avatar', 'orchid'],
    ],
    mimetypes: [
        ['text-x-generic', 'text', 'blossom'],
        ['text-x-script', 'script', 'mint'],
        ['text-html', 'html', 'lagoon'],
        ['application-x-executable', 'app', 'royal'],
        ['image-x-generic', 'image', 'sunset'],
        ['audio-x-generic', 'audio', 'orchid'],
        ['video-x-generic', 'video', 'grape'],
        ['package-x-generic', 'package', 'gold'],
        ['application-pdf', 'pdf', 'cherry'],
        ['x-office-document', 'document', 'ocean'],
        ['x-office-spreadsheet', 'spreadsheet', 'emerald'],
        ['x-office-presentation', 'presentation', 'coral'],
        ['x-office-drawing', 'drawing', 'magenta'],
        ['x-office-address-book', 'contact', 'coral'],
        ['x-office-calendar', 'calendar', 'cherry', ['text-calendar']],
        ['font-x-generic', 'font', 'dusk'],
        ['text-x-generic-template', 'template', 'ice'],
        ['application-x-addon', 'addon', 'lime'],
        ['application-x-firmware', 'chip', 'lime'],
        ['application-x-cd-image', 'disc', 'indigo'],
    ],
    devices: [
        ['computer', 'computer', 'ocean', ['video-display']],
        ['computer-laptop', 'laptop', 'royal'],
        ['phone', 'phone', 'grape', ['smartphone']],
        ['drive-harddisk', 'drive', 'indigo', ['drive-harddisk-system', 'drive-multidisk']],
        ['drive-removable-media', 'usb', 'gold', ['drive-harddisk-usb', 'media-removable']],
        ['media-flash', 'card', 'amber'],
        ['media-optical', 'disc', 'ice', ['drive-optical']],
        ['camera-photo', 'camera', 'indigo'],
        ['camera-web', 'webcam', 'lagoon'],
        ['printer', 'printer', 'coral'],
        ['scanner', 'scanner', 'ice'],
        ['input-keyboard', 'keyboard', 'dusk'],
        ['input-mouse', 'mouse', 'sky'],
        ['input-gaming', 'gamepad', 'flame'],
        ['input-tablet', 'tablet', 'orchid'],
        ['audio-headphones', 'headphones', 'magenta', ['audio-headset']],
        ['audio-speakers', 'speaker', 'sunset', ['audio-card']],
        ['audio-input-microphone', 'microphone', 'cherry'],
        ['network-wired', 'plug', 'mint'],
    ],
    categories: [
        ['applications-system', 'settings', 'ocean'],
        ['applications-utilities', 'wrench', 'lime', ['applications-accessories']],
        ['applications-multimedia', 'play', 'grape'],
        ['applications-graphics', 'palette', 'blossom'],
        ['applications-internet', 'globe', 'lagoon'],
        ['applications-office', 'document', 'ocean'],
        ['applications-development', 'code', 'royal'],
        ['applications-games', 'gamepad', 'flame'],
        ['applications-science', 'flask', 'aqua'],
        ['applications-education', 'cap', 'peach'],
        ['applications-other', 'app', 'royal'],
    ],
};

const CONTEXTS = {apps: 'Applications', places: 'Places', mimetypes: 'MimeTypes', devices: 'Devices', categories: 'Categories'};

const mixWhite = (hex, s) => '#' + [1, 3, 5].map(i => Math.round(parseInt(hex.slice(i, i + 2), 16) * (1 - s) + 255 * s)
    .toString(16).padStart(2, '0')).join('');
const gradient = (id, colours) => `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1">${
    colours.map((c, i) => `<stop offset="${i / (colours.length - 1)}" stop-color="${c}"/>`).join('')}</linearGradient>`;
const shadow = (id, colour, opacity, dy, blur) => `<filter id="${id}" x="-25%" y="-25%" width="150%" height="150%">` +
    `<feDropShadow dx="0" dy="${dy}" stdDeviation="${blur}" flood-color="${colour}" flood-opacity="${opacity}"/></filter>`;
const svg = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 256 256"><defs>${defs}</defs>${body}</svg>\n`;

const PACKS = {
    glass: {
        name: 'Amethystora Glass',
        comment: 'Amethystora\'s own icons, each in its own gradient with a glass sheen',
        draw: (glyph, [fill]) => {
            const soft = fill.map(c => mixWhite(c, 0.55));
            return svg(gradient('g', fill) + gradient('h', soft) +
                '<linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset="0.55" stop-color="#fff" stop-opacity="0"/></linearGradient>' +
                `<mask id="m">${glyph({ink: '#fff', soft: '#fff'})}</mask>` + shadow('f', '#1a0b2e', 0.55, 10, 9),
            `<g filter="url(#f)">${glyph({ink: 'url(#g)', soft: 'url(#h)'})}</g>` +
                '<rect width="256" height="150" fill="url(#s)" fill-opacity="0.55" mask="url(#m)"/>');
        },
    },
    neon: {
        name: 'Amethystora Neon',
        comment: 'Amethystora\'s own icons, their outlines lit in colours of their own',
        draw: (glyph, [, prism]) => svg(gradient('g', prism) +
            // The body's outline: its alpha eroded and taken from it leaves a ring, blurred twice under itself
            '<filter id="n" x="-25%" y="-25%" width="150%" height="150%"><feMorphology in="SourceAlpha" operator="erode" radius="6" result="inner"/>' +
            '<feComposite in="SourceGraphic" in2="inner" operator="out" result="ring"/><feGaussianBlur in="ring" stdDeviation="5" result="glow"/>' +
            '<feMerge><feMergeNode in="glow"/><feMergeNode in="glow"/><feMergeNode in="ring"/></feMerge></filter>' +
            '<filter id="l" x="-25%" y="-25%" width="150%" height="150%"><feGaussianBlur stdDeviation="4" result="glow"/>' +
            '<feMerge><feMergeNode in="glow"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        `<g filter="url(#n)">${glyph({ink: 'url(#g)', soft: 'none'})}</g><g filter="url(#l)">${glyph({ink: 'none', soft: 'url(#g)'})}</g>`),
    },
    duotone: {
        name: 'Amethystora Duotone',
        comment: 'Amethystora\'s own icons, each in its own gradient with its details in a contrasting one',
        draw: (glyph, [fill, , contrast]) => svg(gradient('g', fill) + gradient('h', contrast) + shadow('f', fill[1], 0.45, 6, 7),
            `<g filter="url(#f)">${glyph({ink: 'url(#g)', soft: 'url(#h)'})}</g>`),
    },
};

function indexTheme(pack) {
    const dirs = Object.keys(SET).map(context => `${context}/scalable`);
    return `[Icon Theme]\nName=${pack.name}\nComment=${pack.comment}\nInherits=Adwaita,hicolor\nExample=folder\n` +
        `Directories=${dirs.join(',')}\n` + Object.entries(CONTEXTS).map(([dir, context]) =>
        `\n[${dir}/scalable]\nContext=${context}\nSize=128\nMinSize=8\nMaxSize=512\nType=Scalable\n`).join('');
}

// Each name an icon answers to is a file of its own rather than a link, since the image build's rsync of
// system_files leaves links out
for (const [id, pack] of Object.entries(PACKS)) {
    const dir = join(ICONS, `amethystora-${id}`);
    rmSync(dir, {recursive: true, force: true});
    for (const [context, icons] of Object.entries(SET)) {
        mkdirSync(join(dir, context, 'scalable'), {recursive: true});
        for (const [name, glyph, ramp, also = []] of icons) {
            if (!DRAW[glyph] || !RAMPS[ramp])
                throw new Error(`${name}: no glyph ${glyph} or ramp ${ramp}`);
            const file = pack.draw(DRAW[glyph], RAMPS[ramp]);
            for (const each of [name, ...also])
                writeFileSync(join(dir, context, 'scalable', `${each}.svg`), file);
        }
    }
    writeFileSync(join(dir, 'index.theme'), indexTheme(pack));
    console.log(`wrote ${dir}`);
}

// The two launchers of Amethystora's own that have no artwork of theirs in hicolor (branding/generate.mjs draws
// the others), in the Glass style: every icon theme falls back on hicolor, and the Security app draws its shield
// from this file as it runs
for (const [name, glyph, ramp] of SET.apps.filter(([name]) => ['amethystora-security-status', 'amethystora-notes'].includes(name))) {
    mkdirSync(join(ICONS, 'hicolor/scalable/apps'), {recursive: true});
    writeFileSync(join(ICONS, 'hicolor/scalable/apps', `${name}.svg`), PACKS.glass.draw(DRAW[glyph], RAMPS[ramp]));
}

if (process.argv.includes('--preview')) {
    const out = join(tmpdir(), 'amethystora-icons');
    mkdirSync(out, {recursive: true});
    const all = Object.values(SET).flat();
    const rows = (id, size) => all.map(([name, glyph, ramp]) =>
        `<img title="${name}" width="${size}" height="${size}" src="data:image/svg+xml;base64,${Buffer.from(PACKS[id].draw(DRAW[glyph], RAMPS[ramp])).toString('base64')}">`).join('');
    const ground = (bg, ink) => Object.keys(PACKS).map(id =>
        `<section style="background:${bg};color:${ink};padding:18px 24px"><h2 style="margin:0 0 10px;font:600 18px sans-serif">${PACKS[id].name}</h2>` +
        `<div style="display:flex;flex-wrap:wrap;gap:10px">${rows(id, 64)}</div>` +
        `<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:12px">${rows(id, 24)}</div></section>`).join('');
    writeFileSync(join(out, 'sheet.html'), `<!doctype html><meta charset="utf-8"><body style="margin:0;width:1500px">` +
        ground('radial-gradient(ellipse at 20% 0%, #3a1470 0%, #16042c 55%, #0b0418 100%)', '#e8e0f2') +
        ground('linear-gradient(180deg,#fdf8ff,#e9e1f5)', '#3d3450') + '</body>');
    console.log(join(out, 'sheet.html'));
}
