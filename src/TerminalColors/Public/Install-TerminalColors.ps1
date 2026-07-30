# One command to set everything up, so that installing from the PowerShell Gallery
# is a two-liner:
#
#     Install-Module TerminalColors -Scope CurrentUser
#     Install-TerminalColors
#
# Install-Module cannot do this part itself: the colouring needs the Windows
# Terminal settings and your PowerShell profile to be edited, which no package
# manager is allowed to do on your behalf.
#
# install.ps1 copies the module from a clone and then calls this very function, so
# both installation paths behave identically by construction.

function Write-TcStep {
    param([string] $Message, [switch] $Quiet)
    if ($Quiet) { return }
    Write-Host '  -> ' -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-TcNote {
    param([string] $Message, [switch] $Quiet)
    if ($Quiet) { return }
    Write-Host '  !  ' -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor Yellow
}

function Install-TerminalColors {
    <#
        .SYNOPSIS
        Sets up everything TerminalColors needs, in one command.

        .DESCRIPTION
        Chains the three one-off steps and activates the colouring in the current
        session:

          1. the Windows Terminal theme, which binds the tab and the window border
             to the pane background;
          2. the opaque backdrop, which keeps the pane readable while the tab takes
             the full project colour;
          3. the block in your PowerShell profile, so every new session is coloured.

        Each step is reported, and a step that fails is reported without stopping
        the others - a missing Windows Terminal must not prevent the profile from
        being set up.

        Nothing is installed outside your user profile, and no administrator rights
        are needed. Every file touched is backed up first.

        .PARAMETER SkipTheme
        Does not install the Windows Terminal theme. Without it the tab and the
        border do not change colour at all.

        .PARAMETER SkipBackdrop
        Does not install the opaque backdrop. The project colour is then diluted
        onto the pane background and the tab stays subtle.

        .PARAMETER SystemTitleBar
        Also moves the tabs out of the title bar, so the window gets a real system
        title bar that DWM colours. Requires Windows Terminal to be closed
        completely to take effect.

        .PARAMETER SkipProfile
        Does not touch your PowerShell profile. The colouring then has to be enabled
        by hand with Enable-TerminalColors in each session.

        .PARAMETER EnableArguments
        Arguments written on the Enable-TerminalColors line of your profile.
        Example: '-TitleFormat "{icon} {name}" -NoWindowBorder'
        -PureColor is added automatically when the backdrop is in place, unless you
        specify -Tint or -PureColor yourself.

        .PARAMETER Force
        Reinstalls the theme even when it is already present.

        .PARAMETER NoBackup
        Does not write backup copies of settings.json and of the profile.

        .PARAMETER Quiet
        Prints nothing. Combine with -PassThru to get the result as an object.

        .PARAMETER PassThru
        Returns an object describing what each step did.

        .EXAMPLE
        Install-TerminalColors

        .EXAMPLE
        Install-TerminalColors -SystemTitleBar
        Adds a coloured system title bar on top of the coloured tab.

        .EXAMPLE
        Install-TerminalColors -SkipBackdrop -EnableArguments '-Tint 0.45'
        Keeps the diluted rendering: the colour lands on the pane background rather
        than on the tab.

        .EXAMPLE
        Install-TerminalColors -WhatIf
        Shows every change that would be made, and writes nothing.
    #>
    # SupportsShouldProcess without a ShouldProcess call of its own: every write is
    # performed by a sub-command that implements it, and -WhatIf is forwarded to each
    # of them explicitly. Announcing the orchestration on top of that would report
    # the same change twice.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Delegated to the sub-commands, which each call ShouldProcess; -WhatIf is forwarded to all of them.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [switch] $SkipTheme,
        [switch] $SkipBackdrop,
        [switch] $SystemTitleBar,
        [switch] $SkipProfile,
        [string] $EnableArguments,
        [switch] $Force,
        [switch] $NoBackup,
        [switch] $Quiet,
        [switch] $PassThru
    )

    # Prefix so that -WhatIf never announces an action as done.
    $simulated = ''
    if ($WhatIfPreference) { $simulated = '(simulation) ' }

    $result = [ordered]@{
        Theme           = 'skipped'
        TabRowColor     = $null
        Backdrop        = 'skipped'
        BackdropColor   = $null
        SystemTitleBar  = 'not requested'
        Profiles        = @()
        EnableArguments = $null
        Enabled         = $false
        RestartNeeded   = $false
    }

    if (-not $Quiet) {
        $version = (Get-Module TerminalColors).Version
        Write-Host ''
        Write-Host "  TerminalColors $version" -ForegroundColor White
        Write-Host '  ============================' -ForegroundColor DarkGray
        Write-Host ''
    }

    # --- 1. Windows Terminal theme ------------------------------------------
    # -WhatIf is forwarded explicitly rather than relying on the preference
    # variable, so the intent is visible at every call site.
    if (-not $SkipTheme) {
        try {
            $step = Install-TerminalColorsTheme -Force:$Force -NoBackup:$NoBackup -WhatIf:$WhatIfPreference
            $result.TabRowColor = $step.TabRowColor
            if ($step.Changed) {
                $result.Theme = 'installed'
                Write-TcStep -Quiet:$Quiet -Message "$($simulated)Windows Terminal theme installed ($($step.Changes -join ', '))"
                if ($step.Backup) { Write-TcStep -Quiet:$Quiet -Message "settings.json backup: $($step.Backup)" }
            } else {
                $result.Theme = 'already in place'
                Write-TcStep -Quiet:$Quiet -Message 'Windows Terminal theme already in place'
            }
        } catch {
            $result.Theme = "failed: $($_.Exception.Message)"
            Write-TcNote -Quiet:$Quiet -Message "Theme not installed: $($_.Exception.Message)"
            Write-TcNote -Quiet:$Quiet -Message 'Without the theme, the tab and the window border will not change colour.'
        }
    } else {
        Write-TcNote -Quiet:$Quiet -Message 'Windows Terminal theme skipped (-SkipTheme).'
    }

    # --- 2. Opaque backdrop --------------------------------------------------
    # This is what allows a full-strength colour on the tab without colouring the
    # pane: the background colour carries the pure project colour (the tab copies
    # it), and a solid image of your usual background colour covers the pane.
    $backdropReady = $false
    if (-not $SkipBackdrop) {
        try {
            $step = Install-TerminalColorsBackdrop -NoBackup:$NoBackup -WhatIf:$WhatIfPreference
            $backdropReady = $true
            $result.BackdropColor = $step.Color
            if ($step.Changed) {
                $result.Backdrop = 'installed'
                Write-TcStep -Quiet:$Quiet -Message "$($simulated)Opaque backdrop installed: the pane stays $($step.Color)"
                if ($step.Backup) { Write-TcStep -Quiet:$Quiet -Message "settings.json backup: $($step.Backup)" }
            } else {
                $result.Backdrop = 'already in place'
                Write-TcStep -Quiet:$Quiet -Message "Opaque backdrop already in place (pane $($step.Color))"
            }
        } catch {
            $result.Backdrop = "failed: $($_.Exception.Message)"
            Write-TcNote -Quiet:$Quiet -Message "Opaque backdrop not installed: $($_.Exception.Message)"
            Write-TcNote -Quiet:$Quiet -Message 'The colour will stay diluted on the pane background.'
        }
    } else {
        Write-TcNote -Quiet:$Quiet -Message 'Opaque backdrop skipped (-SkipBackdrop): the colour will be diluted on the pane background.'
    }

    # --- 3. System title bar (optional) -------------------------------------
    if ($SystemTitleBar) {
        try {
            $step = Install-TerminalColorsTitleBar -NoBackup:$NoBackup -WhatIf:$WhatIfPreference
            if ($step -and $step.Changed) {
                $result.SystemTitleBar = 'enabled'
                $result.RestartNeeded = $true
                Write-TcStep -Quiet:$Quiet -Message "$($simulated)System title bar enabled (showTabsInTitlebar: false)"
                Write-TcNote -Quiet:$Quiet -Message 'Close Windows Terminal completely for this setting to take effect.'
            } else {
                $result.SystemTitleBar = 'already enabled'
                Write-TcStep -Quiet:$Quiet -Message 'System title bar already enabled'
            }
        } catch {
            $result.SystemTitleBar = "failed: $($_.Exception.Message)"
            Write-TcNote -Quiet:$Quiet -Message "System title bar not enabled: $($_.Exception.Message)"
        }
    }

    # --- 4. PowerShell profile ----------------------------------------------
    # The backdrop is only worth having with -PureColor, so add it - unless the
    # caller has already expressed a dilution preference of their own.
    $effectiveArguments = $EnableArguments
    if ($backdropReady -and $EnableArguments -notmatch '-(PureColor|Tint)\b') {
        $effectiveArguments = ('-PureColor ' + $EnableArguments).Trim()
    }
    $result.EnableArguments = $effectiveArguments

    if (-not $SkipProfile) {
        # Both editions' profiles when both are installed, so the colouring works
        # whichever one a Windows Terminal profile happens to launch.
        # Uninstall-TerminalColors reads the same list, so it can never clean less
        # than what was written.
        $touched = @()
        foreach ($profilePath in (Get-TcProfilePath)) {
            try {
                $step = Install-TerminalColorsProfile -ProfilePath $profilePath -EnableArguments $effectiveArguments -NoBackup:$NoBackup -WhatIf:$WhatIfPreference
                $touched += $step.ProfilePath
                if ($step.Changed) {
                    Write-TcStep -Quiet:$Quiet -Message "$($simulated)Profile updated: $($step.ProfilePath) ($($step.Action))"
                } else {
                    Write-TcStep -Quiet:$Quiet -Message "Profile already up to date: $($step.ProfilePath)"
                }
            } catch {
                Write-TcNote -Quiet:$Quiet -Message "Profile [$profilePath] not modified: $($_.Exception.Message)"
            }
        }
        $result.Profiles = $touched
    } else {
        Write-TcNote -Quiet:$Quiet -Message 'PowerShell profile skipped (-SkipProfile).'
    }

    # --- 5. Immediate activation --------------------------------------------
    if ($WhatIfPreference) {
        Write-TcNote -Quiet:$Quiet -Message '-WhatIf mode: nothing was written, and this session was not modified.'
    } elseif (Test-TcWindowsTerminal) {
        if ($effectiveArguments) {
            Write-TcStep -Quiet:$Quiet -Message "Enabling with: $effectiveArguments"
            # The arguments come from the caller, who is already running this
            # command: there is no trust boundary to cross here.
            Invoke-Expression "Enable-TerminalColors $effectiveArguments"
        } else {
            Enable-TerminalColors
        }
        $result.Enabled = $true
        Write-TcStep -Quiet:$Quiet -Message 'Colouring active in this session'
    } else {
        Write-TcNote -Quiet:$Quiet -Message 'Not a Windows Terminal session: open Windows Terminal to see the result.'
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host '  Done.' -ForegroundColor Green
        Write-Host ''
        Write-Host '  To check:         ' -NoNewline; Write-Host 'Invoke-TerminalColorsDoctor' -ForegroundColor White
        Write-Host '  To try it:        ' -NoNewline; Write-Host 'cd <a Git repository> and look at the tab' -ForegroundColor White
        Write-Host '  To pick a colour: ' -NoNewline; Write-Host 'Set-FolderColor ''#215732''' -ForegroundColor White
        Write-Host ''
    }

    if ($PassThru) { return [pscustomobject]$result }
}

