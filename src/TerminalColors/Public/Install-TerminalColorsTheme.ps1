# Installs the Windows Terminal theme that makes the tab and the title bar follow
# the active pane's background colour.
#
# The surgical settings.json editing helpers live in Private\WtSettings.ps1,
# shared with Install-TerminalColorsBackdrop and Install-TerminalColorsTitleBar.

$script:TcThemeName = 'TerminalColors'

function Get-TcThemeJson {
    param([string] $Indent = '    ')

    $lines = @(
        '{',
        '    "name": "TerminalColors",',
        '    "tab":',
        '    {',
        '        "background": "terminalBackground",',
        '        "unfocusedBackground": "terminalBackground"',
        '    },',
        '    "tabRow":',
        '    {',
        '        "background": "terminalBackground",',
        '        "unfocusedBackground": "terminalBackground"',
        '    },',
        '    "window":',
        '    {',
        '        "applicationTheme": "system"',
        '    }',
        '}'
    )
    return ($lines -join ([Environment]::NewLine + $Indent + $Indent))
}

function Test-TcThemeInstalled {
    param([string] $Text)
    $masked = Get-TcMaskedJson -Text $Text
    return [regex]::IsMatch($masked, '"name"\s*:\s*"TerminalColors"')
}

function Install-TerminalColorsTheme {
    <#
        .SYNOPSIS
        Installs the [TerminalColors] theme into Windows Terminal and selects it.

        .DESCRIPTION
        This theme is what makes the colouring visible: it tells Windows Terminal
        to paint the tab and the title bar with the active pane's background
        colour. Since the module changes that background colour on every directory
        change, the tab and title bar follow automatically.

        settings.json is modified by targeted insertion, with a backup taken first
        and the result validated before writing.

        .PARAMETER SettingsPath
        Path of the settings.json to modify. Detected automatically by default
        (Store, Preview, unpackaged and portable versions).

        .PARAMETER Force
        Reinstalls the theme even when it is already present.

        .PARAMETER NoBackup
        Does not write a backup copy.

        .EXAMPLE
        Install-TerminalColorsTheme

        .EXAMPLE
        Install-TerminalColorsTheme -WhatIf
        Shows what would change without writing anything.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $SettingsPath,
        [switch] $Force,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    if ($null -eq (ConvertFrom-TcJsonText -Text $text)) {
        throw "TerminalColors: [$SettingsPath] is not valid JSON. Fix it before installing the theme."
    }

    $alreadyInstalled = Test-TcThemeInstalled -Text $text
    if ($alreadyInstalled -and -not $Force) {
        Write-Verbose 'TerminalColors: theme already present, only the selection is checked.'
    }

    $newText = $text
    $masked = Get-TcMaskedJson -Text $newText
    $changes = @()

    # --- 1. Remove a previous version of the theme when -Force --------------
    if ($alreadyInstalled -and $Force) {
        $m = [regex]::Match($masked, '"name"\s*:\s*"TerminalColors"')
        $span = Find-TcJsonObjectSpan -Text $masked -Index $m.Index
        if ($span) {
            $start = $span.Start
            $end = $span.End
            # Absorb the adjacent comma to keep the array valid
            $after = $end + 1
            while ($after -lt $masked.Length -and [char]::IsWhiteSpace($masked[$after])) { $after++ }
            if ($after -lt $masked.Length -and $masked[$after] -eq ',') {
                $end = $after
            } else {
                $before = $start - 1
                while ($before -ge 0 -and [char]::IsWhiteSpace($masked[$before])) { $before-- }
                if ($before -ge 0 -and $masked[$before] -eq ',') { $start = $before }
            }
            $newText = $newText.Remove($start, $end - $start + 1)
            $masked = Get-TcMaskedJson -Text $newText
            $changes += 'previous theme removed'
            $alreadyInstalled = $false
        }
    }

    # --- 2. Insert the theme into the "themes" array ------------------------
    if (-not $alreadyInstalled) {
        $themeJson = Get-TcThemeJson
        $m = [regex]::Match($masked, '"themes"\s*:\s*\[')
        if ($m.Success) {
            $insertAt = $m.Index + $m.Length
            $probe = $insertAt
            while ($probe -lt $masked.Length -and [char]::IsWhiteSpace($masked[$probe])) { $probe++ }
            $needsComma = ($probe -lt $masked.Length -and $masked[$probe] -ne ']')

            $fragment = [Environment]::NewLine + '        ' + $themeJson
            if ($needsComma) { $fragment += ',' } else { $fragment += [Environment]::NewLine + '    ' }
            $newText = $newText.Insert($insertAt, $fragment)
            $changes += 'theme added to "themes"'
        } else {
            $rootBrace = $masked.IndexOf('{')
            if ($rootBrace -lt 0) { throw 'TerminalColors: unexpected settings.json structure.' }
            $fragment = [Environment]::NewLine + '    "themes":' + [Environment]::NewLine + '    [' +
                        [Environment]::NewLine + '        ' + $themeJson + [Environment]::NewLine + '    ],'
            $newText = $newText.Insert($rootBrace + 1, $fragment)
            $changes += '"themes" section created'
        }
        $masked = Get-TcMaskedJson -Text $newText
    }

    # --- 3. Select the theme ------------------------------------------------
    $previousTheme = $null
    $m = [regex]::Match($masked, '"theme"\s*:\s*(?:"[^"]*"|\{[^{}]*\})')
    if ($m.Success) {
        $currentValue = $newText.Substring($m.Index, $m.Length)
        if ($currentValue -notmatch '"TerminalColors"') {
            $vm = [regex]::Match($currentValue, '"theme"\s*:\s*(.+)$', 'Singleline')
            if ($vm.Success) { $previousTheme = $vm.Groups[1].Value.Trim() }
            $newText = $newText.Remove($m.Index, $m.Length).Insert($m.Index, '"theme": "TerminalColors"')
            $changes += 'theme selected'
        }
    } else {
        $rootBrace = $masked.IndexOf('{')
        $newText = $newText.Insert($rootBrace + 1, [Environment]::NewLine + '    "theme": "TerminalColors",')
        $changes += 'theme selected'
    }

    if ($changes.Count -eq 0) {
        Write-Verbose 'TerminalColors: nothing to change.'
        return [pscustomobject]@{
            SettingsPath = $SettingsPath
            Changed      = $false
            Changes      = @()
            Backup       = $null
        }
    }

    # --- 4. Validate before writing -----------------------------------------
    $parsed = ConvertFrom-TcJsonText -Text $newText
    if ($null -eq $parsed) {
        throw 'TerminalColors: the change would have produced invalid JSON. Nothing was written. Please report this case along with your settings.json.'
    }
    if ([string]$parsed.theme -ne $script:TcThemeName) {
        throw 'TerminalColors: verification failed (theme not selected). Nothing was written.'
    }
    if (-not ($parsed.themes | Where-Object { $_.name -eq $script:TcThemeName })) {
        throw 'TerminalColors: verification failed (theme missing from the list). Nothing was written.'
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($SettingsPath, "Install the TerminalColors theme ($($changes -join ', '))")) {
        $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
        if ($previousTheme) { Set-TcInstallState -Name 'PreviousTheme' -Value $previousTheme }
    }

    return [pscustomobject]@{
        SettingsPath = $SettingsPath
        Changed      = $true
        Changes      = $changes
        Backup       = $backupPath
    }
}

