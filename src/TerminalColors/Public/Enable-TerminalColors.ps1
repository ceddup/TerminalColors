function Enable-TerminalColors {
    <#
        .SYNOPSIS
        Enables automatic terminal colouring based on the current directory.

        .DESCRIPTION
        Wraps the existing [prompt] function: every time the prompt is drawn, the
        colour associated with the current directory is applied. Your original
        prompt (oh-my-posh, Starship, your own...) is kept, and restored by
        Disable-TerminalColors.

        Put this in your PowerShell profile, after your prompt's initialisation if
        you use one.

        .PARAMETER Tint
        Strength of the tint applied to the terminal background, from 0 to 1.
        The default (0.30) clearly colours the tab and title bar while keeping the
        background dark and readable. Ignored when -PureColor is set.

        .PARAMETER PureColor
        Sends the project colour with no dilution at all: the tab, the title bar
        and the border take the exact project colour.

        Only use this with the opaque backdrop installed
        (Install-TerminalColorsBackdrop), which keeps the pane background
        unchanged. Without it, the whole pane would take the pure colour and the
        text would become unreadable. Invoke-TerminalColorsDoctor reports the
        inconsistent combination.

        .PARAMETER TitleFormat
        Tab title template. Available tokens: {icon}, {name}, {color}, {folder},
        {path}.

        .PARAMETER NoTitle
        Leaves the tab title alone.

        .PARAMETER NoIcons
        Does not add a coloured square before the project name.

        .PARAMETER NoWindowBorder
        Does not colour the window border (avoids the DWM call).

        .PARAMETER CaptionColor
        Also colours the system title bar. Only has a visible effect when
        [showTabsInTitlebar] is disabled in Windows Terminal.

        .PARAMETER NoAutoGitColors
        Disables the automatic colour derived from a Git repository name. Only
        explicit colours (.terminalcolors.json, Peacock, Solution Colors) will be
        used.

        .PARAMETER BaseBackground
        Forces the reference background colour used for blending, instead of
        deriving it from the Windows Terminal settings.

        .PARAMETER ExplicitReset
        When leaving a coloured folder, rewrites the reference background colour
        instead of emitting the OSC 111 reset sequence.

        .PARAMETER AlwaysReapply
        Reapplies the colour every time the prompt is drawn, not only when the
        directory changes. Enable this if a program you run resets the terminal
        background colour.

        .EXAMPLE
        Enable-TerminalColors

        .EXAMPLE
        Enable-TerminalColors -PureColor
        Vivid colour on the tab, title bar and border, pane background unchanged.
        Requires Install-TerminalColorsBackdrop.

        .EXAMPLE
        Enable-TerminalColors -Tint 0.45 -TitleFormat '{icon} {name} ({folder})'

        .EXAMPLE
        Enable-TerminalColors -NoWindowBorder -NoAutoGitColors
        Uses only explicitly declared colours, and leaves the window border alone.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(0.0, 1.0)]
        [double] $Tint = 0.30,

        [switch] $PureColor,

        [string] $TitleFormat = '{icon} {name}',

        [switch] $NoTitle,
        [switch] $NoIcons,
        [switch] $NoWindowBorder,
        [switch] $CaptionColor,
        [switch] $NoAutoGitColors,

        [string] $BaseBackground,

        [switch] $ExplicitReset,
        [switch] $AlwaysReapply,

        [switch] $PassThru
    )

    if ($BaseBackground -and -not (ConvertFrom-TcColor -Value $BaseBackground)) {
        throw "TerminalColors: invalid reference background colour [$BaseBackground]."
    }

    $options = New-TcDefaultOptions
    $options.Tint = $Tint
    $options.PureColor = [bool]$PureColor
    if ($PureColor) { $options.Tint = 1.0 }
    $options.TitleFormat = $TitleFormat
    $options.SetTitle = -not $NoTitle
    $options.Icons = -not $NoIcons
    $options.WindowBorder = -not $NoWindowBorder
    $options.CaptionColor = [bool]$CaptionColor
    $options.AutoGitColors = -not $NoAutoGitColors
    $options.ExplicitReset = [bool]$ExplicitReset
    $options.AlwaysReapply = [bool]$AlwaysReapply
    if ($BaseBackground) { $options.BaseBackground = $BaseBackground }

    $script:TcOptions = $options
    $script:TcBaseBackgroundCache = $null

    if (-not $script:TcEnabled) {
        # Remember the existing prompt so it can be restored.
        $existing = Get-Command -Name prompt -CommandType Function -ErrorAction SilentlyContinue
        if ($existing) {
            $global:TerminalColorsOriginalPrompt = $existing.ScriptBlock
        } else {
            $global:TerminalColorsOriginalPrompt = $null
        }

        # The block is created outside the module so that it runs in the global
        # scope, exactly like the original prompt.
        $body = @'
    try { Update-TerminalColor } catch { }
    if ($global:TerminalColorsOriginalPrompt) {
        & $global:TerminalColorsOriginalPrompt
    } else {
        "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) "
    }
'@
        Set-Item -Path function:global:prompt -Value ([scriptblock]::Create($body)) -Force
        $script:TcEnabled = $true
    }

    if ($null -eq $script:TcOriginalTitle) { $script:TcOriginalTitle = Get-TcWindowTitle }

    Update-TerminalColor -Force

    if ($PassThru) { return [pscustomobject]$options }
}

function Disable-TerminalColors {
    <#
        .SYNOPSIS
        Disables automatic colouring and restores the original prompt.

        .PARAMETER KeepColor
        Keeps the colour currently applied instead of resetting the terminal
        appearance.

        .EXAMPLE
        Disable-TerminalColors
    #>
    [CmdletBinding()]
    param([switch] $KeepColor)

    if ($script:TcEnabled) {
        if ($global:TerminalColorsOriginalPrompt) {
            Set-Item -Path function:global:prompt -Value $global:TerminalColorsOriginalPrompt -Force
        } else {
            Remove-Item -Path function:global:prompt -Force -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name TerminalColorsOriginalPrompt -Scope Global -ErrorAction SilentlyContinue
        $script:TcEnabled = $false
    }

    if (-not $KeepColor) { Reset-TerminalColor }
}

function Test-TerminalColorsEnabled {
    <#
        .SYNOPSIS
        Indicates whether automatic colouring is active in this session.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]$script:TcEnabled
}
