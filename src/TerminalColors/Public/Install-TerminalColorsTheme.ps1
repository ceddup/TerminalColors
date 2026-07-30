# Installs the Windows Terminal theme that makes the tab and the title bar follow
# the active pane's background colour.
#
# The surgical settings.json editing helpers live in Private\WtSettings.ps1,
# shared with Install-TerminalColorsBackdrop and Install-TerminalColorsTitleBar.

$script:TcThemeName = 'TerminalColors'

function Get-TcThemeJson {
    <#
        .SYNOPSIS
        The theme document. [tab] follows the project, [tabRow] is pinned to a
        fixed colour - see the comment below, the asymmetry is the whole point.
    #>
    param(
        [string] $Indent = '    ',
        [string] $TabRowColor = '#0C0C0C'
    )

    # How Windows Terminal actually paints a tab, measured rather than assumed:
    #
    #   - the SELECTED tab is painted with its own background colour, opaquely.
    #     A #215732 project gives exactly #215732.
    #   - a BACKGROUND tab is composited at roughly 30 % opacity over the tab row.
    #     Its own colour still shows through, but mixed with the row's.
    #
    # Hence the asymmetry below. [tab] uses terminalBackground, the only per-tab
    # value the theme format offers, so every tab carries its own project colour.
    # [tabRow] is pinned to a fixed colour instead of terminalBackground for two
    # reasons: the strip itself must not take the active project's colour, and it
    # is the base every background tab is composited over - a stable base means a
    # background tab shows its own colour rather than 70 % of its neighbour's.
    # With terminalBackground on the row, a plain black tab next to a #215732
    # project came out #1A4026 and a #61DAFB one came out #347E6E: everything
    # turned green.
    #
    # window.frame is what actually colours the window border. DWM is not:
    # DwmSetWindowAttribute(DWMWA_BORDER_COLOR) returns S_OK on a Windows Terminal
    # window and changes nothing at all - measured, colour applied straight from a
    # test process with nothing else in between. Windows Terminal draws its own
    # frame, so the theme is the only way in, and terminalBackground makes it
    # follow the project exactly like the tab does.
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
        ('        "background": "' + $TabRowColor + '",'),
        ('        "unfocusedBackground": "' + $TabRowColor + '"'),
        '    },',
        '    "window":',
        '    {',
        '        "applicationTheme": "system",',
        '        "frame": "terminalBackground",',
        '        "unfocusedFrame": "terminalBackground"',
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

function Test-TcThemeInSettings {
    <#
        .SYNOPSIS
        Whether the theme is present in the settings.json on disk.

        .DESCRIPTION
        Test-TcThemeInstalled works on text, which suits the install path since it
        already holds the document. A caller that only wants to know whether there
        is anything to remove should not have to read the file itself.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $SettingsPath)

    if (-not $SettingsPath) {
        try { $SettingsPath = Get-TcWtSettingsPath } catch { return $false }
    }
    if (-not $SettingsPath -or -not [System.IO.File]::Exists($SettingsPath)) { return $false }
    return (Test-TcThemeInstalled -Text ([System.IO.File]::ReadAllText($SettingsPath)))
}

