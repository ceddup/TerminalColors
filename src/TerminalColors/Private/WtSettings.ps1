# Edition chirurgicale du settings.json de Windows Terminal.
#
# Principe commun aux trois installateurs (theme, calque opaque, barre de titre
# systeme) : on ne reserialise jamais le document. On insere ou on remplace le
# strict necessaire dans le texte existant, afin de preserver les commentaires,
# l'ordre des cles et la mise en forme de l'utilisateur. Le resultat est valide
# avant toute ecriture, et une sauvegarde est creee.
#
# Les fonctions de reperage travaillent sur une copie [masquee] du texte : meme
# longueur que l'original, commentaires et echappements neutralises, si bien que
# tout index trouve dans la copie est directement utilisable sur l'original.

function Get-TcMaskedJson {
    <#
        .SYNOPSIS
        Copie du texte sans commentaires et sans sequences d'echappement, de
        longueur identique a l'original : les index trouves dans cette copie
        sont donc directement utilisables sur le texte d'origine.
    #>
    param([string] $Text)

    $noComments = Remove-TcJsonComments -Text $Text
    $chars = $noComments.ToCharArray()
    $inString = $false
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        if ($inString) {
            if ($c -eq '\') { $chars[$i] = ' '; if ($i + 1 -lt $chars.Length) { $chars[$i + 1] = ' '; $i++ }; continue }
            if ($c -eq '"') { $inString = $false; continue }
            # Le contenu des chaines est masque, sauf pour les noms de cles que
            # l'on veut pouvoir retrouver : on garde donc les caracteres.
            continue
        }
        if ($c -eq '"') { $inString = $true }
    }
    return (-join $chars)
}

function Find-TcJsonObjectSpan {
    <#
        .SYNOPSIS
        A partir d'un index situe dans un objet JSON, renvoie @{ Start; End }
        delimitant cet objet (accolades incluses).
    #>
    param([string] $Text, [int] $Index)

    # Reculer jusqu'a l'accolade ouvrante de l'objet courant
    $depth = 0
    $start = -1
    for ($i = $Index; $i -ge 0; $i--) {
        $c = $Text[$i]
        if ($c -eq '}') { $depth++ }
        elseif ($c -eq '{') {
            if ($depth -eq 0) { $start = $i; break }
            $depth--
        }
    }
    if ($start -lt 0) { return $null }

    $depth = 0
    for ($i = $start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return @{ Start = $start; End = $i } }
        }
    }
    return $null
}

function Find-TcJsonBlockSpan {
    <#
        .SYNOPSIS
        Renvoie @{ Start; End } de l'objet ou du tableau qui commence a $Index
        (l'index doit pointer sur [{] ou [[]).
    #>
    param([string] $Text, [int] $Index)

    $open = $Text[$Index]
    if ($open -eq '{') { $close = '}' } elseif ($open -eq '[') { $close = ']' } else { return $null }

    $depth = 0
    for ($i = $Index; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq $open) { $depth++ }
        elseif ($c -eq $close) {
            $depth--
            if ($depth -eq 0) { return @{ Start = $Index; End = $i } }
        }
    }
    return $null
}

function Find-TcJsonMember {
    <#
        .SYNOPSIS
        Cherche le membre [Name] directement dans l'objet delimite par $Span
        (profondeur 1 : les objets imbriques sont ignores).

        Renvoie @{ NameStart; ValueStart; ValueEnd } ou $null. ValueEnd est
        l'index du dernier caractere de la valeur.
    #>
    param([string] $Masked, [hashtable] $Span, [string] $Name)

    $pattern = '"' + [regex]::Escape($Name) + '"\s*:'
    foreach ($m in [regex]::Matches($Masked, $pattern)) {
        if ($m.Index -le $Span.Start -or $m.Index -ge $Span.End) { continue }

        # Verifier que le membre est bien a la racine de cet objet, et non dans
        # un objet ou un tableau imbrique.
        $depth = 0
        for ($i = $Span.Start + 1; $i -lt $m.Index; $i++) {
            $c = $Masked[$i]
            if ($c -eq '{' -or $c -eq '[') { $depth++ }
            elseif ($c -eq '}' -or $c -eq ']') { $depth-- }
        }
        if ($depth -ne 0) { continue }

        # Debut de la valeur
        $v = $m.Index + $m.Length
        while ($v -lt $Span.End -and [char]::IsWhiteSpace($Masked[$v])) { $v++ }
        if ($v -ge $Span.End) { continue }

        $end = -1
        $c = $Masked[$v]
        if ($c -eq '"') {
            for ($i = $v + 1; $i -le $Span.End; $i++) {
                if ($Masked[$i] -eq '"') { $end = $i; break }
            }
        } elseif ($c -eq '{' -or $c -eq '[') {
            $block = Find-TcJsonBlockSpan -Text $Masked -Index $v
            if ($block) { $end = $block.End }
        } else {
            # Litteral : nombre, true, false, null
            for ($i = $v; $i -le $Span.End; $i++) {
                $ch = $Masked[$i]
                if ($ch -eq ',' -or $ch -eq '}' -or $ch -eq ']') { break }
                $end = $i
            }
            while ($end -gt $v -and [char]::IsWhiteSpace($Masked[$end])) { $end-- }
        }

        if ($end -lt 0) { continue }
        return @{ NameStart = $m.Index; ValueStart = $v; ValueEnd = $end }
    }
    return $null
}

