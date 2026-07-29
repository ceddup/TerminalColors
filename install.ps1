<#
    .SYNOPSIS
    Installe TerminalColors : module, theme Windows Terminal et hook de profil.

    .DESCRIPTION
    A lancer depuis un clone (ou une archive decompressee) du depot :

        .\install.ps1

    Le script :
      1. copie le module dans vos modules PowerShell utilisateur (5.1 et 7 si
         present) ;
      2. installe et selectionne le theme Windows Terminal qui fait suivre
         l'onglet et la barre de titre ;
      3. installe le calque opaque, qui rend la couleur franche sur l'onglet, la
         barre de titre et la bordure sans changer le fond du volet ;
      4. ajoute le bloc d'activation a votre profil PowerShell ;
      5. active la coloration dans la session courante.

    Aucun droit administrateur n'est necessaire, et rien n'est installe hors de
    votre profil utilisateur.

    .PARAMETER Scope
    CurrentUser (defaut) installe dans vos modules personnels. AllUsers exige
    des droits administrateur.

    .PARAMETER SkipTheme
    N'installe pas le theme Windows Terminal (a faire manuellement ensuite avec
    Install-TerminalColorsTheme).

    .PARAMETER SkipBackdrop
    N'installe pas le calque opaque. La couleur du projet est alors diluee sur le
    fond du volet (comportement des versions 1.0), et l'onglet reste discret.

    .PARAMETER SystemTitleBar
    Sort les onglets de la barre de titre pour que Windows Terminal affiche une
    vraie barre de titre systeme, coloree en couleur pure par DWM. Demande la
    fermeture complete de Windows Terminal pour prendre effet.

    .PARAMETER SkipProfile
    Ne modifie pas votre profil PowerShell.

    .PARAMETER EnableArguments
    Arguments passes a Enable-TerminalColors dans le profil.
    Exemple : -EnableArguments '-TitleFormat "{icon} {name}" -NoWindowBorder'
    -PureColor est ajoute automatiquement quand le calque opaque est installe,
    sauf si vous precisez vous-meme -Tint ou -PureColor.

    .PARAMETER Force
    Ecrase une installation existante du module et reinstalle le theme.

    .EXAMPLE
    .\install.ps1

    .EXAMPLE
    .\install.ps1 -SystemTitleBar
    Ajoute une barre de titre systeme coloree en plus de l'onglet.

    .EXAMPLE
    .\install.ps1 -SkipBackdrop -EnableArguments '-Tint 0.45' -Force
    Conserve le rendu dilue des versions 1.0.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string] $Scope = 'CurrentUser',

    [switch] $SkipTheme,
    [switch] $SkipBackdrop,
    [switch] $SystemTitleBar,
    [switch] $SkipProfile,
    [string] $EnableArguments,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Message)
    Write-Host '  -> ' -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string] $Message)
    Write-Host '  !  ' -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor Yellow
}

$sourceModule = Join-Path $PSScriptRoot 'src\TerminalColors'
if (-not (Test-Path -LiteralPath (Join-Path $sourceModule 'TerminalColors.psd1'))) {
    throw "Module introuvable dans [$sourceModule]. Lancez ce script depuis la racine du depot TerminalColors."
}

$manifest = Import-PowerShellDataFile -Path (Join-Path $sourceModule 'TerminalColors.psd1')
$version = [string]$manifest.ModuleVersion

# Prefixe des messages en mode simulation, pour ne pas annoncer une action faite.
$simulated = ''
if ($WhatIfPreference) { $simulated = '(simulation) ' }

Write-Host ''
Write-Host "  TerminalColors $version" -ForegroundColor White
Write-Host '  ============================' -ForegroundColor DarkGray
Write-Host ''

# --- 1. Destinations ---------------------------------------------------------
# On installe pour chaque edition de PowerShell presente sur la machine, afin
# que le module soit disponible quel que soit le profil Windows Terminal utilise.
$documents = [Environment]::GetFolderPath('MyDocuments')
$targets = New-Object System.Collections.ArrayList

if ($Scope -eq 'AllUsers') {
    [void]$targets.Add((Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'))
    if (Test-Path (Join-Path $env:ProgramFiles 'PowerShell')) {
        [void]$targets.Add((Join-Path $env:ProgramFiles 'PowerShell\Modules'))
    }
} else {
    [void]$targets.Add((Join-Path $documents 'WindowsPowerShell\Modules'))
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        [void]$targets.Add((Join-Path $documents 'PowerShell\Modules'))
    }
}

foreach ($root in $targets) {
    $destination = Join-Path (Join-Path $root 'TerminalColors') $version

    if (Test-Path -LiteralPath $destination) {
        if (-not $Force) {
            Write-Warn "Deja installe dans [$destination] - utilisez -Force pour remplacer."
            continue
        }
        if ($PSCmdlet.ShouldProcess($destination, 'Supprimer la version existante')) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($destination, 'Copier le module')) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path (Join-Path $sourceModule '*') -Destination $destination -Recurse -Force
        Write-Step "Module copie dans $destination"
    }
}

# --- 2. Chargement -----------------------------------------------------------
Remove-Module TerminalColors -Force -ErrorAction SilentlyContinue
if ($WhatIfPreference) {
    # Rien n'a ete copie : on charge depuis le depot pour pouvoir tout de meme
    # montrer ce que les etapes suivantes feraient.
    Import-Module (Join-Path $sourceModule 'TerminalColors.psd1') -Force -ErrorAction Stop
    Write-Step 'Module charge depuis le depot (mode -WhatIf)'
} else {
    # Import par nom : verifie du meme coup que le module est bien decouvrable.
    Import-Module TerminalColors -Force -ErrorAction Stop
    Write-Step "Module charge (version $((Get-Module TerminalColors).Version))"
}