function Uninstall-TerminalColors {
    <#
        .SYNOPSIS
        Undoes everything Install-TerminalColors set up.

        .DESCRIPTION
        Removes the profile block, the opaque backdrop and the theme, restores what
        was there before, and returns the current session to its normal appearance.
        The module itself is left in place - remove it with
        Uninstall-Module TerminalColors, or by deleting its folder.

        .PARAMETER KeepTheme
        Leaves the Windows Terminal theme installed and selected.

        .PARAMETER NoBackup
        Does not write backup copies of settings.json.

        .PARAMETER Quiet
        Prints nothing.

        .EXAMPLE
        Uninstall-TerminalColors
    #>
    # Same as Install-TerminalColors: the removals are all performed by
    # sub-commands that implement ShouldProcess themselves.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Delegated to the sub-commands, which each call ShouldProcess; -WhatIf is forwarded to all of them.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [switch] $KeepTheme,
        [switch] $NoBackup,
        [switch] $Quiet
    )

    # Order matters: the profile first, so a new session started midway does not
    # reapply what is being removed.
    #
    # Every profile the install writes to, not just the current edition's, read from
    # the same helper it uses. A profile that carries no block is left alone rather
    # than warned about: it was never touched.
    foreach ($profilePath in (Get-TcProfilePath)) {
        if (-not (Test-TerminalColorsProfile -ProfilePath $profilePath)) { continue }
        try {
            Uninstall-TerminalColorsProfile -ProfilePath $profilePath -WhatIf:$WhatIfPreference
            Write-TcStep -Quiet:$Quiet -Message "Removed: the block in $profilePath"
        } catch {
            Write-TcNote -Quiet:$Quiet -Message "PowerShell profile [$profilePath]: $($_.Exception.Message)"
        }
    }

    foreach ($action in @(
        @{ Name = 'opaque backdrop'; Script = { Uninstall-TerminalColorsBackdrop -NoBackup:$NoBackup -WhatIf:$WhatIfPreference } }
        @{ Name = 'system title bar'; Script = { if (Test-TerminalColorsTitleBar) { Uninstall-TerminalColorsTitleBar -NoBackup:$NoBackup -WhatIf:$WhatIfPreference } } }
    )) {
        try {
            & $action.Script | Out-Null
            Write-TcStep -Quiet:$Quiet -Message "Removed: $($action.Name)"
        } catch {
            Write-TcNote -Quiet:$Quiet -Message "$($action.Name): $($_.Exception.Message)"
        }
    }

    if (-not $KeepTheme) {
        try {
            Uninstall-TerminalColorsTheme -NoBackup:$NoBackup -WhatIf:$WhatIfPreference | Out-Null
            Write-TcStep -Quiet:$Quiet -Message 'Removed: Windows Terminal theme'
        } catch {
            Write-TcNote -Quiet:$Quiet -Message "Theme: $($_.Exception.Message)"
        }
    }

    if (-not $WhatIfPreference) {
        try { Disable-TerminalColors } catch {
            Write-Verbose "TerminalColors: could not restore this session ($($_.Exception.Message))"
        }
        Write-TcStep -Quiet:$Quiet -Message 'This session restored to its normal appearance'
    }
}
