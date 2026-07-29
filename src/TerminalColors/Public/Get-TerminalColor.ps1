function Get-TerminalColor {
    <#
        .SYNOPSIS
        Indique quelle couleur s'applique a un dossier, et d'ou elle vient.

        .DESCRIPTION
        Sert de commande de diagnostic : elle montre le fichier retenu
        (.terminalcolors.json, Peacock, Solution Colors ou depot Git), la
        couleur, et le fond teinte qui serait reellement applique au terminal.

        .PARAMETER Path
        Dossier a evaluer. Accepte l'entree de pipeline, ce qui permet de
        dresser la carte des couleurs de tous vos depots.

        .PARAMETER NoAutoGitColors
        Ignore la couleur automatique deduite du nom du depot Git.

        .EXAMPLE
        Get-TerminalColor

        .EXAMPLE
        Get-ChildItem C:\Repos -Directory | Get-TerminalColor | Format-Table Name, Color, Source
        Affiche la couleur attribuee a chacun de vos depots.
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
        Vide le cache de resolution des couleurs et relit les reglages de
        Windows Terminal.

        .DESCRIPTION
        Utile apres avoir modifie a la main un fichier de configuration ou la
        palette de votre profil Windows Terminal.

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
