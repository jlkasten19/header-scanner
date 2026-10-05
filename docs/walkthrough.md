# How the scanner works

When a web server answers a request, it sends a status code and named headers before the response body. The body might be an HTML page. Headers can describe its content type, caching behavior, or browser security policies.

This scanner asks for one page, reads those headers, and explains a few observations. It doesn't render the page or execute JavaScript.

## Start with one command

```powershell
.\Scan-Headers.ps1 -Url 'https://example.com'
```

| Part | Name and meaning |
| --- | --- |
| `.\` | Dot and backslash: use a file in the current folder. |
| `Scan-Headers.ps1` | Script filename. The dot before `ps1` separates the name from the PowerShell script extension. |
| `-Url` | Named parameter. The hyphen introduces the parameter name; it isn't subtraction. |
| `'...'` | Single quotation marks: surround literal text. |
| `https://` | URL scheme followed by a colon and two forward slashes. It specifies HTTPS. |
| `example.com` | The domain name. The dot separates parts of the domain. |

The script can also ask for the address using `Read-Host`. Supplying `-Url` skips that prompt.

## Follow the data

1. `Scan-Headers.ps1` reads the parameters and loads the helper files.
2. `Get-HttpResponseHeaders` checks the URL, sends the request, and handles redirects.
3. `Get-SecurityHeaderFindings` examines the final response's headers.
4. The main script prints the result or converts it to JSON.

The request helper uses .NET's `HttpClient`. `ResponseHeadersRead` tells it to return when the headers arrive instead of buffering the whole response body. Redirects are handled explicitly so the report can show where the request went and apply the limits at each hop.

## Symbols in the main script

| Symbol or word | Name and meaning |
| --- | --- |
| `$Url` | Variable: the dollar sign identifies a named value. |
| `=` | Assignment operator: stores the right-hand value on the left. |
| `param(...)` | Parameter declaration: describes the input accepted by the script. |
| `[string]`, `[int]` | Square brackets declaring types: text and whole numbers. |
| `[switch]` | A parameter turned on by naming it, such as `-Json`. |
| `[ValidateRange(1, 120)]` | A validation attribute: accepts numbers within that inclusive range. |
| `(...)` | Parentheses: group an expression or contain method arguments. |
| `{...}` | Curly braces: enclose a block of instructions. |
| `@{...}` | Hashtable literal: stores named keys and their values. |
| `@(...)` | Array expression: collects values into a list, including when there are zero or one. |
| `[pscustomobject]` | Converts named fields into an object suitable for reporting. |
| `.` | Member-access operator in `$response.StatusCode`; reads a property or calls a method. |
| `. (Join-Path ...)` | Dot-sourcing operator followed by a space: loads functions from another script into this scope. |
| `$PSScriptRoot` | Automatic variable containing this script's folder. |
| `Join-Path` | Command that joins folder and file path parts. The hyphen is part of its name. |
| `if`, `else` | Keywords that choose which block to run. |
| `-not` | Logical NOT operator: reverses true and false. |
| `$PSBoundParameters.ContainsKey('Url')` | Checks whether the caller supplied the named URL parameter. |
| `try`, `catch` | Run an operation and handle a terminating error if it fails. |
| `foreach` | Loop keyword: repeat a block for each item in a collection. |
| `|` | Pipe operator: sends output to another command. |
| `"..."` | Double quotation marks: text in which variable values can be inserted. |
| `$()` | Subexpression: evaluates an expression inside a double-quoted string. |
| `#` | Number sign / comment marker: the rest of that line explains the code to a reader. |
| `::` | Double colon / static member access: uses a method or property on a .NET type. |

## Reading the rules

The rule module uses `switch` to choose the checks for each header name. A `switch` is a way to handle several possible values without a long chain of `if` statements.

`-eq` means equal, `-ne` means not equal, `-gt` means greater than, `-and` requires both conditions, and `-or` requires at least one. `-ieq` and `-imatch` explicitly request case-insensitive comparisons or regex matches. `-contains` checks membership in a collection; `-split` breaks text into pieces; `-join` combines pieces into text.

`.Trim()` removes whitespace around a value. `[string]$lookup[$name]` reads a hashtable entry using square-bracket indexing and treats it as text. Missing or empty policy values are reported as missing.

Some checks use regular expressions. Within a regex, `[0-9]` is a character class; the hyphen means a range. `+` means one or more, `*` means zero or more, `^` and `$` are start/end anchors, and `\A` and `\z` require the absolute start/end. A backslash begins regex syntax such as `\s` for whitespace and `\d` for a digit. `(?:...)` groups without capturing; `(?i)` enables case-insensitive matching; `(?=...)` checks what follows without consuming it. Regex `|` means an alternative, unlike PowerShell's pipe outside a string.

The display helper uses `-replace` to replace control and formatting characters from server-provided text. `\p{Cc}` and `\p{Cf}` are Unicode categories for those characters. JSON output uses `\u` escapes for non-ASCII characters and preserves the original values when decoded. In a regex, `\x` introduces a hexadecimal character code. The `-f` format operator builds each JSON escape, and `[int][char]` gets the numeric UTF-16 character value. The output tests check the handling of terminal escapes, bidirectional formatting, and Unicode text.

## Interpreting a result

- **Present:** a value exists and any implemented basic check recognized it. Read the note.
- **Missing:** the response did not include a usable value for that header.
- **Review:** something needs interpretation, such as a disabled HSTS policy or a report-only CSP.
- **Not applicable:** this check doesn't apply to the response context, such as HSTS over HTTP.

A 404 is still an HTTP response with headers. The scanner reports that status rather than pretending it was a successful page. A DNS error, TLS error, timeout, or rejected redirect produces a scan error instead of a header report.

Start by understanding the main script and reading one result. Then trace a single header through the rule module. The networking and test helpers introduce more advanced .NET and PowerShell concepts; they don't need to be memorized to use the tool.
