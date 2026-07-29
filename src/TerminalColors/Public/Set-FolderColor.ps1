function Set-FolderColor {
    <#
        .SYNOPSIS
        Associe une couleur a un dossier en y ecrivant un fichier
        .terminalcolors.json.

        .DESCRIPTION
        La couleur s'applique au dossier et, par defaut, a tous ses
        sous-dossiers. Le fichier est volontairement lisible et versionnable :
        commitez-le pour que toute l'equipe partage la meme couleur de projet.

        .PARAMETER Color
        Couleur au format hexadecimal (#215732), nom de couleur connu (Teal,
        SteelBlue...) ou [auto] pour deriver une couleur stable du nom du
        projet.

        .PARAMETER Path
        Dossier a colorer. Par defaut, le dossier courant.

        .PARAMETER Name
        Libelle affiche dans l'onglet. Par defaut, le nom du dossier.

        .PARAMETER Icon
        Symbole affiche devant le libelle. Par defaut, un carre colore deduit de
        la couleur.

        .PARAMETER Tint
        Intensite de la teinte propre a ce projet, de 0 a 1. Surcharge le
        reglage global.

        .PARAMETER Branches
        Table de correspondance branche Git -> couleur. Les jokers sont
        acceptes. Exemple : @{ 'main' = '#215732'; 'release/*' = '#B71C1C' }

        .PARAMETER NoSubfolders
        Limite la couleur au seul dossier indique.

        .PARAMETER Force
        Ecrase un fichier de configuration existant.

        .EXAMPLE
        Set-FolderColor '#215732'

        .EXAMPLE
        Set-FolderColor auto -Path C:\Repos\pastel

        .EXAMPLE
        Set-FolderColor Teal -Name 'Superviseur' -Branches @{ 'main' = 'Teal'; 'hotfix/*' = 'OrangeRed' }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Color,

        [Parameter(Position = 1)]
        [string] $Path = '.',

        [string] $Name,
        [string] $Icon,

        [ValidateRange(0.0, 1.0)]
        [double] $Tint = -1,

        [hashtable] $Branches,

        [switch] $NoSubfolders,
        [switch] $Force,
        [switch] $PassThru
    )

    try {
        $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        throw "TerminalColors : dossier introuvable [$Path]."
    }
    if (-not [System.IO.Directory]::Exists($directory)) {
        throw "TerminalColors : [$directory] n'est pas un dossier."
    }

    if ($Color -ne 'auto' -and -not (ConvertFrom-TcColor -Value $Color)) {
        throw "TerminalColors : couleur non reconnue [$Color]. Utilisez un code hexadecimal (#RRGGBB), un nom de couleur connu, ou [auto]."
    }

    if ($Branches) {
        foreach ($key in $Branches.Keys) {
            $value = [string]$Branches[$key]
            if ($value -ne 'auto' -and -not (ConvertFrom-TcColor -Value $value)) {
                throw "TerminalColors : couleur non reconnue [$value] pour la branche [$key]."
            }
        }
    }

    $target = Join-Path $directory '.terminalcolors.json'
    if ([System.IO.File]::Exists($target) -and -not $Force) {
        throw "TerminalColors : [$target] existe deja. Utilisez -Force pour l'ecraser."
    }

    $config = [ordered]@{ color = $Color }
    if ($Name) { $config.name = $Name } else { $config.name = Split-Path $directory -Leaf }
    if ($Icon) { $config.icon = $Icon }
    if ($Tint -ge 0) { $config.tint = $Tint }
    if ($Branches) {
        $ordered = [ordered]@{}
        foreach ($key in ($Branches.Keys | Sort-Object)) { $ordered[$key] = [string]$Branches[$key] }
        $config.branches = $ordered
    }
    if ($NoSubfolders) { $config.applyToSubfolders = $false }

    $json = ([pscustomobject]$config | ConvertTo-Json -Depth 10)

    if ($PSCmdlet.ShouldProcess($target, 'Ecrire la configuration de couleur')) {
        # UTF-8 sans BOM : lisible par tous les outils, diff propre dans Git.
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($target, $json + [Environment]::NewLine, $encoding)

        Clear-TcResolveCache
        $script:TcLastPath = $null
        $script:TcLastKey = $null

        $current = Get-TcCurrentPath
        if ($current -and ($current -eq $directory -or $current.StartsWith($directory + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
            Update-TerminalColor -Force
        }
    }

    if ($PassThru) { return Get-TerminalColor -Path $directory }
}

function Remove-FolderColor {
    <#
        .SYNOPSIS
        Supprime le fichier .terminalcolors.json d'un dossier.

        .PARAMETER Path
        Dossier concerne. Par defaut, le dossier courant.

        .EXAMPLE
        Remove-FolderColor
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [string] $Path = '.'
    )

    try {
        $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        throw "TerminalColors : dossier introuvable [$Path]."
    }

    $removed = $false
    foreach ($name in @('.terminalcolors.json', 'terminalcolors.json', '.terminalcolors')) {
        $candidate = Join-Path $directory $name
        if ([System.IO.File]::Exists($candidate)) {
            if ($PSCmdlet.ShouldProcess($candidate, 'Supprimer')) {
                Remove-Item -LiteralPath $candidate -Force
                $removed = $true
            }
        }
    }

    if (-not $removed) {
        Write-Warning "TerminalColors : aucune configuration de couleur dans [$directory]."
        return
    }

    Clear-TerminalColorCache
    Update-TerminalColor -Force
}
