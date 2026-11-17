# set-key.ps1 - 세션키퍼 창을 여는 단축키를 확인/변경/원래대로/연결 해제 한다. (Herdr 의 keys.json 에서 세션키퍼 한 줄만 건드립니다)
#
#   지금 키 확인:   powershell -NoProfile -ExecutionPolicy Bypass -File set-key.ps1 -Show
#   키 바꾸기:      powershell -NoProfile -ExecutionPolicy Bypass -File set-key.ps1 -Key ctrl-alt-r      (Ctrl+Alt+R 처럼 써도 됩니다)
#   원래대로:       ... -File set-key.ps1 -Reset      (기본 키 Ctrl+Shift+R)
#   키 연결 해제:   ... -File set-key.ps1 -Remove     (키만 끔. 팔레트 Ctrl+Shift+P -> mod.open session-keeper 로는 계속 열 수 있음)
#   겹쳐도 덮어쓰기: ... -File set-key.ps1 -Key ctrl-alt-k -Replace   (그 키를 쓰던 기존 연결 한 줄을 해제하고 세션키퍼에 연결. 백업 있음)
#   미리 점검만:    ... -File set-key.ps1 -Key ctrl-alt-r -DryRun   (아무것도 쓰지 않고 가능 여부만 알려 줌)
#
# 안전 규칙
#   - 바꾸려는 키를 Herdr 가 이미 다른 기능에 쓰고 있으면 기본은 거부(어떤 기능과 겹치는지 알려 줌). -Replace 를 붙여야만 그 한 줄을 해제합니다.
#   - 터미널 필수 키(Ctrl+C/D/Z)와, Ctrl/Alt 없는 글자 키는 거부합니다. F1-F12 는 혼자 써도 되고, 기호 키(ctrl-, alt-] 등)도 됩니다.
#   - 수정한 결과가 올바른 JSON 이 아니면 파일을 그대로 두고 멈춥니다. 처음 한 번은 원본을 keys.json.bak-before-session-keeper-kit 로 백업합니다.
# 결과 마지막 줄: KEY=<지금 연결된 키>  (없으면 빈 값). 종료 코드 0=성공/이미 그 상태, 1=거부·실패.
param(
    [string]$Key = '',
    [switch]$Show,
    [switch]$Reset,
    [switch]$Remove,
    [switch]$DryRun,
    [switch]$Replace,
    [string]$HerdrHome = ''
)
$ErrorActionPreference = 'Stop'
$DefaultKey = 'ctrl-shift-r'
function Say([string]$m) { Write-Host $m }
function Finish([string]$k, [int]$code) { Write-Host "KEY=$k"; exit $code }
function Write-Utf8NoBom([string]$path, [string]$text) {
    $tmp = "$path.tmp-kit"
    [IO.File]::WriteAllBytes($tmp, (New-Object Text.UTF8Encoding($false)).GetBytes($text))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}
function Format-Key([string]$k) { if (-not $k) { return '(없음)' }; return (($k -split '-') | ForEach-Object { if ($_.Length -le 1) { $_.ToUpperInvariant() } else { (Get-Culture).TextInfo.ToTitleCase($_) } }) -join '+' }

# Herdr 설정 폴더: -HerdrHome > 설치 폴더의 kit.env(APP_HOME) > 환경 변수 HERDR_APP_HOME > 기본 위치
if (-not $HerdrHome) {
    $ke = Join-Path $PSScriptRoot 'kit.env'
    if (Test-Path -LiteralPath $ke) { foreach ($ln in [IO.File]::ReadAllLines($ke)) { if ($ln -match '^APP_HOME=(.+)$') { $HerdrHome = $Matches[1].Trim() } } }
}
if (-not $HerdrHome) { $HerdrHome = $(if ($env:HERDR_APP_HOME) { $env:HERDR_APP_HOME } else { Join-Path $env:USERPROFILE '.config\herdr-app' }) }
$KeysFile = Join-Path $HerdrHome 'keys.json'
if (-not (Test-Path -LiteralPath $KeysFile)) { Say "keys.json 이 없습니다: $KeysFile  (Herdr 를 한 번 실행한 뒤 다시 하세요. 그동안은 팔레트 Ctrl+Shift+P -> mod.open session-keeper 로 열 수 있습니다.)"; Finish '' 1 }

