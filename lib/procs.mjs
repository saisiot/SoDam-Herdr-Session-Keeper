// 프로세스 계보(누가 누구의 부모인지). 실행 중인 세션이 어느 Herdr 창의 셸 아래에서 돌고 있는지 정확히 알아내는 데 쓴다.
// macOS에서는 /bin/ps, Windows에서는 Toolhelp32(실패 시 WMI)를 쓴다.
import { execFile } from 'node:child_process';

const TOOLHELP_CS = `using System; using System.Runtime.InteropServices; using System.Text;
public static class PS {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct PE { public uint size, usage, pid; public IntPtr heap; public uint module, threads, ppid; public int pri; public uint flags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string exe; }
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint f, uint p);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool Process32FirstW(IntPtr s, ref PE e);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool Process32NextW(IntPtr s, ref PE e);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static string Dump() { var sb = new StringBuilder(); IntPtr s = CreateToolhelp32Snapshot(2, 0); var e = new PE(); e.size = (uint)Marshal.SizeOf(typeof(PE));
    if (Process32FirstW(s, ref e)) { do { sb.Append(e.pid).Append('|').Append(e.ppid).Append('|').Append(e.exe).Append('\\n'); } while (Process32NextW(s, ref e)); } CloseHandle(s); return sb.ToString(); }
}`;
const TOOLHELP_SCRIPT = `Add-Type -TypeDefinition @'\n${TOOLHELP_CS}\n'@\n[Console]::Out.Write([PS]::Dump())`;
const WMI_SCRIPT = "Get-CimInstance Win32_Process | ForEach-Object { '{0}|{1}|{2}' -f $_.ProcessId,$_.ParentProcessId,$_.Name }";

export const SCRIPTS = { toolhelp: TOOLHELP_SCRIPT, wmi: WMI_SCRIPT };   // 시험·성능 비교용

export function runScript(script, timeout) {
  return new Promise((resolve) => {
    execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { timeout, windowsHide: true, maxBuffer: 1 << 25, encoding: 'utf8' }, (err, stdout) => {
      resolve(parseDump(err && !stdout ? '' : stdout));
    });
  });
}

// "pid|ppid|이름" 줄들 -> Map<pid, {ppid, name}>
export function parseDump(text) {
  const map = new Map();
  for (const line of String(text || '').split(/\r?\n/)) {
    const m = /^(\d+)\|(\d+)\|(.*)$/.exec(line.trim());
    if (m) map.set(Number(m[1]), { ppid: Number(m[2]), name: m[3] });
  }
  return map;
}

