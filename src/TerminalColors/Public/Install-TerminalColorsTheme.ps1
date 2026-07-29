# Installation du theme Windows Terminal qui fait suivre l'onglet et la barre de
# titre a la couleur de fond du volet actif.
#
# Les outils d'edition chirurgicale de settings.json sont dans
# Private\WtSettings.ps1, partages avec Install-TerminalColorsBackdrop et
# Install-TerminalColorsTitleBar.

$script:TcThemeName = 'TerminalColors'

function Get-TcThemeJson {
    param([string] $Indent = '    ')

    $lines = @(
        '{',
        '    "name": "TerminalColors",',
        '    "tab":',
        '    {',
        '        "background": "terminalBackground",',
        '        "unfocusedBackground": "terminalBackground"',
        '    },',
        '    "tabRow":',
        '    {',
        '        "background": "terminalBackground",',
        '        "unfocusedBackground": "terminalBackground"',
        '    },',
        '    "window":',
        '    {',
        '        "applicationTheme": "system"',
        '    }',
        '}'
    )
    return ($lines -join ([Environment]::NewLine + $Indent + $Indent))
}

function Test-TcThemeInstalled {
    param([string] $Text)
    $masked = Get-TcMaskedJson -Text $Text
    return [regex]::IsMatch($masked, '"name"\s*:\s*"TerminalColors"')
}

function Install-TerminalColorsTheme {
    <#
        .SYNOPSIS
        Installe le theme [TerminalColors] dans Windows Terminal et l'active.

        .DESCRIPTION
        C'est ce theme qui rend la coloration visible : il indique a Windows
        Terminal de peindre l'onglet et la barre de titre avec la couleur de
        fond du volet actif. Le module changeant cette couleur de fond a chaque
        changement de dossier, l'onglet et la barre de titre suivent
        automatiquement.

        settings.json est modifie par insertion ciblee, avec sauvegarde
        prealable et validation du resultat avant ecriture.

        .PARAMETER SettingsPath
        Chemin du settings.json a modifier. Detecte automatiquement par defaut
        (versions Store, Preview, non empaquetee et portable).

        .PARAMETER Force
        Reinstalle le theme meme s'il est deja present.

        .PARAMETER NoBackup
        N'ecrit pas de copie de sauvegarde.

        .EXAMPLE
        Install-TerminalColorsTheme

        .EXAMPLE
        Install-TerminalColorsTheme -WhatIf
        Montre ce qui serait modifie sans rien ecrire.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string] $SettingsPath,
        [switch] $Force,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    if ($null -eq (ConvertFrom-TcJsonText -Text $text)) {
        throw "TerminalColors : [$SettingsPath] n'est pas un JSON valide. Corrigez-le avant d'installer le theme."
    }

    $alreadyInstalled = Test-TcThemeInstalled -Text $text
    if ($alreadyInstalled -and -not $Force) {
        Write-Verbose 'TerminalColors: theme deja present, seule la selection est verifiee.'
    }

    $newText = $text
    $masked = Get-TcMaskedJson -Text $newText
    $changes = @()

    # --- 1. Retirer une version precedente du theme si -Force ---------------
    if ($alreadyInstalled -and $Force) {
        $m = [regex]::Match($masked, '"name"\s*:\s*"TerminalColors"')
        $span = Find-TcJsonObjectSpan -Text $masked -Index $m.Index
        if ($span) {
            $start = $span.Start
            $end = $span.End
            # Absorber la virgule adjacente pour garder un tableau valide
            $after = $end + 1
            while ($after -lt $masked.Length -and [char]::IsWhiteSpace($masked[$after])) { $after++ }
            if ($after -lt $masked.Length -and $masked[$after] -eq ',') {
                $end = $after
            } else {
                $before = $start - 1
                while ($before -ge 0 -and [char]::IsWhiteSpace($masked[$before])) { $before-- }
                if ($before -ge 0 -and $masked[$before] -eq ',') { $start = $before }
            }
            $newText = $newText.Remove($start, $end - $start + 1)
            $masked = Get-TcMaskedJson -Text $newText
            $changes += 'ancien theme retire'
            $alreadyInstalled = $false
        }
    }

    # --- 2. Inserer le theme dans le tableau "themes" -----------------------
    if (-not $alreadyInstalled) {
        $themeJson = Get-TcThemeJson
        $m = [regex]::Match($masked, '"themes"\s*:\s*\[')
        if ($m.Success) {
            $insertAt = $m.Index + $m.Length
            $probe = $insertAt
            while ($probe -lt $masked.Length -and [char]::IsWhiteSpace($masked[$probe])) { $probe++ }
            $needsComma = ($probe -lt $masked.Length -and $masked[$probe] -ne ']')

            $fragment = [Environment]::NewLine + '        ' + $themeJson
            if ($needsComma) { $fragment += ',' } else { $fragment += [Environment]::NewLine + '    ' }
            $newText = $newText.Insert($insertAt, $fragment)
            $changes += 'theme ajoute a "themes"'
        } else {
            $rootBrace = $masked.IndexOf('{')
            if ($rootBrace -lt 0) { throw 'TerminalColors : structure de settings.json inattendue.' }
            $fragment = [Environment]::NewLine + '    "themes":' + [Environment]::NewLine + '    [' +
                        [Environment]::NewLine + '        ' + $themeJson + [Environment]::NewLine + '    ],'
            $newText = $newText.Insert($rootBrace + 1, $fragment)
            $changes += 'section "themes" creee'
        }
        $masked = Get-TcMaskedJson -Text $newText
    }

    # --- 3. Selectionner le theme ------------------------------------------
    $previousTheme = $null
    $m = [regex]::Match($masked, '"theme"\s*:\s*(?:"[^"]*"|\{[^{}]*\})')
    if ($m.Success) {
        $currentValue = $newText.Substring($m.Index, $m.Length)
        if ($currentValue -notmatch '"TerminalColors"') {
            $vm = [regex]::Match($currentValue, '"theme"\s*:\s*(.+)$', 'Singleline')
            if ($vm.Success) { $previousTheme = $vm.Groups[1].Value.Trim() }
            $newText = $newText.Remove($m.Index, $m.Length).Insert($m.Index, '"theme": "TerminalColors"')
            $changes += 'theme selectionne'
        }
    } else {
        $rootBrace = $masked.IndexOf('{')
        $newText = $newText.Insert($rootBrace + 1, [Environment]::NewLine + '    "theme": "TerminalColors",')
        $changes += 'theme selectionne'
    }

    if ($changes.Count -eq 0) {
        Write-Verbose 'TerminalColors: rien a modifier.'
        return [pscustomobject]@{
            SettingsPath = $SettingsPath
            Changed      = $false
            Changes      = @()
            Backup       = $null
        }
    }

    # --- 4. Validation avant ecriture --------------------------------------
    $parsed = ConvertFrom-TcJsonText -Text $newText
    if ($null -eq $parsed) {
        throw 'TerminalColors : la modification aurait produit un JSON invalide. Aucun changement ecrit. Signalez ce cas avec votre settings.json.'
    }
    if ([string]$parsed.theme -ne $script:TcThemeName) {
        throw 'TerminalColors : verification echouee (theme non selectionne). Aucun changement ecrit.'
    }
    if (-not ($parsed.themes | Where-Object { $_.name -eq $script:TcThemeName })) {
        throw 'TerminalColors : verification echouee (theme absent de la liste). Aucun changement ecrit.'
    }

    $backupPath = $null
    if ($PSCmdlet.ShouldProcess($SettingsPath, "Installer le theme TerminalColors ($($changes -join ', '))")) {
        $backupPath = Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup
        if ($previousTheme) { Set-TcInstallState -Name 'PreviousTheme' -Value $previousTheme }
    }

    return [pscustomobject]@{
        SettingsPath = $SettingsPath
        Changed      = $true
        Changes      = $changes
        Backup       = $backupPath
    }
}

