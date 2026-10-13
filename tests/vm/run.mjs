#!/usr/bin/env node
// A test run, in the lab container: builds the image from the commit tests/vm/run.sh sent, installs it onto a
// disk, boots it, and runs the suites in tests/vm/suites in it. Everything it did is in /vm/runs/<when>/
// (/vm/runs/last): run.log, one log per stage and per suite, a screenshot after each suite, the guest's
// journal, results.json, and summary.md, which it prints last.
//
//   node run.mjs [all | build | disk | test] [--keep]
//
// all (the default) does the three in turn and stops at the first that fails; the others do one, from what
// the last run left. --keep leaves the VM ("test") running afterwards, for a closer look over MCP. The exit
// status is 0 only when everything that ran passed.
//
// A suite is a bash script run as root in the guest, beside lib.sh: one "ok - ...", "not ok - ..." or
// "skip - ..." line per check, and exit status 0 only when it passed. Exit status 100 asks for a reboot:
// the suite runs again after it, with SUITE_PHASE one higher.
import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import { agent, call, decode, screendump } from './lab.mjs';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const SRC = path.resolve(HERE, '../..');
const SUITES = `${HERE}/suites`;
const IMAGE = 'localhost/amethystora:latest';
const DISK = 'test';
const VM = 'test';
const GUEST_DIR = '/run/amethystora-tests';
// Blank disks for the pools of disks (50-raid.sh): four alike, and a larger one
const SPARES_GB = [8, 8, 8, 8, 10];
const MAX_PHASES = 6;
const stage = process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : 'all';
const keep = process.argv.includes('--keep');

const RUN = `/vm/runs/${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}`;
fs.mkdirSync(RUN, { recursive: true });
fs.rmSync('/vm/runs/last', { force: true });
fs.symlinkSync(RUN, '/vm/runs/last');

const say = (line) => {
  console.log(line);
  fs.appendFileSync(`${RUN}/run.log`, `${line}\n`);
};
const minutes = (began) => `${((Date.now() - began) / 60000).toFixed(1)} min`;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const git = (...args) => execFileSync('git', ['-C', SRC, ...args], { encoding: 'utf8' }).trim();
const stages = [];

// A command, with its output in NAME.log and the end of it said when it fails
function step(name, command, args) {
  return new Promise((resolve) => {
    const began = Date.now();
    say(`== ${name}: ${[command, ...args].join(' ')}`);
    const log = fs.openSync(`${RUN}/${name}.log`, 'w');
    const child = spawn(command, args, { cwd: SRC, stdio: ['ignore', log, log] });
    child.on('close', (code) => {
      const passed = code === 0;
      stages.push({ stage: name, passed, time: minutes(began) });
      if (passed) {
        say(`== ${name}: passed in ${minutes(began)}`);
      } else {
        const tail = fs.readFileSync(`${RUN}/${name}.log`, 'utf8').trimEnd().split('\n').slice(-80).join('\n');
        say(`== ${name}: FAILED (exit ${code}) after ${minutes(began)}. The end of ${RUN}/${name}.log:\n${tail}`);
      }
      resolve(passed);
    });
  });
}

async function build() {
  // The submodules are the GNOME extensions the build compiles; a bundle carries none of them
  if (!(await step('submodules', 'git', ['-C', SRC, 'submodule', 'update', '--init', '--recursive']))) return false;
  if (!(await step('build', 'just', ['build', 'amethystora', 'latest', 'main']))) return false;
  // What earlier builds left, no longer tagged
  await step('prune', 'podman', ['image', 'prune', '-f']);
  return true;
}

const disk = () => step('disk', 'bash', [`${HERE}/make-disk.sh`, IMAGE, DISK]);

// The guest's boot id, or nothing while it does not answer
async function bootId() {
  try {
    const answer = await agent(VM, { op: 'read', path: '/proc/sys/kernel/random/boot_id' }, 5);
    return decode(answer.data).trim();
  } catch {
    return '';
  }
}

