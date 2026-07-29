# Barre de titre systeme : deuxieme facon d'obtenir une couleur pure, sans
# toucher au fond du volet ni ajouter de fichier.
#
# Par defaut, Windows Terminal dessine ses onglets DANS la barre de titre : la
# fenetre n'a donc pas de vraie barre de titre systeme, et sa couleur depend du
# theme - donc de la couleur de fond. En desactivant showTabsInTitlebar, la
# fenetre retrouve une barre de titre systeme, que DWM sait colorer directement
# (DWMWA_CAPTION_COLOR), exactement comme la bordure : couleur pure, immediate,
# sans passer par la couleur de fond.
#
# Contrepartie : la bande d'onglets descend sous la barre de titre, et elle reste
# soumise au theme. L'onglet lui-meme ne porte donc la couleur du projet que si
# le calque opaque est installe (Install-TerminalColorsBackdrop).
#
# La coloration effective de la barre de titre est faite a l'execution par
# [Enable-TerminalColors -CaptionColor].

function Get-TcShowTabsInTitlebar {
    <#
        .SYNOPSIS
        Valeur de showTabsInTitlebar dans un settings.json analyse. $null si la
        cle est absente (Windows Terminal considere alors qu'elle vaut true).
    #>
    param($Settings)

    return (Get-TcJsonProperty -InputObject $Settings -Name 'showTabsInTitlebar')
}

function Install-TerminalColorsTitleBar {
    <#
        .SYNOPSIS
        Fait apparaitre une vraie barre de titre systeme, colorable en couleur
        pure par DWM.

        .DESCRIPTION
        Ecrit [showTabsInTitlebar: false] dans settings.json. La fenetre Windows
        Terminal retrouve alors une barre de titre systeme, que TerminalColors
        colore en couleur pure du projet via DWM - comme la bordure, et sans
        toucher au fond du volet.

        Deux choses a savoir :

        - Windows Terminal doit etre entierement redemarre (toutes ses fenetres
          fermees) : ce reglage n'est pas relu a chaud.
        - la coloration effective demande [Enable-TerminalColors -CaptionColor].
          Sans ce commutateur, la barre de titre reste de la couleur du systeme.

        La bande d'onglets, elle, descend sous la barre de titre et reste soumise
        au theme : pour que l'onglet lui-meme porte la couleur du projet,
        installez aussi le calque opaque (Install-TerminalColorsBackdrop).

        .PARAMETER SettingsPath
        Chemin du settings.json a modifier. Detecte automatiquement par defaut.

        .PARAMETER NoBackup
        N'ecrit pas de copie de sauvegarde.

        .EXAMPLE
        Install-TerminalColorsTitleBar
        Enable-TerminalColors -CaptionColor

        .EXAMPLE
        Install-TerminalColorsTitleBar -WhatIf
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
        throw "TerminalColors : [$SettingsPath] n'est pas un JSON valide. Corrigez-le avant de modifier la barre de titre."
    }

    $previous = Get-TcShowTabsInTitlebar -Settings $settings
    if ($previous -eq $false) {
        Write-Verbose 'TerminalColors: showTabsInTitlebar est deja a false.'
        return [pscustomobject]@{
            SettingsPath = $SettingsPath
            Changed      = $false
            Changes      = @()
            Backup       = $null
            RestartNeeded = $false
        }
    }

    $masked = Get-TcMaskedJson -Text $text
    $root = Find-TcJsonRootIndex -Masked $masked
    $applied = Set-TcJsonMember -Text $text -AnchorIndex $root -Name 'showTabsInTitlebar' -Literal 'false' -Indent '    '
    $newText = $applied.Text

    $parsed = ConvertFrom-TcJsonText -Text $newText
    if ($null -eq $parsed) {
        throw 'TerminalColors : la modification aurait produit un JSON invalide. Aucun changement ecrit.'
    }
    if ((Get-TcShowTabsInTitlebar -Settings $parsed) -ne $false) {
        throw 'TerminalColors : verification echouee (showTabsInTitlebar non desactive). Aucun changement ecrit.'
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($SettingsPath, 'Desactiver showTabsInTitlebar')) {
        # On memorise l'absence de cle comme une valeur a part entiere, pour que
        # la desinstallation retire la cle au lieu d'ecrire [true].
        if ($null -eq $previous) {
            Set-TcInstallState -Name 'PreviousShowTabsInTitlebar' -Value 'absent'
        } else {
            Set-TcInstallState -Name 'PreviousShowTabsInTitlebar' -Value ([bool]$previous)
        }
        $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
    }

    return [pscustomobject]@{
        SettingsPath  = $SettingsPath
        Changed       = $true
        Changes       = @("showTabsInTitlebar $($applied.Action)")
        Backup        = $backupPath
        RestartNeeded = $true
    }
}

