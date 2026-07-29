# Surgical editing of the Windows Terminal settings.json.
#
# The principle shared by all three installers (theme, opaque backdrop, system
# title bar): the document is never re-serialised. Only the strict minimum is
# inserted or replaced in the existing text, so that comments, key order and the
# user's formatting are preserved. The result is validated before any write, and a
# backup is taken.
#
# The locating helpers work on a [masked] copy of the text: same length as the
# original, comments and escape sequences neutralised, so that any index found in
# the copy is directly usable on the original.

function Get-TcMaskedJson {
    <#
        .SYNOPSIS
        Copy of the text without comments and without escape sequences, the same
        length as the original: indexes found in this copy are therefore directly
        usable on the original text.
    #>
    param([string] $Text)

    $noComments = Remove-TcJsonComments -Text $Text
    $chars = $noComments.ToCharArray()
    $inString = $false
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        if ($inString) {
            if ($c -eq '\') { $chars[$i] = ' '; if ($i + 1 -lt $chars.Length) { $chars[$i + 1] = ' '; $i++ }; continue }
            if ($c -eq '"') { $inString = $false; continue }
            # String contents are masked, except for the key names we want to be
            # able to find again: the characters are therefore kept.
            continue
        }
        if ($c -eq '"') { $inString = $true }
    }
    return (-join $chars)
}

function Find-TcJsonObjectSpan {
    <#
        .SYNOPSIS
        Given an index inside a JSON object, returns @{ Start; End } delimiting
        that object (braces included).
    #>
    param([string] $Text, [int] $Index)

    # Walk back to the current object's opening brace
    $depth = 0
    $start = -1
    for ($i = $Index; $i -ge 0; $i--) {
        $c = $Text[$i]
        if ($c -eq '}') { $depth++ }
        elseif ($c -eq '{') {
            if ($depth -eq 0) { $start = $i; break }
            $depth--
        }
    }
    if ($start -lt 0) { return $null }

    $depth = 0
    for ($i = $start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return @{ Start = $start; End = $i } }
        }
    }
    return $null
}

