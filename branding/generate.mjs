// Generates the Amethystora artwork under system_files/ from the geometry and palette below.
//
//   node branding/generate.mjs
//
// SVGs and the fastfetch logo are written directly. PNGs are rendered with a
// headless Chromium browser (Edge or Chrome); set BROWSER to its path if it is
// not found automatically.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tmpdir } from "node:os";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SHARED = join(ROOT, "system_files/shared");

// -------------------------------------------------------------- palette --

// Sampled from a deep amethyst, from the shadow in its pavilion to the glint on its crown
const SHADES = ["#16042c", "#260850", "#380d78", "#4a13a0", "#5d1ac4", "#7429e0", "#9148f0", "#b37df9", "#dcbcff"];

// The desktop accent (boot splash, fastfetch): a dark amethyst that still reads on dark surfaces.
// 06-branding.sh carries the same value.
const ACCENT = "#7c3aed";

// ---------------------------------------------------------------- the gem --

// Pear-cut gem in a 256x256 box, point up. The outline is a teardrop sampled at 64 points evenly spaced
// along it, starting at the tip; every fourth point is one of the 16 girdle vertices the crown facets meet.
const OUTLINE_POINTS = 64;
const OUTLINE = (() => {
  const [top, bottom, halfWidth] = [14, 242, 86];
  const fine = Array.from({ length: 4096 }, (_, k) => {
    const a = (2 * Math.PI * k) / 4096;
    return [Math.sin(a) * Math.pow(Math.sin(a / 2), 0.9), -Math.cos(a)];
  });
  const maxX = Math.max(...fine.map(([x]) => x));
  const curve = fine.map(([x, y]) => [128 + (x / maxX) * halfWidth, top + ((y + 1) / 2) * (bottom - top)]);
  const along = [0];
  curve.forEach(([x, y], i) => {
    const [nx, ny] = curve[(i + 1) % curve.length];
    along.push(along[i] + Math.hypot(nx - x, ny - y));
  });
  const length = along[curve.length];
  let i = 0;
  return Array.from({ length: OUTLINE_POINTS }, (_, k) => {
    while (along[i + 1] < (k * length) / OUTLINE_POINTS) i++;
    return curve[i];
  });
})();

// Tight bounds of the gem, for the bitmaps: [x, y, width, height]
const BOUNDS = (() => {
  const xs = OUTLINE.map(([x]) => x);
  const ys = OUTLINE.map(([, y]) => y);
  const [x0, y0] = [Math.min(...xs), Math.min(...ys)];
  return [x0, y0, Math.max(...xs) - x0, Math.max(...ys) - y0].map((v) => Math.round(v));
})();

// The table and star facets are laid out around the centroid of the outline, which sits below the middle
const CENTER = (() => {
  let [area, cx, cy] = [0, 0, 0];
  OUTLINE.forEach(([x0, y0], i) => {
    const [x1, y1] = OUTLINE[(i + 1) % OUTLINE.length];
    const cross = x0 * y1 - x1 * y0;
    area += cross / 2;
    cx += ((x0 + x1) * cross) / 6;
    cy += ((y0 + y1) * cross) / 6;
  });
  return [cx / area, cy / area];
})();

const mod = (n, m) => ((n % m) + m) % m;
const toward = ([x0, y0], [x1, y1], s) => [x0 + (x1 - x0) * s, y0 + (y1 - y0) * s];

// Points of the crown with their height above the girdle: girdle vertices, the tips of the star facets
// and the corners of the table.
const girdle = (k) => [...OUTLINE[mod(k, 16) * 4], 0];
const star = (i) => [...toward(CENTER, OUTLINE[mod(2 * i + 1, 16) * 4], 0.78), 20];
const table = (i) => [...toward(CENTER, OUTLINE[mod(2 * i, 16) * 4], 0.5), 30];
// The outline between two girdle vertices, so the upper girdle facets follow the curve
const arc = (k0, k1) =>
  Array.from({ length: (k1 - k0) * 4 + 1 }, (_, j) => [...OUTLINE[mod(k0 * 4 + j, OUTLINE_POINTS)], 0]);

// Light comes from the upper left, in front of the gem
const LIGHT = (() => {
  const l = [-0.45, -0.7, 0.55];
  const n = Math.hypot(...l);
  return l.map((c) => c / n);
})();
const HALF = (() => {
  const h = [LIGHT[0], LIGHT[1], LIGHT[2] + 1];
  const n = Math.hypot(...h);
  return h.map((c) => c / n);
})();
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

// Brightness of a crown facet from about -1 (shadow) to 1 (glint), from the plane through its first three points
function crownLevel([a, b, c]) {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  const v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
  const len = Math.hypot(...n) * Math.sign(n[2]);
  const normal = n.map((x) => x / len);
  const diffuse = Math.max(0, dot(normal, LIGHT));
  const glint = Math.pow(Math.max(0, dot(normal, HALF)), 60);
  return (diffuse - 0.55) * 1.6 + glint * 0.9;
}

// 8 star, 8 bezel and 16 upper girdle facets on the crown, shaded by the way they face; neighbouring girdle
// facets alternate lighter and darker, as a cut stone sparkles. The table shows the pavilion below it as
// 8 wedges, brightest opposite the light and alternately catching and missing it.
const FACETS = (() => {
  const facets = [];
  const add = (pts, level) => facets.push({ pts: pts.map(([x, y]) => [x, y]), level });
  const crown = (pts, bias = 0) => add(pts, crownLevel(pts) + bias);
  for (let i = 0; i < 8; i++) {
    crown([table(i), star(i - 1), girdle(2 * i), star(i)]);
    crown([table(i), star(i), table(i + 1)], -0.1);
    const sparkle = i % 2 ? 0.22 : -0.08;
    crown([star(i), ...arc(2 * i, 2 * i + 1)], sparkle);
    crown([star(i), ...arc(2 * i + 1, 2 * i + 2)], 0.14 - sparkle);
  }
  const away = Math.atan2(-LIGHT[1], -LIGHT[0]);
  for (let i = 0; i < 8; i++) {
    const [mx, my] = toward(table(i), table(i + 1), 0.5);
    const facing = Math.cos(Math.atan2(my - CENTER[1], mx - CENTER[0]) - away);
    add([[...CENTER], table(i), table(i + 1)], 0.1 + 0.35 * facing + (i % 2 ? 0.2 : -0.2));
  }
  return facets;
})();

const clamp01 = (x) => Math.min(1, Math.max(0, x));
// Facets use every shade but the darkest, which would read as a hole in the gem
const shadeOf = (level) => SHADES[1 + Math.round(clamp01((level + 1) / 2) * (SHADES.length - 2))];
const opacityOf = (level) => (0.45 + 0.55 * clamp01((level + 1) / 2)).toFixed(2);

const pointList = (pts) => pts.map(([x, y]) => `${+x.toFixed(1)},${+y.toFixed(1)}`).join(" ");

// A silhouette under the coloured facets, and each facet stroked in its own colour, hide the hairline seams
// antialiasing leaves between them
function gemPolygons(white = false) {
  if (white) {
    return FACETS.map(
      (f) => `<polygon points="${pointList(f.pts)}" fill="#ffffff" fill-opacity="${opacityOf(f.level)}"/>`,
    ).join("\n  ");
  }
  const base = `<polygon points="${pointList(OUTLINE)}" fill="${SHADES[3]}"/>`;
  const facets = FACETS.map((f) => {
    const color = shadeOf(f.level);
    return `<polygon points="${pointList(f.pts)}" fill="${color}" stroke="${color}" stroke-width="0.6" stroke-linejoin="round"/>`;
  });
  return [base, ...facets].join("\n  ");
}

