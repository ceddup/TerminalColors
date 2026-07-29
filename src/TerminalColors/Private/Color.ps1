# Colour helpers: parsing, blending, deterministic generation. No external
# dependency, compatible with Windows PowerShell 5.1.

# Colour aliases specific to the Visual Studio [Solution Colors] extension
# (see SolutionColors/src/ColorCache.cs). Other names are resolved through
# System.Drawing (lazily loaded), then through this fallback table.
$script:TcNamedColors = @{
    # Solution Colors aliases
    'burgundy'  = '#FF6347'  # Tomato
    'pumpkin'   = '#FF4500'  # OrangeRed
    'volt'      = '#9ACD32'  # YellowGreen
    'mint'      = '#66CDAA'  # MediumAquamarine
    'darkbrown' = '#8B4513'  # SaddleBrown
    'lavender'  = '#9370DB'  # MediumPurple
    # The most common everyday names (avoids loading System.Drawing)
    'red'       = '#FF0000'
    'green'     = '#008000'
    'blue'      = '#0000FF'
    'teal'      = '#008080'
    'cyan'      = '#00FFFF'
    'magenta'   = '#FF00FF'
    'yellow'    = '#FFFF00'
    'orange'    = '#FFA500'
    'purple'    = '#800080'
    'violet'    = '#EE82EE'
    'pink'      = '#FFC0CB'
    'brown'     = '#A52A2A'
    'gray'      = '#808080'
    'grey'      = '#808080'
    'black'     = '#000000'
    'white'     = '#FFFFFF'
    'gold'      = '#FFD700'
    'olive'     = '#808000'
    'navy'      = '#000080'
    'maroon'    = '#800000'
    'lime'      = '#00FF00'
    'indigo'    = '#4B0082'
    'salmon'    = '#FA8072'
    'tomato'    = '#FF6347'
    'crimson'   = '#DC143C'
    'orangered' = '#FF4500'
    'steelblue' = '#4682B4'
    'seagreen'  = '#2E8B57'
    'darkcyan'  = '#008B8B'
    'chocolate' = '#D2691E'
    'none'      = $null
}

function ConvertFrom-TcColor {
    <#
        .SYNOPSIS
        Converts a colour (hex or name) into an @{ R; G; B } table. Returns $null
        when invalid.
    #>
    [CmdletBinding()]
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $v = $Value.Trim()

    if ($v -match '^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$') {
        $hex = $Matches[1]
        switch ($hex.Length) {
            3 { $hex = "$($hex[0])$($hex[0])$($hex[1])$($hex[1])$($hex[2])$($hex[2])" }
            4 { $hex = "$($hex[0])$($hex[0])$($hex[1])$($hex[1])$($hex[2])$($hex[2])" }
            8 { $hex = $hex.Substring(0, 6) }  # alpha channel ignored
        }
        return @{
            R = [Convert]::ToInt32($hex.Substring(0, 2), 16)
            G = [Convert]::ToInt32($hex.Substring(2, 2), 16)
            B = [Convert]::ToInt32($hex.Substring(4, 2), 16)
        }
    }

    $key = $v.ToLowerInvariant()
    if ($script:TcNamedColors.ContainsKey($key)) {
        $mapped = $script:TcNamedColors[$key]
        if ($null -eq $mapped) { return $null }   # [None] = no colour
        return ConvertFrom-TcColor -Value $mapped
    }

    # Last resort: known .NET names (SlateBlue, MediumAquamarine, ...)
    try {
        if (-not ('System.Drawing.Color' -as [type])) {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        }
        $known = [System.Drawing.Color]::FromName($v)
        if ($known.IsKnownColor) {
            return @{ R = [int]$known.R; G = [int]$known.G; B = [int]$known.B }
        }
    } catch {
        Write-Verbose "TerminalColors: unresolved colour name [$v] ($($_.Exception.Message))"
    }

    return $null
}

function ConvertTo-TcHex {
    [CmdletBinding()]
    param([hashtable] $Rgb)
    if ($null -eq $Rgb) { return $null }
    return ('#{0:X2}{1:X2}{2:X2}' -f [int]$Rgb.R, [int]$Rgb.G, [int]$Rgb.B)
}

function Get-TcBlendedColor {
    <#
        .SYNOPSIS
        Linearly blends Base towards Color by Amount (0 = Base, 1 = Color).
    #>
    [CmdletBinding()]
    param(
        [hashtable] $Base,
        [hashtable] $Color,
        [double] $Amount
    )

    if ($Amount -lt 0) { $Amount = 0 }
    if ($Amount -gt 1) { $Amount = 1 }

    # Round half away from zero, like the bash variant (int(x + 0.5) in awk): both
    # implementations give exactly the same colour for the same project.
    return @{
        R = [int][Math]::Round($Base.R + ($Color.R - $Base.R) * $Amount, 0, [MidpointRounding]::AwayFromZero)
        G = [int][Math]::Round($Base.G + ($Color.G - $Base.G) * $Amount, 0, [MidpointRounding]::AwayFromZero)
        B = [int][Math]::Round($Base.B + ($Color.B - $Base.B) * $Amount, 0, [MidpointRounding]::AwayFromZero)
    }
}