function Uninstall-TerminalColorsTheme {
    <#
        .SYNOPSIS
        Retire le theme [TerminalColors] de Windows Terminal et restaure le
        theme precedemment selectionne.

        .PARAMETER SettingsPath
        Chemin du settings.json a modifier. Detecte automatiquement par defaut.

        .PARAMETER NoBackup
        N'ecrit pas de copie de sauvegarde.

        .EXAMPLE
        Uninstall-TerminalColorsTheme
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string] $SettingsPath,
        [switch] $NoBackup
    )

    $SettingsPath = Resolve-TcWtSettingsPath -Path $SettingsPath

    $text = [System.IO.File]::ReadAllText($SettingsPath)
    $newText = $text
    $masked = Get-TcMaskedJson -Text $newText
    $changes = @()

    $m = [regex]::Match($masked, '"name"\s*:\s*"TerminalColors"')
    if ($m.Success) {
        $span = Find-TcJsonObjectSpan -Text $masked -Index $m.Index
        if ($span) {
            $start = $span.Start
            $end = $span.End
            $after = $end + 1
            while ($after -lt $masked.Length -and [char]::IsWhiteSpace($masked[$after])) { $after++ }
            if ($after -lt $masked.Length -and $masked[$after] -eq ',') {
                $end = $after
            } else {
                $before = $start - 1
                while ($before -ge 0 -and [char]::IsWhiteSpace($masked[$before])) { $before-- }
                if ($before -ge 0 -and $masked[$before] -eq ',') { $start = $before }
            }
            $newText = $newText.Remove($start, $end - $start + 1)
            $masked = Get-TcMaskedJson -Text $newText
            $changes += 'theme retire'
        }
    }

    $restore = Get-TcInstallState -Name 'PreviousTheme'
    if (-not $restore) { $restore = '"system"' }
    $m = [regex]::Match($masked, '"theme"\s*:\s*(?:"[^"]*"|\{[^{}]*\})')
    if ($m.Success -and $newText.Substring($m.Index, $m.Length) -match '"TerminalColors"') {
        $newText = $newText.Remove($m.Index, $m.Length).Insert($m.Index, '"theme": ' + $restore)
        $changes += "theme restaure ($restore)"
    }

    if ($changes.Count -eq 0) {
        Write-Warning 'TerminalColors : le theme n''etait pas installe.'
        return
    }

    if ($null -eq (ConvertFrom-TcJsonText -Text $newText)) {
        throw 'TerminalColors : la modification aurait produit un JSON invalide. Aucun changement ecrit.'
    }

    if ($PSCmdlet.ShouldProcess($SettingsPath, "Retirer le theme TerminalColors ($($changes -join ', '))")) {
        [void](Save-TcWtSettings -Path $SettingsPath -Text $newText -NoBackup:$NoBackup)
    }
}

