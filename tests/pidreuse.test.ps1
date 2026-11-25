# 재부팅 뒤 옛 pid 재사용 시험(Get-ClaudeSessions). 2026-11-20 실제 재부팅 시험에서 발견된 결함의 재현:
#   재부팅 전에 쓴 sessions\<pid>.json 이 남아 있고, 그 pid 를 Windows 가 전혀 다른 프로그램에 다시 줬을 때
#   키퍼가 "같은 대화가 이미 실행 중"으로 잘못 판단해 그 창을 복구하지 않았다.
# 임시 폴더의 가짜 파일 + 시험 중에만 띄우는 대기 프로세스만 쓴다(실제 Claude 세션 파일·창은 건드리지 않는다).
$env:KEEPER_NO_MAIN = '1'
. (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'session-keeper.ps1')
$script:pass = 0; $script:fail = 0
function Check([string]$n, $c) { if ($c) { $script:pass++; "PASS  $n" } else { $script:fail++; "FAIL  $n" } }

$tmp = Join-Path $env:TEMP ('pr-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $tmp | Out-Null
$SessDir = $tmp
$helpers = @()
try {
    # 서로 다른 pid 가 필요해서 대기용 프로세스 3개를 띄운다(60초 뒤 스스로 끝남, 아래에서 바로 정리).
    1..3 | ForEach-Object { $helpers += Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 60' -WindowStyle Hidden -PassThru }
    Start-Sleep -Milliseconds 600
    function New-SessFile([int]$procId, [string]$sid, $procStart) {
        $o = [ordered]@{ pid = $procId; sessionId = $sid; cwd = 'C:\Users\tester'; kind = 'interactive' }
        if ($null -ne $procStart) { $o['procStart'] = "$procStart" }
        [IO.File]::WriteAllText((Join-Path $tmp "$procId.json"), ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    }
    $sidReal = '11111111-1111-4111-8111-111111111111'; $sidFake = '22222222-2222-4222-8222-222222222222'
    $sidLegacy = '33333333-3333-4333-8333-333333333333'; $sidNear = '44444444-4444-4444-8444-444444444444'; $sidDead = '55555555-5555-4555-8555-555555555555'
    $ft = { param($p) [int64](Get-Process -Id $p.Id).StartTime.ToFileTime() }

    # A) 진짜: 파일의 시작 시각이 실제 프로세스와 같다 -> 실행 중으로 인정
    New-SessFile $helpers[0].Id $sidReal (& $ft $helpers[0])
    # B) 가짜(이번 결함): pid 는 살아 있지만 다른 프로그램 - 시작 시각이 10분 어긋남 -> 무시
    New-SessFile $helpers[1].Id $sidFake ((& $ft $helpers[1]) - [int64]6000000000)
    # C) 옛 형식(procStart 없음) -> 예전처럼 pid 만 보고 인정(되돌림 호환)
    New-SessFile $helpers[2].Id $sidLegacy $null
    # D) pid 자체가 없음 -> 무시(예전과 같음)
    New-SessFile 2147480000 $sidDead 123456789
    $r = Get-ClaudeSessions
    $sids = @($r.Values | ForEach-Object { "$($_.sessionId)" })
    Check 'A) 시작 시각이 일치하는 진짜 세션은 실행 중으로 인정' ($sids -contains $sidReal)
    Check 'B) pid 만 겹친 가짜(시작 시각 10분 차이)는 실행 중으로 보지 않음 - 복구가 건너뛰어지지 않는다' (-not ($sids -contains $sidFake))
    Check 'C) procStart 가 없는 옛 형식 파일은 예전처럼 인정(호환)' ($sids -contains $sidLegacy)
    Check 'D) 없는 pid 는 무시' (-not ($sids -contains $sidDead))
    Check '개수: 진짜+옛 형식 2개만 남음' ($r.Count -eq 2)

    # E) 오차 2초 이내는 같은 프로세스로 인정(시각 표현 차이 대비), 30초는 다른 프로세스
    New-SessFile $helpers[1].Id $sidNear ((& $ft $helpers[1]) + [int64]20000000)
    $r = Get-ClaudeSessions
    Check 'E1) 시작 시각 오차 2초는 같은 프로세스로 인정' (@($r.Values | Where-Object { "$($_.sessionId)" -eq $sidNear }).Count -eq 1)
    New-SessFile $helpers[1].Id $sidNear ((& $ft $helpers[1]) + [int64]300000000)
    $r = Get-ClaudeSessions
    Check 'E2) 시작 시각 오차 30초는 다른 프로세스로 봄' (@($r.Values | Where-Object { "$($_.sessionId)" -eq $sidNear }).Count -eq 0)

    # H) 안전장치: procStart 가 FILETIME 이 아닌 다른 단위(예: 밀리초 시각)면 판단하지 않고 실행 중으로 본다
    #    (Claude 가 나중에 이 값의 단위를 바꿔도 모든 창이 "가짜"로 보여 복구·기록이 무너지지 않게)
    New-SessFile $helpers[1].Id $sidNear 1795130299469
    $r = Get-ClaudeSessions
    Check 'H) procStart 가 다른 단위(밀리초 시각)면 판단하지 않고 실행 중으로 인정' (@($r.Values | Where-Object { "$($_.sessionId)" -eq $sidNear }).Count -eq 1)
    # I) 숫자가 아닌 값도 마찬가지
    New-SessFile $helpers[1].Id $sidNear 'abc-not-a-number'
    $r = Get-ClaudeSessions
    Check 'I) procStart 가 숫자가 아니면 판단하지 않고 실행 중으로 인정' (@($r.Values | Where-Object { "$($_.sessionId)" -eq $sidNear }).Count -eq 1)

    # F) 같은 대화 ID 의 복구 판단: 가짜만 있으면 Running 에 안 들어가 복구가 진행된다(Get-Decision 은 입출력 없는 판단 함수)
    New-SessFile $helpers[1].Id $sidFake ((& $ft $helpers[1]) - [int64]6000000000)
    $r = Get-ClaudeSessions
    $ctx = @{ Running = @{}; AllowCreate = $true; JsonlOk = $true; HasClaude = $false; LastLine = ''; MaxAttempts = 3; ClaudeTemplate = $true; CheckFile = $false }
    foreach ($v in $r.Values) { $ctx.Running["$($v.sessionId)"] = $true }
    $e = @{ sid = $sidFake; addr = 't1df'; where = 'x / y'; cwd = 'C:\Users\tester'; attempts = 0 }
    $dec = Get-Decision $e @{ state = 'live'; cwd = 'C:\Users\tester' } $ctx
    Check 'F) 가짜 파일만 있는 대화는 "이미 실행 중"으로 건너뛰지 않음' ($dec.Reason -ne '같은 대화가 이미 실행 중')
    $ctx.Running[$sidReal] = $true
    $dec2 = Get-Decision @{ sid = $sidReal; addr = 't1xx'; where = 'x / y'; cwd = 'C:\Users\tester'; attempts = 0 } @{ state = 'live'; cwd = 'C:\Users\tester' } $ctx
    Check 'G) 진짜로 실행 중인 대화는 여전히 건너뜀(겹쳐 켜지 않음)' ($dec2.Action -eq 'SKIP' -and $dec2.Reason -eq '같은 대화가 이미 실행 중')
}
finally {
    foreach ($h in $helpers) { try { Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue } catch {} }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"`n합계: PASS $script:pass / FAIL $script:fail"
if ($script:fail -gt 0) { exit 1 }
