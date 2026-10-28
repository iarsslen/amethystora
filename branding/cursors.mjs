// Amethystora's own pointers, drawn in code like the icon packs, in three sets:
//
//   Halo   white, with an amethyst rim: the pointer of every dark theme
//   Ink    dark, with a white rim: the pointer of every light theme
//   Facet  cut like the gem, in two faces of amethyst: for whoever picks it
//
// Each drawing is an SVG in the design's 24 by 30 units (plans/beyond/spec-pointer.md), rendered by the same headless
// Chromium generate.mjs uses at five nominal sizes, 24, 32, 48, 64 and 96, on a square canvas 30 units wide, so that
// one unit is N/24 pixels and the image is 1.25 times the nominal size (Mutter draws a cursor's height from its
// image's width, so a cursor image has to be square). The pixels are packed into Xcursor files here, with no
// xcursorgen: a file is a small table of contents and the premultiplied images it points at. GNOME Shell 51 draws its
// own pointers from SVG instead, so each drawing is also written as cursors_scalable/<name>/, its frames and the
// metadata.json that lists them.
//
// Only one file (and one folder) per drawing is written, under its CSS name. Every other name a toolkit asks for (the
// X11 names, the hashes) is a line of the set's `aliases` table, which the image build turns into links in both
// (build_files/base/10-icons.sh): a container layer stores every copy in full, where a link costs nothing.
//
//   node branding/cursors.mjs              writes the three sets into system_files/shared/usr/share/icons
//   node branding/cursors.mjs --preview    also renders a contact sheet of every drawing, and prints where
//   node branding/cursors.mjs --png DIR    also writes every image as a PNG, and a config xcursorgen reads, per drawing
//   ONLY=halo node branding/cursors.mjs    one set only (ink, facet)
import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {deflateSync, inflateSync} from 'node:zlib';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const ICONS = join(ROOT, 'system_files/shared/usr/share/icons');

// The colours of each set. They are artwork, not the theme's accent: a cursor file is a bitmap every client reads.
const SETS = [
    {
        id: 'halo', name: 'Halo', comment: 'White, with an amethyst rim',
        fill: '#ffffff', fill2: '#ffffff', rim: '#9148f0', w: 1.5, ink: '#ffffff', badge: '#9148f0', badgeInk: '#ffffff',
        track: '#ffffff', accent: '#9148f0',
    },
    {
        id: 'ink', name: 'Ink', comment: 'Dark, with a white rim',
        fill: '#15101c', fill2: '#15101c', rim: '#ffffff', w: 1.6, ink: '#15101c', badge: '#15101c', badgeInk: '#ffffff',
        track: '#15101c', accent: '#b37df9',
    },
    {
        id: 'facet', name: 'Facet', comment: 'Cut like the gem, in two faces',
        fill: '#9148f0', fill2: '#dcbcff', rim: '#ffffff', w: 1.3, ink: '#7429e0', badge: '#7429e0', badgeInk: '#ffffff',
        track: '#dcbcff', accent: '#5d1ac4',
    },
];

const SIZES = [24, 32, 48, 64, 96];
const FRAMES = 20; // an animated pointer turns once a second, 20 frames of 50 ms
const DELAY = 50; // what xcursorgen writes for a line without a delay, so that our files match its own

// ---------------------------------------------------------------- drawings --

const ROUND = 'stroke-linecap="round" stroke-linejoin="round"';

// The arrow, which every badge drawing shares
const arrow = (c) =>
    `<path d="M4 3L20 16 12.6 17.3 8.7 24Z" fill="${c.fill}" stroke="${c.rim}" stroke-width="${c.w}" stroke-linejoin="round"/>` +
    `<path d="M4 3L12.6 17.3 8.7 24Z" fill="${c.fill2}"/>` +
    `<path d="M4 3L20 16 12.6 17.3 8.7 24Z" fill="none" stroke="${c.rim}" stroke-width="${c.w}" stroke-linejoin="round"/>`;

// The badge at the arrow's foot, and a glyph drawn on it
const badge = (c, fill = c.badge) => `<circle cx="19" cy="23.5" r="5.6" fill="${fill}" stroke="${c.rim}" stroke-width="1.2"/>`;
const glyph = (d, color, width, extra = '') =>
    `<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" ${ROUND}${extra}/>`;

