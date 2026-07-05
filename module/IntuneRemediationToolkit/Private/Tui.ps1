# ============================================================================
#  TUI HELPERS + ACTION FLOWS
#  Arrow-key driven console menu that surfaces every Export/Publish option and
#  invokes the module functions directly. No Intune logic is duplicated here.
# ============================================================================

# Draw the toolkit banner at the top of a cleared screen
function Show-Header {
    param([string]$Subtitle)
    Clear-Host
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "            Intune Remediation Toolkit" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host "  $Subtitle" -ForegroundColor DarkCyan
        Write-Host ""
    }
}

# Arrow-key menu. Returns the zero-based index of the chosen option, or -1 if
# the user pressed Esc. Number keys (1-9) act as quick-select shortcuts.
function Show-Menu {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options,
        [string[]]$Hints
    )

    $selected = 0
    $previousCursor = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    try {
        while ($true) {
            Show-Header -Subtitle $Title

            for ($i = 0; $i -lt $Options.Count; $i++) {
                $prefix = if ($i -eq $selected) { "  > " } else { "    " }
                $number = "$($i + 1). "
                $line   = "$prefix$number$($Options[$i])"

                if ($i -eq $selected) {
                    Write-Host $line -ForegroundColor Black -BackgroundColor Cyan
                }
                else {
                    Write-Host $line -ForegroundColor White
                }

                if ($Hints -and $Hints[$i]) {
                    Write-Host "        $($Hints[$i])" -ForegroundColor DarkGray
                }
            }

            Write-Host ""
            Write-Host "  Up/Down = move   Enter = select   Esc = back" -ForegroundColor DarkGray

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $selected = ($selected - 1 + $Options.Count) % $Options.Count }
                'DownArrow' { $selected = ($selected + 1) % $Options.Count }
                'Enter'     { return $selected }
                'Escape'    { return -1 }
                default {
                    # Number-key quick select (1..9)
                    if ($key.KeyChar -match '[1-9]') {
                        $idx = [int]::Parse($key.KeyChar) - 1
                        if ($idx -lt $Options.Count) { return $idx }
                    }
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $previousCursor
    }
}

# Free-text prompt with an optional default value shown in brackets
function Read-Value {
    param([string]$Prompt, [string]$Default)

    $suffix = if ($Default) { " [$Default]" } else { "" }
    $value = Read-Host "  $Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

# Pause so the user can read output before returning to the menu
function Wait-ForKey {
    Write-Host ""
    Write-Host "  Press any key to return to the menu..." -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

# ============================================================================
#  ACTION FLOWS
# ============================================================================

# Ask how the user wants to choose the source folder, returns a param hashtable
function Get-SourceSelection {
    $choice = Show-Menu -Title "Choose the source of the remediation folder(s)" -Options @(
        "Browse for a folder (graphical picker)",
        "Use all folders in the toolkit directory",
        "Enter a specific folder name"
    ) -Hints @(
        "Pick a single remediation folder, or a parent of many",
        "Path: $Path",
        "Matches a subfolder name under the toolkit directory"
    )

    switch ($choice) {
        0       { return @{ BrowseFolder = $true } }
        1       { return @{ Path = $Path } }
        2       {
            $name = Read-Value -Prompt "Folder name"
            if ([string]::IsNullOrWhiteSpace($name)) { return $null }
            return @{ Path = $Path; FolderName = $name }
        }
        default { return $null }   # Esc
    }
}

# Optional approval justification, returns a param hashtable fragment
function Get-Justification {
    $choice = Show-Menu -Title "Approval justification (used if approval is required)" -Options @(
        "Updating for Signature Enforcement",
        "Security compliance update",
        "Bug fix deployment",
        "Enter a custom justification",
        "Let the script prompt me"
    )

    switch ($choice) {
        0       { return @{ ApprovalJustification = "Updating for Signature Enforcement" } }
        1       { return @{ ApprovalJustification = "Security compliance update" } }
        2       { return @{ ApprovalJustification = "Bug fix deployment" } }
        3       {
            $text = Read-Value -Prompt "Custom justification"
            if ($text) { return @{ ApprovalJustification = $text } } else { return @{} }
        }
        default { return @{} }   # option 5 or Esc -> let the push script ask
    }
}

# Build and run a Push action for the given base params (Create/Update/WhatIf)
function Invoke-PushAction {
    param([hashtable]$ActionParams, [string]$ActionLabel, [switch]$SkipJustification)

    $source = Get-SourceSelection
    if ($null -eq $source) { return }   # cancelled

    $params = $ActionParams + $source
    if (-not $SkipJustification) {
        $params += Get-Justification
    }

    Show-Header -Subtitle "$ActionLabel"
    Write-Host "  Launching Push-RemdiationsToIntune.ps1 with:" -ForegroundColor Cyan
    ($params.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $val = if ($_.Value -is [switch] -or $_.Value -is [bool]) { "(on)" } else { $_.Value }
        "    -$($_.Key) $val"
    }) | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    Write-Host ""

    Publish-IntuneRemediation @params
    Wait-ForKey
}

# Push submenu - one entry per push option
function Invoke-PushMenu {
    while ($true) {
        $choice = Show-Menu -Title "Push remediations to Intune - choose an action" -Options @(
            "Create new remediation(s)",
            "Update existing remediation(s)",
            "Preview only (WhatIf - nothing is uploaded)",
            "Back to main menu"
        ) -Hints @(
            "-Create : always creates new objects",
            "-UpdateExisting : PATCH by the Id in metadata.json",
            "-WhatIf : shows what would be uploaded",
            ""
        )

        switch ($choice) {
            0       { Invoke-PushAction -ActionParams @{ Create = $true; Interactive = $true }        -ActionLabel "Create new remediation(s)" }
            1       { Invoke-PushAction -ActionParams @{ UpdateExisting = $true; Interactive = $true } -ActionLabel "Update existing remediation(s)" }
            2       { Invoke-PushAction -ActionParams @{ WhatIf = $true }                              -ActionLabel "Preview (WhatIf)" -SkipJustification }
            default { return }   # Back / Esc
        }
    }
}

# Export flow - one entry per export option
function Invoke-ExportMenu {
    $choice = Show-Menu -Title "Export remediations from Intune - choose destination" -Options @(
        "Export to the default folder (.\RemediationScripts)",
        "Export to a custom folder"
    ) -Hints @(
        "Under: $Path",
        "You'll be asked for a path"
    )

    $params = @{}
    switch ($choice) {
        0       { $params = @{ OutputPath = (Join-Path $Path 'RemediationScripts') } }
        1       {
            $out = Read-Value -Prompt "Output path" -Default (Join-Path $Path 'RemediationScripts')
            $params = @{ OutputPath = $out }
        }
        default { return }   # Esc
    }

    Show-Header -Subtitle "Export remediations from Intune"
    Write-Host "  Launching Export-IntuneRemediations.ps1 with:" -ForegroundColor Cyan
    Write-Host "    -OutputPath $($params.OutputPath)" -ForegroundColor Gray
    Write-Host ""

    Export-IntuneRemediation @params
    Wait-ForKey
}