function Test-TcJsonObjectEmpty {
    param([string] $Masked, [hashtable] $Span)

    for ($i = $Span.Start + 1; $i -lt $Span.End; $i++) {
        if (-not [char]::IsWhiteSpace($Masked[$i])) { return $false }
    }
    return $true
}

function Set-TcJsonMember {
    <#
        .SYNOPSIS
        Ajoute ou remplace le membre [Name] de l'objet contenant $AnchorIndex.

        .DESCRIPTION
        $Literal est insere tel quel : c'est a l'appelant de fournir un litteral
        JSON valide (chaine entre guillemets, nombre, true/false).

        Renvoie @{ Text; Action } ou Action vaut 'ajoute', 'remplace' ou
        'inchange'. Les index etant invalides par toute modification, on
        n'applique qu'un seul membre par appel.
    #>
    param(
        [string] $Text,
        [int] $AnchorIndex,
        [string] $Name,
        [string] $Literal,
        [string] $Indent = '        '
    )

    $masked = Get-TcMaskedJson -Text $Text
    $span = Find-TcJsonObjectSpan -Text $masked -Index $AnchorIndex
    if ($null -eq $span) { throw "TerminalColors : objet JSON introuvable pour le membre [$Name]." }

    $member = Find-TcJsonMember -Masked $masked -Span $span -Name $Name
    if ($member) {
        $current = $Text.Substring($member.ValueStart, $member.ValueEnd - $member.ValueStart + 1)
        if ($current -eq $Literal) { return @{ Text = $Text; Action = 'inchange' } }
        $newText = $Text.Remove($member.ValueStart, $member.ValueEnd - $member.ValueStart + 1).Insert($member.ValueStart, $Literal)
        return @{ Text = $newText; Action = 'remplace' }
    }

    $fragment = '"' + $Name + '": ' + $Literal
    if (Test-TcJsonObjectEmpty -Masked $masked -Span $span) {
        # Objet vide : on le reecrit en entier pour ne pas coller l'accolade
        # fermante a la valeur inseree.
        $closeIndent = $Indent
        if ($closeIndent.Length -ge 4) { $closeIndent = $closeIndent.Substring(4) }
        $block = '{' + [Environment]::NewLine + $Indent + $fragment + [Environment]::NewLine + $closeIndent + '}'
        $newText = $Text.Remove($span.Start, $span.End - $span.Start + 1).Insert($span.Start, $block)
    } else {
        $newText = $Text.Insert($span.Start + 1, [Environment]::NewLine + $Indent + $fragment + ',')
    }
    return @{ Text = $newText; Action = 'ajoute' }
}

function Remove-TcJsonMember {
    <#
        .SYNOPSIS
        Retire le membre [Name] de l'objet contenant $AnchorIndex, en absorbant
        la virgule adjacente pour garder un objet valide.

        Renvoie @{ Text; Action } ou Action vaut 'retire' ou 'absent'.
    #>
    param(
        [string] $Text,
        [int] $AnchorIndex,
        [string] $Name
    )

    $masked = Get-TcMaskedJson -Text $Text
    $span = Find-TcJsonObjectSpan -Text $masked -Index $AnchorIndex
    if ($null -eq $span) { return @{ Text = $Text; Action = 'absent' } }

    $member = Find-TcJsonMember -Masked $masked -Span $span -Name $Name
    if ($null -eq $member) { return @{ Text = $Text; Action = 'absent' } }

    $start = $member.NameStart
    $end = $member.ValueEnd

    $after = $end + 1
    while ($after -lt $span.End -and [char]::IsWhiteSpace($masked[$after])) { $after++ }
    if ($after -lt $span.End -and $masked[$after] -eq ',') {
        $end = $after
    } else {
        $before = $start - 1
        while ($before -gt $span.Start -and [char]::IsWhiteSpace($masked[$before])) { $before-- }
        if ($before -gt $span.Start -and $masked[$before] -eq ',') { $start = $before }
    }

    # Absorber l'indentation restee en debut de ligne.
    $probe = $start - 1
    while ($probe -gt $span.Start -and ($masked[$probe] -eq ' ' -or $masked[$probe] -eq "`t")) { $probe-- }
    if ($probe -gt $span.Start -and $masked[$probe] -eq "`n") { $start = $probe }

    return @{ Text = $Text.Remove($start, $end - $start + 1); Action = 'retire' }
}

