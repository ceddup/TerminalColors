# Generation d'une image PNG unie, sans dependance externe.
#
# Le calque opaque (Install-TerminalColorsBackdrop) a besoin d'une image d'une
# seule couleur a poser sur le volet. System.Drawing ferait l'affaire en 5.1
# mais n'est pas garanti sur PowerShell 7 (assembly Windows-only, absente de
# certaines installations), donc on encode le PNG a la main.
#
# Le fichier produit est minuscule (moins de 100 octets) et parfaitement
# deterministe : la meme couleur donne toujours les memes octets.

$script:TcCrcTable = $null
$script:TcPngWidth = 2
$script:TcPngHeight = 2

function Get-TcCrcTable {
    <#
        .SYNOPSIS
        Table CRC-32 (polynome 0xEDB88320), calculee une seule fois.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $script:TcCrcTable) { return $script:TcCrcTable }

    $table = New-Object 'System.Int64[]' 256
    for ($n = 0; $n -lt 256; $n++) {
        $c = [int64]$n
        for ($k = 0; $k -lt 8; $k++) {
            if ($c -band 1) {
                # 3988292384 = 0xEDB88320 ; le litteral hexa serait vu comme un
                # Int32 negatif par PowerShell.
                $c = 3988292384 -bxor ($c -shr 1)
            } else {
                $c = $c -shr 1
            }
        }
        $table[$n] = $c -band 4294967295
    }

    $script:TcCrcTable = $table
    return $table
}

function Get-TcCrc32 {
    [CmdletBinding()]
    param([byte[]] $Bytes)

    $table = Get-TcCrcTable
    $c = [int64]4294967295
    foreach ($b in $Bytes) {
        $index = [int](($c -bxor [int64]$b) -band 255)
        $c = $table[$index] -bxor ($c -shr 8)
    }
    return (($c -bxor 4294967295) -band 4294967295)
}

function Get-TcAdler32 {
    <#
        .SYNOPSIS
        Somme de controle Adler-32, exigee en fin de flux zlib.
    #>
    [CmdletBinding()]
    param([byte[]] $Bytes)

    $a = [int64]1
    $b = [int64]0
    foreach ($x in $Bytes) {
        $a = ($a + [int64]$x) % 65521
        $b = ($b + $a) % 65521
    }
    return ((($b -shl 16) -bor $a) -band 4294967295)
}

function ConvertTo-TcUInt32Bytes {
    <#
        .SYNOPSIS
        Entier 32 bits en gros-boutien, comme l'exige le format PNG.
    #>
    [CmdletBinding()]
    param([int64] $Value)

    return [byte[]] @(
        [byte](($Value -shr 24) -band 255),
        [byte](($Value -shr 16) -band 255),
        [byte](($Value -shr 8) -band 255),
        [byte]($Value -band 255)
    )
}

function New-TcPngChunk {
    <#
        .SYNOPSIS
        Assemble un bloc PNG : longueur, type, donnees, CRC du type+donnees.
    #>
    [CmdletBinding()]
    param(
        [string] $Type,
        [byte[]] $Data
    )

    if ($null -eq $Data) { $Data = [byte[]] @() }

    # Les transtypages [byte[]] sont indispensables : une valeur renvoyee par une
    # fonction PowerShell revient en System.Object[], que AddRange refuse.
    $body = New-Object 'System.Collections.Generic.List[byte]'
    $body.AddRange([byte[]][System.Text.Encoding]::ASCII.GetBytes($Type))
    if ($Data.Length -gt 0) { $body.AddRange([byte[]]$Data) }

    $bytes = $body.ToArray()
    $out = New-Object 'System.Collections.Generic.List[byte]'
    $out.AddRange([byte[]](ConvertTo-TcUInt32Bytes -Value ([int64]$Data.Length)))
    $out.AddRange([byte[]]$bytes)
    $out.AddRange([byte[]](ConvertTo-TcUInt32Bytes -Value (Get-TcCrc32 -Bytes $bytes)))
    return $out.ToArray()
}

