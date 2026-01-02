# analyze-policy: Full Parameter Guide

## Parameters

### `-ParentMgId` (Required)
**Type:** String or String[]  
**Description:** Management group ID(s) to start scanning from (recursive). Supports single or multiple root management groups.

```powershell
# Single management group
-ParentMgId "contoso-root"

# Multiple management groups (array)
-ParentMgId @("org-root", "it-division")
```

### `-OutputCsv` (Required)
**Type:** String  
**Description:** Full file path where the CSV report will be saved.

```powershell
-OutputCsv "C:\Reports\policy-audit-$(Get-Date -f 'yyyyMMdd').csv"
```

### `-IncludeSubscriptions` (Optional)
**Type:** Switch  
**Default:** `$false`  
**Description:** Include subscription-level policy assignments in the report.

```powershell
-IncludeSubscriptions
```

## Full Syntax

```powershell
.\analyze-policy.ps1 -ParentMgId <String[]> -OutputCsv <String> [-IncludeSubscriptions]
```

## Output Columns

| Column | Description |
|--------|-------------|
| Scope | Policy assignment scope level |
| ScopeName | Name of the scope (MG or subscription) |
| ScopeDisplayName | Display name from Azure |
| AssignmentName | Policy assignment technical name |
| AssignmentDisplayName | User-friendly assignment name |
| EnforcementMode | Enforced or Audit mode |
| Inherited | Direct or Inherited assignment |
| HasManagedIdentity | Yes/No |
| ManagedIdentityId | Resource ID if present |
| IdentityType | System Assigned or User Assigned |
