# Intune Remediation Toolkit

A PowerShell **module** (`IntuneRemediationToolkit`) for backing up and deploying **Intune remediation scripts**
(a.k.a. *proactive remediations* / *device health scripts*) via the Microsoft Graph API.

It gives you a round-trip workflow: **export → edit / version in Git → publish**.

| Command | Alias | What it does |
|---------|-------|--------------|
| `Export-IntuneRemediation` | | Download every remediation from Intune to disk + CSV reports |
| `Publish-IntuneRemediation` | `Push-IntuneRemediation` | Create / update remediations in Intune from local folders |
| `Start-RemediationToolkit` | | Interactive arrow-key menu (TUI) that drives the above |
| `Show-RemediationToolkitHelp` | | Comprehensive, colorized help reference |

> **Author:** Mark Orr

The original standalone scripts (`Export-IntuneRemediations.ps1`,
`Push-RemdiationsToIntune.ps1`, `Start-RemediationToolkit.ps1`) still live at the repo
root and work the same way, but the **module is the recommended way to use the toolkit**.

---

## Install

Copy the module folder into a location on your `$env:PSModulePath` (the per-user modules
folder autoloads by name):

```powershell
# From the repo root
$dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
Copy-Item .\module\IntuneRemediationToolkit -Destination $dest -Recurse -Force

Import-Module IntuneRemediationToolkit
Get-Command -Module IntuneRemediationToolkit
```

Or import it directly from the repo without installing:

```powershell
Import-Module .\module\IntuneRemediationToolkit\IntuneRemediationToolkit.psd1
```

---

## Prerequisites

- **PowerShell 7+** (Windows). The folder-picker and the TUI use Windows-only APIs.
- **Microsoft Graph PowerShell SDK modules** (declared as `RequiredModules` in the manifest):
  ```powershell
  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
  Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
  ```
- A Microsoft Entra account with the delegated Graph permissions listed below, and rights
  in Intune to manage remediations (e.g. the **Intune Administrator** role, or a custom
  role with the equivalent Device Health Script permissions).

---

## Required Permissions

Both commands authenticate with **delegated** Microsoft Graph permissions via
`Connect-MgGraph`. You're prompted to consent on first connect (or an admin can pre-consent).

### `Export-IntuneRemediation` (read-only)

| Graph scope | Why it's needed |
|-------------|-----------------|
| `DeviceManagementConfiguration.Read.All` | Read remediation scripts, their content, and assignments |
| `Group.Read.All` | Resolve assignment target **group IDs** to display names |
| `User.Read.All` | Look up **publisher email addresses** for the contact-list CSV |

*Never modifies the tenant.*

### `Publish-IntuneRemediation` (read/write)

| Graph scope | Why it's needed |
|-------------|-----------------|
| `DeviceManagementConfiguration.ReadWrite.All` | Create/update remediations and create assignments |

> **Approval workflow:** If your tenant has **multiple administrative approval** enabled
> for remediation scripts, `POST`/`PATCH` calls return `412 Precondition Failed` (or `409`
> if a request is already pending). The toolkit detects this and reports it as
> **"Approval Required"** with the approval code — it is **not** a failure. Approve the
> change in **Intune Portal → Endpoint Security → Remediations → Approvals**.

---

## Usage

### Export remediations from Intune

```powershell
# Export all remediations to .\RemediationScripts
Export-IntuneRemediation

# Export to a custom location
Export-IntuneRemediation -OutputPath "C:\Backup\Remediations"
```

Outputs, per run:
- One folder per remediation (`detection.ps1`, `remediation.ps1`, `metadata.json`).
- `remediation-scripts-summary.csv` — full details: deployment status, signature
  enforcement, run schedule, assignments, publisher, version, dates, IDs.
- `publishers-contact-list.csv` — unique publishers and their resolved emails.

> These CSVs can contain admin/publisher email addresses and tenant IDs, so they are
> **git-ignored** in this repository (see `.gitignore`).

### Publish remediations to Intune

```powershell
# Create new remediations from every folder in a path
Publish-IntuneRemediation -Create -Path .\RemediationScripts

# Pick a folder graphically (single remediation folder or a parent of many)
Publish-IntuneRemediation -BrowseFolder -Create

# Update existing remediations (matched by the Id in metadata.json)
Publish-IntuneRemediation -BrowseFolder -UpdateExisting

# Update a specific folder with an approval justification
Publish-IntuneRemediation -FolderName "DeviceType-Inventory" -UpdateExisting `
    -ApprovalJustification "Security compliance update"

# Preview what would be pushed without contacting Intune
Publish-IntuneRemediation -UpdateExisting -WhatIf

