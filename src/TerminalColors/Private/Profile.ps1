# Which PowerShell profiles the colouring is installed into.
#
# Both editions when both are present: a Windows Terminal profile can launch
# either one, and the colouring has to work whichever it launches.
#
# Install and uninstall MUST read this list from the same place. When they did not,
# uninstalling from one edition left the Enable-TerminalColors call behind in the
# other, where it then ran against a theme and a backdrop that were gone - and
# Test-TerminalColorsProfile kept reporting the block as present.

function Get-TcProfilePath {
    [OutputType([string[]])]
    param()

    $documents = [Environment]::GetFolderPath('MyDocuments')
    $paths = New-Object System.Collections.ArrayList
    [void]$paths.Add($PROFILE.CurrentUserAllHosts)

    if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        [void]$paths.Add((Join-Path $documents 'PowerShell\profile.ps1'))
    } elseif ($PSVersionTable.PSEdition -eq 'Core') {
        [void]$paths.Add((Join-Path $documents 'WindowsPowerShell\profile.ps1'))
    }

    return @($paths | Select-Object -Unique)
}