// A stroked drawing: its rim under all of it first, then its ink
const twoPass = (c, d, rim, ink, attrs = ROUND) =>
    `<path d="${d}" fill="none" stroke="${c.rim}" stroke-width="${rim}" ${attrs}/>` +
    `<path d="${d}" fill="none" stroke="${c.ink}" stroke-width="${ink}" ${attrs}/>`;

const rotated = (deg, body) => `<g transform="rotate(${deg} 12 15)">${body}</g>`;

const TEXT = 'M8.5 4.5c2 0 3.5 1 3.5 2.5v16c0 1.5-1.5 2.5-3.5 2.5M15.5 4.5c-2 0-3.5 1-3.5 2.5M15.5 25.5c-2 0-3.5-1-3.5-2.5M9.5 15h5';
const EW = 'M3 15h18M6.5 11.5L3 15l3.5 3.5M17.5 11.5L21 15l-3.5 3.5';
const MOVE = 'M12 5v20M2 15h20M9 8l3-3 3 3M9 22l3 3 3-3M5 12l-3 3 3 3M19 12l3 3-3 3';
const COL = 'M3 15h4.6M16.4 15h4.6M6.5 11.5L3 15l3.5 3.5M17.5 11.5L21 15l-3.5 3.5M10.2 9.5v11M13.8 9.5v11';

const text = (c) => twoPass(c, TEXT, 4.2, 1.8, 'stroke-linecap="round"');
const ew = (c) => twoPass(c, EW, 4.6, 2);
const move = (c) => twoPass(c, MOVE, 4.4, 1.9);
const col = (c) => twoPass(c, COL, 4.6, 2);
const zoom = (c, sign) =>
    `<circle cx="10.5" cy="13.5" r="6" fill="${c.track}" stroke="${c.rim}" stroke-width="4.4"/>` +
    `<path d="M14.8 17.8L20 23" fill="none" stroke="${c.rim}" stroke-width="5.2" ${ROUND}/>` +
    `<circle cx="10.5" cy="13.5" r="6" fill="none" stroke="${c.ink}" stroke-width="1.9"/>` +
    `<path d="M14.8 17.8L20 23" fill="none" stroke="${c.ink}" stroke-width="2.6" ${ROUND}/>` +
    glyph(sign, c.accent, 1.6);

const ARROW_HOT = [4, 3];
const CENTRE = [12, 15];
const ZOOM_HOT = [10.5, 13.5];

