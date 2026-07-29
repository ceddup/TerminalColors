function Invoke-TerminalColorsDoctor {
    <#
        .SYNOPSIS
        Verifie l'installation et signale ce qui empecherait la coloration de
        fonctionner.

        .DESCRIPTION
        Controle l'environnement (Windows Terminal, version de Windows), le
        theme, le hook de profil, les reglages de profil Windows Terminal
        susceptibles de neutraliser la coloration, et la resolution de couleur
        pour le dossier courant.

        .PARAMETER PassThru
        Renvoie les resultats sous forme d'objets en plus de l'affichage.

        .EXAMPLE
        Invoke-TerminalColorsDoctor
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch] $PassThru)

    $results = New-Object System.Collections.ArrayList

    function Add-Result {
        param([string] $Check, [ValidateSet('OK', 'Attention', 'Probleme', 'Info')] [string] $Status, [string] $Detail)
        [void]$results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
    }

    # --- Environnement ------------------------------------------------------
    if (Test-TcWindowsTerminal) {
        Add-Result 'Windows Terminal' 'OK' "session detectee (WT_SESSION=$($env:WT_SESSION))"
    } else {
        Add-Result 'Windows Terminal' 'Probleme' 'WT_SESSION absent : cette session ne tourne pas dans Windows Terminal, aucune couleur ne sera appliquee.'
    }

    $build = 0
    try { $build = [int][Environment]::OSVersion.Version.Build } catch { }
    if ($build -ge 22000) {
        Add-Result 'Bordure de fenetre' 'OK' "Windows build $build : coloration de bordure disponible."
    } else {
        Add-Result 'Bordure de fenetre' 'Attention' "Windows build $build : la coloration de bordure exige Windows 11 (22000+). L'onglet et la barre de titre fonctionnent quand meme."
    }

    # --- settings.json et theme --------------------------------------------
    $settingsPath = Get-TcWtSettingsPath
    if ($settingsPath) {
        Add-Result 'settings.json' 'OK' $settingsPath

        # On distingue [fichier illisible] de [JSON invalide] : le correctif n'est
        # pas le meme, et sans la cause l'utilisateur ne peut que deviner.
        $text = ''
        $readError = ''
        try { $text = [System.IO.File]::ReadAllText($settingsPath) } catch { $readError = $_.Exception.Message }
        $settings = ConvertFrom-TcJsonText -Text $text

        if ($null -eq $settings) {
            if ($readError) {
                Add-Result 'Theme' 'Probleme' "settings.json illisible ($readError) : impossible de verifier le theme."
            } else {
                Add-Result 'Theme' 'Probleme' 'settings.json contient un JSON invalide : impossible de verifier le theme.'
            }
        } else {
            $installed = $settings.themes | Where-Object { $_.name -eq 'TerminalColors' }
            $selected = ([string]$settings.theme -eq 'TerminalColors')

            if ($installed -and $selected) {
                Add-Result 'Theme' 'OK' 'theme TerminalColors installe et selectionne.'
            } elseif ($installed) {
                Add-Result 'Theme' 'Probleme' "theme present mais non selectionne (theme actuel : [$($settings.theme)]). Lancez Install-TerminalColorsTheme."
            } else {
                Add-Result 'Theme' 'Probleme' 'theme absent : sans lui, l''onglet et la barre de titre ne changent pas de couleur. Lancez Install-TerminalColorsTheme.'
            }

            # --- Calque opaque ----------------------------------------------
            # C'est lui qui permet la couleur pure sur l'onglet sans colorer le
            # volet. L'incoherence a signaler en priorite est -PureColor sans
            # calque : le volet prendrait la couleur pleine du projet.
            $backdrop = Test-TerminalColorsBackdrop -SettingsPath $settingsPath
            $pureColor = [bool]($script:TcOptions -and $script:TcOptions.PureColor)

            if ($backdrop.Installed) {
                if (-not $backdrop.ImageExists) {
                    Add-Result 'Calque opaque' 'Probleme' "l''image [$($backdrop.ImagePath)] est declaree mais absente du disque : le volet prendra la couleur pure du projet. Relancez Install-TerminalColorsBackdrop."
                } elseif (-not $pureColor) {
                    Add-Result 'Calque opaque' 'Attention' "installe (volet fige a $($backdrop.Color)) mais la session dilue encore la couleur : ajoutez -PureColor a Enable-TerminalColors pour un onglet franc."
                } else {
                    Add-Result 'Calque opaque' 'OK' "actif : volet fige a $($backdrop.Color), onglet et barre de titre en couleur pure."
                }

                if ($backdrop.ProfileOverrides.Count -gt 0) {
                    Add-Result 'Calque opaque' 'Attention' "ces profils declarent leur propre image de fond et ignorent donc le calque : $($backdrop.ProfileOverrides -join ', ')."
                }
            } elseif ($backdrop.ForeignImage) {
                Add-Result 'Calque opaque' 'Attention' "une image de fond personnelle est declaree [$($backdrop.ImagePath)] : le calque n''est pas installe. Install-TerminalColorsBackdrop -Force la remplacerait (elle serait restaurable)."
            } elseif ($pureColor) {
                Add-Result 'Calque opaque' 'Probleme' 'absent alors que -PureColor est actif : le fond du volet prend la couleur pleine du projet. Lancez Install-TerminalColorsBackdrop, ou retirez -PureColor.'
            } else {
                Add-Result 'Calque opaque' 'Info' 'non installe : la couleur est diluee sur le fond du volet (comportement d''origine). Install-TerminalColorsBackdrop la rend franche sur l''onglet.'
            }

            # --- Barre de titre systeme -------------------------------------
            $systemTitleBar = ((Get-TcJsonProperty -InputObject $settings -Name 'showTabsInTitlebar') -eq $false)
            $captionColor = [bool]($script:TcOptions -and $script:TcOptions.CaptionColor)
            if ($systemTitleBar -and -not $captionColor) {
                Add-Result 'Barre de titre' 'Attention' 'barre de titre systeme active (showTabsInTitlebar: false) mais -CaptionColor absent : elle gardera la couleur du systeme.'
            } elseif ($systemTitleBar) {
                Add-Result 'Barre de titre' 'OK' 'barre de titre systeme coloree en couleur pure par DWM.'
            } elseif ($captionColor) {
                Add-Result 'Barre de titre' 'Info' '-CaptionColor est actif mais les onglets sont dans la barre de titre : aucun effet visible. Install-TerminalColorsTitleBar sort les onglets de la barre de titre.'
            }

            $wtProfile = Get-TcWtProfile -Settings $settings -ProfileId $env:WT_PROFILE_ID
            if ($wtProfile) {
                if ($wtProfile.tabColor) {
                    Add-Result 'Profil WT' 'Probleme' "[tabColor] ($($wtProfile.tabColor)) est defini sur ce profil : il prend le pas sur le theme et fige la couleur de l''onglet. Retirez-le."
                }
                if ($wtProfile.suppressApplicationTitle) {
                    Add-Result 'Profil WT' 'Attention' '[suppressApplicationTitle] est actif : le titre de l''onglet ne suivra pas le projet (la couleur, si).'
                }
                if ($wtProfile.tabTitle) {
                    Add-Result 'Profil WT' 'Attention' "[tabTitle] ($($wtProfile.tabTitle)) est defini : il peut figer le titre de l''onglet."
                }
            }
        }
    } else {
        Add-Result 'settings.json' 'Probleme' 'introuvable. Lancez Windows Terminal une fois, puis Install-TerminalColorsTheme.'
    }

    # --- Session ------------------------------------------------------------
    $base = Get-TcBaseBackground
    Add-Result 'Fond de reference' 'Info' "$(ConvertTo-TcHex -Rgb $base) (sert de base au melange ; forcable avec -BaseBackground)"

    if (Test-TerminalColorsEnabled) {
        $options = Get-TcOptions
        $mode = "teinte $($options.Tint)"
        if ($options.PureColor) { $mode = 'couleur pure' }
        Add-Result 'Session' 'OK' "coloration active ($mode, titre $(if ($options.SetTitle) { 'oui' } else { 'non' }), bordure $(if ($options.WindowBorder) { 'oui' } else { 'non' }))"
    } else {
        Add-Result 'Session' 'Attention' 'coloration inactive dans cette session. Lancez Enable-TerminalColors.'
    }

    if (Test-TerminalColorsProfile) {
        Add-Result 'Profil PowerShell' 'OK' "bloc present dans $($PROFILE.CurrentUserAllHosts)"
    } else {
        Add-Result 'Profil PowerShell' 'Attention' 'bloc absent : la coloration ne sera pas active au prochain demarrage. Lancez Install-TerminalColorsProfile.'
    }

    if ($script:TcOptions -and $script:TcOptions.WindowBorder -and (Test-TcWindowsTerminal)) {
        $hwnd = Get-TcTerminalWindowHandle
        if ($hwnd -ne [IntPtr]::Zero) {
            Add-Result 'Fenetre du terminal' 'OK' ("handle 0x{0:X}" -f [int64]$hwnd)
        } else {
            Add-Result 'Fenetre du terminal' 'Attention' 'fenetre Windows Terminal non localisee : la bordure ne sera pas coloree (onglet et barre de titre restent fonctionnels).'
        }
    }

    # --- Dossier courant ----------------------------------------------------
    $current = Get-TcCurrentPath
    if ($current) {
        $info = Get-TerminalColor -Path $current
        if ($info.Color) {
            Add-Result 'Dossier courant' 'OK' "$($info.Color) via $($info.Source) -> $($info.SourcePath)"
        } else {
            Add-Result 'Dossier courant' 'Info' "aucune couleur pour [$current] (c''est normal hors projet)."
        }
    }

    # --- Affichage ----------------------------------------------------------
    $colors = @{ 'OK' = 'Green'; 'Attention' = 'Yellow'; 'Probleme' = 'Red'; 'Info' = 'Cyan' }
    $symbols = @{ 'OK' = '[ok]'; 'Attention' = '[! ]'; 'Probleme' = '[KO]'; 'Info' = '[i ]' }

    Write-Host ''
    Write-Host '  TerminalColors - diagnostic' -ForegroundColor White
    Write-Host '  ---------------------------' -ForegroundColor DarkGray
    foreach ($r in $results) {
        Write-Host ('  {0} ' -f $symbols[$r.Status]) -ForegroundColor $colors[$r.Status] -NoNewline
        Write-Host ('{0,-20}' -f $r.Check) -ForegroundColor White -NoNewline
        Write-Host $r.Detail -ForegroundColor Gray
    }
    Write-Host ''

    if ($PassThru) { return $results }
}
