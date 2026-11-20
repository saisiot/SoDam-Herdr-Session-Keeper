# 창 안 Claude/Codex 탐지와 복구 시도 횟수 판단 시험 (2026-11-18 근본 원인 수정)
#  - hc 는 창 정보에 pid(창의 뿌리 셸)와 foreground.pid(지금 앞에서 도는 프로그램)를 따로 준다. Claude 가 앞에서 돌면 foreground.pid 는 claude 자신이다.
#    예전 코드는 foreground.pid 를 "셸"로 가정해 자식만 찾아서, 실제 hc 형식에서는 열린 Claude 를 하나도 못 찾았다(기록 정지, 복구 확인 실패, 시도 99 잠금).
#  - 시도 횟수 99(영구 잠금)는 더 이상 쓰지 않는다: 시도 횟수는 한도(3)까지만 세고, 예전 기록의 99 는 "1번 시도함"으로 읽는다.
# 가짜 프로세스 표·가짜 hc 정보만 쓰고 아무것도 실행하지 않는다. 쓰기 시험은 임시 폴더의 키퍼 사본에서만 한다.
# 마지막 줄 "합계: PASS n / FAIL m" 형식은 run-all 이 읽는다.
$ErrorActionPreference = 'Continue'
$env:KEEPER_NO_MAIN = '1'
$srcDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $srcDir 'session-keeper.ps1')
$script:pass = 0; $script:fail = 0
# 검사식은 스크립트블록으로 받아 try/catch 로 실행한다: 함수가 없거나 오류가 나도 "검사가 조용히 빠지는" 일 없이 FAIL 로 센다
function Check([string]$n, [scriptblock]$c) { $ok = $false; try { $ok = [bool](& $c) } catch { $ok = $false }; if ($ok) { $script:pass++; "PASS  $n" } else { $script:fail++; "FAIL  $n" } }

# ---- 가짜 프로세스 표
$kids = @{}
function Link([int]$parent, [int]$child) { if (-not $kids.ContainsKey($parent)) { $kids[$parent] = New-Object System.Collections.ArrayList }; [void]$kids[$parent].Add($child) }
$sidA = '01234567-89ab-cdef-0123-456789abcdef'; $sidB = '11111111-2222-3333-4444-555555555555'
$sess = @{ 200 = [pscustomobject]@{ pid = 200; sessionId = $sidA; cwd = 'C:\work' }; 250 = [pscustomobject]@{ pid = 250; sessionId = $sidB; cwd = 'C:\work' } }
Link 100 200            # 창1: 뿌리 셸 100 -> claude 200
Link 110 150; Link 150 250   # 창2: 뿌리 셸 110 -> node 150 -> claude 250 (손자)
$win = { param($rootPid, $fgPid, $fgName) [pscustomobject]@{ pid = $rootPid; state = 'live'; foreground = [pscustomobject]@{ pid = $fgPid; name = $fgName }; labels = [pscustomobject]@{ where = '공간 / 탭' } } }

# 1) 지금 hc 형식: 맨 앞 프로세스가 claude 자신(foreground.pid=200), 뿌리 셸은 pid=100
$g1 = & $win 100 200 'claude.exe'
Check '현재 hc 형식(맨 앞이 claude): 뿌리 셸 아래에서 찾는다' { (Find-ClaudeInWindow $g1 $kids $sess).sessionId -eq $sidA }
Check '(참고) 옛 방식 Find-ClaudeUnder(foreground.pid)는 못 찾는다 = 결함 재현' { $null -eq (Find-ClaudeUnder 200 $kids $sess) }
# 2) 옛 hc 형식: pid 없음, foreground = 셸
$g2 = [pscustomobject]@{ state = 'live'; foreground = [pscustomobject]@{ pid = 100; name = 'powershell.exe' } }
Check '옛 hc 형식(foreground=셸, pid 없음)도 찾는다' { (Find-ClaudeInWindow $g2 $kids $sess).sessionId -eq $sidA }
# 3) 뿌리 pid 정보가 없고 맨 앞이 곧 claude
$g3 = [pscustomobject]@{ state = 'live'; foreground = [pscustomobject]@{ pid = 200; name = 'claude.exe' } }
Check '뿌리 pid 없이 맨 앞 프로그램이 곧 Claude 세션이면 그 세션' { (Find-ClaudeInWindow $g3 $kids $sess).sessionId -eq $sidA }
# 4) 손자 단계(node 래퍼 아래)
$g4 = & $win 110 250 'claude.exe'
Check 'node 래퍼 아래(손자) Claude 도 찾는다' { (Find-ClaudeInWindow $g4 $kids $sess).sessionId -eq $sidB }
# 5) 빈 셸: 자식 없음
$g5 = & $win 120 120 'powershell.exe'
Check '빈 셸 창에서는 아무것도 찾지 않는다' { $null -eq (Find-ClaudeInWindow $g5 $kids $sess) }
# 6) 남의 창의 Claude 를 가져오지 않는다
$g6 = & $win 130 130 'powershell.exe'
Check '다른 창의 Claude(200, 250)를 이 창의 것으로 착각하지 않는다' { $null -eq (Find-ClaudeInWindow $g6 $kids $sess) }
# 7) 이상한 입력
Check 'pid 가 전혀 없는 창 정보는 안전하게 못 찾음 처리' { $null -eq (Find-ClaudeInWindow ([pscustomobject]@{ state = 'live' }) $kids $sess) }
Check 'Test-HasWindowPid: pid 만 / foreground 만 / 둘 다 없음' { (Test-HasWindowPid $g1) -and (Test-HasWindowPid $g3) -and -not (Test-HasWindowPid ([pscustomobject]@{ state = 'live' })) -and -not (Test-HasWindowPid $null) }

