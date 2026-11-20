﻿# 설치 꾸러미 시험: build-kit -> install(-Check/충돌 거부/설치/재설치/-NoTask) -> 설치본 동작 -> uninstall.
# 임시 폴더 + 임시 Herdr 설정 폴더 + 임시 작업 이름만 쓴다. 이 PC 의 실제 세션키퍼·모드·작업·바로가기는 건드리지 않는다.
# (경로에 한글·공백을 넣어 "폴더/컴퓨터가 달라도" 되는지 본다). 마지막 줄 "합계: PASS n / FAIL m" 형식은 run-all 이 읽는다.
$ErrorActionPreference = 'Continue'
$src = Split-Path -Parent $PSScriptRoot
$T = Join-Path $env:TEMP ("kit-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $T -Force | Out-Null
$script:pass = 0; $script:fail = 0
function Check([string]$n, $c) { if ($c) { $script:pass++; "PASS  $n" } else { $script:fail++; "FAIL  $n" } }
$realApp = Join-Path $env:LOCALAPPDATA 'Programs\herdr-app\herdr-app.exe'
if (-not (Test-Path -LiteralPath $realApp)) { "SKIP  Herdr 앱이 없는 PC 라 설치 시험을 건너뜁니다"; "합계: PASS 0 / FAIL 0"; Remove-Item -LiteralPath $T -Recurse -Force; exit 0 }

$kitOut = Join-Path $T 'kit'
$b = & node (Join-Path $src 'build-kit.mjs') $kitOut 2>&1 | Out-String
Check 'build-kit: 꾸러미 생성(개인 경로 검사 통과)' ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $kitOut '.claude-plugin\marketplace.json')))
$pl = Join-Path $kitOut 'plugins\herdr-session-keeper'
$mk = Get-Content (Join-Path $kitOut '.claude-plugin\marketplace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$pj = Get-Content (Join-Path $pl '.claude-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check '마켓플레이스: 플러그인 항목의 source 폴더가 실제로 있고 이름이 plugin.json 과 같다' ($mk.plugins[0].name -eq $pj.name -and (Test-Path (Join-Path $kitOut ($mk.plugins[0].source -replace '^\./', ''))))
Check '스킬 파일에 name/description 머리말이 있다' ((Get-Content (Join-Path $pl 'skills\herdr-session-keeper\SKILL.md') -Raw -Encoding UTF8) -match '(?s)^---\s*\r?\nname: herdr-session-keeper\r?\ndescription: .+?\r?\n---')
$ib = [IO.File]::ReadAllBytes((Join-Path $pl 'install.ps1'))
Check 'install.ps1 은 UTF-8 BOM (한글이 5.1 에서 안 깨짐)' ($ib[0] -eq 0xEF -and $ib[1] -eq 0xBB -and $ib[2] -eq 0xBF)
foreach ($f in @('install.ps1', 'uninstall.ps1', 'payload\session-keeper.ps1', 'payload\lib\appupdate.ps1', 'payload\herdr-launch.ps1')) { $e = $null; $tk = $null; [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $pl $f), [ref]$tk, [ref]$e); Check "문법 오류 없음: $f" (@($e).Count -eq 0) }

# 임시 Herdr 설정 폴더(실제 keys.json 흉내)
$hh = Join-Path $T 'herdrhome'; New-Item -ItemType Directory -Path (Join-Path $hh 'mods') -Force | Out-Null
$keys = Join-Path $hh 'keys.json'
[IO.File]::WriteAllText($keys, "{`r`n    `"global`": {`r`n        `"ctrl-shift-p`": `"palette.open`"`r`n    }`r`n}`r`n", (New-Object Text.UTF8Encoding($false)))
$tn = 'HerdrKitTest-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$inst = Join-Path $T '설치 폴더 1\앱'            # 한글 + 공백 경로
function RunInstall([string[]]$extra) {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pl 'install.ps1') -InstallDir $inst -HerdrHome $hh -HerdrApp $realApp -TaskName $tn @extra 2>&1 | Out-String
    return [pscustomobject]@{ code = $LASTEXITCODE; out = $o }
}

# 1) 점검만: 아무것도 만들지 않는다
$r = RunInstall @('-Check')
Check '-Check: 성공 코드 + 설치 위치를 만들지 않음' ($r.code -eq 0 -and -not (Test-Path -LiteralPath $inst) -and -not (Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue))