// The icon keeps the padded 256x256 box; bitmaps use the tight bounds of the gem.
const gemSvg = (white = false, viewBox = "0 0 256 256") => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">
  ${gemPolygons(white)}
</svg>
`;

// ---------------------------------------------------------------- icons --

// Amethystora versions of the Universal Blue icons shipped by projectbluefin/common; 06-branding.sh points
// the launchers at these names and deletes the originals.

// Symbolic (single colour, recoloured by GTK): the straight-sided table, and the crown around it as four facets
// split at the table's diagonal corners, with gaps between them.
const symbolicSvg = (() => {
  const s = 14 / BOUNDS[3];
  const px = (p, scale) => {
    const [x, y] = toward(CENTER, p, scale);
    return [8 + (x - 128) * s, 1 + (y - BOUNDS[1]) * s].map((v) => +v.toFixed(2)).join(",");
  };
  // A point on the octagon through every eighth outline point, the straight-sided counterpart of the outline
  const octagon = (k) => {
    const j = Math.floor(k / 8);
    return toward(OUTLINE[mod(8 * j, OUTLINE_POINTS)], OUTLINE[mod(8 * j + 8, OUTLINE_POINTS)], (k - 8 * j) / 8);
  };
  const path = (pts) => "M" + pts.join("L") + "z";
  const table = path([0, 8, 16, 24, 32, 40, 48, 56].map((k) => px(octagon(k), 0.46)));
  const crown = [-8, 8, 24, 40].map((from) => {
    const ks = Array.from({ length: 13 }, (_, j) => from + 2 + j);
    const inner = [from + 2, ...ks.filter((k) => k % 8 === 0), from + 14].reverse();
    return path([...ks.map((k) => px(OUTLINE[mod(k, OUTLINE_POINTS)], 1)), ...inner.map((k) => px(octagon(k), 0.64))]);
  });
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path fill="#2e3436" d="${[table, ...crown].join("")}"/>
</svg>
`;
})();

// Full-colour app icon: white glyph on a rounded amethyst tile.
const tileSvg = (glyph) => `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${SHADES[6]}"/>
      <stop offset="1" stop-color="${SHADES[2]}"/>
    </linearGradient>
  </defs>
  <rect x="16" y="16" width="224" height="224" rx="52" fill="url(#tile)"/>
  ${glyph}
</svg>
`;

// The gem centred on the tile, in white facets
const docsGlyph = (() => {
  const s = 156 / BOUNDS[3];
  const [tx, ty] = [128 - s * (BOUNDS[0] + BOUNDS[2] / 2), 128 - s * (BOUNDS[1] + BOUNDS[3] / 2)];
  return `<g transform="translate(${tx.toFixed(1)} ${ty.toFixed(1)}) scale(${s.toFixed(3)})">
    ${gemPolygons(true)}
  </g>`;
})();

const communityGlyph = `<g fill="#ffffff">
    <rect x="108" y="118" width="88" height="64" rx="16" fill-opacity="0.7"/>
    <path d="M172 182l10 22 6-22z" fill-opacity="0.7"/>
    <rect x="60" y="68" width="108" height="76" rx="18"/>
    <path d="M80 144l-6 24 28-24z"/>
  </g>
  <g fill="${SHADES[4]}">
    <circle cx="92" cy="106" r="8"/>
    <circle cx="114" cy="106" r="8"/>
    <circle cx="136" cy="106" r="8"/>
  </g>`;

const updateGlyph = `<g fill="none" stroke="#ffffff" stroke-width="20">
    <path d="M79.1 110.2A52 52 0 0 1 172 100"/>
    <path d="M176.9 145.8A52 52 0 0 1 84 156"/>
  </g>
  <g fill="#ffffff">
    <path d="M154 94h40l-20 28z"/>
    <path d="M62 162h40l-20-28z"/>
  </g>`;

// ----------------------------------------------------------- wallpapers --

// A hexagonal crystal point: three visible column faces capped by three pyramid faces.
function crystal({ x, base, w, h, tip, rot, faces }) {
  const top = base - h;
  const xs = [x - w / 2, x - w / 4, x + w / 4, x + w / 2];
  const apex = `${x},${top - tip}`;
  const polys = [];
  for (let i = 0; i < 3; i++) {
    polys.push(`<polygon points="${xs[i]},${base} ${xs[i]},${top} ${xs[i + 1]},${top} ${xs[i + 1]},${base}" fill="${faces.column[i]}"/>`);
    polys.push(`<polygon points="${xs[i]},${top} ${xs[i + 1]},${top} ${apex}" fill="${faces.tip[i]}"/>`);
  }
  return `<g transform="rotate(${rot} ${x} ${base})">${polys.join("")}</g>`;
}

const CLUSTER = [
  { x: 2180, base: 2500, w: 200, h: 640, tip: 170, rot: -38 },
  { x: 3740, base: 2500, w: 220, h: 700, tip: 180, rot: 30 },
  { x: 2520, base: 2450, w: 300, h: 980, tip: 250, rot: -21 },
  { x: 3360, base: 2450, w: 340, h: 1060, tip: 270, rot: 15 },
  { x: 2920, base: 2450, w: 420, h: 1380, tip: 330, rot: -5 },
];

function wallpaperSvg(theme) {
  const t = theme === "dark"
    ? {
        bg: ["#0e0419", "#1f0840", "#35106a"],
        glowA: ["#7429e0", 0.45], glowB: ["#4a13a0", 0.5],
        faces: { column: ["#5d1ac4", "#4a13a0", "#2c0a5c"], tip: ["#9148f0", "#7429e0", "#4a13a0"] },
        shade: "#0e0419",
      }
    : {
        bg: ["#f6f0fd", "#e2d2f8", "#c6a8f0"],
        glowA: ["#ffffff", 0.7], glowB: ["#9148f0", 0.3],
        faces: { column: ["#9148f0", "#7429e0", "#5d1ac4"], tip: ["#dcbcff", "#b37df9", "#9148f0"] },
        shade: "#c6a8f0",
      };
  return `<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="2160" viewBox="0 0 3840 2160">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${t.bg[0]}"/>
      <stop offset="0.55" stop-color="${t.bg[1]}"/>
      <stop offset="1" stop-color="${t.bg[2]}"/>
    </linearGradient>
    <radialGradient id="glowA" cx="2900" cy="900" r="1700" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="${t.glowA[0]}" stop-opacity="${t.glowA[1]}"/>
      <stop offset="1" stop-color="${t.glowA[0]}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glowB" cx="600" cy="2000" r="1500" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="${t.glowB[0]}" stop-opacity="${t.glowB[1]}"/>
      <stop offset="1" stop-color="${t.glowB[0]}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0.55" stop-color="${t.shade}" stop-opacity="0"/>
      <stop offset="1" stop-color="${t.shade}" stop-opacity="0.85"/>
    </linearGradient>
  </defs>
  <rect width="3840" height="2160" fill="url(#bg)"/>
  <rect width="3840" height="2160" fill="url(#glowA)"/>
  <rect width="3840" height="2160" fill="url(#glowB)"/>
  ${CLUSTER.map((c) => crystal({ ...c, faces: t.faces })).join("\n  ")}
  <rect width="3840" height="2160" fill="url(#fade)"/>
</svg>
`;
}

// ------------------------------------------------------- boot splash --