function Uninstall-TerminalColorsTheme {
    <#
        .SYNOPSIS
        Removes the [TerminalColors] theme from Windows Terminal and restores the
        previously selected theme.

        .PARAMETER SettingsPath
        Path of the settings.json to modify. Detected automatically by default.

        .PARAMETER NoBackup
        Does not write a backup copy.

        .EXAMPLE
        Uninstall-TerminalColorsTheme
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string] $SettingsPath,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    $newText = $text
    $masked = Get-TcMaskedJson -Text $newText
    $changes = @()

    $m = [regex]::Match($masked, '"name"\s*:\s*"TerminalColors"')
    if ($m.Success) {
        $span = Find-TcJsonObjectSpan -Text $masked -Index $m.Index
        if ($span) {
            $start = $span.Start
            $end = $span.End
            $after = $end + 1
            while ($after -lt $masked.Length -and [char]::IsWhiteSpace($masked[$after])) { $after++ }
            if ($after -lt $masked.Length -and $masked[$after] -eq ',') {
                $end = $after
            } else {
                $before = $start - 1
                while ($before -ge 0 -and [char]::IsWhiteSpace($masked[$before])) { $before-- }
                if ($before -ge 0 -and $masked[$before] -eq ',') { $start = $before }
            }
            $newText = $newText.Remove($start, $end - $start + 1)
            $masked = Get-TcMaskedJson -Text $newText
            $changes += 'theme removed'
        }
    }

    $restore = Get-TcInstallState -Name 'PreviousTheme'
    if (-not $restore) { $restore = '"system"' }
    $m = [regex]::Match($masked, '"theme"\s*:\s*(?:"[^"]*"|\{[^{}]*\})')
    if ($m.Success -and $newText.Substring($m.Index, $m.Length) -match '"TerminalColors"') {
        $newText = $newText.Remove($m.Index, $m.Length).Insert($m.Index, '"theme": ' + $restore)
        $changes += "theme restored ($restore)"
    }

    if ($changes.Count -eq 0) {
        Write-Warning 'TerminalColors: the theme was not installed.'
        return
    }

    if ($null -eq (ConvertFrom-TcJsonText -Text $newText)) {
        throw 'TerminalColors: the change would have produced invalid JSON. Nothing was written.'
    }

    if ($PSCmdlet.ShouldProcess($SettingsPath, "Remove the TerminalColors theme ($($changes -join ', '))")) {
        [void](Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup)
    }
}
