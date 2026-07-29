# Calque opaque : ce qui permet d'avoir l'onglet, la barre de titre et la
# bordure en couleur PURE tout en gardant le fond du volet inchange.
#
# Pourquoi c'est necessaire. Un theme Windows Terminal n'accepte que quatre
# valeurs pour tab.background et tabRow.background : terminalBackground, accent,
# une couleur figee, ou rien. La seule pilotable a l'execution est
# terminalBackground. Autrement dit, [couleur de l'onglet] et [couleur de fond]
# sont un seul et meme canal - d'ou la dilution historique a 30 %.
#
# Le calque decouple les deux : OSC 11 envoie la couleur PURE du projet (que
# Windows Terminal recopie sur l'onglet et la barre de titre), et une image de
# fond opaque de votre couleur de fond habituelle est posee par-dessus dans le
# volet. Windows Terminal peint l'onglet a partir de la couleur de fond, jamais
# de l'image : l'onglet devient franc, le volet reste tel quel.
#
# Verifie : couleur de fond #FF0000 + image #0C0C0C donne bien un onglet et une
# barre de titre a #FF0000 pour un volet mesure a #0C0C0C.

$script:TcBackdropPrefix = 'backdrop-'

function Get-TcBackdropDirectory {
    return (Get-TcDataDirectory)
}

function Get-TcBackdropPath {
    param([hashtable] $Rgb)

    $name = '{0}{1:X2}{2:X2}{3:X2}.png' -f $script:TcBackdropPrefix, [int]$Rgb.R, [int]$Rgb.G, [int]$Rgb.B
    return (Join-Path (Get-TcBackdropDirectory) $name)
}