function Find-TcJsonBlockSpan {
    <#
        .SYNOPSIS
        Returns @{ Start; End } of the object or array starting at $Index (the
        index must point at [{] or [[]).
    #>
    param([string] $Text, [int] $Index)

    $open = $Text[$Index]
    if ($open -eq '{') { $close = '}' } elseif ($open -eq '[') { $close = ']' } else { return $null }

    $depth = 0
    for ($i = $Index; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq $open) { $depth++ }
        elseif ($c -eq $close) {
            $depth--
            if ($depth -eq 0) { return @{ Start = $Index; End = $i } }
        }
    }
    return $null
}

function Find-TcJsonMember {
    <#
        .SYNOPSIS
        Looks for the [Name] member directly inside the object delimited by $Span
        (depth 1: nested objects are ignored).

        Returns @{ NameStart; ValueStart; ValueEnd } or $null. ValueEnd is the
        index of the value's last character.
    #>
    param([string] $Masked, [hashtable] $Span, [string] $Name)

    $pattern = '"' + [regex]::Escape($Name) + '"\s*:'
    foreach ($m in [regex]::Matches($Masked, $pattern)) {
        if ($m.Index -le $Span.Start -or $m.Index -ge $Span.End) { continue }

        # Check that the member really is at the root of this object, and not
        # inside a nested object or array.
        $depth = 0
        for ($i = $Span.Start + 1; $i -lt $m.Index; $i++) {
            $c = $Masked[$i]
            if ($c -eq '{' -or $c -eq '[') { $depth++ }
            elseif ($c -eq '}' -or $c -eq ']') { $depth-- }
        }
        if ($depth -ne 0) { continue }

        # Start of the value
        $v = $m.Index + $m.Length
        while ($v -lt $Span.End -and [char]::IsWhiteSpace($Masked[$v])) { $v++ }
        if ($v -ge $Span.End) { continue }

        $end = -1
        $c = $Masked[$v]
        if ($c -eq '"') {
            for ($i = $v + 1; $i -le $Span.End; $i++) {
                if ($Masked[$i] -eq '"') { $end = $i; break }
            }
        } elseif ($c -eq '{' -or $c -eq '[') {
            $block = Find-TcJsonBlockSpan -Text $Masked -Index $v
            if ($block) { $end = $block.End }
        } else {
            # Literal: number, true, false, null
            for ($i = $v; $i -le $Span.End; $i++) {
                $ch = $Masked[$i]
                if ($ch -eq ',' -or $ch -eq '}' -or $ch -eq ']') { break }
                $end = $i
            }
            while ($end -gt $v -and [char]::IsWhiteSpace($Masked[$end])) { $end-- }
        }

        if ($end -lt 0) { continue }
        return @{ NameStart = $m.Index; ValueStart = $v; ValueEnd = $end }
    }
    return $null
}

function Test-TcJsonObjectEmpty {
    param([string] $Masked, [hashtable] $Span)

    for ($i = $Span.Start + 1; $i -lt $Span.End; $i++) {
        if (-not [char]::IsWhiteSpace($Masked[$i])) { return $false }
    }
    return $true
}

function Set-TcJsonMember {
    <#
        .SYNOPSIS
        Adds or replaces the [Name] member of the object containing $AnchorIndex.

        .DESCRIPTION
        $Literal is inserted as-is: it is up to the caller to supply a valid JSON
        literal (quoted string, number, true/false).

        Returns @{ Text; Action } where Action is 'added', 'replaced' or
        'unchanged'. Since any modification invalidates the indexes, only one
        member is applied per call.
    #>
    param(
        [string] $Text,
        [int] $AnchorIndex,
        [string] $Name,
        [string] $Literal,
        [string] $Indent = '        '
    )

    $masked = Get-TcMaskedJson -Text $Text
    $span = Find-TcJsonObjectSpan -Text $masked -Index $AnchorIndex
    if ($null -eq $span) { throw "TerminalColors: JSON object not found for member [$Name]." }

    $member = Find-TcJsonMember -Masked $masked -Span $span -Name $Name
    if ($member) {
        $current = $Text.Substring($member.ValueStart, $member.ValueEnd - $member.ValueStart + 1)
        if ($current -eq $Literal) { return @{ Text = $Text; Action = 'unchanged' } }
        $newText = $Text.Remove($member.ValueStart, $member.ValueEnd - $member.ValueStart + 1).Insert($member.ValueStart, $Literal)
        return @{ Text = $newText; Action = 'replaced' }
    }

    $fragment = '"' + $Name + '": ' + $Literal
    if (Test-TcJsonObjectEmpty -Masked $masked -Span $span) {
        # Empty object: rewrite it whole so the closing brace does not end up
        # glued to the inserted value.
        $closeIndent = $Indent
        if ($closeIndent.Length -ge 4) { $closeIndent = $closeIndent.Substring(4) }
        $block = '{' + [Environment]::NewLine + $Indent + $fragment + [Environment]::NewLine + $closeIndent + '}'
        $newText = $Text.Remove($span.Start, $span.End - $span.Start + 1).Insert($span.Start, $block)
    } else {
        $newText = $Text.Insert($span.Start + 1, [Environment]::NewLine + $Indent + $fragment + ',')
    }
    return @{ Text = $newText; Action = 'added' }
}

function Remove-TcJsonMember {
    <#
        .SYNOPSIS
        Removes the [Name] member from the object containing $AnchorIndex,
        absorbing the adjacent comma to keep the object valid.

        Returns @{ Text; Action } where Action is 'removed' or 'absent'.
    #>
    param(
        [string] $Text,
        [int] $AnchorIndex,
        [string] $Name
    )

    $masked = Get-TcMaskedJson -Text $Text
    $span = Find-TcJsonObjectSpan -Text $masked -Index $AnchorIndex
    if ($null -eq $span) { return @{ Text = $Text; Action = 'absent' } }

    $member = Find-TcJsonMember -Masked $masked -Span $span -Name $Name
    if ($null -eq $member) { return @{ Text = $Text; Action = 'absent' } }

    $start = $member.NameStart
    $end = $member.ValueEnd

    $after = $end + 1
    while ($after -lt $span.End -and [char]::IsWhiteSpace($masked[$after])) { $after++ }
    if ($after -lt $span.End -and $masked[$after] -eq ',') {
        $end = $after
    } else {
        $before = $start - 1
        while ($before -gt $span.Start -and [char]::IsWhiteSpace($masked[$before])) { $before-- }
        if ($before -gt $span.Start -and $masked[$before] -eq ',') { $start = $before }
    }

    # Absorb the indentation left at the start of the line.
    $probe = $start - 1
    while ($probe -gt $span.Start -and ($masked[$probe] -eq ' ' -or $masked[$probe] -eq "`t")) { $probe-- }
    if ($probe -gt $span.Start -and $masked[$probe] -eq "`n") { $start = $probe }

    return @{ Text = $Text.Remove($start, $end - $start + 1); Action = 'removed' }
}

function Find-TcJsonRootIndex {
    param([string] $Masked)

    $index = $Masked.IndexOf('{')
    if ($index -lt 0) { throw 'TerminalColors: unexpected settings.json structure (no root object).' }
    return $index
}

function Resolve-TcWtSettingsPath {
    <#
        .SYNOPSIS
        Validates a supplied settings.json path, or detects one. Throws an
        explicit error when the file cannot be found.
    #>
    param([string] $Path)

    if (-not $Path) { $Path = Get-TcWtSettingsPath }
    if (-not $Path -or -not [System.IO.File]::Exists($Path)) {
        throw 'TerminalColors: Windows Terminal settings.json not found. Start Windows Terminal once, or pass -SettingsPath.'
    }
    return $Path
}

function Get-TcWtSettingsEncoding {
    param([string] $Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    } catch { $hasBom = $false }
    return (New-Object System.Text.UTF8Encoding($hasBom))
}

function Save-TcWtSettings {
    <#
        .SYNOPSIS
        Writes settings.json preserving its encoding, after taking a timestamped
        backup. Returns the backup path, or $null.
    #>
    param(
        [string] $Path,
        [string] $Text,
        [switch] $NoBackup
    )

    $backupPath = $null
    if (-not $NoBackup) {
        $backupPath = '{0}.terminalcolors-backup-{1}' -f $Path, (Get-Date -Format 'yyyyMMdd-HHmmss')
        [System.IO.File]::Copy($Path, $backupPath, $true)
    }
    [System.IO.File]::WriteAllText($Path, $Text, (Get-TcWtSettingsEncoding -Path $Path))
    return $backupPath
}

# --- Module data -------------------------------------------------------------
# Folder holding the install state and the opaque backdrop images. Redirectable so
# that the tests never touch the user's real data (uninstalling the backdrop
# deletes files in there).

$script:TcDataDirectory = $null

function Get-TcDataDirectory {
    if ($script:TcDataDirectory) { return $script:TcDataDirectory }
    return (Join-Path $env:LOCALAPPDATA 'TerminalColors')
}

# --- Install state -----------------------------------------------------------
# Remembers what has to be restored on uninstall (previous theme, previous
# background image, previous value of showTabsInTitlebar).

function Get-TcInstallStatePath {
    return (Join-Path (Get-TcDataDirectory) 'state.json')
}

function Set-TcInstallState {
    param([string] $Name, $Value)

    $path = Get-TcInstallStatePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $state = @{}
    if ([System.IO.File]::Exists($path)) {
        $existing = ConvertFrom-TcJsonFile -Path $path
        if ($existing) {
            foreach ($p in $existing.PSObject.Properties) { $state[$p.Name] = $p.Value }
        }
    }
    $state[$Name] = $Value

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, ([pscustomobject]$state | ConvertTo-Json -Depth 5), $encoding)
}

function Get-TcInstallState {
    param([string] $Name)

    $path = Get-TcInstallStatePath
    if (-not [System.IO.File]::Exists($path)) { return $null }
    $state = ConvertFrom-TcJsonFile -Path $path
    if (-not $state) { return $null }
    return (Get-TcJsonProperty -InputObject $state -Name $Name)
}

function Remove-TcInstallState {
    param([string] $Name)

    $path = Get-TcInstallStatePath
    if (-not [System.IO.File]::Exists($path)) { return }
    $state = ConvertFrom-TcJsonFile -Path $path
    if (-not $state) { return }

    $kept = @{}
    foreach ($p in $state.PSObject.Properties) {
        if ($p.Name -ne $Name) { $kept[$p.Name] = $p.Value }
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, ([pscustomobject]$kept | ConvertTo-Json -Depth 5), $encoding)
}
