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
"합계: PASS $script:pass / FAIL $script:fail"
if ($script:fail -gt 0) { exit 1 }
