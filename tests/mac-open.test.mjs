import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { encodeProj } from '../lib/claude.mjs';

const cli = fileURLToPath(new URL('../sessions.mjs', import.meta.url));

if (process.platform !== 'darwin') {
  console.log('합계: PASS 0 / FAIL 0 (macOS 전용)');
} else {
  await verifyMacOpen();
}

async function verifyMacOpen() {
  const root = mkdtempSync(join(tmpdir(), '대화냥줍 열기 '));
  try {
    const cwd = join(root, '한국어 작업 공간');
    const codexDir = join(root, '.codex');
    const claudeProject = join(root, '.claude', 'projects', encodeProj(cwd));
    const fakeBin = join(root, '가짜 명령');
    const keeper = join(root, 'keeper');
    for (const dir of [cwd, codexDir, claudeProject, fakeBin, keeper]) mkdirSync(dir, { recursive: true });

    const app = join(fakeBin, '가짜 Herdr');
    const codex = join(fakeBin, '가짜 Codex');
    const claude = join(fakeBin, '가짜 Claude');
    const capture = join(root, '열기 요청.jsonl');
    const preload = join(root, '가짜 프로세스.cjs');
    writeFileSync(preload, `
const childProcess = require('node:child_process');
const { syncBuiltinESMExports } = require('node:module');
const original = childProcess.execFile;
childProcess.execFile = function(file, ...args) {
  if (file !== '/bin/ps') return original.call(this, file, ...args);
  const callback = args.at(-1);
  queueMicrotask(() => callback(null, process.env.FAKE_PS_OUTPUT, ''));
};
syncBuiltinESMExports();
`);
    writeFileSync(join(fakeBin, 'hc'), `#!/usr/bin/env node
const args = JSON.stringify(process.argv.slice(2));
const live = process.env.FAKE_HC_LIVE === '1';
if (args === '["ls","--json"]') {
  const terminals = live ? [{ state: 'live', address: 't2', agent: 'codex', where: '테스트 공간' }] : [];
  console.log(JSON.stringify({ terminals }));
  process.exit(process.env.FAKE_HC_FAIL === '1' ? 1 : 0);
}
if (live && args === '["get","t2","--json"]') {
  console.log(JSON.stringify({ pid: 10, foreground: { pid: 11 }, title: '관계없는 제목' }));
  process.exit(0);
}
process.exit(2);
`, { mode: 0o755 });
    writeFileSync(app, `#!/usr/bin/env node
const { appendFileSync } = require('node:fs');
appendFileSync(process.env.FAKE_APP_CAPTURE, JSON.stringify(process.argv.slice(2)) + '\\n');
Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
console.log(JSON.stringify({ terminal: 't1', tab: 'x' }));
`, { mode: 0o755 });
    writeFileSync(codex, '#!/bin/sh\nexit 99\n', { mode: 0o755 });
    writeFileSync(claude, '#!/bin/sh\nexit 99\n', { mode: 0o755 });

    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const missingCwdId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const failedHcId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    const claudeId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    writeFileSync(join(claudeProject, claudeId + '.jsonl'), JSON.stringify({
      cwd, type: 'user', message: { content: '클로드 재개 확인' },
    }) + '\n');
    const db = new DatabaseSync(join(codexDir, 'state_5.sqlite'));
    try {
      db.exec('CREATE TABLE threads (id TEXT, updated_at INTEGER, title TEXT, cwd TEXT)');
      const insert = db.prepare('INSERT INTO threads VALUES (?, ?, ?, ?)');
      const old = Math.floor(Date.now() / 1000) - 600;
      insert.run(id, old, '동시 열기 확인', cwd);
      insert.run(missingCwdId, old, '없는 작업 폴더 확인', join(root, '없는 폴더'));
      insert.run(failedHcId, old, 'Herdr 조회 실패 확인', cwd);
    } finally {
      db.close();
    }

    const env = {
      ...process.env,
      HOME: root,
      USERPROFILE: root,
      APPDATA: join(root, 'appdata'),
      LOCALAPPDATA: join(root, 'localappdata'),
      PATH: [fakeBin, dirname(process.execPath), process.env.PATH || ''].join(delimiter),
      KEEPER_APP_EXE: app,
      KEEPER_CODEX_EXE: codex,
      KEEPER_CLAUDE_EXE: claude,
      SESSIONS_KEEPER_DIR: keeper,
      FAKE_APP_CAPTURE: capture,
      FAKE_PS_OUTPUT: processTable([10, 1, 'zsh', '-zsh']),
    };
    for (const name of ['CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'SESSIONS_NO_CODEX', 'SESSIONS_NO_HERDR', 'SESS_RESUME_TEMPLATE', 'FAKE_HC_FAIL', 'FAKE_HC_LIVE', 'NODE_OPTIONS']) delete env[name];

    const run = (sid, overrides = {}) => new Promise((resolve, reject) => {
      const child = spawn(process.execPath, ['--require', preload, cli, 'open', sid, '--json'], {
        env: { ...env, ...overrides }, timeout: 30000,
      });
      let stdout = '', stderr = '';
      child.stdout.setEncoding('utf8').on('data', (chunk) => { stdout += chunk; });
      child.stderr.setEncoding('utf8').on('data', (chunk) => { stderr += chunk; });
      child.on('error', reject);
      child.on('close', (status) => {
        try { resolve({ status, ...JSON.parse(stdout) }); }
        catch (error) { reject(new Error(`open ${sid} (${status}): ${stdout}${stderr}`, { cause: error })); }
      });
    });
    const requests = () => readFileSync(capture, 'utf8').trim().split('\n').map((line) => JSON.parse(line));

    const results = await Promise.all([run(id), run(id)]);
    assert.equal(results.filter(({ status, ok }) => status === 0 && ok).length, 1, JSON.stringify(results));
    assert.equal(results.filter(({ status, ok }) => status === 1 && ok === false).length, 1, JSON.stringify(results));
    assert.equal(results.find(({ ok }) => !ok).code, 'PENDING');
    const opened = results.find(({ ok }) => ok);
    assert.equal(opened.terminal, 't1');
    assert.equal(opened.tab, 'x');

    const captured = requests();
    assert.equal(captured.length, 1);
    const [request] = captured;
    assert.deepEqual(request.slice(0, 2), ['do', 'terminal.open']);
    const spec = JSON.parse(request[2]);
    assert.deepEqual(spec.argv, [codex, 'resume', id]);
    assert.equal(spec.folder, cwd);
    assert.equal(spec.place, 'tab');

    const missing = await run(missingCwdId);
    assert.equal(missing.status, 1, JSON.stringify(missing));
    assert.equal(missing.ok, false, JSON.stringify(missing));
    assert.equal(missing.code, 'MISSING_FOLDER');
    assert.equal(requests().length, 1, '작업 폴더가 없으면 Herdr 탭을 열지 않는다');
    const unavailable = await run(failedHcId, { FAKE_HC_FAIL: '1' });
    assert.equal(unavailable.status, 1, JSON.stringify(unavailable));
    assert.equal(unavailable.ok, false, JSON.stringify(unavailable));
    assert.equal(unavailable.code, 'LOOKUP_FAILED');
    assert.equal(requests().length, 1, 'Herdr 조회가 실패하면 탭을 열지 않는다');

    const claudeOpened = await run(claudeId);
    assert.equal(claudeOpened.status, 0, JSON.stringify(claudeOpened));
    assert.equal(claudeOpened.code, 'OPENED');
    const allRequests = requests();
    assert.equal(allRequests.length, 2);
    const claudeRequest = allRequests[1];
    assert.deepEqual(claudeRequest.slice(0, 2), ['do', 'terminal.open']);
    const claudeSpec = JSON.parse(claudeRequest[2]);
    assert.deepEqual(claudeSpec.argv, [claude, '--resume', claudeId]);
    assert.equal(claudeSpec.folder, cwd);

    const focused = await run(id, {
      FAKE_HC_LIVE: '1',
      FAKE_PS_OUTPUT: processTable([10, 1, 'zsh', '-zsh'], [11, 10, 'codex', 'codex resume ' + id]),
    });
    assert.equal(focused.status, 0, JSON.stringify(focused));
    assert.equal(focused.code, 'FOCUSED');
    assert.deepEqual(requests()[2], ['do', 'agent.focus', JSON.stringify({ terminal: 't2' })]);
    assert.equal(requests().length, 3);

    const external = await run(failedHcId, {
      FAKE_PS_OUTPUT: processTable([10, 1, 'zsh', '-zsh'], [12, 1, 'codex', 'codex resume --last']),
    });
    assert.equal(external.status, 1, JSON.stringify(external));
    assert.equal(external.code, 'UNCONFIRMED');
    assert.equal(requests().length, 3, '외부 Codex 세션을 식별할 수 없으면 탭을 열지 않는다');

    console.log('PASS  macOS 재개 인자·작업 폴더·중복 열기·확정 탭 이동·미확정 세션 거부');
    console.log('합계: PASS 1 / FAIL 0');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function processTable(...rows) {
  const header = '  PID  PPID EXECUTABLE       COMMAND';
  return [header, ...rows.map(([pid, ppid, name, command]) =>
    `${String(pid).padStart(5)} ${String(ppid).padStart(5)} ${name.padEnd(16)} ${command}`)].join('\n');
}
