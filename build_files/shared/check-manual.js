'use strict';

// Checks the manual's pages for 20-tests.sh: every page in pages.json exists and has a title, and
// every link between pages lands on a page that is listed and on a heading that page has. Run by the
// manual's own Electron as Node, so the image needs no Node of its own:
//
//   ELECTRON_RUN_AS_NODE=1 /usr/lib/amethystora-manual/amethystora-manual check-manual.js [manual dir]

const fs = require('node:fs');
const path = require('node:path');

const manual = process.argv[2] || '/usr/share/amethystora/manual';
const toc = JSON.parse(fs.readFileSync(path.join(manual, 'pages.json'), 'utf8'));
const pages = new Map();
const problems = [];

// The same ids manual.js gives headings, from their text with the Markdown taken out
function slug(heading) {
    return heading.replace(/`/g, '').replace(/\*\*?/g, '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/&[#\w]+;/g, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-|-$/g, '');
}

for (const group of toc) {
    for (const file of group.pages) {
        const id = path.basename(file, '.md');
        const text = fs.readFileSync(path.join(manual, file), 'utf8').replace(/^```[\s\S]*?^```/gm, '');
        if (!/^# .+/m.test(text)) {
            problems.push(`${file}: no "# " title`);
        }
        if (pages.has(id)) {
            problems.push(`${file}: a second page called ${id}`);
        }
        const anchors = new Set([...text.matchAll(/^#{2,6} (.+)$/gm)].map((m) => slug(m[1])));
        pages.set(id, { file, text, anchors });
    }
}

for (const { file, text } of pages.values()) {
    for (const [, href] of text.matchAll(/\]\(([^)\s]+)\)/g)) {
        if (/^(https?|mailto):/.test(href)) {
            continue;
        }
        const [, target, anchor] = href.match(/^(?:(?:.*\/)?([\w-]+)\.md)?(?:#(.+))?$/) || [];
        const page = pages.get(target || path.basename(file, '.md'));
        if (!page) {
            problems.push(`${file}: links to ${href}, which is not a page of the manual`);
        } else if (anchor && !page.anchors.has(anchor)) {
            problems.push(`${file}: links to ${href}, but ${page.file} has no such heading`);
        }
    }
}

for (const problem of problems) {
    console.error(`::error::manual: ${problem}`);
}
console.log(`manual: ${pages.size} pages checked`);
process.exit(problems.length ? 1 : 0);
