// The glyphs of the Amethystora icon packs, drawn for Amethystora: none is traced from or modelled on another set.
//
// Each glyph is drawn in a 256 box, its content kept inside 36..220, with two inks: `ink`, the body, and `soft`, the
// details on it. The packs render the same glyph twice (branding/icons.mjs): Glass fills the body with a gradient and
// the details with a lighter one, Neon draws the body's outline lit and the details lit inside it. So a detail is a
// separate shape over the body, never a hole cut into it, and a body is one silhouette.

const f = n => +n.toFixed(1);

// A circle as a path, for cutting holes with fill-rule="evenodd"
const circlePath = (cx, cy, r) => `M${cx + r} ${cy}A${r} ${r} 0 1 0 ${cx - r} ${cy}A${r} ${r} 0 1 0 ${cx + r} ${cy}Z`;

function gearPath(cx, cy, outer, inner, teeth, hole) {
    let d = '';
    for (let i = 0; i < teeth * 4; i++) {
        const a = (i / (teeth * 4)) * 2 * Math.PI - Math.PI / 2;
        const r = (i % 4 === 0 || i % 4 === 1) ? outer : inner;
        d += `${i ? 'L' : 'M'}${f(cx + r * Math.cos(a))} ${f(cy + r * Math.sin(a))}`;
    }
    return d + 'Z' + circlePath(cx, cy, hole);
}

function starPath(cx, cy, outer, inner) {
    let d = '';
    for (let i = 0; i < 10; i++) {
        const a = (i / 10) * 2 * Math.PI - Math.PI / 2, r = i % 2 ? inner : outer;
        d += `${i ? 'L' : 'M'}${f(cx + r * Math.cos(a))} ${f(cy + r * Math.sin(a))}`;
    }
    return d + 'Z';
}

// An arc of a circle from one angle to another (degrees, clockwise from three o'clock) as a stroked path, and the
// filled arrowhead at its end, pointing the way the arc runs
function arcArrow(cx, cy, r, from, to, width, colour) {
    const rad = a => (a * Math.PI) / 180, at = a => [cx + r * Math.cos(rad(a)), cy + r * Math.sin(rad(a))];
    const [x1, y1] = at(from), [x2, y2] = at(to), sweep = to > from ? 1 : 0;
    const large = Math.abs(to - from) > 180 ? 1 : 0;
    const dir = sweep ? 1 : -1, t = [-Math.sin(rad(to)) * dir, Math.cos(rad(to)) * dir], n = [Math.cos(rad(to)), Math.sin(rad(to))];
    const head = width * 1.25, back = [x2 - t[0] * 2, y2 - t[1] * 2];
    const tip = [x2 + t[0] * head * 1.1, y2 + t[1] * head * 1.1];
    const p1 = [back[0] + n[0] * head, back[1] + n[1] * head], p2 = [back[0] - n[0] * head, back[1] - n[1] * head];
    return `<path d="M${f(x1)} ${f(y1)}A${r} ${r} 0 ${large} ${sweep} ${f(x2)} ${f(y2)}" fill="none" stroke="${colour}" stroke-width="${width}" stroke-linecap="round"/>` +
        `<path d="M${f(tip[0])} ${f(tip[1])}L${f(p1[0])} ${f(p1[1])}L${f(p2[0])} ${f(p2[1])}Z" fill="${colour}" stroke="${colour}" stroke-width="4" stroke-linejoin="round"/>`;
}

