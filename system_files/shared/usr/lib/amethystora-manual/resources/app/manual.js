'use strict';

// The pages are Markdown, listed and grouped in /usr/share/amethystora/manual/pages.json and rendered
// with marked. A page is addressed by its file name: #updates, or #updates/rollback for a section.

const toc = document.getElementById('toc');
const results = document.getElementById('results');
const search = document.getElementById('search');
const article = document.getElementById('page');
const pager = document.getElementById('pager');
const main = document.getElementById('main');

const pages = [];
const byId = new Map();
let rendering = null;
let shown = null;

// A code span that is a key or a combination of keys is drawn as keycaps: `Super+Shift+B`
const KEY = /^(Super|Ctrl|Alt|Shift|Fn|Tab|Esc|Return|Enter|Space|Backspace|Delete|Print|Home|End|PageUp|PageDown|Up|Down|Left|Right|F\d{1,2}|[A-Z0-9]|[.,/`=-])$/;

function escapeHtml(text) {
    return String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function slug(html) {
    return html.replace(/<[^>]+>/g, '').replace(/&[#\w]+;/g, '').toLowerCase()
        .replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-|-$/g, '');
}

function keycaps(text) {
    const keys = text.split('+');
    if (!keys.every((key) => KEY.test(key))) {
        return null;
    }
    // On its own, only a named key or a letter: a lone `1` or `-` is more likely a value than a key
    if (keys.length === 1 && !/^([A-Z]|[A-Z][a-z]+|F\d{1,2})$/.test(text)) {
        return null;
    }
    return `<span class="keys">${keys.map((key) => `<kbd>${escapeHtml(key)}</kbd>`).join('<span>+</span>')}</span>`;
}

// Links between pages are written as they are on disk (updates.md#rollback), so the pages also read
// correctly anywhere else Markdown is shown
function route(href) {
    if (/^(https?|mailto):/i.test(href)) {
        return href;
    }
    const local = href.match(/^#(.+)$/);
    if (local) {
        return `#${rendering.id}/${local[1]}`;
    }
    const page = href.match(/^(?:.*\/)?([\w-]+)\.md(?:#(.+))?$/);
    if (page) {
        return page[2] ? `#${page[1]}/${page[2]}` : `#${page[1]}`;
    }
    return href;
}

marked.use({
    gfm: true,
    renderer: {
        heading({ tokens, depth }) {
            const html = this.parser.parseInline(tokens);
            if (depth === 1) {
                return `<h1>${html}</h1>\n`;
            }
            const id = slug(html);
            return `<h${depth} id="${id}"><a class="anchor" href="#${rendering.id}/${id}" aria-hidden="true" tabindex="-1">#</a>${html}</h${depth}>\n`;
        },
        link({ href, title, tokens }) {
            const text = this.parser.parseInline(tokens);
            const external = /^(https?|mailto):/i.test(href);
            const attributes = [`href="${escapeHtml(route(href))}"`];
            if (external) {
                attributes.push('class="external"');
            }
            if (title) {
                attributes.push(`title="${escapeHtml(title)}"`);
            }
            return `<a ${attributes.join(' ')}>${text}</a>`;
        },
        code({ text }) {
            return `<div class="code"><button class="copy" type="button">Copy</button><pre><code>${escapeHtml(text)}</code></pre></div>\n`;
        },
        codespan({ text }) {
            const unescaped = text.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
            return keycaps(unescaped) ?? `<code>${escapeHtml(unescaped)}</code>`;
        },
    },
});

function render(page) {
    rendering = page;
    page.html = marked.parse(page.markdown);
    rendering = null;

    // What search looks through: each page split at its headings, without the copy buttons' labels
    const doc = new DOMParser().parseFromString(page.html, 'text/html');
    doc.querySelectorAll('button.copy').forEach((button) => button.remove());
    page.sections = [{ id: '', title: page.title, text: '' }];
    for (const node of doc.body.children) {
        if (/^H[23]$/.test(node.tagName)) {
            page.sections.push({ id: node.id, title: node.textContent.replace(/^#/, ''), text: '' });
        } else if (node.tagName !== 'H1') {
            page.sections.at(-1).text += ` ${node.textContent}`;
        }
    }
}

function buildToc() {
    let group = null;
    for (const page of pages) {
        if (page.section !== group) {
            group = page.section;
            const heading = document.createElement('h2');
            heading.textContent = group;
            toc.append(heading);
        }
        const link = document.createElement('a');
        link.href = `#${page.id}`;
        link.textContent = page.title;
        link.dataset.page = page.id;
        toc.append(link);
    }
}

function remember(id) {
    try {
        if (id === undefined) {
            return localStorage.getItem('page');
        }
        localStorage.setItem('page', id);
    } catch {
        // Nowhere to keep it: the manual opens on its first page instead
    }
    return null;
}

function show(hash) {
    const [id, anchor] = decodeURIComponent(hash.replace(/^#/, '')).split('/');
    const page = byId.get(id) || byId.get(remember()) || pages[0];
    // Within a page the view glides to the section; a new page opens straight at it
    const behavior = page === shown ? 'smooth' : 'instant';
    if (page !== shown) {
        shown = page;
        const at = pages.indexOf(page);
        article.innerHTML = `<p class="eyebrow">${escapeHtml(page.section)}</p>${page.html}`;
        const neighbour = (other, label, className) => other
            ? `<a class="${className}" href="#${other.id}"><span>${label}</span>${escapeHtml(other.title)}</a>`
            : '<span></span>';
        pager.innerHTML = neighbour(pages[at - 1], 'Previous', 'prev') + neighbour(pages[at + 1], 'Next', 'next');
        for (const link of toc.querySelectorAll('a')) {
            link.toggleAttribute('aria-current', link.dataset.page === page.id);
        }
        toc.querySelector('[aria-current]')?.scrollIntoView({ block: 'nearest' });
        document.title = `${page.title} · Amethystora Manual`;
        remember(page.id);
    }
    const target = anchor && document.getElementById(anchor);
    if (target) {
        target.scrollIntoView({ behavior });
    } else {
        main.scrollTo({ top: 0, behavior });
    }
}

// --- Search -------------------------------------------------------------------------------------

function snippet(text, word) {
    const at = text.toLowerCase().indexOf(word);
    if (at < 0) {
        return text.slice(0, 120);
    }
    const start = Math.max(0, at - 50);
    return (start > 0 ? '…' : '') + text.slice(start, at + 90).trim() + '…';
}

function find(query) {
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    const found = [];
    for (const page of pages) {
        for (const section of page.sections) {
            const title = section.title.toLowerCase();
            const body = section.text.toLowerCase();
            if (!words.every((word) => title.includes(word) || body.includes(word) || page.title.toLowerCase().includes(word))) {
                continue;
            }
            const score = words.filter((word) => title.includes(word)).length * 3 + (section.id ? 0 : 1);
            found.push({ page, section, score });
        }
    }
    return found.sort((a, b) => b.score - a.score).slice(0, 40).map(({ page, section }) => ({
        href: section.id ? `#${page.id}/${section.id}` : `#${page.id}`,
        title: section.id ? `${page.title} › ${section.title}` : page.title,
        text: snippet(section.text.replace(/\s+/g, ' ').trim(), words[0]),
    }));
}

function showResults() {
    const query = search.value.trim();
    toc.hidden = Boolean(query);
    results.hidden = !query;
    if (!query) {
        return;
    }
    const found = find(query);
    results.innerHTML = found.length
        ? found.map((hit, i) => `<li><a href="${escapeHtml(hit.href)}"${i === 0 ? ' class="selected"' : ''}><strong>${escapeHtml(hit.title)}</strong><span>${escapeHtml(hit.text)}</span></a></li>`).join('')
        : '<li class="none">Nothing in the manual matches that.</li>';
}

function moveSelection(step) {
    const hits = [...results.querySelectorAll('a')];
    if (!hits.length) {
        return;
    }
    const at = hits.findIndex((hit) => hit.classList.contains('selected'));
    hits[at]?.classList.remove('selected');
    const next = hits[(at + step + hits.length) % hits.length];
    next.classList.add('selected');
    next.scrollIntoView({ block: 'nearest' });
}

function clearSearch() {
    search.value = '';
    showResults();
}

search.addEventListener('input', showResults);
search.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        moveSelection(event.key === 'ArrowDown' ? 1 : -1);
    } else if (event.key === 'Enter') {
        const hit = results.querySelector('a.selected');
        if (hit) {
            location.hash = hit.getAttribute('href');
            clearSearch();
        }
    } else if (event.key === 'Escape') {
        clearSearch();
        search.blur();
    }
});
results.addEventListener('click', (event) => {
    if (event.target.closest('a')) {
        setTimeout(clearSearch);
    }
});

// --- The rest of the window -----------------------------------------------------------------------

function applyPalette(colors) {
    const style = document.documentElement.style;
    const variables = {
        background: '--bg',
        foreground: '--fg',
        accent: '--accent',
        color0: '--surface',
        color8: '--muted',
        selection_background: '--selection',
        selection_foreground: '--selection-fg',
    };
    for (const [key, variable] of Object.entries(variables)) {
        if (colors?.[key]) {
            style.setProperty(variable, colors[key]);
        } else {
            style.removeProperty(variable);
        }
    }
    if (colors) {
        document.documentElement.dataset.mode = colors.light ? 'light' : 'dark';
    } else {
        delete document.documentElement.dataset.mode;
    }
}

document.addEventListener('click', (event) => {
    const copy = event.target.closest('button.copy');
    if (copy) {
        window.manual.copy(copy.nextElementSibling.textContent);
        copy.textContent = 'Copied';
        setTimeout(() => {
            copy.textContent = 'Copy';
        }, 1500);
        return;
    }
    const link = event.target.closest('a.external');
    if (link) {
        event.preventDefault();
        window.manual.openExternal(link.href);
    }
});

document.addEventListener('keydown', (event) => {
    const typing = event.target === search;
    if ((event.ctrlKey && (event.key === 'k' || event.key === 'f')) || (event.key === '/' && !typing)) {
        event.preventDefault();
        search.focus();
        search.select();
    } else if (event.ctrlKey && (event.key === '=' || event.key === '+')) {
        window.manual.zoom(0.5);
    } else if (event.ctrlKey && event.key === '-') {
        window.manual.zoom(-0.5);
    } else if (event.ctrlKey && event.key === '0') {
        window.manual.zoom(0);
    } else if (event.altKey && event.key === 'ArrowLeft') {
        history.back();
    } else if (event.altKey && event.key === 'ArrowRight') {
        history.forward();
    }
});

async function start() {
    applyPalette(await window.manual.palette());
    window.manual.onPalette(applyPalette);

    for (const group of await window.manual.toc()) {
        for (const file of group.pages) {
            const page = { id: file.replace(/^.*\//, '').replace(/\.md$/, ''), file, section: group.section };
            pages.push(page);
            byId.set(page.id, page);
        }
    }
    await Promise.all(pages.map(async (page) => {
        page.markdown = await window.manual.page(page.file);
        page.title = page.markdown.match(/^# (.+)$/m)?.[1].trim() || page.id;
    }));
    pages.forEach(render);
    buildToc();

    window.addEventListener('hashchange', () => show(location.hash));
    window.manual.onOpen((page) => {
        location.hash = page;
    });
    show(location.hash);
}

start();