// Every drawing: its CSS name (the file it is written to), the other names it answers to, its hot spot in units, and
// the SVG of frame f. The names are those Mutter, GTK 3 and 4, Qt, Chromium and Firefox ask for today.
const DRAWINGS = [
    {
        name: 'default', hot: ARROW_HOT, draw: (c) => arrow(c),
        aliases: ['left_ptr', 'arrow', 'top_left_arrow', 'left_arrow', 'X_cursor', 'dnd-move'],
    },
    {
        name: 'pointer', hot: ARROW_HOT,
        draw: (c) => arrow(c) + badge(c) + glyph('M16.8 23.5h4.4M19 21.3l2.2 2.2-2.2 2.2', c.badgeInk, 1.4),
        aliases: ['hand', 'hand1', 'hand2', 'pointing_hand', 'e29285e634086352946a0e7090d73106'],
    },
    {
        name: 'context-menu', hot: ARROW_HOT,
        draw: (c) => arrow(c) + badge(c) + glyph('M16.9 21.7h4.2M16.9 23.5h4.2M16.9 25.3h4.2', c.badgeInk, 1.2),
        aliases: ['dnd-ask', '08ffe1e65f80fcfdf9fff11263e74c48'],
    },
    {
        name: 'help', hot: ARROW_HOT,
        draw: (c) => arrow(c) + badge(c) + glyph('M17.4 22.2a1.6 1.6 0 1 1 2.3 1.4c-.5.3-.7.6-.7 1.1', c.badgeInk, 1.4) +
            `<circle cx="19" cy="26.1" r=".75" fill="${c.badgeInk}"/>`,
        aliases: ['question_arrow', 'whats_this', '5c6cd98b3f3ebcb1f9c7f1c204630408', 'd9ce0ab605698f320427677b458ad60b'],
    },
    {
        name: 'copy', hot: ARROW_HOT,
        draw: (c) => arrow(c) + badge(c) + glyph('M19 21.3v4.4M16.8 23.5h4.4', c.badgeInk, 1.4),
        aliases: ['dnd-copy', '08ffe1cb5fe6fc01f906f1c063814ccf'],
    },
    {
        name: 'alias', hot: ARROW_HOT,
        draw: (c) => arrow(c) + badge(c) + glyph('M17.2 25.3l3.4-3.4M18.2 21.9h2.4v2.4', c.badgeInk, 1.4),
        aliases: ['link', 'dnd-link', '0876e1c15ff2fc01f906f1c363074c0f'],
    },
    {
        name: 'not-allowed', hot: ARROW_HOT,
        draw: (c) => arrow(c) + badge(c, '#f2566a') +
            '<path d="M16.8 23.5h4.4" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/>',
        aliases: ['no-drop', 'dnd-none', 'dnd-no-drop', 'crossed_circle', 'forbidden', 'circle', 'pirate',
            '03b6e0fcb3499374a867c041f52298f0', '03b6e0fcb3499374a867d041f52298f0'],
    },
    {
        name: 'progress', hot: ARROW_HOT, animated: true,
        draw: (c, f) => arrow(c) + badge(c) +
            `<g transform="rotate(${18 * f} 19 23.5)"><path d="M19 20.4a3.1 3.1 0 1 1-3.1 3.1" fill="none" stroke="${c.badgeInk}" stroke-width="1.6" stroke-linecap="round"/></g>`,
        aliases: ['left_ptr_watch', 'half-busy', '00000000000000020006000e7e9ffc3f', '08e8e1c95fe2fc01f976f1e063a24ccd'],
    },
    {
        name: 'wait', hot: CENTRE, animated: true,
        draw: (c, f) =>
            `<circle cx="12" cy="15" r="8.5" fill="none" stroke="${c.rim}" stroke-width="5.4"/>` +
            `<circle cx="12" cy="15" r="8.5" fill="none" stroke="${c.track}" stroke-width="2.6"/>` +
            `<g transform="rotate(${18 * f} 12 15)"><path d="M12 6.5a8.5 8.5 0 0 1 8.5 8.5" fill="none" stroke="${c.accent}" stroke-width="2.6" stroke-linecap="round"/></g>`,
        aliases: ['watch', '0426c94ea35c87780ff01dc239897213'],
    },
    {name: 'text', hot: CENTRE, draw: text, aliases: ['xterm', 'ibeam']},
    {
        name: 'vertical-text', hot: CENTRE, draw: (c) => rotated(90, text(c)),
        aliases: ['048008013003cff3c00c801001200000'],
    },
    {
        name: 'crosshair', hot: CENTRE,
        draw: (c) => twoPass(c, 'M12 4v7M12 19v7M2 15h7M15 15h7', 4.4, 1.9, 'stroke-linecap="round"') +
            `<circle cx="12" cy="15" r="1.4" fill="${c.accent}"/>`,
        aliases: ['cross', 'tcross', 'cell', 'plus'],
    },
    {
        name: 'move', hot: CENTRE, draw: move,
        aliases: ['all-scroll', 'all-resize', 'fleur', 'size_all', 'grab', 'openhand', '5aca4d189052212118709018842178c0',
            '9d800788f1b08800ae810202380a0822'],
    },
    {
        name: 'grabbing', hot: CENTRE,
        draw: (c) => move(c) + `<circle cx="12" cy="15" r="2.2" fill="${c.accent}" stroke="${c.rim}" stroke-width="1.2"/>`,
        aliases: ['closedhand', '208530c400c041818281048008011002'],
    },
    {
        name: 'ew-resize', hot: CENTRE, draw: ew,
        aliases: ['e-resize', 'w-resize', 'h_double_arrow', 'sb_h_double_arrow', 'size_hor', 'right_side', 'left_side',
            '028006030e0e7ebffc7f7070c0600140'],
    },
    {
        name: 'ns-resize', hot: CENTRE, draw: (c) => rotated(90, ew(c)),
        aliases: ['n-resize', 's-resize', 'v_double_arrow', 'sb_v_double_arrow', 'size_ver', 'top_side', 'bottom_side',
            '00008160000006810000408080010102'],
    },
    {
        name: 'nesw-resize', hot: CENTRE, draw: (c) => rotated(-45, ew(c)),
        aliases: ['ne-resize', 'sw-resize', 'fd_double_arrow', 'size_bdiag', 'top_right_corner', 'bottom_left_corner',
            '50585d75b494802d0151028115016902', 'fcf1c3c7cd4491d801f1e1c78f100000'],
    },
    {
        name: 'nwse-resize', hot: CENTRE, draw: (c) => rotated(45, ew(c)),
        aliases: ['nw-resize', 'se-resize', 'bd_double_arrow', 'size_fdiag', 'top_left_corner', 'bottom_right_corner',
            '38c5dff7c7b8962045400281044508d2', 'c7088f0f3e6c8088236ef8e1e3e70000'],
    },
    {
        name: 'col-resize', hot: CENTRE, draw: col,
        aliases: ['split_h', '043a9f68147c53184671403ffa811cc5', '14fef782d02440884392942c11205230'],
    },
    {
        name: 'row-resize', hot: CENTRE, draw: (c) => rotated(90, col(c)),
        aliases: ['split_v', '2870a09082c103050810ffdffffe0204', 'c07385c7190e701020ff7ffffd08103c'],
    },
    {name: 'zoom-in', hot: ZOOM_HOT, draw: (c) => zoom(c, 'M8.2 13.5h4.6M10.5 11.2v4.6'), aliases: ['f41c0e382c94c0958e07017e42b00462']},
    {name: 'zoom-out', hot: ZOOM_HOT, draw: (c) => zoom(c, 'M8.2 13.5h4.6'), aliases: ['f41c0e382c97c0938e07017e42800402']},
];

