# Session Keeper (Herdr Session Keeper)

[한국어](README.md) | [English](README.en.md)

> **In one sentence**: A Windows tool that helps you pick up your AI conversations (Claude Code · Codex) again from a list after the computer shuts down or a Herdr window suddenly closes, and that also fixes the "Herdr never updates while it stays open" problem.

- Document version: kit 1.1.4 · written 2026-11-20 · last updated 2026-11-26
- This document is written so that **people who are new to computers and AI tools** can follow it. If you meet an unfamiliar word, read [2. Glossary](#2-glossary) first.
- The same content is in four files: `README.md` (Korean), `README.en.md` (English), `README.html` (Korean, for web browsers) and `README.en.html` (English, for web browsers). The HTML files are generated from the md files, so the content is always the same (see [12. Files and documents](#12-files-and-documents)).
- Note: the buttons and tabs of the Session Keeper window are in Korean. This document shows the Korean label in `backticks` next to the English meaning.

## Table of contents

1. [At a glance](#1-at-a-glance)
2. [Glossary](#2-glossary)
3. [Prerequisites and required software](#3-prerequisites-and-required-software)
4. [How to download](#4-how-to-download)
5. [How to install](#5-how-to-install)
6. [Quick start (10 minutes)](#6-quick-start-10-minutes)
7. [How to run (start and stop)](#7-how-to-run-start-and-stop)
8. [How to use](#8-how-to-use)
9. [How it works](#9-how-it-works)
10. [Command reference](#10-command-reference)
11. [Update summary](#11-update-summary)
12. [Files and documents](#12-files-and-documents)
13. [Workflow](#13-workflow)
14. [Architecture](#14-architecture)
15. [Security and data flow](#15-security-and-data-flow)
16. [Troubleshooting](#16-troubleshooting)
17. [FAQ](#17-faq)
18. [Legal, copyright, license and commercial use](#18-legal-copyright-license-and-commercial-use)
19. [Verification status and known limits](#19-verification-status-and-known-limits)
20. [Uninstall and rollback](#20-uninstall-and-rollback)

---

## 1. At a glance

### 1.1 What is it?

**Herdr** is a program that shows many terminals (black command windows) on one screen. Many people work inside a terminal while talking to an AI helper such as **Claude Code** or **Codex**.

Problems appear in these situations.

- After you turn the computer off and on, Herdr's windows **come back as empty terminals** and the AI conversations are over. (The conversation **records** stay as files, but you have to remember which window held which conversation.)
- If you keep Herdr open, **app updates are never applied.** (The cause and the fix are in [11. Update summary](#11-update-summary).)

**Session Keeper** solves both.

| Feature | In plain words | Automatic / manual |
|---|---|---|
| Remembering sessions | Every minute it notes "which window is holding which AI conversation". | Automatic |
| Restoring sessions | When you start Herdr again it reads the notes and types `claude --resume <conversation id>` or `codex resume <conversation id>` into that window so the conversation continues. | Automatic + manual (button) |
| Session Keeper window | A list window that opens with `Ctrl+Shift+R` inside Herdr. You look at it and choose what to restore. | Manual |
| Automatic app update | Applies a new Herdr version safely even while Herdr is open. If anything fails it puts everything back. It can be switched on and off. | Automatic (can be switched off) + manual |

### 1.2 What it does not do (to avoid misunderstanding)

- It **sends nothing to and receives nothing from the internet.** The code of this tool contains no internet access (see [chapter 15](#15-security-and-data-flow)).
- It does not restore the **content** of an AI conversation. It reopens the conversation **record file**. The single task the AI was working on when the computer went off is not continued.
- It does not bring back **monitors (Monitor) and schedules (ScheduleWakeup/Cron)** that you had started inside an AI session (it only tells you).
- It **does not turn the computer on by itself.** Booting alone starts nothing; it works only after you start Herdr.
- Windows you closed yourself are not restored (only windows lost by accident are targeted).

### 1.3 Who needs it?

People who use Herdr on Windows and run several jobs at once with Claude Code or Codex. If you only use one or two windows, the need is small.

---

## 2. Glossary

| Term | Meaning (plain explanation) |
|---|---|
| Terminal | A window where you type commands as text. In this document it is also called a "window". |
| Herdr | An app that arranges many terminals into spaces and tabs. The app is `herdr-app`; the helper that actually holds the terminals is `herdr-core` (command tool name `hc`). Even if you close the app window, `herdr-core` keeps the terminals alive. |
| Session (AI session) | One "conversation" with Claude Code or Codex. Each conversation has a number (ID). |
| Session ID / resume ID | The long number that identifies one conversation (for example `12345678-7110-…`). The conversation is reopened with this number. |
| Claude Code | Anthropic's AI coding helper (for terminals). The reopen command is `claude --resume <number>`. |
| Codex | OpenAI's AI coding helper (for terminals). The reopen command is `codex resume <number>`. |
| Session Keeper | The name of this project. It has two parts: ① the **Session Keeper window** (the list) inside Herdr and ② the **keeper program** (`session-keeper.ps1`) that runs in the background. |
| Mod (Herdr mod) | A small add-on folder plugged into Herdr. The Session Keeper window is one. |
| PowerShell | The command tool built into Windows. The main script (`.ps1`) of this tool runs on it. |
| Node.js | A program that runs JavaScript programs. The list/restore tool (`.mjs`) runs on it. It must be installed separately. |
| Task Scheduler | A Windows feature that runs programs at set times. Session Keeper registers one very short task there that asks every minute "is Herdr running?". |
| Marketplace / plugin | The way **Claude Code** installs add-ons (similar to an app store). This project is also provided in a Claude Code marketplace form. **Herdr has no such store.** |
| Path | The address of where a file is. Example: `C:\Users\myname\Documents`. |
| Administrator rights | A high permission that can change the whole computer. **This tool does not need it.** |
| Backup | A separate copy of the original made before changing it, so you can go back if something goes wrong. |
| Log | A file in which a program writes "what it did". |
| Toggle (▶) | In this document, a collapsible item that opens when clicked (visible in web browsers and on GitHub). |

---

## 3. Prerequisites and required software

### 3.1 Must have

| Needed | Why | How to check | If missing |
|---|---|---|---|
| Windows 10/11 (64-bit) | This tool is Windows only. | Development and tests were done only on **Windows 11 Home 10.0.26300**. Windows 10 is **unverified**. | Other operating systems are not supported. |
| Windows PowerShell 5.1 | Runs the main script | Included with Windows. Tested version 5.1 | Usually already there. |
| **Herdr** (app + core) | The thing this tool manages | Tested versions: herdr-app **0.1.14 → 0.1.15**, herdr-core/hc **0.1.20** | [4.1](#41-getting-herdr) |
| **Node.js 18 or newer** | Runs the list/restore tool | Type `node --version` in a terminal. Tested version v26.7.0 | [4.2](#42-getting-nodejs) |
| A writable folder | Install location (default `%LOCALAPPDATA%\HerdrSessionKeeper\app`) | Normally available | Give another location with `-InstallDir` |

### 3.2 Nice to have (optional)

| Optional program | Purpose |
|---|---|
| Claude Code | Needed to restore Claude conversations (restoring runs `claude --resume`). |
| Codex CLI | Needed to restore Codex conversations (`codex resume`). |
| Claude Code's plugin feature | Needed only for the "marketplace install" ([5.1](#51-method-1--install-through-the-claude-code-marketplace)). Without it you can still install with [5.2](#52-method-2--direct-install-double-click). |

### 3.3 Things worth deciding before installing

- Whether you want a different install location (with the default you need to do nothing).
- Whether to keep automatic updates on (default **on**). You can change it at any time later.
- Whether to allow the Task Scheduler entry (if not, the keeper does not start by itself when Herdr starts and must be started manually; option `-NoTask`).

### 3.4 Permissions

- **No administrator rights are needed.** It is installed only for the user account that is logged in.
- On company PCs where the Task Scheduler or script execution is restricted, a warning may appear during installation ([chapter 16](#16-troubleshooting)).

---

## 4. How to download

> **Current status (confirmed 2026-11-26)**: this kit is published in the GitHub repository <https://github.com/sodam-ai/SoDam-Herdr-Session-Keeper>. Get it with the methods in 4.3 below.

### 4.1 Getting Herdr

- Official Herdr repository: <https://github.com/herdrdev/herdr> — follow the instructions there to install.
- **Run it once** after installing (the settings folder `%USERPROFILE%\.config\herdr-app` must exist before Session Keeper can be installed).
- Check: you can open Herdr from the Start menu, and if installed in the usual place the file `%LOCALAPPDATA%\Programs\herdr-app\herdr-app.exe` exists.

### 4.2 Getting Node.js

1. Go to <https://nodejs.org> with a web browser.
2. Download the installer labelled **LTS**, run it and click "Next" as instructed until it finishes.
3. Open a **new terminal** and type `node --version`; check that a number `v18` or higher appears. (A terminal that was already open when you installed may not know about the new install, so you must open a **new** one.)
4. Note: it is said that PCs with `winget` (the Windows package manager) can install it that way too, but **the development PC has no winget, so this was not verified.**

### 4.3 Getting the Session Keeper kit

At the top level of the repository you will find `.claude-plugin` (the marketplace list) and `plugins\herdr-session-keeper` (the install kit). The installer is `plugins\herdr-session-keeper\install.cmd`.

1. On the repository page click the green **Code** button → **Download ZIP**, or, if you have git, run `git clone https://github.com/sodam-ai/SoDam-Herdr-Session-Keeper.git`.
2. Move the downloaded folder (or ZIP file) to the PC where you want to install (skip this if you downloaded on that PC).
3. On the target PC **extract it completely.** (Do not run it from inside the zip file. It cannot find the `payload` folder and stops with "installation files are missing".)
4. It was tested with Korean characters and spaces in the folder path, but an English-only path is recommended.

To rebuild the install kit yourself (for developers): in the project folder run `node build-kit.mjs` (see [10.7](#107-build-test-and-release-for-developers)).

---

## 5. How to install

There are two ways. **Method 2 (double-click) is the easiest.**

With either method you can first do a **check only**. The check changes nothing ([5.3](#53-check-before-installing-recommended)).

### 5.1 Method 1 — Install through the Claude Code marketplace

In Claude Code, type the two lines below one at a time. This repository is the marketplace itself.

```
/plugin marketplace add sodam-ai/SoDam-Herdr-Session-Keeper
/plugin install herdr-session-keeper@herdr-session-keeper-market
```

Then tell Claude **"install Session Keeper"** (in Korean: "세션키퍼 설치해줘") and the built-in skill goes through **check → explain what will change → confirm → install**.

> **Unverified**: these two commands have never been run to the end in a real Claude Code. Only the kit format check (`claude plugin validate`) passed. If there is a problem, use method 2.

### 5.2 Method 2 — Direct install (double-click)

1. **Double-click** `plugins\herdr-session-keeper\install.cmd` inside the kit folder.
2. A black window shows the progress (6 steps). When it ends it prints "설치가 끝났습니다." (installation finished).
3. Press any key to close the window.

To run it from a terminal:

```
powershell -NoProfile -ExecutionPolicy Bypass -File plugins\herdr-session-keeper\install.ps1
```

### 5.3 Check before installing (recommended)

```
powershell -NoProfile -ExecutionPolicy Bypass -File plugins\herdr-session-keeper\install.ps1 -Check
```

It only checks Node.js, Herdr, the settings folder and any existing install in another location, then stops. If it prints "점검 완료: 설치할 수 있는 환경입니다" (check complete: the environment can be installed), you are ready. If a line starting with "중단:" (stopped) appears, fix that reason and try again.

### 5.4 What the installer does (6 steps)

| Step | What it does |
|---|---|
| 1/6 Environment check | Finds Node.js 18+, the Herdr app, `hc` and the Herdr settings folder. Looks for a Session Keeper already installed in another location. |
| 2/6 Copy programs | Copies the program files to the install location (if there is an earlier install, one set is backed up and the latest 3 are kept) and writes the locations it found into `kit.env`. |
| 3/6 Herdr mod | Copies 3 screen files into `mods\session-keeper`, fills in the install location and the node path, then runs Herdr's official check (`herdr-app check`). |
| 4/6 Key binding | Adds one line for `Ctrl+Shift+R` to `keys.json` (original backed up as `keys.json.bak-before-session-keeper-kit`). If you pass `-NoKey` or there is no `keys.json`, this step is skipped, and if the result after the addition is not valid JSON, nothing is written to the file. If Herdr already uses the chosen key for another feature, only that line is skipped and the install carries on (you can still open it with `Ctrl+Shift+P`). |
| 5/6 Automatic-start task | Creates `HerdrSessionKeeper-Watchdog` in Task Scheduler (every minute; starts the keeper only while Herdr is running). |
| 6/6 Wrap-up | Writes the install record (`kit.install.json`) and, if the automatic-start task was registered and Herdr is running, calls the watchdog once immediately (it does not if you used `-NoTask` or the task registration failed). |

### 5.5 Install options

| Option | Meaning |
|---|---|
| `-Check` | Only check; change nothing |
| `-InstallDir <path>` | Program install location (default `%LOCALAPPDATA%\HerdrSessionKeeper\app`). It must be a **dedicated empty or new folder**; a folder that holds other files, or a drive root, is refused |
| `-HerdrHome <path>` | Herdr settings folder (default: environment variable `HERDR_APP_HOME`, otherwise `%USERPROFILE%\.config\herdr-app`) |
| `-HerdrApp <path>` | Location of `herdr-app.exe` (when automatic search fails) |
| `-TaskName <name>` | Task Scheduler task name (default `HerdrSessionKeeper-Watchdog`) |
| `-NoTask` | Do not register a Task Scheduler task |
| `-Key <key>` | Shortcut that opens the Session Keeper window (e.g. `ctrl-alt-r`). If omitted, an already-bound key is kept; if none, `Ctrl+Shift+R`. Stops before installing if the key is already used or not allowed ([5.8](#58-changing-the-shortcut-key)) |
| `-NoKey` | Do not bind a shortcut (use `Ctrl+Shift+P` → `mod.open session-keeper` instead) |
| `-Launcher` | (optional) Connect the Herdr shortcuts to the launcher ([8.5](#85-how-to-use-automatic-app-updates)) |
| `-RestartKeeper` | Stop a keeper that is already running and start it again with the new code (the watchdog restarts it within a minute) |
| `-Force` | Replace a Session Keeper installed in **another location** with this install |

### 5.6 If Session Keeper is already installed

If a Task Scheduler task or a mod pointing to another location exists, the installer **stops without overwriting** ("중단: … 덮어쓰지 않았습니다" = stopped, did not overwrite). To keep using the existing one, do nothing; to switch to this install add `-Force` (the existing task and mod are changed to point to this install). Installing again in the same location (an update) just works.

### 5.7 How it keeps working when the environment, folder or computer changes

It **finds the following on that PC** (no path is hard-coded in the code). Node and `hc` are found at install time and recorded in `kit.env`; the Herdr app and the Herdr settings folder are recorded only when they are not in the default place; the Claude and Codex conversation folders are searched every time the program runs.

| What is searched | Order |
|---|---|
| Node.js | PATH → usual places such as `%ProgramFiles%\nodejs` (only 18 or newer accepted) |
| Herdr app | `-HerdrApp` → environment variable `KEEPER_APP_EXE` → `%LOCALAPPDATA%\Programs\herdr-app` → PATH → installed-programs list (registry) |
| hc (herdr-core) | PATH → `herdr-core` next to the app → `%LOCALAPPDATA%\Programs\herdr-core` |
| Herdr settings folder | `-HerdrHome` → environment variable `HERDR_APP_HOME` → `%USERPROFILE%\.config\herdr-app` |
| Claude settings folder | environment variable `CLAUDE_CONFIG_DIR` → `%APPDATA%\claude-code` (if present) → `%USERPROFILE%\.claude` |
| Codex data | the folder in the environment variable `CODEX_HOME` if set. Otherwise **one place**: whichever of `%USERPROFILE%\.codex_runtime` and `%USERPROFILE%\.codex` has the more recently written state file |

To move the install, install again at the new place with `-InstallDir newplace`. If the files at the old place are already gone (you moved or deleted them), the installer says "it looks like you moved the folder" and re-links to the new place without `-Force`. If the old place is still there (you only copied), it is treated as a different install and stops, so remove the old place with `uninstall.ps1 -InstallDir oldplace` or add `-Force`. If the drive of the old place does not exist at all (an external disk may be unplugged), it stops to be safe. **If you move the folder and do not install again**, the recovery scheduled task that runs every minute points at the old place, fails, and the keeper does not start (measured).

### 5.8 Changing the shortcut key

The Session Keeper window opens with `Ctrl+Shift+R` by default. **Inside the window**, press the **[단축키]** (shortcut) button on the top row. Press a suggested key, type the key you want into the input box and press [적용] (apply) or Enter, or press [직접 누르기] (press it yourself) and then the key combination you want. A key that Herdr already uses for something else is refused; only a second confirmation press releases that function and overwrites it. From the command line, run `set-key.ps1` in the install folder (you can also choose it from the start with `-Key` at install time).

```
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\HerdrSessionKeeper\app\set-key.ps1" -Show
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\HerdrSessionKeeper\app\set-key.ps1" -Key ctrl-alt-r
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\HerdrSessionKeeper\app\set-key.ps1" -Reset
```

| Option | What it does |
|---|---|
| `-Show` | Shows the key that is bound now (changes nothing) |
| `-Key <key>` | Changes to that key. You may write `ctrl-alt-r` or `Ctrl+Alt+R` |
| `-Reset` | Goes back to the default key `Ctrl+Shift+R` |
| `-Replace` | If the key you want is already used by another function, removes only that one binding line and binds it to Session Keeper (the original is backed up) |
| `-Remove` | Removes only the shortcut binding (you can still open it with the palette `Ctrl+Shift+P` → `mod.open session-keeper`) |
| `-DryRun` | Only checks whether the key can be used; writes nothing |
| `-HerdrHome <path>` | Give the Herdr settings folder yourself (when run from the install folder it uses the location in `kit.env` automatically) |

Safety rules:

- If the key you want is **already used by Herdr for another function, nothing is changed by default** and you are told which function it clashes with. Only `-Replace` (in the window: press [덮어쓰기] (overwrite) twice) releases that one line.
- Allowed keys: modifiers (`ctrl`, `alt`, `shift`) plus English letters, digits, symbols (`,` `.` `/` `[` `]` etc.), `f1`-`f12`, arrow keys, `pageup`, `tab`, `space`, etc. `F1`-`F12` may be used alone. You may write `Ctrl+Alt+K` or `ctrl-alt-k`.
- The essential terminal keys (`Ctrl+C`, `Ctrl+D`, `Ctrl+Z`) and letter keys without Ctrl or Alt are refused. Other `Ctrl+letter` keys are allowed, but you are told that the key will stop working inside the terminal once bound.
- If the edited result would not be valid JSON, the file is left as it was and the script stops. The first time, the original is backed up as `keys.json.bak-before-session-keeper-kit`.
- Installing again (an update) **keeps the changed key** unless you pass `-Key`. Uninstalling (`uninstall.ps1`) also removes the changed key.
- If Herdr does not notice the change right away, close and reopen Herdr. (Whether Herdr re-reads `keys.json` instantly has not been verified.)

---

## 6. Quick start (10 minutes)

If this is your first time, just follow this order.

1. **Install Node.js** ([4.2](#42-getting-nodejs)) and check `node --version` in a new terminal.
2. **Install Herdr** and run it once ([4.1](#41-getting-herdr)).
3. **Move the kit folder and extract it** ([4.3](#43-getting-the-session-keeper-kit)).
4. **Double-click** `plugins\herdr-session-keeper\install.cmd` (to see the check first, see [5.3](#53-check-before-installing-recommended)).
5. Confirm "설치가 끝났습니다." (installation finished).
6. In the Herdr screen press **`Ctrl+Shift+R`** and check that the Session Keeper window opens. If it does not, press `Ctrl+Shift+P` and type `mod.open session-keeper`.
7. If Herdr is running, the keeper starts by itself **within about a minute** (check: the file `session-keeper.alive` appears in the install folder and is refreshed every minute).
8. Work with Claude Code / Codex as usual. From now on Session Keeper remembers every minute.
9. (Later) If the computer was turned off and on, or Herdr was closed, **start Herdr again.** Automatic restoring runs within a few minutes and a notification appears when it ends. For windows that did not come back, press **Restore** (`복구`) in the `Ctrl+Shift+R` list.

---

## 7. How to run (start and stop)

### 7.1 Normally you do not need to do anything

- Task Scheduler checks every minute "is Herdr running?".
  - Herdr off → does nothing.
  - Herdr on + keeper alive (`session-keeper.alive` refreshed within 3 minutes) → does nothing.
  - Herdr on + no keeper → starts the keeper (at most about a minute after Herdr starts).
- The keeper **ends by itself if Herdr stays off for more than 2 minutes.** **Booting the PC alone starts nothing.**

### 7.2 Starting it manually

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<install location>\session-keeper.ps1" -Mode Run
```

(`<install location>` default: `%LOCALAPPDATA%\HerdrSessionKeeper\app`. If the same keeper is already running, the newly started one quietly ends.)

### 7.3 Stopping it

| What you want | How |
|---|---|
| Only turn off the automatic start | `schtasks /Delete /TN "HerdrSessionKeeper-Watchdog" /F` (or the uninstall tool, [chapter 20](#20-uninstall-and-rollback)) |
| Stop the keeper that is running now | In Task Manager, end the `powershell.exe` that contains `session-keeper` |
| Only turn off automatic app updates | `session-keeper.ps1 -Mode Update -Auto Off` ([8.5](#85-how-to-use-automatic-app-updates)) |

---

## 8. How to use

### 8.1 Opening the Session Keeper window

Press `Ctrl+Shift+R` inside Herdr. Press it again or press `Esc` to close. If it does not open: `Ctrl+Shift+P` → `mod.open session-keeper`.

### 8.2 Screen layout

Top line: title · 3 tabs (with counts, as one segmented control) · search box · **Shortcut** (`단축키`) · **Refresh** (`새로고침`) / second line: tools of the tab / list / below the list: a result notice (done, needs attention and in-progress are told apart by color and text, and you can close it with the close button) / bottom: keyboard hints. When the list is empty, loading or failed to load, a notice card gives the reason and a next-step button. While an action runs, the main buttons (restore, apply) are dimmed to prevent double clicks, and an action that is hard to undo turns the button to a warning color and asks "press once more …". It refreshes automatically every 20 seconds (every 5 seconds while "restore all" is running).

| Tab | What it shows | Shortcut |
|---|---|---|
| **Waiting for restore** (`복구 대기`) | Work that was closed or turned off and is waiting to be restored (grouped by Herdr space/tab name). If there is something to restore this tab opens first and shows a red dot. | `Ctrl+1` |
| **Open windows** (`열려 있는 창`) | AI windows currently in Herdr (by space). Clicking a status chip at the top (waiting for approval · working · finished · idle) shows only that status. | `Ctrl+2` |
| **Closed sessions** (`꺼진 세션`) | Past Claude/Codex conversations that are not automatic-restore targets (by folder). Can be filtered by AI type. | `Ctrl+3` |

Pressing `Enter` in the search box runs the first result (restore for "waiting for restore" and "closed sessions", move for open windows).

### 8.3 "Waiting for restore" tab — buttons

| Button | What it does | Caution |
|---|---|---|
| **Restore all (N)** (`전부 복구 (N)`) | The keeper restores all waiting work (in the background, a few minutes). While running it shows "remaining N / M" | **Runs only after a second click** |
| **Preview** (`미리보기`) | Shows only, per item, "type into the empty window and continue / open as a new tab / skipped — reason", without typing or creating anything | Safe (changes nothing) |
| **Restore** (`복구`) | Restores only that one item | |
| **Remove from list** (`목록에서 제외`) | Removes work you have finished for good from the restore list (the conversation record file is not deleted) | Runs only after a second click |
| **Remove N old items** (`옛 항목 N개 제외`) | Removes old items classified as "restore by hand" all at once (a backup file is made first) | Runs only after a second click |

Item states: `복구 대기` (waiting; automatic restore target) · `직접 복구` (old item, by button only) · `자동 복구 실패` (gave up after 3 automatic tries → **Restore** starts it in a new tab) · `복구 불가` (the conversation record file is gone → only removal is possible).

### 8.4 "Open windows" and "Closed sessions" tabs — buttons

| Button | What it does |
|---|---|
| **Go to this window** (`이 창으로 이동`) | Only moves the screen to that window (no typing, no closing). |
| **Restore** (`복구`) (closed sessions) | Opens a new tab and continues with `claude --resume` / `codex resume`. A conversation that is already running somewhere is **not opened**, to prevent the accident of two windows using the same conversation. |
| **Copy ID** (`ID 복사`) | Clicking the 8-character chip copies the **full ID**. |
| **Copy command** (`명령 복사`) (when hovering with the mouse) | Copies one line, `claude --resume <ID>` or `codex resume <ID>`. Paste it into a terminal to continue. |

A window shown as `ID 확인 불가` (ID cannot be determined) can be clicked to see the reason (for example, there is more than one Codex window in the same folder so it cannot be decided).

### 8.5 How to use automatic app updates

The update line at the top of the Session Keeper window appears **only when a new version exists or automatic update is off**. If there is no line, it is up to date and automatic update is on.

| State | Meaning |
|---|---|
| New version downloaded (`ready`) | Herdr has downloaded a new version (for example 0.1.15) but it is not applied yet |
| Window restart needed (`restart`) | The files are the new version but the window is still running the old version |
| Nothing to do (`none`) | Up to date (in this state the update line is not shown on the screen) |

| Button | What it does |
|---|---|
| **App update** (`앱 업데이트`) | Replaces the files safely and **restarts only the Herdr window** (terminals are kept by `herdr-core`). **Runs only after two clicks.** The window closes and opens briefly. |
| **Automatic update: on/off** (`자동 업데이트: 켜짐/꺼짐`) | Switches automatic applying on and off (default on). This button is inside the update line, so it is not shown in the usual state (up to date and automatic update on); to turn it off then, use `-Mode Update -Auto Off`. Turning it off creates the file `session-keeper.appupdate.off`. |

> **These two buttons are close together, so look at the screen when you click.** On the development PC there was once a case where an update and "automatic update off" were recorded in the same second (cause not confirmed; a shifting button position is possible). If that is not what you wanted, turn it on again with `-Mode Update -Auto On`.

**When it is applied automatically** (when automatic update is on):

1. If the keeper finds an old version **within 3 minutes after Herdr started**, it applies the update right away. A window that has been open for a long time is **not closed and reopened by itself**; it only notifies you.
2. (optional) If you installed the launcher, it applies **before the app starts**.
3. (optional) If you create the file `session-keeper.appupdate.idle`, it also applies while the app is open and idle (default off).

**Launcher (optional)**: `session-keeper.ps1 -Mode Update -Launcher Install` — connects the desktop and Start-menu shortcuts to the launcher and **sets their "Start in" folder to the user folder** (because a Herdr install folder used as the "Start in" folder is the root cause of the blocked update, [chapter 11](#11-update-summary)). For a pinned taskbar icon only the "Start in" folder is fixed. The original shortcuts are backed up in `shortcut-backup\` and `-Launcher Uninstall` puts them back. Even if the launcher fails, Herdr always starts. **It has never been installed on real shortcuts (unverified, [chapter 19](#19-verification-status-and-known-limits)).**

### 8.6 Checking the restore result (after a reboot)

- On-screen notification: "Herdr 세션 복구 완료" (restore complete) or "확인 필요" (check needed).
- The **verdict** line at the very top of `LAST-RESTORE.txt` (inside the install folder):

| Verdict | Meaning |
|---|---|
| `정상` (normal) | Everything restored (or already running) |
| `주의` (attention) | Some windows need checking → see the list below in the file and `다음 할 일` (next to do). With `주의 - 대화는 전부 복구됨 · 감시·예약 재가동 필요 N 개` the conversations came back but the monitors/schedules you had running in those windows must be **started again by hand**. |
| `복구할 것 없음` (nothing to restore) | There was nothing to restore (for example only Herdr was restarted) |
| `확인 필요 - 재부팅 직후인데 복구할 기록이 없습니다` (check needed — right after a reboot but no record to restore) | The record may be empty → check `session-keeper.log` |

More detail: `session-keeper.log`; past results: `restore-history.log`.

---

## 9. How it works

### 9.1 Normally (every minute): remembering

The keeper reads the list of open windows from the Herdr core (`hc ls`), finds the number of the AI conversation running in each window and writes it to `session-map.json`.

- **Claude**: it links a window exactly using the running-session files Claude Code leaves and the **process lineage** (session → parent … → the window's shell).
- **Codex**: decided in the order below. If it is not certain it **does not record** and writes the reason to the log (better than attaching a wrong conversation).
  1. `codex resume <ID>` in the command line (windows restored by the keeper all use this, so it is exact).
  2. Same working folder + a conversation file updated after the window started.
  3. If there is more than one Codex window in the same folder, **screen matching**: compare whether the first 40 characters (whitespace ignored) of a candidate conversation's latest statement appear on a window's screen (`hc read`), and confirm **only when one window matches exactly one candidate and that candidate does not overlap with another window**.
- When a window itself disappears: if the same Herdr is still running and the end reason is `killed` (the tab or space was closed directly), it is treated as "closed by the user" and removed from the restore list at once. Anything else (core restart, whole app shut down, no end record, 6 or more ending within 30 seconds) is treated as an accident or uncertain and is **kept**. If the window is still open but only Claude ended (for example `/exit`), it is tidied up after about 2 minutes (two checks).
- A window you closed yourself is written to the log as `직접 닫은 창: … (다시 열려면 claude --resume <ID>)` (window closed by hand … to reopen use …) and leaves the restore list. Condition: the same Herdr is still running (at least one live window) and that window's end record is `killed`. If the judgement is uncertain it is **treated as an accident and kept**.

### 9.2 When Herdr is started again: restoring

1. When the keeper detects that the Herdr app has newly started, it begins restore attempts after 20 seconds (every 30 seconds for 10 minutes; up to 30 minutes if items are left; it ends early after 3 rounds in a row with nothing to do). An accident where 6 or more windows died at once while the app stayed up is restored the same way.
2. The **automatic restore targets** are only "windows that were open just before closing" (within 10 minutes of the latest last-seen time). Older items remain in the restore list as `직접 복구` and are restored by button only.
3. Order: space names written in `restore-priority.txt` in the install folder (you must **create this file yourself**; without it there is no space ordering) → inside the same space the most recently used first → window address. Batches of 6 with 4 seconds between batches.
4. By window type:
   - **A window that came back as an empty shell** → type `claude --resume <ID>` (or `codex resume <ID>`) into that shell. Layout and name are kept.
   - **A window that ended** → create a **new tab** in the space of the same name and run it (from 120 seconds after the core started).
5. **Safety rules — if any one is not met, that window is skipped**: the same conversation is not already running / the conversation file (`.jsonl`) exists / fewer than 3 attempts / (empty shell) same tab + the foreground program is powershell + no AI + an empty prompt / (new tab) 120 seconds after the core started.
6. When finished it writes the result to `LAST-RESTORE.txt` and shows one notification.

### 9.3 Why the Herdr app did not update, and the fix (plain explanation)

- Herdr downloads a new version into the `herdr-app.new` folder and, at the next restart, replaces the install folder **by renaming it**.
- Windows **cannot rename a folder that someone is using as a working location.** On the development PC the shortcut "Start in" was the install folder, so 1 app + 4 core + 34 terminal-host processes were holding that folder (measured). The replacement therefore failed forever.
- Session Keeper changes **the files inside the folder, not the folder name** (because even a running program file can be renamed).

| Step | Description |
|---|---|
| ① Full backup | Folder `herdr-app.backup-<version>-<time>` (latest 2 kept) |
| ② File-by-file replacement | Rename the old file to `.old-<time>` → copy the new file |
| ③ Verification | Check the SHA256 of every file and `--version` |
| ④ On failure | **Put everything back** (if even one is wrong) |
| ⑤ Window restart (optional) | Send the end signal (`app.quit`) to the old window using the old program → start the window with the new program → compare the number of live terminals |
| Safety net | If the update stops after closing the window, the keeper starts the app instead after 20 seconds. During the restart the keeper neither opens the restore window nor deletes records. |

---

## 10. Command reference

Run every command in PowerShell/a terminal. `<install location>` defaults to `%LOCALAPPDATA%\HerdrSessionKeeper\app`. Quotes are needed when the path has spaces.

### 10.1 Keeper (`session-keeper.ps1`)

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<install location>\session-keeper.ps1" -Mode <mode> [options]
```

| Mode | What it does |
|---|---|
| `Snapshot` (default) | Records the current state once |
| `Recover` | Restores once, right now. With `-Plan` it is a **preview** (nothing typed or created), `-Only <window address>` restores only that window, `-Batch <count>` (default 6) and `-DelaySec <seconds>` (default 4) adjust speed |
| `Run` | The watch loop (the mode Task Scheduler starts). `-RecentMin <minutes>` (default 10; 0 restores everything as before) · `-AppGoneExitSec <seconds>` (default 120) |
| `Forget` | Remove from the restore list. `-Sid <6 or more characters of the session ID>` for one (the 8 characters inside `[ ]` in the restore result file also work), `-Stale` for old items in bulk (backed up first) |
| `Update` | Herdr app update. Options: `-NoRestart` (replace files only, leave the window) / `-Auto On\|Off\|Status` / `-Launcher Install\|Uninstall\|Status` |

### 10.2 List/restore tool (`sessions.mjs`, Node.js)

```
node "<install location>\sessions.mjs" <command>
```

| Command | What it does |
|---|---|
| `list [--days 14] [--limit 60] [--all]` | Show sessions as a table (`--all` includes short/automatic sessions) |
| `json …` | The same content as JSON (used by the Session Keeper window) |
| `open <6 or more characters of the session ID>` | Opens a **new tab** in Herdr and continues. Refuses if it is already running |
| `focus <window address>` | Only moves the screen to that window |
| `last` | The latest automatic restore result (JSON) |
| `plan start` / `plan read` | Run / read the "restore all" preview |
| `recover <window address\|all>` | Restore waiting work through the keeper (in the background) |
| `forget <ID>` / `forget-old` | Remove from waiting / remove old items in bulk |
| `health` | Show the keeper's recognition-rate check result (`keeper-health.json`) as JSON (read-only; `null` if the file does not exist) |
| `update-state` / `update` / `update-auto on\|off` | App update state / apply / switch automatic on or off |
| `set-key <key\|reset\|remove> [--replace]` | Changes the shortcut that opens the Session Keeper window (the command the window's [단축키] button uses. A clashing key is refused; only `--replace` overwrites) |

### 10.3 Install and uninstall (`install.ps1`, `uninstall.ps1`)

```
powershell -NoProfile -ExecutionPolicy Bypass -File plugins\herdr-session-keeper\install.ps1 [-Check] [-InstallDir path] [-HerdrHome path] [-HerdrApp path] [-TaskName name] [-NoTask] [-Key key] [-NoKey] [-Launcher] [-RestartKeeper] [-Force]
powershell -NoProfile -ExecutionPolicy Bypass -File plugins\herdr-session-keeper\uninstall.ps1 [-InstallDir path] [-HerdrHome path] [-TaskName name] [-RemoveData]
powershell -NoProfile -ExecutionPolicy Bypass -File plugins\herdr-session-keeper\set-key.ps1 [-Show | -Key key | -Reset | -Remove] [-Replace] [-DryRun] [-HerdrHome path]
```

### 10.4 Other tools and tests

| Command | What it does |
|---|---|
| `node scan-monitors.mjs [UTC time]` | (read-only) Tells which windows had monitors/schedules running at that time |
| `node build-kit.mjs [output folder]` | Rebuild the install kit. Without an argument it writes to the repository top level (`.claude-plugin`, `plugins`); given a folder it builds a standalone kit there (includes a check that fails if personal paths or secrets get in) |
| `node build-readme.mjs` | Regenerate the HTML files of the README from md and check that md and html match |
| `node tests/run-all.mjs [name…]` | Run all (or some) tests. Example: `node tests/run-all.mjs codex lib` |
| `herdr-app check <mod folder>` | Herdr's official mod check |
| `herdr-app --version` | Herdr app version |

### 10.5 Inside Claude Code

```
/plugin marketplace add sodam-ai/SoDam-Herdr-Session-Keeper
/plugin install herdr-session-keeper@herdr-session-keeper-market
```

The install-helper skill is named `herdr-session-keeper` (say "세션키퍼 설치해줘", meaning "install Session Keeper").

### 10.6 Environment variables

Environment variables are **not required.** The installer finds the locations on that PC and records them in `kit.env` in the install folder, so in a normal environment you need to set nothing. All variables below are **folder or program locations, or switches for tests**.

| Name | Role | Default |
|---|---|---|
| `HERDR_APP_HOME` | Herdr settings folder | `%USERPROFILE%\.config\herdr-app` |
| `KEEPER_APP_EXE` | Path of `herdr-app.exe` | `%LOCALAPPDATA%\Programs\herdr-app\herdr-app.exe` |
| `CLAUDE_CONFIG_DIR` | Claude Code settings folder | `%APPDATA%\claude-code` (if present) → `%USERPROFILE%\.claude` |
| `CODEX_HOME` | Codex data folder | If unset, the more recently written of `.codex_runtime` and `.codex` is used |
| `KEEPER_APP_PROC` | (for tests) Name of the app process to watch | `herdr-app` |
| `SESSIONS_KEEPER_DIR` | (for tests) Folder from which `sessions.mjs` reads keeper records | The folder containing `sessions.mjs` |
| `SESSIONS_NO_HERDR` · `SESSIONS_NO_CODEX` | (for tests/checks) `1` turns off the Herdr query / the Codex reading | Off |
| `KEEPER_NO_MAIN` | (for tests) `1` only loads the keeper functions, the main loop is not run | Off |
| `kit.env` file | Lines `NODE_DIR`, `HC_DIR`, `APP_EXE`, `APP_HOME`, `CLAUDE_CFG` that the installer records (a variable already set in the environment is used first) | Created at install time |

### 10.7 Build, test and release (for developers)

Ordinary users do not need this item. It is the procedure for developers who want to change this repository and release it again.

```
node tests/run-all.mjs        # 1) all tests (only some: node tests/run-all.mjs codex lib)
node build-kit.mjs            # 2) if you changed the sources, rebuild the install kit (plugins\, .claude-plugin\)
node build-readme.mjs         # 3) if you changed README.md / README.en.md, rebuild the HTML + check md<->html and ko<->en
# 4) commit the generated files too -> push to a work branch -> Pull Request -> merge (never push directly to the default branch)
```

- The "real data" tests (`contract`, `sessions`) read the real files of a **PC with Claude Code and Herdr installed** (read-only), so they may not pass on a PC without them (that environment is **unverified**).
- A GitHub Release is not created automatically. If needed, raise the version number (`kit-src\plugin.json`, `VERSION` in `build-kit.mjs`) and decide separately.

---

## 11. Update summary

<details>
<summary><b>Kit 1.1.4 (2026-11-26) — documentation and test update (the program is the same as 1.1.3)</b></summary>

- **The product (keeper, install tool, window screen) did not change.** The 5 core files (`session-keeper.ps1`, `sessions.mjs`, `scan-monitors.mjs`, `herdr-launch.ps1`, the watchdog `.vbs`) were confirmed identical to the development copy. The program files are the same as 1.1.3; only the version number was raised to 1.1.4 to carry the documentation and test fixes. If you already installed it, updating the plugin to 1.1.4 does not change its behavior, and you do not need to run `install.ps1` again.
- **Newly confirmed (development PC)**: on 2026-11-21 the user added the marketplace and installed 1.1.3 themselves, and a 6-step rehearsal install with the installed tool, using a temporary folder and a temporary task name, passed all 19 checks (the real Session Keeper, task and `keys.json` stayed unchanged). All 3 real PC restarts passed, and in the most recent (2026-11-22) 29 of the 29 windows recorded before the restart were restored (0 failures). This confirms the "real restart restore after the old-pid fix" that the 1.1.3 entry below lists as not yet verified. On 2026-11-26 all 22 test suites, 694 checks, passed again.
- **Test fixes**: the fixed 0.8-second wait in the app-update test became a state check of up to 10 seconds (reduces intermittent failures; the checks are unchanged), and the summary line format of the old-pid reuse test was fixed.
- **Security and legal review**: all 14 hostile inputs were blocked, the security tests passed 34/34, and secrets were 0. The `LICENSE` was compared line by line with the official Apache text ([chapter 18](#18-legal-copyright-license-and-commercial-use)). The caution that installing on a drive such as `D:` may inherit write permission for all users is in [15.4](#154-security-cautions).
- **Documents**: the whole Korean and English README was checked against the code and stale or wrong parts were fixed (install step 3/6 `WARN` display, path mistakes, the log line for a helper keeper that exits, keeper restart time of 3–4 minutes, when the update line is shown, how a closed window and an accident are judged, when a restore starts, the rule for choosing the Codex folder, etc.). A plain-language summary table (18.7) and a caution about AI-generated content (18.8) were added.
- **Left as is**: the keeper log line `루프 오류(계속 진행)` (32 in total, cause unverified), the heartbeat not being refreshed during a restore, the install 3/6 wording, and the intermittent failure of the install-kit tests (cause unverified, [19.2](#192-what-could-not-be-confirmed-unverified--not-run)). Installation on another PC or Windows 10 is unverified.

</details>

<details>
<summary><b>Kit 1.1.3 (2026-11-20) — recognition-rate check warning · fix for record-saving collisions</b></summary>

- **Recognition-rate check warning (new)**: every minute the keeper compares "the number of windows Herdr reports as Claude windows" with "the number the keeper recognized as Claude". If there are 3 or more windows and fewer than half are recognized for 3 minutes in a row, it warns through the log and a Windows notification (again every 6 hours) and a red line appears at the top of the keeper window. If the check record is not refreshed for over 6 minutes, it shows "check stopped". It only warns; it does not touch records, restore or input. It stays quiet during a restore and within 5 minutes after the keeper starts.
- **State file `keeper-health.json` (new)**: every minute it records the check result (last check time, check interval, window count, recognized count, number of old-screen residue windows, state, whether a restore is in progress). It lets other programs read the keeper's state, and `node sessions.mjs health` shows it too. The format of the restore record `session-map.json` is unchanged.
- **Old-screen residue windows excluded**: a residue window with only a shell and no Claude is not counted as "an unrecognized Claude", so it does not cause a false warning.
- **Fix for record-saving collisions**: when the automatic watcher and a manual run saved the record at the same time, they wrote the same temporary file and a save could fail (experiment: 31 of 240 saves failed with 4 runs saving 60 times each at the same time). The keeper now locks only the short saving moment and gives each run its own temporary file name; the same experiment now fails 0 times.
- **Keeper-stuck notice**: if a new keeper cannot start while the check record (heartbeat) has been stopped for over 5 minutes, it notifies once through the log and a notification.
- **Fix: recovery skipped because an old process number was reused**: after a restart, Windows can hand a process number (pid) from before the restart to a completely different program. The keeper then read the leftover old session file (`sessions\<number>.json`) as "the same conversation is already running" and did not recover that window. In a real restart test (2026-11-20, with the code from before this fix) 27 of 28 windows were recovered in about 6 minutes and 1 was skipped this way (that window had to be continued by hand with `claude --resume <id>`). The keeper now compares the process start time written in the session file with the real process's start time (5-second tolerance) and ignores the file as a leftover if they differ. If the file has no start time, it cannot be read, or it is not in the expected format (a Windows FILETIME), the keeper does not judge and treats it as running as before (so that a future change of this value's format in Claude cannot make every window look fake, and so it never types over a conversation that really is running).
- **Re-install after moving the folder**: if the files at the old place are gone, the installer re-links to the new place without `-Force` (see [5.7](#57-how-it-keeps-working-when-the-environment-folder-or-computer-changes)). If the old place is still there or its drive is missing, it stops as a conflict like before.
- **Herdr app location re-search**: if the app location written at install time is stale (the app was reinstalled somewhere else), the keeper searches again: the running app, then the default install location, then PATH. A location the user set with an environment variable is respected as is.
- **Tests**: added tests for the check, the state file, saving collisions, old-pid reuse (11 checks) and re-install after a folder move plus the app location re-search (5 checks); all 22 suites pass. The "auto-start rule" test used to count app processes once and sometimes failed falsely when another program briefly started an app process at that moment; it now waits and checks whether the count stays increased.
- **Not verified (as of the 2026-11-20 release)**: a real PC restart restore after the old-pid fix (at release time that fix was verified only with a replay test using fake session files and a waiting process, and **it was later confirmed by a real restart on 2026-11-22: 29 of 29 windows restored**), a real-PC check of re-install after a folder move (only tested with temporary folders and a temporary task), another PC, Windows 10. The recognition-rate warning was verified with fake data and a replay of the past incident (2026-11-14); I have not yet seen it fire in a real incident. Also, the keeper sometimes disappears without a normal-exit mark (it happened once more on 2026-11-20 at 14:34; the watchdog task started it again within about 4 minutes and no window was affected). I have not yet found the cause.
- Shortcut and app-update behavior are unchanged. Restore behavior changed only by the "old process number reuse" fix above, and the install kit only by "re-install after moving the folder" above. The keeper program applies the new code the next time it restarts.

</details>

<details>
<summary><b>Kit 1.1.2 (2026-11-18) — fixes for sessions not being restored (update recommended)</b></summary>

- **Fixed detection of Claude inside a window (most important)**: `hc` reports the window's root shell number (`pid`) and the number of the program currently in front (`foreground.pid`) separately, but the old keeper assumed the front program was the shell and looked only at its children. With this format it found none of the open Claude sessions, so the restore record stopped being updated. It now searches under the root shell first (on a real PC: 0 found → 19 found).
- **Removed the permanent give-up lock**: after one failed restore check, the old keeper fixed the attempt count at 99 and never tried again. Attempts are now counted only up to the limit (3), and an old record's 99 is read as "tried once". The check after typing waits up to 180 seconds.
- **Handling of windows with old-screen residue**: when the Herdr app starts again, an empty shell where the old Claude screen was redrawn is recognized by Herdr as a Claude app, and typing a command into it mixed mouse/key-encoding characters into the command and broke it. For such windows the keeper does not type; it **restores into a new tab** and leaves the old window open.
- **Automatic restore when windows end while the app stays open**: before, automatic restore started only "when the Herdr app starts anew", so Claude windows that ended while the app kept running were not brought back. Now restore starts when 6 or more restore-pending windows appear and the newest has settled for over 45 seconds (so the app is not just shutting down), at most once per 10 minutes for the same incident.
- **Tests**: added 50 tests for window detection, attempt counting, residue windows and incident detection; all 21 suites pass.
- **Verified on a real PC**: after restarting the PC and opening Herdr, all 22 conversations were restored automatically (0 failures) and the conversation IDs matched before and after the restart. Not verified on another PC or Windows 10.
- Install kit, shortcut and app-update behavior is unchanged. The keeper program applies the new rules the next time it restarts.

</details>

<details>
<summary><b>Kit 1.1.1 (released 2026-11-18) — security review fixes</b></summary>

- **Install and uninstall data protection**: install is refused into a folder that holds other files or into a drive root, and `uninstall.ps1 -RemoveData` no longer deletes the whole folder; it deletes only the files Session Keeper created (the folder stays if other files are in it). Before, installing into a wrong folder and then uninstalling with `-RemoveData` also deleted that folder's other files.
- **Shortcut file protection**: a `keys.json` you locked as read-only is not changed (you are told instead). A shortcut can now be bound in an empty `global` section, and the new line matches the file's indentation.
- **Stricter ID check**: the conversation-ID check that let a value with a trailing line break pass was fixed, and the window's copy function also refuses Unicode quotes.
- **Stronger tests**: added a security test (20 command-injection inputs and the ID format) and the test runner now marks a suite as failed whenever it reports failures, whatever the exit code.
- Restore, watchdog and app-update behavior is unchanged. The keeper program applies the new ID check the next time it restarts.

</details>

<details>
<summary><b>Kit 1.1.0 (2026-11-15) — shortcut change · window UI refresh · repository rename</b></summary>

- **Change the shortcut**: change the key that opens the window with the **[단축키]** (shortcut) button in the Session Keeper window (input box, suggested keys, "press the key") or with `set-key.ps1` (`-Show` `-Key` `-Reset` `-Remove` `-Replace`). A key already used by another function is refused and only overwritten after confirmation. You can also choose it at install time with `-Key`, and a changed key is kept when you install again.
- **Window UI refresh**: tabs as one control with counts, button kinds (primary, normal, quiet, warning) with pressed and disabled states, result notices told apart by color and text (closable), notice cards for empty, loading and error states, a repeated explanation shown once, `자동 시도 3/3` (auto attempts 3/3) wording, tidier shortcut wording.
- **Repository rename**: the GitHub repository is now `SoDam-Herdr-Session-Keeper`, so the install command (`/plugin marketplace add sodam-ai/SoDam-Herdr-Session-Keeper`) was updated. The internal marketplace and plugin names are unchanged.
- Restore, watchdog and app-update behavior is unchanged.

</details>

<details>
<summary><b>Kit 1.0.0 (2026-11-11) — install kit and portability</b></summary>

- Provides a Claude Code marketplace + plugin + direct install (`install.ps1`/`uninstall.ps1`/`install.cmd`).
- Automatic environment discovery (`kit.env`): finds Node.js, the Herdr app, `hc`, the Herdr settings folder and the Claude settings folder on that PC and records them.
- The watchdog script (`session-keeper-watchdog.vbs`) finds the keeper relative to its own folder instead of a fixed path.
- Claude settings folder rule: `CLAUDE_CONFIG_DIR` → `%APPDATA%\claude-code` → `~\.claude`.
- If a Session Keeper already installed in another location exists, it stops instead of overwriting (replaced only with `-Force`).
- 41 tests (temporary folders and temporary task names, Korean/space paths) pass. **Installation on another PC is unverified.**

</details>

<details>
<summary><b>2026-11-11 — Herdr app automatic update</b></summary>

- **Problem**: While Herdr stayed open, a new version was never applied (0.1.15 had been downloaded but 0.1.14 remained).
- **Cause (measured)**: replacement by renaming a folder + 39 processes (1 app · 4 core · 34 terminal hosts) holding the install folder as their working location + the shortcut "Start in" being the install folder. Upstream (herdr-app) also fixed this in 0.1.15, but installing 0.1.15 required getting past this very bug first — a chicken-and-egg loop.
- **Fix**: file-level replacement (full backup → SHA256/version check → full rollback on failure → optional window restart). Terminals are kept by the core.
- **When applied**: the moment Herdr starts (within 3 minutes of start) / before the app starts when going through the launcher / the **App update** button of the restore window / `-Mode Update`.
- **On/off**: default on. `-Auto On|Off|Status` or the button in the restore window. Applying while open and idle uses the `.idle` file (default off).
- **Confirmed in real use**: the real Herdr on the development PC was replaced and restarted from 0.1.14 to 0.1.15 and its 26 terminals stayed as they were (log record). This run appears to have been done through the restore-window button, and automatic update also became "off" in the same second (cause not confirmed).
- Limits: old files that no longer exist in the new version are not removed. The launcher/shortcut feature has never been installed on real shortcuts.

</details>

<details>
<summary><b>2026-11-11 — Codex window matching improved</b></summary>

- The problem that restoring was impossible when there were several Codex windows in the same folder (all 6 Codex windows on the development PC were affected) is improved with **screen matching** (confirmed only when a window and a candidate conversation match each other uniquely).
- Both Codex data folders (`~/.codex`, `~/.codex_runtime`) are candidates, and the one whose state file was written more recently is used (the folder in `CODEX_HOME` takes priority if set).
- Limit: only fake-data tests passed. No Codex window was open at the time of testing, so it was not confirmed on a real window.

</details>

<details>
<summary><b>2026-11-11 — Restore scope made more precise</b></summary>

- Windows closed by the user are excluded from the restore list (user decision).
- Automatic restore applies only to "windows that were open just before closing" (`-RecentMin`, default 10 minutes). Old items by button only.
- **Remove N old items** bulk removal (backup `session-map.json.before-forget-old-<time>`, latest 5 kept).
- After restoring, a notice of windows that need their monitors/schedules started again (they are not restarted automatically).

</details>

<details>
<summary><b>2026-11-09 ~ 11-10 — Automatic start rule, Codex, ID copy</b></summary>

- It does not start by booting; it works only while Herdr is running (Task Scheduler checks every minute; the startup-folder entry was removed).
- Codex windows are confirmed by the command-line `resume <ID>`, the new-tab creation condition was strengthened, the restore window was extended to at most 30 minutes.
- An `ID` chip is always shown on every row of the Session Keeper window, and a `명령 복사` (copy command) button was added.

</details>

<details>
<summary><b>2026-11-04 — Restore speed, Codex restore, screen overhaul</b></summary>

- Restore order (space priority → most recently used) and speed improvement (isolated test with 14 windows 200.1 s → 29.8 s, about 6.7×; real Claude is heavier so the real time is **not measured**).
- Codex conversations can be restored too (`codex resume`).
- Second overhaul of the Session Keeper window (3 tabs · status chips · preview · restore all).

</details>

<details>
<summary><b>2026-11-03 — First version</b></summary>

- Records window ↔ session every minute, automatically types `claude --resume` when Herdr restarts, and a watchdog (Task Scheduler) was added.

</details>

---

## 12. Files and documents

### 12.1 This project folder (development / originals)

What is in the top-level project folder:

| File/folder | Description |
|---|---|
| `README.md` · `README.en.md` · `README.html` · `README.en.html` | **This document** (Korean/English × md/html). The HTML is generated from md with `node build-readme.mjs` |
| `LICENSE` | Full text of the Apache License 2.0 (copyright holder SoDam AI Studio) |
| `session-keeper-README.md` | Detailed keeper development record (changes by date, test results) |
| `session-keeper.ps1`, `lib\appupdate.ps1` | Keeper main program, app update |
| `sessions.mjs`, `lib\*.mjs`, `scan-monitors.mjs` | List/restore tool |
| `herdr-mod\session-keeper\` | Herdr mod originals (`main.js` · `model.js` · `mod.json`) |
| `herdr-launch.ps1`, `herdr-launch.vbs` | Launcher |
| `session-keeper-watchdog.vbs` | One-minute watchdog |
| `install-herdr-mod.ps1` | Script that installs only the mod directly from the repository folder (for developers; separate from the install kit) |
| `kit-src\`, `build-kit.mjs`, `.claude-plugin\`, `plugins\` | Install-kit sources · generator · generated result (included in the repository) |
| `tests\` | Tests (`run-all.mjs`, 22 suites). Includes the shortcut test `setkey.test.ps1` and the security test `security.test.ps1` (command injection and ID checks) |

### 12.2 Inside the install kit

```
(repository top level)\
  .claude-plugin\marketplace.json        marketplace list
  LICENSE                                Apache License 2.0 (a copy is also in the plugin folder)
  plugins\herdr-session-keeper\
    .claude-plugin\plugin.json
    skills\herdr-session-keeper\SKILL.md install-helper skill
    install.ps1  uninstall.ps1  set-key.ps1  install.cmd
    payload\                             program files to be installed + mod\ + VERSION
```

### 12.3 After installation (user's PC)

| What | Location (default) |
|---|---|
| Programs, records, logs | `%LOCALAPPDATA%\HerdrSessionKeeper\app\` |
| Herdr mod | `%USERPROFILE%\.config\herdr-app\mods\session-keeper\` |
| Key binding | `%USERPROFILE%\.config\herdr-app\keys.json` (+ backup `keys.json.bak-before-session-keeper-kit`) |
| Automatic start | Task Scheduler `HerdrSessionKeeper-Watchdog` |
| Launcher copy (optional) | `%LOCALAPPDATA%\HerdrSessionKeeper\` |

Data files inside the install folder:

| File | Content |
|---|---|
| `session-map.json` (+`.bak`) | Window address → session ID/space/tab record |
| `keeper-health.json` | The keeper's self-check result (last check time, window count, recognized count, state, whether a restore is in progress). Rewritten every minute and deleted when the keeper starts. Other programs may read it |
| `LAST-RESTORE.txt` · `restore-history.log` | Last restore result · accumulated results |
| `session-keeper.log` | Detailed log |
| `session-keeper.alive` | "I am alive" heartbeat (refreshed every minute, deleted on a normal exit) |
| `session-keeper.cutoff` | Reference time for automatic restore |
| `session-keeper.appupdate.json` / `.off` / `.idle` / `.marker` | App update state / automatic off / apply when idle / in-progress marker |
| `session-keeper.launcher.json`, `shortcut-backup\` | Launcher record, backup of original shortcuts |
| `restore-priority.txt` | Space names to restore first (one per line, `#` is a comment) |
| `kit.env` · `kit.install.json` | Record of found locations · install record |
| `_backup\` | Program backup before an update (latest 3) |

---

## 13. Workflow

### 13.1 Normal → accident → restore

```
[Normal]
 Work with Claude/Codex ──► the keeper writes "window ↔ conversation number" to session-map.json every minute

[Accident] PC turned off / Herdr suddenly closed
 └─ The conversation "record files" stay on disk; windows come back as empty terminals or vanish

[Restore]
 Start Herdr again
   └─► (within 1 minute) the Task Scheduler watchdog starts the keeper
         └─► automatically restores only the windows open just before closing
               ├─ empty-shell window → types claude --resume <number>
               └─ vanished window    → new tab in the same space + claude --resume <number>
         └─► result: LAST-RESTORE.txt + notification
   └─► remaining items: Ctrl+Shift+R → press Restore by hand
```

### 13.2 Installation

```
Install Node.js → install Herdr and run it once → extract the kit → install.cmd
   └─ check → copy programs → install mod (official check) → key binding → register task → record
        └─ press Ctrl+Shift+R in the Herdr screen
```

### 13.3 App update

```
Herdr downloads a new version (herdr-app.new)
   └─ the keeper notices it (state: ready)
        ├─ within 3 minutes of start + automatic on → apply immediately
        └─ otherwise → notify only; the user presses App update twice to apply
   Apply: full backup → replace files → SHA256/version check
          ├─ failure → put everything back
          └─ success → (optional) end signal to the window → start new window → compare terminal counts
```

---

## 14. Architecture

```
┌────────────────────────── User PC (Windows) ──────────────────────────────┐
│  Herdr app (herdr-app)  ◄── mod: Session Keeper window (main.js/model.js) │
│        │                         │ node sessions.mjs …                    │
│        ▼                         ▼                                        │
│  herdr-core (hc) ◄───── list/restore tool (sessions.mjs + lib\*.mjs)      │
│        ▲                         │ start command                          │
│        │ hc ls/read/send         ▼                                        │
│  ┌─────┴────────── keeper main session-keeper.ps1 ◄── Task Scheduler (1 min)
│  │  · lib\appupdate.ps1 (app file replacement)     watchdog.vbs           │
│  │  · records: session-map.json, log, heartbeat                           │
│  └───────────────┬──────────────────────────────────────────────────────  │
│                  ▼ read-only                                              │
│   Claude settings folder (sessions·projects), Codex data (~/.codex etc.)  │
└───────────────────────────────────────────────────────────────────────────┘
```

| Component | Role | Language |
|---|---|---|
| Session Keeper window (Herdr mod) | Screen, buttons, tabs. Leaves the real work to `sessions.mjs` | JavaScript |
| `sessions.mjs` + `lib\` | Reads sessions (Claude · Codex), links windows, restore commands, calls the keeper | Node.js (JavaScript) |
| `session-keeper.ps1` | Recording, restoring, watch loop, app update | PowerShell |
| `session-keeper-watchdog.vbs` | Starts the keeper only while Herdr is running | VBScript |
| `herdr-launch.*` | (optional) Update before the app starts | PowerShell + VBScript |

Design principles:

- **Read-only first**: lists and states are only read; the only thing that sends input is the restore path that passed every safety rule.
- **If not sure, do nothing**: if it cannot decide which conversation it is, it does not record, and it never attaches a wrong conversation.
- **Make it reversible**: back up before changing (`keys.json`, shortcuts, the Herdr app folder, restore records).
- **Herdr always starts**: even if the launcher or the update fails, the app is started.
- **No duplicate runs**: the keeper runs as only one through a Windows lock (mutex), and app update and restore each use a lock too.

---

## 15. Security and data flow

### 15.1 Summary

| Question | Answer |
|---|---|
| Does it send things to the internet? | **No.** I searched the source code (`.ps1` `.mjs` `.js` `.vbs`) for internet-access code (`http`, `Invoke-WebRequest`, `fetch`, etc.) and **found none** (confirmed by search; the address text `https://nodejs.org` in the install tool's Node.js hint is a hint message, not connection code). A new version of the Herdr app is downloaded by **Herdr itself**; this tool only moves the downloaded files into place. |
| Does it need administrator rights? | No. It works only within the current user's scope. |
| Does it handle passwords or API keys? | No. The 28 files of the kit (and also the whole repository of 90 files and the 24 commits of the Git history as of the 2026-11-26 check) were searched for keys, tokens, passwords, private keys and e-mail strings, with **0 hits**. |
| Does it read conversation content? | To display the list it reads the **title, part of the last request, folder and model** from Claude conversation records (`.jsonl`); for Codex it reads conversation files and part of the **window screen text (`hc read`)**. All of it is processed **only inside this PC** and shown on screen. |
| Does it send input? | **Yes, in one case only**: the restore that types `claude --resume <ID>` / `codex resume <ID>` into an empty shell window (when all safety rules pass). It types into no other windows. |
| Does it delete anything? | It **does not delete** conversation records. It only tidies old backups in its own folder (keeping only the latest few) and temporary files. The uninstall tool also deletes only what was installed. |
| Can a wrong install or uninstall folder make me lose my files? | **No.** A folder that holds other files, or a drive root, is refused at install, and uninstall (`-RemoveData`) deletes only the files Session Keeper created and leaves the folder if other files are in it. |

### 15.2 Where data is written

| Data | Location | Sensitivity |
|---|---|---|
| Window ↔ session record (session ID · space · tab name) | install folder `session-map.json` | **Medium**: contains project names and session numbers |
| Logs · restore results | `session-keeper.log`, `LAST-RESTORE.txt`, `restore-history.log` | Medium: may include working-folder names |
| Restore-preview temporary file | `%TEMP%\session-keeper-plan.txt` | Medium |
| Shortcut backups | `shortcut-backup\` | Low |

> **Do not post these files to public repositories, messengers or e-mail.** They are not included in the install kit (the build checks this). When you upload the project folder to a repository, these files must be excluded.

### 15.3 System areas this tool changes (full list)

1. The install folder (programs, records).
2. Herdr settings folder: `mods\session-keeper`, and in `keys.json` **the one Session Keeper shortcut line** (a backup is made. Changing the shortcut changes only that line, and a file you locked as read-only is left alone).
3. One Task Scheduler task.
4. (during an app update) **Files inside the Herdr install folder** (replaced after a backup, rolled back on failure).
5. (only if the launcher is installed) desktop and Start-menu shortcuts (changed after a backup).

It **does not touch** Claude Code settings (`settings.json` etc.) or Codex settings.

### 15.4 Security cautions

- The install and run scripts are run with `-ExecutionPolicy Bypass` **for that one script only.** Before running a kit of unknown origin, read the scripts inside `payload` yourself.
- It does not access the data of other user accounts on the same PC (only the current user's folders).
- To install on a shared PC or someone else's PC you need the owner's consent ([chapter 18](#18-legal-copyright-license-and-commercial-use)).
- **Permissions of the install folder**: the default install location (`%LOCALAPPDATA%`) is writable only by the current user. If you use `-InstallDir` on a place such as drive D:, the folder may be writable by "all users", and then another account could replace the keeper scripts, so check the folder permissions (Security tab).
- The restore records and logs (`session-map.json`, `session-keeper.log`, etc.) contain conversation IDs, folder paths and task names, so do not share them. They are excluded from the repository by `.gitignore`.
- The install location must be a "Session Keeper only folder". A folder that holds other files, or a drive root, is refused at install, and `-RemoveData` also deletes only the files Session Keeper created.

---

## 16. Troubleshooting

| Symptom | Possible cause | Fix |
|---|---|---|
| `중단: Node.js 18 이상이 필요한데 찾지 못했습니다` (stopped: Node.js 18+ needed but not found) | Node.js not installed / old, or the terminal was not reopened after install | After [4.2](#42-getting-nodejs) try again in a **new terminal** |
| `중단: Herdr 앱(herdr-app.exe)을 찾지 못했습니다` (stopped: Herdr app not found) | Herdr not installed or in another place | Install and run Herdr then retry, or `-HerdrApp "path\herdr-app.exe"` |
| `중단: Herdr 설정 폴더가 없습니다` (stopped: Herdr settings folder missing) | Herdr was never run | Run Herdr once and retry, or `-HerdrHome` |
| `중단: 설치 파일(payload)이 없습니다` (stopped: installation files missing) | Ran without extracting / only part of the folder was copied | **Extract completely** and move the whole folder, then retry |
| `중단: … 이미 다른 위치에 세션키퍼가 설치되어 있습니다 … 덮어쓰지 않았습니다` (stopped: already installed elsewhere, not overwritten) | Conflict with an existing install | Keep using the existing one, or use `-Force` to replace |
| `중단: 설치 위치가 이미 다른 파일이 들어 있는 폴더입니다` / `드라이브 루트입니다` (stopped: the install location holds other files / is a drive root) | You pointed the install at a place that holds someone else's files, such as a documents folder (refused so those files cannot be lost when uninstalling later) | Use a dedicated empty or new folder, e.g. `%LOCALAPPDATA%\HerdrSessionKeeper\app` |
| `… 는 Herdr 에서 이미 다른 기능(…)에 쓰고 있어 바꾸지 않았습니다` (… is already used by another Herdr function, not changed) | The key you chose is already used by Herdr (refused on purpose) | Choose another key. To release that function and use the key anyway, press [덮어쓰기] (overwrite) twice in the window or run `set-key.ps1 -Key … -Replace` |
| `keys.json 이 읽기 전용이라 바꾸지 않았습니다` (keys.json is read-only, not changed) | You locked the shortcut settings file as read-only | Remove the "read-only" attribute yourself, then try again (the tool never unlocks it for you) |
| `이 키는 쓸 수 없습니다: …` (this key cannot be used) | `Ctrl+C/D/Z`, a letter key without Ctrl or Alt, etc. | Use a key that follows the rules in [5.8](#58-changing-the-shortcut-key), as the message says |
| Script execution is blocked (execution policy / security software) | Company policy, antivirus | Use `install.cmd` or the `powershell -ExecutionPolicy Bypass …` form above. If policy blocks it, ask the administrator |
| Warning: task registration failed | Task Scheduler restrictions | Install with `-NoTask`, then after starting Herdr run it manually with `-Mode Run` |
| `Ctrl+Shift+R` does not open | Another feature already uses that key / the mod failed to load | `Ctrl+Shift+P` → `mod.open session-keeper`. Check with `herdr-app check "<mod folder>"` |
| The list is empty | The keeper has not started yet / `hc` was not found | Wait 1 minute → check `session-keeper.alive` → check `HC_DIR` in `kit.env` |
| Restore does not happen | Blocked by a safety rule, the conversation record file is gone, already running | See the reason with **Preview** (`건너뜀 — 이유` = skipped — reason) and check `session-keeper.log` |
| "대화를 하나로 정할 수 없어 기록하지 않습니다" (cannot decide on one conversation, not recorded) | More than one Codex window in the same folder and screen matching is also uncertain | Normal behavior (protects against a wrong conversation). Restore by hand from the Closed sessions tab |
| After restoring, the AI does not continue what it was doing | Restoring only continues the **conversation record** | Normal. Ask the AI again for the work it was doing |
| No monitors/schedules after restoring | Monitors/schedules vanish together with the program | Start them again by hand in the windows listed under the verdict `감시·예약 재가동 필요` (monitors/schedules need restarting) |
| App update does not finish at `restart` | Before the window restart | Click **App update** twice or run `-Mode Update` |
| App update failure message | Error during file replacement (automatically rolled back) | Check `session-keeper.log` and try again. The backup is `herdr-app.backup-<version>-<time>` |
| Window does not appear after an update | Rare failure | The keeper starts the app instead after 20 seconds. If it still does not appear, start Herdr from the Start menu |
| Automatic update suddenly "off" | The button was clicked, or clicked together with App update | `-Mode Update -Auto On` |
| Characters look garbled (`?`, strange characters) | Console encoding | No effect on operation. If you need to check, run `chcp 65001` first |
| A red line at the top of the keeper window: `점검 필요: Claude 창 N개 중 M개만 인식 중` (check needed: only M of N Claude windows recognized) | The keeper has failed to recognize the open Claude windows for over 3 minutes (if this continues, a restore after a PC restart may not work) | In `session-keeper.log`, read the warning line for the cause counts (window lookup failed / Claude not found, etc.). If it was temporary, the log later says `정상으로 돌아왔습니다` (back to normal). If it continues, keep the log and report an issue |
| A warning that the keeper disappeared | Keeper replaced or ended | The log line "같은 부팅 안에서 이전 감시가 … 사라졌습니다" (the earlier watcher disappeared during the same boot) — the watchdog starts it again (it starts it only after confirming the check record has been stopped for over 3 minutes, so it can take up to 3–4 minutes). If it repeats, check the log before and after |
| Install step 3/6 shows `검사 실행 실패: WARN …` (check run failed: WARN …) | Cause not settled (observation: the `WARN` of Herdr's official check is printed together) | The install carries on and finished 4/6 to 6/6 (the 2026-11-21 rehearsal install passed all 19 checks). Do not judge it a failure from this wording alone. **If step 6/6 is printed to the end and the exit code is 0, it is normal** |
| `install.ps1` gives `cannot find the file`, or `-Check` seems to do nothing | The terminal's current location is not the kit folder while you used a short path such as `.\install.ps1`, or you left out the leading `powershell` | Run it with the **full path**: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\myfolder\install.ps1" -Check`. Or open the kit folder in File Explorer, type `powershell` in the address bar to open a terminal in that folder, then run it |
| The log shows `… 심박이 N초째 멈춰 있습니다 … 새 프로세스는 종료합니다` (the heartbeat has been stopped for N seconds … the new process exits) | While a restore takes long, the check record (heartbeat) stops being refreshed, so the watchdog started a helper keeper and that keeper exited by itself | In both observed cases (2026-11-21, 2026-11-22) the restore result was not affected. If it repeats, check the log before and after |

**Where to look first for more detail**: ① the end of `session-keeper.log` in the install folder ② `LAST-RESTORE.txt` ③ the `-Plan` preview.

**If you want to go back**: [chapter 20](#20-uninstall-and-rollback).

---

## 17. FAQ

<details>
<summary><b>Q1. Does it restore by itself when I turn the computer on?</b></summary>

No. **Booting the PC alone starts nothing.** When you start Herdr yourself, the keeper starts within about a minute and restoring begins.

</details>

<details>
<summary><b>Q2. Does the work the AI was doing continue as it was?</b></summary>

No. Only the **conversation record** continues. The single task that was in progress when it went off does not continue, so you must ask the AI again, "please continue".

</details>

<details>
<summary><b>Q3. Does personal information leave the computer?</b></summary>

This tool's code has no internet access, so it sends nothing ([chapter 15](#15-security-and-data-flow)). Communication done by Claude Code, Codex and Herdr themselves is separate from this tool and follows each service's terms and settings.

</details>

<details>
<summary><b>Q4. Does it work on Mac or Linux?</b></summary>

No. It is Windows only (it uses PowerShell, Task Scheduler and Windows process information).

</details>

<details>
<summary><b>Q5. Is this a marketplace that can be installed from inside Herdr?</b></summary>

No. Herdr has no plugin-install feature (it was confirmed that the `herdr-app` commands have no mod-install command). The "marketplace" is for **Claude Code**. Herdr gets it by copying a mod folder (the installer does this for you).

</details>

<details>
<summary><b>Q6. Does installing close Herdr?</b></summary>

No. Installing does not close Herdr. Only when an app **update is applied** (button/automatic) does the window close and open briefly, and the terminals are kept.

</details>

<details>
<summary><b>Q7. Is the Herdr update really safe?</b></summary>

The order is full backup → file-by-file replacement → SHA256/version check → put everything back if anything is wrong. Success was confirmed on a separate test Herdr and on the real Herdr of the development PC (26 terminals kept). It is, however, **not guaranteed** to be safe on every PC and every version ([chapter 19](#19-verification-status-and-known-limits)).

</details>

<details>
<summary><b>Q8. I do not want automatic updates.</b></summary>

Use `session-keeper.ps1 -Mode Update -Auto Off` or the **Automatic update** button (`자동 업데이트`) in the Session Keeper window. When off, it only notifies you even if there is a new version, and you apply it yourself with **App update** (`앱 업데이트`) whenever you want.

</details>

<details>
<summary><b>Q9. I closed a window on purpose. Will it open again?</b></summary>

A window you closed yourself while Herdr was running leaves the restore list and is not restored. However, closing 6 or more at once on purpose can look like an accident, and they may come back next time. For work you have finished for good, use **Remove from list** (`목록에서 제외`).

</details>

<details>
<summary><b>Q10. Is it OK to leave the computer off for a long time?</b></summary>

The keeper keeps records for **365 days**. However, **Claude Code itself** has a setting that can delete old conversation files (`cleanupPeriodDays`; its default is said to be 30 days, but **all that was confirmed on the development PC is that the setting was absent and a 78-day-old file still existed**), so it cannot be guaranteed if you leave it off for months. This tool does not touch Claude's settings files. If needed, set `"cleanupPeriodDays": 365` yourself.

</details>

<details>
<summary><b>Q11. Can I install it on several PCs?</b></summary>

Technically you install it on each PC. For the license, see [chapter 18](#18-legal-copyright-license-and-commercial-use) (Apache License 2.0).

</details>

<details>
<summary><b>Q12. Can the installation be undone?</b></summary>

Yes. [Chapter 20](#20-uninstall-and-rollback). `uninstall.ps1` removes only what was installed. Restore records are kept by default.

</details>

<details>
<summary><b>Q13. Korean characters look garbled in the terminal.</b></summary>

It is only a display problem and does not affect operation. The scripts were tested in a Korean environment (UTF-8 BOM).

</details>

<details>
<summary><b>Q14. I changed the shortcut but it does not open.</b></summary>

Whether Herdr re-reads the changed `keys.json` right away has not been verified. **Close and reopen Herdr once.** If it still does not work, `Ctrl+Shift+P` → `mod.open session-keeper` always opens it, and in the window's [단축키] you can see the key that is bound now or press the "back to default" button ([5.8](#58-changing-the-shortcut-key)).

</details>

<details>
<summary><b>Q15. If I choose the wrong install location, will my files be deleted?</b></summary>

No. A **folder that already holds other files**, such as a documents folder, or a **drive root** is refused at install. Even with `-RemoveData` at uninstall, only the files Session Keeper created (including restore records and logs) are deleted, and the folder stays if other files are in it. However, if you already installed into a wrong folder with a very old version (before 1.1.0), check that the folder holds nothing important before uninstalling.

</details>

---

## 18. Legal, copyright, license and commercial use

> **For reference only; no legal effect is guaranteed.** Below are **facts confirmed directly** during development and cautious interpretations. Having a **lawyer review it is recommended** before distributing, selling or publishing, and final responsibility lies with the user. If you are new here, start with [18.7 Plain-language summary](#187-plain-language-summary).

### 18.1 License of this project (Session Keeper) — Apache License 2.0

- The `LICENSE` file at the top level of the repository contains the full text of the **Apache License, Version 2.0** (January 2004, the current latest version of this license), and the copyright holder is **SoDam AI Studio** (`Copyright 2026 SoDam AI Studio`). The same `LICENSE` copy is in the plugin folder, and `license` in `plugin.json` is `Apache-2.0`.
- This license **permits use, copying, modification, distribution and commercial use**, with conditions: ① provide a copy of the license ② keep copyright, patent and attribution notices ③ mark files you modified ④ if a distribution has a `NOTICE` file, keep its content.
- Trademarks are not licensed (section 6 of the license). No right to use names or logos is granted separately.
- Patents: contributors grant a patent license, but if you start patent litigation over this software, that patent license ends (section 3 of the license).
- **Commercial use**: allowed if you follow the conditions above. However, the terms and licenses of what is used together — Herdr, Claude Code, Codex, etc. — are separate and must be checked individually ([18.2](#182-herdr--apache-license-20-confirmed-from-the-installed-files), [18.3](#183-programs-and-services-used-together)).
- No warranty, limited liability: this software is provided **"AS IS"** and does not guarantee operation, data preservation or fitness for a particular purpose (sections 7 and 8 of the license). The interpretation above is for reference; the text of `LICENSE` is the authority.
- **Checking the `LICENSE` text**: on 2026-11-26 it was compared line by line with the official text of the Apache Software Foundation (`https://www.apache.org/licenses/LICENSE-2.0.txt`). The only difference is one copyright line in the closing notice (`Copyright [yyyy] [name of copyright owner]` filled in as `Copyright 2026 SoDam AI Studio`). The license text itself was not edited.
- **`NOTICE` file**: there is none at present. Section 4(d) of Apache 2.0 only requires you to keep the content of a `NOTICE` file **if a distribution has one**, so it is not needed now. This repository contains no image, font, video or audio files and no external-package dependency files, and no one else's copyright notice was found in the source (confirmed). If you later add someone else's code or material, you must judge again whether a `NOTICE` is needed.
- **Source file headers**: no copyright header is attached to each source file. Apache 2.0 recommends headers but does not require them.
- **Contributions (Pull Requests)**: unless stated otherwise, a contribution sent to this repository is treated as provided under the same license, according to section 5 of Apache 2.0.

### 18.2 Herdr — Apache License 2.0 (confirmed from the installed files)

- The `LICENSE` in the installed Herdr folder is the **Apache License 2.0** (confirmed). `THIRD-PARTY-NOTICES` is also there.
- This kit **contains no Herdr program files** (confirmed: no Herdr executable in the kit's file list). So handing out this tool is not redistributing Herdr.
- The app-update feature only moves the new-version files that **Herdr itself downloaded** into the install folder and does not change their content (checked equal by SHA256).
- Herdr contains fonts (OFL family), icons and other open-source components, each with its own license (for example the `THIRD-PARTY-NOTICES` list in the install folder shows file names such as `CC-BY-SA-3.0`, `OFL` and `Unicode`). **If you want to use or redistribute Herdr commercially, check the terms in Herdr's LICENSE and THIRD-PARTY-NOTICES yourself.** This document does not summarize those terms.

### 18.3 Programs and services used together

| Subject | This document's position |
|---|---|
| Claude Code (Anthropic) | This tool only **reads the record files** Claude Code leaves and runs `claude --resume`. **The terms of use are Anthropic's and may change.** This tool does not guarantee conformity with the terms. |
| Codex (OpenAI) | Same as above. It only **reads** conversation files (SQLite · rollout). OpenAI's terms apply. |
| Node.js | A separately installed program. The license of the Node.js you installed applies (this document did not check and write down its content). |
| Windows · PowerShell | Microsoft's licenses apply. |

### 18.4 Trademarks

Names such as Herdr, Claude, Claude Code, Anthropic, Codex, OpenAI, Node.js, Windows, PowerShell and GitHub are **trademarks of their respective owners.** This project is an **independent tool with no affiliation, sponsorship or official endorsement** from them.

### 18.5 Personal information and other people's computers

- The data this tool handles (session IDs, project folder names, parts of conversations) is stored **only inside this PC** and is not sent out, but because it reads files that may contain conversation content, **installing on someone else's PC requires the owner's prior consent.** For company or school PCs check the security policy.
- If record or log files are posted publicly, project names and session numbers are exposed ([chapter 15](#15-security-and-data-flow)).

### 18.6 Checklist before publishing or distributing this document and the kit

1. Is the `LICENSE` (Apache License 2.0, copyright holder SoDam AI Studio) at the repository top level and in the plugin folder, and is `license` in `plugin.json` set to `Apache-2.0`?
2. Have you decided the visibility (private/public), and if public, do you understand it cannot be undone?
3. Are **this-PC-only files excluded** — `session-map.json`, logs, restore results, role tables, approval records, etc. (the kit build checks this, but uploading the **whole project folder** would include them)?
4. Are the trademark and terms notices for Herdr, Claude, Codex etc. accurate?
5. Has the owner checked the AI-generated parts and the copyright holder notice (`SoDam AI Studio`) ([18.8](#188-caution-about-ai-generated-content))?

### 18.7 Plain-language summary

Below is the `LICENSE` (Apache License 2.0) in plain words. No legal effect is guaranteed, and the text of `LICENSE` is the authority.

| What you want to do | Can you? | What you must keep to |
|---|---|---|
| Use it on my PC | Yes | Follow the terms of Herdr, Claude Code and Codex used together |
| Download, keep, copy | Yes | Keep the `LICENSE` file with it |
| Modify and use | Yes | Mark the files you changed as changed (section 4) |
| Copy to my own repository (fork) or hand out for free | Yes | Provide a copy of `LICENSE`, keep copyright and attribution notices, and keep the `NOTICE` content if one appears |
| Sell it, put it in a paid service, use it for company work, deliver it to a client | This project's license **allows** it | Follow the conditions above and check the terms of the services used together. **A lawyer's review is recommended for contracts and deliveries** |
| Use in teaching material or lectures | Yes | State the project name and license |
| Use the name or logo as the name of my own product | **Not permitted** (section 6) | You need separate permission from the rights holder |

**What you must check yourself** (this document could not check it for you)

- The **pricing plan and usage policy** of Claude Code (Anthropic) and Codex (OpenAI): when restoring, this tool types `claude --resume` or `codex resume` for you. Check yourself whether that automatic run fits your plan and terms. The tool itself has no code that takes an API key or calls an AI model directly (confirmed by code search).
- Herdr's `LICENSE` and `THIRD-PARTY-NOTICES`: this kit does not contain Herdr, but the conditions for using or handing out Herdr are in Herdr's own documents ([18.2](#182-herdr--apache-license-20-confirmed-from-the-installed-files)).
- The license of the Node.js you installed, and the software-installation and security policy of a company or school PC.
- If you add fonts, images, icons, video or audio, or put screen captures in the documents, check the rights to that material and any personal information in it (this repository currently has no such files).

**What you must not do**

- Remove the `LICENSE` or copyright notices and hand it out as if you made it.
- Present it as a tool affiliated with or officially approved by Herdr, Anthropic or OpenAI ([18.4](#184-trademarks)).
- This software is provided "as is" and does not warrant operation or data preservation. If you promise a warranty to a customer, the responsibility lies with the person who promised it.
- Install it on someone else's PC without the owner's consent ([18.5](#185-personal-information-and-other-peoples-computers)).
- Post record or log files that contain session IDs and project names in a public place ([chapter 15](#15-security-and-data-flow)).

### 18.8 Caution about AI-generated content

- The code and documents of this project were written with the help of AI (Claude Code, Anthropic) (confirmed: the Git commit messages contain 20 co-author marks).
- Who owns the copyright of AI-generated output, and whether it is protected at all, differs by country and case and is **uncertain**. This document guarantees no conclusion, and **legal/expert review is needed**.
- Whether the copyright holder notice (`SoDam AI Studio`) matches the real legal rights holder must be checked by the project owner.
- No one else's copyright notice was found in the source, but that is **not a guarantee that all code is original**. Before delivering or selling this project's code or documents commercially, check yourself ① the source ② the possibility of infringement from resembling existing works ③ whether commercial use is allowed. The same applies when you add images, documents or translations made with AI.
- The conversation IDs and folder names in the test files are test values. The 34 real session IDs of this PC were searched for in the repository and in the Git history and found 0 times (the Git history was a sample of 40).
- **Items that need expert review**: ① the ownership of AI-generated output ② whether the copyright holder notice matches the real legal entity ③ whether commercial use and automatic execution are allowed under the terms of Anthropic, OpenAI and Herdr ④ the wording of paid delivery or service contracts ⑤ responsibility for personal-data handling when installing on someone else's or a company PC.

---

## 19. Verification status and known limits

### 19.1 What was confirmed (updated 2026-11-26, development PC)

| Item | Result |
|---|---|
| Full regression tests | **All 22 suites passed** (2026-11-20, run in order in the foreground; run in full again on the development PC on 2026-11-26, and all 694 checks passed). Two earlier full runs the same day failed one check in the "auto-start rule" suite; it was measured to coincide with another program's tests briefly starting app processes (not a keeper behavior problem), and it passed again after the test was fixed. Contract, window logic, robustness, Codex, restore, auto-start rule, install, shortcut, security, app update, etc. |
| Install kit tests | 52 passed (temporary folder, temporary task name, Korean/space paths; check, conflict refusal, install, reinstall, uninstall, refusing a wrong install folder, keeping other files on `-RemoveData`) |
| Shortcut tests | 54 passed (change, reset, remove; refusing clashes, bad keys and special input; read-only file, empty `global`, parallel runs, backup; fake `keys.json` only) |
| Security tests | 34 passed (20 kinds of hostile folder names such as quotes, Unicode quotes, `$()`, backtick, line breaks and 5000 characters do not split the command; conversation-ID format check) |
| Real Herdr window | Opened the real window with `herdr-app do mod.open` and `herdr-app shot` and **confirmed the Restore-pending tab by screenshot** (layout fine, 0 Herdr errors) |
| Marketplace format check | `claude plugin validate` passed (only a "no author information" warning) |
| App update | Fake-app tests + confirmed on a separate test Herdr + the development PC's real Herdr replaced and restarted from 0.1.14→0.1.15 (26 terminals kept) |
| Secret / personal-path scan | 0 hits in the kit's 28 files. Also no secrets, personal e-mail or forbidden files in the whole repository of 90 files and the 24 commits of the Git history as of the 2026-11-26 check (all branches and tags); only two things are flagged: the fake example path `C:\Users\myname` used in the glossary, and 1 detection rule that the kit build tool `build-kit.mjs` itself holds to find personal traces (neither is a real exposure). On 2026-11-26 the 6 record and log files of the development PC were also scanned for key, token, password and private-key patterns, with 0 hits (these files are not uploaded to Git) |

### 19.2 What could not be confirmed (unverified / not run)

- **Installation on another PC**: unverified (only tests imitating it with temporary folders on the development PC).
- **Windows 10**: unverified.
- **Actually running `/plugin marketplace add` · `/plugin install` in Claude Code**: **confirmed on the development PC** (on 2026-11-21 the user added the marketplace and installed 1.1.3 themselves, and a 6-step rehearsal install with the installed folder's install tool, using a temporary folder and a temporary task name, passed all 19 checks while the real Session Keeper, watchdog task and `keys.json` stayed unchanged). **Unverified on another PC**.
- **Button clicks and broken layouts (responsive) in the Session Keeper window**: the Restore-pending tab was confirmed by a real window screenshot, but the **shortcut panel, the Open-windows and Dead-sessions tabs, the button click behavior and narrow windows (a line with many chips may be cut off) are unverified**.
- **Real installation of the launcher/shortcuts**: not run (only one check with temporary shortcuts).
- **Codex screen matching**: only fake-data tests. Unverified on a real Codex window.
- **"Restore all" after a real reboot**: **on the development PC all 3 real reboots were judged a pass** (most recent 2026-11-22: 29 of the 29 windows recorded before the reboot were restored, 0 failures). **Unverified on another PC**.
- **Restoring through `codex resume`**: not confirmed by a real reboot test (the empty-shell typing and new-tab paths were confirmed with an isolated Herdr restart test).
- **Whether the update process dies together with the window closing**: not settled (even if it dies, the keeper starts the app instead after 20 seconds).
- **Intermittent test failure**: on 2026-11-20 the "auto-start rule" test sometimes failed when it overlapped with another program's tests (it counted app processes once; fixed), and I could not deliberately reproduce it with the old method. The 2026-11-16 intermittent failure of the fake-app new-window test has an unconfirmed cause (it is a fake program for tests and unrelated to the real Herdr). During the 2026-11-26 full run the "app update" suite failed intermittently twice, but it did not reproduce in a standalone run (26/26) or in 3 re-runs under CPU load (all 26/26); the cause is **presumed** to be a fixed 0.8-second wait, so it now checks the real state for up to 10 seconds. A wrongly displayed summary line of the "old pid reuse" test was fixed the same day (the checks themselves are unchanged). The fixes to these two test files are included in this repository's test files (`tests\appupdate.test.ps1`, `tests\pidreuse.test.ps1`), and running them directly in this repository passed 26/26 and 11/11 respectively. **While testing kit 1.1.4 on 2026-11-26 the "install kit" suite failed intermittently, and the cause is unverified.** In 2 full runs and 4 standalone runs, 1 to 4 of the 57 checks failed (the install folder was left after uninstalling with `-RemoveData` and the following fresh-install and re-install checks failed; once the check that a changed shortcut is kept on re-install failed). There were also several runs of the same code that passed 57/57. In the last full run (only logging that records the moment of failure was added; the checks were the same) all 22 suites passed, but the failure did not reappear then, so the cause was not captured. Because the program files are the same as 1.1.3, the possibility that the same thing rarely happens in 1.1.3 cannot be ruled out. If the install folder is still there after uninstalling, check what is inside it.
- **Keeper log line `루프 오류(계속 진행): null 값 식에서 메서드를 호출할 수 없습니다` (loop error, continuing: cannot call a method on a null value)**: as of 2026-11-26 it has been logged 32 times in total (6 short bursts), the last on 2026-11-24 16:49:29. Each time the keeper logged the error and kept running, the records were preserved, and later restores were normal. However the log does not record the line number where the error occurred, so the **cause is unverified**.
- **Whether Herdr recognizes a changed shortcut immediately**: unverified (if not, close and reopen Herdr).
- **Folder permissions**: if you install on a place such as drive D: with `-InstallDir`, the folder may be writable by "all users". The default location (`%LOCALAPPDATA%`) is current-user only ([15.4](#154-security-cautions)).
- lint / type check / build / e2e / browser tests: **not run**, because this project has no such tools.

### 19.3 Known limits

- If the computer loses power suddenly, a **session started within the last minute** may not be in the records.
- During an app update, **old files that no longer exist in the new version are not removed.**
- The possibility of Claude's automatic deletion of old conversation files ([FAQ Q10](#17-faq)).
- When there are several Codex windows in the same folder, some may not show an ID.
- Closing 6 or more windows on purpose at once may look like an accident.
- The **App update** and **Automatic update** buttons of the Session Keeper window are close together, so a mis-click is possible.
- While a long restore is running, the check record (heartbeat) is not refreshed, so a log may show the watchdog starting a helper keeper that then exits immediately (observed twice, harmless).

---

## 20. Uninstall and rollback

### 20.1 Uninstall

```
powershell -NoProfile -ExecutionPolicy Bypass -File plugins\herdr-session-keeper\uninstall.ps1 [-InstallDir path] [-HerdrHome path] [-TaskName name] [-RemoveData]
```

| What it removes | Condition |
|---|---|
| Launcher disconnection (shortcuts restored) | If the launcher was installed |
| Task Scheduler task | **Only if it points to this install** (left alone if it points elsewhere) |
| The keeper process of this install | Always |
| `Ctrl+Shift+R` binding + `mods\session-keeper` | **Only if the mod points to this install** |
| Program files | Always (restore records and logs are **kept**). With `-RemoveData` the files Session Keeper created (including restore records and logs) are deleted too, and if the folder holds **other files, those files and the folder are left alone** (only when an install record exists) |

It does not touch the Herdr app, terminals, other mods or Claude/Codex conversation records.

**Good to know**: the uninstall tool `uninstall.ps1` is not copied into the install folder; it is in `plugins\herdr-session-keeper\` of the kit folder (if you installed through the marketplace, under the Claude Code settings folder at `plugins\cache\herdr-session-keeper-market\herdr-session-keeper\<version>\`). A default uninstall (without `-RemoveData`) also deletes `_backup\` (the backup for rolling back an app update) and `lib\`, so if you might need to roll back, copy `_backup\<time>\` somewhere else before uninstalling. `shortcut-backup\` is deleted only with `-RemoveData`. Even if you changed the shortcut, all Session Keeper binding lines (`mod.open:session-keeper`) are removed.

### 20.2 Rolling back individual parts

| What to roll back | How |
|---|---|
| Only the automatic start | `schtasks /Delete /TN "HerdrSessionKeeper-Watchdog" /F` |
| Automatic app update | `session-keeper.ps1 -Mode Update -Auto Off` |
| Shortcuts | `session-keeper.ps1 -Mode Update -Launcher Uninstall` (backup `shortcut-backup\`) |
| `keys.json` | Copy the backup `keys.json.bak-before-session-keeper-kit` to `keys.json` |
| Items removed from the restore list | Copy the backup `session-map.json.before-forget-old-<time>` to `session-map.json` |
| Herdr app update | Go back using the files of the `herdr-app.backup-<version>-<time>` folder (after closing Herdr) |
| Program update | Copy files from `_backup\<time>\` in the install folder |

---

*This document records only facts confirmed directly during development. What could not be confirmed is marked "unverified / not run", and the legal content is for reference only.*
