import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";

const installer = fileURLToPath(new URL("./install.mjs", import.meta.url));
const name = "sodam-conversation-picker";

test("installer checks a staged copy, runs the installed CLI, and preserves unrelated files", (t) => {
  const root = mkdtempSync(join(tmpdir(), "conversation-picker-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const appHome = join(root, "한글 Herdr");
  const destination = join(appHome, "mods", name);
  const unrelated = join(appHome, "mods", "another", "main.js");
  const keys = join(appHome, "keys.json");
  const checker = join(root, "Herdr test checker");
  const codexHome = join(root, "codex");
  const claudeHome = join(root, "claude");
  const fakeHome = join(root, "fake home");
  const project = join(root, "한글 프로젝트");
  const claudeProject = join(claudeHome, "projects", project.replace(/[^a-zA-Z0-9]/g, "-"));
  const claudeId = "00000000-0000-4000-8000-000000000001";
  const codexId = "00000000-0000-4000-8000-000000000002";
  for (const dir of [fakeHome, project, claudeProject, codexHome]) mkdirSync(dir, { recursive: true });
  writeFileSync(join(claudeProject, claudeId + ".jsonl"), JSON.stringify({
    type: "user",
    cwd: project,
    message: { content: "Claude 합성 대화" },
  }) + "\n");
  const db = new DatabaseSync(join(codexHome, "state_1.sqlite"));
  db.exec("CREATE TABLE threads (id TEXT, title TEXT, cwd TEXT, updated_at INTEGER)");
  db.prepare("INSERT INTO threads VALUES (?, ?, ?, ?)").run(codexId, "Codex 합성 대화", project, Math.floor(Date.now() / 1000));
  db.close();
  const checkLog = join(root, "checked");
  mkdirSync(join(appHome, "mods", "another"), { recursive: true });
  writeFileSync(unrelated, "other mod");
  writeFileSync(keys, '{"global":{"ctrl-shift-r":"app.help"}}\n');
  writeFileSync(checker, `#!/bin/sh
test "$1" = check || exit 1
test "$HERDR_APP_HOME" != "$TEST_APP_HOME" || exit 2
test -f "$2/main.js" || exit 3
test -f "$2/cli/lib/mac-launch.mjs" || exit 4
printf '%s\\n' "$HERDR_APP_HOME" >> "$CHECK_LOG"
`, { mode: 0o700 });

  const env = {
    ...process.env,
    HOME: fakeHome,
    USERPROFILE: fakeHome,
    APPDATA: fakeHome,
    LOCALAPPDATA: fakeHome,
    HERDR_APP_HOME: appHome,
    TEST_APP_HOME: appHome,
    CHECK_LOG: checkLog,
    KEEPER_APP_EXE: checker,
    KEEPER_HC_EXE: "/usr/bin/true",
    KEEPER_CLAUDE_EXE: "/usr/bin/true",
    KEEPER_CODEX_EXE: "/usr/bin/true",
    SESSIONS_NO_HERDR: "1",
    CLAUDE_CONFIG_DIR: claudeHome,
    CODEX_HOME: codexHome,
    SESSIONS_KEEPER_DIR: join(root, "keeper"),
  };
  delete env.SESSIONS_NO_CODEX;
  const install = (...args) => execFileSync(process.execPath, [installer, ...args], { env, encoding: "utf8" });
  install();
  assert.match(readFileSync(join(destination, "cli", "kit.env"), "utf8"), /KEEPER_HC_EXE=\/usr\/bin\/true/);
  const output = execFileSync(process.execPath, [join(destination, "cli", "sessions.mjs"), "json", "--all"], { env, encoding: "utf8" });
  const rows = JSON.parse(output);
  assert.equal(rows.length, 2);
  assert.ok(rows.some((row) => row.sid === claudeId && row.cwd === project && row.title === "Claude 합성 대화"));
  assert.ok(rows.some((row) => row.sid === codexId && row.cwd === project && row.title === "Codex 합성 대화"));

  const note = join(destination, "user-note.txt");
  writeFileSync(note, "keep");
  install();
  assert.equal(readFileSync(checkLog, "utf8").trim().split("\n").length, 2);
  install("--uninstall");
  assert.equal(existsSync(join(destination, "main.js")), false);
  assert.equal(readFileSync(note, "utf8"), "keep");
  assert.equal(readFileSync(unrelated, "utf8"), "other mod");
  assert.equal(readFileSync(keys, "utf8"), '{"global":{"ctrl-shift-r":"app.help"}}\n');
  const conflict = spawnSync(process.execPath, [installer], { env, encoding: "utf8" });
  assert.notEqual(conflict.status, 0);
  assert.match(conflict.stderr, /다른 모드와 경로가 겹칩니다/);
});
