# System title bar: the second way to get a pure colour, without touching the pane
# background and without adding a file.
#
# By default Windows Terminal draws its tabs INSIDE the title bar, so the window
# has no real system title bar and its colour depends on the theme - therefore on
# the background colour. Disabling showTabsInTitlebar gives the window a genuine
# system title bar back, which DWM can colour directly (DWMWA_CAPTION_COLOR),
# exactly like the border: pure colour, immediately, without going through the
# background colour.
#
# The trade-off: the tab strip moves below the title bar, and it stays subject to
# the theme. The tab itself therefore only carries the project colour when the
# opaque backdrop is installed (Install-TerminalColorsBackdrop).
#
# The actual colouring is done at runtime by [Enable-TerminalColors -CaptionColor].

function Get-TcShowTabsInTitlebar {
    <#
        .SYNOPSIS
        Value of showTabsInTitlebar in a parsed settings.json. $null when the key
        is absent (Windows Terminal then treats it as true).
    #>
    param($Settings)

    return (Get-TcJsonProperty -InputObject $Settings -Name 'showTabsInTitlebar')
}

function Install-TerminalColorsTitleBar {
    <#
        .SYNOPSIS
        Brings back a real system title bar, which DWM can colour in pure colour.

        .DESCRIPTION
        Writes [showTabsInTitlebar: false] into settings.json. The Windows Terminal
        window then regains a system title bar, which TerminalColors colours in the
        pure project colour through DWM - like the border, and without touching the
        pane background.

        Two things to know:

        - Windows Terminal must be restarted completely (all of its windows
          closed): this setting is not re-read at runtime.
        - the actual colouring requires [Enable-TerminalColors -CaptionColor].
          Without that switch the title bar keeps the system colour.

        The tab strip, for its part, moves below the title bar and stays subject to
        the theme: for the tab itself to carry the project colour, install the
        opaque backdrop as well (Install-TerminalColorsBackdrop).

        .PARAMETER SettingsPath
        Path of the settings.json to modify. Detected automatically by default.

        .PARAMETER NoBackup
        Does not write a backup copy.

        .EXAMPLE
        Install-TerminalColorsTitleBar
        Enable-TerminalColors -CaptionColor

        .EXAMPLE
        Install-TerminalColorsTitleBar -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $SettingsPath,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    $settings = ConvertFrom-TcJsonText -Text $text
    if ($null -eq $settings) {
        throw "TerminalColors: [$SettingsPath] is not valid JSON. Fix it before changing the title bar."
    }

    $previous = Get-TcShowTabsInTitlebar -Settings $settings
    if ($previous -eq $false) {
        Write-Verbose 'TerminalColors: showTabsInTitlebar is already false.'
        return [pscustomobject]@{
            SettingsPath = $SettingsPath
            Changed      = $false
            Changes      = @()
            Backup       = $null
            RestartNeeded = $false
        }
    }

    $masked = Get-TcMaskedJson -Text $text
    $root = Find-TcJsonRootIndex -Masked $masked
    $applied = Set-TcJsonMember -Text $text -AnchorIndex $root -Name 'showTabsInTitlebar' -Literal 'false' -Indent '    '
    $newText = $applied.Text

    $parsed = ConvertFrom-TcJsonText -Text $newText
    if ($null -eq $parsed) {
        throw 'TerminalColors: the change would have produced invalid JSON. Nothing was written.'
    }
    if ((Get-TcShowTabsInTitlebar -Settings $parsed) -ne $false) {
        throw 'TerminalColors: verification failed (showTabsInTitlebar not disabled). Nothing was written.'
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($SettingsPath, 'Disable showTabsInTitlebar')) {
        # Record the absence of the key as a value in its own right, so that
        # uninstalling removes the key instead of writing [true].
        if ($null -eq $previous) {
            Set-TcInstallState -Name 'PreviousShowTabsInTitlebar' -Value 'absent'
        } else {
            Set-TcInstallState -Name 'PreviousShowTabsInTitlebar' -Value ([bool]$previous)
        }
        $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
    }

    return [pscustomobject]@{
        SettingsPath  = $SettingsPath
        Changed       = $true
        Changes       = @("showTabsInTitlebar $($applied.Action)")
        Backup        = $backupPath
        RestartNeeded = $true
    }
}

function Uninstall-TerminalColorsTitleBar {
    <#
        .SYNOPSIS
        Puts the tabs back into the title bar (Windows Terminal's default
        behaviour).

        .DESCRIPTION
        Restores the value of showTabsInTitlebar as it was before
        Install-TerminalColorsTitleBar, removing the key if it was absent. Windows
        Terminal must be restarted completely.

        .PARAMETER SettingsPath
        Path of the settings.json to modify. Detected automatically by default.

        .PARAMETER NoBackup
        Does not write a backup copy.

        .EXAMPLE
        Uninstall-TerminalColorsTitleBar
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $SettingsPath,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    $settings = ConvertFrom-TcJsonText -Text $text
    if ($null -eq $settings) {
        throw "TerminalColors: [$SettingsPath] is not valid JSON."
    }

    if ((Get-TcShowTabsInTitlebar -Settings $settings) -ne $false) {
        Write-Warning 'TerminalColors: showTabsInTitlebar is not disabled; nothing to do.'
        return
    }

    $masked = Get-TcMaskedJson -Text $text
    $root = Find-TcJsonRootIndex -Masked $masked
    $restore = Get-TcInstallState -Name 'PreviousShowTabsInTitlebar'

    if ($null -eq $restore -or [string]$restore -eq 'absent') {
        $applied = Remove-TcJsonMember -Text $text -AnchorIndex $root -Name 'showTabsInTitlebar'
        $change = 'showTabsInTitlebar removed'
    } else {
        $literal = 'false'
        if ([bool]$restore) { $literal = 'true' }
        $applied = Set-TcJsonMember -Text $text -AnchorIndex $root -Name 'showTabsInTitlebar' -Literal $literal -Indent '    '
        $change = "showTabsInTitlebar restored ($literal)"
    }

    $newText = $applied.Text
    if ($null -eq (ConvertFrom-TcJsonText -Text $newText)) {
        throw 'TerminalColors: the change would have produced invalid JSON. Nothing was written.'
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($SettingsPath, 'Put the tabs back into the title bar')) {
        $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
        Remove-TcInstallState -Name 'PreviousShowTabsInTitlebar'
    }

    return [pscustomobject]@{
        SettingsPath  = $SettingsPath
        Changed       = $true
        Changes       = @($change)
        Backup        = $backupPath
        RestartNeeded = $true
    }
}

function Test-TerminalColorsTitleBar {
    <#
        .SYNOPSIS
        Indicates whether Windows Terminal shows a real system title bar (and can
        therefore be coloured in pure colour by DWM).

        .PARAMETER SettingsPath
        Path of the settings.json to inspect. Detected automatically by default.

        .EXAMPLE
        Test-TerminalColorsTitleBar
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $SettingsPath)

    if (-not $SettingsPath) { $SettingsPath = Get-TcWtSettingsPath }
    if (-not $SettingsPath -or -not [System.IO.File]::Exists($SettingsPath)) { return $false }

    $settings = ConvertFrom-TcJsonFile -Path $SettingsPath
    if ($null -eq $settings) { return $false }
    return ((Get-TcShowTabsInTitlebar -Settings $settings) -eq $false)
}
