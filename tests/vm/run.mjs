#!/usr/bin/env node
// A test run, in the lab container: builds the image from the commit tests/vm/run.sh sent, installs it onto a
// disk, boots it, and runs the suites in tests/vm/suites in it. Everything it did is in /vm/runs/<when>/
// (/vm/runs/last): run.log, one log per stage and per suite, a screenshot after each suite, the guest's
// journal, results.json, and summary.md, which it prints last.
//
//   node run.mjs [all | build | disk | test] [--keep] [--image IMAGE] [--tag TAG] [--suites NN,NN...]
//
// all (the default) does the three in turn and stops at the first that fails; the others do one, from what
// the last run left. --keep leaves the VMs running afterwards, for a closer look over MCP. The exit status is
// 0 only when everything that ran passed. VMLAB_NAME (default test) names the run's image tag, disks and VMs,
// so that two sessions' runs do not take each other's. --image builds amethystora-dx, or either with -nvidia-open or
// -nvidia-lts, instead of amethystora; --tag builds that stream (beta, which can be on the next Fedora) instead of
// latest; --suites runs only the suites with those numbers.
//
// A suite is a bash script run as root in the guest, beside lib.sh: one "ok - ...", "not ok - ..." or
// "skip - ..." line per check, and exit status 0 only when it passed. Exit status 100 asks for a reboot:
// the suite runs again after it, with SUITE_PHASE one higher. A suite whose second line is
// "# vmlab-vm: installer" runs on a machine of its own installed as the installer lays a disk out, encrypted, and
// "# vmlab-vm: screens" on the first machine's disk with four screens.
// Exit status 101 runs the next phase in the same boot, for what takes longer than a phase may (30 minutes),
// and with /var/lib/vmlab-tests/usb.json left (usb_next in lib.sh) USB devices plugged in or out first.
// A phase that leaves /var/lib/vmlab-tests/next-boot.json gets a power cycle instead of a reboot, with what it
// asks for (next_boot in lib.sh): spare disks absent or faulty, other credentials, the passphrase typed; or
// with {"itself": true} no restart from here at all, only a wait for the one the phase left to happen, a soft
// reboot included, which keeps the boot id and counts in systemd's SoftRebootsCount.
import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import { agent, call, decode, qmp, screendump, serialWrite } from './lab.mjs';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const SRC = path.resolve(HERE, '../..');
const SUITES = `${HERE}/suites`;
const NAME = process.env.VMLAB_NAME || 'test';
if (!/^[a-z0-9][a-z0-9-]{0,20}$/.test(NAME)) throw new Error(`VMLAB_NAME must be lowercase letters, digits and - (got ${NAME})`);
const option = (flag) => (process.argv.includes(flag) ? process.argv[process.argv.indexOf(flag) + 1] : undefined);
const BUILD = option('--image') || 'amethystora';
if (!/^amethystora(-dx)?(-nvidia-(open|lts))?$/.test(BUILD)) throw new Error(`run.mjs: no image ${BUILD}`);
const TAG = option('--tag') || 'latest';
if (!/^(latest|beta|stable)$/.test(TAG)) throw new Error(`run.mjs: no stream ${TAG}`);
const ONLY = option('--suites')?.split(',');
const BUILT = `localhost/${BUILD}:${TAG}`;
// What `just build` tags, kept under the run's own name at once, which the disks are made from
const IMAGE = `localhost/amethystora-run:${NAME}`;
const GUEST_DIR = '/run/amethystora-tests';
const NEXT_BOOT = '/var/lib/vmlab-tests/next-boot.json';
const USB = '/var/lib/vmlab-tests/usb.json';
// The USB devices a phase can have plugged in, on the VM's xHCI controller: sticks with serials of their own, on
// drives that read as zeros, and a keyboard and nothing else. Each has a port of its own (the tablet has 1):
// without one, QEMU puts a hub of its own in front of the second, which USB protection blocks as the new
// device it is.
const USB_DEVICES = {
  stick: { driver: 'usb-storage', serial: 'VMLAB-STICK-1', port: '2' },
  keyboard: { driver: 'usb-kbd', port: '3' },
  stick2: { driver: 'usb-storage', serial: 'VMLAB-STICK-2', port: '4' },
};
// The lab's disk passphrase, and the PIN a suite enrols the TPM with, both handed to systemd-cryptsetup as
// credentials so that nobody has to type them (next_boot can have one typed instead). The PIN goes under both of
// its names: systemd-cryptsetup first tries every LUKS2 token through libcryptsetup, asking "Please enter LUKS2
// token PIN:" (cryptsetup.luks2-pin), before its own TPM2 path (cryptsetup.tpm2-pin)
const PASSPHRASE = 'amethystora-lab-passphrase';
const TPM_PIN = '246813579';
// Two machines: the one `bootc install to-disk` makes, with blank disks for the pools of disks (50-raid.sh): four
// alike, then a larger one, and one larger than the system's data for its mirror, unplugged until a suite asks
// for it (next_boot), so that the others see five; and one installed as the installer lays a disk out, encrypted,
// with two disks for a pool and two larger than its own for the mirror
const MACHINES = {
  default: { vm: NAME, disk: NAME, make: [], spares: [8, 8, 8, 8, 10, 24], absent: [6], credentials: {} },
  installer: {
    vm: `${NAME}-installer`, disk: `${NAME}-installer`, make: ['40G', `--installer=${PASSPHRASE}`], spares: [8, 8, 48, 48],
    credentials: { 'cryptsetup.passphrase': PASSPHRASE, 'cryptsetup.tpm2-pin': TPM_PIN, 'cryptsetup.luks2-pin': TPM_PIN },
  },
  // The first one's disk again, on a machine with four screens side by side: a workspace on each (tiling/screens.js)
  screens: { vm: `${NAME}-screens`, disk: NAME, make: [], spares: [], absent: [], credentials: {}, screens: 4 },
};
const MAX_PHASES = 16;
const stage = process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : 'all';
const keep = process.argv.includes('--keep');

