$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot '..\src\Http.ps1'
. $sourcePath

$script:Passed = 0
$script:Failed = 0
$script:Jobs = @()
$script:TempFiles = @()

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )

    if ($Expected -is [array] -or $Actual -is [array]) {
        $expectedText = @($Expected) -join '|'
        $actualText = @($Actual) -join '|'
        if ($expectedText -cne $actualText) {
            throw ("{0}. Expected '{1}', got '{2}'." -f $Message, $expectedText, $actualText)
        }
        return
    }

    if ($Expected -cne $Actual) {
        throw ("{0}. Expected '{1}', got '{2}'." -f $Message, $Expected, $Actual)
    }
}

function Assert-Throws {
    param(
        [scriptblock]$ScriptBlock,
        [string]$MessagePattern,
        [string]$Message
    )

    $thrown = $false
    $exceptionMessage = ''
    try {
        & $ScriptBlock
    }
    catch {
        $thrown = $true
        $exceptionMessage = $_.Exception.Message
    }

    if (-not $thrown) {
        throw ("{0}. Expected an exception." -f $Message)
    }

    if ($MessagePattern -and $exceptionMessage -notmatch $MessagePattern) {
        throw ("{0}. Exception '{1}' did not match '{2}'." -f $Message, $exceptionMessage, $MessagePattern)
    }
}

function New-LoopbackServer {
    $serverScript = {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        Write-Output ("READY|{0}" -f $port)

        function Send-Response {
            param(
                [System.Net.Sockets.NetworkStream]$Stream,
                [int]$StatusCode,
                [string]$Reason,
                [string[]]$Headers,
                [string]$Body,
                [int]$DelayMilliseconds = 0
            )

            if ($DelayMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }

            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $lines = New-Object System.Collections.Generic.List[string]
            [void]$lines.Add(("HTTP/1.1 {0} {1}" -f $StatusCode, $Reason))
            [void]$lines.Add('Connection: close')
            [void]$lines.Add(("Content-Length: {0}" -f $bodyBytes.Length))
            foreach ($header in $Headers) {
                [void]$lines.Add($header)
            }

            $responseText = ($lines -join "`r`n") + "`r`n`r`n"
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($responseText)
            $Stream.Write($responseBytes, 0, $responseBytes.Length)
            if ($bodyBytes.Length -gt 0) {
                $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
            }
            $Stream.Flush()
        }

        try {
            while ($true) {
                if (-not $listener.Pending()) {
                    Start-Sleep -Milliseconds 50
                    continue
                }
                $client = $null
                try {
                    $client = $listener.AcceptTcpClient()
                    $stream = $client.GetStream()
                    $stream.ReadTimeout = 5000
                    $buffer = New-Object byte[] 8192
                    $requestText = New-Object System.Text.StringBuilder
                    do {
                        $read = $stream.Read($buffer, 0, $buffer.Length)
                        if ($read -le 0) {
                            break
                        }
                        [void]$requestText.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $read))
                    } while ($requestText.ToString().IndexOf("`r`n`r`n", [System.StringComparison]::Ordinal) -lt 0)

                    $firstLine = ($requestText.ToString() -split "`r`n")[0]
                    $requestParts = $firstLine.Split(' ')
                    $requestTarget = if ($requestParts.Length -gt 1) { $requestParts[1] } else { '/' }
                    $requestUri = New-Object System.Uri (("http://127.0.0.1{0}" -f $requestTarget))
                    $path = $requestUri.AbsolutePath

                    switch ($path) {
                        '/success' {
                            Send-Response -Stream $stream -StatusCode 200 -Reason 'OK' -Headers @(
                                'X-Test: success',
                                'X-Multi: first',
                                'X-Multi: second'
                            ) -Body 'success'
                        }
                        '/nested/start' {
                            Send-Response -Stream $stream -StatusCode 302 -Reason 'Found' -Headers @('Location: ../final?via=relative') -Body ''
                        }
                        '/final' {
                            Send-Response -Stream $stream -StatusCode 200 -Reason 'OK' -Headers @('X-Final: yes') -Body 'final'
                        }
                        '/cli-start' {
                            Send-Response -Stream $stream -StatusCode 302 -Reason 'Found' -Headers @('Location: /cli-final') -Body ''
                        }
                        '/cli-final' {
                            Send-Response -Stream $stream -StatusCode 200 -Reason 'OK' -Headers @(
                                'Strict-Transport-Security: max-age=31536000',
                                'Content-Security-Policy: default-src ''self''',
                                'X-Content-Type-Options: nosniff',
                                'X-Frame-Options: DENY',
                                'Referrer-Policy: no-referrer',
                                'Permissions-Policy: geolocation=()',
                                'Set-Cookie: session=secret'
                            ) -Body 'cli'
                        }
                        '/not-found' {
                            Send-Response -Stream $stream -StatusCode 404 -Reason 'Not Found' -Headers @('X-Error: retained') -Body 'missing'
                        }
                        '/loop-a' {
                            Send-Response -Stream $stream -StatusCode 302 -Reason 'Found' -Headers @('Location: /loop-b') -Body ''
                        }
                        '/loop-b' {
                            Send-Response -Stream $stream -StatusCode 302 -Reason 'Found' -Headers @('Location: /loop-a') -Body ''
                        }
                        '/slow' {
                            Send-Response -Stream $stream -StatusCode 200 -Reason 'OK' -Headers @('X-Slow: yes') -Body 'slow' -DelayMilliseconds 3000
                        }
                        '/unsafe' {
                            Send-Response -Stream $stream -StatusCode 302 -Reason 'Found' -Headers @('Location: file:///tmp/blocked') -Body ''
                        }
                        '/missing-location' {
                            Send-Response -Stream $stream -StatusCode 302 -Reason 'Found' -Headers @() -Body ''
                        }
                        default {
                            Send-Response -Stream $stream -StatusCode 404 -Reason 'Not Found' -Headers @() -Body 'unknown'
                        }
                    }
                }
                catch {
                    # A client may close a headers-only response before the body is sent.
                }
                finally {
                    if ($client) {
                        $client.Close()
                    }
                }
            }
        }
        finally {
            $listener.Stop()
        }
    }

    $job = Start-Job -ScriptBlock $serverScript
    $script:Jobs += $job
    $port = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not $port -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $output = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        foreach ($line in $output) {
            if ([string]$line -match '^READY\|(\d+)$') {
                $port = [int]$Matches[1]
                break
            }
        }
    }

    if (-not $port) {
        throw 'Loopback server did not become ready.'
    }

    return "http://127.0.0.1:$port"
}