function Test-TcBackdropPath {
    <#
        .SYNOPSIS
        Indique si un chemin d'image de fond est une image generee par
        TerminalColors (et non une image personnelle de l'utilisateur).
    #>
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $leaf = ''
    try { $leaf = Split-Path $Path -Leaf } catch { return $false }
    return ($leaf -like ($script:TcBackdropPrefix + '*.png'))
}

function ConvertTo-TcJsonString {
    <#
        .SYNOPSIS
        Litteral chaine JSON, guillemets compris, echappements inclus.
    #>
    param([string] $Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Initialize-TcWtProfileDefaults {
    <#
        .SYNOPSIS
        Garantit la presence de profiles.defaults dans le texte de settings.json
        et renvoie @{ Text; Anchor } ou Anchor pointe sur l'accolade ouvrante de
        cet objet.
    #>
    param([string] $Text, [int] $Depth = 0)

    if ($Depth -gt 3) { throw 'TerminalColors : impossible de creer profiles.defaults dans settings.json.' }

    $masked = Get-TcMaskedJson -Text $Text
    $m = [regex]::Match($masked, '"profiles"\s*:\s*')
    if (-not $m.Success) {
        $root = Find-TcJsonRootIndex -Masked $masked
        $fragment = [Environment]::NewLine + '    "profiles":' + [Environment]::NewLine + '    {' +
                    [Environment]::NewLine + '        "defaults": {}' + [Environment]::NewLine + '    },'
        return (Initialize-TcWtProfileDefaults -Text $Text.Insert($root + 1, $fragment) -Depth ($Depth + 1))
    }

    $valueStart = $m.Index + $m.Length
    if ($valueStart -ge $masked.Length) { throw 'TerminalColors : "profiles" est tronque dans settings.json.' }
    if ($masked[$valueStart] -eq '[') {
        throw 'TerminalColors : ce settings.json utilise l''ancien format ou "profiles" est un tableau. Ouvrez les reglages de Windows Terminal et enregistrez-les une fois pour le convertir, puis relancez.'
    }
    if ($masked[$valueStart] -ne '{') { throw 'TerminalColors : "profiles" n''est pas un objet dans settings.json.' }

    $profilesSpan = Find-TcJsonBlockSpan -Text $masked -Index $valueStart
    if ($null -eq $profilesSpan) { throw 'TerminalColors : "profiles" est mal forme dans settings.json.' }

    $defaults = Find-TcJsonMember -Masked $masked -Span $profilesSpan -Name 'defaults'
    if ($null -eq $defaults) {
        $fragment = [Environment]::NewLine + '        "defaults": {},'
        return (Initialize-TcWtProfileDefaults -Text $Text.Insert($profilesSpan.Start + 1, $fragment) -Depth ($Depth + 1))
    }
    if ($masked[$defaults.ValueStart] -ne '{') { throw 'TerminalColors : profiles.defaults n''est pas un objet dans settings.json.' }

    return @{ Text = $Text; Anchor = $defaults.ValueStart }
}

function Get-TcBackdropSettings {
    <#
        .SYNOPSIS
        Lit l'etat du calque dans un settings.json analyse.
    #>
    param($Settings)

    $result = @{ Image = $null; Opacity = $null; StretchMode = $null; ProfileOverrides = @() }

    $profiles = Get-TcJsonProperty -InputObject $Settings -Name 'profiles'
    if ($null -eq $profiles) { return $result }

    $defaults = Get-TcJsonProperty -InputObject $profiles -Name 'defaults'
    if ($defaults) {
        $result.Image = Get-TcJsonProperty -InputObject $defaults -Name 'backgroundImage'
        $result.Opacity = Get-TcJsonProperty -InputObject $defaults -Name 'backgroundImageOpacity'
        $result.StretchMode = Get-TcJsonProperty -InputObject $defaults -Name 'backgroundImageStretchMode'
    }

    # Une image posee sur un profil precis prend le pas sur profiles.defaults :
    # le calque serait alors sans effet dans ce profil.
    $list = Get-TcJsonProperty -InputObject $profiles -Name 'list'
    if ($list) {
        $overrides = @()
        foreach ($p in $list) {
            $image = Get-TcJsonProperty -InputObject $p -Name 'backgroundImage'
            if ($image -and -not (Test-TcBackdropPath -Path ([string]$image))) {
                $label = [string](Get-TcJsonProperty -InputObject $p -Name 'name')
                if (-not $label) { $label = [string](Get-TcJsonProperty -InputObject $p -Name 'guid') }
                $overrides += $label
            }
        }
        $result.ProfileOverrides = $overrides
    }

    return $result
}

function Install-TerminalColorsBackdrop {
    <#
        .SYNOPSIS
        Installe le calque opaque : l'onglet, la barre de titre et la bordure
        passent en couleur pure, et le fond du volet ne change plus.

        .DESCRIPTION
        Genere une image PNG unie de votre couleur de fond actuelle et la declare
        comme image de fond dans profiles.defaults de Windows Terminal
        (backgroundImage, backgroundImageOpacity, backgroundImageStretchMode).

        Windows Terminal peint l'onglet et la barre de titre a partir de la
        couleur de fond, jamais de l'image de fond. La couleur de fond peut donc
        porter la couleur pure du projet sans que le volet ne change d'aspect.

        A combiner avec [Enable-TerminalColors -PureColor], qui envoie la couleur
        du projet sans dilution. Le theme TerminalColors reste indispensable :
        c'est lui qui relie l'onglet a la couleur de fond.

        settings.json est modifie par insertion ciblee, avec sauvegarde prealable
        et validation du resultat avant ecriture.

        .PARAMETER SettingsPath
        Chemin du settings.json a modifier. Detecte automatiquement par defaut.

        .PARAMETER Color
        Couleur du calque, c'est-a-dire la couleur que gardera le volet. Par
        defaut, la couleur de fond deja declaree par votre profil ou votre
        palette Windows Terminal : le volet reste donc exactement tel qu'il est.

        .PARAMETER Force
        Remplace une image de fond deja declaree qui ne vient pas de
        TerminalColors. Sans ce commutateur, la commande s'arrete pour ne pas
        ecraser votre reglage.

        .PARAMETER NoBackup
        N'ecrit pas de copie de sauvegarde.

        .EXAMPLE
        Install-TerminalColorsBackdrop

        .EXAMPLE
        Install-TerminalColorsBackdrop -Color '#000000'
        Fixe un volet parfaitement noir, quelle que soit la palette du profil.

        .EXAMPLE
        Install-TerminalColorsBackdrop -WhatIf
        Montre ce qui serait modifie sans rien ecrire.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $SettingsPath,
        [string] $Color,
        [switch] $Force,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    $settings = ConvertFrom-TcJsonText -Text $text
    if ($null -eq $settings) {
        throw "TerminalColors : [$SettingsPath] n'est pas un JSON valide. Corrigez-le avant d'installer le calque."
    }

    # --- 1. Couleur du calque -----------------------------------------------
    if ($Color) {
        $rgb = ConvertFrom-TcColor -Value $Color
        if ($null -eq $rgb) { throw "TerminalColors : couleur de calque invalide [$Color]." }
    } else {
        $rgb = Get-TcSettingsBackground -Settings $settings -ProfileId $env:WT_PROFILE_ID
        if ($null -eq $rgb) { $rgb = ConvertFrom-TcColor -Value $script:TcDefaultBaseBackground }
    }
    $hex = ConvertTo-TcHex -Rgb $rgb
    $imagePath = Get-TcBackdropPath -Rgb $rgb

    # --- 2. Refus d'ecraser une image personnelle ---------------------------
    $current = Get-TcBackdropSettings -Settings $settings
    $previousImage = [string]$current.Image
    $foreign = ($previousImage -and -not (Test-TcBackdropPath -Path $previousImage))
    if ($foreign -and -not $Force) {
        throw "TerminalColors : une image de fond est deja declaree dans profiles.defaults [$previousImage]. Utilisez -Force pour la remplacer (elle sera restauree par Uninstall-TerminalColorsBackdrop)."
    }

    # --- 3. Edition de settings.json ----------------------------------------
    $prepared = Initialize-TcWtProfileDefaults -Text $text
    $newText = $prepared.Text
    $anchor = $prepared.Anchor
    $changes = @()

    $members = @(
        @{ Name = 'backgroundImage'; Literal = (ConvertTo-TcJsonString -Value $imagePath) }
        @{ Name = 'backgroundImageOpacity'; Literal = '1.0' }
        @{ Name = 'backgroundImageStretchMode'; Literal = '"fill"' }
    )
    foreach ($member in $members) {
        # Chaque edition invalide les index : on relocalise l'ancre a chaque fois.
        $prepared = Initialize-TcWtProfileDefaults -Text $newText
        $newText = $prepared.Text
        $anchor = $prepared.Anchor

        $applied = Set-TcJsonMember -Text $newText -AnchorIndex $anchor -Name $member.Name -Literal $member.Literal
        $newText = $applied.Text
        if ($applied.Action -ne 'inchange') { $changes += "$($member.Name) $($applied.Action)" }
    }

    # --- 4. Validation avant ecriture ---------------------------------------
    $parsed = ConvertFrom-TcJsonText -Text $newText
    if ($null -eq $parsed) {
        throw 'TerminalColors : la modification aurait produit un JSON invalide. Aucun changement ecrit. Signalez ce cas avec votre settings.json.'
    }
    $check = Get-TcBackdropSettings -Settings $parsed
    if ([string]$check.Image -ne $imagePath) {
        throw 'TerminalColors : verification echouee (image de fond non declaree). Aucun changement ecrit.'
    }
    if ([double]$check.Opacity -ne 1.0) {
        throw 'TerminalColors : verification echouee (opacite differente de 1). Aucun changement ecrit.'
    }
    if ([string]$check.StretchMode -ne 'fill') {
        throw 'TerminalColors : verification echouee (mode d''etirement inattendu). Aucun changement ecrit.'
    }

    # --- 5. Ecriture ---------------------------------------------------------
    $backupPath = $null
    $written = $false
    $target = "Installer le calque opaque $hex"
    if ($changes.Count -gt 0) { $target = "$target ($($changes -join ', '))" }

    if ($PSCmdlet.ShouldProcess($SettingsPath, $target)) {
        Write-TcSolidPng -Path $imagePath -Rgb $rgb | Out-Null

        # Les calques d'anciennes couleurs ne servent plus a rien.
        Get-ChildItem -Path (Get-TcBackdropDirectory) -Filter ($script:TcBackdropPrefix + '*.png') -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $imagePath } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        if ($changes.Count -gt 0) {
            if ($foreign) {
                Set-TcInstallState -Name 'PreviousBackgroundImage' -Value $previousImage
                Set-TcInstallState -Name 'PreviousBackgroundImageOpacity' -Value $current.Opacity
                Set-TcInstallState -Name 'PreviousBackgroundImageStretchMode' -Value $current.StretchMode
            }
            $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
        }
        $written = $true
    }

    return [pscustomobject]@{
        SettingsPath = $SettingsPath
        Changed      = ($changes.Count -gt 0)
        Changes      = $changes
        Color        = $hex
        ImagePath    = $imagePath
        ImageWritten = $written
        Replaced     = $foreign
        Backup       = $backupPath
    }
}

function Uninstall-TerminalColorsBackdrop {
    <#
        .SYNOPSIS
        Retire le calque opaque et restaure l'image de fond precedente s'il y en
        avait une.

        .DESCRIPTION
        Apres cette commande, le fond du volet suit de nouveau la couleur envoyee
        par le module : pensez a retirer [-PureColor] de votre profil, sans quoi
        le volet prendra la couleur pure du projet.

        .PARAMETER SettingsPath
        Chemin du settings.json a modifier. Detecte automatiquement par defaut.

        .PARAMETER NoBackup
        N'ecrit pas de copie de sauvegarde.

        .EXAMPLE
        Uninstall-TerminalColorsBackdrop
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
        throw "TerminalColors : [$SettingsPath] n'est pas un JSON valide."
    }

    $current = Get-TcBackdropSettings -Settings $settings
    if (-not $current.Image) {
        Write-Warning 'TerminalColors : aucun calque opaque declare dans profiles.defaults.'
        return
    }
    if (-not (Test-TcBackdropPath -Path ([string]$current.Image))) {
        Write-Warning "TerminalColors : l'image de fond declaree [$($current.Image)] ne vient pas de TerminalColors ; elle est laissee en place."
        return
    }

    $restoreImage = Get-TcInstallState -Name 'PreviousBackgroundImage'
    $newText = $text
    $changes = @()

    if ($restoreImage) {
        $values = @(
            @{ Name = 'backgroundImage'; Literal = (ConvertTo-TcJsonString -Value ([string]$restoreImage)) }
            @{ Name = 'backgroundImageOpacity'; State = 'PreviousBackgroundImageOpacity' }
            @{ Name = 'backgroundImageStretchMode'; State = 'PreviousBackgroundImageStretchMode' }
        )
        foreach ($value in $values) {
            $literal = $value.Literal
            if (-not $literal) {
                $saved = Get-TcInstallState -Name $value.State
                if ($null -eq $saved) { continue }
                if ($saved -is [string]) { $literal = ConvertTo-TcJsonString -Value $saved } else { $literal = [string]$saved }
            }
            $prepared = Initialize-TcWtProfileDefaults -Text $newText
            $applied = Set-TcJsonMember -Text $prepared.Text -AnchorIndex $prepared.Anchor -Name $value.Name -Literal $literal
            $newText = $applied.Text
            if ($applied.Action -ne 'inchange') { $changes += "$($value.Name) restaure" }
        }
    } else {
        foreach ($name in @('backgroundImage', 'backgroundImageOpacity', 'backgroundImageStretchMode')) {
            $prepared = Initialize-TcWtProfileDefaults -Text $newText
            $applied = Remove-TcJsonMember -Text $prepared.Text -AnchorIndex $prepared.Anchor -Name $name
            $newText = $applied.Text
            if ($applied.Action -eq 'retire') { $changes += "$name retire" }
        }
    }

    if ($changes.Count -eq 0) {
        Write-Warning 'TerminalColors : rien a retirer.'
        return
    }

    if ($null -eq (ConvertFrom-TcJsonText -Text $newText)) {
        throw 'TerminalColors : la modification aurait produit un JSON invalide. Aucun changement ecrit.'
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($SettingsPath, "Retirer le calque opaque ($($changes -join ', '))")) {
        $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
        Get-ChildItem -Path (Get-TcBackdropDirectory) -Filter ($script:TcBackdropPrefix + '*.png') -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        foreach ($name in @('PreviousBackgroundImage', 'PreviousBackgroundImageOpacity', 'PreviousBackgroundImageStretchMode')) {
            Remove-TcInstallState -Name $name
        }
    }

    return [pscustomobject]@{
        SettingsPath = $SettingsPath
        Changed      = $true
        Changes      = $changes
        Backup       = $backupPath
    }
}

function Test-TerminalColorsBackdrop {
    <#
        .SYNOPSIS
        Etat du calque opaque : est-il declare, l'image existe-t-elle, quelle
        couleur garde le volet.

        .PARAMETER SettingsPath
        Chemin du settings.json a inspecter. Detecte automatiquement par defaut.

        .EXAMPLE
        Test-TerminalColorsBackdrop
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string] $SettingsPath)

    if (-not $SettingsPath) { $SettingsPath = Get-TcWtSettingsPath }

    $result = [pscustomobject]@{
        SettingsPath     = $SettingsPath
        Installed        = $false
        ImagePath        = $null
        ImageExists      = $false
        Color            = $null
        Opacity          = $null
        StretchMode      = $null
        ForeignImage     = $false
        ProfileOverrides = @()
    }

    if (-not $SettingsPath -or -not [System.IO.File]::Exists($SettingsPath)) { return $result }

    $settings = ConvertFrom-TcJsonFile -Path $SettingsPath
    if ($null -eq $settings) { return $result }

    $current = Get-TcBackdropSettings -Settings $settings
    $image = [string]$current.Image
    $result.ImagePath = $current.Image
    $result.Opacity = $current.Opacity
    $result.StretchMode = $current.StretchMode
    $result.ProfileOverrides = $current.ProfileOverrides

    if (-not $image) { return $result }

    if (-not (Test-TcBackdropPath -Path $image)) {
        $result.ForeignImage = $true
        return $result
    }

    $result.Installed = $true
    $result.ImageExists = [System.IO.File]::Exists($image)

    $leaf = Split-Path $image -Leaf
    $m = [regex]::Match($leaf, '^' + [regex]::Escape($script:TcBackdropPrefix) + '([0-9A-Fa-f]{6})\.png$')
    if ($m.Success) { $result.Color = '#' + $m.Groups[1].Value.ToUpperInvariant() }

    return $result
}
