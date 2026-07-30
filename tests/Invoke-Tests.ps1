<#
    .SYNOPSIS
    TerminalColors tests, with no external dependency.

    .DESCRIPTION
    Deliberately self-contained: no Pester, nothing to install, so that anyone
    can verify the behaviour immediately, on Windows PowerShell 5.1 as well as
    PowerShell 7.

        .\tests\Invoke-Tests.ps1

    Exit code 0 if everything passes, 1 otherwise.
#>
[CmdletBinding()]
param([switch] $Detailed)

$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0
$script:Failures = New-Object System.Collections.ArrayList
$script:Section = ''

function Write-Section {
    param([string] $Name)
    $script:Section = $Name
    Write-Host ''
    Write-Host "  $Name" -ForegroundColor Cyan
}

function Test-It {
    param([string] $Name, [scriptblock] $Body)

    try {
        & $Body
        $script:Passed++
        if ($Detailed) { Write-Host "    [ok] $Name" -ForegroundColor DarkGreen }
    } catch {
        $script:Failed++
        [void]$script:Failures.Add("$($script:Section) / $Name : $($_.Exception.Message)")
        Write-Host "    [KO] $Name" -ForegroundColor Red
        Write-Host "         $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Because)
    if ($Expected -ne $Actual) { throw "expected [$Expected], got [$Actual]. $Because" }
}

function Assert-True {
    param($Condition, [string] $Because)
    if (-not $Condition) { throw "condition is false. $Because" }
}

function Assert-Null {
    param($Value, [string] $Because)
    if ($null -ne $Value) { throw "expected null, got [$Value]. $Because" }
}

function Assert-NotNull {
    param($Value, [string] $Because)
    if ($null -eq $Value) { throw "expected non-null. $Because" }
}

# --- Loading the module ------------------------------------------------------
$repoRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $repoRoot 'src\TerminalColors\TerminalColors.psd1'

Remove-Module TerminalColors -Force -ErrorAction SilentlyContinue
Import-Module $modulePath -Force -ErrorAction Stop
$m = Get-Module TerminalColors

# Shortcuts to the module's internal functions
function Get-ParsedJson { param([string] $Text) & $m { param($t) ConvertFrom-TcJsonText -Text $t } $Text }
function Get-HexOf { param([string] $Value) & $m { param($v) ConvertTo-TcHex -Rgb (ConvertFrom-TcColor -Value $v) } $Value }
function Get-RgbOf { param([string] $Value) & $m { param($v) ConvertFrom-TcColor -Value $v } $Value }
function Get-AutoHexOf { param([string] $Seed) & $m { param($s) ConvertTo-TcHex -Rgb (Get-TcAutoColor -Seed $s) } $Seed }
function Get-EmojiOf { param([string] $Value) & $m { param($v) Get-TcColorEmoji -Rgb (ConvertFrom-TcColor -Value $v) } $Value }
function Get-BlendHex {
    param($Base, $Color, [double] $Amount)
    & $m { param($b, $c, $a) ConvertTo-TcHex -Rgb (Get-TcBlendedColor -Base $b -Color $c -Amount $a) } $Base $Color $Amount
}
function Get-ResolvedColor {
    param([string] $Path, [bool] $AutoGit = $true, [switch] $UseCache)
    if ($UseCache) {
        return & $m { param($p, $a) Resolve-TcColor -Path $p -AutoGitColors $a } $Path $AutoGit
    }
    return & $m { param($p, $a) Resolve-TcColor -Path $p -AutoGitColors $a -NoCache } $Path $AutoGit
}

Write-Host ''
Write-Host '  Tests TerminalColors' -ForegroundColor White
Write-Host '  ====================' -ForegroundColor DarkGray

# Sandbox for the fixtures
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ('tc-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

function New-Fixture {
    param([string] $RelativePath, [string] $Content)
    $full = Join-Path $sandbox $RelativePath
    $dir = Split-Path $full -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($full, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $full
}

function New-FixtureDir {
    param([string] $RelativePath)
    $full = Join-Path $sandbox $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { New-Item -ItemType Directory -Path $full -Force | Out-Null }
    return $full
}

# The module keeps its install state and the opaque backdrop images in
# %LOCALAPPDATA%\TerminalColors, and uninstalling the backdrop deletes files in
# there: that folder is redirected to the sandbox so the tests never
# touchent jamais aux donnees reelles de l'utilisateur.
& $m { param($d) $script:TcDataDirectory = $d } (Join-Path $sandbox 'data')

function Get-SourceFile {
    param([string[]] $Extension = @('*.ps1', '*.psm1', '*.psd1'))
    $files = New-Object System.Collections.ArrayList
    foreach ($ext in $Extension) {
        foreach ($f in @(Get-ChildItem -Path (Join-Path $repoRoot 'src') -Recurse -Filter $ext -File -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
        foreach ($f in @(Get-ChildItem -Path $repoRoot -Filter $ext -File -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
        foreach ($f in @(Get-ChildItem -Path (Join-Path $repoRoot 'tests') -Filter $ext -File -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
    }
    return $files
}

try {

    # ======================================================================
    Write-Section 'Colour parsing'

    Test-It '6-digit hex' {
        $r = Get-RgbOf '#21A5F3'
        Assert-Equal 0x21 $r.R; Assert-Equal 0xA5 $r.G; Assert-Equal 0xF3 $r.B
    }

    Test-It 'hex without a hash' {
        Assert-Equal '#215732' (Get-HexOf '215732')
    }

    Test-It 'short #rgb hex' {
        Assert-Equal '#FF00AA' (Get-HexOf '#f0a')
    }

    Test-It 'alpha channel ignored' {
        Assert-Equal '#215732' (Get-HexOf '#21573280')
    }

    Test-It 'common colour name' {
        Assert-Equal '#008080' (Get-HexOf 'Teal')
    }

    Test-It 'colour name is case-insensitive' {
        Assert-Equal '#008080' (Get-HexOf 'tEaL')
    }

    Test-It 'Solution Colors alias (Burgundy = Tomato)' {
        Assert-Equal '#FF6347' (Get-HexOf 'Burgundy')
    }

    Test-It 'Solution Colors alias (Volt = YellowGreen)' {
        Assert-Equal '#9ACD32' (Get-HexOf 'Volt')
    }

    Test-It 'known .NET name absent from the internal table' {
        Assert-Equal '#66CDAA' (Get-HexOf 'MediumAquamarine')
    }

    Test-It 'None yields no colour' {
        Assert-Null (Get-RgbOf 'None')
    }

    Test-It 'invalid value rejected' {
        Assert-Null (Get-RgbOf 'not-a-colour')
    }

    Test-It 'empty string rejected' {
        Assert-Null (Get-RgbOf '   ')
    }

    Test-It 'conversion to hex' {
        $r = & $m { ConvertTo-TcHex -Rgb @{ R = 1; G = 22; B = 255 } }
        Assert-Equal '#0116FF' $r
    }

    # ======================================================================
    Write-Section 'Blending and derived colours'

    Test-It 'blending at 0 returns the base' {
        Assert-Equal '#0C0C0C' (Get-BlendHex @{R=12;G=12;B=12} @{R=255;G=0;B=0} 0)
    }

    Test-It 'blending at 1 returns the colour' {
        Assert-Equal '#FF0000' (Get-BlendHex @{R=12;G=12;B=12} @{R=255;G=0;B=0} 1)
    }

    Test-It 'blending at 0.5 is halfway' {
        Assert-Equal '#808080' (Get-BlendHex @{R=0;G=0;B=0} @{R=255;G=255;B=255} 0.5)
    }

    Test-It 'blending clamps out-of-range values' {
        Assert-Equal '#FFFFFF' (Get-BlendHex @{R=0;G=0;B=0} @{R=255;G=255;B=255} 5)
        Assert-Equal '#000000' (Get-BlendHex @{R=0;G=0;B=0} @{R=255;G=255;B=255} -3)
    }

    Test-It 'the default blend stays dark, therefore readable' {
        # A 0.30 tint over a Campbell background: the luma must stay low.
        $hex = Get-BlendHex @{R=12;G=12;B=12} (Get-RgbOf '#61DAFB') 0.30
        $rgb = Get-RgbOf $hex
        $luma = (0.2126 * $rgb.R + 0.7152 * $rgb.G + 0.0722 * $rgb.B) / 255
        Assert-True ($luma -lt 0.45) "luma too high ($([Math]::Round($luma, 3))) for $hex"
    }

    Test-It 'automatic colour is deterministic' {
        Assert-Equal (Get-AutoHexOf 'oseille') (Get-AutoHexOf 'oseille')
    }

    Test-It 'automatic colour is case-insensitive' {
        Assert-Equal (Get-AutoHexOf 'Oseille') (Get-AutoHexOf 'oseille')
    }

    Test-It 'distinct automatic colours for distinct names' {
        $colors = foreach ($n in @('oseille', 'pastel', 'superviseur', 'ioda_v3', 'rag-megane', 'sgi', 'TerminalColors')) {
            Get-AutoHexOf $n
        }
        $unique = @($colors | Select-Object -Unique)
        Assert-True ($unique.Count -ge 6) "at least 6 distinct colours out of 7, got $($unique.Count): $($colors -join ' ')"
    }

    Test-It 'automatic colour in the expected format' {
        Assert-True ((Get-AutoHexOf 'quelque-chose') -match '^#[0-9A-F]{6}$')
    }

    Test-It 'automatic colour neither too dark nor too light' {
        foreach ($n in @('a', 'depot-test', 'zzz-projet', 'Superviseur_C2')) {
            $rgb = Get-RgbOf (Get-AutoHexOf $n)
            $luma = (0.2126 * $rgb.R + 0.7152 * $rgb.G + 0.0722 * $rgb.B) / 255
            Assert-True ($luma -gt 0.08 -and $luma -lt 0.85) "luma out of bounds for ${n}: $([Math]::Round($luma, 3))"
        }
    }

    Test-It 'red emoji for a red colour' {
        Assert-Equal ([char]::ConvertFromUtf32(0x1F7E5)) (Get-EmojiOf '#E00000')
    }

    Test-It 'green emoji for a green colour' {
        Assert-Equal ([char]::ConvertFromUtf32(0x1F7E9)) (Get-EmojiOf '#215732')
    }

    Test-It 'blue emoji for a blue colour' {
        Assert-Equal ([char]::ConvertFromUtf32(0x1F7E6)) (Get-EmojiOf '#61DAFB')
    }

    Test-It 'black emoji for a dark desaturated colour' {
        Assert-Equal ([char]::ConvertFromUtf32(0x2B1B)) (Get-EmojiOf '#303030')
    }

    Test-It 'white emoji for a light desaturated colour' {
        Assert-Equal ([char]::ConvertFromUtf32(0x2B1C)) (Get-EmojiOf '#EEEEEE')
    }

    Test-It 'RGB / HSL round trip' {
        $r = & $m {
            param($hex)
            $hsl = ConvertTo-TcHsl -Rgb (ConvertFrom-TcColor -Value $hex)
            ConvertTo-TcHex -Rgb (ConvertFrom-TcHsl -Hue $hsl.H -Saturation $hsl.S -Lightness $hsl.L)
        } '#4682B4'
        Assert-Equal '#4682B4' $r
    }

    # ======================================================================
    Write-Section 'Tolerant JSON'

    Test-It 'end-of-line comments removed' {
        Assert-Equal 1 (Get-ParsedJson "{ `"a`": 1 // commentaire`n }").a
    }

    Test-It 'block comments removed' {
        Assert-Equal 2 (Get-ParsedJson '{ /* bloc */ "a": 2 }').a
    }

    Test-It 'trailing comma tolerated' {
        Assert-Equal 3 (Get-ParsedJson '{ "a": 3, }').a
    }

    Test-It 'slashes inside a string are not taken for comments' {
        Assert-Equal 'http://example.org // not a comment' (Get-ParsedJson '{ "a": "http://example.org // not a comment" }').a
    }

    Test-It 'escaped quotes do not break parsing' {
        Assert-Equal 'guillemet " puis // rien' (Get-ParsedJson '{ "a": "guillemet \" puis // rien" }').a
    }

    Test-It 'comment removal preserves the length' {
        $r = & $m {
            $text = "{ `"a`": 1, // xyz`n  `"b`": 2 }"
            @{ Original = $text.Length; Clean = (Remove-TcJsonComments -Text $text).Length }
        }
        Assert-Equal $r.Original $r.Clean
    }

    Test-It 'invalid JSON returns null without throwing' {
        Assert-Null (Get-ParsedJson '{ this is not json')
    }

    Test-It 'property with a dotted name' {
        $r = & $m { param($t) Get-TcJsonProperty -InputObject (ConvertFrom-TcJsonText -Text $t) -Name 'peacock.color' } '{ "peacock.color": "#215732" }'
        Assert-Equal '#215732' $r
    }

    Test-It 'absent property returns null' {
        $r = & $m { param($t) Get-TcJsonProperty -InputObject (ConvertFrom-TcJsonText -Text $t) -Name 'absente' } '{ "a": 1 }'
        Assert-Null $r
    }

    # ======================================================================
    Write-Section 'Git detection'

    $gitRepo = New-FixtureDir 'git\monrepo'
    New-Fixture 'git\monrepo\.git\HEAD' "ref: refs/heads/feature/ma-branche`n" | Out-Null
    New-FixtureDir 'git\monrepo\src\lib' | Out-Null

    Test-It 'repository root detected' {
        Assert-True (& $m { param($p) Test-TcGitRoot -Path $p } $gitRepo)
    }

    Test-It 'a subfolder is not a root' {
        Assert-True (-not (& $m { param($p) Test-TcGitRoot -Path $p } (Join-Path $gitRepo 'src')))
    }

    Test-It 'branch read from HEAD' {
        Assert-Equal 'feature/ma-branche' (& $m { param($p) Get-TcGitBranch -Path $p } $gitRepo)
    }

    Test-It 'root found from a deep subfolder' {
        Assert-Equal $gitRepo (& $m { param($p) Get-TcGitRootFrom -Path $p } (Join-Path $gitRepo 'src\lib'))
    }

    Test-It 'Git worktree (.git file) recognised' {
        $worktree = New-FixtureDir 'git\worktree'
        New-Fixture 'git\wtdata\HEAD' "ref: refs/heads/wt-branche`n" | Out-Null
        New-Fixture 'git\worktree\.git' ('gitdir: ' + (Join-Path $sandbox 'git\wtdata')) | Out-Null
        Assert-Equal 'wt-branche' (& $m { param($p) Get-TcGitBranch -Path $p } $worktree)
    }

    Test-It 'detached HEAD returns null' {
        $p = New-FixtureDir 'git\detache'
        New-Fixture 'git\detache\.git\HEAD' "a1b2c3d4e5f6`n" | Out-Null
        Assert-Null (& $m { param($x) Get-TcGitBranch -Path $x } $p)
    }

    # ======================================================================
    Write-Section 'Colour resolution'

    $projConfig = New-FixtureDir 'resolve\with-config'
    New-Fixture 'resolve\with-config\.terminalcolors.json' '{ "color": "#215732", "name": "Oseille" }' | Out-Null
    New-FixtureDir 'resolve\with-config\src\deep\deeper' | Out-Null

    Test-It 'configuration read in the folder itself' {
        $r = Get-ResolvedColor $projConfig
        Assert-Equal '#215732' $r.Color
        Assert-Equal 'Oseille' $r.Name
        Assert-Equal 'Config' $r.Source
    }

    Test-It 'configuration inherited by subfolders' {
        $r = Get-ResolvedColor (Join-Path $projConfig 'src\deep\deeper')
        Assert-Equal '#215732' $r.Color
        Assert-Equal $projConfig $r.Root
    }

    Test-It 'default name = folder name' {
        $p = New-FixtureDir 'resolve\no-name'
        New-Fixture 'resolve\no-name\.terminalcolors.json' '{ "color": "Teal" }' | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal 'no-name' $r.Name
        Assert-Equal '#008080' $r.Color
    }

    Test-It 'applyToSubfolders false limits it to the folder' {
        $p = New-FixtureDir 'resolve\strict'
        New-Fixture 'resolve\strict\.terminalcolors.json' '{ "color": "#112233", "applyToSubfolders": false }' | Out-Null
        New-FixtureDir 'resolve\strict\enfant' | Out-Null

        Assert-Equal '#112233' (Get-ResolvedColor $p).Color
        Assert-Null (Get-ResolvedColor (Join-Path $p 'enfant') $false)
    }

    Test-It 'auto colour in the configuration' {
        $p = New-FixtureDir 'resolve\auto'
        New-Fixture 'resolve\auto\.terminalcolors.json' '{ "color": "auto", "name": "oseille" }' | Out-Null
        Assert-Equal (Get-AutoHexOf 'oseille') (Get-ResolvedColor $p).Color
    }

    Test-It 'project-specific tint' {
        $p = New-FixtureDir 'resolve\teinte'
        New-Fixture 'resolve\teinte\.terminalcolors.json' '{ "color": "#445566", "tint": 0.8 }' | Out-Null
        Assert-Equal 0.8 (Get-ResolvedColor $p).Tint
    }

    Test-It 'custom icon' {
        $p = New-FixtureDir 'resolve\icone'
        New-Fixture 'resolve\icone\.terminalcolors.json' '{ "color": "#445566", "icon": "ZZ" }' | Out-Null
        Assert-Equal 'ZZ' (Get-ResolvedColor $p).Icon
    }

    Test-It 'per-Git-branch colour' {
        $p = New-FixtureDir 'resolve\branches'
        New-Fixture 'resolve\branches\.git\HEAD' "ref: refs/heads/release/2026.1`n" | Out-Null
        New-Fixture 'resolve\branches\.terminalcolors.json' '{ "color": "#215732", "branches": { "release/*": "#B71C1C" } }' | Out-Null
        Assert-Equal '#B71C1C' (Get-ResolvedColor $p).Color
    }

    Test-It 'per-branch colour inherited in a subfolder' {
        $p = Join-Path $sandbox 'resolve\branches'
        New-FixtureDir 'resolve\branches\src' | Out-Null
        Assert-Equal '#B71C1C' (Get-ResolvedColor (Join-Path $p 'src')).Color
    }

    Test-It 'a branch with no match keeps the default colour' {
        $p = New-FixtureDir 'resolve\branches2'
        New-Fixture 'resolve\branches2\.git\HEAD' "ref: refs/heads/main`n" | Out-Null
        New-Fixture 'resolve\branches2\.terminalcolors.json' '{ "color": "#215732", "branches": { "release/*": "#B71C1C" } }' | Out-Null
        Assert-Equal '#215732' (Get-ResolvedColor $p).Color
    }

    Test-It 'unreadable configuration ignored without error' {
        $p = New-FixtureDir 'resolve\broken'
        New-Fixture 'resolve\broken\.terminalcolors.json' '{ this is not json' | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'unknown colour in the configuration ignored' {
        $p = New-FixtureDir 'resolve\unknown-colour'
        New-Fixture 'resolve\unknown-colour\.terminalcolors.json' '{ "color": "faded-mauve" }' | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'Peacock colour read from .vscode/settings.json' {
        $p = New-FixtureDir 'resolve\peacock'
        New-Fixture 'resolve\peacock\.vscode\settings.json' @'
{
    // configuration written by Peacock
    "workbench.colorCustomizations": {
        "titleBar.activeBackground": "#215732",
    },
    "peacock.color": "#61dafb"
}
'@ | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#61DAFB' $r.Color
        Assert-Equal 'Peacock' $r.Source
    }

    Test-It 'falls back to titleBar.activeBackground without peacock.color' {
        $p = New-FixtureDir 'resolve\peacock-ancien'
        New-Fixture 'resolve\peacock-ancien\.vscode\settings.json' '{ "workbench.colorCustomizations": { "titleBar.activeBackground": "#215732" } }' | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#215732' $r.Color
        Assert-Equal 'Peacock' $r.Source
    }

    Test-It 'VS Code settings.json with no colour ignored' {
        $p = New-FixtureDir 'resolve\vscode-neutre'
        New-Fixture 'resolve\vscode-neutre\.vscode\settings.json' '{ "editor.tabSize": 4 }' | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'Solution Colors colour read from .vs' {
        $p = New-FixtureDir 'resolve\solution'
        New-Fixture 'resolve\solution\.vs\MaSolution\color.txt' "master:Teal`n" | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#008080' $r.Color
        Assert-Equal 'SolutionColors' $r.Source
        Assert-Equal 'MaSolution' $r.Name
    }

    Test-It 'Solution Colors: legacy format with no branch' {
        $p = New-FixtureDir 'resolve\solution-ancien'
        New-Fixture 'resolve\solution-ancien\.vs\Sol\color.txt' "Cyan`n" | Out-Null
        Assert-Equal '#00FFFF' (Get-ResolvedColor $p).Color
    }

    Test-It 'Solution Colors: the current branch wins' {
        $p = New-FixtureDir 'resolve\solution-branche'
        New-Fixture 'resolve\solution-branche\.git\HEAD' "ref: refs/heads/dev`n" | Out-Null
        New-Fixture 'resolve\solution-branche\.vs\Sol\color.txt' "master:Teal`ndev:Pumpkin`n" | Out-Null
        Assert-Equal '#FF4500' (Get-ResolvedColor $p).Color
    }

    Test-It 'Solution Colors: None ignored' {
        $p = New-FixtureDir 'resolve\solution-none'
        New-Fixture 'resolve\solution-none\.vs\Sol\color.txt' "master:None`n" | Out-Null
        Assert-Null (Get-ResolvedColor $p $false)
    }

    Test-It 'the module configuration takes priority over Peacock' {
        $p = New-FixtureDir 'resolve\priorite'
        New-Fixture 'resolve\priorite\.terminalcolors.json' '{ "color": "#111111" }' | Out-Null
        New-Fixture 'resolve\priorite\.vscode\settings.json' '{ "peacock.color": "#222222" }' | Out-Null
        Assert-Equal '#111111' (Get-ResolvedColor $p).Color
    }

    Test-It 'Peacock takes priority over Solution Colors' {
        $p = New-FixtureDir 'resolve\priorite2'
        New-Fixture 'resolve\priorite2\.vscode\settings.json' '{ "peacock.color": "#222222" }' | Out-Null
        New-Fixture 'resolve\priorite2\.vs\Sol\color.txt' "master:Teal`n" | Out-Null
        Assert-Equal '#222222' (Get-ResolvedColor $p).Color
    }

    Test-It 'Solution Colors takes priority over the automatic Git colour' {
        $p = New-FixtureDir 'resolve\priorite3'
        New-Fixture 'resolve\priorite3\.git\HEAD' "ref: refs/heads/main`n" | Out-Null
        New-Fixture 'resolve\priorite3\.vs\Sol\color.txt' "main:Teal`n" | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal '#008080' $r.Color
        Assert-Equal 'SolutionColors' $r.Source
    }

    Test-It 'the nearest folder wins' {
        $parent = New-FixtureDir 'resolve\imbrique'
        New-Fixture 'resolve\imbrique\.terminalcolors.json' '{ "color": "#111111" }' | Out-Null
        $child = New-FixtureDir 'resolve\imbrique\sous-projet'
        New-Fixture 'resolve\imbrique\sous-projet\.terminalcolors.json' '{ "color": "#222222" }' | Out-Null

        Assert-Equal '#222222' (Get-ResolvedColor $child).Color
        Assert-Equal '#111111' (Get-ResolvedColor $parent).Color
    }

    Test-It 'automatic colour for a Git repository' {
        $p = New-FixtureDir 'resolve\depot-nu'
        New-Fixture 'resolve\depot-nu\.git\HEAD' "ref: refs/heads/main`n" | Out-Null
        $r = Get-ResolvedColor $p
        Assert-Equal 'GitRepository' $r.Source
        Assert-Equal (Get-AutoHexOf 'depot-nu') $r.Color
    }

    Test-It 'automatic colour can be disabled' {
        Assert-Null (Get-ResolvedColor (Join-Path $sandbox 'resolve\depot-nu') $false)
    }

    Test-It 'a folder with nothing returns no colour' {
        Assert-Null (Get-ResolvedColor (New-FixtureDir 'resolve\vide') $false)
    }

    Test-It 'a non-existent path raises no error' {
        Assert-Null (Get-ResolvedColor (Join-Path $sandbox 'resolve\not-on-disk') $false)
    }

    # ======================================================================
    Write-Section 'Resolution cache'

    Test-It 'a change to the file is picked up' {
        $p = New-FixtureDir 'cache\projet'
        $file = New-Fixture 'cache\projet\.terminalcolors.json' '{ "color": "#111111" }'

        & $m { Clear-TcResolveCache }
        Assert-Equal '#111111' (Get-ResolvedColor $p $false -UseCache).Color

        [System.IO.File]::WriteAllText($file, '{ "color": "#999999" }', (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::SetLastWriteTimeUtc($file, (Get-Date).ToUniversalTime().AddSeconds(5))

        Assert-Equal '#999999' (Get-ResolvedColor $p $false -UseCache).Color
    }

    Test-It 'the tree walk terminates at a drive root' {
        # Must terminate, with no exception and no infinite loop.
        Assert-Null (Get-ResolvedColor 'C:\' $false)
    }

    Test-It 'the walk terminates on a UNC path' {
        # Deliberately non-existent path: only termination is checked.
        Assert-Null (Get-ResolvedColor '\\serveur-inexistant\partage\projet\src' $false)
    }

    Test-It 'the cache returns the same object when nothing changes' {
        $p = Join-Path $sandbox 'cache\projet'
        $a = Get-ResolvedColor $p $false -UseCache
        $b = Get-ResolvedColor $p $false -UseCache
        Assert-True ([object]::ReferenceEquals($a, $b)) 'the second call should come from the cache'
    }

    # ======================================================================
    Write-Section 'Control sequences and title'

    Test-It 'correct OSC 11 sequence' {
        $r = & $m { Get-TcBackgroundSequence -Rgb @{ R = 12; G = 87; B = 50 } }
        Assert-Equal (([char]27) + ']11;rgb:0c/57/32' + ([char]7)) $r
    }

    Test-It 'OSC 111 reset sequence' {
        $r = & $m { Get-TcBackgroundResetSequence }
        Assert-Equal (([char]27) + ']111' + ([char]7)) $r
    }

    Test-It 'title template' {
        $r = & $m {
            $info = [pscustomobject]@{ Icon = 'ZZ'; Name = 'Oseille'; Color = '#215732' }
            Format-TcTitle -Format '{icon} {name} [{color}] {folder}' -Info $info -Path 'C:\Repos\oseille\src'
        }
        Assert-Equal 'ZZ Oseille [#215732] src' $r
    }

    Test-It 'a template with no icon leaves no extra space' {
        $r = & $m {
            $info = [pscustomobject]@{ Icon = ''; Name = 'Oseille'; Color = '#215732' }
            Format-TcTitle -Format '{icon} {name}' -Info $info -Path 'C:\Repos\oseille'
        }
        Assert-Equal 'Oseille' $r
    }

    Test-It 'complete {path} token' {
        $r = & $m {
            $info = [pscustomobject]@{ Icon = ''; Name = 'X'; Color = '#000000' }
            Format-TcTitle -Format '{path}' -Info $info -Path 'C:\Repos\oseille\src'
        }
        Assert-Equal 'C:\Repos\oseille\src' $r
    }

    # ======================================================================
    Write-Section 'Windows Terminal settings'

    Test-It 'profile merged with profiles.defaults' {
        $r = & $m { param($t) Get-TcWtProfile -Settings (ConvertFrom-TcJsonText -Text $t) -ProfileId '{bbb}' } @'
{
    "defaultProfile": "{aaa}",
    "profiles": {
        "defaults": { "colorScheme": "One Half Dark", "suppressApplicationTitle": true },
        "list": [ { "guid": "{aaa}", "name": "PS" }, { "guid": "{bbb}", "name": "Autre", "background": "#123456" } ]
    }
}
'@
        Assert-Equal '#123456' $r.background
        Assert-Equal 'One Half Dark' $r.colorScheme
        Assert-True $r.suppressApplicationTitle
    }

    Test-It 'falls back to the default profile when the id is unknown' {
        $r = & $m { param($t) Get-TcWtProfile -Settings (ConvertFrom-TcJsonText -Text $t) -ProfileId '{inconnu}' } '{ "defaultProfile": "{aaa}", "profiles": { "defaults": {}, "list": [ { "guid": "{aaa}", "background": "#0C0C0C" } ] } }'
        Assert-Equal '#0C0C0C' $r.background
    }

    Test-It 'reference background derived from a built-in colour scheme' {
        $r = & $m { ConvertTo-TcHex -Rgb (Get-TcBaseBackground) }
        Assert-True ($r -match '^#[0-9A-F]{6}$') "fond inattendu : $r"
    }

    # ======================================================================
    Write-Section 'Windows Terminal theme installation'

    $wtSample = @'
{
    // This file was created automatically.
    "$schema": "https://aka.ms/terminal-profiles-schema",
    "actions": [],
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles":
    {
        "defaults": {},
        "list":
        [
            {
                "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "name": "Windows PowerShell"
            }
        ]
    },
    "schemes": [],
    "themes": []
}
'@

    Test-It 'theme inserted and selected, JSON still valid' {
        $path = New-Fixture 'wt\case1\settings.json' $wtSample
        $r = Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed

        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed 'the result must stay valid JSON'
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)

        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })
        Assert-Equal 1 $theme.Count
        Assert-Equal 'terminalBackground' ([string]$theme[0].tab.background)
    }

    # Measured behaviour of Windows Terminal: the SELECTED tab is painted with its
    # own background colour opaquely, while a BACKGROUND tab is composited at about
    # 30 % opacity over the tab row. So [tab] must follow the project - it is the
    # only per-tab value available - and the row must be a fixed colour, both so
    # the strip does not take the active project's colour and so background tabs
    # are composited over a stable base instead of their neighbour's colour.
    Test-It 'every tab follows its own project, selected or not' {
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText((Join-Path $sandbox 'wt\case1\settings.json')))
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        Assert-Equal 'terminalBackground' ([string]$theme.tab.background)
        Assert-Equal 'terminalBackground' ([string]$theme.tab.unfocusedBackground)
    }

    Test-It 'the tab row is a fixed colour, never the project''s' {
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText((Join-Path $sandbox 'wt\case1\settings.json')))
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        foreach ($key in 'background', 'unfocusedBackground') {
            $value = [string]$theme.tabRow.$key
            Assert-True ($value -match '^#[0-9A-Fa-f]{6}$') "tabRow.$key expected a fixed colour, got [$value]"
        }
    }

    # DwmSetWindowAttribute(DWMWA_BORDER_COLOR) returns S_OK on a Windows Terminal
    # window and changes nothing - measured. The theme is the only way in.
    Test-It 'the window border follows the project through window.frame' {
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText((Join-Path $sandbox 'wt\case1\settings.json')))
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        Assert-Equal 'terminalBackground' ([string]$theme.window.frame)
        Assert-Equal 'terminalBackground' ([string]$theme.window.unfocusedFrame)
    }

    Test-It 'a theme without window.frame counts as outdated' {
        $path = New-Fixture 'wt\noframe\settings.json' @'
{
    "theme": "TerminalColors",
    "themes":
    [
        {
            "name": "TerminalColors",
            "tab": { "background": "terminalBackground", "unfocusedBackground": "terminalBackground" },
            "tabRow": { "background": "#0C0C0C", "unfocusedBackground": "#0C0C0C" },
            "window": { "applicationTheme": "system" }
        }
    ]
}
'@
        $r = Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed 'a theme that cannot colour the border must be replaced'
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        Assert-Equal 'terminalBackground' ([string]$theme.window.frame)
    }

    Test-It 'the tab-row colour comes from the profile''s colour scheme' {
        $path = New-Fixture 'wt\tabrow\settings.json' @'
{
    "defaultProfile": "{aaa}",
    "profiles": { "defaults": {}, "list": [ { "guid": "{aaa}", "name": "PS", "colorScheme": "MyScheme" } ] },
    "schemes": [ { "name": "MyScheme", "background": "#102030" } ],
    "themes": []
}
'@
        $r = Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        Assert-Equal '#102030' $r.TabRowColor
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        Assert-Equal '#102030' ([string]$theme.tabRow.background)
        Assert-Equal '#102030' ([string]$theme.tabRow.unfocusedBackground)
    }

    Test-It '-TabRowColor imposes the tab-row colour' {
        $path = New-Fixture 'wt\tabrow2\settings.json' $wtSample
        $r = Install-TerminalColorsTheme -SettingsPath $path -TabRowColor 'Black' -Confirm:$false
        Assert-Equal '#000000' $r.TabRowColor
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        Assert-Equal '#000000' ([string]$theme.tabRow.background)
    }

    Test-It 'invalid -TabRowColor refused without modification' {
        $path = New-Fixture 'wt\tabrow3\settings.json' $wtSample
        $before = [System.IO.File]::ReadAllText($path)
        $threw = $false
        try { Install-TerminalColorsTheme -SettingsPath $path -TabRowColor 'not-a-colour' -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw 'an error must be raised'
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'a theme with terminalBackground on the row is upgraded without -Force' {
        # That shape made background tabs borrow the active project's colour.
        $path = New-Fixture 'wt\legacyrow\settings.json' @'
{
    "theme": "TerminalColors",
    "themes":
    [
        {
            "name": "TerminalColors",
            "tab": { "background": "terminalBackground", "unfocusedBackground": "terminalBackground" },
            "tabRow": { "background": "terminalBackground", "unfocusedBackground": "terminalBackground" }
        }
    ]
}
'@
        $r = Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed 'an outdated theme must be replaced even without -Force'

        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal 1 @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' }).Count
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        Assert-Equal 'terminalBackground' ([string]$theme.tab.unfocusedBackground)
        Assert-True ([string]$theme.tabRow.background -match '^#') 'the row must be pinned'
    }

    Test-It 'a theme with pinned tabs is upgraded without -Force' {
        # Pinning the tabs instead of the row cost them their own colour.
        $path = New-Fixture 'wt\legacytabs\settings.json' @'
{
    "theme": "TerminalColors",
    "themes":
    [
        {
            "name": "TerminalColors",
            "tab": { "background": "terminalBackground", "unfocusedBackground": "#0C0C0C" },
            "tabRow": { "background": "terminalBackground", "unfocusedBackground": "terminalBackground" }
        }
    ]
}
'@
        $r = Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        $theme = @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' })[0]
        Assert-Equal 'terminalBackground' ([string]$theme.tab.unfocusedBackground)
        Assert-True ([string]$theme.tabRow.background -match '^#') 'the row must be pinned'
    }

    Test-It 'an up-to-date theme is left alone' {
        $path = Join-Path $sandbox 'wt\legacytabs\settings.json'
        $before = [System.IO.File]::ReadAllText($path)
        $r = Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        Assert-True (-not $r.Changed) 'nothing to change on a second run'
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'comments, profiles and other keys preserved' {
        $text = [System.IO.File]::ReadAllText((Join-Path $sandbox 'wt\case1\settings.json'))
        Assert-True ($text.Contains('// This file was created automatically.')) 'the comment must survive'
        Assert-True ($text.Contains('"name": "Windows PowerShell"')) 'the profiles must survive'
        Assert-True ($text.Contains('"schemes": []')) 'the other keys must survive'
        Assert-True ($text.Contains('%SystemRoot%\\System32')) 'the escapes must survive'
    }

    Test-It 'backup created' {
        Assert-True (@(Get-ChildItem (Join-Path $sandbox 'wt\case1') -Filter '*.terminalcolors-backup-*').Count -ge 1)
    }

    Test-It 'second run does not duplicate' {
        $path = Join-Path $sandbox 'wt\case1\settings.json'
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, '"name"\s*:\s*"TerminalColors"')).Count
    }

    Test-It '-Force does not duplicate the theme' {
        $path = Join-Path $sandbox 'wt\case1\settings.json'
        Install-TerminalColorsTheme -SettingsPath $path -Force -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, '"name"\s*:\s*"TerminalColors"')).Count
        Assert-NotNull (Get-ParsedJson $text)
    }

    Test-It 'themes already populated: added without breaking what is there' {
        $path = New-Fixture 'wt\case2\settings.json' @'
{
    "theme": "dark",
    "themes":
    [
        {
            "name": "MonTheme",
            "tab": { "background": "#FF0000" }
        }
    ]
}
'@
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed 'valid JSON expected'
        Assert-Equal 2 @($parsed.themes).Count
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)
        Assert-Equal 1 @($parsed.themes | Where-Object { $_.name -eq 'MonTheme' }).Count
    }

    Test-It 'no themes key: the section is created' {
        $path = New-Fixture 'wt\case3\settings.json' '{ "defaultProfile": "{aaa}" }'
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)
        Assert-Equal 1 @($parsed.themes).Count
        Assert-Equal '{aaa}' ([string]$parsed.defaultProfile)
    }

    Test-It 'theme in light/dark object form is replaced' {
        $path = New-Fixture 'wt\case4\settings.json' '{ "theme": { "dark": "dark", "light": "light" }, "themes": [] }'
        Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-Equal 'TerminalColors' ([string]$parsed.theme)
    }

    Test-It 'invalid JSON refused without modification' {
        $path = New-Fixture 'wt\case5\settings.json' '{ "themes": [ this is broken'
        $before = [System.IO.File]::ReadAllText($path)
        $threw = $false
        try { Install-TerminalColorsTheme -SettingsPath $path -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw 'an error must be raised'
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'settings.json missing: explicit error' {
        $threw = $false
        try { Install-TerminalColorsTheme -SettingsPath (Join-Path $sandbox 'wt\nulle-part\settings.json') -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
    }

    Test-It '-WhatIf changes nothing' {
        $path = New-Fixture 'wt\case6\settings.json' $wtSample
        $before = [System.IO.File]::ReadAllText($path)
        Install-TerminalColorsTheme -SettingsPath $path -WhatIf | Out-Null
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'uninstall: theme removed, JSON valid, existing content preserved' {
        $path = Join-Path $sandbox 'wt\case2\settings.json'
        Uninstall-TerminalColorsTheme -SettingsPath $path -Confirm:$false
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal 0 @($parsed.themes | Where-Object { $_.name -eq 'TerminalColors' }).Count
        Assert-Equal 1 @($parsed.themes | Where-Object { $_.name -eq 'MonTheme' }).Count
        Assert-True ([string]$parsed.theme -ne 'TerminalColors') "theme selectionne inattendu : $($parsed.theme)"
    }

    # ======================================================================
    Write-Section 'Backdrop PNG encoding'

    # The PNG is encoded by hand (System.Drawing is not guaranteed on
    # PowerShell 7), so the file structure is checked byte by byte.
    function Get-SolidPngBytes {
        param([string] $Color)
        & $m { param($c) New-TcSolidPngBytes -Rgb (ConvertFrom-TcColor -Value $c) } $Color
    }

    function Get-PngChunk {
        param([byte[]] $Bytes, [string] $Type)
        $i = 8
        while ($i + 8 -le $Bytes.Length) {
            $len = ([int]$Bytes[$i] -shl 24) -bor ([int]$Bytes[$i + 1] -shl 16) -bor ([int]$Bytes[$i + 2] -shl 8) -bor [int]$Bytes[$i + 3]
            $name = [System.Text.Encoding]::ASCII.GetString($Bytes, $i + 4, 4)
            if ($name -eq $Type) {
                $data = New-Object 'byte[]' $len
                if ($len -gt 0) { [Array]::Copy($Bytes, $i + 8, $data, 0, $len) }
                return @{ Data = $data; Start = $i }
            }
            $i += 12 + $len
        }
        return $null
    }

    Test-It 'PNG signature and expected size' {
        $bytes = Get-SolidPngBytes '#0C0C0C'
        $signature = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        for ($i = 0; $i -lt 8; $i++) { Assert-Equal $signature[$i] $bytes[$i] "octet de signature $i" }
        # 8 signature + 25 IHDR + 37 IDAT + 12 IEND
        Assert-Equal 82 $bytes.Length 'a solid 2x2 PNG must fit in 82 bytes'
    }

    Test-It 'IHDR declares a 2x2 8-bit truecolor image' {
        $bytes = Get-SolidPngBytes '#215732'
        $ihdr = Get-PngChunk -Bytes $bytes -Type 'IHDR'
        Assert-NotNull $ihdr 'the IHDR chunk must exist'
        Assert-Equal 13 $ihdr.Data.Length
        Assert-Equal 2 $ihdr.Data[3] 'largeur'
        Assert-Equal 2 $ihdr.Data[7] 'hauteur'
        Assert-Equal 8 $ihdr.Data[8] 'bits per channel'
        Assert-Equal 2 $ihdr.Data[9] 'RGB colour type'
        Assert-Equal 0 $ihdr.Data[12] 'non entrelace'
    }

    Test-It 'every chunk CRC is correct' {
        $bytes = Get-SolidPngBytes '#FF8000'
        $i = 8
        $blocks = 0
        while ($i + 8 -le $bytes.Length) {
            $len = ([int]$bytes[$i] -shl 24) -bor ([int]$bytes[$i + 1] -shl 16) -bor ([int]$bytes[$i + 2] -shl 8) -bor [int]$bytes[$i + 3]
            $covered = New-Object 'byte[]' (4 + $len)
            [Array]::Copy($bytes, $i + 4, $covered, 0, 4 + $len)
            $expected = & $m { param($b) Get-TcCrc32 -Bytes $b } $covered
            $offset = $i + 8 + $len
            $actual = ([int64]$bytes[$offset] -shl 24) -bor ([int64]$bytes[$offset + 1] -shl 16) -bor ([int64]$bytes[$offset + 2] -shl 8) -bor [int64]$bytes[$offset + 3]
            Assert-Equal $expected $actual "chunk CRC at offset $i"
            $blocks++
            $i = $offset + 4
        }
        Assert-Equal 3 $blocks 'IHDR, IDAT and IEND expected'
        Assert-Equal $bytes.Length $i 'no byte must remain after IEND'
    }

    Test-It 'the zlib stream carries the requested colour and its Adler-32' {
        $bytes = Get-SolidPngBytes '#215732'
        $idat = Get-PngChunk -Bytes $bytes -Type 'IDAT'
        Assert-NotNull $idat
        Assert-Equal 0x78 $idat.Data[0] 'en-tete zlib CMF'
        Assert-Equal 0x01 $idat.Data[1] 'en-tete zlib FLG'
        Assert-Equal 0 (((([int]$idat.Data[0]) * 256) + [int]$idat.Data[1]) % 31) 'the zlib header must be divisible by 31'
        Assert-Equal 0x01 $idat.Data[2] 'bloc final non compresse'

        # LEN / NLEN : 2 lignes de (1 octet de filtre + 2 pixels RVB) = 14
        Assert-Equal 14 $idat.Data[3]
        Assert-Equal 0 $idat.Data[4]
        Assert-Equal 0xF1 $idat.Data[5]
        Assert-Equal 0xFF $idat.Data[6]

        $raw = New-Object 'byte[]' 14
        [Array]::Copy($idat.Data, 7, $raw, 0, 14)
        Assert-Equal 0 $raw[0] 'filter byte of the first row'
        Assert-Equal 0x21 $raw[1]; Assert-Equal 0x57 $raw[2]; Assert-Equal 0x32 $raw[3]
        Assert-Equal 0 $raw[7] 'filter byte of the second row'
        Assert-Equal 0x21 $raw[8]; Assert-Equal 0x57 $raw[9]; Assert-Equal 0x32 $raw[10]

        $expected = & $m { param($b) Get-TcAdler32 -Bytes $b } $raw
        $offset = 7 + 14
        $actual = ([int64]$idat.Data[$offset] -shl 24) -bor ([int64]$idat.Data[$offset + 1] -shl 16) -bor ([int64]$idat.Data[$offset + 2] -shl 8) -bor [int64]$idat.Data[$offset + 3]
        Assert-Equal $expected $actual 'Adler-32 of the zlib stream'
    }

    Test-It 'encoding is deterministic and differs per colour' {
        $a = Get-SolidPngBytes '#215732'
        $b = Get-SolidPngBytes '#215732'
        $c = Get-SolidPngBytes '#215733'
        Assert-Equal ([Convert]::ToBase64String($a)) ([Convert]::ToBase64String($b)) 'same colour, same bytes'
        Assert-True ([Convert]::ToBase64String($a) -ne [Convert]::ToBase64String($c)) 'different colours, different bytes'
    }

    Test-It 'the PNG is read back correctly by the system decoder' {
        # System.Drawing is not guaranteed everywhere: this only runs when it is
        # available, but when it is, it is the most direct proof.
        $available = $true
        try {
            if (-not ('System.Drawing.Bitmap' -as [type])) { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
        } catch { $available = $false }

        if (-not $available) {
            Write-Verbose 'System.Drawing unavailable: decoding check skipped.'
            return
        }

        $path = Join-Path $sandbox 'png\relu.png'
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($path, (Get-SolidPngBytes '#215732'))

        $bitmap = [System.Drawing.Bitmap]::FromFile($path)
        try {
            Assert-Equal 2 $bitmap.Width
            Assert-Equal 2 $bitmap.Height
            foreach ($x in 0, 1) {
                foreach ($y in 0, 1) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    Assert-Equal '#215732' ('#{0:X2}{1:X2}{2:X2}' -f $pixel.R, $pixel.G, $pixel.B) "pixel $x,$y"
                }
            }
        } finally { $bitmap.Dispose() }
    }

    # ======================================================================
    Write-Section 'Opaque backdrop'

    $backdropSample = @'
{
    // Comment to preserve.
    "defaultProfile": "{aaa}",
    "profiles":
    {
        "defaults": {},
        "list":
        [
            {
                "commandline": "%SystemRoot%\\System32\\cmd.exe",
                "guid": "{aaa}",
                "name": "PS",
                "colorScheme": "MaPalette"
            }
        ]
    },
    "schemes":
    [
        { "name": "MaPalette", "background": "#0C0C0C" }
    ],
    "themes": []
}
'@

    Test-It 'backdrop installed: three keys in profiles.defaults, JSON valid' {
        $path = New-Fixture 'backdrop\case1\settings.json' $backdropSample
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed
        Assert-Equal '#0C0C0C' $r.Color 'the colour must come from the profile colour scheme'

        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed 'the result must stay valid JSON'
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal 1 ([double]$parsed.profiles.defaults.backgroundImageOpacity)
        Assert-Equal 'fill' ([string]$parsed.profiles.defaults.backgroundImageStretchMode)
    }

    Test-It 'PNG image written, named after the colour' {
        $path = Join-Path $sandbox 'backdrop\case1\settings.json'
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        $image = [string]$parsed.profiles.defaults.backgroundImage
        Assert-True ([System.IO.File]::Exists($image)) "the image [$image] must exist"
        Assert-Equal 'backdrop-0C0C0C.png' (Split-Path $image -Leaf)
    }

    Test-It 'comments, profiles and escapes preserved' {
        $text = [System.IO.File]::ReadAllText((Join-Path $sandbox 'backdrop\case1\settings.json'))
        Assert-True ($text.Contains('// Comment to preserve.')) 'the comment must survive'
        Assert-True ($text.Contains('"name": "PS"')) 'the profiles must survive'
        Assert-True ($text.Contains('%SystemRoot%\\System32')) 'the escapes must survive'
        Assert-True ($text.Contains('"themes": []')) 'the other keys must survive'
    }

    Test-It 'second run: nothing to change, no duplication' {
        $path = Join-Path $sandbox 'backdrop\case1\settings.json'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false
        Assert-True (-not $r.Changed) 'the second run must change nothing'
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, '"backgroundImage"')).Count
        Assert-Equal 1 ([regex]::Matches($text, '"backgroundImageOpacity"')).Count
    }

    Test-It 'Test-TerminalColorsBackdrop reports the state' {
        $path = Join-Path $sandbox 'backdrop\case1\settings.json'
        $state = Test-TerminalColorsBackdrop -SettingsPath $path
        Assert-True $state.Installed
        Assert-True $state.ImageExists
        Assert-Equal '#0C0C0C' $state.Color
        Assert-True (-not $state.ForeignImage)
    }

    Test-It '-Color forces the pane colour' {
        $path = New-Fixture 'backdrop\case2\settings.json' $backdropSample
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color 'Black' -Confirm:$false
        Assert-Equal '#000000' $r.Color
        Assert-Equal 'backdrop-000000.png' (Split-Path $r.ImagePath -Leaf)
    }

    Test-It 'invalid colour refused without modification' {
        $path = New-Fixture 'backdrop\case3\settings.json' $backdropSample
        $before = [System.IO.File]::ReadAllText($path)
        $threw = $false
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color 'bleu-canard' -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw 'an error must be raised'
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'profiles.defaults missing: the key is created' {
        $path = New-Fixture 'backdrop\case4\settings.json' '{ "profiles": { "list": [] } }'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false
        Assert-True $r.Changed
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-NotNull $parsed.profiles.list 'the profile list must survive'
    }

    Test-It 'profiles key missing: the section is created' {
        $path = New-Fixture 'backdrop\case5\settings.json' '{ "defaultProfile": "{aaa}" }'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false
        Assert-True $r.Changed
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal '{aaa}' ([string]$parsed.defaultProfile)
    }

    Test-It 'legacy format where profiles is an array: explicit error' {
        $path = New-Fixture 'backdrop\case6\settings.json' '{ "profiles": [ { "guid": "{aaa}" } ] }'
        $before = [System.IO.File]::ReadAllText($path)
        $message = ''
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null } catch { $message = $_.Exception.Message }
        Assert-True ($message -like '*array*') "unexpected message: $message"
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'a background image of your own: refused without -Force' {
        $path = New-Fixture 'backdrop\case7\settings.json' '{ "profiles": { "defaults": { "backgroundImage": "C:\\images\\moi.jpg", "backgroundImageOpacity": 0.4 } } }'
        $before = [System.IO.File]::ReadAllText($path)
        $message = ''
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null } catch { $message = $_.Exception.Message }
        Assert-True ($message -like '*-Force*') "message inattendu : $message"
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It 'Test-TerminalColorsBackdrop reports a foreign image' {
        $state = Test-TerminalColorsBackdrop -SettingsPath (Join-Path $sandbox 'backdrop\case7\settings.json')
        Assert-True (-not $state.Installed)
        Assert-True $state.ForeignImage
    }

    Test-It '-Force replaces the image of your own' {
        $path = Join-Path $sandbox 'backdrop\case7\settings.json'
        $r = Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Force -Confirm:$false
        Assert-True $r.Replaced
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-Equal $r.ImagePath ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal 1 ([double]$parsed.profiles.defaults.backgroundImageOpacity)
    }

    Test-It 'uninstall restores the image of your own and its opacity' {
        $path = Join-Path $sandbox 'backdrop\case7\settings.json'
        Uninstall-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-NotNull $parsed
        Assert-Equal 'C:\images\moi.jpg' ([string]$parsed.profiles.defaults.backgroundImage)
        Assert-Equal 0.4 ([double]$parsed.profiles.defaults.backgroundImageOpacity)
    }

    Test-It 'uninstall with no previous image: the three keys disappear' {
        $path = Join-Path $sandbox 'backdrop\case1\settings.json'
        Uninstall-TerminalColorsBackdrop -SettingsPath $path -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        $parsed = Get-ParsedJson $text
        Assert-NotNull $parsed 'the result must stay valid JSON'
        Assert-True (-not $text.Contains('backgroundImage')) 'no backgroundImage key must remain'
        Assert-True ($text.Contains('// Comment to preserve.')) 'the comment must survive'
        Assert-True ($text.Contains('"name": "PS"')) 'the profiles must survive'
        Assert-True (-not (Test-TerminalColorsBackdrop -SettingsPath $path).Installed)
    }

    Test-It 'invalid JSON refused without modification' {
        $path = New-Fixture 'backdrop\case8\settings.json' '{ "profiles": { this is broken'
        $before = [System.IO.File]::ReadAllText($path)
        $threw = $false
        try { Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    Test-It '-WhatIf changes nothing' {
        $path = New-Fixture 'backdrop\case9\settings.json' $backdropSample
        $before = [System.IO.File]::ReadAllText($path)
        Install-TerminalColorsBackdrop -SettingsPath $path -Color '#123456' -WhatIf | Out-Null
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
        Assert-True (-not [System.IO.File]::Exists((Join-Path (Join-Path $sandbox 'data') 'backdrop-123456.png'))) 'no image must be written'
    }

    Test-It 'image set on a specific profile: reported as taking priority' {
        $path = New-Fixture 'backdrop\case10\settings.json' '{ "profiles": { "defaults": {}, "list": [ { "guid": "{aaa}", "name": "Special", "backgroundImage": "C:\\a.png" } ] } }'
        Install-TerminalColorsBackdrop -SettingsPath $path -Color '#101010' -Confirm:$false | Out-Null
        $state = Test-TerminalColorsBackdrop -SettingsPath $path
        Assert-True $state.Installed
        Assert-Equal 1 @($state.ProfileOverrides).Count
        Assert-Equal 'Special' ([string]$state.ProfileOverrides[0])
    }

    Test-It 'settings.json missing: explicit error' {
        $threw = $false
        try { Install-TerminalColorsBackdrop -SettingsPath (Join-Path $sandbox 'backdrop\nulle-part\settings.json') -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
    }

    # ======================================================================
    Write-Section 'System title bar'

    Test-It 'showTabsInTitlebar set to false, JSON valid' {
        $path = New-Fixture 'titlebar\case1\settings.json' $backdropSample
        $r = Install-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false
        Assert-True $r.Changed
        Assert-True $r.RestartNeeded 'a full Windows Terminal restart is required'

        $text = [System.IO.File]::ReadAllText($path)
        $parsed = Get-ParsedJson $text
        Assert-NotNull $parsed
        Assert-Equal $false ([bool]$parsed.showTabsInTitlebar)
        Assert-True ($text.Contains('// Comment to preserve.')) 'the comment must survive'
        Assert-True (Test-TerminalColorsTitleBar -SettingsPath $path)
    }

    Test-It 'second run: nothing to change' {
        $path = Join-Path $sandbox 'titlebar\case1\settings.json'
        $r = Install-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false
        Assert-True (-not $r.Changed)
        Assert-Equal 1 ([regex]::Matches([System.IO.File]::ReadAllText($path), '"showTabsInTitlebar"')).Count
    }

    Test-It 'key absent originally: uninstall removes it' {
        $path = Join-Path $sandbox 'titlebar\case1\settings.json'
        Uninstall-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-NotNull (Get-ParsedJson $text)
        Assert-True (-not $text.Contains('showTabsInTitlebar')) 'the key must disappear, not be set to true'
        Assert-True (-not (Test-TerminalColorsTitleBar -SettingsPath $path))
    }

    Test-It 'value true originally: it is restored' {
        $path = New-Fixture 'titlebar\case2\settings.json' '{ "showTabsInTitlebar": true, "profiles": { "defaults": {} } }'
        Install-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false | Out-Null
        Assert-True (Test-TerminalColorsTitleBar -SettingsPath $path)

        Uninstall-TerminalColorsTitleBar -SettingsPath $path -Confirm:$false | Out-Null
        $parsed = Get-ParsedJson ([System.IO.File]::ReadAllText($path))
        Assert-Equal $true ([bool]$parsed.showTabsInTitlebar)
    }

    Test-It '-WhatIf changes nothing' {
        $path = New-Fixture 'titlebar\case3\settings.json' $backdropSample
        $before = [System.IO.File]::ReadAllText($path)
        Install-TerminalColorsTitleBar -SettingsPath $path -WhatIf | Out-Null
        Assert-Equal $before ([System.IO.File]::ReadAllText($path))
    }

    # ======================================================================
    Write-Section 'Pure colour mode'

    Test-It '-PureColor forces the tint to 1' {
        $options = Enable-TerminalColors -PureColor -PassThru
        try {
            Assert-True $options.PureColor
            Assert-Equal 1.0 ([double]$options.Tint)
        } finally { Disable-TerminalColors -KeepColor }
    }

    Test-It '-PureColor emits the project colour undiluted' {
        # Get-TcBlendedColor with Amount = 1 returns exactly the colour, so the
        # emitted sequence must carry the project colour, not a blend.
        $sequence = & $m {
            $rgb = ConvertFrom-TcColor -Value '#215732'
            Get-TcBackgroundSequence -Rgb (Get-TcBlendedColor -Base (ConvertFrom-TcColor -Value '#0C0C0C') -Color $rgb -Amount 1.0)
        }
        Assert-Equal (([char]27) + ']11;rgb:21/57/32' + ([char]7)) $sequence
    }

    # The colour actually sent to the terminal for a project, with the reference
    # background forced so the test does not depend on the machine's settings.
    function Get-EffectiveBackgroundHex {
        param([string] $Path, [bool] $PureColor, [string] $Base = '#000000')
        & $m { param($p, $pure, $b)
            $info = Resolve-TcColor -Path $p -AutoGitColors $false -NoCache
            $options = New-TcDefaultOptions
            $options.PureColor = $pure
            ConvertTo-TcHex -Rgb (Get-TcEffectiveBackground -Info $info -Options $options -BaseBackground (ConvertFrom-TcColor -Value $b))
        } $Path $PureColor $Base
    }

    Test-It 'in pure colour, a project tint key is ignored' {
        # A project declaring "tint": 0.2 must not re-dilute the colour when
        # l'utilisateur a demande -PureColor.
        $p = New-FixtureDir 'pure\projet'
        New-Fixture 'pure\projet\.terminalcolors.json' '{ "color": "#215732", "tint": 0.2 }' | Out-Null
        Assert-Equal '#215732' (Get-EffectiveBackgroundHex -Path $p -PureColor $true)
    }

    Test-It 'without -PureColor, a project tint key is honoured' {
        # 20 % of #215732 over a black background: 33*0.2=7, 87*0.2=17, 50*0.2=10
        $p = Join-Path $sandbox 'pure\projet'
        Assert-Equal '#07110A' (Get-EffectiveBackgroundHex -Path $p -PureColor $false)
    }

    Test-It 'in pure colour, the reference background plays no part' {
        $p = Join-Path $sandbox 'pure\projet'
        Assert-Equal '#215732' (Get-EffectiveBackgroundHex -Path $p -PureColor $true -Base '#FFFFFF')
    }

    # ======================================================================
    Write-Section 'Border: only the visible tab drives it'

    # The border belongs to the window, not to the tab. Without a guard every tab
    # repaints it on its first prompt - and since those prompts race each other
    # while a window opens, a colourless tab can win and leave a grey border on a
    # window whose visible tab belongs to a project.
    function Test-TitleMatch {
        param([string] $WindowTitle, [string[]] $Candidates)
        & $m { param($w, $c) Test-TcTitleMatchesWindow -WindowTitle $w -Candidates $c } $WindowTitle $Candidates
    }

    Test-It 'the visible tab is recognised by its title' {
        Assert-Equal $true (Test-TitleMatch -WindowTitle 'ZZ oseille' -Candidates @('ZZ oseille'))
    }

    Test-It 'a background tab is recognised as such' {
        Assert-Equal $false (Test-TitleMatch -WindowTitle 'ZZ pastel' -Candidates @('ZZ oseille'))
    }

    Test-It 'the previous title is tolerated: WT propagates asynchronously' {
        # Right after a cd the window may still show the former title; the visible
        # tab must not be mistaken for a background one.
        Assert-Equal $true (Test-TitleMatch -WindowTitle 'ZZ former' -Candidates @('ZZ current', 'ZZ former'))
    }

    Test-It 'empty window title: undecidable, not a refusal' {
        Assert-Null (Test-TitleMatch -WindowTitle '' -Candidates @('ZZ oseille'))
    }

    Test-It 'no title of our own: undecidable, not a refusal' {
        # The -NoTitle case: we cannot tell, so we must not block the border.
        Assert-Null (Test-TitleMatch -WindowTitle 'Windows PowerShell' -Candidates @('', $null))
    }

    Test-It 'applied titles are remembered, the last two only' {
        $titles = & $m {
            $saved = $script:TcAppliedTitles
            try {
                $script:TcAppliedTitles = @()
                Set-TcWindowTitle -Title 'TC-TEST-1'
                Set-TcWindowTitle -Title 'TC-TEST-2'
                Set-TcWindowTitle -Title 'TC-TEST-3'
                return @($script:TcAppliedTitles)
            } finally { $script:TcAppliedTitles = $saved }
        }
        Assert-Equal 2 $titles.Count 'only the last two titles are of any use'
        Assert-Equal 'TC-TEST-3' $titles[0]
        Assert-Equal 'TC-TEST-2' $titles[1]
    }

    # A single Windows Terminal process exposes several windows of the same class
    # carrying the same title: the real ones, plus hidden placeholders parked at
    # -32000,-32000. Colouring a placeholder succeeds and shows nothing, so the
    # real window has to be told apart by geometry first.
    function Select-Window {
        param([object[]] $Candidates, [string] $Title)
        & $m { param($c, $t) Select-TcTerminalWindow -Candidates $c -Title $t } $Candidates $Title
    }

    function New-WindowCandidate {
        param([int] $Handle, [int] $Left, [int] $Top, [int] $Width, [int] $Height, [string] $Title)
        [pscustomobject]@{ Handle = $Handle; Left = $Left; Top = $Top; Width = $Width; Height = $Height; Title = $Title }
    }

    Test-It 'hidden placeholders are discarded, the real window wins' {
        $candidates = @(
            New-WindowCandidate -Handle 1 -Left -32000 -Top -32000 -Width 160 -Height 28 -Title 'ZZ oseille'
            New-WindowCandidate -Handle 2 -Left 304 -Top 312 -Width 1129 -Height 635 -Title 'ZZ oseille'
            New-WindowCandidate -Handle 3 -Left -32000 -Top -32000 -Width 160 -Height 28 -Title 'ZZ oseille'
        )
        Assert-Equal 2 (Select-Window -Candidates $candidates -Title 'ZZ oseille')
    }

    Test-It 'a placeholder is discarded even when listed first and titled alike' {
        # The old code took the first candidate, so it could land on this one.
        $candidates = @(
            New-WindowCandidate -Handle 9 -Left -32000 -Top -32000 -Width 160 -Height 28 -Title 'ZZ oseille'
            New-WindowCandidate -Handle 4 -Left 10 -Top 10 -Width 800 -Height 400 -Title 'ZZ oseille'
        )
        Assert-Equal 4 (Select-Window -Candidates $candidates -Title 'ZZ oseille')
    }

    Test-It 'among several real windows the title decides' {
        $candidates = @(
            New-WindowCandidate -Handle 5 -Left 0 -Top 0 -Width 1200 -Height 700 -Title 'ZZ pastel'
            New-WindowCandidate -Handle 6 -Left 40 -Top 40 -Width 900 -Height 500 -Title 'ZZ oseille'
        )
        Assert-Equal 6 (Select-Window -Candidates $candidates -Title 'ZZ oseille') 'the title must win over size'
    }

    Test-It 'no usable title: the largest real window is taken' {
        $candidates = @(
            New-WindowCandidate -Handle 7 -Left 0 -Top 0 -Width 600 -Height 400 -Title 'other'
            New-WindowCandidate -Handle 8 -Left 40 -Top 40 -Width 1200 -Height 700 -Title 'other'
        )
        Assert-Equal 8 (Select-Window -Candidates $candidates -Title '')
    }

    Test-It 'several windows share the title: the largest of those is taken' {
        $candidates = @(
            New-WindowCandidate -Handle 10 -Left 0 -Top 0 -Width 600 -Height 400 -Title 'ZZ oseille'
            New-WindowCandidate -Handle 11 -Left 40 -Top 40 -Width 1200 -Height 700 -Title 'ZZ oseille'
            New-WindowCandidate -Handle 12 -Left 80 -Top 80 -Width 1400 -Height 800 -Title 'ZZ pastel'
        )
        Assert-Equal 11 (Select-Window -Candidates $candidates -Title 'ZZ oseille')
    }

    Test-It 'placeholders only: nothing is chosen' {
        $candidates = @(
            New-WindowCandidate -Handle 13 -Left -32000 -Top -32000 -Width 160 -Height 28 -Title 'ZZ oseille'
        )
        Assert-Null (Select-Window -Candidates $candidates -Title 'ZZ oseille') 'better no window than an invisible one'
    }

    Test-It 'no candidate at all: nothing is chosen' {
        Assert-Null (Select-Window -Candidates @() -Title 'ZZ oseille')
    }

    # $Apply / $Reset record what Set-TcAppearance and Reset-TcAppearance actually
    # asked of the border, with the DWM calls stubbed out.
    function Measure-BorderCalls {
        param($ActiveTab, [switch] $SkipApply, [switch] $SkipReset, [switch] $ForceReset)
        & $m { param($active, $skipApply, $skipReset, $forceReset)
            $savedActive = ${function:Test-TcActiveTab}
            $savedSet = ${function:Set-TcWindowBorderColor}
            $savedReset = ${function:Reset-TcWindowBorderColor}
            $savedFlag = $script:TcBorderApplied
            try {
                $script:TcApplyCalls = 0
                $script:TcResetCalls = 0
                $script:TcBorderApplied = $false
                Set-Item -Path function:script:Test-TcActiveTab -Value ([scriptblock]::Create("return `$$active"))
                Set-Item -Path function:script:Set-TcWindowBorderColor -Value { param($Rgb, [switch] $IncludeCaption) $script:TcApplyCalls++; return $true }
                Set-Item -Path function:script:Reset-TcWindowBorderColor -Value { param([switch] $IncludeCaption) $script:TcResetCalls++; return $true }

                $options = New-TcDefaultOptions
                $options.SetTitle = $false
                $info = [pscustomobject]@{ Color = '#215732'; Rgb = (ConvertFrom-TcColor -Value '#215732'); Name = 'x'; Icon = ''; Tint = $null }
                if (-not $skipApply) { Set-TcAppearance -Info $info -Path 'C:\x' -Options $options }
                if (-not $skipReset) { Reset-TcAppearance -Options $options -Force:$forceReset }
                return [pscustomobject]@{ Apply = $script:TcApplyCalls; Reset = $script:TcResetCalls }
            } finally {
                Set-Item -Path function:script:Test-TcActiveTab -Value $savedActive
                Set-Item -Path function:script:Set-TcWindowBorderColor -Value $savedSet
                Set-Item -Path function:script:Reset-TcWindowBorderColor -Value $savedReset
                $script:TcBorderApplied = $savedFlag
            }
        } $ActiveTab ([bool]$SkipApply) ([bool]$SkipReset) ([bool]$ForceReset)
    }

    Test-It 'a background tab never touches the border' {
        $r = Measure-BorderCalls -ActiveTab 'false'
        Assert-Equal 0 $r.Apply 'no colour applied from a background tab'
        Assert-Equal 0 $r.Reset 'no reset from a background tab'
    }

    Test-It 'the visible tab drives the border' {
        $r = Measure-BorderCalls -ActiveTab 'true'
        Assert-Equal 1 $r.Apply
        Assert-Equal 1 $r.Reset
    }

    Test-It 'undecidable state: the border is still driven' {
        $r = Measure-BorderCalls -ActiveTab 'null' -SkipReset
        Assert-Equal 1 $r.Apply 'without certainty, keep the original behaviour'
    }

    # The decisive case. Several tabs open at once: a colourless tab restores the
    # shell's default title, which is also what the window shows until the active
    # tab sets its own, so the title check believes it is the visible one. Only
    # [have I ever coloured the border?] catches it.
    Test-It 'a tab that never coloured the border does not reset it' {
        $r = Measure-BorderCalls -ActiveTab 'true' -SkipApply
        Assert-Equal 0 $r.Reset 'nothing of ours to restore, so nothing to clobber'
    }

    Test-It 'an explicit Reset-TerminalColor restores it anyway' {
        $r = Measure-BorderCalls -ActiveTab 'true' -SkipApply -ForceReset
        Assert-Equal 1 $r.Reset 'the user asked for it explicitly'
    }

    Test-It 'leaving a project does reset the border it had applied' {
        $r = Measure-BorderCalls -ActiveTab 'true'
        Assert-Equal 1 $r.Apply
        Assert-Equal 1 $r.Reset 'this session coloured it, so it restores it'
    }

    # ======================================================================
    Write-Section 'PowerShell profile hook'

    Test-It 'block added to an existing profile' {
        $path = New-Fixture 'profile\case1\profile.ps1' "# my profile`nSet-Alias ll Get-ChildItem`n"
        $r = Install-TerminalColorsProfile -ProfilePath $path -Confirm:$false
        Assert-True $r.Changed

        $text = [System.IO.File]::ReadAllText($path)
        Assert-True ($text.Contains('# my profile')) 'the existing content must survive'
        Assert-True ($text.Contains('Import-Module TerminalColors')) 'the block must be present'
        Assert-True ($text.Contains('Enable-TerminalColors')) 'the activation call must be present'
        Assert-True (Test-TerminalColorsProfile -ProfilePath $path)
    }

    Test-It 'second run: updated without duplication' {
        $path = Join-Path $sandbox 'profile\case1\profile.ps1'
        Install-TerminalColorsProfile -ProfilePath $path -EnableArguments '-Tint 0.5' -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        Assert-Equal 1 ([regex]::Matches($text, [regex]::Escape('# >>> TerminalColors >>>'))).Count
        Assert-True ($text.Contains('Enable-TerminalColors -Tint 0.5')) 'the arguments must be taken into account'
    }

    Test-It 'a non-existent profile is created' {
        $path = Join-Path $sandbox 'profile\case2\profile.ps1'
        Install-TerminalColorsProfile -ProfilePath $path -Confirm:$false | Out-Null
        Assert-True (Test-Path -LiteralPath $path)
        Assert-True (Test-TerminalColorsProfile -ProfilePath $path)
    }

    Test-It 'the inserted block is valid PowerShell' {
        $path = Join-Path $sandbox 'profile\case2\profile.ps1'
        $errors = $null; $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-Equal 0 @($errors).Count "erreurs : $(($errors | ForEach-Object { $_.Message }) -join ' | ')"
    }

    Test-It 'uninstall: block removed, the rest preserved' {
        $path = Join-Path $sandbox 'profile\case1\profile.ps1'
        Uninstall-TerminalColorsProfile -ProfilePath $path -Confirm:$false
        $text = [System.IO.File]::ReadAllText($path)
        Assert-True (-not $text.Contains('TerminalColors')) 'plus aucune trace attendue'
        Assert-True ($text.Contains('Set-Alias ll Get-ChildItem')) 'the existing content must survive'
        Assert-True (-not (Test-TerminalColorsProfile -ProfilePath $path))
    }

    # ======================================================================
    Write-Section 'Install-TerminalColors (single entry point)'

    # The orchestrator must never be the reason a step is skipped silently, and it
    # must not touch anything under -WhatIf. It is exercised with -Quiet so the
    # test output stays readable, and with -SkipProfile so it never writes to the
    # real PowerShell profile.
    Test-It 'exposed by the module, with -WhatIf support' {
        $cmd = Get-Command Install-TerminalColors -ErrorAction Stop
        Assert-NotNull $cmd
        Assert-True $cmd.Parameters.ContainsKey('WhatIf') 'the command must support -WhatIf'
        foreach ($p in 'SkipTheme', 'SkipBackdrop', 'SystemTitleBar', 'SkipProfile', 'EnableArguments', 'Force', 'Quiet', 'PassThru') {
            Assert-True $cmd.Parameters.ContainsKey($p) "-$p is missing"
        }
        Assert-NotNull (Get-Command Uninstall-TerminalColors -ErrorAction Stop)
    }

    Test-It 'chains theme and backdrop, and reports each step' {
        $r = Install-TerminalColors -SkipProfile -Quiet -PassThru -Confirm:$false
        Assert-NotNull $r
        Assert-True ($r.Theme -in 'installed', 'already in place') "theme step: $($r.Theme)"
        Assert-True ($r.Backdrop -in 'installed', 'already in place') "backdrop step: $($r.Backdrop)"
        Assert-Equal 'not requested' $r.SystemTitleBar
        Assert-Equal 0 @($r.Profiles).Count '-SkipProfile must leave the profile alone'
    }

    Test-It 'adds -PureColor to the profile line when the backdrop is in place' {
        $r = Install-TerminalColors -SkipProfile -Quiet -PassThru -Confirm:$false
        Assert-Equal '-PureColor' $r.EnableArguments 'the backdrop is only useful undiluted'
    }

    Test-It 'respects a dilution choice already expressed' {
        $r = Install-TerminalColors -SkipProfile -Quiet -PassThru -EnableArguments '-Tint 0.45' -Confirm:$false
        Assert-Equal '-Tint 0.45' $r.EnableArguments 'a stated -Tint must not gain -PureColor'
    }

    Test-It 'without the backdrop, no -PureColor is added' {
        $r = Install-TerminalColors -SkipProfile -SkipBackdrop -Quiet -PassThru -Confirm:$false
        Assert-Equal 'skipped' $r.Backdrop
        Assert-True ([string]::IsNullOrEmpty($r.EnableArguments)) "expected no arguments, got [$($r.EnableArguments)]"
    }

    Test-It 'a step that fails does not stop the others' {
        # No settings.json in sight: the theme and the backdrop must fail, and the
        # command must still report and carry on rather than throw.
        $r = & $m {
            $saved = ${function:Get-TcWtSettingsPath}
            try {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value { return $null }
                Install-TerminalColors -SkipProfile -Quiet -PassThru -Confirm:$false
            } finally {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value $saved
            }
        }
        Assert-NotNull $r 'the command must return a report, not throw'
        Assert-True ($r.Theme -like 'failed:*') "theme step: $($r.Theme)"
        Assert-True ($r.Backdrop -like 'failed:*') "backdrop step: $($r.Backdrop)"
    }

    Test-It '-WhatIf writes nothing at all' {
        # Including the real PowerShell profile: -WhatIf reaches it, since that is
        # the path the command targets, so it is the one worth watching.
        $path = New-Fixture 'entry\whatif\settings.json' $backdropSample
        $before = [System.IO.File]::ReadAllText($path)

        $realProfile = $PROFILE.CurrentUserAllHosts
        $profileBefore = $null
        if ([System.IO.File]::Exists($realProfile)) { $profileBefore = [System.IO.File]::ReadAllText($realProfile) }

        & $m { param($p)
            $saved = ${function:Get-TcWtSettingsPath}
            try {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value ([scriptblock]::Create("return '$p'"))
                Install-TerminalColors -Quiet -WhatIf
            } finally {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value $saved
            }
        } $path | Out-Null

        Assert-Equal $before ([System.IO.File]::ReadAllText($path)) 'settings.json must be untouched'

        $profileAfter = $null
        if ([System.IO.File]::Exists($realProfile)) { $profileAfter = [System.IO.File]::ReadAllText($realProfile) }
        Assert-Equal $profileBefore $profileAfter 'the PowerShell profile must be untouched'
    }

    Test-It '-Quiet prints nothing' {
        $output = Install-TerminalColors -SkipProfile -Quiet -Confirm:$false 6>&1 | Out-String
        Assert-Equal '' $output.Trim() "expected no output, got [$($output.Trim())]"
    }

    Test-It 'the uninstall clears every profile the install wrote to' {
        # The regression this guards: the install writes to both editions' profiles
        # when both are present, so an uninstall that only cleaned the current
        # edition left an Enable-TerminalColors call behind in the other - running
        # against a theme and a backdrop that were gone. Both now read the profile
        # list from Get-TcProfilePath, which is what this stubs.
        $settings = New-Fixture 'entry\symmetry\settings.json' $backdropSample
        $first = New-Fixture 'entry\symmetry\edition1\profile.ps1' '# an existing profile'
        $second = New-Fixture 'entry\symmetry\edition2\profile.ps1' '# the other edition'

        & $m { param($settingsPath, $p1, $p2)
            $savedSettings = ${function:Get-TcWtSettingsPath}
            $savedProfiles = ${function:Get-TcProfilePath}
            $savedWt = ${function:Test-TcWindowsTerminal}
            try {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value ([scriptblock]::Create("return '$settingsPath'"))
                Set-Item -Path function:script:Get-TcProfilePath -Value ([scriptblock]::Create("return @('$p1', '$p2')"))
                # Neither command may touch the session running the tests.
                Set-Item -Path function:script:Test-TcWindowsTerminal -Value { return $false }
                Install-TerminalColors -Quiet -Confirm:$false | Out-Null
                Uninstall-TerminalColors -Quiet -Confirm:$false | Out-Null
            } finally {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value $savedSettings
                Set-Item -Path function:script:Get-TcProfilePath -Value $savedProfiles
                Set-Item -Path function:script:Test-TcWindowsTerminal -Value $savedWt
            }
        } $settings $first $second | Out-Null

        foreach ($path in @($first, $second)) {
            Assert-True (-not (Test-TerminalColorsProfile -ProfilePath $path)) "the block is still in [$path]"
            Assert-True ([System.IO.File]::Exists($path)) "[$path] must be kept, only the block removed"
        }
    }

    Test-It 'the uninstall reports only what it actually removed' {
        # It used to print "Removed: <step>" unconditionally, so an uninstall on a
        # machine where nothing was installed claimed to have removed the profile
        # block, the backdrop, the title bar and the theme - each message printed
        # right after the sub-command had warned there was nothing there.
        $settings = New-Fixture 'entry\nothing\settings.json' $wtSample
        $untouched = New-Fixture 'entry\nothing\profile.ps1' '# a profile with no TerminalColors block'

        $output = & $m { param($s, $p)
            $savedSettings = ${function:Get-TcWtSettingsPath}
            $savedProfiles = ${function:Get-TcProfilePath}
            $savedWt = ${function:Test-TcWindowsTerminal}
            try {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value ([scriptblock]::Create("return '$s'"))
                Set-Item -Path function:script:Get-TcProfilePath -Value ([scriptblock]::Create("return @('$p')"))
                Set-Item -Path function:script:Test-TcWindowsTerminal -Value { return $false }
                Uninstall-TerminalColors -Confirm:$false 6>&1 3>&1
            } finally {
                Set-Item -Path function:script:Get-TcWtSettingsPath -Value $savedSettings
                Set-Item -Path function:script:Get-TcProfilePath -Value $savedProfiles
                Set-Item -Path function:script:Test-TcWindowsTerminal -Value $savedWt
            }
        } $settings $untouched | Out-String

        Assert-True ($output -notmatch 'Removed:') "nothing was installed, yet a removal was reported: $output"
        Assert-True ($output -match 'Nothing to remove') "it must say what it did not find: $output"
        Assert-Equal $wtSample ([System.IO.File]::ReadAllText($settings)) 'settings.json must be untouched'
    }

    # ======================================================================
    Write-Section 'Public commands'

    Test-It 'Set-FolderColor writes a readable configuration' {
        $p = New-FixtureDir 'public\projet'
        Set-FolderColor -Color '#215732' -Path $p -Name 'MonProjet' -Confirm:$false | Out-Null

        Assert-True (Test-Path -LiteralPath (Join-Path $p '.terminalcolors.json'))
        $r = Get-TerminalColor -Path $p
        Assert-Equal '#215732' $r.Color
        Assert-Equal 'MonProjet' $r.Name
        Assert-Equal 'Config' $r.Source
    }

    Test-It 'Set-FolderColor refuses to overwrite without -Force' {
        $threw = $false
        try { Set-FolderColor -Color 'Teal' -Path (Join-Path $sandbox 'public\projet') -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
    }

    Test-It 'Set-FolderColor -Force overwrites' {
        $p = Join-Path $sandbox 'public\projet'
        Set-FolderColor -Color 'Teal' -Path $p -Force -Confirm:$false | Out-Null
        Assert-Equal '#008080' (Get-TerminalColor -Path $p).Color
    }

    Test-It 'Set-FolderColor rejects an invalid colour' {
        $p = New-FixtureDir 'public\projet2'
        $threw = $false
        try { Set-FolderColor -Color 'bleu-canard-fonce' -Path $p -Confirm:$false | Out-Null } catch { $threw = $true }
        Assert-True $threw
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $p '.terminalcolors.json')))
    }

    Test-It 'Set-FolderColor handles per-branch colours' {
        $p = New-FixtureDir 'public\projet3'
        New-Fixture 'public\projet3\.git\HEAD' "ref: refs/heads/hotfix/urgent`n" | Out-Null
        Set-FolderColor -Color 'Teal' -Path $p -Branches @{ 'hotfix/*' = 'OrangeRed' } -Confirm:$false | Out-Null
        Assert-Equal '#FF4500' (Get-TerminalColor -Path $p).Color
    }

    Test-It 'Set-FolderColor produces standard JSON' {
        $text = [System.IO.File]::ReadAllText((Join-Path $sandbox 'public\projet3\.terminalcolors.json'))
        Assert-Equal 'Teal' ($text | ConvertFrom-Json).color
    }

    Test-It 'Set-FolderColor accepts auto' {
        $p = New-FixtureDir 'public\projet4'
        Set-FolderColor -Color auto -Path $p -Name 'oseille' -Confirm:$false | Out-Null
        Assert-Equal (Get-AutoHexOf 'oseille') (Get-TerminalColor -Path $p).Color
    }

    Test-It 'Remove-FolderColor deletes the configuration' {
        $p = Join-Path $sandbox 'public\projet'
        Remove-FolderColor -Path $p -Confirm:$false
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $p '.terminalcolors.json')))
    }

    Test-It 'Get-TerminalColor accepts the pipeline' {
        $root = New-FixtureDir 'public\depots'
        foreach ($name in @('alpha', 'beta')) {
            New-FixtureDir "public\depots\$name" | Out-Null
            New-Fixture "public\depots\$name\.terminalcolors.json" '{ "color": "auto" }' | Out-Null
        }
        $results = @(Get-ChildItem $root -Directory | Get-TerminalColor)
        Assert-Equal 2 $results.Count
        Assert-True ($results[0].Color -match '^#[0-9A-F]{6}$')
    }

    Test-It 'Get-TerminalColor on a folder with no colour' {
        $r = Get-TerminalColor -Path (New-FixtureDir 'public\rien') -NoAutoGitColors
        Assert-Equal 'None' $r.Source
        Assert-Null $r.Color
    }

    Test-It 'Get-TerminalColor computes the tinted background' {
        $p = New-FixtureDir 'public\teinte'
        New-Fixture 'public\teinte\.terminalcolors.json' '{ "color": "#FFFFFF", "tint": 0.5 }' | Out-Null
        $r = Get-TerminalColor -Path $p
        Assert-True ($r.TintedFallback -match '^#[0-9A-F]{6}$') "fond teinte inattendu : $($r.TintedFallback)"
        Assert-True ($r.TintedFallback -ne '#FFFFFF') 'the background must be blended, not the pure colour'
    }

    Test-It 'Get-TerminalColor suggests an automatic icon' {
        $r = Get-TerminalColor -Path (Join-Path $sandbox 'public\projet3')
        Assert-True (-not [string]::IsNullOrEmpty($r.Icon)) 'an icon is expected'
    }

    Test-It 'Enable / Disable preserve the original prompt' {
        $original = 'PS-TEST> '
        Set-Item -Path function:global:prompt -Value ([scriptblock]::Create("'$original'")) -Force

        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        Assert-True (Test-TerminalColorsEnabled) 'the colouring must be active'
        Assert-Equal $original (& (Get-Command prompt).ScriptBlock)

        Disable-TerminalColors
        Assert-True (-not (Test-TerminalColorsEnabled)) 'the colouring must be inactive'
        Assert-Equal $original (& (Get-Command prompt).ScriptBlock)
    }

    Test-It 'Enable is idempotent' {
        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        Assert-True (Test-TerminalColorsEnabled)
        Disable-TerminalColors
        Assert-Equal 'PS-TEST> ' (& (Get-Command prompt).ScriptBlock)
    }

    Test-It 'Disable without Enable raises no error' {
        Disable-TerminalColors
        Assert-True (-not (Test-TerminalColorsEnabled))
    }

    Test-It 'Update-TerminalColor accepts an explicit path' {
        $p = New-FixtureDir 'public\update'
        New-Fixture 'public\update\.terminalcolors.json' '{ "color": "#123456", "name": "Update" }' | Out-Null
        $r = Update-TerminalColor -Path $p -Force -PassThru
        Assert-Equal '#123456' $r.Color
        Assert-Equal 'Update' $r.Name
    }

    Test-It 'Update-TerminalColor reads nothing when the directory has not changed' {
        $p = New-FixtureDir 'public\stable'
        New-Fixture 'public\stable\.terminalcolors.json' '{ "color": "#ABCDEF", "name": "Stable" }' | Out-Null

        $first = Update-TerminalColor -Path $p -Force -PassThru
        Assert-Equal '#ABCDEF' $first.Color

        # The file changes, but without -Force and with an unchanged directory the
        # module must stay on the already resolved colour (no disk re-read).
        [System.IO.File]::WriteAllText((Join-Path $p '.terminalcolors.json'), '{ "color": "#111111" }', (New-Object System.Text.UTF8Encoding($false)))
        $second = Update-TerminalColor -Path $p -PassThru
        Assert-Equal '#ABCDEF' $second.Color

        # With -Force, the new colour is picked up.
        Assert-Equal '#111111' (Update-TerminalColor -Path $p -Force -PassThru).Color
    }

    Test-It 'AlwaysReapply is off by default and can be enabled' {
        Enable-TerminalColors -NoWindowBorder -NoTitle | Out-Null
        $options = & $m { Get-TcOptions }
        Assert-True (-not $options.AlwaysReapply) 'off by default'

        Enable-TerminalColors -NoWindowBorder -NoTitle -AlwaysReapply | Out-Null
        $options = & $m { Get-TcOptions }
        Assert-True $options.AlwaysReapply 'activable'
        Disable-TerminalColors
    }

    Test-It 'Clear-TerminalColorCache raises no error' {
        Clear-TerminalColorCache
        Assert-True $true
    }

    Test-It 'Invoke-TerminalColorsDoctor returns consistent results' {
        $results = @(Invoke-TerminalColorsDoctor -PassThru 6>$null)
        Assert-True ($results.Count -ge 5) "at least 5 checks expected, got $($results.Count)"
        foreach ($r in $results) {
            Assert-NotNull $r.Check
            Assert-True ($r.Status -in @('OK', 'Warning', 'Problem', 'Info')) "unexpected status: $($r.Status)"
            Assert-True (-not [string]::IsNullOrWhiteSpace($r.Detail)) "missing detail for $($r.Check)"
        }
    }

    # ======================================================================
    Write-Section 'Code quality'

    Test-It 'every advertised command is exported' {
        $manifest = Import-PowerShellDataFile -Path $modulePath
        $exported = @((Get-Module TerminalColors).ExportedFunctions.Keys)
        foreach ($name in $manifest.FunctionsToExport) {
            Assert-True ($exported -contains $name) "commande annoncee mais absente : $name"
        }
        Assert-Equal @($manifest.FunctionsToExport).Count $exported.Count 'no command must be exported without being advertised'
    }

    Test-It 'the advertised alias is exported' {
        $exported = @((Get-Module TerminalColors).ExportedAliases.Keys)
        Assert-True ($exported -contains 'Set-TerminalColor') "alias missing, got: $($exported -join ', ')"
    }

    Test-It 'every public command is documented' {
        foreach ($name in (Get-Module TerminalColors).ExportedFunctions.Keys) {
            $help = Get-Help $name -ErrorAction SilentlyContinue
            Assert-True (-not [string]::IsNullOrWhiteSpace($help.Synopsis)) "missing help for $name"
            Assert-True ($help.Synopsis -notlike "$name*") "no synopsis for $name"
        }
    }

    Test-It 'the PowerShell sources are pure ASCII' {
        $offenders = New-Object System.Collections.ArrayList
        foreach ($file in (Get-SourceFile)) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            for ($i = 0; $i -lt $text.Length; $i++) {
                if ([int]$text[$i] -gt 126) {
                    [void]$offenders.Add("$($file.Name):$i U+$('{0:X4}' -f [int]$text[$i])")
                    break
                }
            }
        }
        Assert-Equal 0 $offenders.Count ('caracteres non-ASCII : ' + ($offenders -join ' ; '))
    }

    Test-It 'no source file has a syntax error' {
        foreach ($file in (Get-SourceFile -Extension @('*.ps1', '*.psm1'))) {
            $errors = $null; $tokens = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
            Assert-Equal 0 @($errors).Count "$($file.Name) : $(($errors | ForEach-Object { $_.Message }) -join ' | ')"
        }
    }

    Test-It 'the manifest is valid' {
        $manifest = Test-ModuleManifest -Path $modulePath -ErrorAction Stop
        Assert-Equal 'TerminalColors' $manifest.Name
        Assert-NotNull $manifest.Version
        Assert-True ($manifest.Description.Length -gt 40) 'description too short for the Gallery'
    }

} finally {
    Set-Item -Path function:global:prompt -Value ([scriptblock]::Create('"PS $($ExecutionContext.SessionState.Path.CurrentLocation)> "')) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Bilan -------------------------------------------------------------------
Write-Host ''
Write-Host '  ---------------------------' -ForegroundColor DarkGray
if ($script:Failed -eq 0) {
    Write-Host "  $($script:Passed) tests passed." -ForegroundColor Green
    Write-Host ''
    exit 0
}

Write-Host "  $($script:Passed) passed, $($script:Failed) failed:" -ForegroundColor Red
foreach ($f in $script:Failures) { Write-Host "    - $f" -ForegroundColor Red }
Write-Host ''
exit 1
