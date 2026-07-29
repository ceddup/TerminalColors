function Get-TerminalColor {
    <#
        .SYNOPSIS
        Reports which colour applies to a folder, and where it comes from.

        .DESCRIPTION
        A diagnostics command: it shows the file that was picked
        (.terminalcolors.json, Peacock, Solution Colors or Git repository), the
        colour, and the tinted background that would actually be applied to the
        terminal.

        .PARAMETER Path
        Folder to evaluate. Accepts pipeline input, which lets you map the colours
        of all your repositories at once.

        .PARAMETER NoAutoGitColors
        Ignores the automatic colour derived from a Git repository name.

        .EXAMPLE
        Get-TerminalColor

        .EXAMPLE
        Get-ChildItem C:\Repos -Directory | Get-TerminalColor | Format-Table Name, Color, Source
        Shows the colour assigned to each of your repositories.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string[]] $Path,

        [switch] $NoAutoGitColors
    )

    begin {
        $options = Get-TcOptions
        $autoGit = [bool]$options.AutoGitColors
        if ($NoAutoGitColors) { $autoGit = $false }
    }

    process {
        $targets = $Path
        if (-not $targets) { $targets = @(Get-TcCurrentPath) }

        foreach ($item in $targets) {
            if ([string]::IsNullOrWhiteSpace($item)) { continue }

            try { $resolved = (Resolve-Path -LiteralPath $item -ErrorAction Stop).ProviderPath } catch { $resolved = $item }

            $info = Resolve-TcColor -Path $resolved -AutoGitColors $autoGit -NoCache

            if ($null -eq $info) {
                [pscustomobject]@{
                    Path           = $resolved
                    Name           = Split-Path $resolved -Leaf
                    Color          = $null
                    Icon           = $null
                    Source         = 'None'
                    SourcePath     = $null
                    Root           = $null
                    TintedFallback = $null
                    Tint           = $null
                }
                continue
            }

            $icon = [string]$info.Icon
            if ([string]::IsNullOrEmpty($icon) -and $options.Icons) { $icon = Get-TcColorEmoji -Rgb $info.Rgb }

            $tint = $options.Tint
            if ($null -ne $info.Tint) { $tint = [double]$info.Tint }
            $tinted = Get-TcBlendedColor -Base (Get-TcBaseBackground) -Color $info.Rgb -Amount $tint

            [pscustomobject]@{
                Path           = $resolved
                Name           = $info.Name
                Color          = $info.Color
                Icon           = $icon
                Source         = $info.Source
                SourcePath     = $info.SourcePath
                Root           = $info.Root
                TintedFallback = ConvertTo-TcHex -Rgb $tinted
                Tint           = $tint
            }
        }
    }
}

function Clear-TerminalColorCache {
    <#
        .SYNOPSIS
        Empties the colour resolution cache and re-reads the Windows Terminal
        settings.

        .DESCRIPTION
        Useful after editing a configuration file by hand, or the colour scheme of
        your Windows Terminal profile.

        .EXAMPLE
        Clear-TerminalColorCache; Update-TerminalColor -Force
    #>
    [CmdletBinding()]
    param()

    Clear-TcResolveCache
    $script:TcBaseBackgroundCache = $null
    $script:TcLastPath = $null
    $script:TcLastKey = $null
}
