$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/Headers.ps1')
$failures = 0
$checks = 0

function Assert-Finding {
    param($Name, $Headers, $Header, $Expected, $Url = 'https://example.com/')
    $script:checks++
    $findings = @(Get-SecurityHeaderFindings -Headers $Headers -Url $Url)
    $selected = @($findings | Where-Object { $_.Header -eq $Header })
    if (($findings.Count -eq 6) -and ($selected.Count -eq 1) -and ($selected[0].Status -eq $Expected)) {
        Write-Output "PASS: $Name"
    } else {
        $script:failures++
        Write-Output "FAIL: $Name (expected $Expected; got $($selected.Status -join ', '); findings $($findings.Count))"
    }
}

Assert-Finding 'Missing HTTPS HSTS' @{} 'Strict-Transport-Security' 'Missing'
Assert-Finding 'Case-insensitive header names' @{'x-content-type-options'='nosniff'} 'X-Content-Type-Options' 'Present'
Assert-Finding 'Positive HSTS max-age' @{'Strict-Transport-Security'='max-age=31536000; includeSubDomains'} 'Strict-Transport-Security' 'Present'
Assert-Finding 'Disabled HSTS' @{'Strict-Transport-Security'='max-age=0'} 'Strict-Transport-Security' 'Review'
Assert-Finding 'Malformed HSTS' @{'Strict-Transport-Security'='max-age=banana'} 'Strict-Transport-Security' 'Review'
Assert-Finding 'Duplicate HSTS age directives' @{'Strict-Transport-Security'='max-age=0; max-age=9999'} 'Strict-Transport-Security' 'Review'
Assert-Finding 'HTTP HSTS ignored by browsers' @{'Strict-Transport-Security'='max-age=31536000'} 'Strict-Transport-Security' 'Not applicable' 'http://example.com/'
Assert-Finding 'HSTS does not apply to IP hosts' @{'Strict-Transport-Security'='max-age=31536000'} 'Strict-Transport-Security' 'Not applicable' 'https://127.0.0.1/'
Assert-Finding 'Enforcing CSP exists' @{'Content-Security-Policy'="default-src 'self'"} 'Content-Security-Policy' 'Present'
Assert-Finding 'Report-only CSP is not enforcing' @{'Content-Security-Policy-Report-Only'="default-src 'self'"} 'Content-Security-Policy' 'Review'
Assert-Finding 'Whitespace CSP is absent' @{'Content-Security-Policy'='   '} 'Content-Security-Policy' 'Missing'
Assert-Finding 'Empty headers do not count as policies' @{'Permissions-Policy'=''} 'Permissions-Policy' 'Missing'
Assert-Finding 'Permissions policy presence only' @{'Permissions-Policy'='geolocation=()'} 'Permissions-Policy' 'Present'
Assert-Finding 'Invalid MIME sniffing value' @{'X-Content-Type-Options'='something-else'} 'X-Content-Type-Options' 'Review'
Assert-Finding 'XFO DENY case-insensitive' @{'X-Frame-Options'='deny'} 'X-Frame-Options' 'Present'
Assert-Finding 'XFO SAMEORIGIN' @{'X-Frame-Options'='SAMEORIGIN'} 'X-Frame-Options' 'Present'
Assert-Finding 'Obsolete XFO ALLOW-FROM' @{'X-Frame-Options'='ALLOW-FROM https://example.com'} 'X-Frame-Options' 'Review'
Assert-Finding 'CSP framing alternative needs review' @{'Content-Security-Policy'="frame-ancestors 'none'"} 'X-Frame-Options' 'Review'
Assert-Finding 'CSP framing in a later policy' @{'Content-Security-Policy'=@("default-src 'self'", "frame-ancestors 'none'")} 'X-Frame-Options' 'Review'
Assert-Finding 'Report-only does not replace XFO' @{'Content-Security-Policy-Report-Only'="frame-ancestors 'none'"} 'X-Frame-Options' 'Missing'
Assert-Finding 'Recognized referrer policy' @{'Referrer-Policy'='strict-origin-when-cross-origin'} 'Referrer-Policy' 'Present'
Assert-Finding 'Unsafe referrer policy flagged' @{'Referrer-Policy'='unsafe-url'} 'Referrer-Policy' 'Review'
Assert-Finding 'Unknown referrer policy' @{'Referrer-Policy'='made-up'} 'Referrer-Policy' 'Review'
Assert-Finding 'Referrer fallback uses last recognized token' @{'Referrer-Policy'='unsafe-url, no-referrer, unknown'} 'Referrer-Policy' 'Present'
Assert-Finding 'Referrer final recognized unsafe token' @{'Referrer-Policy'='no-referrer, unsafe-url'} 'Referrer-Policy' 'Review'
Assert-Finding 'Repeated conflicting nosniff values' @{'X-Content-Type-Options'=@('nosniff','wrong')} 'X-Content-Type-Options' 'Review'

Write-Output "$($checks - $failures)/$checks header checks passed."
if ($failures -gt 0) { exit 1 }
