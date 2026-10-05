# HTTP Header Scanner

[![Tests](https://github.com/jlkasten19/header-scanner/actions/workflows/test.yml/badge.svg)](https://github.com/jlkasten19/header-scanner/actions/workflows/test.yml)

Give this PowerShell script a URL and it reports the security headers returned by that page. It shows the final URL, HTTP status, header values, and a short note on what to look at next.

The useful part is seeing what the server actually sent. A header can exist and still have a poor policy, so the scanner doesn't give a site a security grade.

## Run it

Works with Windows PowerShell 5.1 and PowerShell 7. No extra modules are needed.

Open PowerShell in the project folder:

```powershell
.\Scan-Headers.ps1 -Url 'https://example.com'
```

Or run it without an address and enter one when prompted:

```powershell
.\Scan-Headers.ps1
```

The `.\` means the current folder. `-Url` is the parameter that supplies the page address. The single quotes keep the address together as text.

## What it checks

| Header | What the scanner looks for |
| --- | --- |
| `Strict-Transport-Security` | A positive `max-age` on an HTTPS domain; flags zero or an unrecognized value |
| `Content-Security-Policy` | An enforcing header; calls out a report-only policy when enforcement is absent |
| `X-Content-Type-Options` | The `nosniff` value |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN`; notes when CSP has a `frame-ancestors` directive instead |
| `Referrer-Policy` | A recognized policy token; flags `unsafe-url` for review |
| `Permissions-Policy` | Whether a nonempty policy header was returned |

Results are labeled **Present**, **Missing**, **Review**, or **Not applicable**. Present means the header was found, with a few basic value checks where practical. It doesn't mean the policy has been fully validated. Missing means it wasn't in this particular response, not that an exploit has been found.

HSTS doesn't apply to an HTTP response or an IP-address host. CSP and Permissions-Policy values need a closer look than this script can provide. An API, a static document, and an application page may need different policies.

## Save a report

Use `-Json` to get structured output instead of the terminal summary:

```powershell
.\Scan-Headers.ps1 -Url 'https://example.com' -Json
```

To save that output locally:

```powershell
New-Item -ItemType Directory -Path reports -Force
.\Scan-Headers.ps1 -Url 'https://example.com' -Json | Set-Content -Path reports\scan.json -Encoding UTF8
```

`|` is the pipe operator: it sends the scanner's output to `Set-Content`, which writes the file. Reports include the URLs you supplied, including any query parameters. Keep private addresses and tokens out of shared reports. The `reports` folder is ignored by Git.

## Requests and redirects

The scanner uses GET and stops after reading the response headers, without reading or saving the body. It follows up to five redirects and records each hop. It checks the final response, including error pages such as a 404. The default request deadline is 20 seconds.

You can change those limits:

```powershell
.\Scan-Headers.ps1 -Url 'https://example.com' -TimeoutSeconds 10 -MaxRedirects 3
```

Only `http://` and `https://` addresses are accepted. Redirects to other schemes, URLs containing embedded credentials, and HTTPS-to-HTTP downgrades are rejected. Certificate validation stays enabled. The script doesn't send login credentials or maintain a cookie session.

This is a command-line tool for a URL you choose. It isn't designed to accept untrusted URLs inside a hosted service. It doesn't crawl the site, execute page scripts, or scan ports.

## Tests

```powershell
.\tests\Run-Tests.ps1
```

The tests check the header rules and make real requests to a temporary server on your computer. They cover redirects, unsuccessful HTTP responses, input validation, timeouts, and JSON output. The test server is stopped afterward. GitHub runs the suite with both Windows PowerShell and PowerShell 7.

## Read the code

- `Scan-Headers.ps1` handles arguments and output.
- `src/Http.ps1` makes the request and follows redirects.
- `src/Headers.ps1` turns header values into observations.
- `src/Output.ps1` prepares terminal text and JSON without printing control characters from server values.
- [Walkthrough](docs/walkthrough.md) explains the flow and the PowerShell symbols.
- [Testing notes](docs/testing.md) explain the cases and how to reproduce them.

## References

The checks follow the documentation for [HSTS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security), [CSP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy), [X-Content-Type-Options](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Content-Type-Options), [X-Frame-Options](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options), [Referrer-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Referrer-Policy), and [Permissions-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy). They cover the observations listed above, rather than a browser's full policy parsing and enforcement.
