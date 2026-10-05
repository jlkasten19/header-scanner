Add-Type -AssemblyName System.Net.Http

function ConvertTo-HeaderScannerHttpUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $uri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or $null -eq $uri) {
        throw ("Invalid URL '{0}'. An absolute http or https URL is required." -f $Value)
    }

    if ($uri.Scheme -ine 'http' -and $uri.Scheme -ine 'https') {
        throw ("Unsupported URL scheme '{0}'. Only http and https are allowed." -f $uri.Scheme)
    }

    if ([string]::IsNullOrEmpty($uri.Host)) {
        throw ("Invalid URL '{0}'. A host is required." -f $Value)
    }

    if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
        throw ("URL credentials are not allowed in '{0}'." -f $Value)
    }

    return $uri
}

function Add-HeaderScannerHeaders {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$Table,
        [Parameter(Mandatory = $true)]
        $HeaderCollection
    )

    foreach ($header in $HeaderCollection) {
        $key = [string]$header.Key
        $values = @($header.Value | ForEach-Object { [string]$_ })
        $value = $values -join ', '

        if ($Table.ContainsKey($key)) {
            $Table[$key] = ("{0}, {1}" -f [string]$Table[$key], $value)
        }
        else {
            $Table[$key] = [string]$value
        }
    }
}

function Get-HttpResponseHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [ValidateRange(1, 120)]
        [int]$TimeoutSeconds = 20,

        [ValidateRange(0, 10)]
        [int]$MaxRedirects = 5
    )

    $requestedUrl = [string]$Url
    $currentUri = ConvertTo-HeaderScannerHttpUri -Value $requestedUrl
    $redirects = New-Object System.Collections.ArrayList
    $handler = $null
    $client = $null
    $cancellation = $null

    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $false
        $handler.UseCookies = $false
        $handler.UseDefaultCredentials = $false
        $handler.Credentials = $null
        $handler.PreAuthenticate = $false
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
        $cancellation = New-Object System.Threading.CancellationTokenSource
        $cancellation.CancelAfter([System.TimeSpan]::FromSeconds($TimeoutSeconds))
        $completion = [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead

        while ($true) {
            $request = $null
            $response = $null
            try {
                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $currentUri)
                $response = $client.SendAsync($request, $completion, $cancellation.Token).GetAwaiter().GetResult()
                $statusCode = [int]$response.StatusCode
                $isRedirect = $statusCode -eq 301 -or
                    $statusCode -eq 302 -or
                    $statusCode -eq 303 -or
                    $statusCode -eq 307 -or
                    $statusCode -eq 308

                if ($isRedirect) {
                    if ($redirects.Count -ge $MaxRedirects) {
                        throw ("Maximum number of redirects ({0}) exceeded while requesting '{1}'." -f $MaxRedirects, $currentUri.AbsoluteUri)
                    }

                    $locationValues = $null
                    if (-not $response.Headers.TryGetValues('Location', [ref]$locationValues) -or $null -eq $locationValues) {
                        throw ("Redirect response {0} from '{1}' is missing a Location header." -f $statusCode, $currentUri.AbsoluteUri)
                    }

                    $location = (@($locationValues) | Select-Object -First 1)
                    if ([string]::IsNullOrWhiteSpace([string]$location)) {
                        throw ("Redirect response {0} from '{1}' has an empty Location header." -f $statusCode, $currentUri.AbsoluteUri)
                    }

                    $nextUri = $null
                    try {
                        $nextUri = [System.Uri]::new($currentUri, [string]$location)
                    }
                    catch {
                        throw ("Redirect response {0} from '{1}' has an invalid Location '{2}'." -f $statusCode, $currentUri.AbsoluteUri, $location)
                    }

                    $nextUri = ConvertTo-HeaderScannerHttpUri -Value $nextUri.AbsoluteUri
                    if ($currentUri.Scheme -ieq 'https' -and $nextUri.Scheme -ieq 'http') {
                        throw ("HTTPS to HTTP redirect is not allowed: '{0}' to '{1}'." -f $currentUri.AbsoluteUri, $nextUri.AbsoluteUri)
                    }

                    [void]$redirects.Add([PSCustomObject]@{
                            From       = [string]$currentUri.AbsoluteUri
                            To         = [string]$nextUri.AbsoluteUri
                            StatusCode = $statusCode
                        })
                    $currentUri = $nextUri
                    continue
                }

                $headers = @{}
                Add-HeaderScannerHeaders -Table $headers -HeaderCollection $response.Headers
                if ($null -ne $response.Content -and $null -ne $response.Content.Headers) {
                    Add-HeaderScannerHeaders -Table $headers -HeaderCollection $response.Content.Headers
                }

                return [PSCustomObject]@{
                    RequestedUrl = $requestedUrl
                    FinalUrl     = [string]$currentUri.AbsoluteUri
                    StatusCode   = $statusCode
                    Headers      = $headers
                    Redirects    = [object[]]$redirects.ToArray()
                }
            }
            catch [System.OperationCanceledException] {
                throw [System.TimeoutException]::new(("HTTP request timed out after {0} seconds while requesting '{1}'." -f $TimeoutSeconds, $currentUri.AbsoluteUri))
            }
            finally {
                if ($response) {
                    $response.Dispose()
                }
                if ($request) {
                    $request.Dispose()
                }
            }
        }
    }
    finally {
        if ($cancellation) {
            $cancellation.Dispose()
        }
        if ($client) {
            $client.Dispose()
        }
        if ($handler) {
            $handler.Dispose()
        }
    }
}
