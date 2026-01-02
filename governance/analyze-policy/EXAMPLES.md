# analyze-policy: Ready-to-Use Examples

Copy, paste, and run. Update management group IDs and output paths for your environment.

## Example 1: Single Management Group Audit

```powershell
Connect-AzAccount
.\analyze-policy.ps1 -ParentMgId "contoso-root" -OutputCsv "C:\Reports\policies.csv"
Write-Host "Report saved to C:\Reports\policies.csv"
```

## Example 2: Multiple Root Organizations

```powershell
Connect-AzAccount
.\analyze-policy.ps1 -ParentMgId @("org-us", "org-eu") -OutputCsv "C:\Reports\org-policies.csv"
```

## Example 3: Include Subscription-Level Policies

```powershell
Connect-AzAccount
.\analyze-policy.ps1 -ParentMgId "enterprise-root" -OutputCsv "C:\Reports\detailed-policies.csv" -IncludeSubscriptions
```

## Example 4: Automated Weekly Report

```powershell
# Schedule via Task Scheduler or runbook
Connect-AzAccount -ServicePrincipal -Credential $cred -TenantId $tenantId
$reportPath = "\\fileserver\reports\Policy-$(Get-Date -f 'yyyy-MM-dd').csv"
.\analyze-policy.ps1 -ParentMgId "root-mg" -OutputCsv $reportPath
```

## Example 5: Filter Report After Export

```powershell
# Load CSV and filter
$policies = Import-Csv "C:\Reports\policies.csv"

# Show only Audit mode policies
$policies | Where-Object { $_.EnforcementMode -eq "Audit" }

# Show only policies with managed identities
$policies | Where-Object { $_.HasManagedIdentity -eq "Yes" }
```
