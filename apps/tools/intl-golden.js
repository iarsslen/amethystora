'use strict';

// What Chromium's Intl writes for every form common/src/i18n.rs writes, in the languages the apps are
// translated into: the golden file its tests compare with (common/tests/intl.json). It was written on
// Electron 44.7.0, the Electron windows' own; a Node with full ICU writes the same, but for what its CLDR
// has changed since:
//
//   TZ=UTC node intl-golden.js > ../common/tests/intl.json

const LOCALES = ['en', 'en-US', 'en-GB', 'fr', 'fr-CA', 'de', 'es', 'ar', 'ar-EG', 'ar-MA'];
const NUMBERS = [0, 1, 2, 7, 12.5, 1234, 12345, 1234.5678, -3, 0.0004, 1000000];
const PERCENTS = [0, 0.05, 0.5, 0.999, 1];
const DAYS = [-2, -1, 0, 1, 2, 5];
const LISTS = [['a'], ['a', 'b'], ['a', 'b', 'c']];
// A Saturday and a Tuesday morning, one in another year, in seconds since the epoch
const MOMENTS = [Date.UTC(2026, 8, 26, 12, 0, 5) / 1000, Date.UTC(2026, 0, 6, 9, 5, 0) / 1000, Date.UTC(2024, 11, 31, 23, 59, 59) / 1000];

// The Intl options each DateStyle of i18n.rs stands for
const STYLES = {
    Time: { hour: '2-digit', minute: '2-digit' },
    TimeNumeric: { hour: 'numeric', minute: '2-digit' },
    Time24: { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' },
    Time24Seconds: { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' },
    Weekday: { weekday: 'long' },
    WeekdayDayMonthShort: { weekday: 'short', day: 'numeric', month: 'short' },
    WeekdayDayMonth: { weekday: 'long', day: 'numeric', month: 'long' },
    WeekdayDayMonthYear: { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' },
    WeekdayDayMonthYearShort: { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' },
    DayMonthYear: { day: 'numeric', month: 'long', year: 'numeric' },
    DayMonthShort: { day: 'numeric', month: 'short' },
    DayMonthYearShort: { day: 'numeric', month: 'short', year: 'numeric' },
    MediumShort: { dateStyle: 'medium', timeStyle: 'short' },
};

const out = {};
for (const locale of LOCALES) {
    const entry = {
        numbers: NUMBERS.map((n) => [n, new Intl.NumberFormat(locale).format(n)]),
        percents: PERCENTS.map((n) => [n, new Intl.NumberFormat(locale, { style: 'percent' }).format(n)]),
        days: DAYS.map((n) => [n, new Intl.RelativeTimeFormat(locale, { numeric: 'auto' }).format(n, 'day')]),
        lists: LISTS.map((items) => [items, new Intl.ListFormat(locale, { type: 'conjunction' }).format(items)]),
        plurals: [0, 1, 2, 3, 5, 11, 100, 1.5].map((n) => [n, new Intl.PluralRules(locale).select(n)]),
        // The calls the apps make: Notes' and Backups' sizes, Control's seconds
        units: [[0, 'byte', 'long', 0, 0], [1, 'byte', 'long', 0, 0], [2, 'byte', 'long', 0, 0], [512, 'byte', 'long', 0, 0],
            [1.4, 'kilobyte', 'short', 1, 1], [12, 'megabyte', 'short', 0, 0], [1, 'gigabyte', 'short', 1, 1], [3.25, 'terabyte', 'short', 0, 1],
            [900, 'byte', 'short', 0, 0], [1, 'second', 'short', 0, 1], [2.5, 'second', 'short', 0, 1], [11, 'second', 'short', 0, 1]]
            .map(([n, unit, unitDisplay, min, max]) => [n, unit, unitDisplay, min, max, new Intl.NumberFormat(locale, { style: 'unit', unit, unitDisplay, minimumFractionDigits: min, maximumFractionDigits: max }).format(n)]),
        dates: {},
    };
    for (const [name, options] of Object.entries(STYLES)) {
        entry.dates[name] = MOMENTS.map((seconds) => [seconds, new Intl.DateTimeFormat(locale, options).format(new Date(seconds * 1000))]);
    }
    out[locale] = entry;
}
process.stdout.write(`${JSON.stringify(out, null, 1)}\n`);
