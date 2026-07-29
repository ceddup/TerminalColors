function Update-TerminalColor {
    <#
        .SYNOPSIS
        Applique la couleur correspondant au dossier courant.

        .DESCRIPTION
        Appelee automatiquement a chaque affichage de l'invite quand
        Enable-TerminalColors est actif. Ne fait rien si le dossier n'a pas
        change depuis le dernier appel, afin que le cout par invite reste
        negligeable.

        .PARAMETER Path
        Dossier a evaluer. Par defaut, le dossier courant.

        .PARAMETER Force
        Reapplique la couleur meme si rien n'a change.

        .PARAMETER PassThru
        Renvoie l'objet decrivant la couleur resolue.

        .EXAMPLE
        Update-TerminalColor -Force
        Reapplique la couleur, par exemple apres avoir modifie .terminalcolors.json.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string] $Path,

        [switch] $Force,

        [switch] $PassThru
    )

    $options = Get-TcOptions

    if ($Path) {
        try { $target = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { $target = $Path }
    } else {
        $target = Get-TcCurrentPath
    }
    if (-not $target) { return }

    $pathChanged = ($target -ne $script:TcLastPath)

    # Dossier inchange : on ne relit rien. On ne reemet la couleur que si
    # l'utilisateur a demande AlwaysReapply (utile si un programme reinitialise
    # le fond du terminal), sinon on ressort immediatement.
    if (-not $pathChanged -and -not $Force) {
        if ($options.AlwaysReapply) {
            if ($script:TcLastInfo) {
                Set-TcAppearance -Info $script:TcLastInfo -Path $target -Options $options
            } else {
                Reset-TcAppearance -Options $options
            }
        }
        if ($PassThru) { return $script:TcLastInfo }
        return
    }

    if ($Force) { Clear-TcResolveCache }

    $info = Resolve-TcColor -Path $target -AutoGitColors ([bool]$options.AutoGitColors)

    $key = 'none'
    if ($info) { $key = '{0}|{1}' -f $info.Color, $info.Name }

    if ($key -ne $script:TcLastKey -or $Force) {
        if ($info) {
            Set-TcAppearance -Info $info -Path $target -Options $options
        } else {
            Reset-TcAppearance -Options $options
        }
        $script:TcLastKey = $key
    }

    $script:TcLastPath = $target
    $script:TcLastInfo = $info

    if ($PassThru) { return $info }
}

function Get-TcEffectiveBackground {
    <#
        .SYNOPSIS
        Couleur de fond a envoyer au terminal pour un projet donne.

        .DESCRIPTION
        En mode couleur pure, c'est la couleur du projet telle quelle : le calque
        opaque garde le volet lisible, et toute dilution serait contre-productive
        - y compris celle qu'un projet aurait demandee par sa cle [tint].

        Sinon, la couleur est melangee au fond de reference selon la teinte
        demandee, celle du projet ayant la priorite sur celle de la session.

        .PARAMETER BaseBackground
        Fond de reference du melange. Deduit des reglages de Windows Terminal
        s'il n'est pas fourni. Le mode couleur pure ne le lit jamais, ce qui
        evite une lecture de settings.json.
    #>
    [CmdletBinding()]
    param(
        [pscustomobject] $Info,
        [hashtable] $Options,
        [hashtable] $BaseBackground
    )

    if ($Options.PureColor) { return $Info.Rgb }

    $tint = $Options.Tint
    if ($null -ne $Info.Tint) { $tint = [double]$Info.Tint }

    if ($null -eq $BaseBackground) { $BaseBackground = Get-TcBaseBackground }
    return (Get-TcBlendedColor -Base $BaseBackground -Color $Info.Rgb -Amount $tint)
}

function Set-TcAppearance {
    [CmdletBinding()]
    param(
        [pscustomobject] $Info,
        [string] $Path,
        [hashtable] $Options
    )

    # Icone : celle de la configuration, sinon le carre colore le plus proche.
    $icon = [string]$Info.Icon
    if ([string]::IsNullOrEmpty($icon) -and $Options.Icons) {
        $icon = Get-TcColorEmoji -Rgb $Info.Rgb
    }
    $effective = $Info.PSObject.Copy()
    $effective.Icon = $icon

    if (Test-TcVtSupported) {
        Set-TcTerminalBackground -Rgb (Get-TcEffectiveBackground -Info $Info -Options $Options)
    }

    if ($Options.SetTitle) {
        if ($null -eq $script:TcOriginalTitle) { $script:TcOriginalTitle = Get-TcWindowTitle }
        Set-TcWindowTitle -Title (Format-TcTitle -Format $Options.TitleFormat -Info $effective -Path $Path)
    }

    if ($Options.WindowBorder) {
        [void](Set-TcWindowBorderColor -Rgb $Info.Rgb -IncludeCaption:([bool]$Options.CaptionColor))
    }
}

function Reset-TcAppearance {
    [CmdletBinding()]
    param([hashtable] $Options)

    if (Test-TcVtSupported) {
        Reset-TcTerminalBackground -Explicit:([bool]$Options.ExplicitReset)
    }

    if ($Options.SetTitle -and $script:TcOriginalTitle) {
        Set-TcWindowTitle -Title $script:TcOriginalTitle
    }

    if ($Options.WindowBorder) {
        [void](Reset-TcWindowBorderColor -IncludeCaption:([bool]$Options.CaptionColor))
    }
}

function Reset-TerminalColor {
    <#
        .SYNOPSIS
        Restaure l'apparence par defaut du terminal (fond, titre, bordure).

        .PARAMETER Explicit
        Reecrit la couleur de fond deduite des reglages de Windows Terminal au
        lieu d'utiliser la sequence de reinitialisation OSC 111. Utile si votre
        version de Windows Terminal ne gere pas OSC 111.

        .EXAMPLE
        Reset-TerminalColor
    #>
    [CmdletBinding()]
    param([switch] $Explicit)

    $options = (Get-TcOptions).Clone()
    if ($Explicit) { $options.ExplicitReset = $true }

    Reset-TcAppearance -Options $options
    $script:TcLastKey = 'none'
    $script:TcLastPath = $null
}
