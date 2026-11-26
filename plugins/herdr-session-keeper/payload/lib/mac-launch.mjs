// A short, atomic reservation covers concurrent CLI invocations while the AI starts.
import { constants, accessSync, mkdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, isAbsolute, delimiter } from 'node:path';
import { createRequire } from 'node:module';
import { openTab } from './herdr.mjs';
import { UUID } from './common.mjs';

function executable(configured, name) {
  const paths = configured ? [configured] : (process.env.PATH || '').split(delimiter).filter(isAbsolute).map(dir => join(dir, name));
  for (const path of paths) {
    try {
      accessSync(path, constants.X_OK);
      if (isAbsolute(path) && statSync(path).isFile()) return path;
    } catch { /* Try the next install location. */ }
  }
}

function reserve(sid) {
  const dir = process.env.SESSIONS_KEEPER_DIR || join(homedir(), 'Library', 'Application Support', '대화냥줍');
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const { DatabaseSync } = createRequire(import.meta.url)('node:sqlite');
  const db = new DatabaseSync(join(dir, 'open-requests.sqlite'));
  try {
    db.exec('PRAGMA busy_timeout = 3000');
    db.exec('CREATE TABLE IF NOT EXISTS requests (sid TEXT PRIMARY KEY, expires INTEGER NOT NULL)');
    const now = Date.now();
    db.prepare('DELETE FROM requests WHERE expires <= ?').run(now);
    return db.prepare('INSERT OR IGNORE INTO requests VALUES (?, ?)').run(sid, now + 60000).changes > 0;
  } finally { db.close(); }
}

export function launchMacSession(row, cwd, name) {
  if (process.env.SESSIONS_NO_HERDR) return { ok: false, code: 'NO_APP', message: 'Herdr 연결이 꺼져 있습니다.' };
  if (!UUID.test(row.sid)) return { ok: false, code: 'INVALID_ID', message: '올바른 세션 ID가 필요합니다.' };
  let validFolder = false;
  try { validFolder = !!cwd && isAbsolute(cwd) && statSync(cwd).isDirectory(); } catch { /* Moved or inaccessible. */ }
  if (!validFolder)
    return { ok: false, code: 'MISSING_FOLDER', message: '원래 작업 폴더를 찾지 못했습니다.' };
  const codex = row.ai === 'Codex';
  const tool = codex ? 'codex' : 'claude';
  const path = executable(codex ? process.env.KEEPER_CODEX_EXE : process.env.KEEPER_CLAUDE_EXE, tool);
  if (!path) return { ok: false, code: 'NO_CLI', message: tool + ' 실행 파일을 찾지 못했습니다.' };
  try {
    if (!reserve(row.sid)) return { ok: false, code: 'PENDING', message: '최근에 이어 열기를 요청했습니다. 잠시 후 다시 확인하세요.' };
  } catch {
    return { ok: false, code: 'STATE_ERROR', message: '중복 실행 방지 기록을 저장하지 못했습니다.' };
  }
  const result = openTab({ argv: codex ? [path, '--no-daemon', 'resume', row.sid] : [path, '--resume', row.sid], folder: cwd, place: 'tab', name });
  if (!result.ok) return { ok: false, code: 'OPEN_FAILED', message: result.detail || 'Herdr에서 새 탭을 열지 못했습니다.' };
  return { ok: true, code: 'OPENED', message: 'Herdr에 이어 열기를 요청했습니다.', terminal: result.terminal || '', tab: result.tab || '', cwd };
}
