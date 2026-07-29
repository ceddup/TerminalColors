<#
    .SYNOPSIS
    Tests de TerminalColors, sans aucune dependance externe.

    .DESCRIPTION
    Volontairement autonome : ni Pester ni module a installer, pour que
    n'importe qui puisse verifier le comportement immediatement, sur Windows
    PowerShell 5.1 comme sur PowerShell 7.

        .\tests\Invoke-Tests.ps1

    Code de sortie 0 si tout passe, 1 sinon.
#>
[CmdletBinding()]
param([switch] $Detailed)

$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0
$script:Failures = New-Object System.Collections.ArrayList
$script:Section = ''

function Write-Section {
    param([string] $Name)
    $script:Section = $Name
    Write-Host ''
    Write-Host "  $Name" -ForegroundColor Cyan
}

function Test-It {
    param([string] $Name, [scriptblock] $Body)

    try {
        & $Body
        $script:Passed++
        if ($Detailed) { Write-Host "    [ok] $Name" -ForegroundColor DarkGreen }
    } catch {
        $script:Failed++
        [void]$script:Failures.Add("$($script:Section) / $Name : $($_.Exception.Message)")
        Write-Host "    [KO] $Name" -ForegroundColor Red
        Write-Host "         $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Because)
    if ($Expected -ne $Actual) { throw "attendu [$Expected], obtenu [$Actual]. $Because" }
}

function Assert-True {
    param($Condition, [string] $Because)
    if (-not $Condition) { throw "condition fausse. $Because" }
}

function Assert-Null {
    param($Value, [string] $Because)
    if ($null -ne $Value) { throw "attendu null, obtenu [$Value]. $Because" }
}

function Assert-NotNull {
    param($Value, [string] $Because)
    if ($null -eq $Value) { throw "attendu non-null. $Because" }
}

# --- Chargement du module ----------------------------------------------------
$repoRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $repoRoot 'src\TerminalColors\TerminalColors.psd1'

Remove-Module TerminalColors -Force -ErrorAction SilentlyContinue
Import-Module $modulePath -Force -ErrorAction Stop
$m = Get-Module TerminalColors

# Raccourcis vers les fonctions internes du module
function Get-ParsedJson { param([string] $Text) & $m { param($t) ConvertFrom-TcJsonText -Text $t } $Text }
function Get-HexOf { param([string] $Value) & $m { param($v) ConvertTo-TcHex -Rgb (ConvertFrom-TcColor -Value $v) } $Value }
function Get-RgbOf { param([string] $Value) & $m { param($v) ConvertFrom-TcColor -Value $v } $Value }
function Get-AutoHexOf { param([string] $Seed) & $m { param($s) ConvertTo-TcHex -Rgb (Get-TcAutoColor -Seed $s) } $Seed }
function Get-EmojiOf { param([string] $Value) & $m { param($v) Get-TcColorEmoji -Rgb (ConvertFrom-TcColor -Value $v) } $Value }
function Get-BlendHex {
    param($Base, $Color, [double] $Amount)
    & $m { param($b, $c, $a) ConvertTo-TcHex -Rgb (Get-TcBlendedColor -Base $b -Color $c -Amount $a) } $Base $Color $Amount
}
function Get-ResolvedColor {
    param([string] $Path, [bool] $AutoGit = $true, [switch] $UseCache)
    if ($UseCache) {
        return & $m { param($p, $a) Resolve-TcColor -Path $p -AutoGitColors $a } $Path $AutoGit
    }
    return & $m { param($p, $a) Resolve-TcColor -Path $p -AutoGitColors $a -NoCache } $Path $AutoGit
}

Write-Host ''
Write-Host '  Tests TerminalColors' -ForegroundColor White
Write-Host '  ====================' -ForegroundColor DarkGray

# Bac a sable pour les fixtures
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ('tc-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

function New-Fixture {
    param([string] $RelativePath, [string] $Content)
    $full = Join-Path $sandbox $RelativePath
    $dir = Split-Path $full -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($full, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $full
}

function New-FixtureDir {
    param([string] $RelativePath)
    $full = Join-Path $sandbox $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { New-Item -ItemType Directory -Path $full -Force | Out-Null }
    return $full
}

# Le module range son etat d'installation et les images du calque opaque dans
# %LOCALAPPDATA%\TerminalColors, et la desinstallation du calque y supprime des
# fichiers : on redirige ce dossier vers le bac a sable pour que les tests ne
# touchent jamais aux donnees reelles de l'utilisateur.
& $m { param($d) $script:TcDataDirectory = $d } (Join-Path $sandbox 'donnees')

function Get-SourceFile {
    param([string[]] $Extension = @('*.ps1', '*.psm1', '*.psd1'))
    $files = New-Object System.Collections.ArrayList
    foreach ($ext in $Extension) {
        foreach ($f in @(Get-ChildItem -Path (Join-Path $repoRoot 'src') -Recurse -Filter $ext -File -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
        foreach ($f in @(Get-ChildItem -Path $repoRoot -Filter $ext -File -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
        foreach ($f in @(Get-ChildItem -Path (Join-Path $repoRoot 'tests') -Filter $ext -File -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
    }
    return $files
}

try {

    # ======================================================================
    Write-Section 'Analyse des couleurs'

    Test-It 'hexadecimal a 6 chiffres' {
        $r = Get-RgbOf '#21A5F3'
        Assert-Equal 0x21 $r.R; Assert-Equal 0xA5 $r.G; Assert-Equal 0xF3 $r.B
    }

    Test-It 'hexadecimal sans diese' {
        Assert-Equal '#215732' (Get-HexOf '215732')
    }

    Test-It 'hexadecimal court #rgb' {
        Assert-Equal '#FF00AA' (Get-HexOf '#f0a')
    }

    Test-It 'canal alpha ignore' {
        Assert-Equal '#215732' (Get-HexOf '#21573280')
    }

    Test-It 'nom de couleur usuel' {
        Assert-Equal '#008080' (Get-HexOf 'Teal')
    }

    Test-It 'nom de couleur insensible a la casse' {
        Assert-Equal '#008080' (Get-HexOf 'tEaL')
    }

    Test-It 'alias Solution Colors (Burgundy = Tomato)' {
        Assert-Equal '#FF6347' (Get-HexOf 'Burgundy')
    }

    Test-It 'alias Solution Colors (Volt = YellowGreen)' {
        Assert-Equal '#9ACD32' (Get-HexOf 'Volt')
    }

    Test-It 'nom .NET connu absent de la table interne' {
        Assert-Equal '#66CDAA' (Get-HexOf 'MediumAquamarine')
    }

    Test-It 'None ne donne aucune couleur' {
        Assert-Null (Get-RgbOf 'None')
    }

    Test-It 'valeur invalide rejetee' {
        Assert-Null (Get-RgbOf 'pas-une-couleur')
    }

    Test-It 'chaine vide rejetee' {
        Assert-Null (Get-RgbOf '   ')
    }

    Test-It 'conversion vers hexadecimal' {
        $r = & $m { ConvertTo-TcHex -Rgb @{ R = 1; G = 22; B = 255 } }
        Assert-Equal '#0116FF' $r
    }

    # ======================================================================
    Write-Section 'Melange et couleurs derivees'

    Test-It 'melange a 0 renvoie la base' {
        Assert-Equal '#0C0C0C' (Get-BlendHex @{R=12;G=12;B=12} @{R=255;G=0;B=0} 0)
    }

    Test-It 'melange a 1 renvoie la couleur' {
        Assert-Equal '#FF0000' (Get-BlendHex @{R=12;G=12;B=12} @{R=255;G=0;B=0} 1)
    }

    Test-It 'melange a 0,5 est a mi-chemin' {
        Assert-Equal '#808080' (Get-BlendHex @{R=0;G=0;B=0} @{R=255;G=255;B=255} 0.5)
    }

    Test-It 'melange borne les valeurs hors intervalle' {
        Assert-Equal '#FFFFFF' (Get-BlendHex @{R=0;G=0;B=0} @{R=255;G=255;B=255} 5)
        Assert-Equal '#000000' (Get-BlendHex @{R=0;G=0;B=0} @{R=255;G=255;B=255} -3)
    }

    Test-It 'le melange par defaut reste sombre donc lisible' {
        # Teinte de 0,30 sur un fond Campbell : la luminosite doit rester basse.
        $hex = Get-BlendHex @{R=12;G=12;B=12} (Get-RgbOf '#61DAFB') 0.30
        $rgb = Get-RgbOf $hex
        $luma = (0.2126 * $rgb.R + 0.7152 * $rgb.G + 0.0722 * $rgb.B) / 255
        Assert-True ($luma -lt 0.45) "luminosite trop elevee ($([Math]::Round($luma, 3))) pour $hex"
    }

    Test-It 'couleur automatique deterministe' {
        Assert-Equal (Get-AutoHexOf 'oseille') (Get-AutoHexOf 'oseille')
    }

    Test-It 'couleur automatique insensible a la casse' {
        Assert-Equal (Get-AutoHexOf 'Oseille') (Get-AutoHexOf 'oseille')
    }

    Test-It 'couleurs automatiques distinctes pour des noms distincts' {
        $colors = foreach ($n in @('oseille', 'pastel', 'superviseur', 'ioda_v3', 'rag-megane', 'sgi', 'TerminalColors')) {
            Get-AutoHexOf $n
        }
        $unique = @($colors | Select-Object -Unique)
        Assert-True ($unique.Count -ge 6) "au moins 6 couleurs distinctes sur 7, obtenu $($unique.Count) : $($colors -join ' ')"
    }

    Test-It 'couleur automatique au format attendu' {
        Assert-True ((Get-AutoHexOf 'quelque-chose') -match '^#[0-9A-F]{6}$')
    }

    Test-It 'couleur automatique ni trop sombre ni trop claire' {
        foreach ($n in @('a', 'depot-test', 'zzz-projet', 'Superviseur_C2')) {
            $rgb = Get-RgbOf (Get-AutoHexOf $n)
            $luma = (0.2126 * $rgb.R + 0.7152 * $rgb.G + 0.0722 * $rgb.B) / 255
            Assert-True ($luma -gt 0.08 -and $luma -lt 0.85) "luminosite hors bornes pour $n : $([Math]::Round($luma, 3))"
        }
    }

    Test-It 'emoji rouge pour une couleur rouge' {
        Assert-Equal ([char]::ConvertFromUtf32(0x1F7E5)) (Get-EmojiOf '#E00000')
    }

    Test-It 'emoji vert pour une couleur verte' {
        Assert-Equal ([char]::ConvertFromUtf32(0x1F7E9)) (Get-EmojiOf '#215732')
    }

    Test-It 'emoji bleu pour une couleur bleue' {
        Assert-Equal ([char]::ConvertFromUtf32(0x1F7E6)) (Get-EmojiOf '#61DAFB')
    }

    Test-It 'emoji noir pour une couleur desaturee sombre' {
        Assert-Equal ([char]::ConvertFromUtf32(0x2B1B)) (Get-EmojiOf '#303030')
    }

    Test-It 'emoji blanc pour une couleur desaturee claire' {
        Assert-Equal ([char]::ConvertFromUtf32(0x2B1C)) (Get-EmojiOf '#EEEEEE')
    }

    Test-It 'aller-retour RVB / TSL' {
        $r = & $m {
            param($hex)
            $hsl = ConvertTo-TcHsl -Rgb (ConvertFrom-TcColor -Value $hex)
            ConvertTo-TcHex -Rgb (ConvertFrom-TcHsl -Hue $hsl.H -Saturation $hsl.S -Lightness $hsl.L)
        } '#4682B4'
        Assert-Equal '#4682B4' $r
    }

    # ======================================================================
    Write-Section 'JSON tolerant'

    Test-It 'commentaires de fin de ligne retires' {
        Assert-Equal 1 (Get-ParsedJson "{ `"a`": 1 // commentaire`n }").a
    }

    Test-It 'commentaires de bloc retires' {
        Assert-Equal 2 (Get-ParsedJson '{ /* bloc */ "a": 2 }').a
    }

    Test-It 'virgule finale toleree' {
        Assert-Equal 3 (Get-ParsedJson '{ "a": 3, }').a
    }

    Test-It 'les slashs dans une chaine ne sont pas pris pour des commentaires' {
        Assert-Equal 'http://exemple.fr // pas un commentaire' (Get-ParsedJson '{ "a": "http://exemple.fr // pas un commentaire" }').a
    }

    Test-It 'les guillemets echappes ne cassent pas l''analyse' {
        Assert-Equal 'guillemet " puis // rien' (Get-ParsedJson '{ "a": "guillemet \" puis // rien" }').a
    }

    Test-It 'le retrait des commentaires preserve la longueur' {
        $r = & $m {
            $text = "{ `"a`": 1, // xyz`n  `"b`": 2 }"
            @{ Original = $text.Length; Clean = (Remove-TcJsonComments -Text $text).Length }
        }
        Assert-Equal $r.Original $r.Clean
    }

    Test-It 'JSON invalide renvoie null sans exception' {
        Assert-Null (Get-ParsedJson '{ ceci nest pas du json')
    }

    Test-It 'propriete a nom pointe' {
        $r = & $m { param($t) Get-TcJsonProperty -InputObject (ConvertFrom-TcJsonText -Text $t) -Name 'peacock.color' } '{ "peacock.color": "#215732" }'
        Assert-Equal '#215732' $r
    }

    Test-It 'propriete absente renvoie null' {
        $r = & $m { param($t) Get-TcJsonProperty -InputObject (ConvertFrom-TcJsonText -Text $t) -Name 'absente' } '{ "a": 1 }'
        Assert-Null $r
    }

    # ======================================================================
    Write-Section 'Detection Git'

    $gitRepo = New-FixtureDir 'git\monrepo'
    New-Fixture 'git\monrepo\.git\HEAD' "ref: refs/heads/feature/ma-branche`n" | Out-Null
    New-FixtureDir 'git\monrepo\src\lib' | Out-Null

    Test-It 'racine de depot detectee' {
        Assert-True (& $m { param($p) Test-TcGitRoot -Path $p } $gitRepo)
    }

    Test-It 'un sous-dossier n''est pas une racine' {
        Assert-True (-not (& $m { param($p) Test-TcGitRoot -Path $p } (Join-Path $gitRepo 'src')))
    }

    Test-It 'branche lue dans HEAD' {
        Assert-Equal 'feature/ma-branche' (& $m { param($p) Get-TcGitBranch -Path $p } $gitRepo)
    }

    Test-It 'racine trouvee depuis un sous-dossier profond' {
        Assert-Equal $gitRepo (& $m { param($p) Get-TcGitRootFrom -Path $p } (Join-Path $gitRepo 'src\lib'))
    }

    Test-It 'worktree Git (fichier .git) reconnu' {
        $worktree = New-FixtureDir 'git\worktree'
        New-Fixture 'git\wtdata\HEAD' "ref: refs/heads/wt-branche`n" | Out-Null
        New-Fixture 'git\worktree\.git' ('gitdir: ' + (Join-Path $sandbox 'git\wtdata')) | Out-Null
        Assert-Equal 'wt-branche' (& $m { param($p) Get-TcGitBranch -Path $p } $worktree)
    }

    Test-It 'HEAD detachee renvoie null' {
        $p = New-FixtureDir 'git\detache'
        New-Fixture 'git\detache\.git\HEAD' "a1b2c3d4e5f6`n" | Out-Null
        Assert-Null (& $m { param($x) Get-TcGitBranch -Path $x } $p)
    }

    # ======================================================================
    Write-Section 'Resolution des couleurs'

    $projConfig = New-FixtureDir 'resolve\avec-config'
    New-Fixture 'resolve\avec-config\.terminalcolors.json' '{ "color": "#215732", "name": "Oseille" }' | Out-Null
    New-FixtureDir 'resolve\avec-config\src\deep\deeper' | Out-Null

    Test-It 'configuration lue dans le dossier meme' {
        $r = Get-ResolvedColor $projConfig
        Assert-Equal '#215732' $r.Color
        Assert-Equal 'Oseille' $r.Name
        Assert-Equal 'Config' $r.Source
    }

    Test-It 'configuration heritee par les sous-dossiers' {
        $r = Get-ResolvedColor (Join-Path $projConfig 'src\deep\deeper')
        Assert-Equal '#215732' $r.Color
        Assert-Equal $projConfig $r.Root
    }

    Test-It 'nom par defaut = nom du dossier' {
        $p = New-FixtureDir 'resolve\sans-nom'
        New-Fixture 'resolve\sans-nom\.terminalcolors.json' '{ "color": "Teal" }' | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal 'sans-nom' $r.Name
        Assert-Equal '#008080' $r.Color
    }

    Test-It 'applyToSubfolders false limite au dossier' {
        $p = New-FixtureDir 'resolve\strict'
        New-Fixture 'resolve\strict\.terminalcolors.json' '{ "color": "#112233", "applyToSubfolders": false }' | Out-Null
        New-FixtureDir 'resolve\strict\enfant' | Out-Null

        Assert-Equal '#112233' (Get-ResolvedColor $p).Color
        Assert-Null (Get-ResolvedColor (Join-Path $p 'enfant') $false)
    }

    Test-It 'couleur auto dans la configuration' {
        $p = New-FixtureDir 'resolve\auto'
        New-Fixture 'resolve\auto\.terminalcolors.json' '{ "color": "auto", "name": "oseille" }' | Out-Null
        Assert-Equal (Get-AutoHexOf 'oseille') (Get-ResolvedColor $p).Color
    }

    Test-It 'teinte propre au projet' {
        $p = New-FixtureDir 'resolve\teinte'
        New-Fixture 'resolve\teinte\.terminalcolors.json' '{ "color": "#445566", "tint": 0.8 }' | Out-Null
        Assert-Equal 0.8 (Get-ResolvedColor $p).Tint
    }

    Test-It 'icone personnalisee' {
        $p = New-FixtureDir 'resolve\icone'
        New-Fixture 'resolve\icone\.terminalcolors.json' '{ "color": "#445566", "icon": "ZZ" }' | Out-Null
        Assert-Equal 'ZZ' (Get-ResolvedColor $p).Icon
    }

    Test-It 'couleur par branche Git' {
        $p = New-FixtureDir 'resolve\branches'
        New-Fixture 'resolve\branches\.git\HEAD' "ref: refs/heads/release/2026.1`n" | Out-Null
        New-Fixture 'resolve\branches\.terminalcolors.json' '{ "color": "#215732", "branches": { "release/*": "#B71C1C" } }' | Out-Null
        Assert-Equal '#B71C1C' (Get-ResolvedColor $p).Color
    }

    Test-It 'couleur par branche heritee dans un sous-dossier' {
        $p = Join-Path $sandbox 'resolve\branches'
        New-FixtureDir 'resolve\branches\src' | Out-Null
        Assert-Equal '#B71C1C' (Get-ResolvedColor (Join-Path $p 'src')).Color
    }

    Test-It 'branche sans correspondance garde la couleur par defaut' {
        $p = New-FixtureDir 'resolve\branches2'
        New-Fixture 'resolve\branches2\.git\HEAD' "ref: refs/heads/main`n" | Out-Null
        New-Fixture 'resolve\branches2\.terminalcolors.json' '{ "color": "#215732", "branches": { "release/*": "#B71C1C" } }' | Out-Null
        Assert-Equal '#215732' (Get-ResolvedColor $p).Color
    }

    Test-It 'configuration illisible ignoree sans erreur' {
        $p = New-FixtureDir 'resolve\casse'
        New-Fixture 'resolve\casse\.terminalcolors.json' '{ ceci nest pas du json' | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'couleur inconnue dans la configuration ignoree' {
        $p = New-FixtureDir 'resolve\couleur-inconnue'
        New-Fixture 'resolve\couleur-inconnue\.terminalcolors.json' '{ "color": "mauve-passe" }' | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'couleur Peacock lue dans .vscode/settings.json' {
        $p = New-FixtureDir 'resolve\peacock'
        New-Fixture 'resolve\peacock\.vscode\settings.json' @'
{
    // configuration ecrite par Peacock
    "workbench.colorCustomizations": {
        "titleBar.activeBackground": "#215732",
    },
    "peacock.color": "#61dafb"
}
'@ | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#61DAFB' $r.Color
        Assert-Equal 'Peacock' $r.Source
    }

    Test-It 'repli sur titleBar.activeBackground sans peacock.color' {
        $p = New-FixtureDir 'resolve\peacock-ancien'
        New-Fixture 'resolve\peacock-ancien\.vscode\settings.json' '{ "workbench.colorCustomizations": { "titleBar.activeBackground": "#215732" } }' | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#215732' $r.Color
        Assert-Equal 'Peacock' $r.Source
    }

    Test-It 'settings.json VS Code sans couleur ignore' {
        $p = New-FixtureDir 'resolve\vscode-neutre'
        New-Fixture 'resolve\vscode-neutre\.vscode\settings.json' '{ "editor.tabSize": 4 }' | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'couleur Solution Colors lue dans .vs' {
        $p = New-FixtureDir 'resolve\solution'
        New-Fixture 'resolve\solution\.vs\MaSolution\color.txt' "master:Teal`n" | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#008080' $r.Color
        Assert-Equal 'SolutionColors' $r.Source
        Assert-Equal 'MaSolution' $r.Name
    }

    Test-It 'Solution Colors : ancien format sans branche' {
        $p = New-FixtureDir 'resolve\solution-ancien'
        New-Fixture 'resolve\solution-ancien\.vs\Sol\color.txt' "Cyan`n" | Out-Null
        Assert-Equal '#00FFFF' (Get-ResolvedColor $p).Color
    }

    Test-It 'Solution Colors : la branche courante gagne' {
        $p = New-FixtureDir 'resolve\solution-branche'
        New-Fixture 'resolve\solution-branche\.git\HEAD' "ref: refs/heads/dev`n" | Out-Null
        New-Fixture 'resolve\solution-branche\.vs\Sol\color.txt' "master:Teal`ndev:Pumpkin`n" | Out-Null
        Assert-Equal '#FF4500' (Get-ResolvedColor $p).Color
    }

    Test-It 'Solution Colors : None ignore' {
        $p = New-FixtureDir 'resolve\solution-none'
        New-Fixture 'resolve\solution-none\.vs\Sol\color.txt' "master:None`n" | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'la configuration propre prime sur Peacock' {
        $p = New-FixtureDir 'resolve\priorite'
        New-Fixture 'resolve\priorite\.terminalcolors.json' '{ "color": "#111111" }' | Out-Null
        New-Fixture 'resolve\priorite\.vscode\settings.json' '{ "peacock.color": "#222222" }' | Out-Null
        Assert-Equal '#111111' (Get-ResolvedColor $p).Color
    }

    Test-It 'Peacock prime sur Solution Colors' {
        $p = New-FixtureDir 'resolve\priorite2'
        New-Fixture 'resolve\priorite2\.vscode\settings.json' '{ "peacock.color": "#222222" }' | Out-Null
        New-Fixture 'resolve\priorite2\.vs\Sol\color.txt' "master:Teal`n" | Out-Null
        Assert-Equal '#222222' (Get-ResolvedColor $p).Color
    }

    Test-It 'Solution Colors prime sur la couleur automatique Git' {
        $p = New-FixtureDir 'resolve\priorite3'
        New-Fixture 'resolve\priorite3\.git\HEAD' "ref: refs/heads/main`n" | Out-Null
        New-Fixture 'resolve\priorite3\.vs\Sol\color.txt' "main:Teal`n" | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#008080' $r.Color
        Assert-Equal 'SolutionColors' $r.Source
    }

    Test-It 'le dossier le plus proche gagne' {
        $parent = New-FixtureDir 'resolve\imbrique'
        New-Fixture 'resolve\imbrique\.terminalcolors.json' '{ "color": "#111111" }' | Out-Null
        $child = New-FixtureDir 'resolve\imbrique\sous-projet'
        New-Fixture 'resolve\imbrique\sous-projet\.terminalcolors.json' '{ "color": "#222222" }' | Out-Null

        Assert-Equal '#222222' (Get-ResolvedColor $child).Color
        Assert-Equal '#111111' (Get-ResolvedColor $parent).Color
    }

    Test-It 'couleur automatique pour un depot Git' {
        $p = New-FixtureDir 'resolve\depot-nu'
        New-Fixture 'resolve\depot-nu\.git\HEAD' "ref: refs/heads/main`n" | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal 'GitRepository' $r.Source
        Assert-Equal (Get-AutoHexOf 'depot-nu') $r.Color
    }

    Test-It 'couleur automatique desactivable' {
        Assert-Null (Get-ResolvedColor (Join-Path $sandbox 'resolve\depot-nu') $false)
    }

    Test-It 'dossier sans rien ne renvoie aucune couleur' {
        Assert-Null (Get-ResolvedColor (New-FixtureDir 'resolve\vide') $false)
    }

    Test-It 'chemin inexistant ne provoque pas d''erreur' {
        Assert-Null (Get-ResolvedColor (Join-Path $sandbox 'resolve\absent-du-disque') $false)
    }

    # ======================================================================
    Write-Section 'Cache de resolution'

    Test-It 'modification du fichier prise en compte' {
        $p = New-FixtureDir 'cache\projet'
        $file = New-Fixture 'cache\projet\.terminalcolors.json' '{ "color": "#111111" }'

        & $m { Clear-TcResolveCache }
        Assert-Equal '#111111' (Get-ResolvedColor $p $false -UseCache).Color

        [System.IO.File]::WriteAllText($file, '{ "color": "#999999" }', (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::SetLastWriteTimeUtc($file, (Get-Date).ToUniversalTime().AddSeconds(5))

        Assert-Equal '#999999' (Get-ResolvedColor $p $false -UseCache).Color
    }

    Test-It 'le parcours de l''arborescence se termine sur une racine de lecteur' {
        # Doit se terminer, sans exception ni boucle infinie.
        Assert-Null (Get-ResolvedColor 'C:\' $false)
    }

    Test-It 'le parcours se termine sur un chemin UNC' {
        # Chemin volontairement inexistant : on verifie seulement la terminaison.
        Assert-Null (Get-ResolvedColor '\\serveur-inexistant\partage\projet\src' $false)
    }

    Test-It 'le cache renvoie le meme objet quand rien ne change' {
        $p = Join-Path $sandbox 'cache\projet'
        $a = Get-ResolvedColor $p $false -UseCache
        $b = Get-ResolvedColor $p $false -UseCache
        Assert-True ([object]::ReferenceEquals($a, $b)) 'le second appel devrait venir du cache'
    }

    # ======================================================================
    Write-Section 'Sequences de controle et titre'

    Test-It 'sequence OSC 11 correcte' {
        $r = & $m { Get-TcBackgroundSequence -Rgb @{ R = 12; G = 87; B = 50 } }
        Assert-Equal (([char]27) + ']11;rgb:0c/57/32' + ([char]7)) $r
    }

    Test-It 'sequence de reinitialisation OSC 111' {
        $r = & $m { Get-TcBackgroundResetSequence }
        Assert-Equal (([char]27) + ']111' + ([char]7)) $r
    }

    Test-It 'gabarit de titre' {
        $r = & $m {
            $info = [pscustomobject]@{ Icon = 'ZZ'; Name = 'Oseille'; Color = '#215732' }
            Format-TcTitle -Format '{icon} {name} [{color}] {folder}' -Info $info -Path 'C:\Repos\oseille\src'
        }
        Assert-Equal 'ZZ Oseille [#215732] src' $r
    }

    Test-It 'gabarit sans icone ne laisse pas d''espace en trop' {
        $r = & $m {
            $info = [pscustomobject]@{ Icon = ''; Name = 'Oseille'; Color = '#215732' }
            Format-TcTitle -Format '{icon} {name}' -Info $info -Path 'C:\Repos\oseille'
        }
        Assert-Equal 'Oseille' $r
    }

    Test-It 'jeton {path} complet' {
        $r = & $m {
            $info = [pscustomobject]@{ Icon = ''; Name = 'X'; Color = '#000000' }
            Format-TcTitle -Format '{path}' -Info $info -Path 'C:\Repos\oseille\src'
        }
        Assert-Equal 'C:\Repos\oseille\src' $r
    }

    # ======================================================================
    Write-Section 'Reglages Windows Terminal'

    Test-It 'profil fusionne avec profiles.defaults' {
        $r = & $m { param($t) Get-TcWtProfile -Settings (ConvertFrom-TcJsonText -Text $t) -ProfileId '{bbb}' } @'
{
    "defaultProfile": "{aaa}",
    "profiles": {
        "defaults": { "colorScheme": "One Half Dark", "suppressApplicationTitle": true },
        "list": [ { "guid": "{aaa}", "name": "PS" }, { "guid": "{bbb}", "name": "Autre", "background": "#123456" } ]
    }
}
'@
        Assert-Equal '#123456' $r.background
        Assert-Equal 'One Half Dark' $r.colorScheme
        Assert-True $r.suppressApplicationTitle
    }

    Test-It 'repli sur le profil par defaut si l''identifiant est inconnu' {
        $r = & $m { param($t) Get-TcWtProfile -Settings (ConvertFrom-TcJsonText -Text $t) -ProfileId '{inconnu}' } '{ "defaultProfile": "{aaa}", "profiles": { "defaults": {}, "list": [ { "guid": "{aaa}", "background": "#0C0C0C" } ] } }'
        Assert-Equal '#0C0C0C' $r.background
    }

    Test-It 'fond de reference deduit d''une palette integree' {
        $r = & $m { ConvertTo-TcHex -Rgb (Get-TcBaseBackground) }
        Assert-True ($r -match '^#[0-9A-F]{6}$') "fond inattendu : $r"
    }

    # ======================================================================
    Write-Section 'Installation du theme Windows Terminal'

    $wtSample = @'
{
    // Ce fichier a ete cree automatiquement.
    "$schema": "https://aka.ms/terminal-profiles-schema",
    "actions": [],
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles":
    {
        "defaults": {},
        "list":
        [
            {
                "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "name": "Windows PowerShell"
            }
        ]
    },
    "schemes": [],
    "themes": []
}
'@

    Test-It 'theme insere et selectionne, JSON toujours valide' {
        $path = New-Fixture 'wt\cas1\settings.json' $wtSample
        $r = Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed

        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed 'le resultat doit rester du JSON valide'
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)

        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })
        Assert-Equal 1 $theme.Count
        Assert-Equal 'terminalBackground' ([string]$theme[0].tab.background)
        Assert-Equal 'terminalBackground' ([string]$theme[0].tab.unfocusedBackground)
        Assert-Equal 'terminalBackground' ([string]$theme[0].tabRow.background)
    }

    Test-It 'commentaires, profils et autres cles preserves' {
        $text = [System.IO.File]::ReadAllText((Join-Path $sandbox 'wt\cas1\settings.json'))
        Assert-True ($text.Contains('// Ce fichier a ete cree automatiquement.')) 'le commentaire doit survivre'
        Assert-True ($text.Contains('"name": "Windows PowerShell"')) 'les profils doivent survivre'
        Assert-True ($text.Contains('"schemes": []')) 'les autres cles doivent survivre'
        Assert-True ($text.Contains('%SystemRoot%\\System32')) 'les echappements doivent survivre'
    }

    Test-It 'sauvegarde creee' {
        Assert-True (@(Get-ChildItem (Join-Path $sandbox 'wt\cas1') -Filter '*.terminalcolors-backup-*').Count -ge 1)
    }

    Test-It 'seconde execution sans duplication' {
        $path = Join-Path $sandbox 'wt\cas1\settings.json'
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, '"name"\s*:\s*"TerminalColors"')).Count
    }

    Test-It '-Force ne duplique pas le theme' {
        $path = Join-Path $sandbox 'wt\cas1\settings.json'
        Install-TerminalColorsTheme -SettingsPath $path -Force -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, '"name"\s*:\s*"TerminalColors"')).Count
        Assert-NotNull (Get-ParsedJson $text)
    }

    Test-It 'themes deja peuple : ajout sans casser l''existant' {
        $path = New-Fixture 'wt\cas2\settings.json' @'
{
    "theme": "dark",
    "themes":
    [
        {
            "name": "MonTheme",
            "tab": { "background": "#FF0000" }
        }
    ]
}
'@
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed 'JSON valide attendu'
        Assert-Equal 2 @($parsed.themes).Count
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)
        Assert-Equal 1 @($parsed.themes | Where-Object { $_.name -eq 'MonTheme' }).Count
    }

    Test-It 'absence de cle themes : la section est creee' {
        $path = New-Fixture 'wt\cas3\settings.json' '{ "defaultProfile": "{aaa}" }'
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)
        Assert-Equal 1 @($parsed.themes).Count
        Assert-Equal '{aaa}' ([string]$parsed.defaultProfile)
    }

    Test-It 'theme sous forme d''objet clair/sombre remplace' {
        $path = New-Fixture 'wt\cas4\settings.json' '{ "theme": { "dark": "dark", "light": "light" }, "themes": [] }'
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)
    }

    Test-It 'JSON invalide refuse sans modification' {
        $path = New-Fixture 'wt\cas5\settings.json' '{ "themes": [ ceci est casse'
        $before = [System.IO.File]::ReadAllText($path)
        $threw = $false
        try { Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw 'une erreur doit etre levee'
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'settings.json absent : erreur explicite' {
        $threw = $false
        try { Install-TerminalColorsTheme -SettingsPath (Join-Path $sandbox 'wt\nulle-part\settings.json') -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
    }

    Test-It '-WhatIf ne modifie rien' {
        $path = New-Fixture 'wt\cas6\settings.json' $wtSample
        $before = [System.IO.File]::ReadAllText($path)
        Install-TerminalColorsTheme -SettingsPath $path -WhatIf | Out-Null
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'desinstallation : theme retire, JSON valide, existant preserve' {
        $path = Join-Path $sandbox 'wt\cas2\settings.json'
        Uninstall-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal 0 @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' }).Count
        Assert-Equal 1 @($parsed.themes | Where-Object { $_.name -eq 'MonTheme' }).Count
        Assert-True ([string]$parsed.theme -ne 'TerminalColors') "theme selectionne inattendu : $($parsed.theme)"
    }

    # ======================================================================
    Write-Section 'Encodage PNG du calque'

    # Le PNG est encode a la main (System.Drawing n'est pas garantie sur
    # PowerShell 7) : on verifie donc la structure du fichier octet par octet.
    function Get-SolidPngBytes {
        param([string] $Color)
        & $m { param($c) New-TcSolidPngBytes -Rgb (ConvertFrom-TcColor -Value $c) } $Color
    }

    function Get-PngChunk {
        param([byte[]] $Bytes, [string] $Type)
        $i = 8
        while ($i + 8 -le $Bytes.Length) {
            $len = ([int]$Bytes[$i] -shl 24) -bor ([int]$Bytes[$i + 1] -shl 16) -bor ([int]$Bytes[$i + 2] -shl 8) -bor [int]$Bytes[$i + 3]
            $name = [System.Text.Encoding]::ASCII.GetString($Bytes, $i + 4, 4)
            if ($name -eq $Type) {
                $data = New-Object 'byte[]' $len
                if ($len -gt 0) { [Array]::Copy($Bytes, $i + 8, $data, 0, $len) }
                return @{ Data = $data; Start = $i }
            }
            $i += 12 + $len
        }
        return $null
    }

    Test-It 'signature PNG et taille attendue' {
        $bytes = Get-SolidPngBytes '#0C0C0C'
        $signature = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        for ($i = 0; $i -lt 8; $i++) { Assert-Equal $signature[$i] $bytes[$i] "octet de signature $i" }
        # 8 signature + 25 IHDR + 37 IDAT + 12 IEND
        Assert-Equal 82 $bytes.Length 'un PNG uni 2x2 doit tenir en 82 octets'
    }

    Test-It 'IHDR annonce une image 2x2 truecolor 8 bits' {
        $bytes = Get-SolidPngBytes '#215732'
        $ihdr = Get-PngChunk -Bytes $bytes -Type 'IHDR'
        Assert-NotNull $ihdr 'le bloc IHDR doit exister'
        Assert-Equal 13 $ihdr.Data.Length
        Assert-Equal 2 $ihdr.Data[3] 'largeur'
        Assert-Equal 2 $ihdr.Data[7] 'hauteur'
        Assert-Equal 8 $ihdr.Data[8] 'bits par canal'
        Assert-Equal 2 $ihdr.Data[9] 'type de couleur RVB'
        Assert-Equal 0 $ihdr.Data[12] 'non entrelace'
    }

    Test-It 'tous les CRC de blocs sont corrects' {
        $bytes = Get-SolidPngBytes '#FF8000'
        $i = 8
        $blocks = 0
        while ($i + 8 -le $bytes.Length) {
            $len = ([int]$bytes[$i] -shl 24) -bor ([int]$bytes[$i + 1] -shl 16) -bor ([int]$bytes[$i + 2] -shl 8) -bor [int]$bytes[$i + 3]
            $covered = New-Object 'byte[]' (4 + $len)
            [Array]::Copy($bytes, $i + 4, $covered, 0, 4 + $len)
            $expected = & $m { param($b) Get-TcCrc32 -Bytes $b } $covered
            $offset = $i + 8 + $len
            $actual = ([int64]$bytes[$offset] -shl 24) -bor ([int64]$bytes[$offset + 1] -shl 16) -bor ([int64]$bytes[$offset + 2] -shl 8) -bor [int64]$bytes[$offset + 3]
            Assert-Equal $expected $actual "CRC du bloc a l'offset $i"
            $blocks++
            $i = $offset + 4
        }
        Assert-Equal 3 $blocks 'IHDR, IDAT et IEND attendus'
        Assert-Equal $bytes.Length $i 'aucun octet ne doit rester apres IEND'
    }

    Test-It 'le flux zlib porte la couleur demandee et son Adler-32' {
        $bytes = Get-SolidPngBytes '#215732'
        $idat = Get-PngChunk -Bytes $bytes -Type 'IDAT'
        Assert-NotNull $idat
        Assert-Equal 0x78 $idat.Data[0] 'en-tete zlib CMF'
        Assert-Equal 0x01 $idat.Data[1] 'en-tete zlib FLG'
        Assert-Equal 0 (((([int]$idat.Data[0]) * 256) + [int]$idat.Data[1]) % 31) 'l''en-tete zlib doit etre divisible par 31'
        Assert-Equal 0x01 $idat.Data[2] 'bloc final non compresse'

        # LEN / NLEN : 2 lignes de (1 octet de filtre + 2 pixels RVB) = 14
        Assert-Equal 14 $idat.Data[3]
        Assert-Equal 0 $idat.Data[4]
        Assert-Equal 0xF1 $idat.Data[5]
        Assert-Equal 0xFF $idat.Data[6]

        $raw = New-Object 'byte[]' 14
        [Array]::Copy($idat.Data, 7, $raw, 0, 14)
        Assert-Equal 0 $raw[0] 'octet de filtre de la premiere ligne'
        Assert-Equal 0x21 $raw[1]; Assert-Equal 0x57 $raw[2]; Assert-Equal 0x32 $raw[3]
        Assert-Equal 0 $raw[7] 'octet de filtre de la seconde ligne'
        Assert-Equal 0x21 $raw[8]; Assert-Equal 0x57 $raw[9]; Assert-Equal 0x32 $raw[10]

        $expected = & $m { param($b) Get-TcAdler32 -Bytes $b } $raw
        $offset = 7 + 14
        $actual = ([int64]$idat.Data[$offset] -shl 24) -bor ([int64]$idat.Data[$offset + 1] -shl 16) -bor ([int64]$idat.Data[$offset + 2] -shl 8) -bor [int64]$idat.Data[$offset + 3]
        Assert-Equal $expected $actual 'Adler-32 du flux zlib'
    }

    Test-It 'encodage deterministe et distinct selon la couleur' {
        $a = Get-SolidPngBytes '#215732'
        $b = Get-SolidPngBytes '#215732'
        $c = Get-SolidPngBytes '#215733'
        Assert-Equal ([Convert]::ToBase64String($a)) ([Convert]::ToBase64String($b)) 'meme couleur, memes octets'
        Assert-True ([Convert]::ToBase64String($a) -ne [Convert]::ToBase64String($c)) 'couleurs differentes, octets differents'
    }

    Test-It 'le PNG est relu correctement par le decodeur du systeme' {
        # System.Drawing n'est pas garantie partout : on ne teste que si elle est
        # disponible, mais quand elle l'est c'est la preuve la plus directe.
        $available = $true
        try {
            if (-not ('System.Drawing.Bitmap' -as [type])) { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
        } catch { $available = $false }

        if (-not $available) {
            Write-Verbose 'System.Drawing indisponible : verification du decodage ignoree.'
            return
        }

        $path = Join-Path $sandbox 'png\relu.png'
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($path, (Get-SolidPngBytes '#215732'))

        $bitmap = [System.Drawing.Bitmap]::FromFile($path)
        try {
            Assert-Equal 2 $bitmap.Width
            Assert-Equal 2 $bitmap.Height
            foreach ($x in 0, 1) {
                foreach ($y in 0, 1) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    Assert-Equal '#215732' ('#{0:X2}{1:X2}{2:X2}' -f $pixel.R, $pixel.G, $pixel.B) "pixel $x,$y"
                }
            }
        } finally { $bitmap.Dispose() }
    }

    # ======================================================================
    Write-Section 'Calque opaque'

    $backdropSample = @'
{
    // Commentaire a preserver.
    "defaultProfile": "{aaa}",
    "profiles":
    {
        "defaults": {},
        "list":
        [
            {
                "commandline": "%SystemRoot%\\System32\\cmd.exe",
                "guid": "{aaa}",
                "name": "PS",
                "colorScheme": "MaPalette"
            }
        ]
    },
    "schemes":
    [
        { "name": "MaPalette", "background": "#0C0C0C" }
    ],
    "themes": []
}
'@

    Test-It 'calque installe : trois cles dans profiles.defaults, JSON valide' {
        $path = New-Fixture 'backdrop\cas1\settings.json' $backdropSample
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed
        Assert-Equal '#0C0C0C' $r.Color 'la couleur doit venir de la palette du profil'

        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed 'le resultat doit rester du JSON valide'
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal 1 ([double]$parsed.profiles.defaults.backgroundImageOpacity)
        Assert-Equal 'fill' ([string]$parsed.profiles.defaults.backgroundImageStretchMode)
    }

    Test-It 'image PNG ecrite, nommee d''apres la couleur' {
        $path = Join-Path $sandbox 'backdrop\cas1\settings.json'
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        $image = [string]$parsed.profiles.defaults.backgroundImage
        Assert-True ([System.IO.File]::Exists($image)) "l'image [$image] doit exister"
        Assert-Equal 'backdrop-0C0C0C.png' (Split-Path $image -Leaf)
    }

    Test-It 'commentaires, profils et echappements preserves' {
        $text = [System.IO.File]::ReadAllText((Join-Path $sandbox 'backdrop\cas1\settings.json'))
        Assert-True ($text.Contains('// Commentaire a preserver.')) 'le commentaire doit survivre'
        Assert-True ($text.Contains('"name": "PS"')) 'les profils doivent survivre'
        Assert-True ($text.Contains('%SystemRoot%\\System32')) 'les echappements doivent survivre'
        Assert-True ($text.Contains('"themes": []')) 'les autres cles doivent survivre'
    }

    Test-It 'seconde execution : rien a changer, aucune duplication' {
        $path = Join-Path $sandbox 'backdrop\cas1\settings.json'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false
        Assert-True (-not $r.Changed) 'la seconde execution ne doit rien changer'
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, '"backgroundImage"')).Count
        Assert-Equal 1 ([regex]::Matches($text, '"backgroundImageOpacity"')).Count
    }

    Test-It 'Test-TerminalColorsBackdrop rend compte de l''etat' {
        $path = Join-Path $sandbox 'backdrop\cas1\settings.json'
        $state = Test-TerminalColorsBackdrop -SettingsPath $path
        Assert-True $state.Installed
        Assert-True $state.ImageExists
        Assert-Equal '#0C0C0C' $state.Color
        Assert-True (-not $state.ForeignImage)
    }

    Test-It '-Color impose la couleur du volet' {
        $path = New-Fixture 'backdrop\cas2\settings.json' $backdropSample
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color 'Black' -Confirm:$false
        Assert-Equal '#000000' $r.Color
        Assert-Equal 'backdrop-000000.png' (Split-Path $r.ImagePath -Leaf)
    }

    Test-It 'couleur invalide refusee sans modification' {
        $path = New-Fixture 'backdrop\cas3\settings.json' $backdropSample
        $before = [System.IO.File]::ReadAllText($path)
        $threw = $false
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color 'bleu-canard' -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw 'une erreur doit etre levee'
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'profiles.defaults absent : la cle est creee' {
        $path = New-Fixture 'backdrop\cas4\settings.json' '{ "profiles": { "list": [] } }'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false
        Assert-True $r.Changed
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-NotNull $parsed.profiles.list 'la liste des profils doit survivre'
    }

    Test-It 'cle profiles absente : la section est creee' {
        $path = New-Fixture 'backdrop\cas5\settings.json' '{ "defaultProfile": "{aaa}" }'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false
        Assert-True $r.Changed
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal '{aaa}' ([string]$parsed.defaultProfile)
    }

    Test-It 'ancien format ou profiles est un tableau : erreur explicite' {
        $path = New-Fixture 'backdrop\cas6\settings.json' '{ "profiles": [ { "guid": "{aaa}" } ] }'
        $before = [System.IO.File]::ReadAllText($path)
        $message = ''
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null } catch { $message = $_.Exception.Message }
        Assert-True ($message -like '*tableau*') "message inattendu : $message"
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'image de fond personnelle : refus sans -Force' {
        $path = New-Fixture 'backdrop\cas7\settings.json' '{ "profiles": { "defaults": { "backgroundImage": "C:\\images\\moi.jpg", "backgroundImageOpacity": 0.4 } } }'
        $before = [System.IO.File]::ReadAllText($path)
        $message = ''
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null } catch { $message = $_.Exception.Message }
        Assert-True ($message -like '*-Force*') "message inattendu : $message"
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'Test-TerminalColorsBackdrop signale une image etrangere' {
        $state = Test-TerminalColorsBackdrop -SettingsPath (Join-Path $sandbox 'backdrop\cas7\settings.json')
        Assert-True (-not $state.Installed)
        Assert-True $state.ForeignImage
    }

    Test-It '-Force remplace l''image personnelle' {
        $path = Join-Path $sandbox 'backdrop\cas7\settings.json'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Force -Confirm:$false
        Assert-True $r.Replaced
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal 1 ([double]$parsed.profiles.defaults.backgroundImageOpacity)
    }

    Test-It 'desinstallation restaure l''image personnelle et son opacite' {
        $path = Join-Path $sandbox 'backdrop\cas7\settings.json'
        Uninstall-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal 'C:\images\moi.jpg' ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal 0.4 ([double]$parsed.profiles.defaults.backgroundImageOpacity)
    }

    Test-It 'desinstallation sans image precedente : les trois cles disparaissent' {
        $path = Join-Path $sandbox 'backdrop\cas1\settings.json'
        Uninstall-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        $parsed = Get-ParsedJson $text
        Assert-NotNull $parsed 'le resultat doit rester du JSON valide'
        Assert-True (-not $text.Contains('backgroundImage')) 'aucune cle backgroundImage ne doit rester'
        Assert-True ($text.Contains('// Commentaire a preserver.')) 'le commentaire doit survivre'
        Assert-True ($text.Contains('"name": "PS"')) 'les profils doivent survivre'
        Assert-True (-not (Test-TerminalColorsBackdrop -SettingsPath $path).Installed)
    }

    Test-It 'JSON invalide refuse sans modification' {
        $path = New-Fixture 'backdrop\cas8\settings.json' '{ "profiles": { ceci est casse'
        $before = [System.IO.File]::ReadAllText($path)
        $threw = $false
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It '-WhatIf ne modifie rien' {
        $path = New-Fixture 'backdrop\cas9\settings.json' $backdropSample
        $before = [System.IO.File]::ReadAllText($path)
        Install-TerminalColorsBackdrop -SettingsPath $path -Color '#123456' -WhatIf | Out-Null
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
        Assert-True (-not [System.IO.File]::Exists((Join-Path (Join-Path $sandbox 'donnees') 'backdrop-123456.png'))) 'aucune image ne doit etre ecrite'
    }

    Test-It 'image posee sur un profil precis : signalee comme prioritaire' {
        $path = New-Fixture 'backdrop\cas10\settings.json' '{ "profiles": { "defaults": {}, "list": [ { "guid": "{aaa}", "name": "Special", "backgroundImage": "C:\\a.png" } ] } }'
        Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null
        $state = Test-TerminalColorsBackdrop -SettingsPath $path
        Assert-True $state.Installed
        Assert-Equal 1 @($state.ProfileOverrides).Count
        Assert-Equal 'Special' ([string]$state.ProfileOverrides[0])
    }

    Test-It 'settings.json absent : erreur explicite' {
        $threw = $false
        try { Install-TerminalColorsBackdrop -SettingsPath (Join-Path $sandbox 'backdrop\nulle-part\settings.json') -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
    }

    # ======================================================================
    Write-Section 'Barre de titre systeme'

    Test-It 'showTabsInTitlebar passe a false, JSON valide' {
        $path = New-Fixture 'titlebar\cas1\settings.json' $backdropSample
        $r = Install-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed
        Assert-True $r.RestartNeeded 'un redemarrage complet de Windows Terminal est requis'

        $text = [System.IO.File]::ReadAllText($path)
        $parsed = Get-ParsedJson $text
        Assert-NotNull $parsed
        Assert-Equal $false ([bool]$parsed.showTabsInTitlebar)
        Assert-True ($text.Contains('// Commentaire a preserver.')) 'le commentaire doit survivre'
        Assert-True (Test-TerminalColorsTitleBar -SettingsPath $path)
    }

    Test-It 'seconde execution : rien a changer' {
        $path = Join-Path $sandbox 'titlebar\cas1\settings.json'
        $r = Install-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false
        Assert-True (-not $r.Changed)
        Assert-Equal 1 ([regex]::Matches([System.IO.File]::ReadAllText($path), '"showTabsInTitlebar"')).Count
    }

    Test-It 'cle absente a l''origine : la desinstallation la retire' {
        $path = Join-Path $sandbox 'titlebar\cas1\settings.json'
        Uninstall-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-NotNull (Get-ParsedJson $text)
        Assert-True (-not $text.Contains('showTabsInTitlebar')) 'la cle doit disparaitre, et non passer a true'
        Assert-True (-not (Test-TerminalColorsTitleBar -SettingsPath $path))
    }

    Test-It 'valeur true a l''origine : elle est restauree' {
        $path = New-Fixture 'titlebar\cas2\settings.json' '{ "showTabsInTitlebar": true, "profiles": { "defaults": {} } }'
        Install-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false | Out-Null
        Assert-True (Test-TerminalColorsTitleBar -SettingsPath $path)

        Uninstall-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-Equal $true ([bool]$parsed.showTabsInTitlebar)
    }

    Test-It '-WhatIf ne modifie rien' {
        $path = New-Fixture 'titlebar\cas3\settings.json' $backdropSample
        $before = [System.IO.File]::ReadAllText($path)
        Install-TerminalColorsTitleBar -SettingsPath $path -WhatIf | Out-Null
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    # ======================================================================
    Write-Section 'Mode couleur pure'

    Test-It '-PureColor force la teinte a 1' {
        $options = Enable-TerminalColors -PureColor -PassThru
        try {
            Assert-True $options.PureColor
            Assert-Equal 1.0 ([double]$options.Tint)
        } finally { Disable-TerminalColors -KeepColor }
    }

    Test-It '-PureColor emet la couleur du projet sans dilution' {
        # Get-TcBlendedColor avec Amount = 1 renvoie exactement la couleur : la
        # sequence emise doit donc porter la couleur du projet, pas un melange.
        $sequence = & $m {
            $rgb = ConvertFrom-TcColor -Value '#215732'
            Get-TcBackgroundSequence -Rgb (Get-TcBlendedColor -Base (ConvertFrom-TcColor -Value '#0C0C0C') -Color $rgb -Amount 1.0)
        }
        Assert-Equal (([char]27) + ']11;rgb:21/57/32' + ([char]7)) $sequence
    }

    # Couleur reellement envoyee au terminal pour un projet, fond de reference
    # impose pour que le test ne depende pas des reglages de la machine.
    function Get-EffectiveBackgroundHex {
        param([string] $Path, [bool] $PureColor, [string] $Base = '#000000')
        & $m { param($p, $pure, $b)
            $info = Resolve-TcColor -Path $p -AutoGitColors $false -NoCache
            $options = New-TcDefaultOptions
            $options.PureColor = $pure
            ConvertTo-TcHex -Rgb (Get-TcEffectiveBackground -Info $info -Options $options -BaseBackground (ConvertFrom-TcColor -Value $b))
        } $Path $PureColor $Base
    }

    Test-It 'en couleur pure, la cle tint d''un projet est ignoree' {
        # Un projet declarant "tint": 0.2 ne doit pas rediluer la couleur quand
        # l'utilisateur a demande -PureColor.
        $p = New-FixtureDir 'pure\projet'
        New-Fixture 'pure\projet\.terminalcolors.json' '{ "color": "#215732", "tint": 0.2 }' | Out-Null
        Assert-Equal '#215732' (Get-EffectiveBackgroundHex -Path $p -PureColor $true)
    }

    Test-It 'sans -PureColor, la cle tint d''un projet est respectee' {
        # 20 % de #215732 sur un fond noir : 33*0.2=7, 87*0.2=17, 50*0.2=10
        $p = Join-Path $sandbox 'pure\projet'
        Assert-Equal '#07110A' (Get-EffectiveBackgroundHex -Path $p -PureColor $false)
    }

    Test-It 'en couleur pure, le fond de reference n''intervient pas' {
        $p = Join-Path $sandbox 'pure\projet'
        Assert-Equal '#215732' (Get-EffectiveBackgroundHex -Path $p -PureColor $true -Base '#FFFFFF')
    }

    # ======================================================================
    Write-Section 'Hook de profil PowerShell'

    Test-It 'bloc ajoute a un profil existant' {
        $path = New-Fixture 'profil\cas1\profile.ps1' "# mon profil`nSet-Alias ll Get-ChildItem`n"
        $r = Install-TerminalColorsProfile -ProfilePath $path -Confirm:$false
        Assert-True $r.Changed

        $text = [System.IO.File]::ReadAllText($path)
        Assert-True ($text.Contains('# mon profil')) 'le contenu existant doit survivre'
        Assert-True ($text.Contains('Import-Module TerminalColors')) 'le bloc doit etre present'
        Assert-True ($text.Contains('Enable-TerminalColors')) 'l''activation doit etre presente'
        Assert-True (Test-TerminalColorsProfile -ProfilePath $path)
    }

    Test-It 'seconde execution : mise a jour sans duplication' {
        $path = Join-Path $sandbox 'profil\cas1\profile.ps1'
        Install-TerminalColorsProfile -ProfilePath $path -EnableArguments '-Tint 0.5' -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, [regex]::Escape('# >>> TerminalColors >>>'))).Count
        Assert-True ($text.Contains('Enable-TerminalColors -Tint 0.5')) 'les arguments doivent etre pris en compte'
    }

    Test-It 'profil inexistant cree' {
        $path = Join-Path $sandbox 'profil\cas2\profile.ps1'
        Install-TerminalColorsProfile -ProfilePath $path -Confirm:$false | Out-Null
        Assert-True (Test-Path -LiteralPath $path)
        Assert-True (Test-TerminalColorsProfile -ProfilePath $path)
    }

    Test-It 'le bloc insere est du PowerShell valide' {
        $path = Join-Path $sandbox 'profil\cas2\profile.ps1'
        $errors = $null; $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-Equal 0 @($errors).Count "erreurs : $(($errors | ForEach-Object { $_.Message }) -join ' | ')"
    }

    Test-It 'desinstallation : bloc retire, reste preserve' {
        $path = Join-Path $sandbox 'profil\cas1\profile.ps1'
        Uninstall-TerminalColorsProfile -ProfilePath $path -Confirm:$false
        $text = [System.IO.File]::ReadAllText($path)
        Assert-True (-not $text.Contains('TerminalColors')) 'plus aucune trace attendue'
        Assert-True ($text.Contains('Set-Alias ll Get-ChildItem')) 'le contenu existant doit survivre'
        Assert-True (-not (Test-TerminalColorsProfile -ProfilePath $path))
    }

    # ======================================================================
    Write-Section 'Commandes publiques'

    Test-It 'Set-FolderColor ecrit une configuration lisible' {
        $p = New-FixtureDir 'public\projet'
        Set-FolderColor -Color '#215732' -Path $p -Name 'MonProjet' -Confirm:$false | Out-Null

        Assert-True (Test-Path -LiteralPath (Join-Path $p '.terminalcolors.json'))
        $r = Get-TerminalColor -Path $p
        Assert-Equal '#215732' $r.Color
        Assert-Equal 'MonProjet' $r.Name
        Assert-Equal 'Config' $r.Source
    }

    Test-It 'Set-FolderColor refuse d''ecraser sans -Force' {
        $threw = $false
        try { Set-FolderColor -Color 'Teal' -Path (Join-Path $sandbox 'public\projet') -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
    }

    Test-It 'Set-FolderColor -Force ecrase' {
        $p = Join-Path $sandbox 'public\projet'
        Set-FolderColor -Color 'Teal' -Path $p -Force -Confirm:$false | Out-Null
        Assert-Equal '#008080' (Get-TerminalColor -Path $p).Color
    }

    Test-It 'Set-FolderColor rejette une couleur invalide' {
        $p = New-FixtureDir 'public\projet2'
        $threw = $false
        try { Set-FolderColor -Color 'bleu-canard-fonce' -Path $p -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $p '.terminalcolors.json')))
    }

    Test-It 'Set-FolderColor gere les couleurs par branche' {
        $p = New-FixtureDir 'public\projet3'
        New-Fixture 'public\projet3\.git\HEAD' "ref: refs/heads/hotfix/urgent`n" | Out-Null
        Set-FolderColor -Color 'Teal' -Path $p -Branches @{ 'hotfix/*' = 'OrangeRed' } -Confirm:$false | Out-Null
        Assert-Equal '#FF4500' (Get-TerminalColor -Path $p).Color
    }

    Test-It 'Set-FolderColor produit un JSON standard' {
        $text = [System.IO.File]::ReadAllText((Join-Path $sandbox 'public\projet3\.terminalcolors.json'))
        Assert-Equal 'Teal' ($text | ConvertFrom-Json).color
    }

    Test-It 'Set-FolderColor accepte auto' {
        $p = New-FixtureDir 'public\projet4'
        Set-FolderColor -Color auto -Path $p -Name 'oseille' -Confirm:$false | Out-Null
        Assert-Equal (Get-AutoHexOf 'oseille') (Get-TerminalColor -Path $p).Color
    }

    Test-It 'Remove-FolderColor supprime la configuration' {
        $p = Join-Path $sandbox 'public\projet'
        Remove-FolderColor -Path $p -Confirm:$false
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $p '.terminalcolors.json')))
    }

    Test-It 'Get-TerminalColor accepte le pipeline' {
        $root = New-FixtureDir 'public\depots'
        foreach ($name in @('alpha', 'beta')) {
            New-FixtureDir "public\depots\$name" | Out-Null
            New-Fixture "public\depots\$name\.terminalcolors.json" '{ "color": "auto" }' | Out-Null
        }
        $results = @(Get-ChildItem $root -Directory | Get-TerminalColor)
        Assert-Equal 2 $results.Count
        Assert-True ($results[0].Color -match '^#[0-9A-F]{6}$')
    }

    Test-It 'Get-TerminalColor sur un dossier sans couleur' {
        $r = Get-TerminalColor -Path (New-FixtureDir 'public\rien') -NoAutoGitColors
        Assert-Equal 'None' $r.Source
        Assert-Null $r.Color
    }

    Test-It 'Get-TerminalColor calcule le fond teinte' {
        $p = New-FixtureDir 'public\teinte'
        New-Fixture 'public\teinte\.terminalcolors.json' '{ "color": "#FFFFFF", "tint": 0.5 }' | Out-Null
        $r = Get-TerminalColor -Path $p
        Assert-True ($r.TintedFallback -match '^#[0-9A-F]{6}$') "fond teinte inattendu : $($r.TintedFallback)"
        Assert-True ($r.TintedFallback -ne '#FFFFFF') 'le fond doit etre melange, pas la couleur pure'
    }

    Test-It 'Get-TerminalColor propose une icone automatique' {
        $r = Get-TerminalColor -Path (Join-Path $sandbox 'public\projet3')
        Assert-True (-not [string]::IsNullOrEmpty($r.Icon)) 'une icone est attendue'
    }

    Test-It 'Enable / Disable preservent l''invite d''origine' {
        $original = 'PS-TEST> '
        Set-Item -Path function:global:prompt -Value ([scriptblock]::Create("'$original'")) -Force

        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        Assert-True (Test-TerminalColorsEnabled) 'la coloration doit etre active'
        Assert-Equal $original (& (Get-Command prompt).ScriptBlock)

        Disable-TerminalColors
        Assert-True (-not (Test-TerminalColorsEnabled)) 'la coloration doit etre inactive'
        Assert-Equal $original (& (Get-Command prompt).ScriptBlock)
    }

    Test-It 'Enable est idempotent' {
        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        Assert-True (Test-TerminalColorsEnabled)
        Disable-TerminalColors
        Assert-Equal 'PS-TEST> ' (& (Get-Command prompt).ScriptBlock)
    }

    Test-It 'Disable sans Enable ne leve pas d''erreur' {
        Disable-TerminalColors
        Assert-True (-not (Test-TerminalColorsEnabled))
    }

    Test-It 'Update-TerminalColor accepte un chemin explicite' {
        $p = New-FixtureDir 'public\update'
        New-Fixture 'public\update\.terminalcolors.json' '{ "color": "#123456", "name": "Update" }' | Out-Null
        $r = Update-TerminalColor -Path $p -Force -PassThru
        Assert-Equal '#123456' $r.Color
        Assert-Equal 'Update' $r.Name
    }

    Test-It 'Update-TerminalColor ne relit rien quand le dossier n''a pas change' {
        $p = New-FixtureDir 'public\stable'
        New-Fixture 'public\stable\.terminalcolors.json' '{ "color": "#ABCDEF", "name": "Stable" }' | Out-Null

        $first = Update-TerminalColor -Path $p -Force -PassThru
        Assert-Equal '#ABCDEF' $first.Color

        # Le fichier change, mais sans -Force et a dossier inchange le module
        # doit rester sur la couleur deja resolue (aucune relecture disque).
        [System.IO.File]::WriteAllText((Join-Path $p '.terminalcolors.json'), '{ "color": "#111111" }', (New-Object System.Text.UTF8Encoding($false)))
        $second = Update-TerminalColor -Path $p -PassThru
        Assert-Equal '#ABCDEF' $second.Color

        # Avec -Force, la nouvelle couleur est prise en compte.
        Assert-Equal '#111111' (Update-TerminalColor -Path $p -Force -PassThru).Color
    }

    Test-It 'AlwaysReapply est desactive par defaut et activable' {
        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        $options = & $m { Get-TcOptions }
        Assert-True (-not $options.AlwaysReapply) 'desactive par defaut'

        Enable-TerminalColors -NoWindowBorder -NoTitle -AlwaysReapply | Out-Null
        $options = & $m { Get-TcOptions }
        Assert-True $options.AlwaysReapply 'activable'
        Disable-TerminalColors
    }

    Test-It 'Clear-TerminalColorCache ne leve pas d''erreur' {
        Clear-TerminalColorCache
        Assert-True $true
    }

    Test-It 'Invoke-TerminalColorsDoctor renvoie des resultats coherents' {
        $results = @(Invoke-TerminalColorsDoctor -PassThru 6>$null)
        Assert-True ($results.Count -ge 5) "au moins 5 verifications attendues, obtenu $($results.Count)"
        foreach ($r in $results) {
            Assert-NotNull $r.Check
            Assert-True ($r.Status -in @('OK', 'Attention', 'Probleme', 'Info')) "statut inattendu : $($r.Status)"
            Assert-True (-not [string]::IsNullOrWhiteSpace($r.Detail)) "detail manquant pour $($r.Check)"
        }
    }

    # ======================================================================
    Write-Section 'Qualite du code'

    Test-It 'toutes les commandes annoncees sont exportees' {
        $manifest = Import-PowerShellDataFile -Path $modulePath
        $exported = @((Get-Module TerminalColors).ExportedFunctions.Keys)
        foreach ($name in $manifest.FunctionsToExport) {
            Assert-True ($exported -contains $name) "commande annoncee mais absente : $name"
        }
        Assert-Equal @($manifest.FunctionsToExport).Count $exported.Count 'aucune commande ne doit etre exportee sans etre annoncee'
    }

    Test-It 'l''alias annonce est exporte' {
        $exported = @((Get-Module TerminalColors).ExportedAliases.Keys)
        Assert-True ($exported -contains 'Set-TerminalColor') "alias manquant, obtenu : $($exported -join ', ')"
    }

    Test-It 'toutes les commandes publiques sont documentees' {
        foreach ($name in (Get-Module TerminalColors).ExportedFunctions.Keys) {
            $help = Get-Help $name -ErrorAction SilentlyContinue
            Assert-True (-not [string]::IsNullOrWhiteSpace($help.Synopsis)) "aide manquante pour $name"
            Assert-True ($help.Synopsis -notlike "$name*") "synopsis absent pour $name"
        }
    }

    Test-It 'les sources PowerShell sont en ASCII pur' {
        $offenders = New-Object System.Collections.ArrayList
        foreach ($file in (Get-SourceFile)) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            for ($i = 0; $i -lt $text.Length; $i++) {
                if ([int]$text[$i] -gt 126) {
                    [void]$offenders.Add("$($file.Name):$i U+$('{0:X4}' -f [int]$text[$i])")
                    break
                }
            }
        }
        Assert-Equal 0 $offenders.Count ('caracteres non-ASCII : ' + ($offenders -join ' ; '))
    }

    Test-It 'aucun fichier source ne comporte d''erreur de syntaxe' {
        foreach ($file in (Get-SourceFile -Extension @('*.ps1', '*.psm1'))) {
            $errors = $null; $tokens = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
            Assert-Equal 0 @($errors).Count "$($file.Name) : $(($errors | ForEach-Object { $_.Message }) -join ' | ')"
        }
    }

    Test-It 'le manifeste est valide' {
        $manifest = Test-ModuleManifest -Path $modulePath -ErrorAction Stop
        Assert-Equal 'TerminalColors' $manifest.Name
        Assert-NotNull $manifest.Version
        Assert-True ($manifest.Description.Length -gt 40) 'description trop courte pour la galerie'
    }

} finally {
    Set-Item -Path function:global:prompt -Value ([scriptblock]::Create('"PS $($ExecutionContext.SessionState.Path.CurrentLocation)> "')) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Bilan -------------------------------------------------------------------
Write-Host ''
Write-Host '  ---------------------------' -ForegroundColor DarkGray
if ($script:Failed -eq 0) {
    Write-Host "  $($script:Passed) tests reussis." -ForegroundColor Green
    Write-Host ''
    exit 0
}

Write-Host "  $($script:Passed) reussis, $($script:Failed) en echec :" -ForegroundColor Red
foreach ($f in $script:Failures) { Write-Host "    - $f" -ForegroundColor Red }
Write-Host ''
exit 1