# 2) 다른 위치의 기존 모드가 있으면 덮어쓰지 않고 멈춘다
$fake = Join-Path $hh 'mods\session-keeper'; New-Item -ItemType Directory -Path $fake -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $fake 'main.js'), 'const TOOL = "X:/other/place/sessions.mjs";', (New-Object Text.UTF8Encoding($false)))
$r = RunInstall @()
Check '다른 위치의 기존 설치 -> 덮어쓰지 않고 중단(코드 1)' ($r.code -eq 1 -and $r.out -match '덮어쓰지' -and (Get-Content (Join-Path $fake 'main.js') -Raw) -match 'X:/other')
Check '중단했으니 설치 위치·작업이 생기지 않음' (-not (Test-Path -LiteralPath $inst) -and -not (Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue))
Remove-Item -LiteralPath $fake -Recurse -Force

# 3) 설치
$r = RunInstall @()
Check '설치: 성공 코드' ($r.code -eq 0)
if ($r.code -ne 0) { "  (진단) " + $r.out }
foreach ($f in @('session-keeper.ps1', 'sessions.mjs', 'scan-monitors.mjs', 'session-keeper-watchdog.vbs', 'herdr-launch.ps1', 'lib\appupdate.ps1', 'lib\claude.mjs', 'kit.env', 'kit.install.json')) { Check "설치 파일: $f" (Test-Path -LiteralPath (Join-Path $inst $f)) }
$kenv = Get-Content (Join-Path $inst 'kit.env') -Raw
Check 'kit.env: NODE_DIR 기록, 기본 위치가 아닌 HERDR 설정 폴더는 APP_HOME 으로 기록' ($kenv -match 'NODE_DIR=' -and $kenv -match [regex]::Escape("APP_HOME=$hh"))
$mj = [IO.File]::ReadAllText((Join-Path $hh 'mods\session-keeper\main.js'), [Text.Encoding]::UTF8)
$toolWant = ((Join-Path $inst 'sessions.mjs') -replace '\\', '/')
Check '모드 main.js: const TOOL 이 설치 위치(한글·공백 경로)로 바뀜' ($mj.Contains('const TOOL = "' + $toolWant + '";'))
Check '모드 main.js: const NODE 가 node 절대 경로로 바뀜' ($mj -match 'const NODE = "[A-Za-z]:/[^"]+node\.exe";')
Check '모드 main.js: 이 PC 의 개발 폴더 경로가 없다' (-not $mj.Contains(($src -replace '\\', '/')))
$kj = [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8); $kok = $true; try { $kobj = $kj | ConvertFrom-Json } catch { $kok = $false }
Check 'keys.json: Ctrl+Shift+R 한 줄 추가, 올바른 JSON, 기존 키 유지, 백업 생성' ($kok -and $kj.Contains('"ctrl-shift-r": "mod.open:session-keeper"') -and $kj.Contains('palette.open') -and (Test-Path "$keys.bak-before-session-keeper-kit"))
$tk2 = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
Check '작업 스케줄러: 임시 이름 작업이 설치 위치의 watchdog 을 가리킴' ($null -ne $tk2 -and (($tk2.Actions | ForEach-Object { $_.Arguments }) -join ' ') -like "*$inst*session-keeper-watchdog.vbs*")
$mf = Get-Content (Join-Path $inst 'kit.install.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check '설치 기록(kit.install.json): 위치·작업 이름 일치' ($mf.installDir -eq $inst -and $mf.taskName -eq $tn)

# 4) 설치본이 이 PC 의 개발 폴더와 무관하게 동작
$o = & node (Join-Path $inst 'sessions.mjs') update-state 2>&1 | Out-String
$us = $null; try { $us = $o | ConvertFrom-Json } catch {}
Check '설치본 sessions.mjs update-state 가 JSON(kind)을 돌려줌' ($null -ne $us -and $null -ne $us.kind)
$cc = Join-Path $T 'cc'; New-Item -ItemType Directory -Path (Join-Path $cc 'sessions') -Force | Out-Null
$p1 = (& node -e "import(process.argv[1]).then(m=>console.log(m.sessDir()))" ('file:///' + ((Join-Path $inst 'lib\claude.mjs') -replace '\\', '/')) 2>&1 | Out-String).Trim()
Check 'Claude 폴더 규칙: 이 PC 환경(기존 %APPDATA%\claude-code)에서 그 폴더를 가리킴' ($p1 -like '*claude-code\sessions' -or $p1 -like '*\.claude\sessions')
$env:CLAUDE_CONFIG_DIR = $cc
$p2 = (& node -e "import(process.argv[1]).then(m=>console.log(m.sessDir()))" ('file:///' + ((Join-Path $inst 'lib\claude.mjs') -replace '\\', '/')) 2>&1 | Out-String).Trim()
Remove-Item Env:CLAUDE_CONFIG_DIR
Check 'CLAUDE_CONFIG_DIR 이 있으면 그 폴더를 우선' ($p2 -eq (Join-Path $cc 'sessions'))
$saveA = $env:APPDATA; $saveU = $env:USERPROFILE
$env:APPDATA = Join-Path $T 'noapp'; $env:USERPROFILE = Join-Path $T 'newpc'
$p3 = (& node -e "import(process.argv[1]).then(m=>console.log(m.sessDir()))" ('file:///' + ((Join-Path $inst 'lib\claude.mjs') -replace '\\', '/')) 2>&1 | Out-String).Trim()
$env:APPDATA = $saveA; $env:USERPROFILE = $saveU
Check '새 PC 흉내(기존 폴더 없음): ~\.claude\sessions 로 간다' ($p3 -eq (Join-Path (Join-Path $T 'newpc') '.claude\sessions'))
$offf = Join-Path $inst 'session-keeper.appupdate.off'
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $inst 'session-keeper.ps1') -Mode Update -Auto Off 2>&1
$offOk = Test-Path -LiteralPath $offf
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $inst 'session-keeper.ps1') -Mode Update -Auto On 2>&1
Check '설치본 키퍼: 자동 업데이트 끄기(.off 생성) -> 켜기(.off 제거)가 설치 폴더 안에서 동작' ($offOk -and -not (Test-Path -LiteralPath $offf))
$vo = & cscript //nologo (Join-Path $inst 'session-keeper-watchdog.vbs') 2>&1 | Out-String
$env:HERDR_WATCHDOG_DRY = '1'; $vo = & cscript //nologo (Join-Path $inst 'session-keeper-watchdog.vbs') 2>&1 | Out-String; Remove-Item Env:HERDR_WATCHDOG_DRY
Check 'watchdog: 폴더 기준 경로로 키퍼를 찾음(시험 모드: WOULD-START 또는 SKIP)' ($vo -match 'WOULD-START|SKIP-ALIVE|SKIP-APP-DOWN')

