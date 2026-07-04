<#
.SYNOPSIS
    Exports all Intune remediation scripts (proactive remediations) to a local folder.

.DESCRIPTION
    Connects to Microsoft Graph, retrieves all device health scripts (remediation scripts),
    downloads their detection and remediation script content, and saves them to an organized folder structure.

.PARAMETER OutputPath
    The folder path where scripts will be exported. Defaults to .\RemediationScripts

.EXAMPLE
    .\Export-IntuneRemediationScripts.ps1

.EXAMPLE
    .\Export-IntuneRemediationScripts.ps1 -OutputPath "C:\Backup\Remediations"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\RemediationScripts"
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

$ErrorActionPreference = "Stop"

function Connect-ToGraph {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

    $requiredScopes = @(
        "DeviceManagementConfiguration.Read.All",
        "Group.Read.All",
        "User.Read.All"
    )

    try {
        # Suppress WAM output
        $null = Connect-MgGraph -Scopes $requiredScopes -NoWelcome -ErrorAction Stop *>&1
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        throw
    }
}

function Get-RemediationScripts {
    Write-Host "Retrieving remediation scripts from Intune..." -ForegroundColor Cyan

    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"
        $scripts = @()
        $pageCount = 0

        do {
            $pageCount++
            Write-Progress -Activity "Retrieving Remediation Scripts List" `
                          -Status "Fetching page $pageCount..." `
                          -PercentComplete -1

            $response = Invoke-MgGraphRequest -Method GET -Uri $uri
            $scripts += $response.value
            $uri = $response.'@odata.nextLink'

            Write-Progress -Activity "Retrieving Remediation Scripts List" `
                          -Status "Retrieved $($scripts.Count) script(s) so far..." `
                          -PercentComplete -1
        } while ($uri)

        Write-Progress -Activity "Retrieving Remediation Scripts List" -Completed
        Write-Host "Found $($scripts.Count) remediation script(s)" -ForegroundColor Green
        return $scripts
    }
    catch {
        Write-Error "Failed to retrieve remediation scripts: $_"
        throw
    }
}

function Get-RemediationScriptContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptId
    )

    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$ScriptId"
        $script = Invoke-MgGraphRequest -Method GET -Uri $uri
        return $script
    }
    catch {
        Write-Warning "Failed to retrieve content for script ID $ScriptId : $_"
        return $null
    }
}

function Get-RemediationScriptAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptId
    )

    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$ScriptId/assignments"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        return $response.value
    }
    catch {
        Write-Warning "Failed to retrieve assignments for script ID $ScriptId : $_"
        return @()
    }
}

function Get-GroupDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId
    )

    try {
        $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId"
        $group = Invoke-MgGraphRequest -Method GET -Uri $uri
        return $group.displayName
    }
    catch {
        return $GroupId
    }
}

function Get-UserEmail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return ""
    }

    try {
        # First try exact match on displayName
        $filter = "displayName eq '$($DisplayName.Replace("'", "''"))'"
        $uri = "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=displayName,mail,userPrincipalName"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri

        if ($response.value.Count -gt 0) {
            $user = $response.value[0]
            # Prefer mail over userPrincipalName
            if ($user.mail) {
                return $user.mail
            }
            else {
                return $user.userPrincipalName
            }
        }

        # If no exact match, try startswith search
        $filter = "startswith(displayName,'$($DisplayName.Replace("'", "''"))')"
        $uri = "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=displayName,mail,userPrincipalName"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri

        if ($response.value.Count -gt 0) {
            # Try to find best match
            $exactMatch = $response.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
            if ($exactMatch) {
                if ($exactMatch.mail) {
                    return $exactMatch.mail
                }
                else {
                    return $exactMatch.userPrincipalName
                }
            }
            else {
                # Return first result
                $user = $response.value[0]
                if ($user.mail) {
                    return $user.mail
                }
                else {
                    return $user.userPrincipalName
                }
            }
        }

        return ""
    }
    catch {
        Write-Warning "Could not find email for: $DisplayName - Error: $_"
        return ""
    }
}