// The names Mutter asks for (its ClutterCursorType values): each has to be in every set
const MUTTER_NAMES = ['default', 'context-menu', 'help', 'pointer', 'progress', 'wait', 'cell', 'crosshair', 'text',
    'vertical-text', 'alias', 'copy', 'move', 'no-drop', 'not-allowed', 'grab', 'grabbing', 'e-resize', 'n-resize',
    'ne-resize', 'nw-resize', 's-resize', 'se-resize', 'sw-resize', 'w-resize', 'ew-resize', 'ns-resize', 'nesw-resize',
    'nwse-resize', 'col-resize', 'row-resize', 'all-scroll', 'zoom-in', 'zoom-out', 'dnd-ask', 'all-resize'];

const frames = (d) => (d.animated ? FRAMES : 1);
const side = (n) => (30 * n) / 24;
const hotPx = ([ux, uy], n) => {
    const s = side(n);
    const clamp = (v) => Math.max(0, Math.min(s - 1, v));
    return [clamp(Math.round(((ux + 3) * n) / 24)), clamp(Math.round((uy * n) / 24))];
};

// One drawing as an inline SVG of S pixels, the canvas x from -3 to 27 and y from 0 to 30 units, with the cells'
// soft shadow in units so that it scales with the drawing. An inline SVG clips to its own box.
function svg(set, drawing, f, n, id) {
    const s = side(n);
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}" viewBox="-3 0 30 30">` +
        `<filter id="s${id}" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB">` +
        '<feDropShadow dx="0" dy="1.2" stdDeviation="0.9" flood-color="#000000" flood-opacity="0.40"/></filter>' +
        `<g filter="url(#s${id})">${drawing.draw(set, f)}</g></svg>`;
}

// ---------------------------------------------------------------- PNG --

const CRC = new Int32Array(256).map((_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++)
        c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c;
});
const crc32 = (buf) => {
    let c = -1;
    for (const b of buf)
        c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ -1) >>> 0;
};

// A straight RGBA PNG, 8 bits, every row filter 0
function encodePng(width, height, rgba) {
    const chunk = (type, data) => {
        const out = Buffer.alloc(12 + data.length);
        out.writeUInt32BE(data.length, 0);
        out.write(type, 4, 'latin1');
        data.copy(out, 8);
        out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
        return out;
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(width, 0);
    ihdr.writeUInt32BE(height, 4);
    ihdr.set([8, 6, 0, 0, 0], 8);
    const raw = Buffer.alloc(height * (1 + 4 * width));
    for (let y = 0; y < height; y++)
        Buffer.from(rgba.buffer, rgba.byteOffset + y * 4 * width, 4 * width).copy(raw, y * (1 + 4 * width) + 1);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
        chunk('IDAT', deflateSync(raw, {level: 9})), chunk('IEND', Buffer.alloc(0))]);
}

