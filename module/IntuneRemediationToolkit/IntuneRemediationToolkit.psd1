@{
    RootModule        = 'IntuneRemediationToolkit.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a018adfc-a1d5-4959-851e-05c22aa8c60f'
    Author            = 'Mark Orr'
    Description       = 'Intune Remediation Toolkit - export Intune proactive remediation scripts to disk and publish them back to Intune, with an interactive console menu.'

    PowerShellVersion = '7.0'

    RequiredModules   = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.DeviceManagement'
    )

    FunctionsToExport = @(
        'Export-IntuneRemediation',
        'Publish-IntuneRemediation',
        'Start-RemediationToolkit',
        'Show-RemediationToolkitHelp'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Push-IntuneRemediation')
}
