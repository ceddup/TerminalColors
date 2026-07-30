<#
    .SYNOPSIS
    Installs TerminalColors: the module, the Windows Terminal theme and the
    profile hook.

    .DESCRIPTION
    Run this from a clone (or an extracted archive) of the repository:

        .\install.ps1

    The script:
      1. copies the module into your user PowerShell modules (5.1 and 7 if
         present);
      2. installs and selects the Windows Terminal theme that makes the tab and
         the title bar follow along;
      3. installs the opaque backdrop, which makes the colour vivid on the tab,
         the title bar and the border without changing the pane background;
      4. adds the activation block to your PowerShell profile;
      5. enables the colouring in the current session.

    No administrator rights are required, and nothing is installed outside your
    user profile.

    .PARAMETER Scope
    CurrentUser (default) installs into your personal modules. AllUsers requires
    administrator rights.

    .PARAMETER SkipTheme
    Does not install the Windows Terminal theme (do it later by hand with
    Install-TerminalColorsTheme).

    .PARAMETER SkipBackdrop
    Does not install the opaque backdrop. The project colour is then diluted onto
    the pane background instead, and the tab stays subtle.

    .PARAMETER SystemTitleBar
    Moves the tabs out of the title bar so that Windows Terminal shows a real
    system title bar, coloured in pure colour by DWM. Requires Windows Terminal to
    be closed completely to take effect.

    .PARAMETER SkipProfile
    Does not modify your PowerShell profile.

    .PARAMETER EnableArguments
    Arguments passed to Enable-TerminalColors in the profile.
    Example: -EnableArguments '-TitleFormat "{icon} {name}" -NoWindowBorder'
    -PureColor is added automatically when the opaque backdrop is installed,
    unless you specify -Tint or -PureColor yourself.

    .PARAMETER Force
    Overwrites an existing installation of the module and reinstalls the theme.

    .EXAMPLE
    .\install.ps1

    .EXAMPLE
    .\install.ps1 -SystemTitleBar
    Adds a coloured system title bar on top of the coloured tab.

    .EXAMPLE
    .\install.ps1 -SkipBackdrop -EnableArguments '-Tint 0.45' -Force
    Keeps the diluted rendering of the 1.0 versions.
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
    throw "Module not found in [$sourceModule]. Run this script from the root of the TerminalColors repository."
}

$manifest = Import-PowerShellDataFile -Path (Join-Path $sourceModule 'TerminalColors.psd1')
$version = [string]$manifest.ModuleVersion

# Message prefix in simulation mode, so no action is announced as done.
$simulated = ''
if ($WhatIfPreference) { $simulated = '(simulation) ' }

Write-Host ''
Write-Host "  TerminalColors $version" -ForegroundColor White
Write-Host '  ============================' -ForegroundColor DarkGray
Write-Host ''

# --- 1. Destinations ---------------------------------------------------------
# Install for every PowerShell edition present on the machine, so that the module
# is available whatever Windows Terminal profile is used.
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
            Write-Warn "Already installed in [$destination] - use -Force to replace it."
            continue
        }
        if ($PSCmdlet.ShouldProcess($destination, 'Remove the existing version')) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($destination, 'Copy the module')) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path (Join-Path $sourceModule '*') -Destination $destination -Recurse -Force
        Write-Step "Module copied to $destination"
    }
}

# --- 2. Loading --------------------------------------------------------------
Remove-Module TerminalColors -Force -ErrorAction SilentlyContinue
if ($WhatIfPreference) {
    # Nothing was copied: load from the repository so the following steps can
    # still show what they would do.
    Import-Module (Join-Path $sourceModule 'TerminalColors.psd1') -Force -ErrorAction Stop
    Write-Step 'Module loaded from the repository (-WhatIf mode)'
} else {
    # Import by name: this also checks that the module really is discoverable.
    Import-Module TerminalColors -Force -ErrorAction Stop
    Write-Step "Module loaded (version $((Get-Module TerminalColors).Version))"
}

# --- 3. Windows Terminal theme ----------------------------------------------
# -WhatIf is forwarded explicitly: preference variables do not cross a module
# boundary, so the $WhatIfPreference set here would not be seen by the module's
# commands.
if (-not $SkipTheme) {
    try {
        $result = Install-TerminalColorsTheme -Force:$Force -WhatIf:$WhatIfPreference
        if ($result.Changed) {
            Write-Step "$($simulated)Windows Terminal theme installed ($($result.Changes -join ', '))"
            if ($result.Backup) { Write-Step "settings.json backup: $($result.Backup)" }
        } else {
            Write-Step 'Windows Terminal theme already in place'
        }
    } catch {
        Write-Warn "Theme not installed: $($_.Exception.Message)"
        Write-Warn 'Without the theme, the tab and the title bar will not change colour.'
    }
} else {
    Write-Warn 'Windows Terminal theme skipped (-SkipTheme).'
}