// The screenshot Chromium wrote: 8-bit RGBA, not interlaced. Anything else is refused.
function decodePng(file) {
    const buf = readFileSync(file);
    if (buf.readUInt32BE(0) !== 0x89504e47)
        throw new Error(`${file} is not a PNG`);
    let pos = 8, width = 0, height = 0;
    const idat = [];
    while (pos < buf.length) {
        const len = buf.readUInt32BE(pos);
        const type = buf.toString('latin1', pos + 4, pos + 8);
        const data = buf.subarray(pos + 8, pos + 8 + len);
        if (type === 'IHDR') {
            width = data.readUInt32BE(0);
            height = data.readUInt32BE(4);
            if (data[8] !== 8 || data[9] !== 6 || data[12] !== 0)
                throw new Error(`${file}: depth ${data[8]}, colour type ${data[9]}, interlace ${data[12]}; 8-bit RGBA expected`);
        } else if (type === 'IDAT') {
            idat.push(data);
        } else if (type === 'IEND') {
            break;
        }
        pos += 12 + len;
    }
    const raw = inflateSync(Buffer.concat(idat));
    const stride = 4 * width;
    const out = new Uint8Array(height * stride);
    for (let y = 0; y < height; y++) {
        const filter = raw[y * (stride + 1)];
        const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
        const row = out.subarray(y * stride, (y + 1) * stride);
        const up = y ? out.subarray((y - 1) * stride, y * stride) : new Uint8Array(stride);
        for (let x = 0; x < stride; x++) {
            const a = x >= 4 ? row[x - 4] : 0, b = up[x], c = x >= 4 ? up[x - 4] : 0;
            let v;
            switch (filter) {
            case 0: v = 0; break;
            case 1: v = a; break;
            case 2: v = b; break;
            case 3: v = (a + b) >> 1; break;
            case 4: {
                const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
                v = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
                break;
            }
            default: throw new Error(`${file}: row filter ${filter}`);
            }
            row[x] = (line[x] + v) & 0xff;
        }
    }
    return {width, height, rgba: out};
}

// ---------------------------------------------------------------- render --

function findBrowser() {
    const candidates = [
        process.env.BROWSER,
        'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
        'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
        'C:/Program Files/Google/Chrome/Application/chrome.exe',
        '/usr/bin/chromium-browser',
        '/usr/bin/chromium',
        '/usr/bin/google-chrome',
        '/usr/bin/microsoft-edge',
    ].filter(Boolean);
    const found = candidates.find((c) => existsSync(c));
    if (!found)
        throw new Error('No Chromium-based browser found; set BROWSER=/path/to/browser');
    return found;
}

const WORK = join(tmpdir(), 'amethystora-cursors');

// One page, one screenshot, and the screenshot decoded
function screenshot(html, width, height, out) {
    const page = join(WORK, 'page.html');
    writeFileSync(page, html);
    rmSync(out, {force: true});
    execFileSync(findBrowser(), [
        '--headless', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
        '--force-color-profile=srgb', '--default-background-color=00000000',
        `--user-data-dir=${join(WORK, 'profile')}`, `--window-size=${width},${height}`, `--screenshot=${out}`,
        pathToFileURL(page).href,
    ], {stdio: 'ignore'});
    // Edge on Windows can return before its screenshot is on disk, or while it is still writing it, so wait for the
    // PNG's last chunk
    const done = () => {
        try {
            return readFileSync(out).subarray(-8, -4).toString() === 'IEND';
        } catch {
            return false;
        }
    };
    for (const start = Date.now(); !done() && Date.now() - start < 60000;)
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 250);
    if (!done())
        throw new Error(`Rendering ${out} failed`);
}

const COLUMNS = 8;
const PAGE_MIN = 480; // a headless window narrower than this is not always honoured