# 8) Codex: 맨 앞이 codex 자신 / 셸 아래 / app-server 는 제외
$script:ProcInfo = @{
    400 = @{ name = 'codex.exe'; cmd = 'codex.exe'; created = (Get-Date); ppid = 300 }
    410 = @{ name = 'codex.exe'; cmd = 'codex.exe app-server'; created = (Get-Date); ppid = 310 }
}
Link 300 400; Link 310 410
$c1 = & $win 300 400 'codex.exe'
Check 'Codex: 맨 앞이 codex 자신이어도 뿌리 셸 아래에서 찾는다' { $null -ne (Find-CodexInWindow $c1 $kids) }
$c2 = [pscustomobject]@{ state = 'live'; foreground = [pscustomobject]@{ pid = 400; name = 'codex.exe' } }
Check 'Codex: 뿌리 pid 없이 맨 앞이 곧 codex 이면 찾는다' { $null -ne (Find-CodexInWindow $c2 $kids) }
$c3 = & $win 310 410 'codex.exe'
Check 'Codex: app-server 같은 보조 프로세스는 대화창으로 보지 않는다' { $null -eq (Find-CodexInWindow $c3 $kids) }
Check 'Codex: 빈 셸은 못 찾음' { $null -eq (Find-CodexInWindow $g5 $kids) }

# 9) 시도 횟수: 99(옛 영구 잠금)는 1번 시도한 것으로 읽는다
Check 'Get-EffAttempts: 0/2/3 은 그대로' { (Get-EffAttempts ([pscustomobject]@{ attempts = 0 })) -eq 0 -and (Get-EffAttempts ([pscustomobject]@{ attempts = 2 })) -eq 2 -and (Get-EffAttempts ([pscustomobject]@{ attempts = 3 })) -eq 3 }
Check 'Get-EffAttempts: 옛 99/100 은 1' { (Get-EffAttempts ([pscustomobject]@{ attempts = 99 })) -eq 1 -and (Get-EffAttempts ([pscustomobject]@{ attempts = 100 })) -eq 1 }
Check 'Get-EffAttempts: 없음/이상한 값은 0' { (Get-EffAttempts ([pscustomobject]@{ x = 1 })) -eq 0 -and (Get-EffAttempts ([pscustomobject]@{ attempts = 'abc' })) -eq 0 -and (Get-EffAttempts $null) -eq 0 }

# 10) 복구 판단(Get-Decision): 빈 셸 + 시도 횟수 + 방금 입력 대기
$ctx = { @{ Running = @{}; AllowCreate = $true; JsonlOk = $true; HasClaude = $false; LastLine = 'PS C:\Users\x>'; MaxAttempts = 3; CheckFile = $false } }
$gEmpty = [pscustomobject]@{ state = 'live'; foreground = [pscustomobject]@{ pid = 5; name = 'powershell.exe' }; labels = [pscustomobject]@{ 'herdr.tab' = 'tb1'; where = '공간 / 탭' } }
$ent = { param($att, $typedAt) $o = [pscustomobject]@{ addr = 't9'; where = '공간 / 탭'; tabId = 'tb1'; sid = $sidA; attempts = $att }; if ($typedAt) { $o | Add-Member -NotePropertyName typedAt -NotePropertyValue $typedAt }; $o }
Check '시도 0: 빈 셸에 입력(TYPE)' { (Get-Decision (& $ent 0 $null) $gEmpty (& $ctx)).Action -eq 'TYPE' }
Check '시도 99(옛 잠금): 이제 잠기지 않고 빈 셸에 다시 입력(TYPE)' { (Get-Decision (& $ent 99 $null) $gEmpty (& $ctx)).Action -eq 'TYPE' }
Check '시도 3: 한도 초과로 건너뜀' { (Get-Decision (& $ent 3 $null) $gEmpty (& $ctx)).Action -eq 'SKIP' }
$recent = (Get-Date).AddSeconds(-20).ToString('yyyy-MM-ddTHH:mm:ss'); $old = (Get-Date).AddMinutes(-10).ToString('yyyy-MM-ddTHH:mm:ss')
$dRecent = Get-Decision (& $ent 1 $recent) $gEmpty (& $ctx)
Check '방금(20초 전) 입력했으면 확인을 기다리며 건너뜀(같은 창에 두 번 입력 방지), 나중에 다시 볼 대상' { $dRecent.Action -eq 'SKIP' -and $dRecent.Retry -eq $true }
Check '10분 전에 입력했는데 지금 빈 셸이면 다시 입력' { (Get-Decision (& $ent 1 $old) $gEmpty (& $ctx)).Action -eq 'TYPE' }
$cRun = & $ctx; $cRun.Running[$sidA] = $true
Check '같은 대화가 이미 실행 중이면 시도 횟수와 상관없이 건너뜀' { (Get-Decision (& $ent 0 $null) $gEmpty $cRun).Action -eq 'SKIP' }
Check '대화 ID 끝에 줄바꿈이 붙은 기록은 형식 오류로 건너뜀' { (Get-Decision ([pscustomobject]@{ addr = 't9'; sid = ($sidA + "`n"); attempts = 0 }) $gEmpty (& $ctx)).Action -eq 'SKIP' }
$gBusy = [pscustomobject]@{ state = 'live'; foreground = [pscustomobject]@{ pid = 7; name = 'claude.exe' }; labels = [pscustomobject]@{ 'herdr.tab' = 'tb1'; where = '공간 / 탭' } }
Check '앞 프로그램이 claude 면(시작 중) 입력하지 않음' { (Get-Decision (& $ent 1 $null) $gBusy (& $ctx)).Action -eq 'SKIP' }