async function reboot() {
  const before = await bootId();
  await agent(VM, { op: 'exec', command: '(sleep 2; systemctl reboot) >/dev/null 2>&1 &' }, 30);
  const began = Date.now();
  for (;;) {
    await sleep(5000);
    const now = await bootId();
    if (now && now !== before) break;
    if (Date.now() - began > 900000) throw new Error('the VM did not come back within 15 minutes of a reboot');
  }
  await call('vm_wait', { name: VM, timeout_s: 900 });
  // Once the test account signs in by itself, a boot that brings it no session stalled: now and then PID 1
  // waits on the console for the answer to its size query, which plymouthd, holding the console, never
  // gives (12-amethystora-console.toml skips the query). Powered off and on again, said in the log, twice at
  // most; then the suite cannot run, rather than skip everything as passed.
  for (let tries = 0; await sessionExpected() && !(await session(240)); tries++) {
    if (tries === 2) throw new Error('the test account got no session after three boots');
    say('   no session after this boot: powering the VM off and on again');
    // What PID 1 and plymouthd wait on, which the power cycle loses: the evidence for the stall
    fs.writeFileSync(`${RUN}/stalled-boot-${tries + 1}.txt`, await guest('cat /proc/1/stack; ' +
      'for p in $(pidof plymouthd); do echo "plymouthd $p $(grep ^State /proc/$p/status)"; cat /proc/$p/stack; done; ' +
      'journalctl -b -o short-monotonic --no-pager _PID=1 | grep -v " audit" | tail -n 15', 60));
    await call('vm_stop', { name: VM, force: true });
    await call('vm_start', { name: VM, disk: DISK, spares_gb: SPARES_GB });
    await call('vm_wait', { name: VM, timeout_s: 900 });
  }
}

async function guest(command, seconds = 20) {
  try {
    return decode((await agent(VM, { op: 'exec', command, timeout: seconds }, seconds)).stdout).trim();
  } catch {
    return '';
  }
}
const sessionExpected = async () => (await guest('grep -s "^AutomaticLogin=tester" /etc/gdm/custom.conf')) !== '';
async function session(seconds) {
  for (const until = Date.now() + seconds * 1000; Date.now() < until; await sleep(10000)) {
    if ((await guest('loginctl show-user tester -p State --value')) === 'active') return true;
  }
  return false;
}

// The suites and lib.sh into the guest's /run, which a reboot empties
async function install() {
  await agent(VM, { op: 'exec', command: `mkdir -p ${GUEST_DIR}` });
  for (const name of fs.readdirSync(SUITES)) {
    const data = fs.readFileSync(`${SUITES}/${name}`).toString('base64');
    const answer = await agent(VM, { op: 'write', path: `${GUEST_DIR}/${name}`, data, mode: '0755' });
    if (answer.rc !== 0) throw new Error(`could not write ${name} into the VM: ${answer.error}`);
  }
}

async function suite(name) {
  const began = Date.now();
  let output = '';
  let rc = 0;
  for (let phase = 1; ; phase++) {
    await install();
    const answer = await agent(VM, { op: 'exec', command: `SUITE_PHASE=${phase} bash ${GUEST_DIR}/${name}`, timeout: 1800 }, 1800);
    output += decode(answer.stdout);
    const stderr = decode(answer.stderr);
    fs.appendFileSync(`${RUN}/${name}.log`, `--- phase ${phase}, exit ${answer.rc}${answer.error ? ` (${answer.error})` : ''}\n${decode(answer.stdout)}${stderr ? `--- stderr\n${stderr}` : ''}`);
    rc = answer.rc;
    if (rc !== 100 || phase >= MAX_PHASES) break;
    say(`   ${name}: rebooting for phase ${phase + 1}`);
    await reboot();
  }
  try {
    fs.writeFileSync(`${RUN}/${name}.png`, await screendump(VM));
  } catch {
    // No screen to take
  }
  const lines = output.split('\n');
  const failures = [];
  lines.forEach((line, i) => {
    if (!line.startsWith('not ok')) return;
    // A failure with the indented lines that explain it
    const detail = [];
    for (let j = i + 1; j < lines.length && lines[j].startsWith('  '); j++) detail.push(lines[j]);
    failures.push([line, ...detail].join('\n'));
  });
  const result = {
    suite: name,
    passed: rc === 0 && failures.length === 0,
    exit: rc,
    ok: lines.filter((l) => l.startsWith('ok')).length,
    skipped: lines.filter((l) => l.startsWith('skip')).length,
    failures,
    time: minutes(began),
  };
  say(`   ${name}: ${result.passed ? 'passed' : 'FAILED'} (${result.ok} ok, ${failures.length} not ok, ${result.skipped} skipped, exit ${rc}, ${result.time})`);
  return result;
}

