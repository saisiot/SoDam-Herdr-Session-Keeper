import { constants, accessSync, copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, rmdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { homedir, tmpdir } from "node:os";
import { dirname, delimiter, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const source = dirname(fileURLToPath(import.meta.url));
const repository = dirname(source);
const appHome = resolve(process.env.HERDR_APP_HOME || join(homedir(), ".config", "herdr-app"));
const mods = join(appHome, "mods");
const name = "sodam-conversation-picker";
const destination = join(mods, name);
const owner = ".sodam-conversation-picker";
const modSources = ["mod.json", "main.js", "icon.png"];
const modFiles = [...modSources, "model.js", "config.js", "cli/sessions.mjs", "cli/kit.env"];
const isPayloadLibrary = (path) => /^cli\/lib\/[a-z][a-z0-9-]*\.mjs$/.test(path);

function findExecutable(explicit, fallbacks) {
  for (const entry of explicit ? [explicit] : fallbacks) {
    const path = resolve(entry);
    try {
      if (lstatSync(path).isDirectory()) continue;
      accessSync(path, constants.X_OK);
      return path;
    } catch {
      // Try the next known location.
    }
  }
  return "";
}

const paths = (command) => (process.env.PATH || "").split(delimiter).filter(isAbsolute).map((dir) => join(dir, command));

function checkDirectory(path) {
  if (existsSync(path) && !lstatSync(path).isDirectory()) throw new Error(`디렉터리를 열 수 없습니다. ${path}`);
}

function installedFiles() {
  checkDirectory(destination);
  if (!existsSync(destination)) return [];
  const marker = join(destination, owner);
  if (!existsSync(marker) || !lstatSync(marker).isFile()) throw new Error(`다른 모드와 경로가 겹칩니다. ${destination}`);
  const files = JSON.parse(readFileSync(marker, "utf8"));
  if (!Array.isArray(files) || files.some((path) => !modFiles.includes(path) && !isPayloadLibrary(path))) throw new Error("기존 설치 정보를 읽을 수 없습니다.");
  checkDirectory(join(destination, "cli"));
  checkDirectory(join(destination, "cli/lib"));
  return files;
}

function remove() {
  const files = installedFiles();
  if (!existsSync(destination)) {
    console.log("대화냥줍 모드가 설치되어 있지 않습니다.");
    return;
  }
  for (const path of [...files, "gpui-kit.d.ts", "jsconfig.json", owner]) rmSync(join(destination, path), { force: true });
  for (const path of ["cli/lib", "cli", ""]) {
    try {
      rmdirSync(join(destination, path));
    } catch (error) {
      if (!["ENOTEMPTY", "ENOENT"].includes(error.code)) throw error;
    }
  }
  console.log("대화냥줍 모드를 제거했습니다.");
}

function install() {
  const previous = installedFiles();
  const app = findExecutable(process.env.KEEPER_APP_EXE, [
    ...paths("herdr-app"),
    join(homedir(), "Applications/Herdr.app/Contents/MacOS/Herdr"),
    "/Applications/Herdr.app/Contents/MacOS/Herdr",
  ]);
  const hc = findExecutable(process.env.KEEPER_HC_EXE, [...paths("hc"), join(homedir(), ".local/bin/hc")]);
  const claude = findExecutable(process.env.KEEPER_CLAUDE_EXE, [...paths("claude"), join(homedir(), ".local/bin/claude")]);
  const codex = findExecutable(process.env.KEEPER_CODEX_EXE, [...paths("codex"), "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]);
  if (!app || !hc) throw new Error("Herdr 앱과 hc CLI를 설치한 뒤 다시 실행하세요.");
  const [nodeMajor, nodeMinor] = process.versions.node.split(".").map(Number);
  if (nodeMajor < 22 || (nodeMajor === 22 && nodeMinor < 13)) {
    throw new Error("Node.js 22.13 이상이 필요합니다.");
  }

  const environment = {
    NODE_DIR: dirname(process.execPath),
    HC_DIR: dirname(hc),
    KEEPER_HC_EXE: hc,
    APP_EXE: app,
    APP_HOME: appHome,
    ...(claude && { CLAUDE_DIR: dirname(claude), KEEPER_CLAUDE_EXE: claude }),
    ...(codex && { CODEX_DIR: dirname(codex), KEEPER_CODEX_EXE: codex }),
  };
  if (Object.values(environment).some((path) => /[\r\n]/.test(path) || path !== path.trim())) {
    throw new Error("줄바꿈이나 끝 공백이 있는 경로에서는 설치할 수 없습니다.");
  }

  const libraryFiles = readdirSync(join(repository, "lib")).map((name) => `cli/lib/${name}`).filter(isPayloadLibrary);
  mkdirSync(mods, { recursive: true });
  const staged = mkdtempSync(join(appHome, ".sodam-install-"));
  const checkHome = mkdtempSync(join(tmpdir(), "sodam-herdr-check-"));
  try {
    mkdirSync(join(staged, "cli", "lib"), { recursive: true });
    for (const path of modSources) copyFileSync(join(source, "mod", path), join(staged, path));
    copyFileSync(join(repository, "herdr-mod/session-keeper/model.js"), join(staged, "model.js"));
    copyFileSync(join(repository, "sessions.mjs"), join(staged, "cli/sessions.mjs"));
    for (const path of libraryFiles) copyFileSync(join(repository, path.slice(4)), join(staged, path));

    writeFileSync(join(staged, "config.js"), [
      `export const NODE = ${JSON.stringify(process.execPath)};`,
      `export const TOOL = ${JSON.stringify(join(destination, "cli/sessions.mjs"))};`,
      "",
    ].join("\n"));
    writeFileSync(join(staged, "cli/kit.env"), Object.entries(environment).map(([key, path]) => `${key}=${path}\n`).join(""));
    const files = [...libraryFiles, ...modFiles];
    writeFileSync(join(staged, owner), JSON.stringify(files));

    const check = spawnSync(app, ["check", staged], {
      encoding: "utf8",
      timeout: 20000,
      env: { ...process.env, HERDR_APP_HOME: checkHome },
    });
    if (check.status !== 0) throw new Error(check.error?.message || [check.stdout, check.stderr].filter(Boolean).join("\n").trim() || "Herdr 모드 검사 실패");
    if (!existsSync(destination)) {
      renameSync(staged, destination);
    } else {
      for (const path of files) {
        if (!previous.includes(path) && existsSync(join(destination, path))) throw new Error(`기존 파일과 경로가 겹칩니다. ${path}`);
      }
      mkdirSync(join(destination, "cli", "lib"), { recursive: true });
      for (const path of [...files, owner]) renameSync(join(staged, path), join(destination, path));
      for (const path of previous) if (!files.includes(path)) rmSync(join(destination, path), { force: true });
    }
    console.log(`설치 및 검사 완료. ${destination}`);
    console.log(`Herdr 명령 팔레트에서 대화냥줍을 열거나 다음 명령을 실행하세요.\nmod.open ${name}`);
    if (!claude || !codex) console.log(`${[!claude && "Claude", !codex && "Codex"].filter(Boolean).join(", ")} CLI를 찾지 못했습니다.`);
  } finally {
    rmSync(staged, { recursive: true, force: true });
    rmSync(checkHome, { recursive: true, force: true });
  }
}

try {
  const args = process.argv.slice(2);
  if (args.length === 0) install();
  else if (args.length === 1 && args[0] === "--uninstall") remove();
  else throw new Error("사용법: macos/install.sh [--uninstall]");
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