function Uninstall-TerminalColorsTitleBar {
    <#
        .SYNOPSIS
        Remet les onglets dans la barre de titre (comportement par defaut de
        Windows Terminal).

        .DESCRIPTION
        Restaure la valeur de showTabsInTitlebar telle qu'elle etait avant
        Install-TerminalColorsTitleBar, en retirant la cle si elle etait absente.
        Windows Terminal doit etre entierement redemarre.

        .PARAMETER SettingsPath
        Chemin du settings.json a modifier. Detecte automatiquement par defaut.

        .PARAMETER NoBackup
        N'ecrit pas de copie de sauvegarde.

        .EXAMPLE
        Uninstall-TerminalColorsTitleBar
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

    if ((Get-TcShowTabsInTitlebar -Settings $settings) -ne $false) {
        Write-Warning 'TerminalColors : showTabsInTitlebar n''est pas desactive ; rien a faire.'
        return
    }

    $masked = Get-TcMaskedJson -Text $text
    $root = Find-TcJsonRootIndex -Masked $masked
    $restore = Get-TcInstallState -Name 'PreviousShowTabsInTitlebar'

    if ($null -eq $restore -or [string]$restore -eq 'absent') {
        $applied = Remove-TcJsonMember -Text $text -AnchorIndex $root -Name 'showTabsInTitlebar'
        $change = 'showTabsInTitlebar retire'
    } else {
        $literal = 'false'
        if ([bool]$restore) { $literal = 'true' }
        $applied = Set-TcJsonMember -Text $text -AnchorIndex $root -Name 'showTabsInTitlebar' -Literal $literal -Indent '    '
        $change = "showTabsInTitlebar restaure ($literal)"
    }

    $newText = $applied.Text
    if ($null -eq (ConvertFrom-TcJsonText -Text $newText)) {
        throw 'TerminalColors : la modification aurait produit un JSON invalide. Aucun changement ecrit.'
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($SettingsPath, 'Remettre les onglets dans la barre de titre')) {
        $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
        Remove-TcInstallState -Name 'PreviousShowTabsInTitlebar'
    }

    return [pscustomobject]@{
        SettingsPath  = $SettingsPath
        Changed       = $true
        Changes       = @($change)
        Backup        = $backupPath
        RestartNeeded = $true
    }
}

function Test-TerminalColorsTitleBar {
    <#
        .SYNOPSIS
        Indique si Windows Terminal affiche une vraie barre de titre systeme
        (donc colorable en couleur pure par DWM).

        .PARAMETER SettingsPath
        Chemin du settings.json a inspecter. Detecte automatiquement par defaut.

        .EXAMPLE
        Test-TerminalColorsTitleBar
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $SettingsPath)

    if (-not $SettingsPath) { $SettingsPath = Get-TcWtSettingsPath }
    if (-not $SettingsPath -or -not [System.IO.File]::Exists($SettingsPath)) { return $false }

    $settings = ConvertFrom-TcJsonFile -Path $SettingsPath
    if ($null -eq $settings) { return $false }
    return ((Get-TcShowTabsInTitlebar -Settings $settings) -eq $false)
}
