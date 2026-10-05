# Testing the scanner

Run this from the project folder:

```powershell
.\tests\Run-Tests.ps1
```

The runner stops with a nonzero exit code if a suite fails. GitHub Actions uses that exit code to mark the run as failed. The tests need no Pester module and do not contact public websites.

The completed local run passed 38 checks in each runtime: 26 header cases, 3 output cases, and 9 HTTP/CLI cases. The public Actions run repeats the suite against the published commit.

## Header rules

`Test-Headers.ps1` supplies known header values directly to the rule function. Its 26 cases include:

- A positive HSTS lifetime, a zero lifetime, malformed values, and repeated lifetimes.
- HSTS on HTTP and on an IP host.
- Enforcing CSP versus a report-only policy.
- Empty values and names written in lowercase.
- Valid and invalid `nosniff` and framing values.
- A framing directive in CSP when X-Frame-Options is absent, including a directive in a second policy header.
- Recognized, unknown, and unsafe referrer policies, including fallback lists.
- Permissions-Policy presence without pretending to validate the full policy.

The cases assert the expected observation and ensure there is exactly one result for each of the six headers. They don't treat a positive result as proof of browser enforcement.

## Output handling

`Test-Output.ps1` has three checks for terminal control/formatting characters, embedded newlines, and JSON round-tripping. Text output replaces control characters with question marks. JSON escapes non-ASCII characters while preserving their original values when decoded, including Unicode surrogate pairs. These tests cover C0, C1, and a bidirectional formatting character.

## Actual HTTP requests

`Test-Http.ps1` starts a small HTTP fixture on the loopback address. A fixture is a test server with responses we control. That lets us check error paths without depending on a third-party site.

The tests cover response status and headers, relative redirects, the recorded final URL, a 404 response, redirect loops, deadline cancellation, invalid URLs, rejected redirects, and parameter limits. They also invoke the complete command with `-Json` and parse the result. The fixture sends a sample cookie header to verify that the JSON report does not include raw cookies.

Cleanup runs even when a test fails. The fixture is stopped and removed when the suite finishes.

## Reproduce both Windows runtimes

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1
```

`powershell.exe` starts Windows PowerShell 5.1. `pwsh` starts PowerShell 7 when installed. `-NoProfile` skips personal startup scripts, and `-File` specifies which script to run. A hyphen introduces each named parameter. The dot and backslash in `.\` mean the current directory.

## Check a real page

```powershell
.\Scan-Headers.ps1 -Url 'https://example.com'
```

Live responses can change. Use this as a smoke test of the network path, not a permanent expected-output test. Note the final URL and status before interpreting the findings; redirects and error pages can have different headers from the page you intended to inspect.

The scanner does not test browser behavior, CSP source restrictions, application vulnerabilities, or every valid syntax variant. The notes deliberately distinguish a basic observation from a full policy assessment.

## Live smoke check

On October 5, 2026, the full command was run against `https://example.com` from fresh Windows PowerShell 5.1 and PowerShell 7 processes. Both received HTTP 200 at `https://example.com/` and produced six findings. Terminal output and JSON parsing were checked separately. Those observations describe that run; they are not a lasting assessment of the site.
