# Tolerant JSON (JSONC) reading: the settings.json files of VS Code and Windows
# Terminal contain comments and sometimes trailing commas.

function Remove-TcJsonComments {
    <#
        .SYNOPSIS
        Replaces // and /* */ comments with spaces, preserving positions
        (essential for the surgical editing of settings.json) and ignoring
        anything inside strings.
    #>
    [CmdletBinding()]
    param([string] $Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $sb = New-Object System.Text.StringBuilder($Text.Length)
    $i = 0
    $len = $Text.Length
    $inString = $false

    while ($i -lt $len) {
        $c = $Text[$i]

        if ($inString) {
            [void]$sb.Append($c)
            if ($c -eq '\') {
                if ($i + 1 -lt $len) { [void]$sb.Append($Text[$i + 1]); $i += 2; continue }
            } elseif ($c -eq '"') {
                $inString = $false
            }
            $i++
            continue
        }

        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); $i++; continue }

        if ($c -eq '/' -and $i + 1 -lt $len) {
            $n = $Text[$i + 1]
            if ($n -eq '/') {
                while ($i -lt $len -and $Text[$i] -ne "`n") {
                    if ($Text[$i] -eq "`r") { [void]$sb.Append($Text[$i]) } else { [void]$sb.Append(' ') }
                    $i++
                }
                continue
            }
            if ($n -eq '*') {
                $i += 2
                [void]$sb.Append('  ')
                while ($i -lt $len) {
                    if ($Text[$i] -eq '*' -and $i + 1 -lt $len -and $Text[$i + 1] -eq '/') {
                        [void]$sb.Append('  '); $i += 2; break
                    }
                    if ($Text[$i] -eq "`n" -or $Text[$i] -eq "`r") { [void]$sb.Append($Text[$i]) } else { [void]$sb.Append(' ') }
                    $i++
                }
                continue
            }
        }

        [void]$sb.Append($c)
        $i++
    }

    return $sb.ToString()
}

function ConvertFrom-TcJsonText {
    <#
        .SYNOPSIS
        Parses JSONC. Returns $null on failure (never throws).
    #>
    [CmdletBinding()]
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $clean = Remove-TcJsonComments -Text $Text
        # Trailing commas
        $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')
        return $clean | ConvertFrom-Json
    } catch {
        Write-Verbose "TerminalColors: unreadable JSON ($($_.Exception.Message))"
        return $null
    }
}

function ConvertFrom-TcJsonFile {
    [CmdletBinding()]
    param([string] $Path)

    try {
        $raw = [System.IO.File]::ReadAllText($Path)
    } catch {
        Write-Verbose "TerminalColors: could not read [$Path] ($($_.Exception.Message))"
        return $null
    }
    return ConvertFrom-TcJsonText -Text $raw
}

function Get-TcJsonProperty {
    <#
        .SYNOPSIS
        Reads a property whose name contains dots ([peacock.color]) from an object
        produced by ConvertFrom-Json, without raising an error.
    #>
    [CmdletBinding()]
    param(
        # Deliberately not mandatory: callers chain reads over objects that may be
        # absent.
        $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $InputObject) { return $null }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}