function Test-TcThemeUpToDate {
    <#
        .SYNOPSIS
        Tells whether an installed theme is the current shape: every tab follows
        its own project, and the tab row is pinned to a fixed colour.

        A theme left over from an older version of the module fails this check, and
        Install-TerminalColorsTheme then replaces it without the caller having to
        pass -Force. The two shapes that matter: terminalBackground on the row
        (background tabs borrow the active project's colour) and a missing
        window.frame (nothing colours the border).
    #>
    param($Settings)

    $theme = $Settings.themes | Where-Object { $_.name -eq $script:TcThemeName } | Select-Object -First 1
    if ($null -eq $theme) { return $false }

    $tab = Get-TcJsonProperty -InputObject $theme -Name 'tab'
    $tabRow = Get-TcJsonProperty -InputObject $theme -Name 'tabRow'
    $window = Get-TcJsonProperty -InputObject $theme -Name 'window'

    $tabUnfocused = [string](Get-TcJsonProperty -InputObject $tab -Name 'unfocusedBackground')
    $rowBackground = [string](Get-TcJsonProperty -InputObject $tabRow -Name 'background')
    $frame = [string](Get-TcJsonProperty -InputObject $window -Name 'frame')

    return (($tabUnfocused -eq 'terminalBackground') -and
            ($rowBackground -match '^#') -and
            ($frame -eq 'terminalBackground'))
}

function Install-TerminalColorsTheme {
    <#
        .SYNOPSIS
        Installs the [TerminalColors] theme into Windows Terminal and selects it.

        .DESCRIPTION
        This theme is what makes the colouring visible: it tells Windows Terminal
        to paint the tab and the window border with the active pane's background
        colour. Since the module changes that background colour on every directory
        change, both follow automatically.

        The tab row - the strip the tabs sit in - is deliberately left out of that:
        it is pinned to a fixed colour so it never takes the colour of whichever
        project happens to be in front.

        settings.json is modified by targeted insertion, with a backup taken first
        and the result validated before writing.

        .PARAMETER SettingsPath
        Path of the settings.json to modify. Detected automatically by default
        (Store, Preview, unpackaged and portable versions).

        .PARAMETER TabRowColor
        Colour of the tab row - the strip the tabs sit in, which is also the title
        bar when the tabs are drawn inside it. Defaults to the background colour
        declared by your profile or your colour scheme, so the strip stays the
        colour of a plain terminal.

        It is deliberately a fixed colour, never the project's: the strip must not
        take the colour of whichever project happens to be in front, and it is the
        base Windows Terminal composites background tabs over, so a stable base is
        what lets each background tab show its own colour.

        .PARAMETER Force
        Reinstalls the theme even when it is already present. A theme left over
        from an earlier version is upgraded automatically, without this switch.

        .PARAMETER NoBackup
        Does not write a backup copy.

        .EXAMPLE
        Install-TerminalColorsTheme

        .EXAMPLE
        Install-TerminalColorsTheme -TabRowColor '#000000'
        Pitch-black tab row, whatever the profile's colour scheme.

        .EXAMPLE
        Install-TerminalColorsTheme -WhatIf
        Shows what would change without writing anything.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $SettingsPath,
        [string] $TabRowColor,
        [switch] $Force,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    $settings = ConvertFrom-TcJsonText -Text $text
    if ($null -eq $settings) {
        throw "TerminalColors: [$SettingsPath] is not valid JSON. Fix it before installing the theme."
    }

    # --- Colour of the tab row ----------------------------------------------
    if ($TabRowColor) {
        $rowRgb = ConvertFrom-TcColor -Value $TabRowColor
        if ($null -eq $rowRgb) { throw "TerminalColors: invalid tab-row colour [$TabRowColor]." }
    } else {
        $rowRgb = Get-TcSettingsBackground -Settings $settings -ProfileId $env:WT_PROFILE_ID
        if ($null -eq $rowRgb) { $rowRgb = ConvertFrom-TcColor -Value $script:TcDefaultBaseBackground }
    }
    $rowHex = ConvertTo-TcHex -Rgb $rowRgb

    $alreadyInstalled = Test-TcThemeInstalled -Text $text

    # A theme from an earlier version makes background tabs borrow the active
    # project's colour: it is replaced without the caller having to ask.
    $outdated = ($alreadyInstalled -and -not (Test-TcThemeUpToDate -Settings $settings))
    $replace = ($Force -or $outdated)

    if ($alreadyInstalled -and -not $replace) {
        Write-Verbose 'TerminalColors: theme already present and current, only the selection is checked.'
    }

    $newText = $text
    $masked = Get-TcMaskedJson -Text $newText
    $changes = @()

    # --- 1. Remove a previous version of the theme --------------------------
    if ($alreadyInstalled -and $replace) {
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
            if ($outdated -and -not $Force) {
                $changes += 'theme from an earlier version upgraded'
            } else {
                $changes += 'previous theme removed'
            }
            $alreadyInstalled = $false
        }
    }

    # --- 2. Insert the theme into the "themes" array ------------------------
    if (-not $alreadyInstalled) {
        $themeJson = Get-TcThemeJson -TabRowColor $rowHex
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
            SettingsPath      = $SettingsPath
            Changed           = $false
            Changes           = @()
            TabRowColor       = $rowHex
            Backup            = $null
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
    if (-not (Test-TcThemeUpToDate -Settings $parsed)) {
        throw 'TerminalColors: verification failed (tabs would not each carry their own colour, or the tab row would follow the active project). Nothing was written.'
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
        TabRowColor  = $rowHex
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
