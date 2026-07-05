<#
.SYNOPSIS
    Interactive text-based menu (TUI) for the Intune Remediation toolkit.

.DESCRIPTION
    Provides an arrow-key driven console menu that surfaces every option of the
    Export-IntuneRemediation and Publish-IntuneRemediation functions, then invokes
    the chosen function with the matching parameters. No Intune logic is duplicated
    here - this is purely a front-end launcher.

    Navigation:
      Up / Down arrows (or number keys) to move, Enter to select, Esc to go back.

.PARAMETER Path
    Root path containing the remediation script folders. Defaults to the script's
    own folder. Passed through to the Export/Publish functions as needed.

.PARAMETER StartAt
    Jump straight to a specific menu (used by Publish-IntuneRemediation -Menu).
    Default 'Main' shows the top-level menu.

.EXAMPLE
    Start-RemediationToolkit

.NOTES
    Author: Mark Orr
#>
function Start-RemediationToolkit {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = (Get-Location).Path,

        # Jump straight to a specific menu (used by Push -Menu / Export -Menu). Default
        # 'Main' shows the top-level menu.
        [Parameter()]
        [ValidateSet('Main', 'Push', 'Export')]
        [string]$StartAt = 'Main'
    )

    # ========================================================================
    #  MAIN LOOP
    # ========================================================================

    # When launched into a specific submenu (e.g. from Push -Menu), run just that
    # menu and exit rather than showing the top-level menu.
    switch ($StartAt) {
        'Push'   { Invoke-PushMenu;   return }
        'Export' { Invoke-ExportMenu; return }
    }

    while ($true) {
        $choice = Show-Menu -Title "Main menu" -Options @(
            "Export remediations FROM Intune",
            "Push remediations TO Intune",
            "Help / command reference",
            "Exit"
        ) -Hints @(
            "Download all remediations to disk + CSV reports",
            "Create / update / preview remediations from local folders",
            "Comprehensive help for every command and setting",
            ""
        )

        switch ($choice) {
            0       { Invoke-ExportMenu }
            1       { Invoke-PushMenu }
            2       { Show-Header; Show-RemediationToolkitHelp; Wait-ForKey }
            default {
                Show-Header
                Write-Host "  Goodbye." -ForegroundColor Green
                Write-Host ""
                break
            }
        }
    }
}