# The Push- alias works too (backward compatible)
Push-IntuneRemediation -Create -Path .\RemediationScripts
```

**Create vs. update:**
- `-UpdateExisting` **with** an `Id` in `metadata.json` → `PATCH`es the existing object.
- `-Create` → always creates a new object and writes the returned `Id` back into
  `metadata.json` (creating a duplicate if an `Id` was already present — useful for cloning).
- Neither switch → creates new.

---

## Interactive Mode (menu / guided prompts)

Prefer menus over switches? Launch the TUI:

```powershell
Start-RemediationToolkit                 # full menu: Export / Publish / Help
Publish-IntuneRemediation -Menu          # jump straight to the Publish menu
```

Navigate with **↑/↓ arrows or number keys**, **Enter** to select, **Esc** to go back.
The Create and Update actions run with `-Interactive`, which you can also use directly:

- **Guided update** (`-UpdateExisting -Interactive`): connects to Intune, shows the
  **current live settings** (highlighted in red), and asks whether to keep them as-is or
  modify each one. Choosing *keep* updates only the detection/remediation script content;
  the existing settings are preserved exactly.

- **Guided create** (`-Create -Interactive`): prompts for every setting (Display Name,
  Description, Publisher, Run-as account, 32-bit, Enforce signature, Scope tags) plus an
  optional **assignment** (All devices / All users / a group by object Id) and a
  **run schedule** (Daily / Hourly / Once). On success it creates the script **and** its
  assignment in one step.

---

## Assignment block (optional in `metadata.json`)

Guided create writes an `Assignment` object into the folder's `metadata.json` so the
deployment is reproducible. You can also add it by hand for a non-interactive
create — when present, `-Create` assigns the script after creating it:

```json
{
  "DisplayName": "DeviceType-Inventory",
  "RunAsAccount": "system",
  "RunAs32Bit": false,
  "EnforceSignatureCheck": false,
  "RoleScopeTagIds": "0",
  "Assignment": {
    "Target": "Group",
    "GroupId": "11111111-2222-3333-4444-555555555555",
    "GroupName": "Intune-Users",
    "ScheduleType": "Daily",
    "Interval": 1,
    "StartTime": "01:00",
    "RunRemediation": true,
    "UseUtc": false
  }
}
```

| Field | Values | Notes |
|-------|--------|-------|
| `Target` | `AllDevices` / `AllUsers` / `Group` | Who the remediation is assigned to |
| `GroupId` | GUID | Required when `Target` is `Group` |
| `GroupName` | string | Optional, for reference only |
| `ScheduleType` | `Daily` / `Hourly` / `Once` | Run cadence |
| `Interval` | integer | Every N days (Daily) or N hours (Hourly) |
| `StartTime` | `HH:mm` | Daily/Once; sent to Graph as `HH:mm:ss` |
| `StartDate` | `YYYY-MM-DD` | Once only |
| `RunRemediation` | `true` / `false` | Run the remediation script (not just detection) |
| `UseUtc` | `true` / `false` | Interpret the time as UTC |

---

## Repository Layout

```
Remediation-Retrevial/
├─ module/
│  └─ IntuneRemediationToolkit/          # the PowerShell module (recommended)
│     ├─ IntuneRemediationToolkit.psd1   # manifest (version, author, RequiredModules)
│     ├─ IntuneRemediationToolkit.psm1   # loader
│     ├─ Public/                         # exported commands
│     ├─ Private/                        # internal helpers
│     └─ en-US/about_RemediationToolkit.help.txt
├─ Export-IntuneRemediations.ps1         # standalone script (original)
├─ Push-RemdiationsToIntune.ps1          # standalone script (original)
├─ Start-RemediationToolkit.ps1          # standalone TUI (original)
├─ RemediationScripts/                   # exported remediations (one folder each)
│  └─ <ScriptName>/
│     ├─ detection.ps1
│     ├─ remediation.ps1                 # optional
│     └─ metadata.json                   # settings + Intune Id (+ optional Assignment)
└─ .gitignore                            # keeps generated CSVs (emails/IDs) out of git
```

Each remediation lives in its own folder. `metadata.json` carries the settings and the
Intune `Id` that links the local copy back to the object in the tenant:

```json
{
  "DisplayName": "DeviceType-Inventory",
  "Description": "",
  "Publisher": "Mark Orr",
  "Version": "2",
  "RunAsAccount": "system",
  "EnforceSignatureCheck": false,
  "RunAs32Bit": false,
  "Id": "ab467d3f-1976-4774-8c2d-45d6bb7f2550",
  "CreatedDateTime": "2025-12-15T11:33:54.849834Z",
  "LastModifiedDateTime": "2025-12-15T11:37:31.298696Z",
  "RoleScopeTagIds": "0"
}
```

> **Note:** A blank or absent `Id` means "create". Exported folders can contain hardcoded
> secrets (function keys, Log Analytics keys) — review before committing to a public repo.

---

## Getting Help

```powershell
Show-RemediationToolkitHelp                              # full colorized reference
Show-RemediationToolkitHelp -Command Publish-IntuneRemediation   # one command in detail
Get-Help Publish-IntuneRemediation -Full                # native comment-based help
Get-Help about_RemediationToolkit                        # concept topic
Get-Command -Module IntuneRemediationToolkit             # list all commands
```

---

## Notes

- All Graph endpoints used are on the **`/beta`** profile for device health scripts, which
  is where the remediation (proactive remediation) APIs currently live.
- The request body is built so it never emits JSON `null` and always includes
  `roleScopeTagIds` — this avoids the Intune approval **completion** step failing on
  schema validation.
- Script content is stored as UTF-8 and base64-encoded when sent to Graph.
- The publish flow prompts **once** for an approval justification and reuses it for the
  whole batch.
