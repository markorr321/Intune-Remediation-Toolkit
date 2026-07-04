<#
.SYNOPSIS
    Pushes remediation scripts to Intune as Device Health Scripts

.DESCRIPTION
    Scans the current directory for remediation script folders (containing detection.ps1,
    optional remediation.ps1, and metadata.json), then uploads them to Intune via Microsoft Graph API.

    Can create new remediation scripts or update existing ones based on the Id in metadata.json.

.PARAMETER Path
    Root path containing remediation script folders. Defaults to current directory.

.PARAMETER FolderName
    Specific folder name to push. If not specified, processes all folders.

.PARAMETER UpdateExisting
    If specified, updates existing remediation scripts. Otherwise, creates new ones.

.PARAMETER ApprovalJustification
    Justification text for the approval request. If not provided, you'll be prompted with common options.

.PARAMETER WhatIf
    Shows what would be uploaded without actually pushing to Intune.

.EXAMPLE
    .\Push-RemediationsToIntune.ps1

.EXAMPLE
    .\Push-RemediationsToIntune.ps1 -UpdateExisting -WhatIf

.EXAMPLE
    .\Push-RemediationsToIntune.ps1 -FolderName "DEV_-_GP_-_CC" -UpdateExisting

.EXAMPLE
    .\Push-RemediationsToIntune.ps1 -FolderName "DEV_-_GP_-_CC" -UpdateExisting -ApprovalJustification "Testing CIS registry compliance updates"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$Path = $PSScriptRoot,

    [Parameter()]
    [string]$FolderName,

    [Parameter()]
    [string[]]$FolderNames,

    [Parameter()]
    [switch]$UpdateExisting,

    [Parameter()]
    [string]$ApprovalJustification
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

# Connect to Microsoft Graph
function Connect-ToGraph {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

    $requiredScopes = @(
        'DeviceManagementConfiguration.ReadWrite.All'
    )

    try {
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome
        $context = Get-MgContext
        Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        exit 1
    }
}

# Convert script content to base64
function ConvertTo-Base64 {
    param([string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    return [Convert]::ToBase64String($bytes)
}

# Scan for remediation script folders
function Get-RemediationFolders {
    param(
        [string]$RootPath,
        [string]$SpecificFolder,
        [string[]]$SpecificFolders
    )

    Write-Host "`nScanning for remediation scripts in: $RootPath" -ForegroundColor Cyan

    if ($SpecificFolders -and $SpecificFolders.Count -gt 0) {
        Write-Host "Filtering for $($SpecificFolders.Count) specific folders" -ForegroundColor Yellow
        $folders = Get-ChildItem -Path $RootPath -Directory | Where-Object {
            $detectionScript = Join-Path $_.FullName "detection.ps1"
            $metadataFile = Join-Path $_.FullName "metadata.json"

            ($SpecificFolders -contains $_.Name) -and (Test-Path $detectionScript) -and (Test-Path $metadataFile)
        }
    }
    elseif ($SpecificFolder) {
        Write-Host "Filtering for folder: $SpecificFolder" -ForegroundColor Yellow
        $folders = Get-ChildItem -Path $RootPath -Directory | Where-Object {
            $detectionScript = Join-Path $_.FullName "detection.ps1"
            $metadataFile = Join-Path $_.FullName "metadata.json"

            $_.Name -eq $SpecificFolder -and (Test-Path $detectionScript) -and (Test-Path $metadataFile)
        }
    }
    else {
        $folders = Get-ChildItem -Path $RootPath -Directory | Where-Object {
            $detectionScript = Join-Path $_.FullName "detection.ps1"
            $metadataFile = Join-Path $_.FullName "metadata.json"

            (Test-Path $detectionScript) -and (Test-Path $metadataFile)
        }
    }

    Write-Host "Found $($folders.Count) remediation script folders" -ForegroundColor Green
    return $folders
}

# Create remediation script in Intune
function New-IntuneRemediationScript {
    param(
        [PSCustomObject]$Metadata,
        [string]$DetectionScriptContent,
        [string]$RemediationScriptContent,
        [string]$Justification = "Automated remediation script deployment via Push-RemediationsToIntune.ps1"
    )

    $body = @{
        '@odata.type' = '#microsoft.graph.deviceHealthScript'
        displayName = $Metadata.DisplayName
        description = $Metadata.Description
        publisher = $Metadata.Publisher
        runAsAccount = $Metadata.RunAsAccount
        enforceSignatureCheck = $Metadata.EnforceSignatureCheck
        runAs32Bit = $Metadata.RunAs32Bit
        roleScopeTagIds = @($Metadata.RoleScopeTagIds -split ',\s*' | ForEach-Object { $_.Trim() })
        detectionScriptContent = ConvertTo-Base64 -Content $DetectionScriptContent
    }

    if ($RemediationScriptContent) {
        $body.remediationScriptContent = ConvertTo-Base64 -Content $RemediationScriptContent
    }

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

    $body = @{
        '@odata.type' = '#microsoft.graph.deviceHealthScript'
        displayName = $Metadata.DisplayName
        description = $Metadata.Description
        publisher = $Metadata.Publisher
        runAsAccount = $Metadata.RunAsAccount
        enforceSignatureCheck = $Metadata.EnforceSignatureCheck
        runAs32Bit = $Metadata.RunAs32Bit
        detectionScriptContent = ConvertTo-Base64 -Content $DetectionScriptContent
    }

    if ($RemediationScriptContent) {
        $body.remediationScriptContent = ConvertTo-Base64 -Content $RemediationScriptContent
    }

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

# Main execution
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Push Remediation Scripts to Intune" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Connect to Graph
if (-not $WhatIfPreference) {
    Connect-ToGraph
}

# Get all remediation folders
$remediationFolders = Get-RemediationFolders -RootPath $Path -SpecificFolder $FolderName -SpecificFolders $FolderNames

if ($remediationFolders.Count -eq 0) {
    Write-Warning "No remediation script folders found."
    exit 0
}

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

    # Create or update
    if ($UpdateExisting -and $metadata.Id) {
        Write-Host "  Updating existing remediation (ID: $($metadata.Id))..." -ForegroundColor Cyan
        $result = Update-IntuneRemediationScript -Id $metadata.Id -Metadata $metadata -DetectionScriptContent $detectionContent -RemediationScriptContent $remediationContent -Justification $justification -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "  Creating new remediation script..." -ForegroundColor Cyan
        $result = New-IntuneRemediationScript -Metadata $metadata -DetectionScriptContent $detectionContent -RemediationScriptContent $remediationContent -Justification $justification -ErrorAction SilentlyContinue
    }

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

                # Update metadata.json with new ID
                $metadata.Id = $result.id
                $metadata.LastModifiedDateTime = Get-Date -Format "o"
                $metadata | ConvertTo-Json | Set-Content $metadataPath
                Write-Host "  Updated metadata.json with new ID" -ForegroundColor Green
            }
            $successCount++
        }
    }
    else {
        Write-Host "  ✗ FAILED - No response from API" -ForegroundColor Red
        $failCount++
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Total: $($remediationFolders.Count)" -ForegroundColor White
Write-Host "  Uploaded/Pending Approval: $successCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor Red

# Disconnect
if (-not $WhatIfPreference) {
    Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph | Out-Null
}

Write-Host "`nDone!" -ForegroundColor Green