# 10-b) Herdr 가 앱을 다시 켤 때 옛 화면(Claude 꼬리 줄)을 다시 그리고 그 위에 새 셸 프롬프트를 얹은 창
#       (2026-11-18 실창 t3n/t3k/t12v: 프롬프트 줄 뒤에 ─ 선 문자가 붙고, 그 아래에 옛 Claude 상태줄이 남음 → 예전엔 "빈 프롬프트 아님"으로 건너뜀)
$rule = ([string][char]0x2500) * 30
$residue = "  auto`n" + ([string][char]0x276F) + "`nPS C:\Users\demo> $rule`n  Sonnet 5.5  ctx 18%`n  auto mode on (shift+tab to cycle)"
Check '잔상 창 + 셸이 놀고 있으면: 입력 줄을 프롬프트로 인정(선 문자만 제거)' { (Get-PromptLine $residue $true) -eq 'PS C:\Users\demo>' }
Check '잔상 창이라도 놀고 있는 셸이 아니면(자식 프로세스 있음) 예전처럼 마지막 줄을 본다' { (Get-PromptLine $residue $false) -match 'auto mode' }
Check '프롬프트 뒤에 사용자가 친 글자가 있으면 빈 프롬프트로 보지 않는다' { (Get-PromptLine "x`nPS C:\Users\demo> git status" $true) -notmatch '^PS .+>\s*$' }
Check '화면 끝이 정상 프롬프트면 그대로' { (Get-PromptLine "out`nPS C:\Users\demo> " $true) -match '^PS .+>\s*$' }
Check '프롬프트가 아예 없는 화면(실행 중 Claude)은 프롬프트로 만들지 않는다' { (Get-PromptLine "hello`n  Sonnet 5.5`n  auto mode on" $true) -notmatch '^PS ' }
Check '잔상 창 판정이 Get-Decision 까지 이어져 TYPE 이 된다' { $c = & $ctx; $c.LastLine = (Get-PromptLine $residue $true); (Get-Decision (& $ent 0 $null) $gEmpty $c).Action -eq 'TYPE' }
# 10-c) Herdr 가 잔상 때문에 창을 'claude-code' 앱으로 인식하는 경우(hc get 의 status.app): 입력이 깨지므로 새 탭으로 복구한다
$gGhost = [pscustomobject]@{ state = 'live'; status = [pscustomobject]@{ app = 'claude-code'; state = 'idle' }; foreground = [pscustomobject]@{ pid = 5; name = 'powershell.exe' }; labels = [pscustomobject]@{ 'herdr.tab' = 'tb1'; where = '공간 / 탭' } }
Check '앱 인식 잔상 창 + 셸이 앞: 입력(TYPE) 대신 새 탭(CREATE)' { $d = Get-Decision (& $ent 0 $null) $gGhost (& $ctx); $d.Action -eq 'CREATE' -and $d.Reason -match 'claude-code' }
$cNoCreate = & $ctx; $cNoCreate.AllowCreate = $false
Check '앱 인식 잔상 창인데 새 탭 생성이 아직 허용되지 않으면 건너뛰고 나중에 다시 본다' { $d = Get-Decision (& $ent 0 $null) $gGhost $cNoCreate; $d.Action -eq 'SKIP' -and $d.Retry -eq $true }
$gGhostBusy = [pscustomobject]@{ state = 'live'; status = [pscustomobject]@{ app = 'claude-code'; state = 'working' }; foreground = [pscustomobject]@{ pid = 7; name = 'claude.exe' }; labels = [pscustomobject]@{ 'herdr.tab' = 'tb1'; where = '공간 / 탭' } }
Check '진짜 Claude 가 앞에서 돌면(앞 프로그램이 claude) 새 탭도 만들지 않는다 = 같은 대화 이중 실행 방지' { (Get-Decision (& $ent 0 $null) $gGhostBusy (& $ctx)).Action -eq 'SKIP' }
$cHas = & $ctx; $cHas.HasClaude = $true
Check '그 창에서 Claude 프로세스가 발견되면 앱 인식이어도 건너뜀' { (Get-Decision (& $ent 0 $null) $gGhost $cHas).Action -eq 'SKIP' }
$cRun2 = & $ctx; $cRun2.Running[$sidA] = $true
Check '같은 대화가 다른 곳에서 실행 중이면 앱 인식 잔상 창이어도 새 탭을 만들지 않는다' { (Get-Decision (& $ent 0 $null) $gGhost $cRun2).Action -eq 'SKIP' }
$gShellNone = [pscustomobject]@{ state = 'live'; status = [pscustomobject]@{ app = 'none' }; foreground = [pscustomobject]@{ pid = 5; name = 'powershell.exe' }; labels = [pscustomobject]@{ 'herdr.tab' = 'tb1'; where = '공간 / 탭' } }
Check '앱 인식이 없는 보통 빈 셸은 예전처럼 입력(TYPE)' { (Get-Decision (& $ent 0 $null) $gShellNone (& $ctx)).Action -eq 'TYPE' -and (Get-Decision (& $ent 0 $null) $gEmpty (& $ctx)).Action -eq 'TYPE' }
$script:ProcInfo = @{ 200 = @{ name = 'node.exe' }; 300 = @{ name = 'conhost.exe' } }
$kidsIdle = @{ 100 = (New-Object System.Collections.ArrayList) }; [void]$kidsIdle[100].Add(300)
$kidsBusy = @{ 100 = (New-Object System.Collections.ArrayList) }; [void]$kidsBusy[100].Add(200)
$gRoot = [pscustomobject]@{ pid = 100; state = 'live' }
Check 'Test-ShellIdle: 콘솔 호스트만 있으면 놀고 있는 셸' { Test-ShellIdle $gRoot $kidsIdle }
Check 'Test-ShellIdle: 자식 프로그램이 있으면 놀고 있지 않음' { -not (Test-ShellIdle $gRoot $kidsBusy) }
Check 'Test-ShellIdle: 창 정보가 없으면 놀고 있다고 단정하지 않음' { -not (Test-ShellIdle $null $kidsIdle) }

