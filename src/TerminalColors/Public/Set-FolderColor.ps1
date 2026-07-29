function Set-FolderColor {
    <#
        .SYNOPSIS
        Associates a colour with a folder by writing a .terminalcolors.json file
        into it.

        .DESCRIPTION
        The colour applies to the folder and, by default, to all of its
        subfolders. The file is deliberately readable and source-controllable:
        commit it so the whole team shares the same project colour.

        .PARAMETER Color
        Colour as a hex code (#215732), a known colour name (Teal, SteelBlue...)
        or [auto] to derive a stable colour from the project name.

        .PARAMETER Path
        Folder to colour. Defaults to the current folder.

        .PARAMETER Name
        Label shown in the tab. Defaults to the folder name.

        .PARAMETER Icon
        Symbol shown before the label. Defaults to a coloured square derived from
        the colour.

        .PARAMETER Tint
        Tint strength specific to this project, from 0 to 1. Overrides the global
        setting.

        .PARAMETER Branches
        Git branch -> colour map. Wildcards are accepted.
        Example: @{ 'main' = '#215732'; 'release/*' = '#B71C1C' }

        .PARAMETER NoSubfolders
        Limits the colour to the given folder only.

        .PARAMETER Force
        Overwrites an existing configuration file.

        .EXAMPLE
        Set-FolderColor '#215732'

        .EXAMPLE
        Set-FolderColor auto -Path C:\Repos\pastel

        .EXAMPLE
        Set-FolderColor Teal -Name 'Superviseur' -Branches @{ 'main' = 'Teal'; 'hotfix/*' = 'OrangeRed' }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Color,

        [Parameter(Position = 1)]
        [string] $Path = '.',

        [string] $Name,
        [string] $Icon,

        [ValidateRange(0.0, 1.0)]
        [double] $Tint = -1,

        [hashtable] $Branches,

        [switch] $NoSubfolders,
        [switch] $Force,
        [switch] $PassThru
    )

    try {
        $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        throw "TerminalColors: folder not found [$Path]."
    }
    if (-not [System.IO.Directory]::Exists($directory)) {
        throw "TerminalColors: [$directory] is not a folder."
    }

    if ($Color -ne 'auto' -and -not (ConvertFrom-TcColor -Value $Color)) {
        throw "TerminalColors: unrecognised colour [$Color]. Use a hex code (#RRGGBB), a known colour name, or [auto]."
    }

    if ($Branches) {
        foreach ($key in $Branches.Keys) {
            $value = [string]$Branches[$key]
            if ($value -ne 'auto' -and -not (ConvertFrom-TcColor -Value $value)) {
                throw "TerminalColors: unrecognised colour [$value] for branch [$key]."
            }
        }
    }

    $target = Join-Path $directory '.terminalcolors.json'
    if ([System.IO.File]::Exists($target) -and -not $Force) {
        throw "TerminalColors: [$target] already exists. Use -Force to overwrite it."
    }

    $config = [ordered]@{ color = $Color }
    if ($Name) { $config.name = $Name } else { $config.name = Split-Path $directory -Leaf }
    if ($Icon) { $config.icon = $Icon }
    if ($Tint -ge 0) { $config.tint = $Tint }
    if ($Branches) {
        $ordered = [ordered]@{}
        foreach ($key in ($Branches.Keys | Sort-Object)) { $ordered[$key] = [string]$Branches[$key] }
        $config.branches = $ordered
    }
    if ($NoSubfolders) { $config.applyToSubfolders = $false }

    $json = ([pscustomobject]$config | ConvertTo-Json -Depth 10)

    if ($PSCmdlet.ShouldProcess($target, 'Write the colour configuration')) {
        # UTF-8 without BOM: readable by every tool, clean diff in Git.
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($target, $json + [Environment]::NewLine, $encoding)

        Clear-TcResolveCache
        $script:TcLastPath = $null
        $script:TcLastKey = $null

        $current = Get-TcCurrentPath
        if ($current -and ($current -eq $directory -or $current.StartsWith($directory + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
            Update-TerminalColor -Force
        }
    }

    if ($PassThru) { return Get-TerminalColor -Path $directory }
}

function Remove-FolderColor {
    <#
        .SYNOPSIS
        Removes a folder's .terminalcolors.json file.

        .PARAMETER Path
        Folder concerned. Defaults to the current folder.

        .EXAMPLE
        Remove-FolderColor
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [string] $Path = '.'
    )

    try {
        $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        throw "TerminalColors: folder not found [$Path]."
    }

    $removed = $false
    foreach ($name in @('.terminalcolors.json', 'terminalcolors.json', '.terminalcolors')) {
        $candidate = Join-Path $directory $name
        if ([System.IO.File]::Exists($candidate)) {
            if ($PSCmdlet.ShouldProcess($candidate, 'Remove')) {
                Remove-Item -LiteralPath $candidate -Force
                $removed = $true
            }
        }
    }

    if (-not $removed) {
        Write-Warning "TerminalColors: no colour configuration in [$directory]."
        return
    }

    Clear-TerminalColorCache
    Update-TerminalColor -Force
}
