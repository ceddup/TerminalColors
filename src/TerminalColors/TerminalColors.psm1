# TerminalColors - automatic Windows Terminal colouring based on the current
# directory. The source is deliberately pure ASCII: no encoding problem is possible
# between Windows PowerShell 5.1, PowerShell 7 and your colleagues' editors.

# Note: no Set-StrictMode here. This module reads a lot of JSON whose properties
# are optional (settings.json, .vscode/settings.json), and strict mode would turn
# every absent property into an exception - right in the middle of the user's
# prompt hook. Optional reads go through Get-TcJsonProperty, which returns $null
# without raising an error.

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    } catch {
        throw "TerminalColors: could not load [$($file.Name)] - $($_.Exception.Message)"
    }
}

Set-Alias -Name Set-TerminalColor -Value Set-FolderColor

Export-ModuleMember -Function @(
    'Enable-TerminalColors'
    'Disable-TerminalColors'
    'Test-TerminalColorsEnabled'
    'Update-TerminalColor'
    'Reset-TerminalColor'
    'Get-TerminalColor'
    'Clear-TerminalColorCache'
    'Set-FolderColor'
    'Remove-FolderColor'
    'Install-TerminalColors'
    'Uninstall-TerminalColors'
    'Install-TerminalColorsTheme'
    'Uninstall-TerminalColorsTheme'
    'Install-TerminalColorsBackdrop'
    'Uninstall-TerminalColorsBackdrop'
    'Test-TerminalColorsBackdrop'
    'Install-TerminalColorsTitleBar'
    'Uninstall-TerminalColorsTitleBar'
    'Test-TerminalColorsTitleBar'
    'Install-TerminalColorsProfile'
    'Uninstall-TerminalColorsProfile'
    'Test-TerminalColorsProfile'
    'Invoke-TerminalColorsDoctor'
) -Alias @('Set-TerminalColor')

# Remove-Module restores the original prompt and the terminal appearance.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    try { Disable-TerminalColors } catch { }
}