// Every image of a set at one size: a page of cells at whole-pixel positions, cut back out of the screenshot as
// straight RGBA, keyed `${drawing}/${frame}`
function renderSize(set, n) {
    const s = side(n);
    const cells = DRAWINGS.flatMap((d) => Array.from({length: frames(d)}, (_, f) => ({d, f})));
    const rows = Math.ceil(cells.length / COLUMNS);
    const width = Math.max(PAGE_MIN, COLUMNS * s), height = Math.max(PAGE_MIN, rows * s);
    const html = '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent}' +
        `svg{position:absolute;display:block}</style></head><body>${cells.map(({d, f}, i) =>
            svg(set, d, f, n, i).replace('<svg ', `<svg style="left:${(i % COLUMNS) * s}px;top:${Math.floor(i / COLUMNS) * s}px" `)).join('')}</body></html>`;
    const shot = join(WORK, `${set.id}-${n}.png`);
    screenshot(html, width, height, shot);
    const png = decodePng(shot);
    if (png.width !== width || png.height !== height)
        throw new Error(`${set.id} at ${n}: the screenshot is ${png.width}x${png.height}, not ${width}x${height}`);
    const images = new Map();
    cells.forEach(({d, f}, i) => {
        const x0 = (i % COLUMNS) * s, y0 = Math.floor(i / COLUMNS) * s;
        const rgba = new Uint8Array(s * s * 4);
        for (let y = 0; y < s; y++)
            rgba.set(png.rgba.subarray(((y0 + y) * width + x0) * 4, ((y0 + y) * width + x0 + s) * 4), y * s * 4);
        if (!rgba.some((v, k) => k % 4 === 3 && v))
            throw new Error(`${set.id} ${d.name} frame ${f} at ${n} is empty`);
        images.set(`${d.name}/${f}`, rgba);
    });
    return images;
}

// ---------------------------------------------------------------- Xcursor --

const XCURSOR_MAGIC = 0x72756358;
const XCURSOR_IMAGE_TYPE = 0xfffd0002;

// Premultiplied 0xAARRGGBB, rounded as xcursorgen rounds
const div255 = (x) => (x + 0x80 + ((x + 0x80) >> 8)) >> 8;

// One Xcursor file: images by nominal size ascending, within a size by frame, each [size, width, xhot, yhot, rgba]
function packXcursor(images) {
    const ntoc = images.length;
    const total = 16 + 12 * ntoc + images.reduce((sum, [, w]) => sum + 36 + 4 * w * w, 0);
    const out = Buffer.alloc(total);
    out.writeUInt32LE(XCURSOR_MAGIC, 0);
    out.writeUInt32LE(16, 4);
    out.writeUInt32LE(0x10000, 8);
    out.writeUInt32LE(ntoc, 12);
    let pos = 16 + 12 * ntoc;
    images.forEach(([n, w, xhot, yhot, rgba], i) => {
        out.writeUInt32LE(XCURSOR_IMAGE_TYPE, 16 + 12 * i);
        out.writeUInt32LE(n, 20 + 12 * i);
        out.writeUInt32LE(pos, 24 + 12 * i);
        [36, XCURSOR_IMAGE_TYPE, n, 1, w, w, xhot, yhot, DELAY].forEach((v, k) => out.writeUInt32LE(v, pos + 4 * k));
        pos += 36;
        for (let p = 0; p < w * w; p++) {
            const r = rgba[4 * p], g = rgba[4 * p + 1], b = rgba[4 * p + 2], a = rgba[4 * p + 3];
            out[pos] = div255(b * a);
            out[pos + 1] = div255(g * a);
            out[pos + 2] = div255(r * a);
            out[pos + 3] = a;
            pos += 4;
        }
    });
    return out;
}

// ---------------------------------------------------------------- scalable --

// GNOME Shell 51 draws the compositor's own pointers from SVG, cursors_scalable/<name>/metadata.json and the frames it
// lists, and reads no Xcursor file for them (X11 and GTK 3 clients still do). Each frame is the drawing at the nominal
// size 24, its 30-pixel canvas and its hot spot in those pixels; GNOME scales it to the pointer size and the screen's.
function writeScalable(set, d, dir) {
    const out = join(dir, 'cursors_scalable', d.name);
    mkdirSync(out, {recursive: true});
    const [hx, hy] = d.hot;
    const meta = Array.from({length: frames(d)}, (_, f) => {
        const filename = d.animated ? `${d.name}-${String(f).padStart(2, '0')}.svg` : `${d.name}.svg`;
        writeFileSync(join(out, filename), `${svg(set, d, f, 24, '')}\n`);
        return {filename, hotspot_x: hx + 3, hotspot_y: hy, nominal_size: 24, delay: d.animated ? DELAY : 0};
    });
    writeFileSync(join(out, 'metadata.json'), `${JSON.stringify(meta, null, 2)}\n`);
}

