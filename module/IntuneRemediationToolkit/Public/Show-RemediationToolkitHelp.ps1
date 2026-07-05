<#
.SYNOPSIS
    Shows a comprehensive, colorized help reference for the IntuneRemediationToolkit module.

.DESCRIPTION
    Prints an at-a-glance reference covering every command, common workflows, the
    Microsoft Graph permissions each command needs, the metadata.json and Assignment
    schemas, the approval workflow, and pointers to per-command help.

    Run with no parameters for the full reference, or -Command <name> to jump to a
    single command's detailed help (wraps Get-Help -Full).

.PARAMETER Command
    Show detailed Get-Help for a single command instead of the overview.
    Valid values: Export-IntuneRemediation, Publish-IntuneRemediation,
    Start-RemediationToolkit, Show-RemediationToolkitHelp.

.EXAMPLE
    Show-RemediationToolkitHelp

.EXAMPLE
    Show-RemediationToolkitHelp -Command Publish-IntuneRemediation

.NOTES
    Author: Mark Orr
#>
function Show-RemediationToolkitHelp {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet(
            'Export-IntuneRemediation',
            'Publish-IntuneRemediation',
            'Start-RemediationToolkit',
            'Show-RemediationToolkitHelp'
        )]
        [string]$Command
    )

    # -Command: defer to native Get-Help for the full, per-command detail
    if ($Command) {
        Get-Help $Command -Full
        return
    }

    $h1 = 'Cyan'      # section headers
    $cmd = 'Yellow'   # command names
    $ex  = 'Green'    # examples
    $txt = 'White'    # body text
    $dim = 'Gray'     # secondary detail

    function Write-Section { param([string]$Title)
        Write-Host ""
        Write-Host ("=" * 70) -ForegroundColor $h1
        Write-Host "  $Title" -ForegroundColor $h1
        Write-Host ("=" * 70) -ForegroundColor $h1
    }

    Write-Host ""
    Write-Host "  Intune Remediation Toolkit" -ForegroundColor $h1
    Write-Host "  Export, edit, and publish Intune proactive remediation (device" -ForegroundColor $dim
    Write-Host "  health) scripts via Microsoft Graph - CLI or interactive menu." -ForegroundColor $dim
    Write-Host "  Author: Mark Orr" -ForegroundColor $dim

    # ---- Commands -----------------------------------------------------------
    Write-Section "COMMANDS"
    $cmds = @(
        @{ Name = 'Export-IntuneRemediation';    Purpose = 'Download every remediation from Intune to disk + CSV reports' }
        @{ Name = 'Publish-IntuneRemediation';   Purpose = 'Create / update remediations in Intune from local folders' }
        @{ Name = 'Start-RemediationToolkit';    Purpose = 'Interactive arrow-key menu (TUI) that drives the above' }
        @{ Name = 'Show-RemediationToolkitHelp'; Purpose = 'This reference' }
    )
    foreach ($c in $cmds) {
        Write-Host ("    {0,-30}" -f $c.Name) -ForegroundColor $cmd -NoNewline
        Write-Host $c.Purpose -ForegroundColor $txt
    }
    Write-Host "    Alias: " -ForegroundColor $dim -NoNewline
    Write-Host "Push-IntuneRemediation" -ForegroundColor $cmd -NoNewline
    Write-Host " -> Publish-IntuneRemediation" -ForegroundColor $dim

    # ---- Quick start --------------------------------------------------------
    Write-Section "QUICK START"
    Write-Host "    # Back up everything from the tenant"                              -ForegroundColor $dim
    Write-Host "    Export-IntuneRemediation -OutputPath .\RemediationScripts"         -ForegroundColor $ex
    Write-Host ""
    Write-Host "    # Launch the interactive menu"                                     -ForegroundColor $dim
    Write-Host "    Start-RemediationToolkit"                                          -ForegroundColor $ex
    Write-Host ""
    Write-Host "    # Preview a push without touching Intune"                          -ForegroundColor $dim
    Write-Host "    Publish-IntuneRemediation -Path .\RemediationScripts -WhatIf"      -ForegroundColor $ex

    # ---- Workflows ----------------------------------------------------------
    Write-Section "WORKFLOWS"

    Write-Host "  EXPORT (read-only backup)" -ForegroundColor $txt
    Write-Host "    Export-IntuneRemediation [-OutputPath <dir>]"                      -ForegroundColor $ex
    Write-Host "    Writes one folder per remediation (detection.ps1, remediation.ps1," -ForegroundColor $dim
    Write-Host "    metadata.json) plus remediation-scripts-summary.csv and"           -ForegroundColor $dim
    Write-Host "    publishers-contact-list.csv."                                       -ForegroundColor $dim
    Write-Host ""

    Write-Host "  CREATE (guided)" -ForegroundColor $txt
    Write-Host "    Publish-IntuneRemediation -Create -Interactive -Path <folder>"     -ForegroundColor $ex
    Write-Host "    Prompts for every setting, then an optional assignment (All"        -ForegroundColor $dim
    Write-Host "    devices / All users / a group) and schedule (Daily/Hourly/Once),"   -ForegroundColor $dim
    Write-Host "    and assigns the script on create."                                  -ForegroundColor $dim
    Write-Host "    Non-interactive: -Create (reads settings from metadata.json)."      -ForegroundColor $dim
    Write-Host ""

    Write-Host "  UPDATE (guided)" -ForegroundColor $txt
    Write-Host "    Publish-IntuneRemediation -UpdateExisting -Interactive -Path <folder>" -ForegroundColor $ex
    Write-Host "    Shows the CURRENT live settings (in red), then lets you keep them"  -ForegroundColor $dim
    Write-Host "    as-is or modify each before patching. Matches by the Id in"         -ForegroundColor $dim
    Write-Host "    metadata.json. Non-interactive: -UpdateExisting."                    -ForegroundColor $dim
    Write-Host ""

    Write-Host "  MENU (TUI)" -ForegroundColor $txt
    Write-Host "    Start-RemediationToolkit          # full menu"                     -ForegroundColor $ex
    Write-Host "    Publish-IntuneRemediation -Menu   # straight to the Push menu"     -ForegroundColor $ex
    Write-Host "    Navigate: Up/Down or number keys, Enter to select, Esc to go back." -ForegroundColor $dim

    # ---- Key parameters -----------------------------------------------------
    Write-Section "KEY PARAMETERS (Publish-IntuneRemediation)"
    $params = @(
        @{ P = '-Create';               D = 'Create a new remediation (always POSTs a new object)' }
        @{ P = '-UpdateExisting';        D = 'Update the existing object matched by metadata.json Id' }
        @{ P = '-Interactive';           D = 'Prompt for settings (and assignment on create)' }
        @{ P = '-BrowseFolder';          D = 'Pick the source folder with a graphical dialog' }
        @{ P = '-Path <dir>';            D = 'Source folder (a single remediation folder or a parent)' }
        @{ P = '-FolderName <name>';     D = 'Process one named subfolder' }
        @{ P = '-ApprovalJustification'; D = 'Justification text for the approval request' }
        @{ P = '-WhatIf';                D = 'Preview only - nothing is uploaded' }
        @{ P = '-Menu';                  D = 'Open the interactive menu' }
    )
    foreach ($p in $params) {
        Write-Host ("    {0,-24}" -f $p.P) -ForegroundColor $cmd -NoNewline
        Write-Host $p.D -ForegroundColor $txt
    }

    # ---- Permissions --------------------------------------------------------
    Write-Section "REQUIRED GRAPH PERMISSIONS (delegated)"
    Write-Host "  Export-IntuneRemediation (read-only):" -ForegroundColor $txt
    Write-Host "    DeviceManagementConfiguration.Read.All   read scripts + assignments" -ForegroundColor $dim
    Write-Host "    Group.Read.All                           resolve assignment groups"  -ForegroundColor $dim
    Write-Host "    User.Read.All                            look up publisher emails"    -ForegroundColor $dim
    Write-Host ""
    Write-Host "  Publish-IntuneRemediation (read/write):" -ForegroundColor $txt
    Write-Host "    DeviceManagementConfiguration.ReadWrite.All   create/update + assign" -ForegroundColor $dim
    Write-Host ""
    Write-Host "  Plus an Intune role that can manage remediations (e.g. Intune"          -ForegroundColor $dim
    Write-Host "  Administrator). You are prompted to consent on first connect."          -ForegroundColor $dim

    # ---- metadata.json ------------------------------------------------------
    Write-Section "metadata.json (per remediation folder)"
    Write-Host "    DisplayName            string   (required)" -ForegroundColor $dim
    Write-Host "    Description            string" -ForegroundColor $dim
    Write-Host "    Publisher              string   (portal treats as required)" -ForegroundColor $dim
    Write-Host "    RunAsAccount           system | user" -ForegroundColor $dim
    Write-Host "    RunAs32Bit             true | false" -ForegroundColor $dim
    Write-Host "    EnforceSignatureCheck  true | false" -ForegroundColor $dim
    Write-Host "    RoleScopeTagIds        comma string, e.g. '0'" -ForegroundColor $dim
    Write-Host "    Id                     Intune object id (blank/absent = create)" -ForegroundColor $dim
    Write-Host "    Assignment             optional object (see below)" -ForegroundColor $dim

    # ---- Assignment ---------------------------------------------------------
    Write-Section "Assignment block (optional, drives assign-on-create)"
    Write-Host "    Target          AllDevices | AllUsers | Group" -ForegroundColor $dim
    Write-Host "    GroupId         GUID   (required when Target = Group)" -ForegroundColor $dim
    Write-Host "    GroupName       string (reference only)" -ForegroundColor $dim
    Write-Host "    ScheduleType    Daily | Hourly | Once" -ForegroundColor $dim
    Write-Host "    Interval        integer (every N days or hours)" -ForegroundColor $dim
    Write-Host "    StartTime       HH:mm   (Daily/Once)" -ForegroundColor $dim
    Write-Host "    StartDate       YYYY-MM-DD (Once only)" -ForegroundColor $dim
    Write-Host "    RunRemediation  true | false" -ForegroundColor $dim
    Write-Host "    UseUtc          true | false" -ForegroundColor $dim

    # ---- Approval -----------------------------------------------------------
    Write-Section "APPROVAL WORKFLOW"
    Write-Host "  If your tenant requires approval for remediation changes, a" -ForegroundColor $txt
    Write-Host "  create/update returns 'APPROVAL REQUIRED' with a code - this is NOT" -ForegroundColor $txt
    Write-Host "  a failure. Approve it here to apply the change:" -ForegroundColor $txt
    Write-Host "    Intune > Endpoint Security > Remediations > Approvals" -ForegroundColor $ex

    # ---- More help ----------------------------------------------------------
    Write-Section "MORE HELP"
    Write-Host "    Show-RemediationToolkitHelp -Command <name>   # detailed per-command help" -ForegroundColor $ex
    Write-Host "    Get-Help <command> -Full                       # native help" -ForegroundColor $ex
    Write-Host "    Get-Help about_RemediationToolkit              # concept topic" -ForegroundColor $ex
    Write-Host "    Get-Command -Module IntuneRemediationToolkit   # list commands" -ForegroundColor $ex
    Write-Host ""
}
