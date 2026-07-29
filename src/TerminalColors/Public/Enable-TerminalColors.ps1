function Enable-TerminalColors {
    <#
        .SYNOPSIS
        Active la coloration automatique du terminal selon le dossier courant.

        .DESCRIPTION
        Enveloppe la fonction [prompt] existante : a chaque affichage de
        l'invite, la couleur associee au dossier courant est appliquee. L'invite
        d'origine (oh-my-posh, Starship, personnalisee...) est conservee et
        restaurable par Disable-TerminalColors.

        A placer dans votre profil PowerShell, apres l'initialisation de votre
        invite si vous en utilisez une.

        .PARAMETER Tint
        Intensite de la teinte appliquee au fond du terminal, de 0 a 1.
        La valeur par defaut (0,30) colore nettement l'onglet et la barre de
        titre tout en gardant un fond sombre et lisible. Ignore si -PureColor
        est actif.

        .PARAMETER PureColor
        Envoie la couleur du projet sans aucune dilution : l'onglet, la barre de
        titre et la bordure prennent la couleur exacte du projet.

        A n'utiliser qu'avec le calque opaque installe
        (Install-TerminalColorsBackdrop), qui garde le fond du volet inchange.
        Sans lui, c'est le volet entier qui prendrait la couleur pure et le texte
        deviendrait illisible. Invoke-TerminalColorsDoctor signale la
        combinaison incoherente.

        .PARAMETER TitleFormat
        Gabarit du titre d'onglet. Jetons disponibles : {icon}, {name}, {color},
        {folder}, {path}.

        .PARAMETER NoTitle
        Ne modifie pas le titre de l'onglet.

        .PARAMETER NoIcons
        N'ajoute pas de carre colore devant le nom du projet.

        .PARAMETER NoWindowBorder
        Ne colore pas la bordure de la fenetre (evite l'appel a DWM).

        .PARAMETER CaptionColor
        Colore aussi la barre de titre systeme. N'a d'effet visible que si
        [showTabsInTitlebar] est desactive dans Windows Terminal.

        .PARAMETER NoAutoGitColors
        Desactive la couleur automatique deduite du nom du depot Git. Seules les
        couleurs explicites (.terminalcolors.json, Peacock, Solution Colors)
        seront utilisees.

        .PARAMETER BaseBackground
        Force la couleur de fond de reference servant au melange, au lieu de la
        deduire des reglages de Windows Terminal.

        .PARAMETER ExplicitReset
        En quittant un dossier colore, reecrit la couleur de fond de reference
        au lieu d'emettre la sequence de reinitialisation OSC 111.

        .PARAMETER AlwaysReapply
        Reemet la couleur a chaque affichage de l'invite, et non seulement au
        changement de dossier. A activer si un programme que vous lancez
        reinitialise la couleur de fond du terminal.

        .EXAMPLE
        Enable-TerminalColors

        .EXAMPLE
        Enable-TerminalColors -PureColor
        Couleur franche sur l'onglet, la barre de titre et la bordure, fond du
        volet inchange. Demande Install-TerminalColorsBackdrop.

        .EXAMPLE
        Enable-TerminalColors -Tint 0.45 -TitleFormat '{icon} {name} ({folder})'

        .EXAMPLE
        Enable-TerminalColors -NoWindowBorder -NoAutoGitColors
        N'utilise que les couleurs declarees explicitement, sans toucher a la
        bordure de la fenetre.
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
        throw "TerminalColors : couleur de fond de reference invalide [$BaseBackground]."
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
        # On memorise l'invite existante pour pouvoir la restaurer.
        $existing = Get-Command -Name prompt -CommandType Function -ErrorAction SilentlyContinue
        if ($existing) {
            $global:TerminalColorsOriginalPrompt = $existing.ScriptBlock
        } else {
            $global:TerminalColorsOriginalPrompt = $null
        }

        # Le bloc est cree hors du module pour s'executer dans la portee globale,
        # exactement comme l'invite d'origine.
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
        Desactive la coloration automatique et restaure l'invite d'origine.

        .PARAMETER KeepColor
        Conserve la couleur actuellement appliquee au lieu de reinitialiser
        l'apparence du terminal.

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
        Indique si la coloration automatique est active dans cette session.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]$script:TcEnabled
}