# 10-d) 앱은 그대로인데 창이 한꺼번에 끝난 사고 판정(2026-11-18 05:46 실사고: 8개가 20초 안에 종료코드 143)
$nowI = [datetime]'2026-11-18T05:48:00'
$mkOrph = { param($addr, $agoSec, $boot) [pscustomobject]@{ addr = $addr; sid = 'x'; boot = $boot; orphan = $true; orphanAt = $nowI.AddSeconds(-$agoSec).ToString('yyyy-MM-ddTHH:mm:ss') } }
$inc8 = @(1..8 | ForEach-Object { & $mkOrph "t$_" (60 + $_) 'B1' })
Check '사고: 이번 부팅 복구 대기 8개가 최근에 생겼고 가라앉았으면(60초 경과) 복구 창을 연다' { Test-IncidentTrigger $inc8 $nowI 'B1' 6 120 45 }
$inc5 = @(1..5 | ForEach-Object { & $mkOrph "t$_" 60 'B1' })
Check '사고 아님: 5개뿐이면(기준 6개 미만) 열지 않는다 = 창 한두 개 정리는 사고로 안 본다' { -not (Test-IncidentTrigger $inc5 $nowI 'B1' 6 120 45) }
$incFresh = @(1..8 | ForEach-Object { & $mkOrph "t$_" (10 + $_) 'B1' })
Check '아직 가라앉지 않음(가장 최근 것이 45초 안): 앱이 같이 꺼지는 중일 수 있어 기다린다' { -not (Test-IncidentTrigger $incFresh $nowI 'B1' 6 120 45) }
$incOld = @(1..8 | ForEach-Object { & $mkOrph "t$_" (3600 + $_) 'B1' })
Check '옛 사건(1시간 전)은 다시 열지 않는다' { -not (Test-IncidentTrigger $incOld $nowI 'B1' 6 120 45) }
$incOtherBoot = @(1..8 | ForEach-Object { & $mkOrph "t$_" 60 'B0' })
Check '다른 부팅의 대기 기록은 세지 않는다(재부팅 복구는 앱 시작 규칙이 맡는다)' { -not (Test-IncidentTrigger $incOtherBoot $nowI 'B1' 6 120 45) }
$incNotOrph = @(1..8 | ForEach-Object { $x = & $mkOrph "t$_" 60 'B1'; $x.orphan = $false; $x })
Check '복구 대기 표시(orphan)가 없는 기록은 세지 않는다' { -not (Test-IncidentTrigger $incNotOrph $nowI 'B1' 6 120 45) }
Check '빈 목록·null 이 섞여도 오류 없이 false' { -not (Test-IncidentTrigger @($null) $nowI 'B1' 6 120 45) -and -not (Test-IncidentTrigger @() $nowI 'B1' 6 120 45) }
$incBadTime = @(1..8 | ForEach-Object { $x = & $mkOrph "t$_" 60 'B1'; $x.orphanAt = '??'; $x })
Check 'orphanAt 시각을 읽을 수 없으면 사고로 세지 않는다(오작동 방지)' { -not (Test-IncidentTrigger $incBadTime $nowI 'B1' 6 120 45) }