function Export-ScriptContent {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Script,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    # Sanitize the script name for folder creation
    $scriptName = $Script.displayName
    # Replace invalid characters
    $scriptName = $scriptName -replace '[\\/:*?"<>|]', '_'
    # Replace multiple spaces with single underscore
    $scriptName = $scriptName -replace '\s+', '_'
    # Trim leading/trailing underscores and spaces
    $scriptName = $scriptName.Trim('_', ' ')
    # Ensure it's not too long (Windows path limit consideration)
    if ($scriptName.Length -gt 100) {
        $scriptName = $scriptName.Substring(0, 100)
    }

    $scriptFolder = Join-Path -Path $BasePath -ChildPath $scriptName

    if (-not (Test-Path -Path $scriptFolder)) {
        New-Item -Path $scriptFolder -ItemType Directory -Force | Out-Null
    }

    Write-Host "  Exporting: $($Script.displayName)" -ForegroundColor Yellow

    # Export metadata
    $metadata = [PSCustomObject]@{
        DisplayName = $Script.displayName
        Description = $Script.description
        Publisher = $Script.publisher
        Version = $Script.version
        RunAsAccount = $Script.runAsAccount
        EnforceSignatureCheck = $Script.enforceSignatureCheck
        RunAs32Bit = $Script.runAs32Bit
        Id = $Script.id
        CreatedDateTime = $Script.createdDateTime
        LastModifiedDateTime = $Script.lastModifiedDateTime
        RoleScopeTagIds = $Script.roleScopeTagIds -join ', '
    }

    $metadataPath = Join-Path -Path $scriptFolder -ChildPath "metadata.json"
    $metadata | ConvertTo-Json -Depth 10 | Out-File -FilePath $metadataPath -Encoding UTF8

    # Export detection script
    if ($Script.detectionScriptContent) {
        try {
            $detectionContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Script.detectionScriptContent))
            $detectionPath = Join-Path -Path $scriptFolder -ChildPath "detection.ps1"
            $detectionContent | Out-File -FilePath $detectionPath -Encoding UTF8
            Write-Host "    ✓ Detection script saved" -ForegroundColor Green
        }
        catch {
            Write-Warning "    Failed to export detection script: $_"
        }
    }

    # Export remediation script
    if ($Script.remediationScriptContent) {
        try {
            $remediationContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Script.remediationScriptContent))
            $remediationPath = Join-Path -Path $scriptFolder -ChildPath "remediation.ps1"
            $remediationContent | Out-File -FilePath $remediationPath -Encoding UTF8
            Write-Host "    ✓ Remediation script saved" -ForegroundColor Green
        }
        catch {
            Write-Warning "    Failed to export remediation script: $_"
        }
    }
}

