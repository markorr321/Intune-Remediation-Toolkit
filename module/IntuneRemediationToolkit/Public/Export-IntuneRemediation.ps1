<#
.SYNOPSIS
    Exports all Intune remediation scripts (proactive remediations) to a local folder.

.DESCRIPTION
    Connects to Microsoft Graph, retrieves all device health scripts (remediation scripts),
    downloads their detection and remediation script content, and saves them to an organized folder structure.

.PARAMETER OutputPath
    The folder path where scripts will be exported. Defaults to .\RemediationScripts

.EXAMPLE
    Export-IntuneRemediation

.EXAMPLE
    Export-IntuneRemediation -OutputPath "C:\Backup\Remediations"

.NOTES
    Author: Mark Orr
#>
function Export-IntuneRemediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = ".\RemediationScripts"
    )

    $ErrorActionPreference = "Stop"

    # ========================================================================
    #  MAIN EXECUTION
    # ========================================================================
    try {
        Write-Host "`n=== Intune Remediation Script Exporter ===" -ForegroundColor Cyan
        Write-Host ""

        # --- Step 1: Connect to Graph ---
        Connect-ToGraph -Scopes @(
            "DeviceManagementConfiguration.Read.All",
            "Group.Read.All",
            "User.Read.All"
        )

        # --- Step 2: Prepare the output directory ---
        # Create output directory
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $resolvedPath = Resolve-Path -Path $OutputPath
        Write-Host "Output directory: $resolvedPath" -ForegroundColor Cyan
        Write-Host ""

        # --- Step 3: Retrieve the list of remediation scripts ---
        # Get all remediation scripts
        $scripts = Get-RemediationScripts

        if ($scripts.Count -eq 0) {
            Write-Host "No remediation scripts found in Intune" -ForegroundColor Yellow
            return
        }

        Write-Host "`nExporting scripts..." -ForegroundColor Cyan
        Write-Host ""

        # --- Step 4: Export each script to disk and build the CSV summary rows ---
        # Export each script with progress and build CSV data
        $counter = 0
        $csvData = @()
        $publisherEmailCache = @{}   # display name -> email, to avoid repeat Graph lookups

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
                # Write the script files (metadata + detection/remediation) to disk
                Export-ScriptContent -Script $scriptWithContent -BasePath $resolvedPath

                # Get assignments
                $assignments = Get-RemediationScriptAssignments -ScriptId $script.id
                $isDeployed = $assignments.Count -gt 0

                # Resolve the run schedule: check the script-level schedule first (this is the default for all assignments)
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

                # Build assignment target names and collect any per-assignment schedule overrides
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

                # Resolve the publisher's email (cached per publisher to avoid duplicate lookups)
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

                # Add one summary row for this script to the CSV dataset
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

        # --- Step 5: Write the summary and publisher-contact CSV files ---
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

        # --- Step 6: Print run statistics (deployment + signature enforcement) ---
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
        # Any terminating error (ErrorActionPreference = Stop) lands here.
        # Write-Error (not exit) so only this command fails, never the whole session.
        Write-Error "Export failed: $_"
    }
    finally {
        # Always disconnect from Graph if we have a session (guard avoids an error
        # when the connection itself failed).
        if (Get-MgContext) {
            Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
            Disconnect-MgGraph | Out-Null
        }
    }
}
