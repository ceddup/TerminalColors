<#
    .SYNOPSIS
    Replaces the OWNER placeholder with the real GitHub account across the whole
    repository.

    .DESCRIPTION
    The repository URLs (manifest, README, badges, issue templates, SECURITY.md)
    are written with [OWNER] as a placeholder, since the account is not known when
    the scaffolding is created. This script replaces them all at once:

        .\tools\Set-RepositoryOwner.ps1 -Owner my-handle

    Run it once, just before the first push. The script is idempotent: running it
    again does nothing once no placeholder is left.

    .PARAMETER Owner
    GitHub account or organisation hosting the repository.

    .PARAMETER Repository
    Repository name, if you named it something other than TerminalColors.

    .EXAMPLE
    .\tools\Set-RepositoryOwner.ps1 -Owner ceddup

    .EXAMPLE
    .\tools\Set-RepositoryOwner.ps1 -Owner my-company -WhatIf
    Shows which files would be modified, without writing anything.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$')]
    [string] $Owner,

    [string] $Repository = 'TerminalColors'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent

# Extensions considered: neither binaries nor the .git folder are touched.
$include = @('*.md', '*.ps1', '*.psd1', '*.psm1', '*.yml', '*.json', '*.sh')

# This script itself contains the placeholder (in $token): if it rewrote itself, a
# second run would look for the wrong pattern. So it excludes itself explicitly.
$files = Get-ChildItem -Path $root -Recurse -File -Include $include |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -ne $PSCommandPath }

$changed = 0
$token = 'github.com/OWNER/TerminalColors'
$replacement = "github.com/$Owner/$Repository"

foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    if ($text -notlike "*$token*") { continue }

    $new = $text.Replace($token, $replacement)
    $relative = $file.FullName.Substring($root.Length + 1)

    if ($PSCmdlet.ShouldProcess($relative, 'Replace the OWNER placeholder')) {
        # Preserve the meaningful encoding: UTF-8 without BOM everywhere, except
        # where a BOM was already present (PowerShell profiles need one).
        $hasBom = $false
        $head = New-Object byte[] 3
        $stream = [System.IO.File]::OpenRead($file.FullName)
        try {
            $read = $stream.Read($head, 0, 3)
            $hasBom = ($read -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)
        } finally {
            $stream.Dispose()
        }

        [System.IO.File]::WriteAllText($file.FullName, $new, (New-Object System.Text.UTF8Encoding($hasBom)))
    }

    Write-Host "  $relative" -ForegroundColor DarkGray
    $changed++
}

Write-Host ''
if ($changed -eq 0) {
    Write-Host 'No OWNER placeholder left: nothing to do.' -ForegroundColor Yellow
} else {
    $verb = if ($WhatIfPreference) { 'would be modified' } else { 'modified' }
    Write-Host "$changed file(s) $verb -> github.com/$Owner/$Repository" -ForegroundColor Green
}
