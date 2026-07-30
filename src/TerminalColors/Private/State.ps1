# Module state and options for the current session.

$script:TcEnabled = $false
$script:TcLastPath = $null
$script:TcLastKey = $null
$script:TcLastInfo = $null
$script:TcOriginalTitle = $null

# Has this session ever coloured the window border? A session that never has must
# not reset it: the border belongs to the window, and when several tabs start at
# once a colourless tab would otherwise wipe the colour a sibling just applied.
# The title check alone cannot catch this - a colourless tab restores the shell's
# default title, which is exactly what the window shows until the active tab sets
# its own, so the tab wrongly believes it is the visible one.
$script:TcBorderApplied = $false
$script:TcOptions = $null

function New-TcDefaultOptions {
    return @{
        # Strength of the tint applied to the terminal background (0 = none,
        # 1 = pure colour). A low value keeps the text perfectly readable while
        # still clearly colouring the tab and the title bar.
        Tint           = 0.30
        # PureColor sends the project colour undiluted: the tab, the title bar and
        # the border become vivid. Only enable it with the opaque backdrop
        # installed (Install-TerminalColorsBackdrop), otherwise it is the pane
        # background that takes the pure colour.
        PureColor      = $false
        SetTitle       = $true
        TitleFormat    = '{icon} {name}'
        Icons          = $true
        WindowBorder   = $true
        CaptionColor   = $false
        AutoGitColors  = $true
        BaseBackground = $null
        ExplicitReset  = $false
        # By default the colour is only re-emitted when the directory changes: zero
        # pointless writes. AlwaysReapply re-emits it on every prompt, in case a
        # program has reset the terminal background in the meantime.
        AlwaysReapply  = $false
    }
}

function Get-TcOptions {
    if ($null -eq $script:TcOptions) { $script:TcOptions = New-TcDefaultOptions }
    return $script:TcOptions
}

function Get-TcCurrentPath {
    <#
        .SYNOPSIS
        The user's current directory. A module has its own session state, so the
        global location is read explicitly.
    #>
    [CmdletBinding()]
    param()

    $location = $null
    try { $location = $global:PWD } catch { }
    if ($null -eq $location) {
        try { $location = Get-Location } catch { return $null }
    }
    if ($null -eq $location) { return $null }

    if ($location.Provider -and $location.Provider.Name -ne 'FileSystem') { return $null }

    $path = [string]$location.ProviderPath
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return $path
}
