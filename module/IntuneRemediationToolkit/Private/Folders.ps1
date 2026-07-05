# ============================================================================
#  FOLDER DISCOVERY + GRAPHICAL FOLDER PICKER
#  Used by Publish-IntuneRemediation to locate remediation script folders.
# ============================================================================

# Scan for remediation script folders
function Get-RemediationFolders {
    param(
        [string]$RootPath,
        [string]$SpecificFolder,
        [string[]]$SpecificFolders
    )

    Write-Host "`nScanning for remediation scripts in: $RootPath" -ForegroundColor Cyan

    # If the selected folder is itself a remediation folder, import just that one
    if ((Test-Path (Join-Path $RootPath "detection.ps1")) -and (Test-Path (Join-Path $RootPath "metadata.json"))) {
        Write-Host "Selected folder is a single remediation script" -ForegroundColor Yellow
        $single = Get-Item -Path $RootPath
        Write-Host "Found 1 remediation script folder" -ForegroundColor Green
        return @($single)
    }

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

# Show a graphical folder-picker dialog and return the selected path (or $null if cancelled)
function Show-FolderPicker {
    param(
        [string]$InitialPath,
        [string]$Description = "Select the folder to import remediation scripts from"
    )

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $false
    if ($InitialPath -and (Test-Path $InitialPath)) {
        $dialog.SelectedPath = $InitialPath
    }

    # Ensure the dialog appears in the foreground
    $topmost = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
    $result = $dialog.ShowDialog($topmost)
    $topmost.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }

    return $null
}