# --- 3b. Opaque backdrop -----------------------------------------------------
# This is what allows a vivid colour on the tab without colouring the pane: the
# background colour carries the pure project colour (the tab copies it), and a
# solid image of your usual background colour is laid over the pane.
$backdropInstalled = $false
if (-not $SkipBackdrop) {
    try {
        $result = Install-TerminalColorsBackdrop -WhatIf:$WhatIfPreference
        $backdropInstalled = $true
        if ($result.Changed) {
            Write-Step "$($simulated)Opaque backdrop installed: the pane stays $($result.Color)"
            if ($result.Backup) { Write-Step "settings.json backup: $($result.Backup)" }
        } else {
            Write-Step "Opaque backdrop already in place (pane $($result.Color))"
        }
    } catch {
        Write-Warn "Opaque backdrop not installed: $($_.Exception.Message)"
        Write-Warn 'The colour will stay diluted on the pane background.'
    }
} else {
    Write-Warn 'Opaque backdrop skipped (-SkipBackdrop): the colour will be diluted on the pane background.'
}

# --- 3c. System title bar (optional) -----------------------------------------
if ($SystemTitleBar) {
    try {
        $result = Install-TerminalColorsTitleBar -WhatIf:$WhatIfPreference
        if ($result.Changed) {
            Write-Step "$($simulated)System title bar enabled (showTabsInTitlebar: false)"
            Write-Warn 'Close Windows Terminal completely for this setting to take effect.'
        } else {
            Write-Step 'System title bar already enabled'
        }
    } catch {
        Write-Warn "System title bar not enabled: $($_.Exception.Message)"
    }
}

# --- 4. PowerShell profile ---------------------------------------------------
# The opaque backdrop is only useful with -PureColor, so add it - unless the user
# has already expressed their dilution preference.
$effectiveArguments = $EnableArguments
if ($backdropInstalled -and $EnableArguments -notmatch '-(PureColor|Tint)\b') {
    $effectiveArguments = ('-PureColor ' + $EnableArguments).Trim()
}

if (-not $SkipProfile) {
    $profiles = New-Object System.Collections.ArrayList
    [void]$profiles.Add($PROFILE.CurrentUserAllHosts)

    # The other PowerShell edition's profile, if it is installed.
    if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        [void]$profiles.Add((Join-Path $documents 'PowerShell\profile.ps1'))
    } elseif ($PSVersionTable.PSEdition -eq 'Core') {
        [void]$profiles.Add((Join-Path $documents 'WindowsPowerShell\profile.ps1'))
    }

    foreach ($profilePath in ($profiles | Select-Object -Unique)) {
        try {
            $result = Install-TerminalColorsProfile -ProfilePath $profilePath -EnableArguments $effectiveArguments -WhatIf:$WhatIfPreference
            if ($result.Changed) {
                Write-Step "$($simulated)Profile updated: $($result.ProfilePath) ($($result.Action))"
            } else {
                Write-Step "Profile already up to date: $($result.ProfilePath)"
            }
        } catch {
            Write-Warn "Profile [$profilePath] not modified: $($_.Exception.Message)"
        }
    }
} else {
    Write-Warn 'PowerShell profile skipped (-SkipProfile).'
}

# --- 5. Immediate activation -------------------------------------------------
if ($WhatIfPreference) {
    Write-Warn '-WhatIf mode: nothing was written, and this session was not modified.'
} elseif ($env:WT_SESSION) {
    if ($effectiveArguments) {
        Write-Step "Enabling with: $effectiveArguments"
        # The arguments come from the user's own command line: forward them
        # as-is to the activation command.
        Invoke-Expression "Enable-TerminalColors $effectiveArguments"
    } else {
        Enable-TerminalColors
    }
    Write-Step 'Colouring active in this session'
} else {
    Write-Warn 'Not a Windows Terminal session: open Windows Terminal to see the result.'
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
Write-Host '  To check:         ' -NoNewline; Write-Host 'Invoke-TerminalColorsDoctor' -ForegroundColor White
Write-Host '  To try it:        ' -NoNewline; Write-Host 'cd <a Git repository> and look at the tab' -ForegroundColor White
Write-Host '  To pick a colour: ' -NoNewline; Write-Host 'Set-FolderColor ''#215732''' -ForegroundColor White
Write-Host ''