function New-TcSolidPngBytes {
    <#
        .SYNOPSIS
        Octets d'un PNG uni de la couleur demandee (truecolor 8 bits).

        .DESCRIPTION
        Le flux zlib du bloc IDAT utilise un bloc [stored] (non compresse) :
        pour une poignee d'octets c'est aussi compact qu'un vrai deflate, et
        cela evite de dependre de System.IO.Compression.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([hashtable] $Rgb)

    if ($null -eq $Rgb) { throw 'TerminalColors : couleur manquante pour la generation du PNG.' }

    $r = [byte]([int]$Rgb.R)
    $g = [byte]([int]$Rgb.G)
    $b = [byte]([int]$Rgb.B)

    # --- Donnees brutes : un octet de filtre (0 = aucun) par ligne ----------
    $raw = New-Object 'System.Collections.Generic.List[byte]'
    for ($y = 0; $y -lt $script:TcPngHeight; $y++) {
        $raw.Add([byte]0)
        for ($x = 0; $x -lt $script:TcPngWidth; $x++) {
            $raw.Add($r); $raw.Add($g); $raw.Add($b)
        }
    }
    $rawBytes = $raw.ToArray()

    # --- Flux zlib : en-tete, bloc non compresse, Adler-32 ------------------
    $zlib = New-Object 'System.Collections.Generic.List[byte]'
    $zlib.Add([byte]0x78)   # CM = deflate, CINFO = fenetre 32 Ko
    $zlib.Add([byte]0x01)   # pas de dictionnaire ; (0x7801 % 31) == 0
    $zlib.Add([byte]0x01)   # BFINAL = 1, BTYPE = 00 (stored)
    $len = $rawBytes.Length
    $zlib.Add([byte]($len -band 255))
    $zlib.Add([byte](($len -shr 8) -band 255))
    $zlib.Add([byte]((-bnot $len) -band 255))
    $zlib.Add([byte](((-bnot $len) -shr 8) -band 255))
    $zlib.AddRange([byte[]]$rawBytes)
    $zlib.AddRange([byte[]](ConvertTo-TcUInt32Bytes -Value (Get-TcAdler32 -Bytes $rawBytes)))

    # --- IHDR ---------------------------------------------------------------
    $ihdr = New-Object 'System.Collections.Generic.List[byte]'
    $ihdr.AddRange([byte[]](ConvertTo-TcUInt32Bytes -Value ([int64]$script:TcPngWidth)))
    $ihdr.AddRange([byte[]](ConvertTo-TcUInt32Bytes -Value ([int64]$script:TcPngHeight)))
    $ihdr.Add([byte]8)   # 8 bits par canal
    $ihdr.Add([byte]2)   # type 2 : RVB sans alpha
    $ihdr.Add([byte]0)   # compression deflate
    $ihdr.Add([byte]0)   # filtrage standard
    $ihdr.Add([byte]0)   # non entrelace

    $png = New-Object 'System.Collections.Generic.List[byte]'
    $png.AddRange([byte[]] @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
    $png.AddRange([byte[]](New-TcPngChunk -Type 'IHDR' -Data $ihdr.ToArray()))
    $png.AddRange([byte[]](New-TcPngChunk -Type 'IDAT' -Data $zlib.ToArray()))
    $png.AddRange([byte[]](New-TcPngChunk -Type 'IEND' -Data ([byte[]] @())))
    return $png.ToArray()
}

function Write-TcSolidPng {
    <#
        .SYNOPSIS
        Ecrit un PNG uni a l'emplacement demande, en creant le dossier au besoin.
    #>
    [CmdletBinding()]
    param(
        [string] $Path,
        [hashtable] $Rgb
    )

    $directory = Split-Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllBytes($Path, (New-TcSolidPngBytes -Rgb $Rgb))
    return $Path
}