function Invoke-Test {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    try {
        & $Body
        $script:Passed++
        Write-Output ("PASS {0}" -f $Name)
    }
    catch {
        $script:Failed++
        Write-Output ("FAIL {0}: {1}" -f $Name, $_.Exception.Message)
    }
}

try {
    $baseUrl = New-LoopbackServer

    Invoke-Test 'returns successful status and case-insensitive merged headers' {
        $result = Get-HttpResponseHeaders -Url "$baseUrl/success"
        Assert-Equal 200 $result.StatusCode 'status code'
        Assert-Equal "$baseUrl/success" $result.FinalUrl 'final URL'
        Assert-Equal 'success' $result.Headers['x-test'] 'header lookup should ignore case'
        Assert-Equal 'first, second' $result.Headers['X-Multi'] 'multi-valued header'
        Assert-Equal 0 $result.Redirects.Count 'redirect count'
    }

    Invoke-Test 'follows relative redirects and records the final URL' {
        $result = Get-HttpResponseHeaders -Url "$baseUrl/nested/start"
        Assert-Equal 200 $result.StatusCode 'redirect final status'
        Assert-Equal "$baseUrl/final?via=relative" $result.FinalUrl 'resolved final URL'
        Assert-Equal 1 $result.Redirects.Count 'redirect count'
        Assert-Equal "$baseUrl/nested/start" $result.Redirects[0].From 'redirect source'
        Assert-Equal "$baseUrl/final?via=relative" $result.Redirects[0].To 'redirect target'
        Assert-Equal 302 $result.Redirects[0].StatusCode 'redirect status'
    }

    Invoke-Test 'runs the JSON CLI in Windows PowerShell and omits raw headers' {
        $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Assert-True (Test-Path -LiteralPath $windowsPowerShell) 'Windows PowerShell 5.1 executable is required for this integration test'
        $scanScript = Join-Path $PSScriptRoot '..\Scan-Headers.ps1'
        $cliOutput = @(
            & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scanScript -Url "$baseUrl/cli-start" -Json 2>&1
        )
        Assert-Equal 0 $LASTEXITCODE 'Windows PowerShell CLI exit code'
        $jsonText = $cliOutput -join [Environment]::NewLine
        $report = $jsonText | ConvertFrom-Json
        Assert-Equal 200 $report.StatusCode 'CLI final status'
        Assert-Equal "$baseUrl/cli-final" $report.FinalUrl 'CLI final URL'
        Assert-Equal 6 @($report.Findings).Count 'CLI finding count'
        Assert-True ($jsonText -notmatch 'Set-Cookie|session=secret') 'CLI report must not disclose raw cookie headers'
    }

    Invoke-Test 'retains non-success final responses' {
        $result = Get-HttpResponseHeaders -Url "$baseUrl/not-found"
        Assert-Equal 404 $result.StatusCode '404 status'
        Assert-Equal 'retained' $result.Headers['X-Error'] '404 response headers'
    }

    Invoke-Test 'stops redirect loops at the configured cap' {
        Assert-Throws {
            Get-HttpResponseHeaders -Url "$baseUrl/loop-a" -MaxRedirects 2
        } 'redirect|maximum|cap' 'redirect loop cap'
    }

    Invoke-Test 'bounds the whole operation with the timeout' {
        Assert-Throws {
            Get-HttpResponseHeaders -Url "$baseUrl/slow" -TimeoutSeconds 1
        } 'tim(e|ed)[ -]?out|cancel' 'request timeout'
    }

    Invoke-Test 'rejects malformed, unsupported, and credential-bearing URLs' {
        Assert-Throws { Get-HttpResponseHeaders -Url 'not-a-url' } 'URL|absolute|invalid' 'malformed URL'
        Assert-Throws { Get-HttpResponseHeaders -Url 'ftp://127.0.0.1/file' } 'http|https|scheme' 'unsupported scheme'
        Assert-Throws { Get-HttpResponseHeaders -Url 'http://user:password@127.0.0.1/' } 'credential|userinfo|user' 'URL credentials'
    }

    Invoke-Test 'rejects unsafe and incomplete redirects' {
        Assert-Throws {
            Get-HttpResponseHeaders -Url "$baseUrl/unsafe"
        } 'redirect|http|https|scheme' 'non-http redirect'
        Assert-Throws {
            Get-HttpResponseHeaders -Url "$baseUrl/missing-location"
        } 'Location|redirect' 'redirect without Location'
    }

    Invoke-Test 'enforces timeout and redirect parameter ranges' {
        Assert-Throws { Get-HttpResponseHeaders -Url "$baseUrl/success" -TimeoutSeconds 0 } 'range|validate|argument' 'timeout lower bound'
        Assert-Throws { Get-HttpResponseHeaders -Url "$baseUrl/success" -TimeoutSeconds 121 } 'range|validate|argument' 'timeout upper bound'
        Assert-Throws { Get-HttpResponseHeaders -Url "$baseUrl/success" -MaxRedirects -1 } 'range|validate|argument' 'redirect lower bound'
        Assert-Throws { Get-HttpResponseHeaders -Url "$baseUrl/success" -MaxRedirects 11 } 'range|validate|argument' 'redirect upper bound'
    }
}
finally {
    foreach ($job in @($script:Jobs)) {
        if ($job -and $job.State -eq 'Running') {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
        }
        if ($job) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($tempFile in @($script:TempFiles)) {
        if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Output ("Summary: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) {
    exit 1
}
