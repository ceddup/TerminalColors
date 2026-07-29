$script:TcProfileBeginMarker = '# >>> TerminalColors >>>'
$script:TcProfileEndMarker = '# <<< TerminalColors <<<'

function Get-TcProfileBlock {
    param([string] $EnableArguments)

    $call = 'Enable-TerminalColors'
    if ($EnableArguments) { $call = "Enable-TerminalColors $EnableArguments" }

    return @(
        $script:TcProfileBeginMarker
        '# Coloration automatique du terminal selon le dossier courant.'
        '# Bloc gere par TerminalColors : Install-TerminalColorsProfile le remplace,'
        '# Uninstall-TerminalColorsProfile le supprime. Vous pouvez aussi le modifier'
        '# a la main (par exemple pour changer -Tint).'
        '# Le test sur WT_SESSION evite tout cout de demarrage hors Windows Terminal ;'
        '# retirez-le pour colorer aussi d''autres terminaux compatibles.'
        'if ($env:WT_SESSION) {'
        '    Import-Module TerminalColors -ErrorAction SilentlyContinue'
        "    if (Get-Module TerminalColors) { $call }"
        '}'
        $script:TcProfileEndMarker
    ) -join [Environment]::NewLine
}

function Install-TerminalColorsProfile {
    <#
        .SYNOPSIS
        Ajoute (ou met a jour) l'activation de TerminalColors dans votre profil
        PowerShell, pour que la coloration soit active a chaque ouverture de
        terminal.

        .DESCRIPTION
        Le bloc insere est delimite par des marqueurs, ce qui permet de le
        remettre a jour ou de le retirer proprement sans toucher au reste de
        votre profil. Une sauvegarde du profil est creee avant modification.

        .PARAMETER ProfilePath
        Profil a modifier. Par defaut, le profil [tous les hotes] de
        l'utilisateur courant ($PROFILE.CurrentUserAllHosts).

        .PARAMETER EnableArguments
        Arguments a passer a Enable-TerminalColors dans le profil.
        Exemple : '-Tint 0.45 -NoWindowBorder'

        .PARAMETER NoBackup
        N'ecrit pas de copie de sauvegarde.

        .EXAMPLE
        Install-TerminalColorsProfile

        .EXAMPLE
        Install-TerminalColorsProfile -EnableArguments '-Tint 0.45'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $ProfilePath,
        [string] $EnableArguments,
        [switch] $NoBackup
    )

    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
    $block = Get-TcProfileBlock -EnableArguments $EnableArguments

    $existing = ''
    if ([System.IO.File]::Exists($ProfilePath)) {
        $existing = [System.IO.File]::ReadAllText($ProfilePath)
    }

    $pattern = '(?s)' + [regex]::Escape($script:TcProfileBeginMarker) + '.*?' + [regex]::Escape($script:TcProfileEndMarker)
    $action = 'Ajouter'

    if ([regex]::IsMatch($existing, $pattern)) {
        $newContent = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block })
        $action = 'Mettre a jour'
    } elseif ([string]::IsNullOrWhiteSpace($existing)) {
        $newContent = $block + [Environment]::NewLine
    } else {
        $separator = [Environment]::NewLine
        if (-not $existing.EndsWith([Environment]::NewLine)) { $separator = [Environment]::NewLine + [Environment]::NewLine }
        $newContent = $existing + $separator + $block + [Environment]::NewLine
    }

    if ($newContent -eq $existing) {
        return [pscustomobject]@{ ProfilePath = $ProfilePath; Changed = $false; Action = 'Aucun changement'; Backup = $null }
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($ProfilePath, "$action le bloc TerminalColors")) {
        $directory = Split-Path $ProfilePath -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        if (-not $NoBackup -and [System.IO.File]::Exists($ProfilePath)) {
            $backupPath = '{0}.terminalcolors-backup-{1}' -f $ProfilePath, (Get-Date -Format 'yyyyMMdd-HHmmss')
            [System.IO.File]::Copy($ProfilePath, $backupPath, $true)
        }
        # UTF-8 avec BOM : Windows PowerShell 5.1 lit les profils dans la page de
        # code ANSI en l'absence de BOM, ce qui casserait les accents.
        $encoding = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($ProfilePath, $newContent, $encoding)
    }

    return [pscustomobject]@{ ProfilePath = $ProfilePath; Changed = $true; Action = $action; Backup = $backupPath }
}

function Uninstall-TerminalColorsProfile {
    <#
        .SYNOPSIS
        Retire le bloc TerminalColors de votre profil PowerShell.

        .PARAMETER ProfilePath
        Profil a modifier. Par defaut, $PROFILE.CurrentUserAllHosts.

        .EXAMPLE
        Uninstall-TerminalColorsProfile
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $ProfilePath)

    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
    if (-not [System.IO.File]::Exists($ProfilePath)) {
        Write-Warning "TerminalColors : profil introuvable [$ProfilePath]."
        return
    }

    $existing = [System.IO.File]::ReadAllText($ProfilePath)
    $pattern = '(?s)\s*' + [regex]::Escape($script:TcProfileBeginMarker) + '.*?' + [regex]::Escape($script:TcProfileEndMarker)
    if (-not [regex]::IsMatch($existing, $pattern)) {
        Write-Warning 'TerminalColors : aucun bloc TerminalColors dans ce profil.'
        return
    }

    $newContent = [regex]::Replace($existing, $pattern, '')
    if ($PSCmdlet.ShouldProcess($ProfilePath, 'Retirer le bloc TerminalColors')) {
        $encoding = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($ProfilePath, $newContent, $encoding)
    }
}

function Test-TerminalColorsProfile {
    <#
        .SYNOPSIS
        Indique si le bloc TerminalColors est present dans un profil PowerShell.

        .PARAMETER ProfilePath
        Profil a inspecter. Par defaut, $PROFILE.CurrentUserAllHosts.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $ProfilePath)

    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
    if (-not [System.IO.File]::Exists($ProfilePath)) { return $false }
    $existing = [System.IO.File]::ReadAllText($ProfilePath)
    return $existing.Contains($script:TcProfileBeginMarker)
}
