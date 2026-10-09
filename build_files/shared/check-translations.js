'use strict';

// The translations of the Amethystora apps (i18n.js), for 20-tests.sh and for whoever changes a string.
//
//   check-translations.js [root]           check, and exit 1 on anything wrong
//   check-translations.js --write [root]   also rewrite each app's locale/en.json from the code
//   ... --po DIR                           also the shell programs' gettext catalogs in DIR (po/), and
//                                          with --write their template, DIR/amethystora.pot
//
// root is where the apps are, /usr/lib/amethystora-* under it: / in the image (the default), or
// system_files/shared in the repository. In the image it runs on the Manual's own Electron as Node, as
// check-manual.js does:
//
//   ELECTRON_RUN_AS_NODE=1 /usr/lib/amethystora-manual/amethystora-manual check-translations.js
//
// Every English message is found where the code says it: the first argument of t( or t.parts(, which
// has to be a plain string in quotes, the text or listed attributes of an element in index.html marked
// data-i18n or data-i18n-attr, and what an app shows from data of its own (t.dynamic), which is listed
// in DATA below. locale/en.json has to hold exactly those, each as its own
// translation: it is what Weblate translates from. Every other catalog has to parse, and use no value a
// message does not have. A translation of a message the code no longer has is only reported: Weblate
// takes it out at its next sync.

const fs = require('node:fs');
const path = require('node:path');

const args = process.argv.slice(2);
const write = args.includes('--write');
const poAt = args.indexOf('--po');
const poDir = poAt >= 0 ? args[poAt + 1] : null;
const root = args.find((arg, at) => !arg.startsWith('--') && (poAt < 0 || at !== poAt + 1)) || '/';
const APPS = ['amethystora-manual', 'amethystora-security', 'amethystora-update', 'amethystora-logs', 'amethystora-notes', 'amethystora-control',
    'amethystora-backups'];
// Not the apps' own code: the translations themselves, and the Markdown renderer
const SKIP = new Set(['i18n.js', 'marked.umd.js', 'preload.js']);

const i18nFile = path.join(root, 'usr/lib/amethystora-manual/resources/app/i18n.js');
const I18N = require(path.resolve(i18nFile));

// The words of an app's launcher, in its main entry and its actions, which translate-desktop.py writes
// into it in every language the app's catalogs have them in
function launcher(app) {
    const text = fs.readFileSync(path.join(root, 'usr/share/applications', `${app}.desktop`), 'utf8');
    return [...text.matchAll(/^(?:Name|GenericName|Comment|Keywords)=(.+)$/gm)].map((match) => match[1].trim());
}

// The messages an app reads from data rather than from its code (t.dynamic()), and its launcher's
const DATA = {
    // The names of the manual's sections, in its table of contents
    'amethystora-manual': () => [
        ...JSON.parse(fs.readFileSync(path.join(root, 'usr/share/amethystora/manual/pages.json'), 'utf8')).map((group) => group.section),
        ...launcher('amethystora-manual'),
    ],
    'amethystora-security': () => launcher('amethystora-security'),
    'amethystora-update': () => launcher('amethystora-update'),
    'amethystora-logs': () => launcher('amethystora-logs'),
    'amethystora-notes': () => launcher('amethystora-notes'),
    'amethystora-control': () => launcher('amethystora-control'),
    'amethystora-backups': () => launcher('amethystora-backups'),
};

const problems = [];
const notes = [];

// A JavaScript string in quotes, as the text it stands for
function unquote(literal) {
    const quote = literal[0];
    return literal.slice(1, -1).replace(/\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)/g, (_match, escape) => {
        if (escape[0] === 'u' || escape[0] === 'x') {
            return String.fromCodePoint(parseInt(escape.replace(/^[ux]\{?|\}$/g, ''), 16));
        }
        return { n: '\n', t: '\t', r: '\r', 0: '\0' }[escape] ?? (escape === quote ? quote : escape);
    });
}

function decodeHtml(text) {
    return text.replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (_match, name) => ({
        amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'", nbsp: ' ',
    })[name]);
}

