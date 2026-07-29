# Lecture de JSON tolerant (JSONC) : les fichiers settings.json de VS Code et de
# Windows Terminal contiennent des commentaires et parfois des virgules finales.

function Remove-TcJsonComments {
    <#
        .SYNOPSIS
        Remplace les commentaires // et /* */ par des espaces, en preservant les
        positions (indispensable pour l'edition chirurgicale de settings.json) et
        en ignorant ce qui se trouve dans des chaines.
    #>
    [CmdletBinding()]
    param([string] $Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $sb = New-Object System.Text.StringBuilder($Text.Length)
    $i = 0
    $len = $Text.Length
    $inString = $false

    while ($i -lt $len) {
        $c = $Text[$i]

        if ($inString) {
            [void]$sb.Append($c)
            if ($c -eq '\') {
                if ($i + 1 -lt $len) { [void]$sb.Append($Text[$i + 1]); $i += 2; continue }
            } elseif ($c -eq '"') {
                $inString = $false
            }
            $i++
            continue
        }

        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); $i++; continue }

        if ($c -eq '/' -and $i + 1 -lt $len) {
            $n = $Text[$i + 1]
            if ($n -eq '/') {
                while ($i -lt $len -and $Text[$i] -ne "`n") {
                    if ($Text[$i] -eq "`r") { [void]$sb.Append($Text[$i]) } else { [void]$sb.Append(' ') }
                    $i++
                }
                continue
            }
            if ($n -eq '*') {
                $i += 2
                [void]$sb.Append('  ')
                while ($i -lt $len) {
                    if ($Text[$i] -eq '*' -and $i + 1 -lt $len -and $Text[$i + 1] -eq '/') {
                        [void]$sb.Append('  '); $i += 2; break
                    }
                    if ($Text[$i] -eq "`n" -or $Text[$i] -eq "`r") { [void]$sb.Append($Text[$i]) } else { [void]$sb.Append(' ') }
                    $i++
                }
                continue
            }
        }

        [void]$sb.Append($c)
        $i++
    }

    return $sb.ToString()
}

function ConvertFrom-TcJsonText {
    <#
        .SYNOPSIS
        Analyse du JSONC. Renvoie $null en cas d'echec (jamais d'exception).
    #>
    [CmdletBinding()]
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $clean = Remove-TcJsonComments -Text $Text
        # Virgules finales
        $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')
        return $clean | ConvertFrom-Json
    } catch {
        Write-Verbose "TerminalColors: JSON illisible ($($_.Exception.Message))"
        return $null
    }
}

function ConvertFrom-TcJsonFile {
    [CmdletBinding()]
    param([string] $Path)

    try {
        $raw = [System.IO.File]::ReadAllText($Path)
    } catch {
        Write-Verbose "TerminalColors: lecture impossible de [$Path] ($($_.Exception.Message))"
        return $null
    }
    return ConvertFrom-TcJsonText -Text $raw
}

function Get-TcJsonProperty {
    <#
        .SYNOPSIS
        Lit une propriete dont le nom contient des points ([peacock.color])
        sur un objet issu de ConvertFrom-Json, sans lever d'erreur.
    #>
    [CmdletBinding()]
    param(
        # Volontairement non obligatoire : les appelants enchainent les lectures
        # sur des objets qui peuvent etre absents.
        $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $InputObject) { return $null }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}
