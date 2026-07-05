# ============================================================================
#  INTERACTIVE PROMPT HELPERS
#  Used by Publish-IntuneRemediation's -Interactive create/update flows.
# ============================================================================

# Free-text prompt that keeps the current value when the user just presses Enter
function Read-TextSetting {
    param([string]$Label, [string]$Current)
    $shown = if ([string]::IsNullOrWhiteSpace($Current)) { "(empty)" } else { $Current }
    $value = Read-Host "    $Label [$shown] (Enter = keep)"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Current }
    return $value
}

# Yes/No prompt that keeps the current boolean when the user just presses Enter
function Read-BoolSetting {
    param([string]$Label, [bool]$Current)
    $shown = if ($Current) { "Yes" } else { "No" }
    while ($true) {
        $value = Read-Host "    $Label [$shown] (Y/N, Enter = keep)"
        if ([string]::IsNullOrWhiteSpace($value)) { return $Current }
        switch -Regex ($value.Trim()) {
            '^(y|yes|true|1)$' { return $true }
            '^(n|no|false|0)$' { return $false }
            default { Write-Host "    Please enter Y or N." -ForegroundColor Yellow }
        }
    }
}

# Choice prompt from a fixed set that keeps the current value on empty input
function Read-ChoiceSetting {
    param([string]$Label, [string]$Current, [string[]]$Choices)
    $list = $Choices -join ' / '
    while ($true) {
        $value = Read-Host "    $Label [$Current] ($list, Enter = keep)"
        if ([string]::IsNullOrWhiteSpace($value)) { return $Current }
        $match = $Choices | Where-Object { $_ -ieq $value.Trim() } | Select-Object -First 1
        if ($match) { return $match }
        Write-Host "    Please enter one of: $list" -ForegroundColor Yellow
    }
}

# Print the current live settings so the user can see them before changing anything.
# Shown in red to make the existing/current values stand out before any change.
function Show-RemediationSettings {
    param([object]$Live)
    Write-Host "`n  ---- Current settings in Intune ----" -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Display Name',          $Live.displayName)          -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Description',           $Live.description)           -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Publisher',             $Live.publisher)             -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Run As Account',        $Live.runAsAccount)          -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Run As 32-bit',         $Live.runAs32Bit)            -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Enforce Signature',     $Live.enforceSignatureCheck) -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Scope Tag Ids',         ($Live.roleScopeTagIds -join ', ')) -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Version',               $Live.version)               -ForegroundColor Red
    Write-Host ("    {0,-24}: {1}" -f 'Last Modified',         $Live.lastModifiedDateTime)  -ForegroundColor Red
    Write-Host "  ------------------------------------" -ForegroundColor Red
}

# Interactively prompt for the create settings + assignment/schedule, writing the
# choices onto the metadata object (defaults come from the folder's metadata.json).
function Read-CreateSettings {
    param([object]$Metadata, [string]$FolderName)

    Write-Host "`n  ---- New remediation settings ----" -ForegroundColor Cyan
    Write-Host "  Enter values (press Enter to accept the [default]):" -ForegroundColor Gray

    # Precompute defaults (an 'if' expression is only valid in statement position,
    # not inline as a command argument).
    $defaultName  = if ($Metadata.DisplayName)     { $Metadata.DisplayName }     else { $FolderName }
    $defaultRunAs = if ($Metadata.RunAsAccount)    { $Metadata.RunAsAccount }    else { 'system' }
    $defaultScope = if ($Metadata.RoleScopeTagIds) { $Metadata.RoleScopeTagIds } else { '0' }

    $Metadata.DisplayName           = Read-TextSetting   -Label 'Display Name'      -Current $defaultName
    $Metadata.Description            = Read-TextSetting   -Label 'Description'       -Current $Metadata.Description
    $Metadata.Publisher             = Read-TextSetting   -Label 'Publisher'         -Current $Metadata.Publisher
    $Metadata.RunAsAccount          = Read-ChoiceSetting -Label 'Run As Account'    -Current $defaultRunAs -Choices @('system','user')
    $Metadata.RunAs32Bit            = Read-BoolSetting   -Label 'Run As 32-bit'     -Current ([bool]$Metadata.RunAs32Bit)
    $Metadata.EnforceSignatureCheck = Read-BoolSetting   -Label 'Enforce Signature' -Current ([bool]$Metadata.EnforceSignatureCheck)
    $Metadata.RoleScopeTagIds       = Read-TextSetting   -Label 'Scope Tag Ids'     -Current $defaultScope

    # --- Assignment ---
    Write-Host "`n  ---- Assignment ----" -ForegroundColor Cyan
    $assignTarget = Read-ChoiceSetting -Label 'Assign to' -Current 'None' -Choices @('None','AllDevices','AllUsers','Group')

    if ($assignTarget -eq 'None') {
        # Remove any assignment block so no assignment is created
        if ($Metadata.PSObject.Properties['Assignment']) { $Metadata.PSObject.Properties.Remove('Assignment') }
        Write-Host "  No assignment will be created." -ForegroundColor Gray
        return
    }

    $assignment = [ordered]@{ Target = $assignTarget }

    if ($assignTarget -eq 'Group') {
        while ($true) {
            $gid = Read-Host "    Group Object Id (GUID)"
            if ($gid -match '^[0-9a-fA-F-]{36}$') { $assignment.GroupId = $gid.Trim(); break }
            Write-Host "    Please enter a valid group object Id (GUID)." -ForegroundColor Yellow
        }
        $assignment.GroupName = Read-Host "    Group name (optional, for reference)"
    }

    # --- Schedule ---
    $scheduleType = Read-ChoiceSetting -Label 'Schedule' -Current 'Daily' -Choices @('Daily','Hourly','Once')
    $assignment.ScheduleType = $scheduleType

    switch ($scheduleType) {
        'Daily' {
            $assignment.Interval  = [int](Read-TextSetting -Label 'Every N day(s)' -Current '1')
            $assignment.StartTime = Read-TextSetting -Label 'Start time (HH:mm)' -Current '01:00'
        }
        'Hourly' {
            $assignment.Interval  = [int](Read-TextSetting -Label 'Every N hour(s)' -Current '1')
        }
        'Once' {
            $assignment.StartDate = Read-TextSetting -Label 'Run date (YYYY-MM-DD)' -Current (Get-Date).AddDays(1).ToString('yyyy-MM-dd')
            $assignment.StartTime = Read-TextSetting -Label 'Run time (HH:mm)' -Current '01:00'
        }
    }

    $assignment.RunRemediation = Read-BoolSetting -Label 'Run remediation script' -Current $true
    $assignment.UseUtc         = $false

    # Attach the assignment to the metadata object (add or replace)
    if ($Metadata.PSObject.Properties['Assignment']) {
        $Metadata.Assignment = [pscustomobject]$assignment
    }
    else {
        $Metadata | Add-Member -NotePropertyName 'Assignment' -NotePropertyValue ([pscustomobject]$assignment)
    }
}
