function Get-SecurityHeaderFindings {
    param([System.Collections.IDictionary]$Headers, [uri]$Url)

    # Copy names into a case-insensitive lookup without changing the input.
    $lookup = @{}
    foreach ($key in $Headers.Keys) {
        $lookup[[string]$key] = (@($Headers[$key]) -join ', ').Trim()
    }
    $names = @('Strict-Transport-Security', 'Content-Security-Policy',
        'X-Content-Type-Options', 'X-Frame-Options', 'Referrer-Policy', 'Permissions-Policy')

    foreach ($name in $names) {
        $value = [string]$lookup[$name]
        $status = 'Missing'
        $note = 'Not found in this response. Check whether it is needed for this page.'
        if ($value) { $status = 'Present' }

        switch ($name) {
            'Strict-Transport-Security' {
                if (($Url.Scheme -ne 'https') -or ($Url.HostNameType -ne [System.UriHostNameType]::Dns)) {
                    $status = 'Not applicable'
                    $note = 'Browsers apply HSTS to domain names over HTTPS, not HTTP responses or IP hosts.'
                } elseif ($value) {
                    $ages = [regex]::Matches($value, '(?i)(?:^|;)\s*max-age\s*=\s*(\d+)\s*(?=;|$)')
                    $age = [uint64]0
                    if (($ages.Count -eq 1) -and ([uint64]::TryParse($ages[0].Groups[1].Value, [ref]$age)) -and ($age -gt 0)) {
                        $note = 'A positive max-age was found. Review the duration and subdomain scope; this is not a full policy validation.'
                    } else {
                        $status = 'Review'
                        $note = 'No single positive, unquoted max-age was recognized. A zero value disables HSTS; inspect malformed or repeated directives.'
                    }
                }
            }
            'Content-Security-Policy' {
                if ($value) {
                    $note = 'An enforcing CSP header is present. Directive syntax, allowed sources, and policy strength need manual review.'
                } elseif ($lookup['Content-Security-Policy-Report-Only']) {
                    $status = 'Review'
                    $note = 'Only Content-Security-Policy-Report-Only was found. That header reports violations without enforcing the policy.'
                }
            }
            'X-Content-Type-Options' {
                if ($value -and ($value -ieq 'nosniff')) {
                    $note = 'The nosniff value was found.'
                } elseif ($value) {
                    $status = 'Review'
                    $note = 'Expected a single nosniff value. Review the supplied value.'
                }
            }
            'X-Frame-Options' {
                if ($value -and ($value -imatch '\A(?:DENY|SAMEORIGIN)\z')) {
                    $note = 'A recognized framing value was found. Check that it matches the intended embedding behavior.'
                } elseif ($value) {
                    $status = 'Review'
                    $note = 'Expected DENY or SAMEORIGIN. Other or conflicting values need review.'
                } elseif ($lookup['Content-Security-Policy'] -match '(?i)(?:^|[;,])\s*frame-ancestors\s+[^;,]+') {
                    $status = 'Review'
                    $note = 'X-Frame-Options is absent, but the enforcing CSP includes frame-ancestors. Inspect that directive before adding a separate framing header.'
                }
            }
            'Referrer-Policy' {
                if ($value) {
                    $known = @('no-referrer', 'no-referrer-when-downgrade', 'origin', 'origin-when-cross-origin',
                        'same-origin', 'strict-origin', 'strict-origin-when-cross-origin', 'unsafe-url')
                    $effective = ''
                    foreach ($token in ($value -split ',')) {
                        if ($known -contains $token.Trim()) { $effective = $token.Trim().ToLowerInvariant() }
                    }
                    if (-not $effective) {
                        $status = 'Review'
                        $note = 'No recognized referrer-policy token was found.'
                    } elseif ($effective -eq 'unsafe-url') {
                        $status = 'Review'
                        $note = 'The last recognized token is unsafe-url, which can send path and query details to other origins.'
                    } else {
                        $note = "Last recognized policy: $effective. Confirm the intended amount of referrer information."
                    }
                }
            }
            'Permissions-Policy' {
                if ($value) { $note = 'A policy header is present. This tool does not validate its syntax, feature names, or allowed origins.' }
            }
        }

        [pscustomobject]@{ Header = $name; Status = $status; Value = $value; Note = $note }
    }
}