# 키 이름 정리: "Ctrl+Alt+K" / "ctrl-alt-k" / "ctrl-," / "f9" -> 쓰는 형식(ctrl-alt-k). 못 쓰는 키면 $null 과 이유를 돌려준다.
function Resolve-KeyName([string]$s) {
    $t = ($s.Trim().ToLowerInvariant()) -replace '\s', ''
    if (-not $t) { return @{ name = $null; why = '키가 비어 있습니다.'; note = '' } }
    $mods = @(); $rest = $t
    while ($rest -match '^(ctrl|alt|shift)[+-](.+)$') { $mods += $Matches[1]; $rest = $Matches[2] }
    $key = $rest
    if ($key -notmatch '^([a-z0-9]|f([1-9]|1[0-2])|pageup|pagedown|home|end|insert|delete|backspace|tab|space|enter|left|right|up|down|[\[\]\\/,.;`=+\-])$') { return @{ name = $null; why = "'$key' 는 쓸 수 없는 키입니다 (영문·숫자·기호 한 글자, F1-F12, 방향키, PageUp/PageDown, Home/End, Tab, Space, Enter 등). 예: ctrl-alt-k, alt-shift-9, f9"; note = '' } }
    if (@($mods | Select-Object -Unique).Count -ne $mods.Count) { return @{ name = $null; why = '같은 조합 키(ctrl/alt/shift)가 두 번 들어 있습니다.'; note = '' } }
    $isF = ($key -match '^f([1-9]|1[0-2])$')
    if ($mods.Count -eq 0 -and -not $isF) { return @{ name = $null; why = 'Ctrl 또는 Alt 와 함께 쓰세요(글자만 누르는 키를 가로채면 입력이 막힙니다). F1-F12 는 혼자 써도 됩니다.'; note = '' } }
    if ($mods.Count -gt 0 -and $mods -notcontains 'ctrl' -and $mods -notcontains 'alt' -and -not $isF) { return @{ name = $null; why = 'Shift 만으로는 일반 입력과 구분되지 않습니다. Ctrl 이나 Alt 를 함께 쓰세요.'; note = '' } }
    $note = ''
    if ($mods.Count -eq 1 -and $mods[0] -eq 'ctrl' -and $key -match '^[a-z]$') {
        if ($key -in @('c', 'd', 'z')) { return @{ name = $null; why = "Ctrl+$($key.ToUpperInvariant()) 는 터미널의 중단·종료·정지 키라 쓸 수 없습니다. 다른 조합을 고르세요. 예: ctrl-shift-$key"; note = '' } }
        $note = "참고: Ctrl+$($key.ToUpperInvariant()) 는 터미널 안에서도 쓰는 키입니다. 연결하면 Herdr 가 먼저 가져가 터미널에서는 그 키가 동작하지 않습니다."
    }
    $ordered = @(@('ctrl', 'alt', 'shift') | Where-Object { $mods -contains $_ }) + $key
    return @{ name = ($ordered -join '-'); why = ''; note = $note }
}

$raw = [IO.File]::ReadAllText($KeysFile, [Text.Encoding]::UTF8)
$nl = $(if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" })
$ourPattern = '[ \t]*"[^"]+"\s*:\s*"mod\.open:session-keeper",?\r?\n'
$current = @([regex]::Matches($raw, '"([^"]+)"\s*:\s*"mod\.open:session-keeper"') | ForEach-Object { $_.Groups[1].Value })
$cur = $(if ($current.Count -gt 0) { $current[0] } else { '' })

function Remove-Ours([string]$text) {
    $t = [regex]::Replace($text, $ourPattern, '')
    $ok = $true; try { $null = $t | ConvertFrom-Json } catch { $ok = $false }
    if (-not $ok) {                                   # 마지막 줄을 지워 앞 줄에 쉼표가 남은 경우만 고쳐 본다
        $t2 = [regex]::Replace($t, ',(\s*\})', '$1')
        $ok2 = $true; try { $null = $t2 | ConvertFrom-Json } catch { $ok2 = $false }
        if ($ok2) { return $t2 }
    }
    return $t
}
function Test-Json([string]$text) { try { $null = $text | ConvertFrom-Json; return $true } catch { return $false } }
function Save-Keys([string]$text) {
    $bak = "$KeysFile.bak-before-session-keeper-kit"
    if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $KeysFile -Destination $bak; Say "  keys.json 백업: $bak" }
    Write-Utf8NoBom $KeysFile $text
}

# ---------- 확인 ----------
if ($Show) {
    if ($current.Count -eq 0) { Say '세션키퍼 단축키: 연결되어 있지 않습니다. (팔레트 Ctrl+Shift+P -> mod.open session-keeper 로 열 수 있습니다)' }
    else { Say ('세션키퍼 단축키: ' + (Format-Key $cur) + $(if ($current.Count -gt 1) { '  (참고: 같은 기능에 키가 ' + $current.Count + '개 연결되어 있습니다: ' + ($current -join ', ') + ')' } else { '' })) }
    Finish $cur 0
}

# ---------- 쓰기 전 확인: 읽기 전용 파일은 건드리지 않는다(사용자가 일부러 잠가 둔 것일 수 있다) ----------
if ((Get-Item -LiteralPath $KeysFile).IsReadOnly) { Say "keys.json 이 읽기 전용이라 바꾸지 않았습니다. 바꾸려면 파일의 '읽기 전용' 표시를 직접 해제한 뒤 다시 하세요: $KeysFile"; Finish $cur 1 }

