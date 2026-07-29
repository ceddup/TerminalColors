# Git detection by reading files only: no call to git.exe, so that the prompt hook
# stays below a millisecond.

function Get-TcGitDirectory {
    <#
        .SYNOPSIS
        Returns the path of the .git directory associated with a folder (handles
        worktrees, where .git is a file containing [gitdir: ...]).
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
        Current branch name read from .git/HEAD. Returns $null when detached or
        not found.
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
    return $null   # detached HEAD
}