# --- 3. Theme Windows Terminal ----------------------------------------------
# -WhatIf est transmis explicitement : les variables de preference ne franchissent
# pas la frontiere d'un module, donc $WhatIfPreference defini ici ne serait pas vu
# par les commandes du module.
if (-not $SkipTheme) {
    try {
        $result = Install-TerminalColorsTheme -Force:$Force -WhatIf:$WhatIfPreference
        if ($result.Changed) {
            Write-Step "$($simulated)Theme Windows Terminal installe ($($result.Changes -join ', '))"
            if ($result.Backup) { Write-Step "Sauvegarde de settings.json : $($result.Backup)" }
        } else {
            Write-Step 'Theme Windows Terminal deja en place'
        }
    } catch {
        Write-Warn "Theme non installe : $($_.Exception.Message)"
        Write-Warn 'Sans le theme, l''onglet et la barre de titre ne changeront pas de couleur.'
    }
} else {
    Write-Warn 'Theme Windows Terminal ignore (-SkipTheme).'
}

# --- 3bis. Calque opaque -----------------------------------------------------
# C'est lui qui permet la couleur franche sur l'onglet sans colorer le volet :
# la couleur de fond porte la couleur pure du projet (l'onglet la recopie), et
# une image unie de votre couleur de fond habituelle est posee sur le volet.
$backdropInstalled = $false
if (-not $SkipBackdrop) {
    try {
        $result = Install-TerminalColorsBackdrop -WhatIf:$WhatIfPreference
        $backdropInstalled = $true
        if ($result.Changed) {
            Write-Step "$($simulated)Calque opaque installe : le volet reste $($result.Color)"
            if ($result.Backup) { Write-Step "Sauvegarde de settings.json : $($result.Backup)" }
        } else {
            Write-Step "Calque opaque deja en place (volet $($result.Color))"
        }
    } catch {
        Write-Warn "Calque opaque non installe : $($_.Exception.Message)"
        Write-Warn 'La couleur restera diluee sur le fond du volet.'
    }
} else {
    Write-Warn 'Calque opaque ignore (-SkipBackdrop) : la couleur sera diluee sur le fond du volet.'
}

# --- 3ter. Barre de titre systeme (optionnelle) ------------------------------
if ($SystemTitleBar) {
    try {
        $result = Install-TerminalColorsTitleBar -WhatIf:$WhatIfPreference
        if ($result.Changed) {
            Write-Step "$($simulated)Barre de titre systeme activee (showTabsInTitlebar: false)"
            Write-Warn 'Fermez completement Windows Terminal pour que ce reglage prenne effet.'
        } else {
            Write-Step 'Barre de titre systeme deja active'
        }
    } catch {
        Write-Warn "Barre de titre systeme non activee : $($_.Exception.Message)"
    }
}

# --- 4. Profil PowerShell ----------------------------------------------------
# Le calque opaque n'a d'interet qu'avec -PureColor : on l'ajoute, sauf si
# l'utilisateur a deja exprime son choix de dilution.
$effectiveArguments = $EnableArguments
if ($backdropInstalled -and $EnableArguments -notmatch '-(PureColor|Tint)\b') {
    $effectiveArguments = ('-PureColor ' + $EnableArguments).Trim()
}

if (-not $SkipProfile) {
    $profiles = New-Object System.Collections.ArrayList
    [void]$profiles.Add($PROFILE.CurrentUserAllHosts)

    # Profil de l'autre edition de PowerShell, si elle est installee.
    if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        [void]$profiles.Add((Join-Path $documents 'PowerShell\profile.ps1'))
    } elseif ($PSVersionTable.PSEdition -eq 'Core') {
        [void]$profiles.Add((Join-Path $documents 'WindowsPowerShell\profile.ps1'))
    }

    foreach ($profilePath in ($profiles | Select-Object -Unique)) {
        try {
            $result = Install-TerminalColorsProfile -ProfilePath $profilePath -EnableArguments $effectiveArguments -WhatIf:$WhatIfPreference
            if ($result.Changed) {
                Write-Step "$($simulated)Profil mis a jour : $($result.ProfilePath) ($($result.Action))"
            } else {
                Write-Step "Profil deja a jour : $($result.ProfilePath)"
            }
        } catch {
            Write-Warn "Profil [$profilePath] non modifie : $($_.Exception.Message)"
        }
    }
} else {
    Write-Warn 'Profil PowerShell ignore (-SkipProfile).'
}

# --- 5. Activation immediate -------------------------------------------------
if ($WhatIfPreference) {
    Write-Warn 'Mode -WhatIf : rien n''a ete ecrit, et la session n''a pas ete modifiee.'
} elseif ($env:WT_SESSION) {
    if ($effectiveArguments) {
        Write-Step "Activation avec : $effectiveArguments"
        # Les arguments viennent de la ligne de commande de l'utilisateur : on
        # les transmet tels quels a la commande d'activation.
        Invoke-Expression "Enable-TerminalColors $effectiveArguments"
    } else {
        Enable-TerminalColors
    }
    Write-Step 'Coloration active dans cette session'
} else {
    Write-Warn 'Session hors Windows Terminal : ouvrez Windows Terminal pour voir le resultat.'
}

Write-Host ''
Write-Host '  Termine.' -ForegroundColor Green
Write-Host ''
Write-Host '  Pour verifier :   ' -NoNewline; Write-Host 'Invoke-TerminalColorsDoctor' -ForegroundColor White
Write-Host '  Pour essayer :    ' -NoNewline; Write-Host 'cd <un depot Git> puis regardez l''onglet' -ForegroundColor White
Write-Host '  Couleur choisie : ' -NoNewline; Write-Host 'Set-FolderColor ''#215732''' -ForegroundColor White
Write-Host ''
