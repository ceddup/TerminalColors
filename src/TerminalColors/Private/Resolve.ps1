# Resolution de la couleur associee a un dossier.
#
# On remonte l'arborescence depuis le dossier courant. Le premier dossier
# ancetre qui fournit une couleur gagne (semantique [le plus proche gagne],
# comme .editorconfig). Dans un meme dossier, l'ordre de priorite est :
#
#   1. .terminalcolors.json   (configuration propre a ce module)
#   2. .vscode/settings.json  (extension Peacock de VS Code)
#   3. .vs/**/color.txt       (extension Solution Colors de Visual Studio)
#   4. .git                   (couleur automatique deduite du nom du depot)

$script:TcConfigNames = @('.terminalcolors.json', 'terminalcolors.json', '.terminalcolors')
$script:TcResolveCache = @{}
$script:TcNegativeCacheSeconds = 5

function Clear-TcResolveCache {
    $script:TcResolveCache = @{}
}

function New-TcColorInfo {
    param(
        [hashtable] $Rgb,
        [string] $Name,
        [string] $Icon,
        $Tint,
        [string] $Source,
        [string] $SourcePath,
        [string] $Root
    )

    return [pscustomobject]@{
        Color      = ConvertTo-TcHex -Rgb $Rgb
        Rgb        = $Rgb
        Name       = $Name
        Icon       = $Icon
        Tint       = $Tint
        Source     = $Source
        SourcePath = $SourcePath
        Root       = $Root
    }
}