const RUN = `/vm/runs/${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}${NAME === 'test' ? '' : `-${NAME}`}`;
fs.mkdirSync(RUN, { recursive: true });
const LAST = NAME === 'test' ? '/vm/runs/last' : `/vm/runs/last-${NAME}`;
fs.rmSync(LAST, { force: true });
fs.symlinkSync(RUN, LAST);

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
  // Git submodules, if the repository has any again: a bundle carries none of them
  if (!(await step('submodules', 'git', ['-C', SRC, 'submodule', 'update', '--init', '--recursive']))) return false;
  const flavor = BUILD.match(/-(nvidia-(open|lts))$/)?.[1] || 'main';
  if (!(await step('build', 'just', ['build', BUILD.replace(/-nvidia-(open|lts)$/, ''), TAG, flavor]))) return false;
  if (!(await step('tag', 'podman', ['tag', BUILT, IMAGE]))) return false;
  // What earlier builds left, no longer tagged
  await step('prune', 'podman', ['image', 'prune', '-f']);
  return true;
}

// The machines whose suites are there to run
const suitesOf = (machine) => fs.readdirSync(SUITES)
  .filter((f) => /^\d\d-.+\.sh$/.test(f) && (!ONLY || ONLY.includes(f.slice(0, 2)))).sort()
  .filter((f) => (fs.readFileSync(`${SUITES}/${f}`, 'utf8').split('\n').slice(0, 3).join('\n')
    .match(/^# vmlab-vm: (installer|screens)$/m)?.[1] ?? 'default') === machine);

async function disk() {
  const made = new Set();
  for (const [kind, m] of Object.entries(MACHINES)) {
    // A machine on another's disk has it made once
    if (!suitesOf(kind).length || made.has(m.disk)) continue;
    if (!(await step(`disk-${kind}`, 'bash', [`${HERE}/make-disk.sh`, IMAGE, m.disk, ...m.make]))) return false;
    made.add(m.disk);
  }
  return true;
}

// The guest's boot id, or nothing while it does not answer
async function bootId(vm) {
  try {
    const answer = await agent(vm, { op: 'read', path: '/proc/sys/kernel/random/boot_id' }, 5);
    return decode(answer.data).trim();
  } catch {
    return '';
  }
}

// How many soft reboots systemd made since the kernel started, which a soft reboot counts and its boot id does
// not show
const softReboots = (vm) => guest(vm, 'systemctl show -P SoftRebootsCount', 10);

async function guest(vm, command, seconds = 20) {
  try {
    return decode((await agent(vm, { op: 'exec', command, timeout: seconds }, seconds)).stdout).trim();
  } catch {
    return '';
  }
}
const sessionExpected = async (vm) => (await guest(vm, 'grep -s "^AutomaticLogin=tester" /etc/gdm/custom.conf')) !== '';
async function session(vm, seconds) {
  for (const until = Date.now() + seconds * 1000; Date.now() < until; await sleep(10000)) {
    if ((await guest(vm, 'loginctl show-user tester -p State --value')) === 'active') return true;
  }
  return false;
}

// A VM of this run started, as a machine is, or with what a suite asked for its next start
async function start(machine, request = {}, fresh = false) {
  const m = MACHINES[machine];
  const credentials = { ...m.credentials, ...(request.credentials || {}) };
  if (request.type_passphrase) delete credentials['cryptsetup.passphrase'];
  // A credential asked for as null is left out: {"cryptsetup.passphrase": null} has the TPM open the disk alone
  for (const [key, value] of Object.entries(credentials)) if (value === null) delete credentials[key];
  await call('vm_start', { name: m.vm, disk: m.disk, fresh, spares_gb: m.spares,
    absent: request.absent || m.absent || [], system_absent: Boolean(request.system_absent), faulty: request.faulty || {}, credentials,
    screens: m.screens || 1 });
  if (request.menu_last) await chooseLastEntry(m.vm);
  if (request.menu_edit) await editEntry(m.vm);
  if (request.type_passphrase) await typePassphrase(m.vm);
}

// The serial console's text, once the boot menu shows on it, before its countdown ends
async function bootMenu(vm) {
  const serial = `/vm/vms/${vm}.serial`;
  const read = () => (fs.existsSync(serial) ? fs.readFileSync(serial, 'latin1') : '');
  const began = Date.now();
  while (!read().includes('will be executed automatically')) {
    if (Date.now() - began > 300000) throw new Error('no boot menu on the serial console within 5 minutes');
    await sleep(300);
  }
  return read;
}

// The default entry opened for editing, as a person would, with e. With a boot menu password GRUB asks for a
// user first, and refuses an empty one ("Press any key to continue"); without one, its editor opens, which
// Escape leaves. Either way the menu is back, and Enter starts the default entry. What GRUB did goes to the
// next phase as VMLAB_MENU_EDIT: asked, editor or nothing.
const menuEdits = new Map();
async function editEntry(vm) {
  const read = await bootMenu(vm);
  const before = read().length;
  await call('vm_keys', { name: vm, keys: ['e'] });
  await sleep(4000);
  const shown = read().slice(before);
  const asked = shown.includes('Enter username:');
  menuEdits.set(vm, asked ? 'asked' : /Ctrl-x|ESC to discard/.test(shown) ? 'editor' : 'nothing');
  await call('vm_keys', { name: vm, keys: ['esc'] });
  await sleep(2000);
  if (asked) {
    await call('vm_keys', { name: vm, keys: ['ret'] });
    await sleep(2000);
  }
  await call('vm_keys', { name: vm, keys: ['ret'] });
}

// The boot menu's last entry chosen, as a person would, with End and Enter, once the menu shows on the serial
// console (GRUB writes there through the firmware) and before its countdown ends: on a system over several
// disks that is "Start with a disk missing" (custom.cfg, after every other entry)
async function chooseLastEntry(vm) {
  await bootMenu(vm);
  await call('vm_keys', { name: vm, keys: ['end', 'ret'] });
}

// The passphrase typed at the prompt, as a person would, once it shows on the serial console: the installer's
// disk starts without Plymouth, with console=ttyS0 last, so systemd asks there. How many times it was asked
// goes to the suite as VMLAB_PROMPTS.
const prompts = new Map();
async function typePassphrase(vm) {
  const serial = `/vm/vms/${vm}.serial`;
  const asked = () => (fs.existsSync(serial) ? fs.readFileSync(serial, 'latin1') : '').match(/[Pp]lease enter passphrase/g)?.length || 0;
  const began = Date.now();
  while (asked() === 0) {
    if (Date.now() - began > 600000) throw new Error('no passphrase prompt on the serial console within 10 minutes');
    await sleep(3000);
  }
  await sleep(2000);
  await serialWrite(vm, `${PASSPHRASE}\r`);
  // Long enough for a second prompt to show if there is one, which is then answered too
  await sleep(45000);
  if (asked() > 1) await serialWrite(vm, `${PASSPHRASE}\r`);
  prompts.set(vm, asked());
}

async function reboot(machine) {
  const { vm } = MACHINES[machine];
  // A power cycle, when the phase asked for one
  let request = null;
  try {
    const answer = await agent(vm, { op: 'read', path: NEXT_BOOT }, 10);
    if (answer.rc === 0) request = JSON.parse(decode(answer.data));
  } catch {
    // None asked for
  }
  const before = await bootId(vm);
  const softBefore = await softReboots(vm);
  if (request?.itself) {
    // The phase left something to restart the machine once it ended, as a person would
    await agent(vm, { op: 'exec', command: `rm -f ${NEXT_BOOT}` }, 10);
    say('   the machine restarts itself');
  } else if (request?.powers_off) {
    // ...or to power it off: started again once QEMU has ended, as a person presses the power button
    await agent(vm, { op: 'exec', command: `rm -f ${NEXT_BOOT}` }, 10);
    say('   the machine powers itself off');
    const off = new RegExp(`^${vm}: stopped`, 'm');
    for (const began = Date.now(); !off.test((await call('vm_list')).content[0].text); await sleep(5000)) {
      if (Date.now() - began > 900000) throw new Error('the VM did not power itself off within 15 minutes');
    }
    await start(machine);
  } else if (request) {
    await agent(vm, { op: 'exec', command: `rm -f ${NEXT_BOOT}` }, 10);
    say(`   power cycle: ${JSON.stringify(request)}`);
    await call('vm_stop', { name: vm });
    await start(machine, request);
  } else {
    await agent(vm, { op: 'exec', command: '(sleep 2; systemctl reboot) >/dev/null 2>&1 &' }, 30);
  }
  const began = Date.now();
  for (;;) {
    await sleep(5000);
    const now = await bootId(vm);
    if (now && (now !== before || (await softReboots(vm)) !== softBefore)) break;
    if (Date.now() - began > 900000) throw new Error('the VM did not come back within 15 minutes of a reboot');
  }
  await call('vm_wait', { name: vm, timeout_s: 900 });
  // Once the test account signs in by itself, a boot that brings it no session stalled: now and then PID 1
  // waits on the console for the answer to its size query, which plymouthd, holding the console, never
  // gives (12-amethystora-console.toml skips the query). Powered off and on again, said in the log, twice at
  // most; then the suite cannot run, rather than skip everything as passed.
  for (let tries = 0; await sessionExpected(vm) && !(await session(vm, 240)); tries++) {
    if (tries === 2) throw new Error('the test account got no session after three boots');
    say('   no session after this boot: powering the VM off and on again');
    // What PID 1 and plymouthd wait on, which the power cycle loses: the evidence for the stall
    fs.writeFileSync(`${RUN}/stalled-boot-${tries + 1}.txt`, await guest(vm, 'cat /proc/1/stack; ' +
      'for p in $(pidof plymouthd); do echo "plymouthd $p $(grep ^State /proc/$p/status)"; cat /proc/$p/stack; done; ' +
      'journalctl -b -o short-monotonic --no-pager _PID=1 | grep -v " audit" | tail -n 15', 60));
    await call('vm_stop', { name: vm, force: true });
    await start(machine, request ? { ...request, type_passphrase: false } : {});
    await call('vm_wait', { name: vm, timeout_s: 900 });
  }
}

// USB devices plugged out, then in, as a phase that ended with 101 asked (usb_next), before the next one
let drives = 0;
async function usb(vm) {
  let request = null;
  try {
    const answer = await agent(vm, { op: 'read', path: USB }, 10);
    if (answer.rc === 0) request = JSON.parse(decode(answer.data));
  } catch {
    // None asked for
  }
  if (!request) return;
  await agent(vm, { op: 'exec', command: `rm -f ${USB}` }, 10);
  for (const name of request.unplug || []) await qmp(vm, 'device_del', { id: `vmlab-${name}` }).catch(() => {});
  if (request.unplug?.length) await sleep(5000);
  for (const name of request.plug || []) {
    const device = USB_DEVICES[name];
    if (!device) throw new Error(`usb_next: no device ${name}`);
    const args = { driver: device.driver, id: `vmlab-${name}`, port: device.port };
    if (device.serial) {
      const node = `vmlab-drive-${++drives}`;
      await qmp(vm, 'blockdev-add', { driver: 'null-co', 'node-name': node, size: 64 * 1024 * 1024, 'read-zeroes': true });
      Object.assign(args, { drive: node, serial: device.serial });
    }
    await qmp(vm, 'device_add', args);
  }
  say(`   usb: ${JSON.stringify(request)}`);
}

// The suites and lib.sh into the guest's /run, which a reboot empties
async function install(vm) {
  await agent(vm, { op: 'exec', command: `mkdir -p ${GUEST_DIR}` });
  for (const name of fs.readdirSync(SUITES)) {
    const data = fs.readFileSync(`${SUITES}/${name}`).toString('base64');
    const answer = await agent(vm, { op: 'write', path: `${GUEST_DIR}/${name}`, data, mode: '0755' });
    if (answer.rc !== 0) throw new Error(`could not write ${name} into the VM: ${answer.error}`);
  }
}

async function suite(machine, name) {
  const { vm } = MACHINES[machine];
  const began = Date.now();
  let output = '';
  let rc = 0;
  for (let phase = 1; ; phase++) {
    await install(vm);
    const env = `SUITE_PHASE=${phase} VMLAB_PASSPHRASE=${PASSPHRASE} VMLAB_TPM_PIN=${TPM_PIN} VMLAB_PROMPTS=${prompts.get(vm) ?? ''}` +
      ` VMLAB_MENU_EDIT=${menuEdits.get(vm) ?? ''}`;
    prompts.delete(vm);
    menuEdits.delete(vm);
    const answer = await agent(vm, { op: 'exec', command: `${env} bash ${GUEST_DIR}/${name}`, timeout: 1800 }, 1800);
    output += decode(answer.stdout);
    const stderr = decode(answer.stderr);
    fs.appendFileSync(`${RUN}/${name}.log`, `--- phase ${phase}, exit ${answer.rc}${answer.error ? ` (${answer.error})` : ''}\n${decode(answer.stdout)}${stderr ? `--- stderr\n${stderr}` : ''}`);
    rc = answer.rc;
    if ((rc !== 100 && rc !== 101) || phase >= MAX_PHASES) break;
    // 101: the next phase in the same boot, for what takes longer than one phase may, or after USB devices
    if (rc === 101) {
      await usb(vm);
      continue;
    }
    say(`   ${name}: rebooting for phase ${phase + 1}`);
    await reboot(machine);
  }
  try {
    fs.writeFileSync(`${RUN}/${name}.png`, await screendump(vm));
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
  const results = [];
  for (const machine of Object.keys(MACHINES)) {
    const names = suitesOf(machine);
    if (!names.length) continue;
    const { vm, disk: base } = MACHINES[machine];
    say(`== test: ${IMAGE} on disk ${base}, VM ${vm}`);
    try {
      await call('vm_stop', { name: vm, force: true });
    } catch {
      // Not running
    }
    await start(machine, {}, true);
    say(`   ${(await call('vm_wait', { name: vm, timeout_s: 900 })).content[0].text}`);
    for (const name of names) {
      try {
        results.push(await suite(machine, name));
      } catch (error) {
        results.push({ suite: name, passed: false, exit: -1, ok: 0, skipped: 0, failures: [`not ok - the suite could not run: ${error.message}`], time: '-' });
        say(`   ${name}: could not run: ${error.message}`);
      }
    }
    try {
      const journal = await agent(vm, { op: 'exec', command: 'journalctl -b -p warning --no-pager -o short-monotonic; echo; systemctl --failed --no-pager', timeout: 120 }, 120);
      fs.writeFileSync(`${RUN}/journal${machine === 'default' ? '' : `-${machine}`}.log`, decode(journal.stdout));
    } catch {
      // The guest no longer answers: the suites' logs say why
    }
    if (!keep) await call('vm_stop', { name: vm }).catch(() => {});
  }
  fs.writeFileSync(`${RUN}/results.json`, `${JSON.stringify(results, null, 2)}\n`);
  const passed = results.every((r) => r.passed);
  stages.push({ stage: 'test', passed, time: minutes(began), results });
  return passed;
}

function summary() {
  const lines = [`# Test run ${path.basename(RUN)}`, '', `Commit: ${git('log', '-1', '--format=%h %s')}`, ''];
  for (const s of stages) {
    if (s.stage === 'prune' || s.stage === 'tag') continue;
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
say(`Test run of ${git('log', '-1', '--format=%h %s')}: ${stage}${NAME === 'test' ? '' : ` (${NAME})`}`);
let ok = true;
if (stage === 'all' || stage === 'build') ok = await build();
if (ok && (stage === 'all' || stage === 'disk')) ok = await disk();
if (ok && (stage === 'all' || stage === 'test')) ok = await test();
summary();
process.exit(ok ? 0 : 1);