# 11) 복구 확인 실패 때 기록 변화: 임시 폴더의 키퍼 사본에서만 쓴다(실제 기록은 건드리지 않음)
$tmp = Join-Path $env:TEMP ('detect-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmp 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $srcDir 'session-keeper.ps1') -Destination $tmp
Get-ChildItem -LiteralPath (Join-Path $srcDir 'lib') -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmp 'lib') }
$probe = Join-Path $tmp 'probe.ps1'
@'
$env:KEEPER_NO_MAIN = '1'
. (Join-Path $PSScriptRoot 'session-keeper.ps1')
$m = @{}
$m['t1'] = [pscustomobject]@{ addr = 't1'; where = 'a / b'; sid = '01234567-89ab-cdef-0123-456789abcdef'; boot = 'B'; orphan = $true; attempts = 0 }
$m['t2'] = [pscustomobject]@{ addr = 't2'; where = 'a / b'; sid = '11111111-2222-3333-4444-555555555555'; boot = 'B'; orphan = $true; attempts = 99 }
$m['t3'] = [pscustomobject]@{ addr = 't3'; where = 'a / b'; sid = '22222222-2222-3333-4444-555555555555'; boot = 'B'; orphan = $true; attempts = 0 }
Save-Map $m
$null = Complete-Resume $m['t1'] $null 'B'          # 60초 안에 확인 안 됨
$null = Complete-Resume $m['t2'] $null 'B'          # 옛 99 기록도 확인 실패
$null = Complete-Resume $m['t3'] 'NOT-FOUND' 'B'    # 대화를 찾을 수 없음
$r = Read-Map
foreach ($k in 't1', 't2', 't3') { "{0}|{1}|{2}" -f $k, $r[$k].attempts, $(if ($r[$k].PSObject.Properties['typedAt']) { 'typed' } else { '-' }) }
'@ | Set-Content -LiteralPath $probe -Encoding UTF8
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $probe 2>&1 | Out-String
$res = @{}; foreach ($ln in ($out -split "`r?`n")) { if ($ln -match '^(t\d)\|(\d+)\|(\S+)$') { $res[$Matches[1]] = @{ a = [int]$Matches[2]; t = $Matches[3] } } }
Check '확인 실패(시간 초과): 99 로 굳히지 않고 시도 1 증가 + 입력 시각 기록' { $res['t1'].a -eq 1 -and $res['t1'].t -eq 'typed' }
Check '옛 99 기록이 확인 실패해도 잠그지 않고 2번째 시도로 센다' { $res['t2'].a -eq 2 -and $res['t2'].t -eq 'typed' }
Check '대화를 찾을 수 없음: 더 시도해도 소용없으니 한도(3)로 올림' { $res['t3'].a -eq 3 }
# ---- 10-e) 인식률 점검 경고(2026-11-19): Herdr 가 보고한 Claude 창 수 vs 키퍼가 인식한 수. 알리기만 하고 기록은 건드리지 않는다.
Check '인식률: 정상 23/23 은 이상 아님' { -not (Test-DetectBad 23 23) }
Check '인식률: 11-14 사고(24개 중 0개)는 이상' { Test-DetectBad 24 0 }
Check '인식률: 창 2개 이하는 판단하지 않음(0개 인식이어도)' { -not (Test-DetectBad 2 0) -and -not (Test-DetectBad 0 0) }
Check '인식률: 3개 중 1개는 이상, 3개 중 2개·4개 중 2개(정확히 절반)는 이상 아님' { (Test-DetectBad 3 1) -and -not (Test-DetectBad 3 2) -and -not (Test-DetectBad 4 2) }
$h0 = @{ streak = 0; warn = $false; since = $null; lastNotify = $null }
$t0 = [datetime]'2026-11-19T03:00:00'
function Run-Steps($bads, [bool]$sup = $false) { $s = $h0; $ev = @(); $i = 0; foreach ($b in $bads) { $s = Step-DetectHealth $s ([bool]$b) $sup $t0.AddMinutes($i) 3 360; $ev += $s.event; $i++ }; return @{ s = $s; ev = $ev } }
$r1 = Run-Steps @($true, $true)
Check '상태: 이상 2회 연속은 아직 경고하지 않음' { -not $r1.s.warn -and @($r1.ev | Where-Object { $_ }).Count -eq 0 }
$r2 = Run-Steps @($true, $true, $true)
Check '상태: 이상 3회 연속(3분)에서 처음 경고(warn) 1번' { $r2.s.warn -and $r2.ev[2] -eq 'warn' -and @($r2.ev | Where-Object { $_ -eq 'warn' }).Count -eq 1 }
$r3 = Run-Steps @($true, $true, $false, $true, $true)
Check '상태: 중간에 정상이 끼면 연속이 끊겨 경고하지 않음' { -not $r3.s.warn }
$r4 = Run-Steps @($true, $true, $true, $true, $true, $true)
Check '상태: 경고 뒤 같은 상태가 이어져도 다시 울리지 않음(1회 알림)' { @($r4.ev | Where-Object { $_ }).Count -eq 1 }
$r5 = Run-Steps @($true, $true, $true, $false)
Check '상태: 경고 뒤 정상이 되면 recover 로 해제' { -not $r5.s.warn -and $r5.ev[3] -eq 'recover' }
$sw = $r2.s
Check '상태: 복구 중·시작 직후(Suppress)에는 연속을 세지 않고 0 으로 되돌림' { (Step-DetectHealth @{ streak = 2; warn = $false; since = $null; lastNotify = $null } $true $true $t0 3 360).streak -eq 0 }
Check '상태: Suppress 중에는 이미 난 경고를 해제하지도 다시 울리지도 않음' { $x = Step-DetectHealth $sw $false $true $t0.AddMinutes(1) 3 360; $x.warn -and $x.event -eq '' }
Check '상태: 경고가 6시간(360분) 이상 이어지면 remind 1번, 그 전에는 없음' { $a = Step-DetectHealth $sw $true $false $t0.AddMinutes(359) 3 360; $b = Step-DetectHealth $sw $true $false $t0.AddMinutes(363) 3 360; $a.event -eq '' -and $b.event -eq 'remind' -and $b.lastNotify -eq $t0.AddMinutes(363) }
$tmpH = Join-Path $env:TEMP ('keeper-health-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmpH 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $srcDir 'session-keeper.ps1') -Destination $tmpH
Get-ChildItem -LiteralPath (Join-Path $srcDir 'lib') -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpH 'lib') }
$probeH = Join-Path $tmpH 'probe.ps1'
@'
$env:KEEPER_NO_MAIN = '1'
. (Join-Path $PSScriptRoot 'session-keeper.ps1')
function Show-Toast([string]$Title, [string]$Body) { $script:Toasts = 1 + [int]$script:Toasts; return $true }   # 시험: 실제 알림을 띄우지 않는다
$st = @{ streak = 0; warn = $false; since = $null; lastNotify = $null }
$script:LastDetect = @{ W = 24; H = 0; hcFail = 0; noPid = 0; none = 24; skip = $false }
for ($i = 0; $i -lt 2; $i++) { $st = Invoke-HealthTick $st $false }
"A|$($st.warn)|$([int]$script:Toasts)"
$st = Invoke-HealthTick $st $false
"B|$($st.warn)|$([int]$script:Toasts)"
$hf = Join-Path $PSScriptRoot 'keeper-health.json'
$j = Get-Content -LiteralPath $hf -Raw | ConvertFrom-Json
"C|$($j.state)|$($j.windows)|$($j.recognized)|$($j.reason.Length -gt 10)"
$b0 = [IO.File]::ReadAllBytes($hf)
"D|$($b0[0] -ne 0xEF)"
$st = Invoke-HealthTick $st $false
"E|$($st.warn)|$([int]$script:Toasts)"
$script:LastDetect = @{ W = 24; H = 24; hcFail = 0; noPid = 0; none = 0; skip = $false }
$st = Invoke-HealthTick $st $false
$j = Get-Content -LiteralPath $hf -Raw | ConvertFrom-Json
"F|$($st.warn)|$($j.state)|$($j.recognized)"
$script:LastDetect = $null
$st2 = Invoke-HealthTick $st $false
"G|$([object]::ReferenceEquals($st, $st2))"
$script:LastDetect = @{ W = 24; H = 0; hcFail = 0; noPid = 0; none = 24; skip = $false }
$s3 = @{ streak = 0; warn = $false; since = $null; lastNotify = $null }
for ($i = 0; $i -lt 5; $i++) { $s3 = Invoke-HealthTick $s3 $true }
"H|$($s3.warn)"
'@ | Set-Content -LiteralPath $probeH -Encoding UTF8
$outH = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeH 2>&1 | Out-String
$rh = @{}; foreach ($ln in ($outH -split "`r?`n")) { if ($ln -match '^([A-H])\|(.*)$') { $rh[$Matches[1]] = $Matches[2] } }
Check '통합: 사고(0/24) 2회째까지는 알림 0, 3회째에 경고+알림 1번' { $rh['A'] -eq 'False|0' -and $rh['B'] -eq 'True|1' }
Check '통합: keeper-health.json 에 상태 warn·창 24·인식 0·원인 문구가 BOM 없이 기록됨' { $rh['C'] -eq 'warn|24|0|True' -and $rh['D'] -eq 'True' }
Check '통합: 경고가 이어져도 알림은 더 늘지 않음(1번)' { $rh['E'] -eq 'True|1' }
Check '통합: 정상 복귀 시 경고 해제 + 상태 파일 ok 로 갱신' { $rh['F'] -eq 'False|ok|24' }
Check '통합: 이번 회차 집계가 없으면(코어 없음 등) 상태를 그대로 둠' { $rh['G'] -eq 'True' }
Check '통합: 복구 중(Suppress)에는 사고 상태여도 경고·알림 없음' { $rh['H'] -eq 'False' }
Check '통합: 시험이 키퍼 기록(session-map.json)을 만들지도 건드리지도 않음(읽기 전용 점검)' { -not (Test-Path -LiteralPath (Join-Path $tmpH 'session-map.json')) }
Remove-Item -LiteralPath $tmpH -Recurse -Force -ErrorAction SilentlyContinue
$srcTxt = [IO.File]::ReadAllText((Join-Path $srcDir 'session-keeper.ps1'), [Text.Encoding]::UTF8)
$ia = $srcTxt.IndexOf('function Invoke-HealthTick'); $ib = $srcTxt.IndexOf('# ---------------------------------------------------------------- Snapshot')
Check '읽기 전용: 점검 함수에는 Save-Map/Invoke-Recover/hc send 호출이 없음' { $seg = $srcTxt.Substring($ia, $ib - $ia); $seg -notmatch 'Save-Map|Invoke-Recover|HcJson @\(.send|keys' }

