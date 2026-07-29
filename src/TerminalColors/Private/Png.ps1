# Generation of a solid PNG image, with no external dependency.
#
# The opaque backdrop (Install-TerminalColorsBackdrop) needs a single-colour image
# to lay over the pane. System.Drawing would do the job on 5.1 but is not
# guaranteed on PowerShell 7 (Windows-only assembly, absent from some
# installations), so the PNG is encoded by hand.
#
# The resulting file is tiny (under 100 bytes) and perfectly deterministic: the
# same colour always produces the same bytes.

$script:TcCrcTable = $null
$script:TcPngWidth = 2
$script:TcPngHeight = 2

function Get-TcCrcTable {
    <#
        .SYNOPSIS
        CRC-32 table (polynomial 0xEDB88320), computed only once.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $script:TcCrcTable) { return $script:TcCrcTable }

    $table = New-Object 'System.Int64[]' 256
    for ($n = 0; $n -lt 256; $n++) {
        $c = [int64]$n
        for ($k = 0; $k -lt 8; $k++) {
            if ($c -band 1) {
                # 3988292384 = 0xEDB88320; PowerShell would read the hex literal as
                # a negative Int32.
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
        Adler-32 checksum, required at the end of a zlib stream.
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
        32-bit big-endian integer, as the PNG format requires.
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
        Assembles a PNG chunk: length, type, data, CRC of type+data.
    #>
    [CmdletBinding()]
    param(
        [string] $Type,
        [byte[]] $Data
    )

    if ($null -eq $Data) { $Data = [byte[]] @() }

    # The [byte[]] casts are essential: a value returned by a PowerShell function
    # comes back as System.Object[], which AddRange refuses.
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
        Bytes of a solid PNG in the requested colour (8-bit truecolor).

        .DESCRIPTION
        The zlib stream of the IDAT chunk uses a [stored] (uncompressed) block: for
        a handful of bytes that is as compact as a real deflate, and it avoids
        depending on System.IO.Compression.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([hashtable] $Rgb)

    if ($null -eq $Rgb) { throw 'TerminalColors: missing colour for PNG generation.' }

    $r = [byte]([int]$Rgb.R)
    $g = [byte]([int]$Rgb.G)
    $b = [byte]([int]$Rgb.B)

    # --- Raw data: one filter byte (0 = none) per row -----------------------
    $raw = New-Object 'System.Collections.Generic.List[byte]'
    for ($y = 0; $y -lt $script:TcPngHeight; $y++) {
        $raw.Add([byte]0)
        for ($x = 0; $x -lt $script:TcPngWidth; $x++) {
            $raw.Add($r); $raw.Add($g); $raw.Add($b)
        }
    }
    $rawBytes = $raw.ToArray()

    # --- zlib stream: header, uncompressed block, Adler-32 ------------------
    $zlib = New-Object 'System.Collections.Generic.List[byte]'
    $zlib.Add([byte]0x78)   # CM = deflate, CINFO = 32 KB window
    $zlib.Add([byte]0x01)   # no dictionary; (0x7801 % 31) == 0
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
    $ihdr.Add([byte]8)   # 8 bits per channel
    $ihdr.Add([byte]2)   # type 2: RGB without alpha
    $ihdr.Add([byte]0)   # deflate compression
    $ihdr.Add([byte]0)   # standard filtering
    $ihdr.Add([byte]0)   # not interlaced

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
        Writes a solid PNG to the requested location, creating the folder if needed.
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