function Find-TcJsonRootIndex {
    param([string] $Masked)

    $index = $Masked.IndexOf('{')
    if ($index -lt 0) { throw 'TerminalColors : structure de settings.json inattendue (aucun objet racine).' }
    return $index
}

function Resolve-TcWtSettingsPath {
    <#
        .SYNOPSIS
        Valide un chemin de settings.json fourni, ou le detecte. Leve une erreur
        explicite si le fichier est introuvable.
    #>
    param([string] $Path)

    if (-not $Path) { $Path = Get-TcWtSettingsPath }
    if (-not $Path -or -not [System.IO.File]::Exists($Path)) {
        throw 'TerminalColors : settings.json de Windows Terminal introuvable. Lancez Windows Terminal une fois, ou indiquez -SettingsPath.'
    }
    return $Path
}

function Get-TcWtSettingsEncoding {
    param([string] $Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    } catch { $hasBom = $false }
    return (New-Object System.Text.UTF8Encoding($hasBom))
}

function Save-TcWtSettings {
    <#
        .SYNOPSIS
        Ecrit settings.json en conservant son encodage, apres sauvegarde
        horodatee. Renvoie le chemin de la sauvegarde, ou $null.
    #>
    param(
        [string] $Path,
        [string] $Text,
        [switch] $NoBackup
    )

    $backupPath = $null
    if (-not $NoBackup) {
        $backupPath = '{0}.terminalcolors-backup-{1}' -f $Path, (Get-Date -Format 'yyyyMMdd-HHmmss')
        [System.IO.File]::Copy($Path, $backupPath, $true)
    }
    [System.IO.File]::WriteAllText($Path, $Text, (Get-TcWtSettingsEncoding -Path $Path))
    return $backupPath
}

# --- Donnees du module -------------------------------------------------------
# Dossier ou vivent l'etat d'installation et les images du calque opaque.
# Redirigeable pour que les tests n'aillent jamais toucher aux donnees reelles
# de l'utilisateur (la desinstallation du calque y supprime des fichiers).

$script:TcDataDirectory = $null

function Get-TcDataDirectory {
    if ($script:TcDataDirectory) { return $script:TcDataDirectory }
    return (Join-Path $env:LOCALAPPDATA 'TerminalColors')
}

# --- Etat d'installation -----------------------------------------------------
# Memorise ce qu'il faut restaurer a la desinstallation (theme precedent, image
# de fond precedente, valeur precedente de showTabsInTitlebar).

function Get-TcInstallStatePath {
    return (Join-Path (Get-TcDataDirectory) 'state.json')
}

function Set-TcInstallState {
    param([string] $Name, $Value)

    $path = Get-TcInstallStatePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $state = @{}
    if ([System.IO.File]::Exists($path)) {
        $existing = ConvertFrom-TcJsonFile -Path $path
        if ($existing) {
            foreach ($p in $existing.PSObject.Properties) { $state[$p.Name] = $p.Value }
        }
    }
    $state[$Name] = $Value

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, ([pscustomobject]$state | ConvertTo-Json -Depth 5), $encoding)
}

function Get-TcInstallState {
    param([string] $Name)

    $path = Get-TcInstallStatePath
    if (-not [System.IO.File]::Exists($path)) { return $null }
    $state = ConvertFrom-TcJsonFile -Path $path
    if (-not $state) { return $null }
    return (Get-TcJsonProperty -InputObject $state -Name $Name)
}

function Remove-TcInstallState {
    param([string] $Name)

    $path = Get-TcInstallStatePath
    if (-not [System.IO.File]::Exists($path)) { return }
    $state = ConvertFrom-TcJsonFile -Path $path
    if (-not $state) { return }

    $kept = @{}
    foreach ($p in $state.PSObject.Properties) {
        if ($p.Name -ne $Name) { $kept[$p.Name] = $p.Value }
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, ([pscustomobject]$kept | ConvertTo-Json -Depth 5), $encoding)
}
