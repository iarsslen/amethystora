// Generates the Amethyst artwork under system_files/ from the geometry and palette below.
//
//   node branding/generate.mjs
//
// SVGs and the fastfetch logo are written directly. PNGs are rendered with a
// headless Chromium browser (Edge or Chrome); set BROWSER to its path if it is
// not found automatically.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tmpdir } from "node:os";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SHARED = join(ROOT, "system_files/shared");

// ---------------------------------------------------------------- the gem --

// Brilliant-cut gem in a 256x256 box: a crown of five facets over a pavilion of three.
const P = {
  L: [24, 104], A: [64, 56], B: [128, 56], C: [192, 56], R: [232, 104],
  M: [96, 104], N: [160, 104], K: [128, 220],
};
const FACETS = [
  { pts: ["L", "A", "M"], color: "#b98ae8" },
  { pts: ["A", "B", "M"], color: "#dcc1fa" },
  { pts: ["M", "B", "N"], color: "#c49cf0" },
  { pts: ["B", "C", "N"], color: "#a874e0" },
  { pts: ["N", "C", "R"], color: "#8a55cc" },
  { pts: ["L", "M", "K"], color: "#7d43c4" },
  { pts: ["M", "N", "K"], color: "#9b62dc" },
  { pts: ["N", "R", "K"], color: "#5e2a9c" },
];
const WHITE_FACETS = [0.78, 1, 0.9, 0.82, 0.68, 0.62, 0.8, 0.5];

const pointList = (names) => names.map((n) => P[n].join(",")).join(" ");

function gemPolygons(white = false) {
  return FACETS.map((f, i) =>
    white
      ? `<polygon points="${pointList(f.pts)}" fill="#ffffff" fill-opacity="${WHITE_FACETS[i]}"/>`
      : `<polygon points="${pointList(f.pts)}" fill="${f.color}"/>`,
  ).join("\n  ");
}

// The icon keeps the padded 256x256 box; bitmaps use the tight bounds of the gem.
const gemSvg = (white = false, viewBox = "0 0 256 256") => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">
  ${gemPolygons(white)}
</svg>
`;

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
        bg: ["#12081f", "#2a0f4a", "#4a1d7a"],
        glowA: ["#9b5ce0", 0.45], glowB: ["#5e2a9c", 0.5],
        faces: { column: ["#8f5ad6", "#6f3bb8", "#4b2186"], tip: ["#c9a2f5", "#a574e6", "#7342b5"] },
        shade: "#12081f",
      }
    : {
        bg: ["#f7f2fd", "#e6d8f8", "#cdb3ef"],
        glowA: ["#ffffff", 0.7], glowB: ["#b98ae8", 0.35],
        faces: { column: ["#c7a3f0", "#a77ae3", "#8454c8"], tip: ["#ebdcff", "#d2b6f7", "#b08ae6"] },
        shade: "#cdb3ef",
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
  const facet = FACETS.find((f) => inPolygon([x, y], f.pts.map((n) => P[n])));
  return facet?.color ?? null;
}

const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(";");

// Truecolour half-block art: every character cell shows two vertically stacked pixels.
function ansiLogo(cols = 34, rows = 28) {
  const [x0, x1, y0, y1] = [24, 232, 56, 220];
  const px = (i, j) => colorAt(x0 + ((i + 0.5) * (x1 - x0)) / cols, y0 + ((j + 0.5) * (y1 - y0)) / rows);
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

// ------------------------------------------------------------ PNG logos --

const gemImg = (white) =>
  `<img src="data:image/svg+xml;base64,${Buffer.from(gemSvg(white, "24 56 208 164")).toString("base64")}">`;

// Gem (plus optional wordmark) centred on a transparent canvas, scaled down to fit with a margin.
function logoHtml({ width, height, text, white = false }) {
  const textColor = text === "white" ? "#ffffff" : "#241f31";
  const body = `<div id="row">${gemImg(white)}${text ? "<span>amethyst</span>" : ""}</div>`;
  return `<!doctype html><html><head><style>
    html,body{margin:0;width:${width}px;height:${height}px;background:transparent;overflow:hidden}
    body{display:flex;align-items:center;justify-content:center}
    #row{display:flex;align-items:center;gap:${Math.round(height * 0.1)}px;white-space:nowrap}
    img{height:${Math.round(height * (text ? 0.72 : 0.84))}px}
    span{font-family:"Segoe UI","Cantarell",sans-serif;font-weight:600;font-size:${Math.round(height * 0.46)}px;
      color:${textColor};line-height:1;padding-bottom:${Math.round(height * 0.05)}px}
  </style></head><body>${body}<script>
    const row = document.getElementById("row");
    const scale = Math.min(1, (${width} * 0.92) / row.offsetWidth, (${height} * 0.92) / row.offsetHeight);
    row.style.transform = "scale(" + scale + ")";
  </script></body></html>`;
}

// Wallpapers are PNG: DankMaterialShell derives its colour theme from them with matugen, which cannot read SVG.
const wallpaperHtml = (theme) => `<!doctype html><html><body style="margin:0">${wallpaperSvg(theme)}</body></html>`;

const logo = (spec) => ({ ...spec, html: () => logoHtml(spec) });
const PNGS = [
  logo({ out: "usr/share/pixmaps/fedora-logo.png", width: 500, height: 204, text: "dark" }),
  logo({ out: "usr/share/pixmaps/fedora_logo_med.png", width: 250, height: 102, text: "dark" }),
  logo({ out: "usr/share/pixmaps/fedora-logo-small.png", width: 150, height: 61, text: "dark" }),
  logo({ out: "usr/share/pixmaps/fedora_whitelogo_med.png", width: 250, height: 102, text: "white" }),
  logo({ out: "usr/share/pixmaps/fedora-logo-icon.png", width: 512, height: 512 }),
  logo({ out: "usr/share/pixmaps/fedora-logo-sprite.png", width: 400, height: 400 }),
  logo({ out: "usr/share/pixmaps/system-logo-white.png", width: 252, height: 252, white: true }),
  logo({ out: "usr/share/plymouth/themes/spinner/watermark.png", width: 240, height: 64, text: "white" }),
  logo({ out: "usr/share/plymouth/themes/spinner/silverblue-watermark.png", width: 240, height: 64, text: "white" }),
  { out: "usr/share/backgrounds/amethyst/amethyst-l.png", width: 3840, height: 2160, html: () => wallpaperHtml("light") },
  { out: "usr/share/backgrounds/amethyst/amethyst-d.png", width: 3840, height: 2160, html: () => wallpaperHtml("dark") },
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

function renderPngs() {
  const browser = findBrowser();
  const work = join(tmpdir(), "amethyst-branding");
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  for (const png of PNGS) {
    const html = join(work, "page.html");
    writeFileSync(html, png.html());
    const out = join(SHARED, png.out);
    mkdirSync(dirname(out), { recursive: true });
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

write("usr/share/icons/hicolor/scalable/apps/amethyst-logo.svg", gemSvg());
write("usr/share/ublue-os/amethyst-logos/symbols/amethyst", ansiLogo());
renderPngs();
