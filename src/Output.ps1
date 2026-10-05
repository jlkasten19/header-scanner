function ConvertTo-SafeTerminalText {
    param([string]$Text)
    return ($Text -replace '[\p{Cc}\p{Cf}]', '?')
}

function ConvertTo-SafeJson {
    param($Value)
    $json = $Value | ConvertTo-Json -Depth 6
    # Escape non-ASCII UTF-16 code units, preserving the original values on decode.
    # ConvertTo-Json already escapes control characters inside JSON strings.
    return [regex]::Replace($json, '[^\x00-\x7f]', {
        param($character)
        '\u{0:x4}' -f [int][char]$character.Value[0]
    })
}
