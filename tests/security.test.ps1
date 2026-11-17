# 보안 시험: 명령 주입·ID 검사. 키퍼 함수(ConvertTo-PsSingleQuoted, $UuidRe)를 직접 불러 적대적 입력으로 확인한다. 아무것도 쓰거나 실행하지 않는다(문법 분석만).
# 마지막 줄 "합계: PASS n / FAIL m" 형식은 run-all 이 읽는다.
$ErrorActionPreference = 'Continue'
$env:KEEPER_NO_MAIN = '1'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'session-keeper.ps1')
$pass = 0; $fail = 0
function Check([string]$n, $c, [string]$d = '') { if ($c) { $script:pass++; "PASS  $n" } else { $script:fail++; "FAIL  $n  $d" } }
$sid = '01234567-89ab-cdef-0123-456789abcdef'
$sq = [string][char]0x2018; $sq2 = [string][char]0x2019; $sq3 = [string][char]0x201A; $sq4 = [string][char]0x201B
$dq = [string][char]0x201C; $dq2 = [string][char]0x201D
$hostile = @(
    "C:\work\plain",
    "C:\a'b", "C:\a''b", "C:\a'; calc; '",
    "C:\a${sq}; calc; ${sq2}", "C:\a${sq3}; calc; ${sq4}", "C:\a${sq}${sq2}${sq3}${sq4}",
    'C:\a`; calc', 'C:\a$(calc)', 'C:\a$env:USERNAME', 'C:\a${calc}',
    'C:\a" ; calc ; "', "C:\a${dq}; calc; ${dq2}",
    'C:\a|calc', 'C:\a&calc', 'C:\a#c', 'C:\a<calc>',
    "C:\a`ncalc", "C:\a`r`ncalc",
    ('C:\' + ('x' * 5000)),
    "C:\한글 경로\공백 있음\(괄호)[대괄호]{중괄호}"
)
foreach ($h in $hostile) {
    $label = ($h -replace "[\r\n]", '<NL>'); if ($label.Length -gt 40) { $label = $label.Substring(0, 40) + '…' }
    $cmd = "Set-Location -LiteralPath '" + (ConvertTo-PsSingleQuoted $h) + "'; " + ('claude --resume {0}' -f $sid)
    $e = $null; $t = $null; $ast = [Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$t, [ref]$e)
    $cmds = @($ast.FindAll({ param($x) $x -is [Management.Automation.Language.CommandAst] }, $true))
    $sub = @($ast.FindAll({ param($x) $x -is [Management.Automation.Language.SubExpressionAst] -or $x -is [Management.Automation.Language.ExpandableStringExpressionAst] -or $x -is [Management.Automation.Language.VariableExpressionAst] -or $x -is [Management.Automation.Language.ScriptBlockExpressionAst] }, $true))
    $strs = @($ast.FindAll({ param($x) $x -is [Management.Automation.Language.StringConstantExpressionAst] -and $x.StringConstantType -eq 'SingleQuoted' }, $true))
    $ok = (@($e).Count -eq 0) -and ($cmds.Count -eq 2) -and ($sub.Count -eq 0) -and ($strs.Count -eq 1) -and ($strs[0].Value -ceq $h) -and ($cmds[0].GetCommandName() -eq 'Set-Location') -and ($cmds[1].GetCommandName() -eq 'claude')
    Check "명령 주입 시도 차단·경로가 글자 그대로 보존: $label" $ok "errors=$(@($e).Count) cmds=$($cmds.Count) sub=$($sub.Count) strs=$($strs.Count)"
}
# 세션 ID 형식 검사: 키퍼가 쓰는 UuidRe 로 이상한 ID 를 거르는지
foreach ($bad in @("$sid; calc", "$sid`ncalc", "$sid`n", "$sid`r`n", "$sid`r", "../../$sid", "$sid ", (' ' + $sid), ($sid + 'x'), "'$sid'", '$(calc)', '')) {
    Check "세션ID 형식 검사가 거부: [$($bad -replace '[\r\n]','<NL>')]" ($bad -notmatch $UuidRe)
}
Check '정상 UUID 는 통과' ($sid -match $UuidRe)
"합계: PASS $pass / FAIL $fail"
if ($script:fail -gt 0) { exit 1 }
