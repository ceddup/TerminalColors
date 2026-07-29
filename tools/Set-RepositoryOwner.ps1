<#
    .SYNOPSIS
    Remplace le jeton OWNER par le vrai compte GitHub dans tout le depot.

    .DESCRIPTION
    Les URL du depot (manifeste, README, badges, modeles d'issue, SECURITY.md)
    sont ecrites avec [OWNER] comme espace reserve, faute de connaitre le compte
    au moment de la mise en place. Ce script les remplace toutes d'un coup :

        .\tools\Set-RepositoryOwner.ps1 -Owner mon-pseudo

    A lancer une seule fois, juste avant le premier push. Le script est
    idempotent : relance sans effet une fois qu'il ne reste plus de jeton.

    .PARAMETER Owner
    Compte ou organisation GitHub qui heberge le depot.

    .PARAMETER Repository
    Nom du depot, si vous l'avez nomme autrement que TerminalColors.

    .EXAMPLE
    .\tools\Set-RepositoryOwner.ps1 -Owner cedric-dupont

    .EXAMPLE
    .\tools\Set-RepositoryOwner.ps1 -Owner ma-societe -WhatIf
    Montre les fichiers qui seraient modifies, sans rien ecrire.
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

# Extensions concernees : on ne touche ni aux binaires ni au dossier .git.
$include = @('*.md', '*.ps1', '*.psd1', '*.psm1', '*.yml', '*.json', '*.sh')

# Ce script contient lui-meme le jeton (dans $token) : s'il se reecrivait, un
# second passage chercherait le mauvais motif. On s'exclut donc explicitement.
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

    if ($PSCmdlet.ShouldProcess($relative, 'Remplacer le jeton OWNER')) {
        # On preserve l'encodage utile : UTF-8 sans BOM partout, sauf la ou un
        # BOM etait deja present (les profils PowerShell en ont besoin).
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
    Write-Host "Aucun jeton OWNER restant : rien a faire." -ForegroundColor Yellow
} else {
    $verb = if ($WhatIfPreference) { 'seraient modifies' } else { 'modifies' }
    Write-Host "$changed fichier(s) $verb -> github.com/$Owner/$Repository" -ForegroundColor Green
}
