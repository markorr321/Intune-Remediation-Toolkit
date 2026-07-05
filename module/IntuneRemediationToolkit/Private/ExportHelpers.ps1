# ============================================================================
#  EXPORT HELPERS
#  Read-only Graph lookups (scripts, content, assignments, group names,
#  publisher emails) plus the per-script disk writer used by Export-IntuneRemediation.
# ============================================================================

# Retrieve the full list of remediation scripts, following @odata.nextLink paging
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

# Fetch a single script by Id, including the base64 detection/remediation content
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

# Fetch the assignment targets (groups / all devices / all users) for a script
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

# Resolve an Entra group Id to its display name (falls back to the Id on failure)
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

# Look up a user's email from their display name (exact match first, then
# startswith); prefers 'mail' over userPrincipalName. Returns "" if not found.
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

# Write one script to disk: a sanitized per-script folder containing
# metadata.json plus decoded detection.ps1 and remediation.ps1 files
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
