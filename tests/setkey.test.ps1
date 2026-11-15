# set-key.ps1 시험: 단축키 확인/변경/되돌리기/해제, 겹침 거부, 잘못된 키 거부, 파일 보존. 전부 임시 폴더의 가짜 keys.json 만 쓴다(실제 Herdr 설정은 읽지도 쓰지도 않는다).
# 마지막 줄 "합계: PASS n / FAIL m" 형식은 run-all 이 읽는다.
$ErrorActionPreference = 'Continue'
$src = Split-Path -Parent $PSScriptRoot
$T = Join-Path $env:TEMP ("setkey-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $T -Force | Out-Null
$script:pass = 0; $script:fail = 0
function Check([string]$n, $c) { if ($c) { $script:pass++; "PASS  $n" } else { $script:fail++; "FAIL  $n" } }

# 꾸러미를 임시 폴더에 만들어 거기 있는 set-key.ps1(BOM+CRLF 판) 으로 시험한다(원본은 BOM 이 없어 5.1 에서 한글이 깨질 수 있음)
$kit = Join-Path $T 'kit'
$null = & node (Join-Path $src 'build-kit.mjs') $kit 2>&1
$sk = Join-Path $kit 'plugins\herdr-session-keeper\set-key.ps1'
Check 'set-key.ps1 이 꾸러미에 들어간다' (Test-Path -LiteralPath $sk)
$e = $null; $tk = $null; [void][Management.Automation.Language.Parser]::ParseFile($sk, [ref]$tk, [ref]$e)
Check 'set-key.ps1 문법 오류 없음' (@($e).Count -eq 0)

function NewHome([string]$name, [string]$text) {
    $h = Join-Path $T $name; New-Item -ItemType Directory -Path $h -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $h 'keys.json'), $text, (New-Object Text.UTF8Encoding($false)))
    return $h
}
function Run([string]$h, [string[]]$extra) {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $sk -HerdrHome $h @extra 2>&1 | Out-String
    return [pscustomobject]@{ code = $LASTEXITCODE; out = $o; key = ([regex]::Match($o, '(?m)^KEY=(.*)$').Groups[1].Value.Trim()) }
}
function Keys([string]$h) { [IO.File]::ReadAllText((Join-Path $h 'keys.json'), [Text.Encoding]::UTF8) }
$base = "{`r`n    `"global`": {`r`n        `"ctrl-shift-p`": `"app.palette`",`r`n        `"alt-1`": `"space.select:1`",`r`n        `"ctrl-shift-r`": `"mod.open:session-keeper`"`r`n    }`r`n}`r`n"

try {
    # 1) 확인
    $h = NewHome 'a' $base
    $r = Run $h @('-Show')
    Check '-Show: 현재 키(ctrl-shift-r)를 알려 주고 파일은 그대로' ($r.code -eq 0 -and $r.key -eq 'ctrl-shift-r' -and $r.out -match 'Ctrl\+Shift\+R' -and (Keys $h) -eq $base)

    # 2) 바꾸기 (+ 쓰는 방식 Ctrl+Alt+R)
    $r = Run $h @('-Key', 'Ctrl+Alt+R')
    $k = Keys $h
    Check '-Key Ctrl+Alt+R: ctrl-alt-r 로 바뀌고 옛 ctrl-shift-r 연결은 사라짐' ($r.code -eq 0 -and $r.key -eq 'ctrl-alt-r' -and $k.Contains('"ctrl-alt-r": "mod.open:session-keeper"') -and -not $k.Contains('"ctrl-shift-r"'))
    Check '바꾼 뒤에도 올바른 JSON, 다른 단축키 그대로, 줄바꿈(CRLF) 유지' ([bool]($k | ConvertFrom-Json) -and $k.Contains('"ctrl-shift-p": "app.palette"') -and $k.Contains('"alt-1": "space.select:1"') -and $k.Contains("`r`n") -and -not [regex]::IsMatch($k, '(?<!\r)\n'))
    Check '백업 파일 생성(원본 내용)' ((Test-Path (Join-Path $h 'keys.json.bak-before-session-keeper-kit')) -and ([IO.File]::ReadAllText((Join-Path $h 'keys.json.bak-before-session-keeper-kit')) -eq $base))
    $r = Run $h @('-Show'); Check '-Show: 바뀐 키를 보여 줌' ($r.key -eq 'ctrl-alt-r')

    # 3) 이미 그 키면 그대로, 키를 안 주면(설치 때 재실행) 바꾼 키를 유지
    $before = Keys $h
    $r = Run $h @('-Key', 'ctrl-alt-r'); Check '같은 키로 다시: 이미 연결(파일 불변)' ($r.code -eq 0 -and $r.out -match '이미' -and (Keys $h) -eq $before)
    $r = Run $h @(); Check '키를 안 주면 바꾼 키 유지(기본 키로 되돌리지 않음)' ($r.code -eq 0 -and $r.key -eq 'ctrl-alt-r' -and (Keys $h) -eq $before)

    # 4) 겹침 거부: 다른 기능이 쓰는 키
    $r = Run $h @('-Key', 'alt-1'); Check '겹치는 키(alt-1)는 거부, 어떤 기능과 겹치는지 알려 줌, 파일 불변' ($r.code -eq 1 -and $r.out -match 'space\.select:1' -and (Keys $h) -eq $before)
    $r = Run $h @('-Key', 'ctrl-shift-p'); Check '겹치는 키(ctrl-shift-p)도 거부, 파일 불변' ($r.code -eq 1 -and (Keys $h) -eq $before)

    # 5) 쓸 수 없는 키 거부
    foreach ($bad in @('r', 'shift-r', 'ctrl-c', 'ctrl-shift', 'ctrl-alt-ㄱ', 'ctrl-foo-r', 'ctrl-alt-r-r')) {
        $r = Run $h @('-Key', $bad)
        Check "쓸 수 없는 키 거부: '$bad'" ($r.code -eq 1 -and (Keys $h) -eq $before)
    }

    # 6) -DryRun 은 아무것도 쓰지 않는다
    $r = Run $h @('-Key', 'alt-shift-s', '-DryRun'); Check '-DryRun: 가능하다고만 알리고 파일 불변' ($r.code -eq 0 -and $r.out -match '점검' -and (Keys $h) -eq $before)
    $r = Run $h @('-Key', 'alt-1', '-DryRun'); Check '-DryRun: 겹치면 거부(코드 1)' ($r.code -eq 1)

    # 7) 원래대로
    $r = Run $h @('-Reset'); $k = Keys $h
    Check '-Reset: ctrl-shift-r 로 돌아옴' ($r.code -eq 0 -and $r.key -eq 'ctrl-shift-r' -and $k.Contains('"ctrl-shift-r": "mod.open:session-keeper"') -and -not $k.Contains('ctrl-alt-r') -and [bool]($k | ConvertFrom-Json))

    # 8) 연결 해제: 마지막 줄이어도 JSON 유지, 다른 키 보존
    $r = Run $h @('-Remove'); $k = Keys $h
    Check '-Remove: 세션키퍼 연결 줄 제거, JSON 유지, 다른 키 그대로' ($r.code -eq 0 -and $r.key -eq '' -and -not $k.Contains('mod.open:session-keeper') -and [bool]($k | ConvertFrom-Json) -and $k.Contains('"alt-1"'))
    $r = Run $h @('-Remove'); Check '-Remove 를 또 하면 이미 없음(성공)' ($r.code -eq 0 -and $r.out -match '이미')
    $r = Run $h @('-Key', 'alt-shift-s'); $k = Keys $h
    Check '연결이 없을 때 새 키 연결' ($r.code -eq 0 -and $k.Contains('"alt-shift-s": "mod.open:session-keeper"') -and [bool]($k | ConvertFrom-Json))

    # 9) 키를 안 주고 연결도 없을 때: 기본 키, 단 기본 키를 다른 기능이 쓰면 거부
    $h2 = NewHome 'b' "{`n  `"global`": {`n    `"alt-1`": `"space.select:1`"`n  }`n}`n"
    $r = Run $h2 @(); $k = Keys $h2
    Check '연결 없음 + 키 안 줌: 기본 키 ctrl-shift-r 연결(LF 줄바꿈 파일은 LF 유지)' ($r.code -eq 0 -and $r.key -eq 'ctrl-shift-r' -and [bool]($k | ConvertFrom-Json) -and -not $k.Contains("`r`n"))
    $h3 = NewHome 'c' "{`n  `"global`": {`n    `"ctrl-shift-r`": `"pane.zoom`"`n  }`n}`n"
    $o3 = Keys $h3
    $r = Run $h3 @(); Check '기본 키를 다른 기능이 쓰고 있으면 거부(키 지정 없이도), 파일 불변' ($r.code -eq 1 -and $r.out -match 'pane\.zoom' -and (Keys $h3) -eq $o3)

    # 10) 이상한 파일
    $h4 = NewHome 'd' "{`n  `"other`": {}`n}`n"
    $o4 = Keys $h4; $r = Run $h4 @('-Key', 'alt-shift-s'); Check '"global" 구역이 없으면 건드리지 않음' ($r.code -eq 1 -and (Keys $h4) -eq $o4)
    $h5 = Join-Path $T 'e'; New-Item -ItemType Directory -Path $h5 -Force | Out-Null
    $r = Run $h5 @('-Key', 'alt-shift-s'); Check 'keys.json 이 없으면 만들지 않고 안내(코드 1)' ($r.code -eq 1 -and -not (Test-Path (Join-Path $h5 'keys.json')))

    # 11) 설치 폴더에서 실행: kit.env 의 APP_HOME 을 따라간다
    $h6 = NewHome 'f' $base
    $inst = Join-Path $T 'inst 폴더'; New-Item -ItemType Directory -Path $inst -Force | Out-Null
    Copy-Item -LiteralPath $sk -Destination $inst
    [IO.File]::WriteAllText((Join-Path $inst 'kit.env'), "NODE_DIR=x`r`nAPP_HOME=$h6`r`n", (New-Object Text.UTF8Encoding($false)))
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $inst 'set-key.ps1') -Key alt-shift-s 2>&1 | Out-String
    Check '설치 폴더의 set-key.ps1 은 kit.env 의 Herdr 설정 폴더를 사용' ((Keys $h6).Contains('"alt-shift-s": "mod.open:session-keeper"'))

    # 11b) 자유로운 키: 기호 키·F키 단독·표기 다양성 허용, 터미널 필수 키(Ctrl+C/D/Z)와 글자 단독 키만 거부, 겹침은 -Replace 로만 덮어쓰기
    $h8 = NewHome 'h' "{`n  `"global`": {`n    `"alt-1`": `"space.select:1`",`n    `"ctrl-,`": `"app.settings`",`n    `"alt-]`": `"tab.next`"`n  }`n}`n"
    foreach ($ok in @(@('ctrl-shift-/', 'ctrl-shift-/'), @('F9', 'f9'), @('Alt+9', 'alt-9'), @('ctrl-alt-.', 'ctrl-alt-.'), @('Shift+Ctrl+K', 'ctrl-shift-k'), @('ctrl-r', 'ctrl-r'), @('alt-pageup', 'alt-pageup'))) {
        $r = Run $h8 @('-Key', $ok[0]); $kk = Keys $h8
        Check "자유로운 키 허용: '$($ok[0])' -> $($ok[1])" ($r.code -eq 0 -and $r.key -eq $ok[1] -and [bool]($kk | ConvertFrom-Json) -and ([regex]::Matches($kk, 'mod\.open:session-keeper')).Count -eq 1)
    }
    $r = Run $h8 @('-Key', 'ctrl-r'); Check 'Ctrl+글자는 허용하되 터미널에서 막힌다는 참고를 알려 줌' ($r.code -eq 0 -and $r.out -match '터미널')
    foreach ($bad in @('ctrl-d', 'ctrl-z', 'q', 'shift-k', 'ctrl-', 'ctrl-shift')) { $before8 = Keys $h8; $r = Run $h8 @('-Key', $bad); Check "여전히 거부: '$bad'" ($r.code -eq 1 -and (Keys $h8) -eq $before8) }
    $r = Run $h8 @('-Key', 'alt-]'); Check '기호 키가 겹치면 기본은 거부(-Replace 없이)' ($r.code -eq 1 -and $r.out -match 'tab\.next' -and $r.out -match 'Replace')
    $r = Run $h8 @('-Key', 'alt-]', '-Replace'); $kk = Keys $h8
    Check '-Replace: 겹치는 기존 연결 한 줄만 해제하고 세션키퍼에 연결, 다른 키 보존, JSON 유지' ($r.code -eq 0 -and $r.key -eq 'alt-]' -and -not $kk.Contains('tab.next') -and $kk.Contains('"alt-]": "mod.open:session-keeper"') -and $kk.Contains('app.settings') -and $kk.Contains('space.select:1') -and [bool]($kk | ConvertFrom-Json))
    $r = Run $h8 @('-Key', 'ctrl-,', '-Replace'); $kk = Keys $h8
    Check '-Replace: 마지막 줄이어도 JSON 이 깨지지 않음' ($r.code -eq 0 -and -not $kk.Contains('app.settings') -and [bool]($kk | ConvertFrom-Json) -and ([regex]::Matches($kk, 'mod\.open:session-keeper')).Count -eq 1)

    # 12) 세션키퍼 창이 쓰는 명령(sessions.mjs set-key): 가짜 keys.json 으로 실제 변경, 이상한 입력은 거부
    $h7 = NewHome 'g' $base
    $env:HERDR_APP_HOME = $h7
    $o = & node (Join-Path $src 'sessions.mjs') set-key ctrl-alt-r --json 2>&1 | Out-String
    $j = $null; try { $j = $o | ConvertFrom-Json } catch {}
    Check 'sessions.mjs set-key: 창 버튼이 쓰는 명령으로 키가 바뀐다(JSON ok)' ($null -ne $j -and $j.ok -eq $true -and (Keys $h7).Contains('"ctrl-alt-r": "mod.open:session-keeper"'))
    $o = & node (Join-Path $src 'sessions.mjs') set-key alt-1 --json 2>&1 | Out-String
    $j = $null; try { $j = $o | ConvertFrom-Json } catch {}
    Check 'sessions.mjs set-key: 겹치는 키는 ok=false, 파일 불변' ($null -ne $j -and $j.ok -eq $false -and (Keys $h7).Contains('"ctrl-alt-r"'))
    $o = & node (Join-Path $src 'sessions.mjs') set-key 'a;b' --json 2>&1 | Out-String
    $j = $null; try { $j = $o | ConvertFrom-Json } catch {}
    Check 'sessions.mjs set-key: 이상한 글자는 실행 전에 거부' ($null -ne $j -and $j.ok -eq $false)
    Remove-Item Env:HERDR_APP_HOME -ErrorAction SilentlyContinue
} finally {
    Remove-Item Env:HERDR_APP_HOME -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}
"합계: PASS $script:pass / FAIL $script:fail"