# ---- 10-f) 멈춘 키퍼 흔적(2026-11-19): 잠금이 풀리지 않는데 심박이 5분 넘게 멈춰 있으면, 새로 켜진 키퍼가 조용히 끝나되 로그 한 줄을 남긴다
$tmpK = Join-Path $env:TEMP ('keeper-stuck-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmpK 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $srcDir 'session-keeper.ps1') -Destination $tmpK
Get-ChildItem -LiteralPath (Join-Path $srcDir 'lib') -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpK 'lib') }
$mxK = New-Object Threading.Mutex($false, 'Local\HerdrSessionKeeper')
$heldK = $false; try { $heldK = $mxK.WaitOne(0) } catch {}     # 못 잡으면 진짜 키퍼가 이미 쥐고 있는 것: 어느 쪽이든 새 프로세스는 잠금 때문에 끝난다
function Run-Second([int]$ageSec) {
    $alive = Join-Path $tmpK 'session-keeper.alive'; $log = Join-Path $tmpK 'session-keeper.log'
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $alive -Value "1|2026-11-19T00:00:00|B" -Encoding ASCII
    (Get-Item -LiteralPath $alive).LastWriteTime = (Get-Date).AddSeconds(-$ageSec)
    $env:KEEPER_NO_TOAST = '1'; $noMain = $env:KEEPER_NO_MAIN; $env:KEEPER_NO_MAIN = $null     # 자식은 실제로 Run 을 실행해야 한다(이 시험 프로세스의 KEEPER_NO_MAIN 을 물려받으면 아무것도 하지 않아 시험이 헛통과한다)
    $p = Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $tmpK 'session-keeper.ps1'), '-Mode', 'Run' -WindowStyle Hidden -PassThru
    $done = $p.WaitForExit(45000); if (-not $done) { try { $p.Kill() } catch {} }
    $env:KEEPER_NO_TOAST = $null; $env:KEEPER_NO_MAIN = $noMain
    $txt = ''; if (Test-Path -LiteralPath $log) { $txt = [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8) }
    return @{ done = $done; log = $txt }
}
$k1 = Run-Second 330
$k2 = Run-Second 10
$k3 = Run-Second 10800
Check '멈춘 키퍼: 심박 5분 넘게 정지 + 잠김 -> 새 프로세스는 끝나고(멈추지 않음) 경고 로그 1줄' { $k1.done -and ([regex]::Matches($k1.log, '멈춰 있습니다')).Count -eq 1 }
Check '멈춘 키퍼: 심박이 신선하면(정상 실행 중) 로그를 쌓지 않음' { $k2.done -and $k2.log -notmatch '멈춰 있습니다' }
Check '멈춘 키퍼: 3시간 넘게 오래된 심박은 같은 경고를 반복하지 않음(5~6분 구간에서만 1번)' { $k3.done -and $k3.log -notmatch '멈춰 있습니다' }
if ($heldK) { try { $mxK.ReleaseMutex() } catch {} }
$mxK.Dispose()
Remove-Item -LiteralPath $tmpK -Recurse -Force -ErrorAction SilentlyContinue

