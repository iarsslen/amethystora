'use strict';

// common/src/units.rs: how Chromium's Intl writes a number with a unit, as a pattern for each language the
// apps are translated into, each unit, each width and each plural form, taken from Intl itself. ICU4X has
// no digital units. It was written on Electron 44.7.0, the Electron windows' own; a Node with full ICU
// writes the same, but for what its CLDR has changed since:
//
//   node units.js > ../common/src/units.rs

// The languages, then the regions whose words differ from their language's (en-GB writes "secs", fr-CA a plain
// space): only a pattern that differs from the language's is kept for a region
const LANGUAGES = ['en', 'fr', 'de', 'es', 'ar'];
const REGIONS = ['en-GB', 'en-AU', 'en-CA', 'en-IE', 'en-IN', 'en-NZ', 'en-ZA', 'fr-CA', 'fr-CH', 'fr-BE', 'de-AT', 'de-CH',
    'es-MX', 'es-419', 'es-US', 'es-AR', 'es-CO', 'ar-EG', 'ar-SA', 'ar-MA', 'ar-DZ', 'ar-TN', 'ar-AE'];
const UNITS = ['byte', 'kilobyte', 'megabyte', 'gigabyte', 'terabyte', 'second'];
const WIDTHS = ['short', 'long'];
// A number in each plural form a language has: Arabic has them all
const SAMPLES = [0, 1, 2, 3, 11, 100, 1.5];

const rows = [];
const seen = new Map();
for (const lang of [...LANGUAGES, ...REGIONS]) {
    const plurals = new Intl.PluralRules(lang);
    for (const unit of UNITS) {
        for (const width of WIDTHS) {
            const patterns = {};
            for (const n of SAMPLES) {
                const category = plurals.select(n);
                if (patterns[category]) {
                    continue;
                }
                const number = new Intl.NumberFormat(lang, { maximumFractionDigits: 1 }).format(n);
                const text = new Intl.NumberFormat(lang, { style: 'unit', unit, unitDisplay: width, maximumFractionDigits: 1 }).format(n);
                // A form may say its number in words (Arabic's one and two): the pattern is then the words
                patterns[category] = text.includes(number) ? text.replace(number, '{0}') : text;
            }
            for (const [category, pattern] of Object.entries(patterns)) {
                const base = lang.split('-')[0];
                seen.set(`${lang} ${unit} ${width} ${category}`, pattern);
                if (lang !== base && seen.get(`${base} ${unit} ${width} ${category}`) === pattern) {
                    continue;
                }
                rows.push(`    (${JSON.stringify(lang)}, ${JSON.stringify(unit)}, ${JSON.stringify(width)}, ${JSON.stringify(category)}, ${JSON.stringify(pattern)}),`);
            }
        }
    }
}

process.stdout.write(`//! How a number with a unit is written, in the languages the apps are translated into, as Chromium's Intl wrote
//! it for the Electron windows: (language or language-region, unit, width, plural form, pattern). Written by apps/tools/units.js
//! from Intl itself; run it again when a language is added. Another language falls back to English.

pub(crate) const PATTERNS: &[(&str, &str, &str, &str, &str)] = &[
${rows.join('\n')}
];
`);
