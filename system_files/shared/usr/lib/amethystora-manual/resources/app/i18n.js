'use strict';

// Translations for the Amethystora apps: the Manual, Security, Updates, Logs, Notes and Control. One file, which
// each app's main process require()s and each app's page loads as a script before its own (as I18N);
// the build hard-links the Manual's copy into the other apps, as it does Electron.
//
// The English text in the code is the key. t('Update now') is looked up in the app's catalog for the
// session's language, locale/<language>.json, and is its own English when the catalog has nothing for
// it. A message carries its values by name, {name}, and its plurals and variants in ICU MessageFormat:
//
//   t('Last updated {when}', { when })
//   t('{count, plural, one {# file} other {# files}}', { count })
//   t('{state, select, on {On} other {Off}}', { state })
//
// Braces are always syntax: there is no quoting. A number is written the language's way, with its
// separators; pass a string for a number that is a name, such as a process number. t.parts() keeps a
// value that is not text, an element of the page, as it is, for a sentence with a link or code in it.
//
// The catalogs are flat JSON, keyed by the English. locale/en.json lists every key with itself as the
// translation: it is what Weblate translates from, and build_files/shared/check-translations.js writes it
// from the code and checks every catalog against it.

(function (root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.I18N = factory();
    }
}(typeof self !== 'undefined' ? self : this, () => {
    // Languages written from right to left, by their ISO 639 codes
    const RTL = new Set(['ar', 'arc', 'ckb', 'dv', 'fa', 'he', 'ks', 'ps', 'sd', 'ug', 'ur', 'yi']);

    // The session's languages, best first, the way gettext reads them: LANGUAGE is a list (fr:en), and
    // LC_ALL, LC_MESSAGES or LANG one locale (fr_FR.UTF-8). LANGUAGE counts only under a real locale:
    // C and POSIX mean English whatever it says.
    function wanted(env) {
        const locale = env.LC_ALL || env.LC_MESSAGES || env.LANG || '';
        if (!locale || /^(C|POSIX)([._@]|$)/.test(locale)) {
            return [];
        }
        return [...String(env.LANGUAGE || '').split(':'), locale]
            .map((tag) => tag.replace(/[.@].*$/, '').replace(/_/g, '-'))
            .filter((tag) => /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(tag));
    }

    // The language to show, of those a catalog exists for: the first wanted one, by its whole tag or by
    // its language alone (pt-BR, then pt). English is the code's own and needs no catalog.
    function choose(available, env) {
        const lower = available.map((tag) => tag.toLowerCase());
        for (const tag of wanted(env)) {
            const language = tag.split('-')[0].toLowerCase();
            if (language === 'en') {
                return 'en';
            }
            const exact = lower.indexOf(tag.toLowerCase());
            if (exact >= 0) {
                return available[exact];
            }
            const base = lower.indexOf(language);
            if (base >= 0) {
                return available[base];
            }
        }
        return 'en';
    }

    function direction(lang) {
        return RTL.has(String(lang).split('-')[0].toLowerCase()) ? 'rtl' : 'ltr';
    }

    // --- Messages ---------------------------------------------------------------------------------------

    const HASH = { hash: true };

    // A message as parts: text, HASH (the # of a plural), and { name, type, options } for a value. Parsed
    // once and kept.
    function parse(message) {
        let at = 0;
        const fail = (what) => {
            throw new Error(`${what} at ${at} in "${message}"`);
        };
        function parts(inPlural, nested) {
            const list = [];
            let text = '';
            const flush = () => {
                if (text) {
                    list.push(text);
                    text = '';
                }
            };
            while (at < message.length) {
                const c = message[at];
                if (c === '}') {
                    if (!nested) {
                        fail('a } that closes nothing');
                    }
                    break;
                }
                if (c === '{') {
                    flush();
                    list.push(argument(inPlural));
                } else if (c === '#' && inPlural) {
                    flush();
                    list.push(HASH);
                    at += 1;
                } else {
                    text += c;
                    at += 1;
                }
            }
            flush();
            return list;
        }
        function argument(inPlural) {
            at += 1;
            const head = /^\s*(\w+)\s*(?:,\s*(plural|select)\s*,\s*)?(})?/.exec(message.slice(at));
            if (!head) {
                fail('a value without a name');
            }
            at += head[0].length;
            const [, name, type, closed] = head;
            if (closed) {
                return { name };
            }
            if (!type) {
                fail(`a value ${name} that is not closed`);
            }
            const options = {};
            for (;;) {
                const key = /^\s*(=\d+|\w+)\s*\{/.exec(message.slice(at));
                if (!key) {
                    break;
                }
                at += key[0].length;
                options[key[1]] = parts(type === 'plural' || inPlural, true);
                if (message[at] !== '}') {
                    fail(`the option ${key[1]} of ${name} is not closed`);
                }
                at += 1;
            }
            const end = /^\s*}/.exec(message.slice(at));
            if (!end || !options.other) {
                fail(`${name} needs an "other" option and a closing }`);
            }
            at += end[0].length;
            return { name, type, options };
        }
        return parts(false, false);
    }

    // The names of the values a message takes, and of those its plurals and selects choose by
    function names(message) {
        const found = new Set();
        const walk = (list) => {
            for (const part of list) {
                if (part && part.name) {
                    found.add(part.name);
                    Object.values(part.options || {}).forEach(walk);
                }
            }
        };
        walk(parse(message));
        return found;
    }

    // --- One language ------------------------------------------------------------------------------------

    // lang is the catalog's language and locale the session's own tag in that language, which dates,
    // numbers and lists are written for: en-US and en-GB share the English, not the order of a date
    function use({ lang = 'en', locale = lang, strings = {} } = {}) {
        const cache = new Map();
        const plurals = new Intl.PluralRules(locale);
        const numbers = new Intl.NumberFormat(locale);

        function parsed(message) {
            if (!cache.has(message)) {
                let value;
                try {
                    value = parse(message);
                } catch {
                    // A catalog that will not parse shows its text as it is, rather than nothing
                    value = [message];
                }
                cache.set(message, value);
            }
            return cache.get(message);
        }

        function render(list, values, count, out) {
            for (const part of list) {
                if (typeof part === 'string') {
                    out.push(part);
                } else if (part === HASH) {
                    out.push(numbers.format(count));
                } else if (part.type === 'plural') {
                    const n = Number(values?.[part.name]);
                    const option = part.options[`=${n}`] || part.options[plurals.select(n)] || part.options.other;
                    render(option, values, n, out);
                } else if (part.type === 'select') {
                    const option = part.options[String(values?.[part.name])] || part.options.other;
                    render(option, values, count, out);
                } else {
                    const value = values?.[part.name];
                    if (value === undefined || value === null) {
                        out.push(`{${part.name}}`);
                    } else {
                        out.push(typeof value === 'number' ? numbers.format(value) : value);
                    }
                }
            }
            return out;
        }

        // What the English message is in this language
        function translated(message) {
            const own = Object.prototype.hasOwnProperty.call(strings, message) ? strings[message] : '';
            return typeof own === 'string' && own ? own : message;
        }

        function parts(message, values) {
            const out = render(parsed(translated(message)), values, 0, []);
            // Text next to text is joined, so that what is left is text and the values that are not
            const joined = [];
            for (const part of out) {
                if (typeof part === 'string' && typeof joined[joined.length - 1] === 'string') {
                    joined[joined.length - 1] += part;
                } else {
                    joined.push(part);
                }
            }
            return joined;
        }

        function t(message, values) {
            return parts(message, values).map(String).join('');
        }
        t.parts = parts;
        // A message that is not written in the code but read from data the catalog lists as well, such
        // as the section names in the Manual's pages.json, which check-translations.js reads for it
        t.dynamic = (message, values) => t(String(message), values);
        t.lang = lang;
        t.locale = locale;
        t.dir = direction(lang);
        t.number = (n, options) => new Intl.NumberFormat(locale, options).format(n);
        // "a, b and c" the way the language joins them; type 'disjunction' for "a, b or c"
        t.list = (items, type = 'conjunction') => new Intl.ListFormat(locale, { type }).format(items.map(String));
        // "yesterday", "today", "tomorrow", "in 3 days": a day relative to today, in the language's words
        t.days = (days) => new Intl.RelativeTimeFormat(locale, { numeric: 'auto' }).format(days, 'day');

        // The page's own markup: an element with data-i18n has its text translated, and one with
        // data-i18n-attr="aria-label placeholder" those attributes
        t.page = (doc) => {
            doc.documentElement.lang = lang;
            doc.documentElement.dir = t.dir;
            for (const node of doc.querySelectorAll('[data-i18n]')) {
                node.textContent = t(node.textContent.trim());
            }
            for (const node of doc.querySelectorAll('[data-i18n-attr]')) {
                for (const attribute of node.dataset.i18nAttr.split(/\s+/).filter(Boolean)) {
                    if (node.hasAttribute(attribute)) {
                        node.setAttribute(attribute, t(node.getAttribute(attribute)));
                    }
                }
            }
        };
        return t;
    }

    // --- The main process ----------------------------------------------------------------------------------

    // The language and catalog of an app whose catalogs are in dir/locale, for the main process to use
    // and to hand to its page. Read once, at start: the session's language does not change under it.
    function load(dir, env = process.env) {
        const fs = require('node:fs');
        const path = require('node:path');
        const folder = path.join(dir, 'locale');
        let available = [];
        try {
            available = fs.readdirSync(folder)
                .filter((file) => /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*\.json$/.test(file) && file !== 'en.json')
                .map((file) => file.slice(0, -'.json'.length));
        } catch {
            // No catalogs: English
        }
        const lang = choose(available, env);
        const language = lang.split('-')[0].toLowerCase();
        // The session's own tag in the chosen language, when it has one: fr-CA for fr, en-US for English
        const own = wanted(env).find((tag) => tag.split('-')[0].toLowerCase() === language);
        let locale = lang;
        try {
            locale = Intl.getCanonicalLocales(own || lang)[0];
        } catch {
            // A tag Intl does not take: the catalog's own
        }
        let strings = {};
        if (lang !== 'en') {
            try {
                strings = JSON.parse(fs.readFileSync(path.join(folder, `${lang}.json`), 'utf8'));
            } catch {
                return { lang: 'en', locale: 'en', dir: 'ltr', strings: {} };
            }
        }
        return { lang, locale, dir: direction(lang), strings };
    }

    return { use, load, choose, wanted, direction, parse, names };
}));
