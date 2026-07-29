# Reglages PSScriptAnalyzer du depot.
#
#     Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
#
# Chaque exclusion est un choix de conception assume, pas un contournement : la
# raison est ecrite a cote. Si vous devez en ajouter une, expliquez pourquoi ici
# plutot que de la masquer en silence.

@{
    # Les regles de severite Information sont du style (parametres positionnels,
    # OutputType) : utiles a la relecture, pas assez pour bloquer une CI.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Le docteur et l'installateur ecrivent pour un humain, en couleur, dans
        # une console. C'est exactement l'usage legitime de Write-Host : leur
        # sortie n'est pas une valeur de retour a rediriger.
        'PSAvoidUsingWriteHost'

        # [Colors] est le nom du produit. Renommer Enable-TerminalColors en
        # Enable-TerminalColor casserait l'API publique pour satisfaire une
        # regle de grammaire.
        'PSUseSingularNouns'

        # $global:TerminalColorsOriginalPrompt et la lecture de $global:PWD sont
        # deliberement globales : le hook d'invite s'execute dans la portee
        # globale, et un module possede sa propre portee de session - une
        # variable de module y serait invisible.
        'PSAvoidGlobalVars'

        # L'etat modifie par Set-TcTerminalBackground, Update-TerminalColor ou
        # Set-TcWindowBorderColor est l'apparence de la session en cours, pas le
        # systeme : -WhatIf n'y a aucun sens, et le proposer sur le hook d'invite
        # serait nuisible. Les commandes qui ecrivent reellement sur le disque
        # (Set-FolderColor, Remove-FolderColor, les Install-/Uninstall-)
        # implementent toutes SupportsShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'

        # Silence delibere et documente sur quatre chemins qui ne doivent jamais
        # lever : le hook d'invite, le OnRemove du module, la lecture de
        # $global:PWD, et la sonde de date de modification appelee a chaque
        # invite. Y ajouter un Write-Verbose polluerait un chemin chaud.
        'PSAvoidUsingEmptyCatchBlock'

        # Get-WmiObject n'est utilise qu'en repli, quand Get-CimInstance echoue -
        # ce qui arrive sur des postes ou le service WinRM/CIM est bride.
        'PSAvoidUsingWMICmdlet'

        # install.ps1 transmet la chaine -EnableArguments fournie par
        # l'utilisateur lui-meme, qui execute deja le script : il n'y a pas de
        # frontiere de confiance a franchir ici.
        'PSAvoidUsingInvokeExpression'

        # Faux positifs : la regle ne voit pas les parametres utilises dans un
        # bloc de script imbrique (& $m { param($x) ... }), ce dont la suite de
        # tests se sert partout.
        'PSReviewUnusedParameter'
    )
}
