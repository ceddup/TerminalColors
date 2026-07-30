# Installs the Windows Terminal theme that makes the tab and the title bar follow
# the active pane's background colour.
#
# The surgical settings.json editing helpers live in Private\WtSettings.ps1,
# shared with Install-TerminalColorsBackdrop and Install-TerminalColorsTitleBar.

$script:TcThemeName = 'TerminalColors'

function Get-TcSelectedTheme {
    <#
        .SYNOPSIS
        Raw value of the root "theme" setting, exactly as written: a quoted name,
        or the { "dark": ..., "light": ... } object form. $null when absent.
    #>
    param([string] $Text)

    $masked = Get-TcMaskedJson -Text $Text
    $m = [regex]::Match($masked, '"theme"\s*:\s*(?:"[^"]*"|\{[^{}]*\})')
    if (-not $m.Success) { return $null }
    $vm = [regex]::Match($Text.Substring($m.Index, $m.Length), '"theme"\s*:\s*(.+)$', 'Singleline')
    if ($vm.Success) { return $vm.Groups[1].Value.Trim() }
    return $null
}

function Get-TcApplicationTheme {
    <#
        .SYNOPSIS
        The window.applicationTheme a replacement theme must declare to leave the
        chrome as it was.

        .DESCRIPTION
        Selecting a theme replaces the previous one wholesale, so whatever it does
        not declare is lost. The tab row is painted from the chrome, which means
        dropping applicationTheme would flip the strip on a machine whose Windows
        is in the other mode - which is exactly what "system" did on a Windows set
        to light.

        The built-in dark and light themes are explicit. Anything else - "system",
        the { dark, light } object form, a custom theme, or nothing at all -
        follows Windows, which is Windows Terminal's own default.
    #>
    param([string] $ThemeValue)

    if ([string]::IsNullOrWhiteSpace($ThemeValue)) { return 'system' }
    if ($ThemeValue -match '^"?(dark|legacyDark)"?$') { return 'dark' }
    if ($ThemeValue -match '^"?(light|legacyLight)"?$') { return 'light' }
    return 'system'
}

function Get-TcThemeJson {
    <#
        .SYNOPSIS
        The theme document. [tab] follows the project; the tab row is left to
        Windows Terminal unless a colour is explicitly asked for - see the comment
        below, the asymmetry is the whole point.
    #>
    param(
        [string] $Indent = '    ',
        [string] $TabRowColor,
        [ValidateSet('system', 'light', 'dark')]
        [string] $ApplicationTheme = 'system'
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
    #
    # The row must NOT be terminalBackground: the strip would take the colour of
    # whichever project is in front, and since it is the base every background tab
    # is composited over, a plain black tab next to a #215732 project came out
    # #1A4026 and a #61DAFB one came out #347E6E - everything turned green.
    #
    # Any stable colour satisfies that, so the row is simply left out rather than
    # pinned: Windows Terminal then paints it from its own chrome, exactly as its
    # built-in themes do - light, dark and system declare no tabRow.background
    # either. The strip therefore looks the same whether this module is installed
    # or not, which is the point. -TabRowColor pins it for anyone who does want a
    # specific colour, and window.applicationTheme carries the chrome's light/dark
    # identity over from the theme being replaced.
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
        '    },'
    )

    if ($TabRowColor) {
        $lines += @(
            '    "tabRow":',
            '    {',
            ('        "background": "' + $TabRowColor + '",'),
            ('        "unfocusedBackground": "' + $TabRowColor + '"'),
            '    },'
        )
    }

    $lines += @(
        '    "window":',
        '    {',
        ('        "applicationTheme": "' + $ApplicationTheme + '",'),
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
        Tells whether an installed theme is a working shape: every tab follows its
        own project, the tab row does not, and the border is coloured.

        A theme left over from an older version of the module fails this check, and
        Install-TerminalColorsTheme then replaces it without the caller having to
        pass -Force. Only the two broken shapes count: terminalBackground on the
        row (background tabs borrow the active project's colour) and a missing
        window.frame (nothing colours the border).

        A row pinned to a fixed colour is not broken, just a deliberate choice, so
        it passes: -TabRowColor must survive a plain reinstall.
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
            ($rowBackground -ne 'terminalBackground') -and
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

        The tab row - the strip the tabs sit in - is deliberately left out of that,
        and left alone entirely: Windows Terminal paints it from its own chrome, as
        it does without this module, so installing changes nothing about it.

        settings.json is modified by targeted insertion, with a backup taken first
        and the result validated before writing.

        .PARAMETER SettingsPath
        Path of the settings.json to modify. Detected automatically by default
        (Store, Preview, unpackaged and portable versions).

        .PARAMETER TabRowColor
        Pins the tab row - the strip the tabs sit in, which is also the title bar
        when the tabs are drawn inside it - to a fixed colour. Left out by default:
        the strip keeps the colour Windows Terminal gives it, so it looks the same
        installed or not.

        Whatever you pass, it must be a fixed colour and never the project's: the
        strip is the base Windows Terminal composites background tabs over, so a
        stable base is what lets each background tab show its own colour.

        .PARAMETER ApplicationTheme
        Light or dark identity of the window chrome, which is what paints the tab
        row. Taken from the theme being replaced by default, so the strip does not
        flip when Windows is set to the other mode.

        .PARAMETER Force
        Reinstalls the theme even when it is already present. A theme left over
        from an earlier version is upgraded automatically, without this switch.

        .PARAMETER NoBackup
        Does not write a backup copy.

        .EXAMPLE
        Install-TerminalColorsTheme

        .EXAMPLE
        Install-TerminalColorsTheme -TabRowColor '#000000'
        Pitch-black tab row, instead of leaving it to Windows Terminal.

        .EXAMPLE
        Install-TerminalColorsTheme -WhatIf
        Shows what would change without writing anything.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $SettingsPath,
        [string] $TabRowColor,
        [ValidateSet('system', 'light', 'dark')]
        [string] $ApplicationTheme,
        [switch] $Force,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    $settings = ConvertFrom-TcJsonText -Text $text
    if ($null -eq $settings) {
        throw "TerminalColors: [$SettingsPath] is not valid JSON. Fix it before installing the theme."
    }

    # --- Tab row: only pinned when asked for --------------------------------
    $rowHex = $null
    if ($TabRowColor) {
        $rowRgb = ConvertFrom-TcColor -Value $TabRowColor
        if ($null -eq $rowRgb) { throw "TerminalColors: invalid tab-row colour [$TabRowColor]." }
        $rowHex = ConvertTo-TcHex -Rgb $rowRgb
    }

    # --- Chrome: inherited from the theme being replaced --------------------
    # Selecting a theme replaces the previous one wholesale, so the light/dark
    # identity has to be carried over explicitly or the strip flips on a machine
    # whose Windows is in the other mode. On a reinstall the current value is our
    # own theme, so the one recorded at first install answers instead.
    if (-not $PSBoundParameters.ContainsKey('ApplicationTheme')) {
        $selected = Get-TcSelectedTheme -Text $text
        if ($selected -match '"TerminalColors"') { $selected = Get-TcInstallState -Name 'PreviousTheme' }
        $ApplicationTheme = Get-TcApplicationTheme -ThemeValue $selected
    }

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
        $themeJson = Get-TcThemeJson -TabRowColor $rowHex -ApplicationTheme $ApplicationTheme
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
            ApplicationTheme  = $ApplicationTheme
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
        ApplicationTheme = $ApplicationTheme
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