// ---------------------------------------------------------------- write --

function checkNames() {
    const seen = new Set();
    for (const name of DRAWINGS.flatMap((d) => [d.name, ...d.aliases])) {
        if (seen.has(name))
            throw new Error(`${name} is named twice`);
        seen.add(name);
    }
    for (const name of MUTTER_NAMES) {
        if (!seen.has(name))
            throw new Error(`Mutter's ${name} is not drawn`);
    }
    return seen.size;
}

const pngDir = process.argv.includes('--png') ? process.argv[process.argv.indexOf('--png') + 1] : null;
if (process.argv.includes('--png') && !pngDir)
    throw new Error('--png needs a folder');

const names = checkNames();
rmSync(WORK, {recursive: true, force: true});
mkdirSync(WORK, {recursive: true});
const rendered = new Map(); // set id -> drawing name -> the file's bytes, for the contact sheet
for (const set of SETS.filter((s) => !process.env.ONLY || s.id === process.env.ONLY)) {
    const bySize = new Map(SIZES.map((n) => [n, renderSize(set, n)]));
    const dir = join(ICONS, `amethystora-pointer-${set.id}`);
    rmSync(dir, {recursive: true, force: true});
    mkdirSync(join(dir, 'cursors'), {recursive: true});
    writeFileSync(join(dir, 'index.theme'),
        `[Icon Theme]\nName=Amethystora ${set.name}\nComment=${set.comment}\nInherits=Adwaita\n`);
    writeFileSync(join(dir, 'aliases'), '# The other names of each pointer, which the image build makes as links to it\n' +
        '# in cursors/ and cursors_scalable/ (build_files/base/10-icons.sh): name, then the drawing it is\n' +
        DRAWINGS.flatMap((d) => d.aliases.map((a) => `${a} ${d.name}\n`)).join(''));
    const files = new Map();
    let bytes = 0;
    for (const d of DRAWINGS) {
        const images = SIZES.flatMap((n) => Array.from({length: frames(d)}, (_, f) =>
            [n, side(n), ...hotPx(d.hot, n), bySize.get(n).get(`${d.name}/${f}`)]));
        const file = packXcursor(images);
        writeFileSync(join(dir, 'cursors', d.name), file);
        writeScalable(set, d, dir);
        files.set(d.name, {file, images});
        bytes += file.length;
        if (pngDir) {
            const base = join(pngDir, set.id);
            mkdirSync(join(base, d.name), {recursive: true});
            const cfg = images.map(([n, w, xhot, yhot, rgba], i) => {
                const png = `${d.name}/${n}-${String(i % frames(d)).padStart(2, '0')}.png`;
                writeFileSync(join(base, png), encodePng(w, w, rgba));
                return `${n} ${xhot} ${yhot} ${png} ${DELAY}\n`;
            });
            writeFileSync(join(base, `${d.name}.cfg`), cfg.join(''));
            mkdirSync(join(pngDir, 'ours', set.id), {recursive: true});
            writeFileSync(join(pngDir, 'ours', set.id, d.name), file);
        }
    }
    rendered.set(set.id, files);
    console.log(`amethystora-pointer-${set.id}: ${DRAWINGS.length} files, ${names} names, ${bytes} bytes`);
}

// ---------------------------------------------------------------- contact sheet --

const dataUri = (w, rgba) => `data:image/png;base64,${encodePng(w, w, rgba).toString('base64')}`;
const imageOf = (files, name, n, f = 0) => {
    const d = DRAWINGS.find((x) => x.name === name);
    return files.get(name).images[SIZES.indexOf(n) * frames(d) + f][4];
};