# 5) 재설치(업데이트): 중복 없이, 옛 파일 백업
$r = RunInstall @('-NoKey')
$kj2 = [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8)
Check '재설치: 성공 + 키 연결 한 줄만 유지 + 옛 프로그램 백업 생성' ($r.code -eq 0 -and ([regex]::Matches($kj2, 'mod\.open:session-keeper')).Count -eq 1 -and (Test-Path (Join-Path $inst '_backup')))

# 5b) 단축키 변경: 설치 폴더에 set-key.ps1, -Key 로 바꾸기, 안 주면 유지, 겹치거나 못 쓰는 키는 설치 전에 거부
Check '설치본에 set-key.ps1 이 들어 있다' (Test-Path -LiteralPath (Join-Path $inst 'set-key.ps1'))
$kb = [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8)
$r = RunInstall @('-Key', 'palette.open')
Check '못 쓰는 -Key 는 설치 전에 거부(코드 1), keys.json 불변' ($r.code -eq 1 -and $r.out -match 'palette\.open' -and [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8) -eq $kb)
$r = RunInstall @('-Key', 'ctrl-shift-p')
Check '다른 기능과 겹치는 -Key 는 설치 전에 거부(코드 1), keys.json 불변' ($r.code -eq 1 -and [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8) -eq $kb)
$r = RunInstall @('-Key', 'ctrl-alt-r')
$kj4 = [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8)
$mf4 = Get-Content (Join-Path $inst 'kit.install.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check '-Key ctrl-alt-r 로 재설치: 키가 바뀌고(옛 ctrl-shift-r 연결 제거) 연결 줄은 1개, 설치 기록에 key 기록' ($r.code -eq 0 -and $kj4.Contains('"ctrl-alt-r": "mod.open:session-keeper"') -and -not $kj4.Contains('"ctrl-shift-r"') -and ([regex]::Matches($kj4, 'mod\.open:session-keeper')).Count -eq 1 -and $mf4.key -eq 'ctrl-alt-r')
$r = RunInstall @()
Check '-Key 없이 다시 설치해도 바꾼 키(ctrl-alt-r)를 유지' ($r.code -eq 0 -and [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8) -eq $kj4)

# 5c) 폴더를 옮긴 뒤 다시 설치(2026-11-20 이식성 점검): 옛 위치에 파일이 없으면 -Force 없이 새 위치로 다시 연결한다
$instMoved = Join-Path $T '옮긴 설치 폴더\새 앱'
New-Item -ItemType Directory -Path (Split-Path -Parent $instMoved) -Force | Out-Null
$mvOk = $false; for ($i = 0; $i -lt 8 -and -not $mvOk; $i++) { try { Move-Item -LiteralPath $inst -Destination $instMoved -ErrorAction Stop; $mvOk = $true } catch { Start-Sleep -Seconds 1 } }
Check '준비: 설치 폴더를 통째로 옮김' $mvOk
$inst = $instMoved
$r = RunInstall @('-NoKey')
$mj5 = [IO.File]::ReadAllText((Join-Path $hh 'mods\session-keeper\main.js'), [Text.Encoding]::UTF8)
$tk5 = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
Check '폴더를 옮긴 뒤 재설치: -Force 없이 성공하고 옮긴 것을 안내' ($r.code -eq 0 -and $r.out -match '폴더를 옮기신')
Check '폴더를 옮긴 뒤 재설치: 모드·작업이 새 위치를 가리킴' ($mj5.Contains('const TOOL = "' + ((Join-Path $inst 'sessions.mjs') -replace '\\', '/') + '";') -and $null -ne $tk5 -and (($tk5.Actions | ForEach-Object { $_.Arguments }) -join ' ') -like "*$inst*session-keeper-watchdog.vbs*")
# Herdr 앱 위치 재탐색: kit.env 의 APP_EXE 가 사라진 위치여도 키퍼가 기본 위치·실행 중인 앱에서 다시 찾는다. 호출한 쪽이 직접 정한 값(KEEPER_APP_EXE)은 존중한다.
[IO.File]::AppendAllText((Join-Path $inst 'kit.env'), "APP_EXE=$T\없는 폴더\herdr-app.exe`r`n")
$skp = Join-Path $inst 'session-keeper.ps1'
$cmdA = "Get-ChildItem Env: | Where-Object { `$_.Name -in 'KEEPER_APP_EXE','HERDR_APP_HOME','CLAUDE_CONFIG_DIR' } | ForEach-Object { Remove-Item -LiteralPath ('Env:' + `$_.Name) }; `$env:KEEPER_NO_MAIN='1'; . '$skp' -Mode Run | Out-Null; 'APPEXE=' + `$AppExe"
$oA = (& powershell -NoProfile -ExecutionPolicy Bypass -Command $cmdA 2>&1 | Out-String)
$gotA = (($oA -split "\r?\n" | Where-Object { $_ -like 'APPEXE=*' } | Select-Object -Last 1) -replace '^APPEXE=', '').Trim()
Check 'kit.env 의 앱 위치가 사라졌으면 키퍼가 실제 앱 위치로 다시 찾음' ($gotA -ieq $realApp) $oA
$cmdB = "Get-ChildItem Env: | Where-Object { `$_.Name -in 'HERDR_APP_HOME','CLAUDE_CONFIG_DIR' } | ForEach-Object { Remove-Item -LiteralPath ('Env:' + `$_.Name) }; `$env:KEEPER_APP_EXE='$T\호출자가 정함\herdr-app.exe'; `$env:KEEPER_NO_MAIN='1'; . '$skp' -Mode Run | Out-Null; 'APPEXE=' + `$AppExe"
$oB = (& powershell -NoProfile -ExecutionPolicy Bypass -Command $cmdB 2>&1 | Out-String)
$gotB = (($oB -split "\r?\n" | Where-Object { $_ -like 'APPEXE=*' } | Select-Object -Last 1) -replace '^APPEXE=', '').Trim()
Check '호출한 쪽이 KEEPER_APP_EXE 를 직접 정했으면 없어도 그대로 존중(시험이 진짜 앱으로 새지 않음)' ($gotB -ieq "$T\호출자가 정함\herdr-app.exe") $oB

# 6) 제거(데이터 보존) -> 전체 삭제
[IO.File]::WriteAllText((Join-Path $inst 'session-map.json'), '{}')
$u = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pl 'uninstall.ps1') -InstallDir $inst -HerdrHome $hh 2>&1 | Out-String
$kj3 = [IO.File]::ReadAllText($keys, [Text.Encoding]::UTF8); $k3ok = $true; try { $null = $kj3 | ConvertFrom-Json } catch { $k3ok = $false }
Check '제거: 작업·모드·키 연결 제거, keys.json 은 올바른 JSON 이고 기존 키 유지' (-not (Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $hh 'mods\session-keeper')) -and $k3ok -and -not $kj3.Contains('mod.open:session-keeper') -and $kj3.Contains('palette.open'))
Check '제거: 프로그램 파일은 지우고 복구 기록(session-map.json)은 남김' (-not (Test-Path (Join-Path $inst 'session-keeper.ps1')) -and (Test-Path (Join-Path $inst 'session-map.json')))
$r = RunInstall @('-NoTask')
Check '-NoTask 설치: 성공 + 작업 없음' ($r.code -eq 0 -and -not (Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue))
$u = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pl 'uninstall.ps1') -InstallDir $inst -HerdrHome $hh -RemoveData 2>&1 | Out-String
Check '-RemoveData: 설치 폴더 전체 삭제' (-not (Test-Path -LiteralPath $inst))
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pl 'uninstall.ps1') -InstallDir (Join-Path $T 'never') -HerdrHome $hh 2>&1
Check '설치된 적 없는 위치를 제거해도 안전하게 끝남(성공 코드, 아무것도 만들지 않음)' ($LASTEXITCODE -eq 0 -and -not (Test-Path (Join-Path $T 'never')))

