# ============================================================================
#  INTUNE REMEDIATION GRAPH API OPERATIONS
#  Encoding, request-body builder, create/update, live read, and assignments.
#  Create / update both handle the approval workflow: a 412/409 response means
#  the change was accepted but needs portal approval, which is surfaced (not
#  treated as a hard failure) to the caller.
# ============================================================================

# Convert script content to base64
function ConvertTo-Base64 {
    param([string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    return [Convert]::ToBase64String($bytes)
}

# Build the deviceHealthScript request body used by both create and update.
# IMPORTANT: never emit JSON null - the Intune approval "completion" step re-validates
# the stored payload against the schema, and null publisher/description (or a missing
# roleScopeTagIds) fails that validation ("completion action fails"). So string fields
# are coerced to strings, booleans to real booleans, and scope tags default to '0'.
function New-RemediationRequestBody {
    param(
        [PSCustomObject]$Metadata,
        [string]$DetectionScriptContent,
        [string]$RemediationScriptContent
    )

    # Scope tags: split the comma-separated string; default to '0' (Default) if empty
    $scopeTags = @(
        "$($Metadata.RoleScopeTagIds)" -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    )
    if ($scopeTags.Count -eq 0) { $scopeTags = @('0') }

    # Run-as account must be a non-empty string; default to 'system'
    $runAs = if ([string]::IsNullOrWhiteSpace($Metadata.RunAsAccount)) { 'system' } else { "$($Metadata.RunAsAccount)".Trim() }

    $body = @{
        '@odata.type'          = '#microsoft.graph.deviceHealthScript'
        displayName            = "$($Metadata.DisplayName)"
        description            = "$($Metadata.Description)"
        publisher              = "$($Metadata.Publisher)"
        runAsAccount           = $runAs
        enforceSignatureCheck  = [bool]$Metadata.EnforceSignatureCheck
        runAs32Bit             = [bool]$Metadata.RunAs32Bit
        roleScopeTagIds        = $scopeTags
        detectionScriptContent = ConvertTo-Base64 -Content $DetectionScriptContent
    }

    if ($RemediationScriptContent) {
        $body.remediationScriptContent = ConvertTo-Base64 -Content $RemediationScriptContent
    }

    return $body
}

# Create remediation script in Intune
function New-IntuneRemediationScript {
    param(
        [PSCustomObject]$Metadata,
        [string]$DetectionScriptContent,
        [string]$RemediationScriptContent,
        [string]$Justification = "Automated remediation script deployment via Push-RemediationsToIntune.ps1"
    )

    $body = New-RemediationRequestBody -Metadata $Metadata -DetectionScriptContent $DetectionScriptContent -RemediationScriptContent $RemediationScriptContent

    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"
        $justificationBase64 = ConvertTo-Base64 -Content $Justification
        $headers = @{
            'x-msft-approval-justification' = $justificationBase64
        }
        $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        return $response
    }
    catch {
        # Get full error details
        $errorDetails = $_.Exception.Message
        $fullError = $_ | Out-String

        # Check if approval is required (multiple patterns)
        $isApprovalRequired = (
            $errorDetails -match '412 Precondition Failed' -or
            $errorDetails -match 'PreconditionFailed' -or
            $errorDetails -match 'Precondition Failed' -or
            $errorDetails -match 'x-msft-approval-code' -or
            $fullError -match 'x-msft-approval-code' -or
            $fullError -match 'Approval Required'
        )

        if ($isApprovalRequired) {
            # Try to extract approval code from error details or full error
            if ($errorDetails -match 'x-msft-approval-code[:\s\\"]+([a-f0-9-]+)') {
                $approvalCode = $matches[1]
            }
            elseif ($fullError -match 'x-msft-approval-code[:\s\\"]+([a-f0-9-]+)') {
                $approvalCode = $matches[1]
            }
            else {
                $approvalCode = 'CHECK_PORTAL'
            }

            # Return a special object to indicate approval is pending
            return @{
                approvalRequired = $true
                approvalCode = $approvalCode
            }
        }

        # For other errors, return error details
        return @{
            error = $true
            message = $errorDetails
        }
    }
}

# Update existing remediation script in Intune
function Update-IntuneRemediationScript {
    param(
        [string]$Id,
        [PSCustomObject]$Metadata,
        [string]$DetectionScriptContent,
        [string]$RemediationScriptContent,
        [string]$Justification = "Automated remediation script update via Push-RemediationsToIntune.ps1"
    )

    $body = New-RemediationRequestBody -Metadata $Metadata -DetectionScriptContent $DetectionScriptContent -RemediationScriptContent $RemediationScriptContent

    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$Id"
        $justificationBase64 = ConvertTo-Base64 -Content $Justification
        $headers = @{
            'x-msft-approval-justification' = $justificationBase64
        }
        $response = Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers -ErrorAction Stop
        return $response
    }
    catch {
        # Get full error details
        $errorDetails = $_.Exception.Message
        $fullError = $_ | Out-String

        # Check if approval is required (multiple patterns)
        $isApprovalRequired = (
            $errorDetails -match '412 Precondition Failed' -or
            $errorDetails -match 'PreconditionFailed' -or
            $errorDetails -match 'Precondition Failed' -or
            $errorDetails -match 'x-msft-approval-code' -or
            $fullError -match 'x-msft-approval-code' -or
            $fullError -match 'Approval Required'
        )

        if ($isApprovalRequired) {
            # Try to extract approval code from error details or full error
            if ($errorDetails -match 'x-msft-approval-code[:\s\\"]+([a-f0-9-]+)') {
                $approvalCode = $matches[1]
            }
            elseif ($fullError -match 'x-msft-approval-code[:\s\\"]+([a-f0-9-]+)') {
                $approvalCode = $matches[1]
            }
            else {
                $approvalCode = 'CHECK_PORTAL'
            }

            # Return a special object to indicate approval is pending (don't write error)
            return @{
                approvalRequired = $true
                approvalCode = $approvalCode
                id = $Id
            }
        }

        # Check if an approval request already exists (409 Conflict)
        if ($errorDetails -match '409 Conflict' -and $errorDetails -match 'An active Approval Request already exists') {
            # Return a special object to indicate approval is already pending (don't write error)
            return @{
                approvalRequired = $true
                approvalCode = 'PENDING'
                id = $Id
            }
        }

        # For other errors, return error details
        return @{
            error = $true
            message = $errorDetails
        }
    }
}

