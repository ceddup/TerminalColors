function Update-TerminalColor {
    <#
        .SYNOPSIS
        Applies the colour matching the current directory.

        .DESCRIPTION
        Called automatically every time the prompt is drawn while
        Enable-TerminalColors is active. Does nothing if the directory has not
        changed since the last call, so that the per-prompt cost stays negligible.

        .PARAMETER Path
        Directory to evaluate. Defaults to the current directory.

        .PARAMETER Force
        Reapplies the colour even when nothing has changed.

        .PARAMETER PassThru
        Returns the object describing the resolved colour.

        .EXAMPLE
        Update-TerminalColor -Force
        Reapplies the colour, for instance after editing .terminalcolors.json.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string] $Path,

        [switch] $Force,

        [switch] $PassThru
    )

    $options = Get-TcOptions

    if ($Path) {
        try { $target = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { $target = $Path }
    } else {
        $target = Get-TcCurrentPath
    }
    if (-not $target) { return }

    $pathChanged = ($target -ne $script:TcLastPath)

    # Directory unchanged: read nothing. The colour is only re-emitted when the
    # user asked for AlwaysReapply (useful if a program resets the terminal
    # background); otherwise return immediately.
    if (-not $pathChanged -and -not $Force) {
        if ($options.AlwaysReapply) {
            if ($script:TcLastInfo) {
                Set-TcAppearance -Info $script:TcLastInfo -Path $target -Options $options
            } else {
                Reset-TcAppearance -Options $options
            }
        }
        if ($PassThru) { return $script:TcLastInfo }
        return
    }

    if ($Force) { Clear-TcResolveCache }

    $info = Resolve-TcColor -Path $target -AutoGitColors ([bool]$options.AutoGitColors)

    $key = 'none'
    if ($info) { $key = '{0}|{1}' -f $info.Color, $info.Name }

    if ($key -ne $script:TcLastKey -or $Force) {
        if ($info) {
            Set-TcAppearance -Info $info -Path $target -Options $options
        } else {
            Reset-TcAppearance -Options $options
        }
        $script:TcLastKey = $key
    }

    $script:TcLastPath = $target
    $script:TcLastInfo = $info

    if ($PassThru) { return $info }
}

function Get-TcEffectiveBackground {
    <#
        .SYNOPSIS
        Background colour to send to the terminal for a given project.

        .DESCRIPTION
        In pure-colour mode this is the project colour as-is: the opaque backdrop
        keeps the pane readable, and any dilution would be counter-productive -
        including one a project asked for through its [tint] key.

        Otherwise the colour is blended into the reference background using the
        requested tint, the project's taking priority over the session's.

        .PARAMETER BaseBackground
        Reference background for the blend. Derived from the Windows Terminal
        settings when not supplied. Pure-colour mode never reads it, which avoids
        a settings.json read.
    #>
    [CmdletBinding()]
    param(
        [pscustomobject] $Info,
        [hashtable] $Options,
        [hashtable] $BaseBackground
    )

    if ($Options.PureColor) { return $Info.Rgb }

    $tint = $Options.Tint
    if ($null -ne $Info.Tint) { $tint = [double]$Info.Tint }

    if ($null -eq $BaseBackground) { $BaseBackground = Get-TcBaseBackground }
    return (Get-TcBlendedColor -Base $BaseBackground -Color $Info.Rgb -Amount $tint)
}

function Set-TcAppearance {
    [CmdletBinding()]
    param(
        [pscustomobject] $Info,
        [string] $Path,
        [hashtable] $Options
    )

    # Icon: the one from the configuration, otherwise the nearest coloured square.
    $icon = [string]$Info.Icon
    if ([string]::IsNullOrEmpty($icon) -and $Options.Icons) {
        $icon = Get-TcColorEmoji -Rgb $Info.Rgb
    }
    $effective = $Info.PSObject.Copy()
    $effective.Icon = $icon

    if (Test-TcVtSupported) {
        Set-TcTerminalBackground -Rgb (Get-TcEffectiveBackground -Info $Info -Options $Options)
    }

    if ($Options.SetTitle) {
        if ($null -eq $script:TcOriginalTitle) { $script:TcOriginalTitle = Get-TcWindowTitle }
        Set-TcWindowTitle -Title (Format-TcTitle -Format $Options.TitleFormat -Info $effective -Path $Path)
    }

    # The window border itself comes from the theme (window.frame), not from here.
    # This DWM call is a fallback for hosts that ignore the theme, plus the system
    # title bar when -CaptionColor is on. The border belongs to the window, so a
    # tab that is not the visible one must not repaint it, otherwise the tabs of a
    # freshly opened window fight over it.
    if ($Options.WindowBorder -and (Test-TcActiveTab) -ne $false) {
        if (Set-TcWindowBorderColor -Rgb $Info.Rgb -IncludeCaption:([bool]$Options.CaptionColor)) {
            $script:TcBorderApplied = $true
        }
    }
}

function Reset-TcAppearance {
    [CmdletBinding()]
    param(
        [hashtable] $Options,

        # Set for an explicit Reset-TerminalColor / Disable-TerminalColors: the
        # user asked for it, so restore the border whatever this session did.
        [switch] $Force
    )

    if (Test-TcVtSupported) {
        Reset-TcTerminalBackground -Explicit:([bool]$Options.ExplicitReset)
    }

    if ($Options.SetTitle -and $script:TcOriginalTitle) {
        Set-TcWindowTitle -Title $script:TcOriginalTitle
    }

    # Two guards, because erasing another tab's colour is the worst outcome here.
    # A tab only resets the border if it is the visible one AND it is the one that
    # coloured it in the first place - a tab that never coloured anything has
    # nothing to restore, and would only be clobbering a sibling.
    if ($Options.WindowBorder -and ($Force -or $script:TcBorderApplied) -and (Test-TcActiveTab) -ne $false) {
        [void](Reset-TcWindowBorderColor -IncludeCaption:([bool]$Options.CaptionColor))
        $script:TcBorderApplied = $false
    }
}

function Reset-TerminalColor {
    <#
        .SYNOPSIS
        Restores the terminal's default appearance (background, title, border).

        .PARAMETER Explicit
        Rewrites the background colour derived from the Windows Terminal settings
        instead of using the OSC 111 reset sequence. Useful if your version of
        Windows Terminal does not honour OSC 111.

        .EXAMPLE
        Reset-TerminalColor
    #>
    [CmdletBinding()]
    param([switch] $Explicit)

    $options = (Get-TcOptions).Clone()
    if ($Explicit) { $options.ExplicitReset = $true }

    Reset-TcAppearance -Options $options -Force
    $script:TcLastKey = 'none'
    $script:TcLastPath = $null
}
