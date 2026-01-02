# Setup Instructions

Prerequisites for running Azure Scripts.

## System Requirements

- **PowerShell:** 5.0 or later
- **Operating System:** Windows, macOS, or Linux
- **Azure Access:** Active Azure subscription and user account with appropriate permissions

## Install PowerShell (if needed)

### Windows

PowerShell 5.0 comes with Windows 10/11. Check your version:

```powershell
$PSVersionTable.PSVersion
```

If needed, upgrade to PowerShell 7+ (recommended):
- Download from [PowerShell Releases](https://github.com/PowerShell/PowerShell/releases)
- Or use Windows Package Manager: `winget install Microsoft.PowerShell`

### macOS / Linux

Download PowerShell 7+ from [PowerShell Releases](https://github.com/PowerShell/PowerShell/releases)

## Install Azure PowerShell Modules

Each script documents its required modules in its README. Common modules:

```powershell
Install-Module Az.Accounts -Force -AllowClobber
Install-Module Az.Resources -Force -AllowClobber
Install-Module Az.Iam -Force -AllowClobber
```

**Note:** You may be prompted to trust the PowerShell Gallery. Answer `Y` or `A`.

## Authenticate to Azure

Before running any script, authenticate:

```powershell
Connect-AzAccount
```

This opens a browser window. Sign in with your Azure credentials.

### Service Principal Authentication (for automation)

```powershell
$credential = New-Object -TypeName System.Management.Automation.PSCredential `
  -ArgumentList "YOUR_APP_ID", (ConvertTo-SecureString "YOUR_SECRET" -AsPlainText -Force)

Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId "YOUR_TENANT_ID"
```

## Verify Setup

```powershell
Get-AzContext
```

You should see your subscription and account details. If not, re-run `Connect-AzAccount`.

## Permissions Required

Specific scripts require different permissions:

| Script | Required Permissions |
|--------|---------------------|
| analyze-policy | Policy Reader / Reader at Management Group scope |
| analyze-rbac | Reader access to RBAC/IAM; View PIM Assignments for PIM data |

Contact your Azure Administrator if you don't have required permissions.

## Troubleshooting

### Module Not Found Error

```powershell
# List installed modules
Get-Module -ListAvailable Az.*

# Install missing module
Install-Module Az.Resources -Force
```

### "Connect-AzAccount: No subscription found"

You need at least one Azure subscription. Check your account at [portal.azure.com](https://portal.azure.com).

### "Insufficient privileges" when running script

Verify your permissions with your Azure Administrator. Use `Get-AzContext` to see your current role.

### PowerShell ExecutionPolicy Error

```powershell
# Check current policy
Get-ExecutionPolicy

# Temporarily allow scripts for this session
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

---

**Next:** Choose a script from [home directory](../README.md) and get started!
