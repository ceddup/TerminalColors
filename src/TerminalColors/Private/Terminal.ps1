# Dialogue avec l'emulateur de terminal : sequences OSC et titre de fenetre,
# plus lecture des reglages de Windows Terminal pour connaitre la couleur de
# fond de reference.

$script:TcEsc = [string][char]27
$script:TcBel = [string][char]7

# Fonds des palettes livrees avec Windows Terminal.
$script:TcBuiltInSchemes = @{
    'campbell'            = '#0C0C0C'
    'campbell powershell' = '#012456'
    'vintage'             = '#000000'
    'one half dark'       = '#282C34'
    'one half light'      = '#FAFAFA'
    'solarized dark'      = '#002B36'
    'solarized light'     = '#FDF6E3'
    'tango dark'          = '#000000'
    'tango light'         = '#FFFFFF'
}

$script:TcDefaultBaseBackground = '#0C0C0C'
$script:TcBaseBackgroundCache = $null

function Test-TcWindowsTerminal {
    return -not [string]::IsNullOrEmpty($env:WT_SESSION)
}

function Test-TcVtSupported {
    <#
        .SYNOPSIS
        Determine si l'on peut emettre des sequences OSC sans risque d'afficher
        des caracteres parasites.
    #>
    if (Test-TcWindowsTerminal) { return $true }
    if ($env:TERM_PROGRAM -in @('vscode', 'WezTerm', 'Hyper', 'Tabby')) { return $true }
    if (-not [string]::IsNullOrEmpty($env:WEZTERM_PANE)) { return $true }
    return $false
}

function Get-TcWtSettingsPath {
    <#
        .SYNOPSIS
        Chemin du settings.json de Windows Terminal (Store, Preview, non
        empaquete ou portable).
    #>
    [CmdletBinding()]
    param()

    $candidates = @()
    if ($env:WT_SETTINGS_DIR) { $candidates += (Join-Path $env:WT_SETTINGS_DIR 'settings.json') }
    $local = $env:LOCALAPPDATA
    if ($local) {
        $candidates += Join-Path $local 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        $candidates += Join-Path $local 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'
        $candidates += Join-Path $local 'Microsoft\Windows Terminal\settings.json'
    }

    foreach ($c in $candidates) {
        if ($c -and [System.IO.File]::Exists($c)) { return $c }
    }
    return $null
}

function Get-TcWtProfile {
    <#
        .SYNOPSIS
        Renvoie le profil Windows Terminal actif, fusionne avec profiles.defaults.
    #>
    [CmdletBinding()]
    param($Settings, [string] $ProfileId)

    if ($null -eq $Settings) { return $null }

    $profiles = Get-TcJsonProperty -InputObject $Settings -Name 'profiles'
    if ($null -eq $profiles) { return $null }

    $defaults = Get-TcJsonProperty -InputObject $profiles -Name 'defaults'
    $list = Get-TcJsonProperty -InputObject $profiles -Name 'list'

    $match = $null
    if ($list -and $ProfileId) {
        $match = $list | Where-Object { $_.guid -eq $ProfileId } | Select-Object -First 1
    }
    if (-not $match -and $list) {
        $defaultProfile = Get-TcJsonProperty -InputObject $Settings -Name 'defaultProfile'
        if ($defaultProfile) {
            $match = $list | Where-Object { $_.guid -eq $defaultProfile } | Select-Object -First 1
        }
    }

    $result = @{ background = $null; colorScheme = $null; suppressApplicationTitle = $false; tabColor = $null; tabTitle = $null }
    foreach ($source in @($defaults, $match)) {
        if ($null -eq $source) { continue }
        foreach ($key in @('background', 'colorScheme', 'suppressApplicationTitle', 'tabColor', 'tabTitle')) {
            $value = Get-TcJsonProperty -InputObject $source -Name $key
            if ($null -ne $value) { $result[$key] = $value }
        }
    }
    return $result
}

function Get-TcSettingsBackground {
    <#
        .SYNOPSIS
        Couleur de fond declaree par un settings.json deja analyse : celle du
        profil s'il en fixe une, sinon celle de sa palette. Renvoie $null si le
        document ne permet pas de conclure.
    #>
    [CmdletBinding()]
    param($Settings, [string] $ProfileId)

    $wtProfile = Get-TcWtProfile -Settings $Settings -ProfileId $ProfileId
    if ($null -eq $wtProfile) { return $null }

    if ($wtProfile.background) {
        $rgb = ConvertFrom-TcColor -Value ([string]$wtProfile.background)
        if ($rgb) { return $rgb }
    }

    $schemeName = [string]$wtProfile.colorScheme
    if ([string]::IsNullOrWhiteSpace($schemeName)) { $schemeName = 'Campbell' }

    $schemes = Get-TcJsonProperty -InputObject $Settings -Name 'schemes'
    if ($schemes) {
        $scheme = $schemes | Where-Object { $_.name -eq $schemeName } | Select-Object -First 1
        if ($scheme -and $scheme.background) {
            $rgb = ConvertFrom-TcColor -Value ([string]$scheme.background)
            if ($rgb) { return $rgb }
        }
    }

    $key = $schemeName.ToLowerInvariant()
    if ($script:TcBuiltInSchemes.ContainsKey($key)) {
        return (ConvertFrom-TcColor -Value $script:TcBuiltInSchemes[$key])
    }

    return $null
}