function messages(dir) {
    const found = new Map();
    const add = (message, where) => {
        if (!found.has(message)) {
            found.set(message, where);
        }
    };
    for (const file of fs.readdirSync(dir).filter((name) => name.endsWith('.js') && !SKIP.has(name))) {
        const text = fs.readFileSync(path.join(dir, file), 'utf8');
        // t( and t.parts( whose first argument is anything but a quoted string cannot be translated
        for (const match of text.matchAll(/(?<![\w$.])t(?:\.parts)?\(\s*(?=\S)/g)) {
            const rest = text.slice(match.index + match[0].length);
            const literal = /^('(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")/.exec(rest);
            const line = text.slice(0, match.index).split('\n').length;
            if (!literal) {
                problems.push(`${dir}/${file}:${line}: t() needs the English as a string in quotes`);
                continue;
            }
            add(unquote(literal[1]), `${file}:${line}`);
        }
    }
    const html = path.join(dir, 'index.html');
    if (fs.existsSync(html)) {
        const text = fs.readFileSync(html, 'utf8');
        // data-i18n itself, not data-i18n-attr
        for (const match of text.matchAll(/<(\w+)\b([^>]*\sdata-i18n(?![\w-])[^>]*)>([^<]*)<\/\1>/g)) {
            add(decodeHtml(match[3].trim()), 'index.html');
        }
        for (const match of text.matchAll(/<\w+\b([^>]*\bdata-i18n-attr="([^"]+)"[^>]*)>/g)) {
            for (const attribute of match[2].split(/\s+/).filter(Boolean)) {
                const value = new RegExp(`\\s${attribute}="([^"]*)"`).exec(match[1]);
                if (value) {
                    add(decodeHtml(value[1]), 'index.html');
                } else {
                    problems.push(`${dir}/index.html: data-i18n-attr names ${attribute}, which the element does not have`);
                }
            }
        }
    }
    return found;
}

let checked = 0;
for (const app of APPS) {
    const dir = path.join(root, 'usr/lib', app, 'resources/app');
    if (!fs.existsSync(dir)) {
        problems.push(`${dir}: not there`);
        continue;
    }
    const found = messages(dir);
    for (const message of DATA[app]?.() || []) {
        if (!found.has(message)) {
            found.set(message, 'data');
        }
    }
    for (const [message, where] of found) {
        try {
            I18N.parse(message);
        } catch (error) {
            problems.push(`${app} ${where}: ${error.message}`);
        }
    }
    const folder = path.join(dir, 'locale');
    const baseFile = path.join(folder, 'en.json');
    const sorted = [...found.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    const base = Object.fromEntries(sorted.map((message) => [message, message]));
    if (write) {
        fs.mkdirSync(folder, { recursive: true });
        fs.writeFileSync(baseFile, `${JSON.stringify(base, null, 2)}\n`);
    }
    let current = null;
    try {
        current = JSON.parse(fs.readFileSync(baseFile, 'utf8'));
    } catch {
        problems.push(`${app}: locale/en.json is missing or is not JSON`);
    }
    if (current && JSON.stringify(current) !== JSON.stringify(base)) {
        const missing = sorted.filter((message) => !Object.hasOwn(current, message));
        const extra = Object.keys(current).filter((message) => !found.has(message));
        problems.push(`${app}: locale/en.json is not what the code says (${missing.length} missing, ${extra.length} no longer used, or out of order): run node build_files/shared/check-translations.js --write system_files/shared`);
    }
    for (const file of fs.existsSync(folder) ? fs.readdirSync(folder) : []) {
        if (!file.endsWith('.json') || file === 'en.json') {
            continue;
        }
        if (!/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*\.json$/.test(file)) {
            problems.push(`${app}: locale/${file} is not named after a language`);
            continue;
        }
        let catalog;
        try {
            catalog = JSON.parse(fs.readFileSync(path.join(folder, file), 'utf8'));
        } catch (error) {
            problems.push(`${app}: locale/${file} is not JSON: ${error.message}`);
            continue;
        }
        let stale = 0;
        for (const [message, translation] of Object.entries(catalog)) {
            if (!found.has(message)) {
                stale += 1;
                continue;
            }
            if (typeof translation !== 'string') {
                problems.push(`${app}: locale/${file}: the translation of "${message}" is not text`);
                continue;
            }
            if (!translation) {
                continue;
            }
            try {
                const own = I18N.names(message);
                for (const name of I18N.names(translation)) {
                    if (!own.has(name)) {
                        problems.push(`${app}: locale/${file}: "${translation}" uses {${name}}, which "${message}" does not have`);
                    }
                }
            } catch (error) {
                problems.push(`${app}: locale/${file}: ${error.message}`);
            }
        }
        if (stale) {
            notes.push(`${app}: locale/${file} has ${stale} translation(s) of messages the code no longer has`);
        }
        checked += 1;
    }
}

// --- The shell programs ------------------------------------------------------------------------------
//
// What the security report and the app permissions say is translated with gettext, in the text domain
// amethystora: gettext "...", eval_gettext "..." and eval_ngettext "..." "..." N, with their values as
// shell variables (${NAME}), which marks the message sh-format. A comment that starts "# Translators:"
// goes to the translators with every message up to the next empty line.

const SHELL = ['usr/libexec/amethystora-security-status', 'usr/libexec/amethystora-app-permissions', 'usr/libexec/amethystora-layout-offer',
    'usr/libexec/amethystora-control-list', 'usr/libexec/amethystora-security-config', 'usr/libexec/amethystora-hardening',
    'usr/libexec/amethystora-home-networks-notice'];

// A shell word in quotes, as the program it is passed to receives it
function unshell(word) {
    return word[0] === "'" ? word.slice(1, -1) : word.slice(1, -1).replace(/\\(["\\$`])/g, '$1');
}

const QUOTED = String.raw`("(?:[^"\\]|\\.)*"|'[^']*')`;
const CALL = new RegExp(String.raw`(?<![\w-])(eval_ngettext|eval_gettext|gettext)\s+${QUOTED}(?:\s+${QUOTED})?`, 'g');

function shellMessages() {
    const found = new Map();
    for (const script of SHELL) {
        const lines = fs.readFileSync(path.join(root, script), 'utf8').split('\n');
        let comment = '';
        lines.forEach((line) => {
            const note = /^\s*#\s*Translators:\s*(.*)$/.exec(line);
            if (note) {
                comment = note[1];
                return;
            }
            if (!line.trim()) {
                comment = '';
            }
            for (const match of line.matchAll(CALL)) {
                const [, call, first, second] = match;
                const id = unshell(first);
                const plural = call === 'eval_ngettext' && second ? unshell(second) : null;
                const key = `${id}\u0000${plural || ''}`;
                const entry = found.get(key) || { id, plural, files: new Set(), comment: '' };
                entry.files.add(script);
                entry.comment ||= comment;
                found.set(key, entry);
            }
        });
    }
    return [...found.values()];
}

const VARIABLE = /\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g;
const variables = (text) => new Set([...text.matchAll(VARIABLE)].map((match) => match[1]));
const poString = (text) => `"${text.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`;

function template(entries) {
    const out = [
        '# What Amethystora\'s own shell programs say, the security report and the app permissions, for',
        '# translation. Written by build_files/shared/check-translations.js --write; translated on Weblate.',
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: amethystora\\n"',
        '"Report-Msgid-Bugs-To: https://github.com/iarsslen/amethystora/issues\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        '"Plural-Forms: nplurals=INTEGER; plural=EXPRESSION;\\n"',
        '',
    ];
    for (const entry of entries) {
        if (entry.comment) {
            out.push(`#. Translators: ${entry.comment}`);
        }
        out.push(`#: ${[...entry.files].join(' ')}`);
        if (variables(entry.id).size || (entry.plural && variables(entry.plural).size)) {
            out.push('#, sh-format');
        }
        out.push(`msgid ${poString(entry.id)}`);
        if (entry.plural) {
            out.push(`msgid_plural ${poString(entry.plural)}`, 'msgstr[0] ""', 'msgstr[1] ""');
        } else {
            out.push('msgstr ""');
        }
        out.push('');
    }
    return out.join('\n');
}

// The entries of a .po file: msgid, msgid_plural and every msgstr, with its flags
function readPo(text) {
    const entries = [];
    let entry = null;
    let field = null;
    const finish = () => {
        if (entry?.msgid !== undefined) {
            entries.push(entry);
        }
        entry = { flags: '', msgstr: [] };
    };
    finish();
    for (const raw of text.split('\n')) {
        const line = raw.trim();
        if (!line) {
            finish();
            field = null;
            continue;
        }
        if (line.startsWith('#,')) {
            entry.flags += line;
            continue;
        }
        if (line.startsWith('#')) {
            continue;
        }
        const keyword = /^(msgid_plural|msgid|msgctxt|msgstr(?:\[(\d+)\])?)\s+(".*")$/.exec(line);
        const value = (quoted) => JSON.parse(quoted.replace(/\\(?!["\\nt])/g, '\\\\'));
        if (keyword) {
            field = keyword[2] !== undefined ? ['msgstr', Number(keyword[2])] : keyword[1] === 'msgstr' ? ['msgstr', 0] : [keyword[1]];
            if (field[0] === 'msgstr') {
                entry.msgstr[field[1]] = value(keyword[3]);
            } else {
                entry[field[0]] = value(keyword[3]);
            }
        } else if (/^".*"$/.test(line) && field) {
            if (field[0] === 'msgstr') {
                entry.msgstr[field[1]] += value(line);
            } else {
                entry[field[0]] += value(line);
            }
        }
    }
    finish();
    return entries;
}

// Which plural forms of a catalog stand for many numbers, from its Plural-Forms header. msgfmt --check,
// which compiles the catalogs in the build, holds such a form, and every message without plurals, to
// exactly the variables of its English (of msgid_plural, where there is one); a form that fewer than five
// of the numbers 0 to 1000 take, such as the one for n == 1, may leave the number out. The expression is
// C, which JavaScript reads the same once nothing but n, digits and operators is in it.
function pluralForms(entries) {
    const header = entries.find((entry) => entry.msgid === '')?.msgstr[0] || '';
    const match = /Plural-Forms:\s*nplurals\s*=\s*(\d+)\s*;\s*plural\s*=\s*([^;\n]+);?/.exec(header);
    if (!match) {
        return null;
    }
    const nplurals = Number(match[1]);
    const expression = match[2].trim();
    if (!/^[\sn0-9?:()<>=!&|%+\-*/]+$/.test(expression)) {
        return { nplurals, often: null, problem: `a Plural-Forms expression with more than n, digits and operators: ${expression}` };
    }
    // eslint-disable-next-line no-new-func
    const plural = new Function('n', `return +(${expression});`);
    const counts = new Array(nplurals).fill(0);
    for (let n = 0; n <= 1000; n += 1) {
        const index = plural(n);
        if (index >= 0 && index < nplurals) {
            counts[index] += 1;
        }
    }
    return { nplurals, often: counts.map((count) => count >= 5) };
}

let shellCatalogs = 0;
if (poDir) {
    const entries = shellMessages();
    const potFile = path.join(poDir, 'amethystora.pot');
    const pot = template(entries);
    if (write) {
        fs.writeFileSync(potFile, pot);
    }
    if (!fs.existsSync(potFile) || fs.readFileSync(potFile, 'utf8') !== pot) {
        problems.push(`${potFile} is not what the shell programs say: run node build_files/shared/check-translations.js --write --po po system_files/shared`);
    }
    const known = new Map(entries.map((entry) => [entry.id, entry]));
    for (const file of fs.existsSync(poDir) ? fs.readdirSync(poDir).filter((name) => name.endsWith('.po')) : []) {
        let stale = 0;
        const catalog = readPo(fs.readFileSync(path.join(poDir, file), 'utf8'));
        const forms = pluralForms(catalog);
        if (!forms) {
            problems.push(`po/${file}: no Plural-Forms header`);
        } else if (forms.problem) {
            problems.push(`po/${file}: ${forms.problem}`);
        }
        for (const entry of catalog) {
            if (entry.msgid === '' || entry.flags.includes('fuzzy')) {
                continue;
            }
            const source = known.get(entry.msgid);
            if (!source) {
                stale += 1;
                continue;
            }
            const english = source.plural || source.id;
            const allowed = variables(english);
            entry.msgstr.forEach((translation, index) => {
                if (!translation) {
                    return;
                }
                const used = variables(translation);
                for (const name of used) {
                    if (!allowed.has(name)) {
                        problems.push(`po/${file}: "${translation}" uses \${${name}}, which "${english}" does not have`);
                    }
                }
                // What msgfmt --check holds it to: every variable, unless it is a plural form for few numbers
                const strict = !source.plural || forms?.often?.[index] !== false;
                if (strict) {
                    for (const name of allowed) {
                        if (!used.has(name)) {
                            problems.push(`po/${file}: "${translation}" leaves out \${${name}}, which msgfmt --check requires`);
                        }
                    }
                }
                if (source.plural && forms && index >= forms.nplurals) {
                    problems.push(`po/${file}: "${source.id}" has msgstr[${index}], but the language has ${forms.nplurals} forms`);
                }
            });
            if (source.plural && forms && entry.msgstr.length !== forms.nplurals) {
                problems.push(`po/${file}: "${source.id}" has ${entry.msgstr.length} forms where the language has ${forms.nplurals}`);
            }
        }
        if (stale) {
            notes.push(`po/${file} has ${stale} translation(s) of messages the shell programs no longer say`);
        }
        shellCatalogs += 1;
    }
}

for (const note of notes) {
    console.log(`translations: ${note}`);
}
for (const problem of problems) {
    console.error(`::error::translations: ${problem}`);
}
console.log(`translations: ${APPS.length} apps, ${checked} catalogs checked${poDir ? `, and ${shellCatalogs} of the shell programs` : ''}`);
process.exit(problems.length ? 1 : 0);
