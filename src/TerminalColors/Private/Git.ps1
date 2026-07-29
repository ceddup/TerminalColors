# Detection Git par lecture de fichiers uniquement : aucun appel a git.exe, afin
# que le hook d'invite reste sous la milliseconde.

function Get-TcGitDirectory {
    <#
        .SYNOPSIS
        Renvoie le chemin du repertoire .git associe a un dossier (gere les
        worktrees, ou .git est un fichier contenant [gitdir: ...]).
    #>
    [CmdletBinding()]
    param([string] $Path)

    $candidate = Join-Path $Path '.git'

    if ([System.IO.Directory]::Exists($candidate)) { return $candidate }

    if ([System.IO.File]::Exists($candidate)) {
        try {
            $content = [System.IO.File]::ReadAllText($candidate)
        } catch { return $null }
        $m = [regex]::Match($content, '^\s*gitdir:\s*(.+?)\s*$', 'Multiline')
        if ($m.Success) {
            $target = $m.Groups[1].Value
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $target = [System.IO.Path]::GetFullPath((Join-Path $Path $target))
            }
            if ([System.IO.Directory]::Exists($target)) { return $target }
        }
    }

    return $null
}

function Test-TcGitRoot {
    [CmdletBinding()]
    param([string] $Path)
    return $null -ne (Get-TcGitDirectory -Path $Path)
}

function Get-TcGitBranch {
    <#
        .SYNOPSIS
        Nom de la branche courante lue dans .git/HEAD. Renvoie $null si detachee
        ou introuvable.
    #>
    [CmdletBinding()]
    param([string] $Path)

    $gitDir = Get-TcGitDirectory -Path $Path
    if (-not $gitDir) { return $null }

    $head = Join-Path $gitDir 'HEAD'
    if (-not [System.IO.File]::Exists($head)) { return $null }

    try {
        $content = ([System.IO.File]::ReadAllText($head)).Trim()
    } catch { return $null }

    if ($content -match '^ref:\s*refs/heads/(.+)$') { return $Matches[1].Trim() }
    return $null   # HEAD detachee
}