// The splash starts with the gem shattered, its pieces scattered around the screen. They converge and lock
// together with a flash, then the gem glows in a cloud of violet dust: the glow rises to a peak and falls
// back to where it started, over and over. BOOT_TIMELINE drives the browser preview (node branding/generate.mjs
// --preview) and bootScript() ports it to Plymouth's script language, so both play the same animation. It
// sticks to the maths that language has: no exp, pow or floor.
//
// The artwork is drawn in the gem's 256-unit box; BOOT.unit converts that to pixels on a 1080p screen.
const BOOT = {
  unit: 280 / BOUNDS[3], // the gem stands 280px tall at 1080p
  centerY: 0.46, // of the screen height
  // s of plain sky before anything appears: when the graphics driver takes over, a monitor can take a second or
  // two to show a picture again, and the assembly would play before anyone could see it
  hold: 2,
  fadeIn: 0.4, // s for the scattered pieces to appear
  converge: 0.6, // s before the first piece starts moving in
  travel: 1.1, // s each piece takes to reach its place
  settle: 0.6, // s from the flash to the first glow cycle
  cycle: 3.2, // s per glow cycle
  halo: 760, // px across at 1080p
  dust: 40,
  sky: ["#0d0714", "#1a0a2e"], // background, top to bottom
};

// A seeded generator, so every run of this script draws the same scatter and dust
function random(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const centroid = (pts) => [0, 1].map((c) => pts.reduce((sum, p) => sum + p[c], 0) / pts.length);

// The gem breaks along its facet lines into nine pieces: eight slices of the crown, each a bezel facet with
// the star facet and the two girdle facets beside it, and the table, which lands last.
const PIECES = [
  ...Array.from({ length: 8 }, (_, i) => [
    table(i), star(i - 1), girdle(2 * i), ...arc(2 * i, 2 * i + 2).slice(1), star(i), table(i + 1),
  ]),
  Array.from({ length: 8 }, (_, i) => table(i)),
].map((pts) => pts.map(([x, y]) => [x, y]));

// Each piece flies in from a point out beyond it, turning as it comes. dx/dy/spin are where it hangs at the
// start, in gem units and radians, drift how far it keeps moving out while it hangs.
const SHARDS = (() => {
  const rnd = random(7);
  return PIECES.map((pts, i) => {
    const xs = pts.map(([x]) => x);
    const ys = pts.map(([, y]) => y);
    const c = [(Math.min(...xs) + Math.max(...xs)) / 2, (Math.min(...ys) + Math.max(...ys)) / 2];
    const side = Math.ceil(Math.hypot(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys))) + 8;
    const [mx, my] = centroid(pts);
    const away = Math.atan2(my - CENTER[1], mx - CENTER[0]) + (rnd() - 0.5) * 1.2;
    const dist = 170 + rnd() * 130;
    const turn = (Math.PI / 180) * (50 + rnd() * 110) * (rnd() < 0.5 ? -1 : 1);
    return {
      pts, c, side,
      dx: Math.cos(away) * dist, dy: Math.sin(away) * dist, dirx: Math.cos(away), diry: Math.sin(away),
      drift: 10 + rnd() * 14, spin: turn, spinRate: (rnd() - 0.5) * 0.5,
      delay: (i / (PIECES.length - 1)) * 0.3 + rnd() * 0.08,
    };
  });
})();
BOOT.assembled = BOOT.converge + BOOT.travel + Math.max(...SHARDS.map((sh) => sh.delay));

// Dust hangs in an oval around the gem and rises slowly through it, swaying and twinkling. Positions are
// in gem units from the centre of the table.
const DUST = (() => {
  const rnd = random(23);
  return Array.from({ length: BOOT.dust }, () => {
    const a = rnd() * 2 * Math.PI;
    const r = 80 + rnd() * 190;
    return {
      x: Math.cos(a) * r, y: Math.sin(a) * r * 1.2, size: 2 + rnd() * 4, rise: 5 + rnd() * 12,
      sway: 3 + rnd() * 10, swayRate: 0.3 + rnd() * 0.6, twinkle: 0.8 + rnd() * 2, phase: rnd() * 2 * Math.PI,
    };
  });
})();

// One piece of the gem, drawn exactly as the logo, in a square around it with room to turn
const shardSvg = (s) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${[s.c[0] - s.side / 2, s.c[1] - s.side / 2, s.side, s.side].join(" ")}">
  <defs><clipPath id="piece"><polygon points="${pointList(s.pts)}"/></clipPath></defs>
  <g clip-path="url(#piece)">
  ${gemPolygons()}
  </g>
</svg>
`;

// The light that wells up from the table as the gem glows
const lightSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <defs>
    <radialGradient id="light" cx="${CENTER[0].toFixed(1)}" cy="${CENTER[1].toFixed(1)}" r="120" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/>
      <stop offset="0.25" stop-color="#e3a2ff" stop-opacity="0.45"/>
      <stop offset="1" stop-color="${SHADES[7]}" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="gem"><polygon points="${pointList(OUTLINE)}"/></clipPath>
  </defs>
  <rect x="0" y="0" width="256" height="256" fill="url(#light)" clip-path="url(#gem)"/>
</svg>
`;

const mix = (a, b, s) =>
  "#" + [1, 3, 5].map((i) => {
    const [x, y] = [a, b].map((hex) => parseInt(hex.slice(i, i + 2), 16));
    return Math.round(x + (y - x) * s).toString(16).padStart(2, "0");
  }).join("");

// 41 gradient stops of a(o), o running from the centre (0) to the rim (1), the colour blending from inner to
// outer. Enough stops that the steps between them never show as rings.
const stops = (inner, outer, a) =>
  Array.from({ length: 41 }, (_, i) => {
    const o = i / 40;
    return `<stop offset="${o}" stop-color="${mix(inner, outer, o)}" stop-opacity="${a(o).toFixed(3)}"/>`;
  }).join("");

// Where the heart of the gem sits on the 1080p screen
const HEART_PX = [960 + (CENTER[0] - 128) * BOOT.unit, 1080 * BOOT.centerY + (CENTER[1] - 128) * BOOT.unit];