# 7) 안전 장치(2026-11-16 보안 점검): 남의 파일이 든 폴더·드라이브 루트에는 설치하지 않고, -RemoveData 는 남의 파일을 지우지 않는다
$instKeep = $inst
$vic = Join-Path $T '내 문서(소중한 파일)'; New-Item -ItemType Directory -Path (Join-Path $vic 'photos') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $vic 'thesis.txt'), 'IRREPLACEABLE'); [IO.File]::WriteAllText((Join-Path $vic 'photos\a.jpg'), 'IMG')
$inst = $vic
$r = RunInstall @('-NoTask', '-NoKey')
Check '남의 파일이 든 폴더에는 설치하지 않고 중단(코드 1), 파일 그대로, 우리 파일 안 만듦' ($r.code -eq 1 -and (Test-Path (Join-Path $vic 'thesis.txt')) -and (Test-Path (Join-Path $vic 'photos\a.jpg')) -and -not (Test-Path (Join-Path $vic 'kit.env')) -and -not (Test-Path (Join-Path $vic 'session-keeper.ps1')))
$r = RunInstall @('-Check')
Check '-Check 도 같은 이유로 알려 준다(코드 1)' ($r.code -eq 1)
$inst = (Split-Path -Qualifier $T) + '\'
$r = RunInstall @('-Check')
Check '드라이브 루트에는 설치하지 않는다(코드 1)' ($r.code -eq 1)
$inst = $instKeep
$r = RunInstall @('-NoTask', '-NoKey')
Check '전용 새 폴더에는 정상 설치' ($r.code -eq 0 -and (Test-Path (Join-Path $inst 'kit.env')))
$r = RunInstall @('-NoTask', '-NoKey')
Check '같은 폴더에 다시 설치(업데이트)는 그대로 된다' ($r.code -eq 0)
[IO.File]::WriteAllText((Join-Path $inst 'my-notes.txt'), 'KEEP'); New-Item -ItemType Directory -Path (Join-Path $inst 'my-folder') -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $inst 'my-folder\x.txt'), 'KEEP2')
[IO.File]::WriteAllText((Join-Path $inst 'session-map.json'), '{}')
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pl 'uninstall.ps1') -InstallDir $inst -HerdrHome $hh -TaskName $tn -RemoveData 2>&1
Check '-RemoveData: 세션키퍼 파일·복구 기록은 지우고, 남의 파일·폴더는 그대로 두며 폴더도 남김' (-not (Test-Path (Join-Path $inst 'kit.env')) -and -not (Test-Path (Join-Path $inst 'session-map.json')) -and -not (Test-Path (Join-Path $inst 'lib')) -and (Test-Path (Join-Path $inst 'my-notes.txt')) -and (Test-Path (Join-Path $inst 'my-folder\x.txt')) -and (Test-Path $inst))

Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
"합계: PASS $script:pass / FAIL $script:fail"
if ($script:fail -gt 0) { exit 1 }
