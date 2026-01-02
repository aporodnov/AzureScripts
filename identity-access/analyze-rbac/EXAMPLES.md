# analyze-rbac: Ready-to-Use Examples

Copy, paste, and run. Update management group IDs and output paths for your environment.

## Example 1: Management Group RBAC & PIM Audit

```powershell
Connect-AzAccount
.\analyze-rbac.ps1 -ParentMgId "contoso-root" -OutputCsv "C:\Reports\rbac-pim.csv"
Write-Host "Report saved to C:\Reports\rbac-pim.csv"
```

## Example 2: Multiple Root Organizations

```powershell
Connect-AzAccount
.\analyze-rbac.ps1 -ParentMgId @("org-us", "org-eu") -OutputCsv "C:\Reports\org-rbac.csv"
```

## Example 3: Include Subscription-Level Assignments

```powershell
Connect-AzAccount
.\analyze-rbac.ps1 -ParentMgId "enterprise-root" -OutputCsv "C:\Reports\detailed-rbac.csv" -IncludeSubscriptions
```

## Example 4: Full Inventory (Management Groups, Subscriptions, and Resource Groups)

```powershell
Connect-AzAccount
.\analyze-rbac.ps1 -ParentMgId "root-mg" -OutputCsv "C:\Reports\complete-rbac.csv" -IncludeSubscriptions -IncludeRG
```

## Example 5: RBAC Only (Exclude PIM)

```powershell
Connect-AzAccount
.\analyze-rbac.ps1 -ParentMgId "contoso-root" -OutputCsv "C:\Reports\rbac-permanent.csv" -IncludePIM:$false
```

## Example 6: Automated Weekly Report (Service Principal)

```powershell
# Schedule via Task Scheduler or runbook
Connect-AzAccount -ServicePrincipal -Credential $cred -TenantId $tenantId
$reportPath = "\\fileserver\reports\RBAC-$(Get-Date -f 'yyyy-MM-dd').csv"
.\analyze-rbac.ps1 -ParentMgId "root-mg" -OutputCsv $reportPath -IncludeSubscriptions
```

## Example 7: Find All Active PIM Assignments

```powershell
# Load report and filter
$rbac = Import-Csv "C:\Reports\rbac-pim.csv"

# Show only active PIM assignments
$rbac | Where-Object { $_.AssignmentType -eq "PIM Eligible" -and $_.State -eq "Active" }

# Show all assignments for a specific user
$rbac | Where-Object { $_.IdentityName -like "*john.doe*" }
```

## Example 8: Count Assignments by Role and Scope

```powershell
$rbac = Import-Csv "C:\Reports\rbac-pim.csv"

# Count by role
$rbac | Group-Object -Property RoleDefinition | Sort-Object Count -Descending

# Count by scope level
$rbac | Group-Object -Property ScopeLevel | Select-Object Name, Count

# Count by assignment type
$rbac | Group-Object -Property AssignmentType
```