// Violet smoke over the whole screen, in a 480x270 box stretched to it: two layers of fractal noise thin and
// thicken a glow that is densest around the gem and thins out towards the corners without ever ending.
const nebulaSvg = (() => {
  const [cx, cy] = HEART_PX.map((v) => v / 4);
  const layer = (seed, frequency, color, peak, floor) => {
    const falloff = (o) => peak * (floor + (1 - floor) * Math.exp(-3.5 * o * o));
    return `<filter id="smoke${seed}" x="-10%" y="-10%" width="120%" height="120%">
      <feTurbulence type="fractalNoise" baseFrequency="${frequency}" numOctaves="4" seed="${seed}"/>
      <feColorMatrix values="2 0 0 0 -0.5  2 0 0 0 -0.5  2 0 0 0 -0.5  0 0 0 0 1"/>
      <feGaussianBlur stdDeviation="2.5"/>
    </filter>
    <mask id="clouds${seed}"><rect width="480" height="270" filter="url(#smoke${seed})"/></mask>
    <radialGradient id="fall${seed}" cx="${cx}" cy="${cy}" r="300" gradientUnits="userSpaceOnUse">${stops(color, SHADES[3], falloff)}</radialGradient>`;
  };
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 270" preserveAspectRatio="none">
  <defs>
    ${layer(3, 0.014, SHADES[6], 0.8, 0.12)}
    ${layer(11, 0.024, SHADES[5], 0.45, 0.1)}
  </defs>
  <rect width="480" height="270" fill="url(#fall3)" mask="url(#clouds3)"/>
  <rect width="480" height="270" fill="url(#fall11)" mask="url(#clouds11)"/>
</svg>
`;
})();

// The soft glow right around the gem that brightens and dims with it: a bell curve that flattens out to
// nothing before its rim, so it has no edge.
const haloSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
  <defs><radialGradient id="halo">${stops(SHADES[7], SHADES[6], (o) => 0.8 * Math.exp(-4 * o * o) * (1 - o * o) ** 2)}</radialGradient></defs>
  <ellipse cx="100" cy="100" rx="86" ry="100" fill="url(#halo)"/>
</svg>
`;

const dustSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -10 20 20">
  <defs><radialGradient id="d"><stop offset="0" stop-color="#ffffff"/><stop offset="0.35" stop-color="#f0d4ff" stop-opacity="0.8"/>
    <stop offset="1" stop-color="#c79bff" stop-opacity="0"/></radialGradient></defs>
  <circle r="10" fill="url(#d)"/>
</svg>
`;

// ----------------------------------------------------- boot animation --

// The pose of every piece t seconds into the splash, in 1080p pixels relative to the heart. The Plymouth
// script is a line-for-line port of this function.
const BOOT_TIMELINE = String.raw`
function ease(u) {
  u = Math.min(1, Math.max(0, u));
  const v = 2 - 2 * u;
  return u < 0.5 ? 4 * u * u * u : 1 - (v * v * v) / 2;
}
function frame(t, B, SHARDS, DUST) {
  t = Math.max(0, t - B.hold);
  const k = B.unit;
  const assembled = B.assembled;
  const shards = SHARDS.map((s) => {
    const start = B.converge + s.delay;
    const hang = Math.min(t, start);
    const e = ease((t - start) / B.travel);
    const out = 1 - e;
    return {
      x: ((s.c[0] - 128) + (s.dx + s.dirx * s.drift * hang) * out) * k,
      y: ((s.c[1] - 128) + (s.dy + s.diry * s.drift * hang) * out) * k,
      angle: (s.spin + s.spinRate * hang) * out,
      opacity: t < assembled ? Math.min(1, t / B.fadeIn) : 0,
    };
  });
  const whole = t >= assembled ? 1 : 0;
  const rise = Math.min(1, Math.max(0, (t - B.converge) / (assembled + 0.3 - B.converge)));
  const since = (t - assembled) / 0.75;
  const flash = since >= 0 && since < 1 ? (1 - since) * (1 - since) * (1 - since) : 0;
  const loopStart = assembled + B.settle;
  const g = t >= loopStart ? 0.5 - 0.5 * Math.cos((2 * Math.PI * (t - loopStart)) / B.cycle) : 0;
  const dustLevel = rise * (0.55 + 0.45 * g);
  const dust = DUST.map((d) => {
    let y = d.y - d.rise * t;
    y = y - Math.floor((y + 300) / 600) * 600;
    const edge = Math.min(1, (300 - Math.abs(y)) / 60);
    const twinkle = 0.35 + 0.65 * Math.abs(Math.sin(d.phase + d.twinkle * t));
    return {
      x: (d.x + d.sway * Math.sin(d.phase + d.swayRate * t)) * k, y: y * k,
      opacity: dustLevel * edge * twinkle,
    };
  });
  return {
    shards, dust, gem: whole,
    nebula: Math.min(1, 0.85 * rise + 0.15 * flash),
    halo: Math.min(1, rise * (0.3 + 0.7 * g) + 0.5 * flash),
    light: Math.min(1, whole * 0.45 * g + 0.9 * flash),
  };
}
`;

const svgData = (svg) => `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`;

// An animated preview of the splash on a 1920x1080 stage, scaled to the window
function bootPreviewHtml() {
  const k = BOOT.unit;
  const img = (id, svg, w, h, extra = "") =>
    `<img id="${id}" src="${svgData(svg)}" style="width:${w}px;height:${h}px;margin:${-h / 2}px 0 0 ${-w / 2}px${extra}">`;
  return `<!doctype html><html><head><meta charset="utf-8"><title>Amethystora boot splash</title><style>
    ${wordmarkFace}
    html,body{margin:0;height:100%;background:#000;overflow:hidden;font-family:"${WORDMARK_FONT}",sans-serif}
    #stage{position:absolute;left:50%;top:50%;width:1920px;height:1080px;transform-origin:0 0;overflow:hidden;
      background:linear-gradient(${BOOT.sky[0]},${BOOT.sky[1]})}
    #nebula{position:absolute;left:0;top:0;width:1920px;height:1080px}
    #heart{position:absolute;left:960px;top:${1080 * BOOT.centerY}px}
    #heart img{position:absolute;left:0;top:0;will-change:transform,opacity}
    #mark{position:absolute;left:0;right:0;top:${Math.round(1080 * 0.94) - 18}px;text-align:center;color:#fff;
      font-weight:${WORDMARK_WEIGHT};letter-spacing:-0.015em;font-size:34px;line-height:36px}
    /* The author credit under the name, in a violet close to the cloud behind it so it only shows when looked for */
    #credit{position:absolute;left:0;right:0;top:${Math.round(1080 * 0.94) + 26}px;text-align:center;color:${SHADES[7]};
      opacity:0.22;font-weight:500;letter-spacing:0.04em;font-size:13px;line-height:16px}
    #bar{position:fixed;left:12px;bottom:12px;display:flex;gap:8px;align-items:center;color:#cdb8ec;font:13px system-ui}
    button{background:#2a1740;color:#eadcff;border:1px solid #4a2d70;border-radius:6px;padding:6px 12px;font:inherit;cursor:pointer}
  </style></head><body>
  <div id="stage"><img id="nebula" src="${svgData(nebulaSvg)}"><div id="heart">
    ${img("halo", haloSvg, BOOT.halo, BOOT.halo)}
    ${DUST.map((d, i) => img(`dust${i}`, dustSvg, d.size * k * 2, d.size * k * 2)).join("")}
    ${SHARDS.map((s, i) => img(`shard${i}`, shardSvg(s), s.side * k, s.side * k)).join("")}
    ${img("gem", gemSvg(), 256 * k, 256 * k)}
    ${img("light", lightSvg, 256 * k, 256 * k)}
  </div><div id="mark">amethystora</div><div id="credit">by iarsslen</div></div>
  <div id="bar"><button id="replay">Replay</button><button id="slow">Slow motion: off</button><span id="clock"></span></div>
  <script>
    ${BOOT_TIMELINE}
    const B = ${JSON.stringify(BOOT)}, SHARDS = ${JSON.stringify(SHARDS)}, DUST = ${JSON.stringify(DUST)};
    const hx = ${CENTER[0] - 128} * B.unit, hy = ${CENTER[1] - 128} * B.unit;
    const $ = (id) => document.getElementById(id);
    const stage = $("stage");
    const fit = () => {
      const s = Math.min(innerWidth / 1920, innerHeight / 1080);
      stage.style.transform = "scale(" + s + ") translate(-960px,-540px)";
    };
    addEventListener("resize", fit); fit();
    let t0 = performance.now(), t = 0, last = t0, speed = 1;
    $("replay").onclick = () => { t = 0; };
    $("slow").onclick = () => { speed = speed === 1 ? 0.25 : 1; $("slow").textContent = "Slow motion: " + (speed === 1 ? "off" : "on"); };
    const put = (el, x, y, opacity, angle = 0, scale = 1) => {
      el.style.transform = "translate(" + x + "px," + y + "px) rotate(" + angle + "rad) scale(" + scale + ")";
      el.style.opacity = opacity;
    };
    function tick(now) {
      t += ((now - last) / 1000) * speed; last = now;
      // #t=1.5 in the address holds the animation at that moment
      const hold = /t=([\\d.]+)/.exec(location.hash);
      if (hold) t = +hold[1];
      const f = frame(t, B, SHARDS, DUST);
      f.shards.forEach((s, i) => put($("shard" + i), s.x, s.y, s.opacity, s.angle));
      f.dust.forEach((d, i) => put($("dust" + i), d.x + hx, d.y + hy, d.opacity));
      put($("gem"), 0, 0, f.gem); put($("light"), 0, 0, f.light);
      $("nebula").style.opacity = f.nebula;
      put($("halo"), hx, hy, f.halo);
      $("clock").textContent = t.toFixed(2) + " s";
      requestAnimationFrame(tick);
    }
    document.fonts.load('${WORDMARK_WEIGHT} 16px "${WORDMARK_FONT}"').finally(() => requestAnimationFrame(tick));
  </script></body></html>`;
}

// ------------------------------------------------------ fastfetch logo --

function inPolygon([x, y], poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function colorAt(x, y) {
  if (!inPolygon([x, y], OUTLINE)) return null;
  const facet = FACETS.find((f) => inPolygon([x, y], f.pts));
  return facet ? shadeOf(facet.level) : SHADES[3];
}

const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(";");

// Truecolour half-block art: every character cell shows two vertically stacked pixels.
function ansiLogo(rows = 34) {
  const cols = Math.round((rows * BOUNDS[2]) / BOUNDS[3]);
  const [x0, y0, w, h] = BOUNDS;
  const px = (i, j) => colorAt(x0 + ((i + 0.5) * w) / cols, y0 + ((j + 0.5) * h) / rows);
  const lines = [];
  for (let j = 0; j < rows; j += 2) {
    let line = "";
    for (let i = 0; i < cols; i++) {
      const top = px(i, j);
      const bottom = px(i, j + 1);
      if (!top && !bottom) line += "\x1b[0m ";
      else if (top && !bottom) line += `\x1b[0;38;2;${rgb(top)}m▀`;
      else if (!top && bottom) line += `\x1b[0;38;2;${rgb(bottom)}m▄`;
      else line += `\x1b[38;2;${rgb(top)};48;2;${rgb(bottom)}m▀`;
    }
    lines.push(line.replace(/(\x1b\[0m )+$/, "") + "\x1b[0m");
  }
  return lines.join("\n") + "\n";
}

// The Linux text console has 16 colours and maps truecolour to the nearest, which turns the dark facets blue.
// Its variant uses the console's own colours: magenta, bright magenta, and white for the glint. Bright colours
// only exist in the foreground, so the brighter pixel of each cell is drawn with the glyph.
const CONSOLE_TONES = { [SHADES[8]]: 2, [SHADES[7]]: 1, [SHADES[6]]: 1 };
const CONSOLE_FG = ["35", "95", "97"];
const CONSOLE_BG = ["45", "45", "47"];

function consoleLogo(rows = 34) {
  const cols = Math.round((rows * BOUNDS[2]) / BOUNDS[3]);
  const [x0, y0, w, h] = BOUNDS;
  const tone = (i, j) => {
    const color = colorAt(x0 + ((i + 0.5) * w) / cols, y0 + ((j + 0.5) * h) / rows);
    return color && (CONSOLE_TONES[color] ?? 0);
  };
  const lines = [];
  for (let j = 0; j < rows; j += 2) {
    let line = "";
    for (let i = 0; i < cols; i++) {
      const top = tone(i, j);
      const bottom = tone(i, j + 1);
      if (top === null && bottom === null) line += "\x1b[0m ";
      else if (bottom === null) line += `\x1b[0;${CONSOLE_FG[top]}m▀`;
      else if (top === null) line += `\x1b[0;${CONSOLE_FG[bottom]}m▄`;
      else if (top === bottom) line += `\x1b[0;${CONSOLE_FG[top]}m█`;
      else if (top > bottom) line += `\x1b[0;${CONSOLE_FG[top]};${CONSOLE_BG[bottom]}m▀`;
      else line += `\x1b[0;${CONSOLE_FG[bottom]};${CONSOLE_BG[top]}m▄`;
    }
    lines.push(line.replace(/(\x1b\[0m )+$/, "") + "\x1b[0m");
  }
  return lines.join("\n") + "\n";
}

// ------------------------------------------------------------ PNG logos --

// The wordmark is set in Quicksand Bold (branding/fonts, SIL Open Font License): its round bowls and rounded
// stroke ends follow the curve of the teardrop gem, so the gem reads as the "a" of the name. The font is
// embedded so the rendering does not depend on the fonts of this machine.
const WORDMARK_FONT = "Quicksand";
const WORDMARK_WEIGHT = 700;
const wordmarkFace = `@font-face{font-family:"${WORDMARK_FONT}";font-weight:300 700;src:url(data:font/ttf;base64,${readFileSync(
  join(ROOT, "branding/fonts/QuicksandVariable.ttf"),
).toString("base64")}) format("truetype")}`;

const gemImg = (white, cls = "") =>
  `<img${cls ? ` class="${cls}"` : ""} src="data:image/svg+xml;base64,${Buffer.from(
    gemSvg(white, BOUNDS.join(" ")),
  ).toString("base64")}">`;

// The wordmark: the gem stands in for the "a" of amethystora, set tight against "methystora". It is as tall as the
// ascender of the "h" and rests on the baseline. Without the gem the name is set in full.
const GEM_EM = 0.76;
const wordmark = (gem) => (gem ? `<span>${gemImg(false, "a")}methystora</span>` : "<span>amethystora</span>");

// Gem or wordmark centred on a transparent canvas, scaled down to fit with a margin.
function logoHtml({ width, height, text, white = false, gem = true }) {
  const textColor = text === "white" ? "#ffffff" : "#241f31";
  const body = `<div id="row">${text ? wordmark(gem) : gemImg(white)}</div>`;
  return `<!doctype html><html><head><style>
    ${wordmarkFace}
    html,body{margin:0;width:${width}px;height:${height}px;background:transparent;overflow:hidden}
    body{display:flex;align-items:center;justify-content:center}
    #row{display:flex;align-items:center;white-space:nowrap}
    #row>img{height:${Math.round(height * 0.84)}px}
    span{font-family:"${WORDMARK_FONT}";font-weight:${WORDMARK_WEIGHT};letter-spacing:-0.015em;font-size:${Math.round(height * 0.62)}px;
      color:${textColor};line-height:1}
    img.a{height:${GEM_EM}em;width:${((GEM_EM * BOUNDS[2]) / BOUNDS[3]).toFixed(3)}em;margin-right:0.035em;
      vertical-align:-0.012em}
  </style></head><body>${body}<script>
    // Measure once the wordmark font is in use, not the fallback font
    document.fonts.load('${WORDMARK_WEIGHT} 16px "${WORDMARK_FONT}"').then(() => {
      const row = document.getElementById("row");
      const scale = Math.min(1, (${width} * 0.92) / row.offsetWidth, (${height} * 0.92) / row.offsetHeight);
      row.style.transform = "scale(" + scale + ")";
    });
  </script></body></html>`;
}

// ------------------------------------------------------ Plymouth theme --

// The splash runs in Plymouth's script plugin. Its images are drawn at twice their 1080p size so they stay
// sharp up to 4K, and the script scales each one once at start-up to fit the screen. The nebula and halo are
// soft enough to be drawn smaller and stretched.
const THEME = "usr/share/plymouth/themes/amethystora";
const GEM_PX = 256 * BOOT.unit; // the gem's 256-unit box, in 1080p pixels
const TEXT = {
  wordmark: { text: "amethystora", size: 34, weight: WORDMARK_WEIGHT, spacing: "-0.015em", color: "#ffffff", box: [260, 45] },
  credit: { text: "by iarsslen", size: 13, weight: 500, spacing: "0.04em", color: SHADES[7], box: [110, 18], opacity: 0.22 },
};
// Centre of the name, as a share of the screen height, and of the credit below it, in 1080p pixels
const WORDMARK_Y = 0.94;
const CREDIT_BELOW = 34;

const svgPage = (svg, width, height) => `<!doctype html><html><head><style>
    html,body{margin:0;background:transparent;overflow:hidden}
    svg{display:block;width:${width}px;height:${height}px}
  </style></head><body>${svg}</body></html>`;

// A line of text in the wordmark font, centred in its box, at twice its 1080p size
const textPage = ({ text, size, weight, spacing, color, box }) => `<!doctype html><html><head><style>
    ${wordmarkFace}
    html,body{margin:0;width:${box[0] * 2}px;height:${box[1] * 2}px;background:transparent;overflow:hidden}
    body{display:flex;align-items:center;justify-content:center;font-family:"${WORDMARK_FONT}";font-weight:${weight};
      letter-spacing:${spacing};font-size:${size * 2}px;line-height:1;color:${color};white-space:nowrap}
  </style></head><body>${text}<script>document.fonts.load('${weight} 16px "${WORDMARK_FONT}"');</script></body></html>`;

// The password field: a pill in the colours of the splash with the lock inside it, on the left; the typed
// characters show as dots after the lock. In 1080p pixels.
const FIELD = { width: 360, height: 44, textX: 48, dot: 10, gap: 5 };
const fieldSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${FIELD.width} ${FIELD.height}">
  <rect x="0.75" y="0.75" width="${FIELD.width - 1.5}" height="${FIELD.height - 1.5}" rx="${(FIELD.height - 1.5) / 2}"
    fill="#140824" fill-opacity="0.6" stroke="${SHADES[7]}" stroke-opacity="0.55" stroke-width="1.5"/>
  <path d="M21.5 20v-3.5a4.5 4.5 0 0 1 9 0V20" fill="none" stroke="#e9dcff" stroke-width="2" stroke-linecap="round"/>
  <rect x="18" y="20" width="16" height="12" rx="2.5" fill="#e9dcff"/>
</svg>
`;
const dotSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" fill="#efe3ff"/></svg>
`;

const BOOT_PNGS = [
  { out: `${THEME}/field.png`, width: FIELD.width * 2, height: FIELD.height * 2, html: () => svgPage(fieldSvg, FIELD.width * 2, FIELD.height * 2) },
  { out: `${THEME}/dot.png`, width: FIELD.dot * 2, height: FIELD.dot * 2, html: () => svgPage(dotSvg, FIELD.dot * 2, FIELD.dot * 2) },
  { out: `${THEME}/nebula.png`, width: 960, height: 540, html: () => svgPage(nebulaSvg, 960, 540) },
  { out: `${THEME}/halo.png`, width: BOOT.halo / 2, height: BOOT.halo / 2, html: () => svgPage(haloSvg, BOOT.halo / 2, BOOT.halo / 2) },
  { out: `${THEME}/dust.png`, width: 32, height: 32, html: () => svgPage(dustSvg, 32, 32) },
  ...[["gem", gemSvg()], ["light", lightSvg]].map(([name, svg]) => {
    const px = Math.round(GEM_PX * 2);
    return { out: `${THEME}/${name}.png`, width: px, height: px, html: () => svgPage(svg, px, px) };
  }),
  ...SHARDS.map((s, i) => {
    const px = Math.round(s.side * BOOT.unit * 2);
    return { out: `${THEME}/shard-${i}.png`, width: px, height: px, html: () => svgPage(shardSvg(s), px, px) };
  }),
  ...Object.entries(TEXT).map(([name, t]) => ({
    out: `${THEME}/${name}.png`, width: t.box[0] * 2, height: t.box[1] * 2, html: () => textPage(t),
  })),
];

// Numbers for the script: plain decimals, never exponents
const num = (v) => {
  const s = v.toFixed(4).replace(/\.?0+$/, "");
  return s === "-0" || s === "" ? "0" : s;
};
const rgb01 = (hex) => [1, 3, 5].map((i) => num(parseInt(hex.slice(i, i + 2), 16) / 255)).join(", ");

// The splash as a Plymouth script: the same timeline as BOOT_TIMELINE, plus the password prompt, messages and
// update progress, which the script plugin leaves to the theme.
function bootScript() {
  const B = BOOT;
  const K = num(B.unit);
  // Set a sprite's opacity only when it changes, so sprites that hold still are not redrawn
  const fade = (name, expr) => `  o = ${expr};
  if (Math.Abs(o - global.${name}.opacity) > 0.004) {
    global.${name}.sprite.SetOpacity(o);
    global.${name}.opacity = o;
  }`;
  const shards = SHARDS.map((s, i) => `shard[${i}].image = sized(Image("shard-${i}.png"), ${num(s.side * B.unit)} * scale, ${num(s.side * B.unit)} * scale);
shard[${i}].turned = shard[${i}].image;
shard[${i}].sprite = Sprite(shard[${i}].image);
shard[${i}].sprite.SetZ(3);
shard[${i}].sprite.SetOpacity(0);
shard[${i}].angle = 99;
shard[${i}].x = ${num(s.c[0] - 128)};
shard[${i}].y = ${num(s.c[1] - 128)};
shard[${i}].dx = ${num(s.dx)};
shard[${i}].dy = ${num(s.dy)};
shard[${i}].dirx = ${num(s.dirx)};
shard[${i}].diry = ${num(s.diry)};
shard[${i}].drift = ${num(s.drift)};
shard[${i}].spin = ${num(s.spin)};
shard[${i}].spin_rate = ${num(s.spinRate)};
shard[${i}].delay = ${num(s.delay)};`).join("\n");
  const dust = DUST.map((d, i) => `dust[${i}].image = sized(dust_image, ${num(d.size * B.unit * 2)} * scale, ${num(d.size * B.unit * 2)} * scale);
dust[${i}].half = dust[${i}].image.GetWidth() / 2;
dust[${i}].sprite = Sprite(dust[${i}].image);
dust[${i}].sprite.SetZ(2);
dust[${i}].sprite.SetOpacity(0);
dust[${i}].x = ${num(d.x)};
dust[${i}].y = ${num(d.y)};
dust[${i}].rise = ${num(d.rise)};
dust[${i}].sway = ${num(d.sway)};
dust[${i}].sway_rate = ${num(d.swayRate)};
dust[${i}].twinkle = ${num(d.twinkle)};
dust[${i}].phase = ${num(d.phase)};`).join("\n");

  return `# The Amethystora boot splash, for Plymouth's script plugin.
# Generated by branding/generate.mjs from the same timeline as its browser preview
# (node branding/generate.mjs --preview): change it there, not here.

Window.SetBackgroundTopColor(${rgb01(B.sky[0])});
Window.SetBackgroundBottomColor(${rgb01(B.sky[1])});

# Everything is laid out for a 1920x1080 screen and scaled to fit this one
screen_x = Window.GetX();
screen_y = Window.GetY();
screen_w = Window.GetWidth();
screen_h = Window.GetHeight();
scale = Math.Min(screen_w / 1920, screen_h / 1080);
origin_x = screen_x + screen_w / 2;
origin_y = screen_y + screen_h * ${num(B.centerY)};
heart_x = origin_x + ${num((CENTER[0] - 128) * B.unit)} * scale;
heart_y = origin_y + ${num((CENTER[1] - 128) * B.unit)} * scale;

fun sized(image, width, height) {
  if (width < 1) { width = 1; }
  if (height < 1) { height = 1; }
  return image.Scale(Math.Int(width + 0.5), Math.Int(height + 0.5));
}

fun clamp01(v) {
  if (v < 0) { return 0; }
  if (v > 1) { return 1; }
  return v;
}

# Math.Int rounds towards zero; this rounds down
fun floor_of(v) {
  q = Math.Int(v);
  if (q > v) { q = q - 1; }
  return q;
}

fun ease(u) {
  u = clamp01(u);
  if (u < 0.5) { return 4 * u * u * u; }
  v = 2 - 2 * u;
  return 1 - v * v * v / 2;
}

# ------------------------------------------------------------------- scene --

nebula.image = sized(Image("nebula.png"), screen_w, screen_h);
nebula.sprite = Sprite(nebula.image);
nebula.sprite.SetPosition(screen_x, screen_y, 0);
nebula.sprite.SetOpacity(0);
nebula.opacity = 0;

halo.image = sized(Image("halo.png"), ${B.halo} * scale, ${B.halo} * scale);
halo.sprite = Sprite(halo.image);
halo.sprite.SetPosition(heart_x - halo.image.GetWidth() / 2, heart_y - halo.image.GetHeight() / 2, 1);
halo.sprite.SetOpacity(0);
halo.opacity = 0;

dust_image = Image("dust.png");
dust_count = ${DUST.length};
${dust}

shard_count = ${SHARDS.length};
${shards}

gem.image = sized(Image("gem.png"), ${num(GEM_PX)} * scale, ${num(GEM_PX)} * scale);
gem.sprite = Sprite(gem.image);
gem.sprite.SetPosition(origin_x - gem.image.GetWidth() / 2, origin_y - gem.image.GetHeight() / 2, 4);
gem.sprite.SetOpacity(0);

light.image = sized(Image("light.png"), ${num(GEM_PX)} * scale, ${num(GEM_PX)} * scale);
light.sprite = Sprite(light.image);
light.sprite.SetPosition(origin_x - light.image.GetWidth() / 2, origin_y - light.image.GetHeight() / 2, 5);
light.sprite.SetOpacity(0);
light.opacity = 0;

wordmark.image = sized(Image("wordmark.png"), ${TEXT.wordmark.box[0]} * scale, ${TEXT.wordmark.box[1]} * scale);
wordmark.sprite = Sprite(wordmark.image);
wordmark_y = screen_y + screen_h * ${WORDMARK_Y};
wordmark.sprite.SetPosition(origin_x - wordmark.image.GetWidth() / 2, wordmark_y - wordmark.image.GetHeight() / 2, 6);

credit.image = sized(Image("credit.png"), ${TEXT.credit.box[0]} * scale, ${TEXT.credit.box[1]} * scale);
credit.sprite = Sprite(credit.image);
credit.sprite.SetPosition(origin_x - credit.image.GetWidth() / 2, wordmark_y + ${CREDIT_BELOW} * scale - credit.image.GetHeight() / 2, 6);
credit.sprite.SetOpacity(${TEXT.credit.opacity});

# ---------------------------------------------------------------- timeline --

# Shutdown and reboot skip the assembly and start with the gem whole
tick = 0;
mode = Plymouth.GetMode();
if (mode == "shutdown" || mode == "reboot") {
  tick = Math.Int(${num(B.hold + B.assembled + B.settle)} * 50);
}
assembled_done = 0;

# Called 50 times a second
fun refresh_callback() {
  t = global.tick / 50 - ${num(B.hold)};
  if (t < 0) { t = 0; }
  global.tick = global.tick + 1;

  if (t < ${num(B.assembled)}) {
    shown = clamp01(t / ${num(B.fadeIn)});
    for (i = 0; i < global.shard_count; i++) {
      start = ${num(B.converge)} + global.shard[i].delay;
      hang = t;
      if (hang > start) { hang = start; }
      out = 1 - ease((t - start) / ${num(B.travel)});
      angle = (global.shard[i].spin + global.shard[i].spin_rate * hang) * out;
      if (angle != global.shard[i].angle) {
        global.shard[i].turned = global.shard[i].image.Rotate(angle);
        global.shard[i].sprite.SetImage(global.shard[i].turned);
        global.shard[i].angle = angle;
      }
      x = global.origin_x + (global.shard[i].x + (global.shard[i].dx + global.shard[i].dirx * global.shard[i].drift * hang) * out) * ${K} * global.scale;
      y = global.origin_y + (global.shard[i].y + (global.shard[i].dy + global.shard[i].diry * global.shard[i].drift * hang) * out) * ${K} * global.scale;
      global.shard[i].sprite.SetX(x - global.shard[i].turned.GetWidth() / 2);
      global.shard[i].sprite.SetY(y - global.shard[i].turned.GetHeight() / 2);
      global.shard[i].sprite.SetOpacity(shown);
    }
  } else if (!global.assembled_done) {
    # The pieces have landed: the whole gem takes their place
    for (i = 0; i < global.shard_count; i++) {
      global.shard[i].sprite.SetOpacity(0);
    }
    global.gem.sprite.SetOpacity(1);
    global.assembled_done = 1;
  }

  rise = clamp01((t - ${num(B.converge)}) / ${num(B.assembled + 0.3 - B.converge)});
  flash = 0;
  since = (t - ${num(B.assembled)}) / 0.75;
  if (since >= 0 && since < 1) { flash = (1 - since) * (1 - since) * (1 - since); }
  glow = 0;
  if (t >= ${num(B.assembled + B.settle)}) {
    glow = 0.5 - 0.5 * Math.Cos(6.2831853 * (t - ${num(B.assembled + B.settle)}) / ${num(B.cycle)});
  }
  whole = 0;
  if (t >= ${num(B.assembled)}) { whole = 1; }

${fade("nebula", "Math.Min(1, 0.85 * rise + 0.15 * flash)")}
${fade("halo", "Math.Min(1, rise * (0.3 + 0.7 * glow) + 0.5 * flash)")}
${fade("light", "Math.Min(1, whole * 0.45 * glow + 0.9 * flash)")}

  dust_level = rise * (0.55 + 0.45 * glow);
  for (i = 0; i < global.dust_count; i++) {
    y = global.dust[i].y - global.dust[i].rise * t;
    y = y - floor_of((y + 300) / 600) * 600;
    edge = (300 - Math.Abs(y)) / 60;
    if (edge > 1) { edge = 1; }
    twinkle = 0.35 + 0.65 * Math.Abs(Math.Sin(global.dust[i].phase + global.dust[i].twinkle * t));
    x = global.dust[i].x + global.dust[i].sway * Math.Sin(global.dust[i].phase + global.dust[i].sway_rate * t);
    global.dust[i].sprite.SetX(global.heart_x + x * ${K} * global.scale - global.dust[i].half);
    global.dust[i].sprite.SetY(global.heart_y + y * ${K} * global.scale - global.dust[i].half);
    global.dust[i].sprite.SetOpacity(dust_level * edge * twinkle);
  }
}
Plymouth.SetRefreshFunction(refresh_callback);

# ------------------------------------------------ password and questions --

# Text scales with the screen like everything else; size is in points at 1080p
fun font(size) {
  points = Math.Int(size * global.scale + 0.5);
  if (points < 9) { points = 9; }
  return "Inter " + points;
}

# The field under the gem, the lock drawn inside it, and the prompt above
field_image = sized(Image("field.png"), ${FIELD.width} * scale, ${FIELD.height} * scale);
dot_image = sized(Image("dot.png"), ${FIELD.dot} * scale, ${FIELD.dot} * scale);
field_x = origin_x - field_image.GetWidth() / 2;
field_y = origin_y + 210 * scale - field_image.GetHeight() / 2;
text_x = field_x + ${FIELD.textX} * scale;
dot_step = (${FIELD.dot} + ${FIELD.gap}) * scale;
dot_room = Math.Int((field_image.GetWidth() - ${FIELD.textX + FIELD.height / 2} * scale) / dot_step);

dialog.field = Sprite(field_image);
dialog.field.SetPosition(field_x, field_y, 10);
dialog.prompt = Sprite();
dialog.prompt.SetZ(10);
dialog.text = Sprite();
dialog.text.SetZ(11);

fun hide_dots() {
  for (i = 0; global.dialog.dot[i]; i++) {
    global.dialog.dot[i].SetOpacity(0);
  }
}

fun hide_dialog() {
  global.dialog.field.SetOpacity(0);
  global.dialog.prompt.SetOpacity(0);
  global.dialog.text.SetOpacity(0);
  hide_dots();
}
hide_dialog();

fun show_dialog(prompt) {
  global.dialog.field.SetOpacity(1);
  image = Image.Text(prompt, 0.93, 0.89, 1, 1, font(12));
  global.dialog.prompt.SetImage(image);
  global.dialog.prompt.SetX(global.origin_x - image.GetWidth() / 2);
  global.dialog.prompt.SetY(global.field_y - image.GetHeight() - 14 * global.scale);
  global.dialog.prompt.SetOpacity(1);
}

fun display_password_callback(prompt, bullets) {
  show_dialog(prompt);
  global.dialog.text.SetOpacity(0);
  for (i = 0; global.dialog.dot[i] || i < bullets; i++) {
    if (!global.dialog.dot[i]) {
      global.dialog.dot[i] = Sprite(global.dot_image);
      global.dialog.dot[i].SetX(global.text_x + i * global.dot_step);
      global.dialog.dot[i].SetY(global.field_y + global.field_image.GetHeight() / 2 - global.dot_image.GetHeight() / 2);
      global.dialog.dot[i].SetZ(11);
    }
    if (i < bullets && i < global.dot_room) {
      global.dialog.dot[i].SetOpacity(1);
    } else {
      global.dialog.dot[i].SetOpacity(0);
    }
  }
}
Plymouth.SetDisplayPasswordFunction(display_password_callback);

fun display_question_callback(prompt, entry) {
  show_dialog(prompt);
  hide_dots();
  image = Image.Text(entry, 1, 1, 1, 1, font(12));
  global.dialog.text.SetImage(image);
  global.dialog.text.SetX(global.text_x);
  global.dialog.text.SetY(global.field_y + global.field_image.GetHeight() / 2 - image.GetHeight() / 2);
  global.dialog.text.SetOpacity(1);
}
Plymouth.SetDisplayQuestionFunction(display_question_callback);

fun display_normal_callback() {
  hide_dialog();
}
Plymouth.SetDisplayNormalFunction(display_normal_callback);

# ------------------------------------------------------ messages, updates --

message = Sprite();
message.SetZ(10);
fun message_callback(text) {
  image = Image.Text(text, 0.86, 0.8, 0.96, 1, font(11));
  global.message.SetImage(image);
  global.message.SetX(global.origin_x - image.GetWidth() / 2);
  global.message.SetY(global.screen_y + global.screen_h * 0.84);
}
Plymouth.SetMessageFunction(message_callback);

# Offline updates and upgrades: what is happening and how far along, under the gem
if (mode == "updates" || mode == "system-upgrade" || mode == "firmware-upgrade") {
  title = "Installing updates";
  if (mode == "system-upgrade") { title = "Upgrading the system"; }
  if (mode == "firmware-upgrade") { title = "Upgrading firmware"; }
  title_image = Image.Text(title + " - do not turn off your computer", 0.93, 0.89, 1, 1, font(14));
  status.title = Sprite(title_image);
  status.title.SetPosition(origin_x - title_image.GetWidth() / 2, origin_y + 190 * scale, 10);
  status.progress = Sprite();
  status.progress.SetZ(10);
}

fun system_update_callback(progress) {
  image = Image.Text(Math.Int(progress) + "%", 0.86, 0.8, 0.96, 1, font(12));
  global.status.progress.SetImage(image);
  global.status.progress.SetX(global.origin_x - image.GetWidth() / 2);
  global.status.progress.SetY(global.origin_y + 230 * global.scale);
}
Plymouth.SetSystemUpdateFunction(system_update_callback);
`;
}

// Wallpapers are rendered to PNG
const wallpaperHtml = (theme) => `<!doctype html><html><body style="margin:0">${wallpaperSvg(theme)}</body></html>`;

const logo = (spec) => ({ ...spec, html: () => logoHtml(spec) });
const PNGS = [
  logo({ out: "usr/share/pixmaps/amethystora-wordmark.png", width: 690, height: 204, text: "dark" }),
  logo({ out: "usr/share/pixmaps/amethystora-wordmark-medium.png", width: 345, height: 102, text: "dark" }),
  logo({ out: "usr/share/pixmaps/amethystora-wordmark-small.png", width: 205, height: 61, text: "dark" }),
  logo({ out: "usr/share/pixmaps/amethystora-wordmark-white.png", width: 345, height: 102, text: "white" }),
  logo({ out: "usr/share/pixmaps/amethystora-logo-512.png", width: 512, height: 512 }),
  logo({ out: "usr/share/pixmaps/amethystora-logo-400.png", width: 400, height: 400 }),
  logo({ out: "usr/share/pixmaps/amethystora-logo-white.png", width: 252, height: 252, white: true }),
  // Fedora's spinner theme, the fallback splash, looks its watermark up by this name
  logo({ out: "usr/share/plymouth/themes/spinner/watermark.png", width: 330, height: 64, text: "white" }),
  ...BOOT_PNGS,
  { out: "usr/share/backgrounds/amethystora/amethystora-l.png", width: 3840, height: 2160, html: () => wallpaperHtml("light") },
  { out: "usr/share/backgrounds/amethystora/amethystora-d.png", width: 3840, height: 2160, html: () => wallpaperHtml("dark") },
];

function findBrowser() {
  const candidates = [
    process.env.BROWSER,
    "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "/usr/bin/chromium-browser",
    "/usr/bin/chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/microsoft-edge",
  ].filter(Boolean);
  const found = candidates.find((c) => existsSync(c));
  if (!found) throw new Error("No Chromium-based browser found; set BROWSER=/path/to/browser");
  return found;
}

// ONLY=substring renders just the PNGs whose path contains it, for quick previews
function renderPngs() {
  const browser = findBrowser();
  const work = join(tmpdir(), "amethystora-branding");
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  for (const png of PNGS.filter((p) => !process.env.ONLY || p.out.includes(process.env.ONLY))) {
    const html = join(work, "page.html");
    writeFileSync(html, png.html());
    const out = join(SHARED, png.out);
    mkdirSync(dirname(out), { recursive: true });
    rmSync(out, { force: true });
    execFileSync(browser, [
      "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
      "--default-background-color=00000000", `--user-data-dir=${join(work, "profile")}`,
      `--window-size=${png.width},${png.height}`, `--screenshot=${out}`, pathToFileURL(html).href,
    ], { stdio: "ignore" });
    if (!existsSync(out)) throw new Error(`Rendering ${png.out} failed`);
    console.log(`rendered ${png.out}`);
  }
  rmSync(work, { recursive: true, force: true });
}

// ---------------------------------------------------------------- write --

function write(rel, content) {
  const out = join(SHARED, rel);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, content);
  console.log(`wrote ${rel}`);
}

// --preview only writes the animated preview of the boot splash, and prints where
if (process.argv.includes("--preview")) {
  const out = join(tmpdir(), "amethystora-boot-preview.html");
  writeFileSync(out, bootPreviewHtml());
  console.log(out);
  process.exit(0);
}

write("usr/share/icons/hicolor/scalable/apps/amethystora-logo.svg", gemSvg());
write("usr/share/icons/hicolor/scalable/actions/amethystora-logo-symbolic.svg", symbolicSvg);
write("usr/share/icons/hicolor/scalable/places/amethystora-docs.svg", tileSvg(docsGlyph));
write("usr/share/icons/hicolor/scalable/places/amethystora-community.svg", tileSvg(communityGlyph));
write("usr/share/icons/hicolor/scalable/places/amethystora-update.svg", tileSvg(updateGlyph));
write("usr/share/amethystora/logos/symbols/amethystora", ansiLogo());
write("usr/share/amethystora/logos/console/amethystora", consoleLogo());
write(`${THEME}/amethystora.script`, bootScript());
renderPngs();
