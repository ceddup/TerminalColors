# Dialogue with the terminal emulator: OSC sequences and window title, plus
# reading the Windows Terminal settings to find the reference background colour.

$script:TcEsc = [string][char]27
$script:TcBel = [string][char]7

# Backgrounds of the colour schemes shipped with Windows Terminal.
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

# Titles this session has set on its tab, most recent first (see Set-TcWindowTitle).
$script:TcAppliedTitles = @()

function Test-TcWindowsTerminal {
    return -not [string]::IsNullOrEmpty($env:WT_SESSION)
}

function Test-TcVtSupported {
    <#
        .SYNOPSIS
        Determines whether OSC sequences can be emitted without risking stray
        characters on screen.
    #>
    if (Test-TcWindowsTerminal) { return $true }
    if ($env:TERM_PROGRAM -in @('vscode', 'WezTerm', 'Hyper', 'Tabby')) { return $true }
    if (-not [string]::IsNullOrEmpty($env:WEZTERM_PANE)) { return $true }
    return $false
}

function Get-TcWtSettingsPath {
    <#
        .SYNOPSIS
        Path of the Windows Terminal settings.json (Store, Preview, unpackaged or
        portable).
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
        Returns the active Windows Terminal profile, merged with profiles.defaults.
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
        Background colour declared by an already-parsed settings.json: the
        profile's if it sets one, otherwise its colour scheme's. Returns $null when
        the document does not allow a conclusion.
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
        The terminal's [normal] background colour, used as the blending base.
        Derived from the Windows Terminal settings, and cached.

        .PARAMETER SettingsPath
        Reads this settings.json instead of the automatically detected one. The
        cache is then bypassed (used by the installers and the tests).
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
        Writes a control sequence directly to the console, bypassing the PowerShell
        pipeline.
    #>
    [CmdletBinding()]
    param([string] $Text)

    try { [Console]::Write($Text) } catch {
        Write-Verbose "TerminalColors: could not write to the console ($($_.Exception.Message))"
    }
}

function Get-TcBackgroundSequence {
    <#
        .SYNOPSIS
        Builds the OSC 11 sequence requesting the background colour change.
        Canonical xterm format (rgb:rr/gg/bb), understood by Windows Terminal.
    #>
    [CmdletBinding()]
    param([hashtable] $Rgb)

    return ('{0}]11;rgb:{1:x2}/{2:x2}/{3:x2}{4}' -f $script:TcEsc, [int]$Rgb.R, [int]$Rgb.G, [int]$Rgb.B, $script:TcBel)
}

function Get-TcBackgroundResetSequence {
    <#
        .SYNOPSIS
        OSC 111 sequence: back to the profile's default background colour.
    #>
    [CmdletBinding()]
    param()

    return ('{0}]111{1}' -f $script:TcEsc, $script:TcBel)
}

function Set-TcTerminalBackground {
    <#
        .SYNOPSIS
        Changes the active pane's background colour (OSC 11). With the supplied
        Windows Terminal theme, the tab and the title bar follow.
    #>
    [CmdletBinding()]
    param([hashtable] $Rgb)

    Write-TcRaw -Text (Get-TcBackgroundSequence -Rgb $Rgb)
}

function Reset-TcTerminalBackground {
    <#
        .SYNOPSIS
        Restores the default background. OSC 111 is the sequence meant for that; in
        explicit mode the base colour derived from the settings is rewritten instead.
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
        Sets the window title (and therefore the Windows Terminal tab title) through
        the Unicode console API: unlike OSC 0, emoji get through whatever the active
        code page is.
    #>
    [CmdletBinding()]
    param([string] $Title)

    try {
        $Host.UI.RawUI.WindowTitle = $Title
        # Remember the last two titles we set. Windows Terminal mirrors the active
        # tab's title onto the window title with a small delay, so right after a
        # change the window can still be showing the previous one - which
        # Test-TcActiveTab must not read as [this tab is not the active one].
        $script:TcAppliedTitles = @(@($Title) + @($script:TcAppliedTitles | Select-Object -First 1))
    } catch {
        Write-Verbose "TerminalColors: title could not be changed ($($_.Exception.Message))"
    }
}

function Get-TcWindowTitle {
    try { return $Host.UI.RawUI.WindowTitle } catch { return $null }
}

function Format-TcTitle {
    <#
        .SYNOPSIS
        Applies the title template. Tokens: {icon} {name} {color} {folder} {path}
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
