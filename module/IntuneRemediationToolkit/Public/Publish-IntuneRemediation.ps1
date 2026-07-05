<#
.SYNOPSIS
    Pushes remediation scripts to Intune as Device Health Scripts

.DESCRIPTION
    Scans the current directory for remediation script folders (containing detection.ps1,
    optional remediation.ps1, and metadata.json), then uploads them to Intune via Microsoft Graph API.

    Can create new remediation scripts or update existing ones based on the Id in metadata.json.

.PARAMETER Path
    Root path containing remediation script folders. Defaults to current directory.

.PARAMETER BrowseFolder
    Opens a graphical folder-picker dialog to choose the folder to import. You can pick a
    parent folder containing multiple remediation folders, or a single remediation folder
    (one that contains detection.ps1 and metadata.json).

.PARAMETER FolderName
    Specific folder name to push. If not specified, processes all folders.

.PARAMETER Create
    Explicitly create new remediation scripts. This is the default action when
    -UpdateExisting is not used. When a folder's metadata.json already contains an Id,
    -Create still creates a brand-new (duplicate) remediation in Intune and writes the
    new Id back to metadata.json - useful for cloning an existing remediation.

.PARAMETER UpdateExisting
    If specified, updates existing remediation scripts (matched by the Id in
    metadata.json). Otherwise, creates new ones. Takes precedence over -Create.

.PARAMETER ApprovalJustification
    Justification text for the approval request. If not provided, you'll be prompted with common options.

.PARAMETER WhatIf
    Shows what would be uploaded without actually pushing to Intune.

.PARAMETER Interactive
    Prompts for settings before pushing.
    - With -UpdateExisting: fetches the CURRENT live settings from Intune, displays them,
      and lets you keep them as-is or modify each one before the update is applied.
    - With -Create: prompts for all settings (name, description, publisher, run-as account,
      32-bit, signature check, scope tags) plus an optional assignment (All devices / All
      users / a group) and run schedule (Daily / Hourly / Once), then assigns on create.

.PARAMETER Menu
    Opens the interactive text-based menu (TUI) for choosing the action and options,
    instead of running with switches.

.EXAMPLE
    Publish-IntuneRemediation

.EXAMPLE
    Publish-IntuneRemediation -Menu

.EXAMPLE
    Publish-IntuneRemediation -BrowseFolder

.EXAMPLE
    Publish-IntuneRemediation -Create

.EXAMPLE
    Publish-IntuneRemediation -BrowseFolder -Create

.EXAMPLE
    Publish-IntuneRemediation -BrowseFolder -UpdateExisting

.EXAMPLE
    Publish-IntuneRemediation -UpdateExisting -WhatIf

.EXAMPLE
    Publish-IntuneRemediation -FolderName "DEV_-_GP_-_CC" -UpdateExisting

.EXAMPLE
    Publish-IntuneRemediation -FolderName "DEV_-_GP_-_CC" -UpdateExisting -ApprovalJustification "Testing CIS registry compliance updates"

.NOTES
    Author: Mark Orr
