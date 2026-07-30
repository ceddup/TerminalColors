<#
    .SYNOPSIS
    Installs TerminalColors from a clone: the module, then the whole setup.

    .DESCRIPTION
    Run this from a clone (or an extracted archive) of the repository:

        .\install.ps1

    The script copies the module into your user PowerShell modules (5.1 and 7 if
    present), then hands over to Install-TerminalColors for the rest: the Windows
    Terminal theme, the opaque backdrop, the block in your PowerShell profile, and
    the activation of the current session.

    That hand-over is deliberate: the setup logic lives in the module, so installing
    from a clone and installing from the PowerShell Gallery do exactly the same
    thing.

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
    system title bar, coloured by DWM. Requires Windows Terminal to be closed
    completely to take effect.

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
    Keeps the diluted rendering: the colour lands on the pane background rather
    than on the tab.
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

Write-Host ''
Write-Host "  TerminalColors $version - copying the module" -ForegroundColor White
Write-Host '  =========================================' -ForegroundColor DarkGray
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

# --- 3. The rest is the module's job -----------------------------------------
# -WhatIf is forwarded explicitly: preference variables do not cross a module
# boundary, so the $WhatIfPreference set here would not be seen by the module's
# commands.
Install-TerminalColors `
    -SkipTheme:$SkipTheme `
    -SkipBackdrop:$SkipBackdrop `
    -SystemTitleBar:$SystemTitleBar `
    -SkipProfile:$SkipProfile `
    -EnableArguments $EnableArguments `
    -Force:$Force `
    -WhatIf:$WhatIfPreference