function Resolve-TcConfigFile {
    <#
        .SYNOPSIS
        Lit un fichier .terminalcolors.json. Gere [auto], les surcharges par
        branche et applyToSubfolders.
    #>
    [CmdletBinding()]
    param([string] $Directory, [string] $Path, [string] $LeafDirectory)

    $json = ConvertFrom-TcJsonFile -Path $Path
    if ($null -eq $json) {
        Write-Verbose "TerminalColors: [$Path] ignore (JSON invalide)."
        return $null
    }

    # Portee : par defaut la couleur s'applique aux sous-dossiers.
    $applyToSub = Get-TcJsonProperty -InputObject $json -Name 'applyToSubfolders'
    if ($applyToSub -is [bool] -and -not $applyToSub) {
        if ($LeafDirectory -ne $Directory) { return $null }
    }

    $colorText = Get-TcJsonProperty -InputObject $json -Name 'color'

    # Surcharge eventuelle par branche Git
    $branches = Get-TcJsonProperty -InputObject $json -Name 'branches'
    if ($branches) {
        $branch = Get-TcGitBranch -Path $Directory
        if (-not $branch) {
            $gitRoot = Get-TcGitRootFrom -Path $Directory
            if ($gitRoot) { $branch = Get-TcGitBranch -Path $gitRoot }
        }
        if ($branch) {
            foreach ($prop in $branches.PSObject.Properties) {
                if ($branch -like $prop.Name) { $colorText = $prop.Value; break }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$colorText)) { return $null }

    $name = [string](Get-TcJsonProperty -InputObject $json -Name 'name')
    if ([string]::IsNullOrWhiteSpace($name)) { $name = Split-Path $Directory -Leaf }

    if ([string]$colorText -eq 'auto') {
        $rgb = Get-TcAutoColor -Seed $name
    } else {
        $rgb = ConvertFrom-TcColor -Value ([string]$colorText)
    }
    if ($null -eq $rgb) {
        Write-Verbose "TerminalColors: couleur [$colorText] non reconnue dans [$Path]."
        return $null
    }

    $icon = Get-TcJsonProperty -InputObject $json -Name 'icon'
    $tintValue = Get-TcJsonProperty -InputObject $json -Name 'tint'
    $tint = $null
    if ($null -ne $tintValue) {
        try { $tint = [double]$tintValue } catch { $tint = $null }
    }

    return New-TcColorInfo -Rgb $rgb -Name $name -Icon ([string]$icon) -Tint $tint `
        -Source 'Config' -SourcePath $Path -Root $Directory
}

function Resolve-TcPeacock {
    <#
        .SYNOPSIS
        Lit la couleur de l'extension Peacock dans .vscode/settings.json.
    #>
    [CmdletBinding()]
    param([string] $Directory, [string] $Path)

    $json = ConvertFrom-TcJsonFile -Path $Path
    if ($null -eq $json) { return $null }

    $color = Get-TcJsonProperty -InputObject $json -Name 'peacock.color'

    if ([string]::IsNullOrWhiteSpace([string]$color)) {
        # Peacock n'ecrit peacock.color que depuis une version recente : on
        # retombe sur les personnalisations qu'il applique de toute facon.
        $custom = Get-TcJsonProperty -InputObject $json -Name 'workbench.colorCustomizations'
        foreach ($key in @('titleBar.activeBackground', 'activityBar.background', 'statusBar.background')) {
            $candidate = Get-TcJsonProperty -InputObject $custom -Name $key
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { $color = $candidate; break }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$color)) { return $null }

    $rgb = ConvertFrom-TcColor -Value ([string]$color)
    if ($null -eq $rgb) { return $null }

    return New-TcColorInfo -Rgb $rgb -Name (Split-Path $Directory -Leaf) -Icon '' -Tint $null `
        -Source 'Peacock' -SourcePath $Path -Root $Directory
}

function Resolve-TcSolutionColors {
    <#
        .SYNOPSIS
        Lit la couleur de l'extension Visual Studio [Solution Colors].
        Format du fichier .vs\<Solution>\color.txt : une ligne [branche:Couleur]
        par branche (l'ancien format ne contient que [Couleur]).
    #>
    [CmdletBinding()]
    param([string] $Directory, [string] $Path)

    try {
        $lines = [System.IO.File]::ReadAllLines($Path)
    } catch { return $null }

    $entries = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $segments = $line.Split(':')
        if ($segments.Count -eq 1) {
            $entries += [pscustomobject]@{ Branch = 'master'; Color = $segments[0].Trim() }
        } else {
            $entries += [pscustomobject]@{ Branch = $segments[0].Trim(); Color = $segments[1].Trim() }
        }
    }
    if ($entries.Count -eq 0) { return $null }

    $branch = Get-TcGitBranch -Path $Directory
    if (-not $branch) {
        $gitRoot = Get-TcGitRootFrom -Path $Directory
        if ($gitRoot) { $branch = Get-TcGitBranch -Path $gitRoot }
    }

    $chosen = $null
    if ($branch) { $chosen = $entries | Where-Object { $_.Branch -eq $branch } | Select-Object -First 1 }
    if (-not $chosen) { $chosen = $entries | Where-Object { $_.Branch -eq 'master' } | Select-Object -First 1 }
    if (-not $chosen) { $chosen = $entries[0] }

    $rgb = ConvertFrom-TcColor -Value $chosen.Color
    if ($null -eq $rgb) { return $null }   # couvre aussi [None]

    # Le nom du dossier .vs\<Solution> est plus parlant que celui du repertoire.
    $solutionName = Split-Path (Split-Path $Path -Parent) -Leaf
    if ($solutionName -eq '.vs') { $solutionName = Split-Path $Directory -Leaf }

    return New-TcColorInfo -Rgb $rgb -Name $solutionName -Icon '' -Tint $null `
        -Source 'SolutionColors' -SourcePath $Path -Root $Directory
}

function Get-TcSolutionColorFile {
    [CmdletBinding()]
    param([string] $Directory)

    $vs = Join-Path $Directory '.vs'
    if (-not [System.IO.Directory]::Exists($vs)) { return $null }

    $direct = Join-Path $vs 'color.txt'
    if ([System.IO.File]::Exists($direct)) { return $direct }

    try {
        $found = [System.IO.Directory]::GetFiles($vs, 'color.txt', [System.IO.SearchOption]::AllDirectories)
    } catch { return $null }

    # @() est indispensable : sans lui, un pipeline a un seul element renvoie une
    # chaine, et [0] en extrairait le premier caractere.
    $sorted = @($found | Sort-Object)
    if ($sorted.Count -gt 0) { return $sorted[0] }
    return $null
}

function Get-TcGitRootFrom {
    [CmdletBinding()]
    param([string] $Path)

    $current = $Path
    while ($current) {
        if (Test-TcGitRoot -Path $current) { return $current }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Resolve-TcDirectory {
    <#
        .SYNOPSIS
        Cherche une couleur declaree dans un dossier precis (sans remonter).
    #>
    [CmdletBinding()]
    param(
        [string] $Directory,
        [string] $LeafDirectory,
        [bool] $AutoGitColors
    )

    foreach ($name in $script:TcConfigNames) {
        $path = Join-Path $Directory $name
        if ([System.IO.File]::Exists($path)) {
            $info = Resolve-TcConfigFile -Directory $Directory -Path $path -LeafDirectory $LeafDirectory
            if ($info) { return $info }
        }
    }

    $vscode = Join-Path (Join-Path $Directory '.vscode') 'settings.json'
    if ([System.IO.File]::Exists($vscode)) {
        $info = Resolve-TcPeacock -Directory $Directory -Path $vscode
        if ($info) { return $info }
    }

    $colorFile = Get-TcSolutionColorFile -Directory $Directory
    if ($colorFile) {
        $info = Resolve-TcSolutionColors -Directory $Directory -Path $colorFile
        if ($info) { return $info }
    }

    if ($AutoGitColors -and (Test-TcGitRoot -Path $Directory)) {
        $name = Split-Path $Directory -Leaf
        $rgb = Get-TcAutoColor -Seed $name
        return New-TcColorInfo -Rgb $rgb -Name $name -Icon '' -Tint $null `
            -Source 'GitRepository' -SourcePath (Join-Path $Directory '.git') -Root $Directory
    }

    return $null
}