function ConvertFrom-TcHsl {
    [CmdletBinding()]
    param(
        [double] $Hue,          # 0..360
        [double] $Saturation,   # 0..1
        [double] $Lightness     # 0..1
    )

    $h = (($Hue % 360) + 360) % 360
    $c = (1 - [Math]::Abs(2 * $Lightness - 1)) * $Saturation
    $x = $c * (1 - [Math]::Abs((($h / 60.0) % 2) - 1))
    $m = $Lightness - $c / 2

    switch ([int][Math]::Floor($h / 60)) {
        0 { $r = $c; $g = $x; $b = 0 }
        1 { $r = $x; $g = $c; $b = 0 }
        2 { $r = 0; $g = $c; $b = $x }
        3 { $r = 0; $g = $x; $b = $c }
        4 { $r = $x; $g = 0; $b = $c }
        default { $r = $c; $g = 0; $b = $x }
    }

    return @{
        R = [int][Math]::Round(($r + $m) * 255, 0, [MidpointRounding]::AwayFromZero)
        G = [int][Math]::Round(($g + $m) * 255, 0, [MidpointRounding]::AwayFromZero)
        B = [int][Math]::Round(($b + $m) * 255, 0, [MidpointRounding]::AwayFromZero)
    }
}

function ConvertTo-TcHsl {
    [CmdletBinding()]
    param([hashtable] $Rgb)

    $r = $Rgb.R / 255.0; $g = $Rgb.G / 255.0; $b = $Rgb.B / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2
    $d = $max - $min

    if ($d -eq 0) { return @{ H = 0.0; S = 0.0; L = $l } }

    $s = $d / (1 - [Math]::Abs(2 * $l - 1))
    if ($max -eq $r) { $h = 60 * ((($g - $b) / $d) % 6) }
    elseif ($max -eq $g) { $h = 60 * ((($b - $r) / $d) + 2) }
    else { $h = 60 * ((($r - $g) / $d) + 4) }
    if ($h -lt 0) { $h += 360 }

    return @{ H = [double]$h; S = [double]$s; L = [double]$l }
}

function Get-TcAutoColor {
    <#
        .SYNOPSIS
        Generates a stable, readable colour from a string (a repository name). The
        same name always gives the same colour, on every machine.
    #>
    [CmdletBinding()]
    param([string] $Seed)

    # FNV-1a 32-bit: deterministic, unlike String.GetHashCode(), which varies from
    # one process to the next.
    #
    # The arithmetic is done in Int64: the intermediate product reaches 56 bits,
    # which exceeds a Double's exact precision (53 bits) but stays exact in Int64.
    # The mask is an explicit Int64 because PowerShell parses the literal
    # 0xFFFFFFFF as the Int32 -1, which would mask nothing at all.
    $mask = [int64]4294967295
    $hash = [int64]2166136261
    foreach ($ch in $Seed.ToLowerInvariant().ToCharArray()) {
        $hash = $hash -bxor ([int64][int][char]$ch)
        $hash = ($hash * 16777619) -band $mask
    }

    # 24 hues, 15 degrees apart.
    $hue = [double](($hash % 24) * 15)
    $sat = 0.62 + (([int](($hash -shr 8) % 3)) * 0.09)   # 0.62 / 0.71 / 0.80
    $lig = 0.42 + (([int](($hash -shr 16) % 3)) * 0.05)  # 0.42 / 0.47 / 0.52

    return ConvertFrom-TcHsl -Hue $hue -Saturation $sat -Lightness $lig
}

function Get-TcColorEmoji {
    <#
        .SYNOPSIS
        Picks the Unicode coloured square nearest to an RGB colour.
    #>
    [CmdletBinding()]
    param([hashtable] $Rgb)

    $hsl = ConvertTo-TcHsl -Rgb $Rgb

    if ($hsl.S -lt 0.15) {
        if ($hsl.L -ge 0.5) { return [char]::ConvertFromUtf32(0x2B1C) }  # white square
        return [char]::ConvertFromUtf32(0x2B1B)                          # black square
    }

    $h = $hsl.H
    # Brown: dark orange
    if ($h -ge 15 -and $h -lt 45 -and $hsl.L -lt 0.38) { return [char]::ConvertFromUtf32(0x1F7EB) }

    if ($h -lt 15 -or $h -ge 340) { return [char]::ConvertFromUtf32(0x1F7E5) }  # red
    if ($h -lt 45) { return [char]::ConvertFromUtf32(0x1F7E7) }                 # orange
    if ($h -lt 70) { return [char]::ConvertFromUtf32(0x1F7E8) }                 # yellow
    if ($h -lt 175) { return [char]::ConvertFromUtf32(0x1F7E9) }                # green
    if ($h -lt 265) { return [char]::ConvertFromUtf32(0x1F7E6) }                # blue
    return [char]::ConvertFromUtf32(0x1F7EA)                                    # purple
}
