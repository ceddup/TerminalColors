# Repository PSScriptAnalyzer settings.
#
#     Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
#
# Every exclusion is a deliberate design decision, not a workaround: the reason is
# written next to it. If you need to add one, explain why here rather than hiding
# it silently.

@{
    # Information-severity rules are stylistic (positional parameters,
    # OutputType): useful when reviewing, not enough to block a CI run.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # The doctor and the installer write for a human, in colour, in a console.
        # That is exactly the legitimate use of Write-Host: their output is not a
        # return value meant to be redirected.
        'PSAvoidUsingWriteHost'

        # [Colors] is the product name. Renaming Enable-TerminalColors to
        # Enable-TerminalColor would break the public API to satisfy a grammar
        # rule.
        'PSUseSingularNouns'

        # $global:TerminalColorsOriginalPrompt and reading $global:PWD are
        # deliberately global: the prompt hook runs in the global scope, and a
        # module owns its own session scope - a module variable would be invisible
        # there.
        'PSAvoidGlobalVars'

        # The state changed by Set-TcTerminalBackground, Update-TerminalColor or
        # Set-TcWindowBorderColor is the appearance of the current session, not the
        # system: -WhatIf makes no sense there, and offering it on the prompt hook
        # would be harmful. The commands that really write to disk
        # (Set-FolderColor, Remove-FolderColor, the Install-/Uninstall- ones) all
        # implement SupportsShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'

        # Deliberate, documented silence on four paths that must never throw: the
        # prompt hook, the module's OnRemove, reading $global:PWD, and the
        # modification-time probe called on every prompt. Adding a Write-Verbose
        # there would pollute a hot path.
        'PSAvoidUsingEmptyCatchBlock'

        # Get-WmiObject is only used as a fallback, when Get-CimInstance fails -
        # which happens on machines where the WinRM/CIM service is restricted.
        'PSAvoidUsingWMICmdlet'

        # install.ps1 forwards the -EnableArguments string supplied by the user
        # themselves, who is already running the script: there is no trust
        # boundary to cross here.
        'PSAvoidUsingInvokeExpression'

        # False positives: the rule does not see parameters used inside a nested
        # script block (& $m { param($x) ... }), which the test suite relies on
        # throughout.
        'PSReviewUnusedParameter'
    )
}
