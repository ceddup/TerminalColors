# Etat et options du module pour la session courante.

$script:TcEnabled = $false
$script:TcLastPath = $null
$script:TcLastKey = $null
$script:TcLastInfo = $null
$script:TcOriginalTitle = $null
$script:TcOptions = $null

function New-TcDefaultOptions {
    return @{
        # Intensite de la teinte appliquee au fond du terminal (0 = aucune,
        # 1 = couleur pure). Une valeur faible garde le texte parfaitement
        # lisible tout en coloriant nettement l'onglet et la barre de titre.
        Tint           = 0.30
        # PureColor envoie la couleur du projet sans dilution : l'onglet, la
        # barre de titre et la bordure deviennent francs. A n'activer qu'avec le
        # calque opaque installe (Install-TerminalColorsBackdrop), sans quoi
        # c'est le fond du volet qui prend la couleur pure.
        PureColor      = $false
        SetTitle       = $true
        TitleFormat    = '{icon} {name}'
        Icons          = $true
        WindowBorder   = $true
        CaptionColor   = $false
        AutoGitColors  = $true
        BaseBackground = $null
        ExplicitReset  = $false
        # Par defaut la couleur n'est reemise qu'au changement de dossier : zero
        # ecriture inutile. AlwaysReapply la reemet a chaque invite, au cas ou un
        # programme aurait reinitialise le fond du terminal entre-temps.
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
        Dossier courant de l'utilisateur. Un module possede son propre etat de
        session : on lit donc explicitement l'emplacement global.
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