function Get-TcBaseBackground {
    <#
        .SYNOPSIS
        Couleur de fond [normale] du terminal, servant de base au melange.
        Deduite des reglages de Windows Terminal, avec mise en cache.

        .PARAMETER SettingsPath
        Lit ce settings.json au lieu de celui detecte automatiquement. Le cache
        est alors contourne (utilise par les installateurs et les tests).
    #>
    [CmdletBinding()]
    param(
        [switch] $Refresh,
        [string] $SettingsPath
    )

    if (-not $SettingsPath) {
        if ($script:TcOptions -and $script:TcOptions.BaseBackground) {
            $explicit = ConvertFrom-TcColor -Value $script:TcOptions.BaseBackground
            if ($explicit) { return $explicit }
        }
        if (-not $Refresh -and $script:TcBaseBackgroundCache) { return $script:TcBaseBackgroundCache }
        $SettingsPath = Get-TcWtSettingsPath
        $cacheable = $true
    } else {
        $cacheable = $false
    }

    $rgb = $null
    if ($SettingsPath) {
        $rgb = Get-TcSettingsBackground -Settings (ConvertFrom-TcJsonFile -Path $SettingsPath) -ProfileId $env:WT_PROFILE_ID
    }
    if ($null -eq $rgb) { $rgb = ConvertFrom-TcColor -Value $script:TcDefaultBaseBackground }

    if ($cacheable) { $script:TcBaseBackgroundCache = $rgb }
    return $rgb
}

function Write-TcRaw {
    <#
        .SYNOPSIS
        Ecrit une sequence de controle directement sur la console, sans passer
        par le pipeline PowerShell.
    #>
    [CmdletBinding()]
    param([string] $Text)

    try { [Console]::Write($Text) } catch {
        Write-Verbose "TerminalColors: ecriture console impossible ($($_.Exception.Message))"
    }
}

function Get-TcBackgroundSequence {
    <#
        .SYNOPSIS
        Construit la sequence OSC 11 demandant le changement de couleur de fond.
        Format xterm canonique (rgb:rr/gg/bb), compris par Windows Terminal.
    #>
    [CmdletBinding()]
    param([hashtable] $Rgb)

    return ('{0}]11;rgb:{1:x2}/{2:x2}/{3:x2}{4}' -f $script:TcEsc, [int]$Rgb.R, [int]$Rgb.G, [int]$Rgb.B, $script:TcBel)
}

function Get-TcBackgroundResetSequence {
    <#
        .SYNOPSIS
        Sequence OSC 111 : retour a la couleur de fond par defaut du profil.
    #>
    [CmdletBinding()]
    param()

    return ('{0}]111{1}' -f $script:TcEsc, $script:TcBel)
}

function Set-TcTerminalBackground {
    <#
        .SYNOPSIS
        Change la couleur de fond du volet actif (OSC 11). Avec le theme
        Windows Terminal fourni, l'onglet et la barre de titre suivent.
    #>
    [CmdletBinding()]
    param([hashtable] $Rgb)

    Write-TcRaw -Text (Get-TcBackgroundSequence -Rgb $Rgb)
}

function Reset-TcTerminalBackground {
    <#
        .SYNOPSIS
        Restaure le fond par defaut. OSC 111 est la sequence prevue pour cela ;
        en mode explicite on reecrit la couleur de base deduite des reglages.
    #>
    [CmdletBinding()]
    param([switch] $Explicit)

    if ($Explicit) {
        Set-TcTerminalBackground -Rgb (Get-TcBaseBackground)
        return
    }
    Write-TcRaw -Text (Get-TcBackgroundResetSequence)
}

function Set-TcWindowTitle {
    <#
        .SYNOPSIS
        Definit le titre de la fenetre (donc de l'onglet Windows Terminal) via
        l'API console Unicode : contrairement a OSC 0, les emojis passent quelle
        que soit la page de code active.
    #>
    [CmdletBinding()]
    param([string] $Title)

    try { $Host.UI.RawUI.WindowTitle = $Title } catch {
        Write-Verbose "TerminalColors: titre non modifiable ($($_.Exception.Message))"
    }
}

function Get-TcWindowTitle {
    try { return $Host.UI.RawUI.WindowTitle } catch { return $null }
}

function Format-TcTitle {
    <#
        .SYNOPSIS
        Applique le gabarit de titre. Jetons : {icon} {name} {color} {folder} {path}
    #>
    [CmdletBinding()]
    param(
        [string] $Format,
        [pscustomobject] $Info,
        [string] $Path
    )

    $folder = ''
    if ($Path) { $folder = Split-Path $Path -Leaf }

    $title = $Format
    $title = $title.Replace('{icon}', [string]$Info.Icon)
    $title = $title.Replace('{name}', [string]$Info.Name)
    $title = $title.Replace('{color}', [string]$Info.Color)
    $title = $title.Replace('{folder}', $folder)
    $title = $title.Replace('{path}', [string]$Path)

    return $title.Trim()
}