# Main execution
try {
    Write-Host "`n=== Intune Remediation Script Exporter ===" -ForegroundColor Cyan
    Write-Host ""

    # Connect to Graph
    Connect-ToGraph

    # Create output directory
    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $resolvedPath = Resolve-Path -Path $OutputPath
    Write-Host "Output directory: $resolvedPath" -ForegroundColor Cyan
    Write-Host ""

    # Get all remediation scripts
    $scripts = Get-RemediationScripts

    if ($scripts.Count -eq 0) {
        Write-Host "No remediation scripts found in Intune" -ForegroundColor Yellow
        return
    }

    Write-Host "`nExporting scripts..." -ForegroundColor Cyan
    Write-Host ""

    # Export each script with progress and build CSV data
    $counter = 0
    $csvData = @()
    $publisherEmailCache = @{}

    foreach ($script in $scripts) {
        $counter++
        $percentComplete = [math]::Round(($counter / $scripts.Count) * 100)

        Write-Progress -Activity "Exporting Remediation Scripts" `
                       -Status "Processing $counter of $($scripts.Count): $($script.displayName)" `
                       -PercentComplete $percentComplete `
                       -CurrentOperation "Fetching script content and assignments..."

        # Get full script content including detection and remediation scripts
        $scriptWithContent = Get-RemediationScriptContent -ScriptId $script.id

        if ($scriptWithContent) {
            Export-ScriptContent -Script $scriptWithContent -BasePath $resolvedPath

            # Get assignments
            $assignments = Get-RemediationScriptAssignments -ScriptId $script.id
            $isDeployed = $assignments.Count -gt 0

            # Check for script-level schedule first (this is the default for all assignments)
            $scriptSchedule = $null
            if ($scriptWithContent.runSchedule) {
                $schedule = $scriptWithContent.runSchedule
                $scheduleInterval = $schedule.interval

                # Build schedule description
                $scriptSchedule = switch ($scheduleInterval) {
                    0 { "Once (no recurrence)" }
                    1 { "Daily (Every 1 hour)" }
                    default { "Every $scheduleInterval hours" }
                }

                # Add time if available
                if ($schedule.time) {
                    $scriptSchedule += " at $($schedule.time)"
                }
            }

            # Build assignment details
            $assignmentDetails = @()
            $scheduleDetails = @()

            foreach ($assignment in $assignments) {
                $targetType = $assignment.target.'@odata.type'

                if ($targetType -eq '#microsoft.graph.allDevicesAssignmentTarget') {
                    $assignmentDetails += "All Devices"
                }
                elseif ($targetType -eq '#microsoft.graph.allLicensedUsersAssignmentTarget') {
                    $assignmentDetails += "All Users"
                }
                elseif ($targetType -eq '#microsoft.graph.groupAssignmentTarget') {
                    $groupId = $assignment.target.groupId
                    $groupName = Get-GroupDisplayName -GroupId $groupId
                    $assignmentDetails += $groupName
                }

                # Check for assignment-level schedule override
                if ($assignment.runSchedule) {
                    $schedule = $assignment.runSchedule
                    $scheduleInterval = $schedule.interval

                    # Build schedule description
                    $scheduleDesc = switch ($scheduleInterval) {
                        0 { "Once (no recurrence)" }
                        1 { "Daily (Every 1 hour)" }
                        default { "Every $scheduleInterval hours" }
                    }

                    # Add time if available
                    if ($schedule.time) {
                        $scheduleDesc += " at $($schedule.time)"
                    }

                    $scheduleDetails += $scheduleDesc
                }
            }

            # Determine final schedule string
            # Priority: assignment-level schedules > script-level schedule > "Not configured"
            if ($scheduleDetails.Count -gt 0) {
                $uniqueSchedules = $scheduleDetails | Select-Object -Unique
                $scheduleString = ($uniqueSchedules -join '; ')
            }
            elseif ($scriptSchedule) {
                $scheduleString = $scriptSchedule
            }
            else {
                $scheduleString = "Not configured"
            }

            # Get publisher email (with caching to avoid duplicate lookups)
            $publisherName = $scriptWithContent.publisher
            $publisherEmail = ""

            if ($publisherName -and -not [string]::IsNullOrWhiteSpace($publisherName)) {
                if ($publisherEmailCache.ContainsKey($publisherName)) {
                    $publisherEmail = $publisherEmailCache[$publisherName]
                    Write-Verbose "Using cached email for $publisherName : $publisherEmail"
                }
                else {
                    Write-Progress -Activity "Exporting Remediation Scripts" `
                                   -Status "Processing $counter of $($scripts.Count): $($script.displayName)" `
                                   -PercentComplete $percentComplete `
                                   -CurrentOperation "Looking up publisher email for: $publisherName"

                    try {
                        $publisherEmail = Get-UserEmail -DisplayName $publisherName
                        $publisherEmailCache[$publisherName] = $publisherEmail

                        if ($publisherEmail) {
                            Write-Host "    ✓ Found email for $publisherName : $publisherEmail" -ForegroundColor Green
                        }
                        else {
                            Write-Warning "    Could not find email for: $publisherName"
                        }
                    }
                    catch {
                        Write-Warning "    Error looking up email for $publisherName : $_"
                        $publisherEmailCache[$publisherName] = ""
                    }
                }
            }

            # Add to CSV data
            $csvData += [PSCustomObject]@{
                'Display Name' = $scriptWithContent.displayName
                'Deployed' = if ($isDeployed) { 'Yes' } else { 'No' }
                'Signature Enforced' = if ($scriptWithContent.enforceSignatureCheck) { 'Yes' } else { 'No' }
                'Run Schedule' = $scheduleString
                'Run As Account' = $scriptWithContent.runAsAccount
                'Run As 32-bit' = if ($scriptWithContent.runAs32Bit) { 'Yes' } else { 'No' }
                'Publisher' = $publisherName
                'Publisher Email' = $publisherEmail
                'Version' = $scriptWithContent.version
                'Assigned To' = ($assignmentDetails -join '; ')
                'Assignment Count' = $assignments.Count
                'Created Date' = $scriptWithContent.createdDateTime
                'Modified Date' = $scriptWithContent.lastModifiedDateTime
                'Script ID' = $scriptWithContent.id
            }
        }
        else {
            Write-Warning "Skipping $($script.displayName) - could not retrieve content"
        }
    }

    Write-Progress -Activity "Exporting Remediation Scripts" -Completed

    # Export CSV summary
    $csvPath = Join-Path -Path $resolvedPath -ChildPath "remediation-scripts-summary.csv"
    $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    # Create publishers contact list CSV
    $publishersPath = Join-Path -Path $resolvedPath -ChildPath "publishers-contact-list.csv"
    $publisherContacts = $csvData |
        Where-Object { $_.'Publisher Email' -ne "" } |
        Select-Object Publisher, 'Publisher Email' -Unique |
        Sort-Object Publisher

    if ($publisherContacts.Count -gt 0) {
        $publisherContacts | Export-Csv -Path $publishersPath -NoTypeInformation -Encoding UTF8
    }

    Write-Host "`n=== Export Complete ===" -ForegroundColor Green
    Write-Host "Total scripts exported: $($scripts.Count)" -ForegroundColor Green
    Write-Host "Location: $resolvedPath" -ForegroundColor Green
    Write-Host ""

    # Display summary statistics
    $deployedCount = ($csvData | Where-Object { $_.Deployed -eq 'Yes' }).Count
    $notDeployedCount = ($csvData | Where-Object { $_.Deployed -eq 'No' }).Count
    $signatureEnforcedCount = ($csvData | Where-Object { $_.'Signature Enforced' -eq 'Yes' }).Count
    $signatureNotEnforcedCount = ($csvData | Where-Object { $_.'Signature Enforced' -eq 'No' }).Count

    Write-Host "Deployment Status:" -ForegroundColor Cyan
    Write-Host "  Deployed: $deployedCount" -ForegroundColor Green
    Write-Host "  Not Deployed: $notDeployedCount" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Signature Enforcement:" -ForegroundColor Cyan
    Write-Host "  Enforced: $signatureEnforcedCount" -ForegroundColor Green
    Write-Host "  Not Enforced: $signatureNotEnforcedCount" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "CSV Files Created:" -ForegroundColor Cyan
    Write-Host "  remediation-scripts-summary.csv - Full script details with publisher emails" -ForegroundColor White

    if ($publisherContacts.Count -gt 0) {
        Write-Host "  publishers-contact-list.csv - Unique publishers and their emails ($($publisherContacts.Count) contacts)" -ForegroundColor White
    }
    else {
        Write-Host "  No publisher emails found - publishers-contact-list.csv not created" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}
finally {
    Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph | Out-Null
}