#>
function Publish-IntuneRemediation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [switch]$BrowseFolder,

        [Parameter()]
        [string]$FolderName,

        [Parameter()]
        [string[]]$FolderNames,

        [Parameter()]
        [switch]$Create,

        [Parameter()]
        [switch]$UpdateExisting,

        [Parameter()]
        [string]$ApprovalJustification,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [switch]$Menu
    )

    # ========================================================================
    #  MAIN EXECUTION
    # ========================================================================

    # --- Interactive menu: hand off to the TUI launcher and exit when -Menu is used ---
    if ($Menu) {
        Start-RemediationToolkit -StartAt Push -Path $Path
        return
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Push Remediation Scripts to Intune" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # --- Step 0: Validate switch combination ---
    # -Create and -UpdateExisting are opposing intents. If both are set, -UpdateExisting
    # wins for any folder that already has an Id (matches the create/update logic below).
    if ($Create -and $UpdateExisting) {
        Write-Warning "Both -Create and -UpdateExisting were specified. -UpdateExisting takes precedence for folders whose metadata.json already has an Id; folders without an Id are created."
    }

    # --- Step 1: Resolve the source path (optional graphical folder picker) ---
    # Prompt for a folder via the graphical picker if requested
    if ($BrowseFolder) {
        $selectedPath = Show-FolderPicker -InitialPath $Path
        if (-not $selectedPath) {
            Write-Warning "No folder selected. Exiting."
            return
        }
        $Path = $selectedPath
        Write-Host "Selected folder: $Path" -ForegroundColor Green
    }

    # --- Step 2: Connect to Graph (skipped in -WhatIf mode) ---
    # Connect to Graph
    if (-not $WhatIfPreference) {
        Connect-ToGraph -Scopes @(
            'DeviceManagementConfiguration.ReadWrite.All'
        )
    }

    # --- Step 3: Discover the remediation folders to process ---
    # Get all remediation folders
    $remediationFolders = Get-RemediationFolders -RootPath $Path -SpecificFolder $FolderName -SpecificFolders $FolderNames

    if ($remediationFolders.Count -eq 0) {
        Write-Warning "No remediation script folders found."
        return
    }

    # --- Step 4: Process each folder (read files -> justify -> create/update) ---
    # Process each folder
    $successCount = 0
    $failCount = 0
    $skippedCount = 0

    foreach ($folder in $remediationFolders) {
        Write-Host "`n----------------------------------------" -ForegroundColor Yellow
        Write-Host "Processing: $($folder.Name)" -ForegroundColor Yellow
        Write-Host "----------------------------------------" -ForegroundColor Yellow

        # Read metadata
        $metadataPath = Join-Path $folder.FullName "metadata.json"
        $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json

        # Read detection script
        $detectionPath = Join-Path $folder.FullName "detection.ps1"
        $detectionContent = Get-Content $detectionPath -Raw

        # Read remediation script (if exists)
        $remediationPath = Join-Path $folder.FullName "remediation.ps1"
        $remediationContent = $null
        if (Test-Path $remediationPath) {
            $remediationContent = Get-Content $remediationPath -Raw
            Write-Host "  ✓ Detection and Remediation scripts found" -ForegroundColor Green
        }
        else {
            Write-Host "  ✓ Detection script found (no remediation)" -ForegroundColor Green
        }

        # Display metadata
        Write-Host "  Display Name: $($metadata.DisplayName)" -ForegroundColor White
        Write-Host "  Description: $($metadata.Description)" -ForegroundColor Gray
        Write-Host "  Publisher: $($metadata.Publisher)" -ForegroundColor Gray
        Write-Host "  Run As: $($metadata.RunAsAccount)" -ForegroundColor Gray
        Write-Host "  Run As 32-bit: $($metadata.RunAs32Bit)" -ForegroundColor Gray

        if ($WhatIfPreference) {
            Write-Host "  [WHATIF] Would upload to Intune" -ForegroundColor Magenta
            $skippedCount++
            continue
        }

        # --- Approval justification: prompt once, then reuse for the whole batch ---
        # Determine justification (only prompt once for batch processing)
        if (-not $script:batchJustification) {
            $justification = $ApprovalJustification

            if (-not $justification) {
                Write-Host "`n  Common justifications:" -ForegroundColor Cyan
                Write-Host "  1. Updating for Signature Enforcement" -ForegroundColor Gray
                Write-Host "  2. Security compliance update" -ForegroundColor Gray
                Write-Host "  3. Bug fix deployment" -ForegroundColor Gray
                Write-Host "  4. Custom (enter your own)" -ForegroundColor Gray
                Write-Host ""

                $choice = Read-Host "  Select option (1-4) or press Enter for default"

                switch ($choice) {
                    "1" { $justification = "Updating for Signature Enforcement" }
                    "2" { $justification = "Security compliance update" }
                    "3" { $justification = "Bug fix deployment" }
                    "4" {
                        $justification = Read-Host "  Enter custom justification"
                        if ([string]::IsNullOrWhiteSpace($justification)) {
                            if ($UpdateExisting) {
                                $justification = "Automated remediation script update via Push-RemediationsToIntune.ps1"
                            } else {
                                $justification = "Automated remediation script deployment via Push-RemediationsToIntune.ps1"
                            }
                        }
                    }
                    default {
                        if ($UpdateExisting) {
                            $justification = "Automated remediation script update via Push-RemediationsToIntune.ps1"
                        } else {
                            $justification = "Automated remediation script deployment via Push-RemediationsToIntune.ps1"
                        }
                    }
                }
            }

            # Store for batch processing
            $script:batchJustification = $justification
        }
        else {
            $justification = $script:batchJustification
        }

        Write-Host "  Justification: $justification" -ForegroundColor Gray

        # --- Push to Intune: -UpdateExisting (with Id) patches; -Create always makes a new one; default creates ---
        # Create or update
        if ($UpdateExisting -and $metadata.Id) {

            # Interactive update: show the current LIVE settings from Intune, then let the
            # user keep them as-is or modify each one before the script content is patched.
            if ($Interactive) {
                $live = Get-LiveRemediationScript -Id $metadata.Id
                if ($live) {
                    Show-RemediationSettings -Live $live

                    # Start from the live values so "keep" truly preserves what's in Intune
                    $metadata.DisplayName           = $live.displayName
                    $metadata.Description            = $live.description
                    $metadata.Publisher             = $live.publisher
                    $metadata.RunAsAccount          = $live.runAsAccount
                    $metadata.RunAs32Bit            = [bool]$live.runAs32Bit
                    $metadata.EnforceSignatureCheck = [bool]$live.enforceSignatureCheck
                    $metadata.RoleScopeTagIds       = ($live.roleScopeTagIds -join ', ')

                    $modify = Read-BoolSetting -Label "Modify these settings before updating?" -Current $false
                    if ($modify) {
                        Write-Host "`n  Enter new values (press Enter to keep the current value):" -ForegroundColor Cyan
                        $metadata.DisplayName           = Read-TextSetting   -Label 'Display Name'      -Current $metadata.DisplayName
                        $metadata.Description            = Read-TextSetting   -Label 'Description'       -Current $metadata.Description
                        $metadata.Publisher             = Read-TextSetting   -Label 'Publisher'         -Current $metadata.Publisher
                        $metadata.RunAsAccount          = Read-ChoiceSetting -Label 'Run As Account'    -Current $metadata.RunAsAccount -Choices @('system','user')
                        $metadata.RunAs32Bit            = Read-BoolSetting   -Label 'Run As 32-bit'     -Current ([bool]$metadata.RunAs32Bit)
                        $metadata.EnforceSignatureCheck = Read-BoolSetting   -Label 'Enforce Signature' -Current ([bool]$metadata.EnforceSignatureCheck)
                        $metadata.RoleScopeTagIds       = Read-TextSetting   -Label 'Scope Tag Ids'     -Current $metadata.RoleScopeTagIds
                    }
                    else {
                        Write-Host "  Keeping current settings; only the detection/remediation script content will be updated." -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "  Falling back to local metadata.json settings (could not read live settings)." -ForegroundColor Yellow
                }
            }

            Write-Host "  Updating existing remediation (ID: $($metadata.Id))..." -ForegroundColor Cyan
            $result = Update-IntuneRemediationScript -Id $metadata.Id -Metadata $metadata -DetectionScriptContent $detectionContent -RemediationScriptContent $remediationContent -Justification $justification -ErrorAction SilentlyContinue
        }
        else {
            # Creating a new remediation. Warn if this folder already maps to an Intune object,
            # since creating will produce a duplicate rather than updating the existing one.
            if ($metadata.Id) {
                if ($Create) {
                    Write-Host "  -Create specified: creating a NEW remediation even though metadata.json already has an Id ($($metadata.Id)). A duplicate will be created in Intune." -ForegroundColor Yellow
                }
                else {
                    Write-Host "  Note: metadata.json already has an Id ($($metadata.Id)); creating a duplicate. Use -UpdateExisting to update it instead." -ForegroundColor Yellow
                }
            }

            # Interactive create: prompt for settings + assignment/schedule (defaults from metadata.json)
            if ($Interactive) {
                Read-CreateSettings -Metadata $metadata -FolderName $folder.Name
            }

            Write-Host "  Creating new remediation script..." -ForegroundColor Cyan
            $result = New-IntuneRemediationScript -Metadata $metadata -DetectionScriptContent $detectionContent -RemediationScriptContent $remediationContent -Justification $justification -ErrorAction SilentlyContinue
        }

        # --- Interpret the API result: approval-pending / error / success, and tally counts ---
        if ($result) {
            # Check if approval is required
            if ($result.approvalRequired) {
                Write-Host "  ⚠ APPROVAL REQUIRED" -ForegroundColor Yellow
                Write-Host "  Approval Code: $($result.approvalCode)" -ForegroundColor Yellow
                Write-Host "  Go to Intune Portal > Endpoint Security > Remediations > Approvals to approve this change" -ForegroundColor Cyan
                $successCount++
            }
            elseif ($result.error) {
                Write-Host "  ✗ FAILED" -ForegroundColor Red
                Write-Host "  Error: $($result.message)" -ForegroundColor Red
                $failCount++
            }
            else {
                Write-Host "  ✓ SUCCESS" -ForegroundColor Green
                if ($result.id -and -not $UpdateExisting) {
                    Write-Host "  New ID: $($result.id)" -ForegroundColor Green

                    # Update metadata.json with new ID (Depth 10 so any Assignment block persists)
                    $metadata.Id = $result.id
                    $metadata.LastModifiedDateTime = Get-Date -Format "o"
                    $metadata | ConvertTo-Json -Depth 10 | Set-Content $metadataPath
                    Write-Host "  Updated metadata.json with new ID" -ForegroundColor Green

                    # Create the assignment if one was configured (interactive create or metadata.json)
                    if ($metadata.Assignment -and $metadata.Assignment.Target) {
                        $tgt = switch ($metadata.Assignment.Target) {
                            'Group' { "group '$($metadata.Assignment.GroupName)' ($($metadata.Assignment.GroupId))" }
                            default { $metadata.Assignment.Target }
                        }
                        Write-Host "  Creating assignment: $tgt ..." -ForegroundColor Cyan
                        $assignResult = Set-IntuneRemediationAssignment -Id $result.id -Assignment $metadata.Assignment
                        if ($assignResult.success) {
                            Write-Host "  ✓ Assignment created" -ForegroundColor Green
                        }
                        else {
                            Write-Host "  ⚠ Assignment failed: $($assignResult.message)" -ForegroundColor Yellow
                            Write-Host "    (The script was created; you can assign it manually in Intune.)" -ForegroundColor Gray
                        }
                    }
                }
                $successCount++
            }
        }
        else {
            Write-Host "  ✗ FAILED - No response from API" -ForegroundColor Red
            $failCount++
        }
    }

    # --- Step 5: Report results and disconnect ---
    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Total: $($remediationFolders.Count)" -ForegroundColor White
    Write-Host "  Uploaded/Pending Approval: $successCount" -ForegroundColor Green
    Write-Host "  Failed: $failCount" -ForegroundColor Red

    # Disconnect (only if we actually have an active session)
    if (-not $WhatIfPreference -and (Get-MgContext)) {
        Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
        Disconnect-MgGraph | Out-Null
    }

    Write-Host "`nDone!" -ForegroundColor Green
}
