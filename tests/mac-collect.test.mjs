import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { encodeProj } from '../lib/claude.mjs';
import { folderName } from '../lib/common.mjs';

const root = mkdtempSync(join(tmpdir(), '대화냥줍 테스트 '));
const cli = fileURLToPath(new URL('../sessions.mjs', import.meta.url));

try {
  assert.equal(folderName('/Users/dev/work/백슬래시\\폴더'), '백슬래시\\폴더');
  assert.equal(folderName('\\\\server\\share\\한국어 프로젝트'), '한국어 프로젝트');

  const claudeId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const codexId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const windowsId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const cwd = '/Users/dev/작업 공간/한국어 프로젝트';
  const windowsCwd = 'C:\\Users\\dev\\작업 공간\\이전 프로젝트';
  const claudeProject = join(root, '.claude', 'projects', encodeProj(cwd));
  const codexDir = join(root, '.codex');
  const keeperDir = join(root, 'keeper');
  for (const dir of [claudeProject, codexDir, keeperDir]) mkdirSync(dir, { recursive: true });

  const user = (content, metadata = {}) => ({ type: 'user', cwd, message: { content }, ...metadata });
  const records = [
    user('첫 질문'),
    user([{ type: 'text', text: '한국어로\n이어서 질문합니다' }]),
    user([{ type: 'tool_result', content: '도구 결과' }]),
    user('내부 메시지', { isMeta: true }),
  ];
  writeFileSync(join(claudeProject, claudeId + '.jsonl'), records.map((record) => JSON.stringify(record)).join('\n'));

  const db = new DatabaseSync(join(codexDir, 'state_5.sqlite'));
  try {
    db.exec('CREATE TABLE threads (id TEXT, updated_at INTEGER, title TEXT, cwd TEXT)');
    const insert = db.prepare('INSERT INTO threads VALUES (?, ?, ?, ?)');
    const seconds = Math.floor(Date.now() / 1000);
    insert.run(codexId, seconds - 60, '코덱스 대화', cwd);
    insert.run(windowsId, seconds - 120, '옮겨 온 대화', windowsCwd);
  } finally {
    db.close();
  }

  const env = {
    ...process.env,
    HOME: root,
    USERPROFILE: root,
    APPDATA: join(root, 'appdata'),
    LOCALAPPDATA: join(root, 'localappdata'),
    SESSIONS_KEEPER_DIR: keeperDir,
    SESSIONS_NO_HERDR: '1',
  };
  for (const key of ['CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'SESSIONS_NO_CODEX']) delete env[key];
  const run = (...args) => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8', env });
  const rows = JSON.parse(run('json', '--all'));
  assert.deepEqual(rows.map(({ sid, ai, cwd, folder, title }) => ({ sid, ai, cwd, folder, title })), [
    { sid: claudeId, ai: 'Claude Code', cwd, folder: '한국어 프로젝트', title: '한국어로 이어서 질문합니다' },
    { sid: codexId, ai: 'Codex', cwd, folder: '한국어 프로젝트', title: '코덱스 대화' },
    { sid: windowsId, ai: 'Codex', cwd: windowsCwd, folder: '이전 프로젝트', title: '옮겨 온 대화' },
  ]);
  assert.equal(rows[0].lastPrompt, '한국어로 이어서 질문합니다');
  assert.deepEqual(JSON.parse(run('json')).map(({ sid }) => sid), [codexId, windowsId]);
  assert.match(run('list', '--all'), /한국어 프로젝트\s+한국어로 이어서 질문합니다/);
  if (process.platform === 'darwin') {
    env.CODEX_HOME = join(root, 'missing-explicit-codex-home');
    assert.ok(JSON.parse(run('json', '--all')).every(row => row.ai !== 'Codex'));
  }
  console.log('PASS  Claude·Codex 합성 기록 수집과 경로·제목 표시');
  console.log('합계: PASS 1 / FAIL 0');
} finally {
  rmSync(root, { recursive: true, force: true });
}
