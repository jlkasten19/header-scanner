# Read a single page's response headers. No response body is processed or saved.
param(
    [string]$Url,
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 20,
    [ValidateRange(0, 10)][int]$MaxRedirects = 5,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src/Http.ps1')
. (Join-Path $PSScriptRoot 'src/Headers.ps1')
. (Join-Path $PSScriptRoot 'src/Output.ps1')

if (-not $PSBoundParameters.ContainsKey('Url')) {
    $Url = Read-Host 'Enter an http:// or https:// URL'
}

try {
    $response = Get-HttpResponseHeaders -Url $Url -TimeoutSeconds $TimeoutSeconds -MaxRedirects $MaxRedirects
    $report = [pscustomobject]@{
        ScannedAtUtc = [DateTime]::UtcNow.ToString('o')
        RequestedUrl = $response.RequestedUrl
        FinalUrl = $response.FinalUrl
        StatusCode = $response.StatusCode
        Redirects = @($response.Redirects)
        Findings = @(Get-SecurityHeaderFindings -Headers $response.Headers -Url $response.FinalUrl)
        Scope = 'Observations from one response. Present does not mean secure; missing does not prove a vulnerability.'
    }

    if ($Json) {
        ConvertTo-SafeJson $report
    } else {
        # Strip terminal control characters from values supplied by the remote server.
        Write-Output ('Requested: ' + (ConvertTo-SafeTerminalText $report.RequestedUrl))
        Write-Output ('Final URL: ' + (ConvertTo-SafeTerminalText $report.FinalUrl))
        Write-Output "HTTP status: $($report.StatusCode) | Redirects: $($report.Redirects.Count)"
        Write-Output ''
        foreach ($finding in $report.Findings) {
            Write-Output "[$($finding.Status)] $($finding.Header)"
            if ($finding.Value) { Write-Output ('  Value: ' + (ConvertTo-SafeTerminalText $finding.Value)) }
            Write-Output "  $($finding.Note)"
            Write-Output ''
        }
        Write-Output $report.Scope
    }
} catch {
    Write-Error -Message ('Scan failed: ' + (ConvertTo-SafeTerminalText $_.Exception.Message)) -ErrorAction Continue
    exit 1
}
