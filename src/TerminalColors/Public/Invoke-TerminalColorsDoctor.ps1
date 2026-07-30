function Invoke-TerminalColorsDoctor {
    <#
        .SYNOPSIS
        Checks the installation and reports what would prevent the colouring from
        working.

        .DESCRIPTION
        Inspects the environment (Windows Terminal, Windows version), the theme,
        the opaque backdrop, the profile hook, the Windows Terminal profile
        settings that could neutralise the colouring, and the colour resolved for
        the current directory.

        .PARAMETER PassThru
        Also returns the results as objects, in addition to printing them.

        .EXAMPLE
        Invoke-TerminalColorsDoctor
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch] $PassThru)

    $results = New-Object System.Collections.ArrayList

    function Add-Result {
        param([string] $Check, [ValidateSet('OK', 'Warning', 'Problem', 'Info')] [string] $Status, [string] $Detail)
        [void]$results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
    }

    # --- Environment --------------------------------------------------------
    if (Test-TcWindowsTerminal) {
        Add-Result 'Windows Terminal' 'OK' "session detected (WT_SESSION=$($env:WT_SESSION))"
    } else {
        Add-Result 'Windows Terminal' 'Problem' 'WT_SESSION is not set: this session is not running in Windows Terminal, so no colour will be applied.'
    }

    $build = 0
    try { $build = [int][Environment]::OSVersion.Version.Build } catch { }
    if ($build -ge 22000) {
        Add-Result 'Window border' 'OK' "Windows build ${build}: border colouring available."
    } else {
        Add-Result 'Window border' 'Warning' "Windows build ${build}: border colouring requires Windows 11 (22000+). The tab and title bar still work."
    }

    # --- settings.json and theme --------------------------------------------
    $settingsPath = Get-TcWtSettingsPath
    if ($settingsPath) {
        Add-Result 'settings.json' 'OK' $settingsPath

        # Tell [unreadable file] apart from [invalid JSON]: the fix is not the
        # same, and without the cause the user can only guess.
        $text = ''
        $readError = ''
        try { $text = [System.IO.File]::ReadAllText($settingsPath) } catch { $readError = $_.Exception.Message }
        $settings = ConvertFrom-TcJsonText -Text $text

        if ($null -eq $settings) {
            if ($readError) {
                Add-Result 'Theme' 'Problem' "settings.json could not be read ($readError): unable to check the theme."
            } else {
                Add-Result 'Theme' 'Problem' 'settings.json contains invalid JSON: unable to check the theme.'
            }
        } else {
            $installed = $settings.themes | Where-Object { $_.name -eq 'TerminalColors' }
            $selected = ([string]$settings.theme -eq 'TerminalColors')

            if ($installed -and $selected -and -not (Test-TcThemeUpToDate -Settings $settings)) {
                Add-Result 'Theme' 'Warning' 'theme from an earlier version: the tab row follows the active project, or background tabs do not carry their own colour. Run Install-TerminalColorsTheme to upgrade it.'
            } elseif ($installed -and $selected) {
                Add-Result 'Theme' 'OK' 'the TerminalColors theme is installed and selected.'
            } elseif ($installed) {
                Add-Result 'Theme' 'Problem' "theme present but not selected (current theme: [$($settings.theme)]). Run Install-TerminalColorsTheme."
            } else {
                Add-Result 'Theme' 'Problem' 'theme missing: without it, the tab and title bar do not change colour. Run Install-TerminalColorsTheme.'
            }

            # --- Opaque backdrop --------------------------------------------
            # This is what allows pure colour on the tab without colouring the
            # pane. The inconsistency to report first is -PureColor without the
            # backdrop: the pane would take the full project colour.
            $backdrop = Test-TerminalColorsBackdrop -SettingsPath $settingsPath
            $pureColor = [bool]($script:TcOptions -and $script:TcOptions.PureColor)

            if ($backdrop.Installed) {
                if (-not $backdrop.ImageExists) {
                    Add-Result 'Opaque backdrop' 'Problem' "the image [$($backdrop.ImagePath)] is declared but missing from disk: the pane will take the pure project colour. Run Install-TerminalColorsBackdrop again."
                } elseif (-not $pureColor) {
                    Add-Result 'Opaque backdrop' 'Warning' "installed (pane pinned to $($backdrop.Color)) but this session still dilutes the colour: add -PureColor to Enable-TerminalColors for a vivid tab."
                } else {
                    Add-Result 'Opaque backdrop' 'OK' "active: pane pinned to $($backdrop.Color), tab and title bar in pure colour."
                }

                if ($backdrop.ProfileOverrides.Count -gt 0) {
                    Add-Result 'Opaque backdrop' 'Warning' "these profiles declare their own background image and therefore ignore the backdrop: $($backdrop.ProfileOverrides -join ', ')."
                }
            } elseif ($backdrop.ForeignImage) {
                Add-Result 'Opaque backdrop' 'Warning' "a background image of your own is declared [$($backdrop.ImagePath)]: the backdrop is not installed. Install-TerminalColorsBackdrop -Force would replace it (it would be restorable)."
            } elseif ($pureColor) {
                Add-Result 'Opaque backdrop' 'Problem' 'missing while -PureColor is active: the pane background takes the full project colour. Run Install-TerminalColorsBackdrop, or drop -PureColor.'
            } else {
                Add-Result 'Opaque backdrop' 'Info' 'not installed: the colour is diluted onto the pane background (the original behaviour). Install-TerminalColorsBackdrop makes it vivid on the tab.'
            }

            # --- Window border ----------------------------------------------
            # The border comes from the theme, not from DWM: colouring it through
            # DwmSetWindowAttribute returns S_OK on a Windows Terminal window and
            # changes nothing. So the thing to check is the theme key.
            $themeObject = $settings.themes | Where-Object { $_.name -eq 'TerminalColors' } | Select-Object -First 1
            $frame = [string](Get-TcJsonProperty -InputObject (Get-TcJsonProperty -InputObject $themeObject -Name 'window') -Name 'frame')
            if ($frame -eq 'terminalBackground') {
                Add-Result 'Window border' 'OK' 'the theme paints the border with the project colour (window.frame). It is one pixel wide - Windows sets that width.'
            } elseif ($frame) {
                Add-Result 'Window border' 'Warning' "the theme pins the border to [$frame] instead of following the project. Run Install-TerminalColorsTheme."
            } else {
                Add-Result 'Window border' 'Problem' 'the theme does not declare window.frame, so the border keeps the system colour. Run Install-TerminalColorsTheme.'
            }

            # --- System title bar -------------------------------------------
            $systemTitleBar = ((Get-TcJsonProperty -InputObject $settings -Name 'showTabsInTitlebar') -eq $false)
            $captionColor = [bool]($script:TcOptions -and $script:TcOptions.CaptionColor)
            if ($systemTitleBar -and -not $captionColor) {
                Add-Result 'Title bar' 'Warning' 'system title bar enabled (showTabsInTitlebar: false) but -CaptionColor is missing: it will keep the system colour.'
            } elseif ($systemTitleBar) {
                Add-Result 'Title bar' 'OK' 'system title bar coloured in pure colour by DWM.'
            } elseif ($captionColor) {
                Add-Result 'Title bar' 'Info' '-CaptionColor is active but the tabs are inside the title bar, so it has no visible effect. Install-TerminalColorsTitleBar moves the tabs out of the title bar.'
            }

            $wtProfile = Get-TcWtProfile -Settings $settings -ProfileId $env:WT_PROFILE_ID
            if ($wtProfile) {
                if ($wtProfile.tabColor) {
                    Add-Result 'WT profile' 'Problem' "[tabColor] ($($wtProfile.tabColor)) is set on this profile: it overrides the theme and pins the tab colour. Remove it."
                }
                if ($wtProfile.suppressApplicationTitle) {
                    Add-Result 'WT profile' 'Warning' '[suppressApplicationTitle] is enabled: the tab title will not follow the project (the colour still will).'
                }
                if ($wtProfile.tabTitle) {
                    Add-Result 'WT profile' 'Warning' "[tabTitle] ($($wtProfile.tabTitle)) is set: it can pin the tab title."
                }
            }
        }
    } else {
        Add-Result 'settings.json' 'Problem' 'not found. Start Windows Terminal once, then run Install-TerminalColorsTheme.'
    }

    # --- Session ------------------------------------------------------------
    $base = Get-TcBaseBackground
    Add-Result 'Reference background' 'Info' "$(ConvertTo-TcHex -Rgb $base) (used as the blending base; can be forced with -BaseBackground)"

    if (Test-TerminalColorsEnabled) {
        $options = Get-TcOptions
        $mode = "tint $($options.Tint)"
        if ($options.PureColor) { $mode = 'pure colour' }
        Add-Result 'Session' 'OK' "colouring active ($mode, title $(if ($options.SetTitle) { 'yes' } else { 'no' }), border $(if ($options.WindowBorder) { 'yes' } else { 'no' }))"
    } else {
        Add-Result 'Session' 'Warning' 'colouring is not active in this session. Run Enable-TerminalColors.'
    }

    if (Test-TerminalColorsProfile) {
        Add-Result 'PowerShell profile' 'OK' "block present in $($PROFILE.CurrentUserAllHosts)"
    } else {
        Add-Result 'PowerShell profile' 'Warning' 'block missing: the colouring will not be active on next start. Run Install-TerminalColorsProfile.'
    }

    if ($script:TcOptions -and $script:TcOptions.WindowBorder -and (Test-TcWindowsTerminal)) {
        $hwnd = Get-TcTerminalWindowHandle
        if ($hwnd -ne [IntPtr]::Zero) {
            Add-Result 'Terminal window' 'OK' ("handle 0x{0:X}" -f [int64]$hwnd)

            if ((Test-TcActiveTab) -eq $false) {
                Add-Result 'Visible tab' 'Info' 'this tab is not the one on screen, so it leaves the window-wide colouring alone.'
            }
        } else {
            Add-Result 'Terminal window' 'Warning' 'Windows Terminal window not located: the border will not be coloured (tab and title bar still work).'
        }
    }

    # --- Current directory --------------------------------------------------
    $current = Get-TcCurrentPath
    if ($current) {
        $info = Get-TerminalColor -Path $current
        if ($info.Color) {
            Add-Result 'Current folder' 'OK' "$($info.Color) via $($info.Source) -> $($info.SourcePath)"
        } else {
            Add-Result 'Current folder' 'Info' "no colour for [$current] (expected outside a project)."
        }
    }

    # --- Output -------------------------------------------------------------
    $colors = @{ 'OK' = 'Green'; 'Warning' = 'Yellow'; 'Problem' = 'Red'; 'Info' = 'Cyan' }
    $symbols = @{ 'OK' = '[ok]'; 'Warning' = '[! ]'; 'Problem' = '[KO]'; 'Info' = '[i ]' }

    Write-Host ''
    Write-Host '  TerminalColors - diagnostics' -ForegroundColor White
    Write-Host '  ----------------------------' -ForegroundColor DarkGray
    foreach ($r in $results) {
        Write-Host ('  {0} ' -f $symbols[$r.Status]) -ForegroundColor $colors[$r.Status] -NoNewline
        Write-Host ('{0,-21}' -f $r.Check) -ForegroundColor White -NoNewline
        Write-Host $r.Detail -ForegroundColor Gray
    }
    Write-Host ''

    if ($PassThru) { return $results }
}