function Resolve-TcColor {
    <#
        .SYNOPSIS
        Resout la couleur applicable a un chemin en remontant l'arborescence.
        Renvoie $null si aucun ancetre ne definit de couleur.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [bool] $AutoGitColors = $true,
        [switch] $NoCache
    )

    $leaf = $Path.TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $null }

    $cacheKey = "$($leaf.ToLowerInvariant())|$AutoGitColors"

    if (-not $NoCache -and $script:TcResolveCache.ContainsKey($cacheKey)) {
        $entry = $script:TcResolveCache[$cacheKey]
        if ($null -eq $entry.Info) {
            # Resultat negatif : courte duree de vie, pour voir rapidement un
            # fichier de configuration qui vient d'etre cree.
            if (((Get-Date) - $entry.Stamp).TotalSeconds -lt $script:TcNegativeCacheSeconds) { return $null }
        } else {
            $stamp = Get-TcFileStamp -Path $entry.Info.SourcePath
            if ($stamp -eq $entry.Stamp) { return $entry.Info }
        }
    }

    $info = $null
    $current = $leaf
    while ($current) {
        $info = Resolve-TcDirectory -Directory $current -LeafDirectory $leaf -AutoGitColors $AutoGitColors
        if ($info) { break }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }

    if ($info) {
        $script:TcResolveCache[$cacheKey] = @{ Info = $info; Stamp = (Get-TcFileStamp -Path $info.SourcePath) }
    } else {
        $script:TcResolveCache[$cacheKey] = @{ Info = $null; Stamp = (Get-Date) }
    }

    return $info
}

function Get-TcFileStamp {
    param([string] $Path)
    try {
        if ([System.IO.File]::Exists($Path)) {
            return [System.IO.File]::GetLastWriteTimeUtc($Path).Ticks
        }
        if ([System.IO.Directory]::Exists($Path)) {
            return [System.IO.Directory]::GetLastWriteTimeUtc($Path).Ticks
        }
    } catch { }
    return 0
}