async function test() {
  const began = Date.now();
  say(`== test: ${IMAGE} on disk ${DISK}, VM ${VM}`);
  try {
    await call('vm_stop', { name: VM, force: true });
  } catch {
    // Not running
  }
  await call('vm_start', { name: VM, disk: DISK, fresh: true, spares_gb: SPARES_GB });
  say(`   ${(await call('vm_wait', { name: VM, timeout_s: 900 })).content[0].text}`);
  const results = [];
  for (const name of fs.readdirSync(SUITES).filter((f) => /^\d\d-.+\.sh$/.test(f)).sort()) {
    try {
      results.push(await suite(name));
    } catch (error) {
      results.push({ suite: name, passed: false, exit: -1, ok: 0, skipped: 0, failures: [`not ok - the suite could not run: ${error.message}`], time: '-' });
      say(`   ${name}: could not run: ${error.message}`);
    }
  }
  try {
    const journal = await agent(VM, { op: 'exec', command: 'journalctl -b -p warning --no-pager -o short-monotonic; echo; systemctl --failed --no-pager', timeout: 120 }, 120);
    fs.writeFileSync(`${RUN}/journal.log`, decode(journal.stdout));
  } catch {
    // The guest no longer answers: the suites' logs say why
  }
  if (!keep) await call('vm_stop', { name: VM }).catch(() => {});
  fs.writeFileSync(`${RUN}/results.json`, `${JSON.stringify(results, null, 2)}\n`);
  const passed = results.every((r) => r.passed);
  stages.push({ stage: 'test', passed, time: minutes(began), results });
  return passed;
}

function summary() {
  const lines = [`# Test run ${path.basename(RUN)}`, '', `Commit: ${git('log', '-1', '--format=%h %s')}`, ''];
  for (const s of stages) {
    if (s.stage === 'prune') continue;
    lines.push(`- ${s.stage}: ${s.passed ? 'passed' : '**FAILED**'} (${s.time})`);
  }
  const tested = stages.find((s) => s.stage === 'test');
  if (tested) {
    lines.push('', '| Suite | Result | ok | not ok | skipped | Time |', '| --- | --- | --- | --- | --- | --- |');
    for (const r of tested.results) {
      lines.push(`| ${r.suite} | ${r.passed ? 'passed' : '**failed**'} | ${r.ok} | ${r.failures.length} | ${r.skipped} | ${r.time} |`);
    }
    for (const r of tested.results.filter((x) => !x.passed)) {
      lines.push('', `## ${r.suite} (exit ${r.exit})`, '', '```', ...(r.failures.length ? r.failures : ['(no "not ok" line: see its log)']), '```');
    }
  }
  lines.push('', `Files: ${RUN}`);
  const text = `${lines.join('\n')}\n`;
  fs.writeFileSync(`${RUN}/summary.md`, text);
  console.log(`\n${text}`);
}

// The lab's own files from the commit under test, so that the MCP server is the one this run used
for (const name of ['agent.py', 'lab.mjs', 'make-disk.sh', 'server.mjs']) {
  fs.copyFileSync(`${HERE}/${name}`, `/opt/amethystora-vm/${name}`);
}
say(`Test run of ${git('log', '-1', '--format=%h %s')}: ${stage}`);
let ok = true;
if (stage === 'all' || stage === 'build') ok = await build();
if (ok && (stage === 'all' || stage === 'disk')) ok = await disk();
if (ok && (stage === 'all' || stage === 'test')) ok = await test();
summary();
process.exit(ok ? 0 : 1);
