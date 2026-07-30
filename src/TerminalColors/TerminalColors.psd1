@{
    RootModule        = 'TerminalColors.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'edd3a4ad-d99f-4b5c-8897-22fc41b4f309'
    Author            = 'Cedric Dupont'
    CompanyName       = 'Synapse Informatique'
    Copyright         = '(c) 2026 Cedric Dupont. MIT License.'

    # This description is the text indexed by the PowerShell Gallery search, so it
    # is written in English. The French documentation lives in README.fr.md.
    Description       = 'Colours the Windows Terminal tab, title bar and window border according to the current directory. Automatically reuses the colours you already defined with Peacock (VS Code) and Solution Colors (Visual Studio), or a source-controllable .terminalcolors.json file. No third-party tool and no background process: the tab colour comes from a Windows Terminal theme driven by OSC 11, the border from DwmSetWindowAttribute.'

    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
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
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Set-TerminalColor')

    PrivateData       = @{
        PSData = @{
            # PSEdition_* are the Gallery's conventional tags: they drive the
            # per-edition filter on the website.
            Tags         = @(
                'WindowsTerminal'
                'Terminal'
                'Color'
                'Colour'
                'Tab'
                'Peacock'
                'SolutionColors'
                'Git'
                'Prompt'
                'Windows'
                'DeveloperExperience'
                'PSEdition_Desktop'
                'PSEdition_Core'
            )

            ProjectUri   = 'https://github.com/ceddup/TerminalColors'
            LicenseUri   = 'https://github.com/ceddup/TerminalColors/blob/main/LICENSE'

            ReleaseNotes = 'Full changelog: https://github.com/ceddup/TerminalColors/blob/main/CHANGELOG.md

1.0.0 - First release. The selected tab and the window border take the colour of the current project, in full strength, while the pane you read text in stays exactly as it was; background tabs keep their own colour and the tab row never follows the project. Colours come from .terminalcolors.json, Peacock (VS Code), Solution Colors (Visual Studio) or a stable hash of the Git repository name, nearest ancestor winning. Setup: Install-TerminalColorsTheme, Install-TerminalColorsBackdrop, Install-TerminalColorsProfile - or install.ps1 from a clone.'
        }
    }
}
