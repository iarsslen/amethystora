// Every Gio.Settings the shell code of our extensions makes is disposed on the main thread, never left to the
// collector: GJS sweeping a dropped settings object while dconf's worker thread dispatches a change to it deadlocks
// GNOME Shell for good (GJS's toggle queue against the settings backend's lock), and every screen lock is a disable
// and an enable. The rule, as this checks it: a settings object is kept in a variable or a field, and the same file
// calls run_dispose() on that variable or field; one returned by a function makes that function a maker whose callers
// are checked the same way; one used where it is made (`new Gio.Settings(...).get_...`) is refused. The preferences
// (prefs.js) run in a process of their own and are not checked.
//   node build_files/shared/test-settings-disposed.mjs EXTENSION_FOLDER...

import fs from 'node:fs';
import path from 'node:path';

const MAKERS = [/new Gio\.Settings\(/, /Gio\.Settings\.new\w*\(/, /\bgetSettings\(/];
const DEFINITION = /^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(|^\s+(?:static\s+)?(?!if\b|for\b|while\b|switch\b|catch\b)(\w+)\s*\([^)]*\)\s*\{\s*$/;

function escape(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// What on this line holds what is made: `this.name`, a variable, or null (an array's element, an argument)
function holder(line, at) {
    // Less the receiver: `this._ext.getSettings(...)`
    const before = line.slice(0, at).replace(/[\w.?]*$/, '');
    const match = before.match(/(this\.\w+|\b[A-Za-z_]\w*)\s*(?:\?\?)?=\s*(?:[^=;]*\?\s*)?$/);
    return match ? match[1] : null;
}

// Whether what is made on this line is used there and dropped: `new Gio.Settings(...).get_boolean(...)`
function usedWhereMade(line, found) {
    return /^[^()]*(\([^()]*\))*[^()]*\)\s*\.\s*\w/.test(line.slice(found.index + found[0].length));
}

// files: [{name, text}] of one extension; returns the problems found and how many settings objects were seen
export function check(files) {
    const problems = [];
    let made = 0;
    const lines = new Map(files.map(({name, text}) => [name, text.split(/\r?\n/)]));
    // First the makers: a function that returns a settings object it made
    const makers = [...MAKERS];
    for (const [name, list] of lines) {
        list.forEach((line, i) => {
            const found = MAKERS.map(re => line.match(re)).find(Boolean);
            if (!/^\s*return\b/.test(line) || !found || usedWhereMade(line, found))
                return;
            for (let j = i; j >= 0; j--) {
                const def = list[j].match(DEFINITION);
                if (def) {
                    makers.push(new RegExp(`\\b${def[1] ?? def[2]}\\(`));
                    return;
                }
            }
            problems.push(`${name}:${i + 1}: a settings object returned from outside any function`);
        });
    }
    for (const [name, list] of lines) {
        const text = list.join('\n');
        list.forEach((line, i) => {
            if (/^\s*(\/\/|\*)/.test(line) || DEFINITION.test(line))
                return;
            for (const re of makers) {
                const found = line.match(re);
                if (!found)
                    continue;
                made++;
                if (usedWhereMade(line, found)) {
                    problems.push(`${name}:${i + 1}: a settings object used where it is made, then left to the collector`);
                    break;
                }
                if (/^\s*return\b/.test(line))
                    break;
                const held = holder(line, found.index);
                if (held) {
                    const dispose = new RegExp(`${escape(held)}\\??\\.run_dispose\\(\\)`);
                    if (!dispose.test(text))
                        problems.push(`${name}:${i + 1}: ${held} is never run_dispose()d`);
                } else if (!/\.run_dispose\(\)/.test(text)) {
                    problems.push(`${name}:${i + 1}: a settings object made here, and nothing in the file is run_dispose()d`);
                }
                break;
            }
        });
    }
    return {problems, made};
}

function walk(dir, out = []) {
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory())
            walk(full, out);
        else if (entry.name.endsWith('.js') && entry.name !== 'prefs.js')
            out.push(full);
    }
    return out;
}

// The check itself must catch what it is for
const caught = check([{name: 'bad.js', text: [
    'export class Bad {',
    '    enable() {',
    '        this._settings = this._ext.getSettings(SCHEMA);',
    '        this._other = new Gio.Settings({schema_id: ID});',
    '        this._other.run_dispose();',
    '    }',
    '    _allowed() {',
    "        return !new Gio.Settings({schema_id: 'org.gnome.desktop.lockdown'}).get_boolean('x');",
    '    }',
    '}',
].join('\n')}]);
if (caught.made !== 3 || caught.problems.length !== 2)
    throw new Error(`the check does not catch what it is for: ${JSON.stringify(caught)}`);

let total = 0;
const problems = [];
for (const folder of process.argv.slice(2)) {
    const files = walk(folder).map(name => ({name: path.relative(folder, name), text: fs.readFileSync(name, 'utf8')}));
    const result = check(files);
    total += result.made;
    problems.push(...result.problems.map(p => `${path.basename(folder)}/${p}`));
}
if (problems.length) {
    console.log(problems.join('\n'));
    throw new Error(`${problems.length} settings objects left to the collector`);
}
// Nothing found means the check looked in the wrong place
if (process.argv.length > 2 && total < 40)
    throw new Error(`only ${total} settings objects found in ${process.argv.slice(2).join(' ')}`);
console.log(`${total} settings objects, each disposed`);