# ---------- 연결 해제 ----------
if ($Remove) {
    if ($current.Count -eq 0) { Say '이미 연결된 키가 없습니다.'; Finish '' 0 }
    $new = Remove-Ours $raw
    if (-not (Test-Json $new)) { Say '수정 결과가 올바른 JSON 이 아니라 중단했습니다(파일 그대로).'; Finish $cur 1 }
    if ($DryRun) { Say "점검: 키 연결($(Format-Key $cur))을 해제할 수 있습니다(아무것도 쓰지 않음)."; Finish $cur 0 }
    Save-Keys $new
    Say "키 연결 해제 완료: $(Format-Key $cur)  (팔레트 Ctrl+Shift+P -> mod.open session-keeper 로는 계속 열 수 있습니다)"
    Finish '' 0
}

# ---------- 어떤 키로 할지 ----------
$ensure = $false
if ($Reset) { $want = $DefaultKey }
elseif ($Key) {
    $r = Resolve-KeyName $Key
    if (-not $r.name) { Say "이 키는 쓸 수 없습니다: $($r.why)"; Finish $cur 1 }
    $want = $r.name
    if ($r.note) { Say $r.note }
} else {
    $ensure = $true                                   # 키를 지정하지 않음: 이미 연결된 키가 있으면 그대로, 없으면 기본 키
    if ($current.Count -gt 0) { Say "이미 연결되어 있습니다: $(Format-Key $cur)"; Finish $cur 0 }
    $want = $DefaultKey
}

if ($current.Count -eq 1 -and $current[0] -eq $want) { Say "이미 $(Format-Key $want) 로 연결되어 있습니다."; Finish $want 0 }

# ---------- 겹침 검사 ----------
$base = Remove-Ours $raw
$kq = [regex]::Escape($want)
$hit = [regex]::Match($base, '"' + $kq + '"\s*:\s*"([^"]*)"')
if ($hit.Success -or [regex]::IsMatch($base, '"' + $kq + '"\s*:')) {
    $what = $(if ($hit.Success) { $hit.Groups[1].Value } else { '(다른 설정)' })
    if (-not $Replace) {
        Say "$(Format-Key $want) 는 Herdr 에서 이미 다른 기능($what)에 쓰고 있어 바꾸지 않았습니다. 다른 키를 고르거나, 그 기능을 해제하고 쓰려면 -Replace 를 붙이세요."
        if ($ensure) { Say '(팔레트 Ctrl+Shift+P -> mod.open session-keeper 로는 열 수 있습니다)' }
        Finish $cur 1
    }
    # -Replace: 겹치는 기존 연결 한 줄만 지운다(원본은 keys.json.bak-before-session-keeper-kit 에 백업)
    $b2 = [regex]::Replace($base, '[ \t]*"' + $kq + '"\s*:\s*"[^"]*",?\r?\n', '')
    if (-not (Test-Json $b2)) { $b2 = [regex]::Replace($b2, ',(\s*\})', '$1') }
    if (-not (Test-Json $b2) -or [regex]::IsMatch($b2, '"' + $kq + '"\s*:')) { Say '겹치는 기존 연결을 안전하게 지우지 못해 바꾸지 않았습니다(파일 그대로). keys.json 을 직접 열어 확인해 주세요.'; Finish $cur 1 }
    $base = $b2
    Say "기존 연결($(Format-Key $want) = $what)을 해제하고 세션키퍼에 연결합니다."
}

$m = [regex]::Match($base, '"global"\s*:\s*\{\r?\n')
if (-not $m.Success) { Say 'keys.json 에서 "global" 구역을 찾지 못해 바꾸지 않았습니다.'; Finish $cur 1 }
$tail = $base.Substring($m.Index + $m.Length)
$indent = '    '
$im = [regex]::Match($tail, '^([ \t]+)"')
if ($im.Success) { $indent = $im.Groups[1].Value }                      # 파일이 쓰는 들여쓰기에 맞춘다
$comma = $(if ($tail -match '^\s*\}') { '' } else { ',' })              # global 이 비어 있으면(마지막 항목) 쉼표 없이
$new = $base.Insert($m.Index + $m.Length, $indent + '"' + $want + '": "mod.open:session-keeper"' + $comma + $nl)
if (-not (Test-Json $new)) { Say '수정 결과가 올바른 JSON 이 아니라 중단했습니다(파일 그대로).'; Finish $cur 1 }
if ($DryRun) { Say "점검: $(Format-Key $want) 로 연결할 수 있습니다(아무것도 쓰지 않음)."; Finish $cur 0 }

Save-Keys $new
Say $(if ($cur) { "단축키를 바꿨습니다: $(Format-Key $cur) -> $(Format-Key $want)" } else { "키 연결 완료: $(Format-Key $want)" })
Say '  (Herdr 가 바로 인식하지 못하면 Herdr 를 한 번 껐다 켜세요.)'
Finish $want 0