// The board's own cells, for comparison: its SVGs at 40 by 50 with its CSS shadow
const boardCell = (set, d) =>
    `<svg viewBox="0 0 24 30" style="width:40px;height:50px;filter:drop-shadow(0 2px 3px rgba(0,0,0,.4));overflow:visible">${d.draw(set, 0)}</svg>`;

function sheet() {
    const grounds = [
        'linear-gradient(135deg,#f3eefa 0 50%,#1a1226 50% 100%)', '#7f7f7f',
        'repeating-linear-gradient(45deg,#2a1748 0 6px,#e8e0f2 6px 12px)',
    ];
    const board = ['default', 'pointer', 'text', 'progress', 'wait', 'ew-resize', 'move', 'crosshair', 'not-allowed'];
    let html = '<!doctype html><html><head><meta charset="utf-8"><style>' +
        'body{margin:0;padding:16px;background:#110c18;color:#efe4ff;font:12px system-ui,sans-serif}' +
        'h2{margin:16px 0 6px;font-size:15px}.row{display:flex;flex-wrap:wrap;gap:6px;align-items:center}' +
        '.cell{width:84px;height:84px;border-radius:14px;display:flex;align-items:center;justify-content:center;gap:4px;flex-direction:column}' +
        '.big{image-rendering:pixelated}.tag{font-size:9px;color:#b9a8d3}.hot{position:relative;display:inline-block}' +
        '.hot i{position:absolute;width:1px;height:1px;background:red}</style></head><body>';
    for (const [id, files] of rendered) {
        const set = SETS.find((s) => s.id === id);
        html += `<h2>${set.name}: every drawing at 24, 1:1 and at 4x, on the board's ground, mid grey and stripes</h2>`;
        for (const ground of grounds) {
            html += '<div class="row">';
            for (const d of DRAWINGS) {
                const uri = dataUri(30, imageOf(files, d.name, 24));
                html += `<div class="cell" style="background:${ground}"><img src="${uri}"><span class="tag">${d.name}</span></div>`;
            }
            html += '</div><div class="row">';
            for (const d of DRAWINGS) {
                const uri = dataUri(30, imageOf(files, d.name, 24));
                html += `<div style="background:${ground};border-radius:6px"><img class="big" width="120" height="120" src="${uri}"></div>`;
            }
            html += '</div>';
        }
        html += `<h2>${set.name}: sizes 24 to 96, the hot spot in red</h2><div class="row">`;
        for (const name of ['default', 'text', 'pointer', 'wait']) {
            const d = DRAWINGS.find((x) => x.name === name);
            for (const n of SIZES) {
                const w = side(n), [hx, hy] = hotPx(d.hot, n);
                html += `<div class="hot" style="background:#1a1226"><img src="${dataUri(w, imageOf(files, name, n))}">` +
                    `<i style="left:${hx}px;top:${hy}px"></i></div>`;
            }
        }
        html += `</div><h2>${set.name}: the frames of wait and progress at 48</h2>`;
        for (const name of ['wait', 'progress']) {
            html += '<div class="row" style="background:#7f7f7f">';
            for (let f = 0; f < FRAMES; f++)
                html += `<img src="${dataUri(60, imageOf(files, name, 48, f))}">`;
            html += '</div>';
        }
        html += `<h2>${set.name}: the board's cells (left) beside ours at 32 (right)</h2><div class="row">`;
        for (const name of board) {
            const d = DRAWINGS.find((x) => x.name === name);
            html += `<div class="cell" style="background:${grounds[0]};flex-direction:row;width:110px">${boardCell(set, d)}` +
                `<img src="${dataUri(40, imageOf(files, name, 32))}"></div>`;
        }
        html += '</div>';
    }
    return `${html}</body></html>`;
}

if (process.argv.includes('--preview')) {
    const out = join(tmpdir(), 'amethystora-cursors-sheet');
    mkdirSync(out, {recursive: true});
    writeFileSync(join(out, 'sheet.html'), sheet());
    const height = 260 + rendered.size * 1180;
    screenshot(readFileSync(join(out, 'sheet.html'), 'utf8'), 2100, height, join(out, 'sheet.png'));
    console.log(join(out, 'sheet.png'));
}
// Best effort: the browser can hold its profile there for a while after it has returned
try {
    rmSync(WORK, {recursive: true, force: true});
} catch {}