# Fetch the current (live) settings for a remediation script from Intune
function Get-LiveRemediationScript {
    param([string]$Id)
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$Id"
        return Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    }
    catch {
        Write-Warning "  Could not read current settings for ID $Id : $($_.Exception.Message)"
        return $null
    }
}

# Build the Graph "assign" body from an Assignment object (stored in metadata.json).
# Supports All Devices / All Users / a specific group, plus Daily/Hourly/Once schedules.
function Get-RemediationAssignmentBody {
    param([object]$Assignment)

    # Assignment target
    switch ($Assignment.Target) {
        'AllDevices' { $target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }
        'AllUsers'   { $target = @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' } }
        'Group'      { $target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $Assignment.GroupId } }
        default      { throw "Unknown assignment target '$($Assignment.Target)'" }
    }

    $entry = @{
        target               = $target
        runRemediationScript = [bool]$Assignment.RunRemediation
    }

    # Run schedule (normalize HH:mm -> HH:mm:ss for Graph)
    if ($Assignment.ScheduleType) {
        $time = $Assignment.StartTime
        if ($time -and $time -notmatch ':\d{2}:\d{2}$') { $time = "$time`:00" }
        $useUtc = [bool]$Assignment.UseUtc

        switch ($Assignment.ScheduleType) {
            'Daily' {
                $entry.runSchedule = @{
                    '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'
                    interval = [int]$Assignment.Interval
                    time     = $time
                    useUtc   = $useUtc
                }
            }
            'Hourly' {
                $entry.runSchedule = @{
                    '@odata.type' = '#microsoft.graph.deviceHealthScriptHourlySchedule'
                    interval = [int]$Assignment.Interval
                }
            }
            'Once' {
                $entry.runSchedule = @{
                    '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
                    interval = 1
                    date     = $Assignment.StartDate
                    time     = $time
                    useUtc   = $useUtc
                }
            }
        }
    }

    return @{ deviceHealthScriptAssignments = @($entry) }
}

# POST the assignment for a newly-created remediation script
function Set-IntuneRemediationAssignment {
    param([string]$Id, [object]$Assignment)
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$Id/assign"
        $body = Get-RemediationAssignmentBody -Assignment $Assignment
        Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($body | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
        return @{ success = $true }
    }
    catch {
        return @{ error = $true; message = $_.Exception.Message }
    }
}
