$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/Output.ps1')
$failed = 0

$inputText = 'before' + [char]0x1b + '[31m' + [char]0x9b + 'after' + [char]0x202e
if ((ConvertTo-SafeTerminalText $inputText) -ceq 'before?[31m?after?') {
    Write-Output 'PASS: terminal control and formatting characters are replaced'
} else { $failed++; Write-Output 'FAIL: terminal control and formatting characters are replaced' }

if ((ConvertTo-SafeTerminalText "first`nsecond") -ceq 'first?second') {
    Write-Output 'PASS: embedded newlines cannot forge output lines'
} else { $failed++; Write-Output 'FAIL: embedded newlines cannot forge output lines' }

$unicodeText = 'caf' + [char]0xe9 + [char]0x9b + [char]0x202e + [char]0x1b + [char]::ConvertFromUtf32(0x1f600)
$json = ConvertTo-SafeJson ([pscustomobject]@{ Value=$unicodeText; StatusCode=200; List=@('one','two') })
$decoded = $json | ConvertFrom-Json
if (($json -notmatch '[^\x00-\x7f]') -and (-not $json.Contains([string][char]0x1b)) -and
    ($decoded.Value -ceq $unicodeText) -and ($decoded.StatusCode -eq 200) -and ($decoded.List.Count -eq 2)) {
    Write-Output 'PASS: JSON escapes unsafe display characters and round-trips original data'
} else { $failed++; Write-Output 'FAIL: JSON escapes unsafe display characters and round-trips original data' }

Write-Output "$((3 - $failed))/3 output checks passed."
if ($failed -gt 0) { exit 1 }