// ---- Codex: `codex resume <ID>` 로 켠 창은 프로세스 명령줄에 대화 ID 가 그대로 있다(창 제목은 "PC" 등이라 믿을 수 없다).
// Toolhelp 는 명령줄을 주지 않으므로 node.exe / codex.exe 만 WMI 로 따로 읽는다(전체 목록보다 훨씬 작다).
const CODEX_CMD_SCRIPT = "Get-CimInstance Win32_Process -Filter \"Name='node.exe' OR Name='codex.exe'\" | ForEach-Object { '{0}|{1}' -f $_.ProcessId,$_.CommandLine }";
const RESUME_RE = /(?:^|[\s"\\/])codex(?:\.js|\.exe)?"?\s+resume\s+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?=\s|"|$)/i;

// "pid|명령줄" 줄들 -> Map<pid, 대화ID>  (resume <UUID> 가 없는 프로세스는 빠진다)
export function parseResumeDump(text) {
  const map = new Map();
  for (const line of String(text || '').split(/\r?\n/)) {
    const m = /^(\d+)\|(.*)$/.exec(line.trim());
    if (!m) continue;
    const r = RESUME_RE.exec(m[2]);
    if (r) map.set(Number(m[1]), r[1].toLowerCase());
  }
  return map;
}

// ucomm은 운영체제가 기록한 실행 파일명이다. args에는 다른 CLI를 언급하는
// 스크립트·셸·프롬프트도 들어갈 수 있으므로 두 열을 함께 확인한다.
const MAC_PS_COLUMNS = 'pid=PID,ppid=PPID,ucomm=EXECUTABLE,args=COMMAND';
const MAC_CODEX_BINARIES = ['codex', 'codex-aarch64-apple-darwin', 'codex-x86_64-apple-darwin'];
const MAC_CODEX_UUID = /^resume\s+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?=\s|$)/i;
const MAC_CODEX_VALUE_OPTION = /^(?:-c|-C|-i|-m|-p|-a|-s|--config|--cd|--image|--model|--profile|--ask-for-approval|--sandbox|--add-dir|--enable|--disable)(?:=|\s+)\S+(?:\s+|$)/;
const MAC_CODEX_FLAG = /^(?:--full-auto|--dangerously-bypass-approvals-and-sandbox|--no-alt-screen|--oss|--remote-managed)(?:\s+|$)/;
const MAC_CODEX_NONINTERACTIVE = /^(?:app-server|exec-server|mcp-server|exec|e|review|login|logout|mcp|completion|sandbox|apply|cloud|features|debug|help|--help|-h|--version|-V)(?=\s|$)/;

function macCodexMode(args) {
  // 데스크톱 app-server 등은 전역 옵션 뒤에 하위 명령이 나올 수 있다.
  // 인식할 수 있는 옵션만 건너뛰어 프롬프트 속 단어를 하위 명령으로 해석하지 않는다.
  for (let option; (option = MAC_CODEX_VALUE_OPTION.exec(args) ?? MAC_CODEX_FLAG.exec(args));) {
    args = args.slice(option[0].length);
  }
  return args;
}

// ps가 공간을 포함한 argv를 따옴표 없이 표시하므로 절대 경로의 내부 공백을
// 허용한다. 별도 경로·옵션으로 보이는 경계에서는 검색을 멈춘다.
function macArgsAfterExecutable(command, executable) {
  const absolute = '/(?:(?!\\s[/.-]|\\.(?:[cm]?js)\\s).)*?/';
  const relative = '(?:[^\\s/]+/)+';
  const pattern = new RegExp(`^(?:${absolute}|/|${relative})?(?:${executable})(?=\\s|$)\\s*`);
  const match = pattern.exec(command);
  return match ? command.slice(match[0].length) : null;
}

export function parseMacPs(text) {
  const processes = new Map();
  const resume = new Map();
  let unidentifiedCodex = false;
  const [header, ...rows] = String(text || '').split(/\r?\n/);
  const nameStart = header.indexOf('EXECUTABLE');
  const commandStart = header.indexOf('COMMAND');
  if (nameStart < 0 || commandStart <= nameStart) return { processes, resume, unidentifiedCodex };

  for (const row of rows) {
    const ids = /^\s*(\d+)\s+(\d+)\s*$/.exec(row.slice(0, nameStart));
    const name = row.slice(nameStart, commandStart).trim();
    if (!ids || !name) continue;
    const pid = Number(ids[1]);
    processes.set(pid, { ppid: Number(ids[2]), name });

    const command = row.slice(commandStart);
    let args = null;
    if (name === 'node') {
      const script = macArgsAfterExecutable(command, 'node');
      if (script !== null) args = macArgsAfterExecutable(script, 'codex(?:\\.js)?');
    } else {
      const executable = MAC_CODEX_BINARIES.find((binary) => binary === name || binary.slice(0, 16) === name);
      // 실행 파일명은 확인됐고 명령줄이 없거나 예상 형식과 다르면 보수적으로 판정한다.
      if (executable) args = macArgsAfterExecutable(command, executable) ?? macArgsAfterExecutable(command, 'codex') ?? '';
    }
    if (args === null) continue;
    const mode = macCodexMode(args);
    const id = MAC_CODEX_UUID.exec(mode);
    if (id) resume.set(pid, id[1].toLowerCase());
    else if (!MAC_CODEX_NONINTERACTIVE.test(mode)) unidentifiedCodex = true;
  }
  return { processes, resume, unidentifiedCodex };
}

let macPsPending;
function macSnapshot(timeout) {
  // sessions.mjs에서 계보와 resume ID를 함께 요청할 때 동일한 PID 표를 쓴다.
  if (macPsPending?.timeout === timeout) return macPsPending.promise;
  const snapshot = { timeout };
  snapshot.promise = new Promise((resolve) => {
    execFile('/bin/ps', ['-axww', '-o', MAC_PS_COLUMNS], {
      timeout, maxBuffer: 1 << 25, encoding: 'utf8',
    }, (err, stdout) => resolve(parseMacPs(err ? '' : stdout)));
  }).finally(() => {
    if (macPsPending === snapshot) macPsPending = undefined;
  });
  macPsPending = snapshot;
  return snapshot.promise;
}

// 기록 ID를 알 수 없는 대화형 Codex가 있으면 중복 실행을 피할 때 쓴다.
// 프로세스 조회 자체가 실패했는지는 processSnapshot의 빈 Map으로 확인한다.
export async function macUnidentifiedCodex(timeout = 8000) {
  if (process.platform !== 'darwin' || process.env.SESSIONS_NO_HERDR) return false;
  return (await macSnapshot(timeout)).unidentifiedCodex;
}

export function codexResumeSnapshot(timeout = 8000) {
  if (process.env.SESSIONS_NO_HERDR) return Promise.resolve(new Map());
  if (process.platform === 'darwin') return macSnapshot(timeout).then(({ resume }) => resume);
  return new Promise((resolve) => {
    execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', CODEX_CMD_SCRIPT], { timeout, windowsHide: true, maxBuffer: 1 << 25, encoding: 'utf8' }, (err, stdout) => resolve(parseResumeDump(err && !stdout ? '' : stdout)));
  });
}

// 반환: Promise<Map<pid, {ppid, name}>>  (모두 실패/시간 초과/SESSIONS_NO_HERDR 이면 빈 Map → 호출한 쪽이 보조 정보로 대신한다)
export async function processSnapshot(timeout = 8000) {
  if (process.env.SESSIONS_NO_HERDR) return new Map();
  if (process.platform === 'darwin') return (await macSnapshot(timeout)).processes;
  const fast = await runScript(TOOLHELP_SCRIPT, timeout);
  return fast.size > 0 ? fast : runScript(WMI_SCRIPT, timeout);
}