# ---- 10-g) 오케스트레이션과 맞물리는 계약(2026-11-19): 잔상 창 제외, keeper-health.json 계약 필드, session-map.json 4개 필드
$tmpG = Join-Path $env:TEMP ('keeper-contract-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmpG 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $srcDir 'session-keeper.ps1') -Destination $tmpG
Get-ChildItem -LiteralPath (Join-Path $srcDir 'lib') -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpG 'lib') }
$probeG = Join-Path $tmpG 'probe.ps1'
@'
$env:KEEPER_NO_MAIN = '1'
. (Join-Path $PSScriptRoot 'session-keeper.ps1')
function Show-Toast([string]$Title, [string]$Body) { return $true }
$sidA = '01234567-89ab-cdef-0123-456789abcdef'; $sidB = '11111111-2222-3333-4444-555555555555'
$W = @{}
function Win($addr, $root, $fg, $fgName, $agent = 'claude-code') { $W[$addr] = [pscustomobject]@{ pid = $root; state = 'live'; foreground = [pscustomobject]@{ pid = $fg; name = $fgName }; labels = [pscustomobject]@{ where = 'S / T'; 'herdr.tab' = 'tb1' } }; return [pscustomobject]@{ address = $addr; state = 'live'; agent = $agent } }
$script:LS = @()
function Invoke-HcJson([string[]]$a) { if ($a[0] -eq 'ls') { return [pscustomobject]@{ terminals = $script:LS } } elseif ($a[0] -eq 'get') { return $W[$a[1]] } else { return $null } }
function Get-ClaudeSessions { return $script:SESS }
function Get-ChildTable { return $script:KIDS }
function Get-AppLs { return $null }
function Get-LayoutTable($x) { return @{} }
function Show-D($name) { $d = $script:LastDetect; "$name|$($d.W)|$($d.H)|$($d.ghost)|$($d.none)|$(Test-DetectBad $d.W $d.H)" }
# 시나리오 1: 진짜 Claude 2개 + 잔상 창 3개(앞 프로그램이 powershell, Claude 없음) + 일반 셸 1개
$script:KIDS = @{ 100 = (New-Object System.Collections.ArrayList); 110 = (New-Object System.Collections.ArrayList); 150 = (New-Object System.Collections.ArrayList) }
[void]$script:KIDS[100].Add(200); [void]$script:KIDS[110].Add(150); [void]$script:KIDS[150].Add(250)
$script:SESS = @{ 200 = [pscustomobject]@{ pid = 200; sessionId = $sidA; cwd = 'C:\work' }; 250 = [pscustomobject]@{ pid = 250; sessionId = $sidB; cwd = 'C:\work' } }
$script:LS = @((Win 'a1' 100 200 'claude.exe'), (Win 'a2' 110 250 'claude.exe'), (Win 'g1' 300 300 'powershell.exe'), (Win 'g2' 310 310 'powershell.exe'), (Win 'g3' 320 320 'pwsh.exe'), (Win 'p1' 330 330 'powershell.exe' 'powershell.exe'))
Invoke-Snapshot; Show-D 'S1'
# 시나리오 2: 2026-11-14 사고 재현 - 앞 프로그램이 claude 인데 키퍼가 하나도 못 찾음(세션 표는 비어 있지 않아 보호 규칙은 통과)
$script:SESS = @{ 999 = [pscustomobject]@{ pid = 999; sessionId = $sidA; cwd = 'C:\other' } }
$script:KIDS = @{}
$script:LS = @((Win 'b1' 400 401 'claude.exe'), (Win 'b2' 410 411 'claude.exe'), (Win 'b3' 420 421 'claude.exe'), (Win 'b4' 430 431 'claude.exe'))
Invoke-Snapshot; Show-D 'S2'
# 시나리오 3: 잔상 창만 4개 - 진짜 Claude 는 없음(점검 대상 창 0개 -> 이상 아님)
$script:LS = @((Win 'c1' 500 500 'powershell.exe'), (Win 'c2' 510 510 'powershell.exe'), (Win 'c3' 520 520 'powershell.exe'), (Win 'c4' 530 530 'powershell.exe'))
Invoke-Snapshot; Show-D 'S3'
# 계약 파일(keeper-health.json): 복구 중 표시와 즉시 갱신
$script:LastDetect = @{ W = 23; H = 23; hcFail = 0; noPid = 0; ghost = 2; none = 0; skip = $false }
$hf = Join-Path $PSScriptRoot 'keeper-health.json'
Set-HealthRecovering $true (Get-Date)          # 점검 기록이 아직 없으면 아무것도 하지 않아야 한다
"H0|$(Test-Path $hf)"
$st = Invoke-HealthTick @{ streak = 0; warn = $false; since = $null; lastNotify = $null } $true $true ([datetime]'2026-11-19T06:00:00')
$j1 = Get-Content -LiteralPath $hf -Raw | ConvertFrom-Json
"H1|$($j1.v)|$($j1.intervalSec)|$($j1.windows)|$($j1.recognized)|$($j1.ghost)|$($j1.state)|$($j1.recovering)|$($j1.recoverySince)"
Set-HealthRecovering $false $null
$j2 = Get-Content -LiteralPath $hf -Raw | ConvertFrom-Json
"H2|$($j2.recovering)|[$($j2.recoverySince)]|$($j2.at -eq $j1.at)"
Set-HealthRecovering $true ([datetime]'2026-11-19T06:10:00')
$j3 = Get-Content -LiteralPath $hf -Raw | ConvertFrom-Json
"H3|$($j3.recovering)|$($j3.recoverySince)|$($j3.at -eq $j1.at)"
'@ | Set-Content -LiteralPath $probeG -Encoding UTF8
$outG = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeG 2>&1 | Out-String
$rg = @{}; foreach ($ln in ($outG -split "`r?`n")) { if ($ln -match '^(S\d|H\d)\|(.*)$') { $rg[$Matches[1]] = $Matches[2] } }
Check '잔상 제외: 진짜 2개 + 잔상 3개(+일반 셸 1개)는 창 2/인식 2/잔상 3, 이상 아님(제외 안 하면 2/5 로 오경보)' { $rg['S1'] -eq '2|2|3|0|False' }
Check '잔상 제외: 11-14 사고(앞 프로그램이 claude 인데 4개 모두 미인식)는 여전히 이상으로 잡힘' { $rg['S2'] -eq '4|0|0|4|True' }
Check '잔상 제외: 잔상 창뿐이면 점검 대상 0개라 이상 아님' { $rg['S3'] -eq '0|0|4|0|False' }
Check '계약: 점검 기록이 없는 상태에서 복구 표시를 바꿔도 파일을 만들지 않음' { $rg['H0'] -eq 'False' }
Check '계약: keeper-health.json 에 v=1, intervalSec=60, windows/recognized/ghost, state=ok, recovering=true, 시작 시각이 적힘' { $rg['H1'] -eq '1|60|23|23|2|ok|True|2026-11-19T06:00:00' }
Check '계약: 복구가 끝나면 recovering=false·시작 시각 비움, 마지막 점검 시각(at)은 그대로' { $rg['H2'] -eq 'False|[]|True' }
Check '계약: 복구가 다시 시작되면 recovering=true·새 시작 시각, at 은 그대로' { $rg['H3'] -eq 'True|2026-11-19T06:10:00|True' }
Remove-Item -LiteralPath $tmpG -Recurse -Force -ErrorAction SilentlyContinue
# session-map.json 계약(오케스트레이션 role-check 가 읽는 4개 필드): 키=창 주소, sid=UUID, seen=시간대 없는 지역 시각, where=문자열
$srcTxt2 = [IO.File]::ReadAllText((Join-Path $srcDir 'session-keeper.ps1'), [Text.Encoding]::UTF8)
$sa = $srcTxt2.IndexOf('function Invoke-Snapshot'); $sb = $srcTxt2.IndexOf('# ---------------------------------------------------------------- Recover')
$snapSrc = $srcTxt2.Substring($sa, $sb - $sa)
Check '계약: 키퍼가 쓰는 기록 항목에 addr·where·sid·seen 이 모두 들어 있음(Claude·Codex 양쪽)' { ([regex]::Matches($snapSrc, 'addr = \$(t\.address|a);\s*where = ').Count -ge 2) -and ([regex]::Matches($snapSrc, 'sid = ').Count -ge 2) -and ([regex]::Matches($snapSrc, 'seen = \$now').Count -ge 2) }
$realMap = Join-Path $srcDir 'session-map.json'
if (Test-Path -LiteralPath $realMap) {
    $mapObj = $null; try { $mapObj = Get-Content -LiteralPath $realMap -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    Check '계약(실제 기록, 읽기 전용): 모든 항목이 주소 키·UUID sid·시간대 없는 지역 시각 seen·where 문자열 규칙을 지킴' { $bad = 0; foreach ($p in $mapObj.PSObject.Properties) { $e = $p.Value; if ($p.Name -notmatch '^t[0-9a-z]{1,10}$' -or "$($e.sid)" -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or "$($e.seen)" -notmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$' -or [string]::IsNullOrWhiteSpace("$($e.where)")) { $bad++ } }; $null -ne $mapObj -and $bad -eq 0 }
}

# ---- 10-h) 기록 파일 동시 저장(2026-11-19): 자동 감시와 수동 실행이 동시에 저장해도 실패·깨짐·임시 파일 잔재가 없어야 한다(고치기 전엔 4개 동시 60회씩 저장 중 31회 실패)
$tmpH = Join-Path $env:TEMP ('keeper-mapwrite-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmpH 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $srcDir 'session-keeper.ps1') -Destination $tmpH
Get-ChildItem -LiteralPath (Join-Path $srcDir 'lib') -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpH 'lib') }
$workerH = Join-Path $tmpH 'worker.ps1'
@'
param([int]$Id, [int]$Loops)
$ErrorActionPreference = 'Stop'
$env:KEEPER_NO_MAIN = '1'
. (Join-Path $PSScriptRoot 'session-keeper.ps1')
$err = 0
for ($i = 0; $i -lt $Loops; $i++) {
    $m = @{}
    for ($k = 0; $k -lt 25; $k++) { $m["t$($Id)x$k"] = [pscustomobject]@{ addr = "t$($Id)x$k"; sid = [guid]::NewGuid().ToString(); seen = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'); where = "S / T$i" } }
    try { Save-Map $m } catch { $err++ }
}
"ERR|$Id|$err"
'@ | Set-Content -LiteralPath $workerH -Encoding UTF8
$procsH = @()
foreach ($w in 1..4) {
    $procsH += Start-Process -FilePath powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $workerH, '-Id', $w, '-Loops', 25) -RedirectStandardOutput (Join-Path $tmpH "out$w.txt") -WindowStyle Hidden -PassThru
}
$null = $procsH | Wait-Process -Timeout 180
$errH = 0; $doneH = 0
foreach ($w in 1..4) { $l = Get-Content -LiteralPath (Join-Path $tmpH "out$w.txt") -ErrorAction SilentlyContinue | Where-Object { $_ -like 'ERR|*' } | Select-Object -First 1; if ($l -match '^ERR\|\d+\|(\d+)$') { $doneH++; $errH += [int]$Matches[1] } }
$mapOkH = $false; try { $null = Get-Content -LiteralPath (Join-Path $tmpH 'session-map.json') -Raw -Encoding UTF8 | ConvertFrom-Json; $mapOkH = $true } catch {}
$leftH = @(Get-ChildItem -LiteralPath $tmpH -Filter 'session-map.json*.tmp' -Force -ErrorAction SilentlyContinue).Count
Check '동시 저장: 4개 실행이 25회씩 동시에 저장해도 4개 모두 끝까지 돌고 저장 실패 0회' { $doneH -eq 4 -and $errH -eq 0 }
Check '동시 저장: 끝난 뒤 기록 파일이 정상 JSON 이고 임시 파일(.tmp)이 남지 않음' { $mapOkH -and $leftH -eq 0 }
Remove-Item -LiteralPath $tmpH -Recurse -Force -ErrorAction SilentlyContinue

"합계: PASS $script:pass / FAIL $script:fail"
if ($script:fail -gt 0) { exit 1 }