const line = (d, colour, width) => `<path d="${d}" fill="none" stroke="${colour}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;

// A document page and its folded corner, which every file type shares
const PAGE = 'M76 40h84l34 34v128a14 14 0 0 1-14 14H76a14 14 0 0 1-14-14V54a14 14 0 0 1 14-14z';
const page = ({ink, soft}, emblem = '') => `<path d="${PAGE}" fill="${ink}"/><path d="M160 40v22a12 12 0 0 0 12 12h22" fill="${soft}"/>${emblem}`;

// A folder: its back flap in the soft ink, its front in the body ink, and an emblem on the front, centred on 128 148
const folder = ({ink, soft}, emblem = '') =>
    `<path d="M40 78a14 14 0 0 1 14-14h50l20 20h78a14 14 0 0 1 14 14v10H40z" fill="${soft}"/>` +
    `<path d="M36 106a14 14 0 0 1 14-14h156a14 14 0 0 1 14 14v84a16 16 0 0 1-16 16H52a16 16 0 0 1-16-16z" fill="${ink}"/>${emblem}`;

// The emblems, drawn in the soft ink around 128 148: on a folder's front, and on a page
const EMBLEM = {
    documents: s => line('M100 132h56M100 150h56M100 168h34', s, 10),
    download: s => line('M128 118v40M110 142l18 18 18-18', s, 12) + line('M102 180h52', s, 10),
    music: s => `<circle cx="120" cy="170" r="13" fill="${s}"/><path d="M128 118h8v52h-8z" fill="${s}"/><path d="M132 116c12 2 26 10 24 26-6-8-14-10-24-10z" fill="${s}"/>`,
    pictures: s => `<path d="M96 180l24-30 16 18 10-12 18 24z" fill="${s}" stroke="${s}" stroke-width="4" stroke-linejoin="round"/><circle cx="150" cy="126" r="10" fill="${s}"/>`,
    videos: s => `<path d="M114 122v52l42-26z" fill="${s}" stroke="${s}" stroke-width="8" stroke-linejoin="round"/>`,
    templates: s => `<rect x="100" y="122" width="56" height="54" rx="9" fill="none" stroke="${s}" stroke-width="8" stroke-dasharray="11 8"/>`,
    publicshare: s => line('M108 150l40-22M108 150l40 22', s, 7) + `<circle cx="106" cy="150" r="11" fill="${s}"/><circle cx="150" cy="126" r="11" fill="${s}"/><circle cx="150" cy="174" r="11" fill="${s}"/>`,
    desktop: s => `<rect x="96" y="120" width="64" height="42" rx="7" fill="${s}"/>` + line('M128 164v10M112 178h32', s, 8),
    remote: s => `<path d="M108 176h42a17 17 0 0 0 3-34 23 23 0 0 0-44-5 20 20 0 0 0-1 39z" fill="${s}"/>`,
    locked: s => line('M114 140v-10a14 14 0 0 1 28 0v10', s, 8) + `<rect x="102" y="138" width="52" height="40" rx="9" fill="${s}"/>`,
};

// The application glyphs approved on the design canvas of 2026-10-23 (files, settings, terminal, editor, calculator,
// manual, security, control), then the rest of the set drawn the same way
export const DRAW = {
    files: ({ink, soft}) => `
        <path d="M58 86a12 12 0 0 1 12-12h40l16 16h60a12 12 0 0 1 12 12v8H58z" fill="${soft}"/>
        <path d="M54 110a12 12 0 0 1 12-12h124a12 12 0 0 1 12 12v66a14 14 0 0 1-14 14H68a14 14 0 0 1-14-14z" fill="${ink}"/>`,
    settings: ({ink}) => `<path fill-rule="evenodd" d="${gearPath(128, 128, 74, 58, 9, 24)}" fill="${ink}"/>`,
    terminal: ({ink, soft}) => `
        <rect x="52" y="64" width="152" height="128" rx="18" fill="none" stroke="${ink}" stroke-width="12"/>
        ${line('M80 104l26 22-26 22', ink, 14)}${line('M118 152h44', soft, 14)}`,
    editor: c => page(c, line('M86 112h84M86 140h84M86 168h52', c.soft, 11)),
    calculator: ({ink, soft}) => `
        <rect x="70" y="48" width="116" height="160" rx="20" fill="${ink}"/>
        <rect x="86" y="64" width="84" height="32" rx="8" fill="${soft}"/>
        ${[0, 1, 2].map(r => [0, 1, 2].map(c => `<circle cx="${100 + c * 28}" cy="${122 + r * 28}" r="9" fill="${soft}"/>`).join('')).join('')}`,
    manual: ({ink, soft}) => `
        <path d="M128 52l58 33v58l-58 33-58-33V85z" fill="${ink}"/>
        <path d="M128 52l58 33-58 33-58-33z" fill="${soft}" fill-opacity="0.55"/>
        <path d="M186 118v74l-16 12V128z" fill="${ink}"/>`,
    security: ({ink, soft}) => `
        <path d="M128 46l68 26v52c0 44-30 74-68 88-38-14-68-44-68-88V72z" fill="${ink}"/>
        <path d="M128 46l68 26v52c0 44-30 74-68 88z" fill="${soft}" fill-opacity="0.35"/>
        ${line('M100 128l20 20 38-40', soft, 14)}`,
    control: ({ink, soft}) => `
        ${line('M64 84h128M64 128h128M64 172h128', soft, 14)}
        <circle cx="150" cy="84" r="20" fill="${ink}"/><circle cx="98" cy="128" r="20" fill="${ink}"/><circle cx="170" cy="172" r="20" fill="${ink}"/>`,

    // ---- Amethystora's other apps -----------------------------------------------------------------------------------
    // Updates: an arrow coming round, and one coming down into the middle of it
    update: ({ink, soft}) => arcArrow(128, 128, 70, -60, 230, 18, ink) + line('M128 94v54M106 128l22 22 22-22', soft, 16),
    // Logs: a sheet of lines and the lens going over them
    logs: ({ink, soft}) => `<rect x="44" y="44" width="148" height="164" rx="22" fill="${ink}"/>` +
        line('M70 86h96M70 114h72M70 142h40', soft, 11) +
        `<circle cx="160" cy="164" r="30" fill="none" stroke="${soft}" stroke-width="13"/>` + line('M182 186l22 22', soft, 17),
    // Notes: a note with its list ticked
    notes: ({ink, soft}) => `<rect x="52" y="40" width="152" height="176" rx="26" fill="${ink}"/>` +
        [92, 132, 172].map((y, i) => `<rect x="76" y="${y - 14}" width="28" height="28" rx="8" fill="${i < 2 ? soft : 'none'}" stroke="${soft}" stroke-width="7"/>` +
            line(`M120 ${y}h58`, soft, 11)).join(''),
    // Backups: the clock, with time going back round it
    backups: ({ink, soft}) => `<circle cx="128" cy="128" r="54" fill="${ink}"/>` + arcArrow(128, 128, 78, 160, -100, 15, ink) +
        line('M128 98v32l22 14', soft, 13),
    // Community: two speech bubbles
    community: ({ink, soft}) =>
        `<path d="M62 52h92a22 22 0 0 1 22 22v50a22 22 0 0 1-22 22h-50l-30 26v-26h-12a22 22 0 0 1-22-22V74a22 22 0 0 1 22-22z" fill="${ink}"/>` +
        `<path d="M122 112h74a22 22 0 0 1 22 22v40a22 22 0 0 1-22 22h-6v24l-28-24h-40a22 22 0 0 1-22-22v-40a22 22 0 0 1 22-22z" fill="${soft}"/>` +
        [136, 158, 180].map(x => `<circle cx="${x}" cy="154" r="7" fill="${ink}"/>`).join(''),

    // ---- The system's apps -------------------------------------------------------------------------------------------
    monitor: ({ink, soft}) => `<rect x="40" y="48" width="176" height="128" rx="20" fill="${ink}"/>` +
        `<path d="M116 172h24v24h-24z" fill="${ink}"/><rect x="84" y="192" width="88" height="16" rx="8" fill="${ink}"/>` +
        line('M60 118h30l14-32 22 60 18-40 12 12h40', soft, 12),
    computer: ({ink, soft}) => `<rect x="40" y="48" width="176" height="128" rx="20" fill="${ink}"/>` +
        `<rect x="56" y="64" width="144" height="96" rx="10" fill="${soft}" fill-opacity="0.6"/>` +
        `<path d="M116 172h24v24h-24z" fill="${ink}"/><rect x="84" y="192" width="88" height="16" rx="8" fill="${ink}"/>`,
    drive: ({ink, soft}) => `<rect x="36" y="80" width="184" height="96" rx="24" fill="${ink}"/>` +
        line('M64 128h84', soft, 12) + `<circle cx="186" cy="128" r="10" fill="${soft}"/>`,
    // Tour: a compass
    compass: ({ink, soft}) => `<circle cx="128" cy="128" r="80" fill="${ink}"/>` +
        `<path d="M128 60l24 68-24 68-24-68z" fill="${soft}" stroke="${soft}" stroke-width="6" stroke-linejoin="round"/>` +
        `<circle cx="128" cy="128" r="9" fill="${ink}"/>`,
    // Tweaks: a wrench
    wrench: ({ink}) => {
        const r = 40, hw = 14, y = 80, top = f(y - Math.sqrt(r * r - hw * hw));
        return `<g transform="rotate(45 128 128)"><path d="M${128 + hw} ${top}A${r} ${r} 0 1 1 ${128 - hw} ${top}V${y - 14}a${hw} ${hw} 0 0 0 ${hw * 2} 0z" fill="${ink}"/>` +
            `<rect x="114" y="104" width="28" height="118" rx="14" fill="${ink}"/></g>`;
    },
    // Parental Controls: a person under a shield
    guardian: ({ink, soft}) => `<circle cx="108" cy="90" r="32" fill="${ink}"/><path d="M44 204a64 64 0 0 1 128 0z" fill="${ink}"/>` +
        `<path d="M184 120l30 11v24c0 22-13 36-30 42-17-6-30-20-30-42v-24z" fill="${soft}"/>`,
    // Firewall: a wall
    wall: ({ink, soft}) => `<rect x="40" y="56" width="176" height="144" rx="20" fill="${ink}"/>` +
        line('M40 104h176M40 152h176', soft, 8) + line('M100 56v48M158 56v48M72 104v48M128 104v48M186 104v48M100 152v48M158 152v48', soft, 8),
    // Colour: a painter's palette
    palette: ({ink, soft}) =>
        `<path d="M128 44c-50 0-88 38-88 84s38 84 84 84c14 0 22-8 22-19 0-6-4-10-4-17 0-9 7-15 15-15h20c24 0 43-19 43-43 0-42-40-74-92-74z" fill="${ink}"/>` +
        [[90, 112], [118, 80], [158, 84], [84, 152]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="13" fill="${soft}"/>`).join(''),
    // Media sharing: a beacon sending both ways
    broadcast: ({ink, soft}) => `<circle cx="128" cy="116" r="22" fill="${ink}"/><path d="M118 132h20l14 76h-48z" fill="${ink}"/>` +
        line('M92 80a50 50 0 0 0 0 72M164 80a50 50 0 0 1 0 72M66 56a86 86 0 0 0 0 120M190 56a86 86 0 0 1 0 120', soft, 12),
    // Help: a lifebuoy
    lifebuoy: ({ink, soft}) => `<circle cx="128" cy="128" r="62" fill="none" stroke="${ink}" stroke-width="38"/>` +
        `<circle cx="128" cy="128" r="62" fill="none" stroke="${soft}" stroke-width="38" stroke-dasharray="42 55.4" stroke-dashoffset="-27.7"/>`,
    // An app with no icon of its own
    app: ({ink, soft}) => `<rect x="48" y="48" width="160" height="160" rx="42" fill="${ink}"/>` +
        [[80, 80], [136, 80], [80, 136], [136, 136]].map(([x, y]) => `<rect x="${x}" y="${y}" width="40" height="40" rx="12" fill="${soft}"/>`).join(''),

    // ---- GNOME's apps ------------------------------------------------------------------------------------------------
    calendar: ({ink, soft}) => `<rect x="44" y="56" width="168" height="156" rx="26" fill="${ink}"/>` +
        `<path d="M44 82a26 26 0 0 1 26-26h116a26 26 0 0 1 26 26v18H44z" fill="${soft}"/>` +
        `<rect x="82" y="40" width="16" height="36" rx="8" fill="${soft}"/><rect x="158" y="40" width="16" height="36" rx="8" fill="${soft}"/>` +
        [0, 1].map(r => [0, 1, 2].map(c => `<rect x="${70 + c * 44}" y="${124 + r * 40}" width="28" height="26" rx="7" fill="${soft}"/>`).join('')).join(''),
    smile: ({ink, soft}) => `<circle cx="128" cy="128" r="80" fill="${ink}"/>` +
        `<circle cx="100" cy="108" r="12" fill="${soft}"/><circle cx="156" cy="108" r="12" fill="${soft}"/>` + line('M90 146a42 42 0 0 0 76 0', soft, 14),
    remote: ({ink, soft}) => `<rect x="36" y="44" width="140" height="100" rx="16" fill="${ink}"/>` + line('M106 144v18M84 168h44', ink, 13) +
        `<rect x="108" y="108" width="112" height="78" rx="14" fill="${soft}"/>` + line('M164 186v14M144 206h40', soft, 12),
    contact: ({ink, soft}) => `<rect x="36" y="60" width="184" height="136" rx="24" fill="${ink}"/>` +
        `<circle cx="90" cy="112" r="20" fill="${soft}"/><path d="M58 168a32 28 0 0 1 64 0z" fill="${soft}"/>` +
        line('M142 104h52M142 128h52M142 152h34', soft, 11),
    archive: ({ink, soft}) => `<rect x="56" y="40" width="144" height="176" rx="26" fill="${ink}"/>` +
        [0, 1, 2, 3, 4].map(i => `<rect x="${i % 2 ? 128 : 114}" y="${54 + i * 16}" width="14" height="10" rx="3" fill="${soft}"/>`).join('') +
        `<rect x="110" y="138" width="36" height="46" rx="11" fill="${soft}"/><rect x="120" y="150" width="16" height="22" rx="5" fill="${ink}"/>`,
    chip: ({ink, soft}) => [0, 1, 2, 3].map(i => {
        const o = 82 + i * 26;
        return `<rect x="${o}" y="40" width="14" height="28" rx="5" fill="${soft}"/><rect x="${o}" y="188" width="14" height="28" rx="5" fill="${soft}"/>` +
            `<rect x="40" y="${o}" width="28" height="14" rx="5" fill="${soft}"/><rect x="188" y="${o}" width="28" height="14" rx="5" fill="${soft}"/>`;
    }).join('') + `<rect x="64" y="64" width="128" height="128" rx="22" fill="${ink}"/>` +
        `<rect x="96" y="96" width="64" height="64" rx="12" fill="none" stroke="${soft}" stroke-width="9"/>`,
    photo: ({ink, soft}) => `<rect x="36" y="52" width="184" height="152" rx="26" fill="${ink}"/>` +
        `<path d="M60 180l40-50 30 34 20-22 46 38z" fill="${soft}" stroke="${soft}" stroke-width="6" stroke-linejoin="round"/><circle cx="166" cy="98" r="17" fill="${soft}"/>`,
    map: ({ink, soft}) => `<path d="M40 70l58-24 60 24 58-24v140l-58 24-60-24-58 24z" fill="${ink}" stroke="${ink}" stroke-width="8" stroke-linejoin="round"/>` +
        `<path fill-rule="evenodd" d="M128 72c-21 0-38 17-38 38 0 28 38 62 38 62s38-34 38-62c0-21-17-38-38-38z${circlePath(128, 110, 13)}" fill="${soft}"/>`,
    pages: ({ink, soft}) => `<rect x="100" y="40" width="108" height="144" rx="16" fill="${soft}" transform="rotate(10 154 112)"/>` +
        `<rect x="52" y="64" width="116" height="152" rx="16" fill="${ink}"/>` + line('M76 100h68M76 126h68M76 152h68M76 178h40', soft, 10),
    play: ({ink, soft}) => `<rect x="36" y="56" width="184" height="144" rx="30" fill="${ink}"/>` +
        `<path d="M110 96v64l54-32z" fill="${soft}" stroke="${soft}" stroke-width="12" stroke-linejoin="round"/>`,
    scanner: ({ink, soft}) => `<path d="M52 118l148-46a8 8 0 0 1 10 5l3 10-160 50z" fill="${ink}"/>` +
        `<rect x="40" y="130" width="176" height="76" rx="18" fill="${ink}"/>` + line('M64 158h128', soft, 9) + `<circle cx="188" cy="186" r="7" fill="${soft}"/>`,
    camera: ({ink, soft}) => `<path d="M40 92a18 18 0 0 1 18-18h30l14-20h52l14 20h30a18 18 0 0 1 18 18v98a18 18 0 0 1-18 18H58a18 18 0 0 1-18-18z" fill="${ink}"/>` +
        `<circle cx="128" cy="140" r="36" fill="none" stroke="${soft}" stroke-width="14"/><circle cx="128" cy="140" r="12" fill="${soft}"/><circle cx="184" cy="100" r="8" fill="${soft}"/>`,
    notes2: ({ink}) => `<ellipse cx="92" cy="178" rx="26" ry="20" transform="rotate(-20 92 178)" fill="${ink}"/>` +
        `<ellipse cx="172" cy="160" rx="26" ry="20" transform="rotate(-20 172 160)" fill="${ink}"/>` +
        `<path d="M106 172V74l88-20v100h-14V86l-60 14v72z" fill="${ink}"/>`,
    weather: ({ink, soft}) => `<circle cx="96" cy="88" r="28" fill="${soft}"/>` +
        line([0, 45, 90, 135, 180, 225, 270, 315].map(a => {
            const r = (a * Math.PI) / 180;
            return `M${f(96 + 40 * Math.cos(r))} ${f(88 + 40 * Math.sin(r))}L${f(96 + 52 * Math.cos(r))} ${f(88 + 52 * Math.sin(r))}`;
        }).join(''), soft, 9) +
        `<path d="M82 204h100a38 38 0 0 0 6-75 54 54 0 0 0-101-12 44 44 0 0 0-5 87z" fill="${ink}"/>`,
    pie: ({ink, soft}) => `<path d="M120 140V64a76 76 0 1 0 76 76z" fill="${ink}"/><path d="M134 126V50a76 76 0 0 1 76 76z" fill="${soft}"/>`,
    alarm: ({ink, soft}) => `<circle cx="74" cy="78" r="26" fill="${soft}"/><circle cx="182" cy="78" r="26" fill="${soft}"/>` +
        line('M84 196l-14 16M172 196l14 16', soft, 12) + `<circle cx="128" cy="138" r="70" fill="${ink}"/>` + line('M128 98v42l26 18', soft, 13),
    letter: ({ink, soft}) => `<path fill-rule="evenodd" d="M110 48h36l62 160h-36l-14-38H98l-14 38H48zM128 92l-20 52h40z" fill="${ink}"/>` +
        line('M98 152h60', soft, 8),
    code: ({ink, soft}) => `<rect x="44" y="44" width="168" height="168" rx="40" fill="${ink}"/>` +
        line('M106 100l-28 28 28 28M150 100l28 28-28 28', soft, 14) + line('M138 90l-20 76', soft, 12),

    // ---- Places --------------------------------------------------------------------------------------------------
    folder: c => folder(c),
    ...Object.fromEntries(Object.entries(EMBLEM).map(([name, draw]) => [`folder-${name}`, c => folder(c, draw(c.soft))])),
    home: ({ink, soft}) => `<path d="M48 122l80-70 80 70v78a14 14 0 0 1-14 14H62a14 14 0 0 1-14-14z" fill="${ink}" stroke="${ink}" stroke-width="8" stroke-linejoin="round"/>` +
        `<rect x="108" y="150" width="40" height="64" rx="10" fill="${soft}"/>`,
    trash: ({ink, soft}) => `<path d="M70 94h116l-10 106a14 14 0 0 1-14 12H94a14 14 0 0 1-14-12z" fill="${ink}"/>` +
        `<rect x="56" y="66" width="144" height="20" rx="10" fill="${soft}"/>` + line('M108 64v-8a8 8 0 0 1 8-8h24a8 8 0 0 1 8 8v8', soft, 8) +
        line('M106 118v70M128 118v70M150 118v70', soft, 9),
    'trash-full': ({ink, soft}) => `<path d="M70 104h116l-10 96a14 14 0 0 1-14 12H94a14 14 0 0 1-14-12z" fill="${ink}"/>` +
        `<circle cx="102" cy="84" r="20" fill="${soft}"/><circle cx="142" cy="78" r="24" fill="${soft}"/><circle cx="170" cy="92" r="14" fill="${soft}"/>` +
        `<rect x="66" y="52" width="140" height="20" rx="10" fill="${soft}" transform="rotate(-14 200 62)"/>` + line('M106 128v62M128 128v62M150 128v62', soft, 9),
    server: ({ink, soft}) => [48, 106, 164].map(y => `<rect x="52" y="${y}" width="152" height="46" rx="14" fill="${ink}"/>` +
        line(`M76 ${y + 23}h44`, soft, 9) + `<circle cx="178" cy="${y + 23}" r="8" fill="${soft}"/>`).join(''),
    bookmark: ({ink, soft}) => `<path d="M80 40h96a14 14 0 0 1 14 14v164l-62-40-62 40V54a14 14 0 0 1 14-14z" fill="${ink}"/>` +
        `<path d="${starPath(128, 108, 30, 13)}" fill="${soft}" stroke="${soft}" stroke-width="4" stroke-linejoin="round"/>`,
    avatar: ({ink, soft}) => `<circle cx="128" cy="128" r="84" fill="${ink}"/><circle cx="128" cy="104" r="32" fill="${soft}"/>` +
        `<path d="M74 190a54 48 0 0 1 108 0 84 84 0 0 1-108 0z" fill="${soft}"/>`,

    // ---- File types --------------------------------------------------------------------------------------------------
    text: c => page(c, line('M86 112h84M86 140h84M86 168h52', c.soft, 11)),
    script: c => page(c, line('M106 122l-22 24 22 24M150 122l22 24-22 24', c.soft, 12) + line('M136 114l-16 64', c.soft, 10)),
    html: c => page(c, `<circle cx="128" cy="146" r="36" fill="none" stroke="${c.soft}" stroke-width="9"/>` +
        `<ellipse cx="128" cy="146" rx="15" ry="36" fill="none" stroke="${c.soft}" stroke-width="8"/>` + line('M92 146h72', c.soft, 8)),
    image: c => page(c, `<path d="M84 190l32-40 24 28 14-16 32 28z" fill="${c.soft}" stroke="${c.soft}" stroke-width="5" stroke-linejoin="round"/><circle cx="150" cy="114" r="14" fill="${c.soft}"/>`),
    audio: c => page(c, `<circle cx="108" cy="178" r="14" fill="${c.soft}"/><circle cx="154" cy="166" r="14" fill="${c.soft}"/>` +
        `<path d="M114 178v-58l48-12v58h-8v-44l-32 8v48z" fill="${c.soft}"/>`),
    video: c => page(c, `<path d="M110 118v58l48-29z" fill="${c.soft}" stroke="${c.soft}" stroke-width="9" stroke-linejoin="round"/>`),
    pdf: c => page(c, `<rect x="84" y="100" width="88" height="48" rx="9" fill="${c.soft}"/>` + line('M86 168h84M86 190h56', c.soft, 9)),
    document: c => page(c, line('M86 104h56', c.soft, 15) + line('M86 132h84M86 156h84M86 180h60', c.soft, 9)),
    spreadsheet: c => page(c, `<rect x="84" y="102" width="88" height="90" rx="9" fill="none" stroke="${c.soft}" stroke-width="8"/>` +
        line('M84 132h88M84 162h88M114 102v90M144 102v90', c.soft, 6)),
    presentation: c => page(c, `<rect x="88" y="150" width="20" height="42" rx="5" fill="${c.soft}"/><rect x="118" y="124" width="20" height="68" rx="5" fill="${c.soft}"/><rect x="148" y="104" width="20" height="88" rx="5" fill="${c.soft}"/>`),
    drawing: c => page(c, `<circle cx="108" cy="124" r="22" fill="${c.soft}"/><path d="M152 106l26 46h-52z" fill="${c.soft}" stroke="${c.soft}" stroke-width="4" stroke-linejoin="round"/><rect x="94" y="160" width="76" height="30" rx="8" fill="${c.soft}"/>`),
    font: c => page(c, `<path fill-rule="evenodd" d="M116 100h24l34 92h-24l-7-20h-34l-7 20H78zM128 128l-10 28h20z" fill="${c.soft}"/>`),
    template: c => page(c, `<rect x="88" y="104" width="80" height="82" rx="9" fill="none" stroke="${c.soft}" stroke-width="8" stroke-dasharray="12 9"/>`),
    package: ({ink, soft}) => `<rect x="48" y="92" width="160" height="120" rx="16" fill="${ink}"/>` +
        `<rect x="40" y="56" width="176" height="44" rx="14" fill="${ink}"/>` + line('M48 104h160', soft, 6) +
        `<rect x="114" y="56" width="28" height="156" fill="${soft}"/>`,
    addon: ({ink}) => `<path d="M62 78h32a20 20 0 1 1 40 0h40v40a20 20 0 1 1 0 40v40H62v-40a20 20 0 1 0 0-40z" fill="${ink}"/>`,

    // ---- Devices -----------------------------------------------------------------------------------------------------
    laptop: ({ink, soft}) => `<rect x="56" y="52" width="144" height="104" rx="16" fill="${ink}"/>` +
        `<rect x="70" y="66" width="116" height="76" rx="8" fill="${soft}" fill-opacity="0.6"/>` +
        `<path d="M32 168h192l-10 24a14 14 0 0 1-13 8H55a14 14 0 0 1-13-8z" fill="${ink}"/>`,
    phone: ({ink, soft}) => `<rect x="74" y="36" width="108" height="184" rx="26" fill="${ink}"/>` +
        `<rect x="88" y="60" width="80" height="132" rx="10" fill="${soft}" fill-opacity="0.6"/><rect x="112" y="46" width="32" height="7" rx="3.5" fill="${soft}"/>` +
        `<rect x="108" y="202" width="40" height="7" rx="3.5" fill="${soft}"/>`,
    usb: ({ink, soft}) => `<rect x="104" y="40" width="48" height="56" rx="6" fill="${soft}"/>` +
        `<rect x="114" y="54" width="10" height="10" rx="2" fill="${ink}"/><rect x="132" y="54" width="10" height="10" rx="2" fill="${ink}"/>` +
        `<rect x="88" y="92" width="80" height="124" rx="20" fill="${ink}"/>` + line('M114 150h28', soft, 9),
    card: ({ink, soft}) => `<path d="M72 40h84l44 44v116a16 16 0 0 1-16 16H72a16 16 0 0 1-16-16V56a16 16 0 0 1 16-16z" fill="${ink}"/>` +
        [0, 1, 2, 3].map(i => `<rect x="${78 + i * 20}" y="56" width="11" height="34" rx="4" fill="${soft}"/>`).join(''),
    disc: ({ink, soft}) => `<path fill-rule="evenodd" d="${circlePath(128, 128, 84)}${circlePath(128, 128, 16)}" fill="${ink}"/>` +
        `<circle cx="128" cy="128" r="46" fill="none" stroke="${soft}" stroke-width="10" stroke-opacity="0.8"/>` + line('M78 90a64 64 0 0 1 40-26', soft, 9),
    webcam: ({ink, soft}) => `<circle cx="128" cy="104" r="64" fill="${ink}"/><path d="M116 164h24v28h-24z" fill="${ink}"/>` +
        line('M84 204h88', ink, 16) + `<circle cx="128" cy="104" r="26" fill="${soft}"/><circle cx="168" cy="70" r="7" fill="${soft}"/>`,
    printer: ({ink, soft}) => `<rect x="76" y="44" width="104" height="60" rx="8" fill="${soft}"/>` +
        `<rect x="36" y="92" width="184" height="88" rx="20" fill="${ink}"/>` +
        `<rect x="70" y="156" width="116" height="60" rx="8" fill="${soft}"/>` + `<circle cx="190" cy="120" r="8" fill="${soft}"/>`,
    keyboard: ({ink, soft}) => `<rect x="32" y="72" width="192" height="112" rx="22" fill="${ink}"/>` +
        [0, 1].map(r => [0, 1, 2, 3, 4, 5].map(k => `<rect x="${54 + k * 26}" y="${92 + r * 26}" width="18" height="18" rx="5" fill="${soft}"/>`).join('')).join('') +
        `<rect x="80" y="146" width="96" height="18" rx="6" fill="${soft}"/>`,
    mouse: ({ink, soft}) => `<rect x="78" y="40" width="100" height="176" rx="50" fill="${ink}"/>` +
        `<rect x="120" y="70" width="16" height="34" rx="8" fill="${soft}"/>` + line('M128 40v22', soft, 6),
    gamepad: ({ink, soft}) => `<g transform="translate(128 128) scale(0.88) translate(-128 -128)">` +
        `<path d="M72 74h112c28 0 42 24 46 62l6 48c3 24-22 36-39 19l-27-27H86l-27 27c-17 17-42 5-39-19l6-48c4-38 18-62 46-62z" fill="${ink}"/>` +
        line('M78 112v38M59 131h38', soft, 13) + `<circle cx="172" cy="116" r="11" fill="${soft}"/><circle cx="196" cy="140" r="11" fill="${soft}"/></g>`,
    tablet: ({ink, soft}) => `<rect x="36" y="60" width="156" height="148" rx="22" fill="${ink}"/>` +
        `<path d="M206 46l18 18-84 84-28 10 10-28z" fill="${soft}" stroke="${soft}" stroke-width="4" stroke-linejoin="round"/>`,
    headphones: ({ink, soft}) => line('M60 160v-28a68 68 0 0 1 136 0v28', ink, 18) +
        `<rect x="40" y="136" width="44" height="76" rx="20" fill="${ink}"/><rect x="172" y="136" width="44" height="76" rx="20" fill="${ink}"/>` +
        `<rect x="54" y="150" width="16" height="48" rx="8" fill="${soft}"/><rect x="186" y="150" width="16" height="48" rx="8" fill="${soft}"/>`,
    speaker: ({ink, soft}) => `<rect x="68" y="36" width="120" height="184" rx="24" fill="${ink}"/>` +
        `<circle cx="128" cy="80" r="16" fill="${soft}"/><circle cx="128" cy="158" r="36" fill="none" stroke="${soft}" stroke-width="12"/><circle cx="128" cy="158" r="10" fill="${soft}"/>`,
    microphone: ({ink, soft}) => `<rect x="94" y="36" width="68" height="116" rx="34" fill="${ink}"/>` +
        line('M108 72h40M108 94h40M108 116h40', soft, 8) + line('M66 118a62 62 0 0 0 124 0M128 182v26M98 212h60', ink, 14),
    plug: ({ink, soft}) => `<rect x="100" y="44" width="14" height="44" rx="4" fill="${soft}"/><rect x="142" y="44" width="14" height="44" rx="4" fill="${soft}"/>` +
        `<path d="M76 84h104v56a36 36 0 0 1-36 36h-32a36 36 0 0 1-36-36z" fill="${ink}"/>` + line('M128 176v36', ink, 20),

    // ---- Categories --------------------------------------------------------------------------------------------------
    globe: ({ink, soft}) => `<circle cx="128" cy="128" r="80" fill="${ink}"/>` +
        `<ellipse cx="128" cy="128" rx="32" ry="80" fill="none" stroke="${soft}" stroke-width="9"/>` + line('M48 128h160M62 90h132M62 166h132', soft, 8),
    flask: ({ink, soft}) => `<path d="M106 40h44v18h-4v42l54 88a16 16 0 0 1-14 24H70a16 16 0 0 1-14-24l54-88V58h-4z" fill="${ink}" stroke="${ink}" stroke-width="6" stroke-linejoin="round"/>` +
        `<path d="M84 160h88l18 30a8 8 0 0 1-7 12H73a8 8 0 0 1-7-12z" fill="${soft}"/><circle cx="118" cy="136" r="7" fill="${soft}"/><circle cx="140" cy="120" r="5" fill="${soft}"/>`,
    cap: ({ink, soft}) => `<g transform="translate(128 128) scale(0.92) translate(-128 -128)"><path d="M128 52l100 46-100 46-100-46z" fill="${ink}" stroke="${ink}" stroke-width="8" stroke-linejoin="round"/>` +
        `<path d="M72 126v44c0 18 25 32 56 32s56-14 56-32v-44l-56 26z" fill="${ink}"/>` + line('M210 104v58', soft, 8) + `<circle cx="210" cy="170" r="11" fill="${soft}"/></g>`,
};
