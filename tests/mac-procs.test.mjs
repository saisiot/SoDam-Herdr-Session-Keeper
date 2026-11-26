import assert from 'node:assert/strict';
import { parseMacPs, processSnapshot, codexResumeSnapshot, macUnidentifiedCodex } from '../lib/procs.mjs';

const id = '58E43266-1234-4AB0-ABCD-E552222ABBBB';
const header = '  PID  PPID EXECUTABLE       COMMAND';
const row = (pid, ppid, name, command) =>
  `${String(pid).padStart(5)} ${String(ppid).padStart(5)} ${name.padEnd(16)} ${command}`;
const output = [
  header,
  row(10, 1, 'zsh', '-zsh'),
  row(11, 10, 'codex', `/Users/example/Application Support/Codex/bin/codex resume ${id} --full-auto`),
  row(12, 10, 'node', `/opt/homebrew/bin/node /Users/example/Application Support/npm/bin/codex.js resume ${id}`),
  row(13, 12, 'codex-aarch64-ap', `/opt/homebrew/bin/codex-aarch64-apple-darwin resume ${id}`),
  row(14, 1, 'Codex (Aperitif)', `/Applications/ChatGPT.app/Codex (Aperitif) codex resume ${id}`),
  row(15, 10, 'zsh', `zsh -c codex resume ${id}`),
  row(16, 10, 'node', `node /opt/helper.mjs codex resume ${id}`),
  row(17, 10, 'codex', `codex exec codex resume ${id}`),
  row(18, 10, 'codex', `codex resume ${id}extra`),
  row(19, 10, 'node', `node --eval codex resume ${id}`),
  row(20, 10, 'node', `node /path/helper.js another/codex.js resume ${id}`),
  row(21, 10, 'node', `node bin/codex.js resume ${id}`),
  row(22, 10, 'codex-code-mode-', `codex-code-mode-host codex resume ${id}`),
  row(23, 10, 'node', `node /opt/helper.mjs /opt/bin/codex resume ${id}`),
  'invalid process record',
].join('\n');

const { processes, resume, unidentifiedCodex } = parseMacPs(output);
assert.equal(processes.size, 14);
assert.deepEqual(processes.get(11), { ppid: 10, name: 'codex' });
assert.deepEqual(processes.get(14), { ppid: 1, name: 'Codex (Aperitif)' });
assert.deepEqual([...resume], [11, 12, 13, 21].map((pid) => [pid, id.toLowerCase()]));
assert.equal(unidentifiedCodex, true);
assert.deepEqual(parseMacPs('unexpected output'), {
  processes: new Map(), resume: new Map(), unidentifiedCodex: false,
});

const processList = (...commands) => [
  header, ...commands.map(([name, command], i) => row(30 + i, 10, name, command)),
].join('\n');
const background = parseMacPs(processList(
  ['codex', '/Applications/ChatGPT.app/Contents/MacOS/codex -c features.code_mode_host=true app-server --listen stdio://'],
  ['codex', 'codex exec app-server'],
  ['node', 'node /opt/npm/codex.js mcp-server'],
  ['node', 'node /opt/helper.mjs /bin/codex resume'],
  ['Codex (Aperitif)', 'Codex (Aperitif)'],
  ['codex', `codex --config=foo=bar --full-auto resume ${id}`],
));
assert.equal(background.unidentifiedCodex, false);
assert.deepEqual([...background.resume], [[35, id.toLowerCase()]]);
for (const command of ['codex', 'codex resume --last', 'codex fork', 'codex prompt mentioning app-server', '(codex)']) {
  assert.equal(parseMacPs(processList(['codex', command])).unidentifiedCodex, true, command);
}
assert.equal(parseMacPs(processList(['node', 'node /opt/npm/codex.js'])).unidentifiedCodex, true);

if (process.platform === 'darwin' && !process.env.SESSIONS_NO_HERDR) {
  const [live, liveResume, unidentified] = await Promise.all([
    processSnapshot(), codexResumeSnapshot(), macUnidentifiedCodex(),
  ]);
  assert.deepEqual(live.get(process.pid), { ppid: process.ppid, name: 'node' });
  assert.equal(liveResume.has(process.pid), false);
  assert.equal(typeof unidentified, 'boolean');
}

const previous = process.env.SESSIONS_NO_HERDR;
try {
  process.env.SESSIONS_NO_HERDR = '1';
  assert.equal((await processSnapshot()).size, 0);
  assert.equal((await codexResumeSnapshot()).size, 0);
  assert.equal(await macUnidentifiedCodex(), false);
} finally {
  if (previous === undefined) delete process.env.SESSIONS_NO_HERDR;
  else process.env.SESSIONS_NO_HERDR = previous;
}

console.log('합계: PASS 6 / FAIL 0');
