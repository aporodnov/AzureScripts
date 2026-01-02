# analyze-rbac: Full Parameter Guide

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
-OutputCsv "C:\Reports\rbac-audit-$(Get-Date -f 'yyyyMMdd').csv"
```

### `-IncludePIM` (Optional)
**Type:** Switch  
**Default:** `$true`  
**Description:** Include PIM eligible assignments in the report. Set to false to analyze RBAC only.

```powershell
-IncludePIM:$false
```

### `-IncludeSubscriptions` (Optional)
**Type:** Switch  
**Default:** `$false`  
**Description:** Include subscription-level RBAC assignments in the report.

```powershell
-IncludeSubscriptions
```

### `-IncludeRG` (Optional)
**Type:** Switch  
**Default:** `$false`  
**Description:** Include resource group-level RBAC assignments. Requires `-IncludeSubscriptions` to be enabled.

```powershell
-IncludeSubscriptions -IncludeRG
```

## Full Syntax

```powershell
.\analyze-rbac.ps1 -ParentMgId <String[]> -OutputCsv <String> [-IncludePIM] [-IncludeSubscriptions] [-IncludeRG]
```

## Output Columns

| Column | Description |
|--------|-------------|
| RootManagementGroup | Top-level management group |
| ManagementGroup | Current management group (if applicable) |
| SubscriptionId | Subscription ID (if applicable) |
| ResourceGroupName | Resource group name (if applicable) |
| ScopeLevel | Scope level: ManagementGroup, Subscription, ResourceGroup, Resource |
| AssignmentType | Permanent or PIM Eligible |
| IdentityName | User, group, or service principal name |
| IdentityType | User, Group, ServicePrincipal, ManagedIdentity |
| IdentityObjectId | Azure AD object ID |
| RoleDefinition | Role name (e.g., Owner, Contributor, Reader) |
| RoleDefinitionId | Role definition unique identifier |
| Scope | Direct or Inherited assignment |
| State | Active, Expired, or NotYetActive (PIM only) |
| StartDateTime | Assignment start date (PIM only) |
| EndDateTime | Assignment end date (PIM only) |
| Status | Current assignment status |
| PrincipalEmail | Email address if available |
| CreatedOn | Creation date of assignment |
