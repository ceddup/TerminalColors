# TerminalColors - coloration automatique de Windows Terminal selon le dossier
# courant. Le code source est volontairement en ASCII pur : aucun probleme
# d'encodage possible entre Windows PowerShell 5.1, PowerShell 7 et les editeurs
# de vos collegues.

# Note : pas de Set-StrictMode ici. Ce module lit beaucoup de JSON dont les
# proprietes sont facultatives (settings.json, .vscode/settings.json), et le
# mode strict transformerait chaque propriete absente en exception - au beau
# milieu du hook d'invite de l'utilisateur. Les acces optionnels passent par
# Get-TcJsonProperty, qui renvoie $null sans lever d'erreur.

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    } catch {
        throw "TerminalColors : chargement impossible de [$($file.Name)] - $($_.Exception.Message)"
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

# Remove-Module restaure l'invite d'origine et l'apparence du terminal.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    try { Disable-TerminalColors } catch { }
}
