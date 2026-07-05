# ============================================================================
#  GRAPH CONNECTION HELPER
#  Merged from the two source scripts. Takes the required scopes as a parameter
#  so callers can request read-only (export) or read/write (push) access.
#  Keeps the robust validation: -ErrorAction Stop plus an empty-account check
#  that aborts when an interactive sign-in is cancelled.
# ============================================================================

# Connect to Microsoft Graph
function Connect-ToGraph {
    param(
        [Parameter(Mandatory)]
        [string[]]$Scopes
    )

    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

    try {
        # -ErrorAction Stop so a cancelled/failed sign-in throws into the catch below
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop

        # Even when Connect-MgGraph doesn't throw, verify we actually have an account.
        # (A cancelled interactive sign-in can leave an empty context.)
        $context = Get-MgContext
        if (-not $context -or [string]::IsNullOrWhiteSpace($context.Account)) {
            # throw (not exit) so only the calling command stops, never the whole session
            throw "Microsoft Graph sign-in did not complete (no active account). Aborting."
        }

        Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
    }
    catch {
        throw "Failed to connect to Microsoft Graph: $_"
    }
}
