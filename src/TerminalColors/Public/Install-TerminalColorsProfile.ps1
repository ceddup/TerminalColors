$script:TcProfileBeginMarker = '# >>> TerminalColors >>>'
$script:TcProfileEndMarker = '# <<< TerminalColors <<<'

function Get-TcProfileBlock {
    param([string] $EnableArguments)

    $call = 'Enable-TerminalColors'
    if ($EnableArguments) { $call = "Enable-TerminalColors $EnableArguments" }

    return @(
        $script:TcProfileBeginMarker
        '# Automatic terminal colouring based on the current directory.'
        '# Block managed by TerminalColors: Install-TerminalColorsProfile replaces it,'
        '# Uninstall-TerminalColorsProfile removes it. You can also edit it by hand'
        '# (to change -Tint, for instance).'
        '# The WT_SESSION test avoids any startup cost outside Windows Terminal;'
        '# remove it to colour other compatible terminals as well.'
        'if ($env:WT_SESSION) {'
        '    Import-Module TerminalColors -ErrorAction SilentlyContinue'
        "    if (Get-Module TerminalColors) { $call }"
        '}'
        $script:TcProfileEndMarker
    ) -join [Environment]::NewLine
}

function Install-TerminalColorsProfile {
    <#
        .SYNOPSIS
        Adds (or updates) the TerminalColors activation in your PowerShell profile,
        so the colouring is active every time you open a terminal.

        .DESCRIPTION
        The inserted block is delimited by markers, which makes it possible to
        update or remove it cleanly without touching the rest of your profile. A
        backup of the profile is taken before it is modified.

        .PARAMETER ProfilePath
        Profile to modify. Defaults to the current user's [all hosts] profile
        ($PROFILE.CurrentUserAllHosts).

        .PARAMETER EnableArguments
        Arguments to pass to Enable-TerminalColors in the profile.
        Example: '-Tint 0.45 -NoWindowBorder'

        .PARAMETER NoBackup
        Does not write a backup copy.

        .EXAMPLE
        Install-TerminalColorsProfile

        .EXAMPLE
        Install-TerminalColorsProfile -EnableArguments '-Tint 0.45'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $ProfilePath,
        [string] $EnableArguments,
        [switch] $NoBackup
    )

    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
    $block = Get-TcProfileBlock -EnableArguments $EnableArguments

    $existing = ''
    if ([System.IO.File]::Exists($ProfilePath)) {
        $existing = [System.IO.File]::ReadAllText($ProfilePath)
    }

    $pattern = '(?s)' + [regex]::Escape($script:TcProfileBeginMarker) + '.*?' + [regex]::Escape($script:TcProfileEndMarker)
    $action = 'Add'

    if ([regex]::IsMatch($existing, $pattern)) {
        $newContent = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block })
        $action = 'Update'
    } elseif ([string]::IsNullOrWhiteSpace($existing)) {
        $newContent = $block + [Environment]::NewLine
    } else {
        $separator = [Environment]::NewLine
        if (-not $existing.EndsWith([Environment]::NewLine)) { $separator = [Environment]::NewLine + [Environment]::NewLine }
        $newContent = $existing + $separator + $block + [Environment]::NewLine
    }

    if ($newContent -eq $existing) {
        return [pscustomobject]@{ ProfilePath = $ProfilePath; Changed = $false; Action = 'No change'; Backup = $null }
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($ProfilePath, "$action the TerminalColors block")) {
        $directory = Split-Path $ProfilePath -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        if (-not $NoBackup -and [System.IO.File]::Exists($ProfilePath)) {
            $backupPath = '{0}.terminalcolors-backup-{1}' -f $ProfilePath, (Get-Date -Format 'yyyyMMdd-HHmmss')
            [System.IO.File]::Copy($ProfilePath, $backupPath, $true)
        }
        # UTF-8 with BOM: without one, Windows PowerShell 5.1 reads profiles in the
        # ANSI code page, which would corrupt any non-ASCII text the user has put
        # in there.
        $encoding = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($ProfilePath, $newContent, $encoding)
    }

    return [pscustomobject]@{ ProfilePath = $ProfilePath; Changed = $true; Action = $action; Backup = $backupPath }
}

function Uninstall-TerminalColorsProfile {
    <#
        .SYNOPSIS
        Removes the TerminalColors block from your PowerShell profile.

        .PARAMETER ProfilePath
        Profile to modify. Defaults to $PROFILE.CurrentUserAllHosts.

        .EXAMPLE
        Uninstall-TerminalColorsProfile
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $ProfilePath)

    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
    if (-not [System.IO.File]::Exists($ProfilePath)) {
        Write-Warning "TerminalColors: profile not found [$ProfilePath]."
        return
    }

    $existing = [System.IO.File]::ReadAllText($ProfilePath)
    $pattern = '(?s)\s*' + [regex]::Escape($script:TcProfileBeginMarker) + '.*?' + [regex]::Escape($script:TcProfileEndMarker)
    if (-not [regex]::IsMatch($existing, $pattern)) {
        Write-Warning 'TerminalColors: no TerminalColors block in this profile.'
        return
    }

    $newContent = [regex]::Replace($existing, $pattern, '')
    if ($PSCmdlet.ShouldProcess($ProfilePath, 'Remove the TerminalColors block')) {
        $encoding = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($ProfilePath, $newContent, $encoding)
    }
}

function Test-TerminalColorsProfile {
    <#
        .SYNOPSIS
        Indicates whether the TerminalColors block is present in a PowerShell
        profile.

        .PARAMETER ProfilePath
        Profile to inspect. Defaults to $PROFILE.CurrentUserAllHosts.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $ProfilePath)

    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
    if (-not [System.IO.File]::Exists($ProfilePath)) { return $false }
    $existing = [System.IO.File]::ReadAllText($ProfilePath)
    return $existing.Contains($script:TcProfileBeginMarker)
}
